import 'dart:async';

import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

/// Syncs a [ZenStore] through CloudKit: `CKSyncEngine` against the user's private database, each
/// record end-to-end encrypted with CloudKit `encryptedValues` (ADR-065).
///
/// The store stays the source of truth and the merge stays the store's; the engine owns the loop.
/// A local write is handed to the engine at once; other devices' changes arrive by push. A save the
/// server refuses because another device saved first is merged by the store and sent again.
///
/// It needs the CloudKit capability and a container in the app's entitlements, which need a paid
/// Apple Developer Program membership. Until then, develop against [ZenFolderCloud], chosen at
/// compile time.
final class ZenCloudKitSync implements ZenSyncTransport {
  static const MethodChannel _channel = MethodChannel('zen_store_cloudkit');

  final ZenStore _store;
  final StreamController<ZenSyncStatus> _statusChanges =
      StreamController<ZenSyncStatus>.broadcast();
  StreamSubscription<Set<String>>? _unsent;
  ZenSyncStatus _status = ZenSyncStatus.off;

  ZenCloudKitSync._(this._store);

  /// Starts syncing [store] through the CloudKit container [containerId] (the app's default
  /// container when null), in the record zone [zone].
  ///
  /// Fails with a [ZenNotFoundError] on a platform that is not iOS or macOS. A missing iCloud
  /// account is not a failure here: sync starts, and [status] says why it is waiting.
  static Future<ZenResult<ZenCloudKitSync>> start(
    ZenStore store, {
    String? containerId,
    String zone = 'zen_store',
  }) async {
    final sync = ZenCloudKitSync._(store);
    _channel.setMethodCallHandler(sync._handle);
    try {
      await _channel.invokeMethod<void>('start', {
        'containerId': containerId,
        'zone': zone,
        'state': store.transportState,
      });
    } on MissingPluginException {
      _channel.setMethodCallHandler(null);
      return const ZenResult.err(
        ZenNotFoundError('CloudKit sync is available only on iOS and macOS.'),
      );
    } on PlatformException catch (e, stack) {
      _channel.setMethodCallHandler(null);
      return ZenResult.err(
        ZenUnknownError('CloudKit sync could not start: ${e.message}', stackTrace: stack),
      );
    }
    sync._unsent = store.unsentChanges.listen((names) => sync._changed(names));
    await sync._changed(store.unsent);
    return ZenResult.ok(sync);
  }

  @override
  ZenSyncStatus get status => _status;

  @override
  Stream<ZenSyncStatus> get statusChanges => _statusChanges.stream;

  @override
  Future<void> syncNow() async {
    try {
      await _channel.invokeMethod<void>('syncNow');
    } on PlatformException catch (e) {
      _setStatus(
        ZenSyncStatus(ZenSyncState.unavailable, issue: ZenSyncIssue.other, message: e.message),
      );
    }
  }

  @override
  Future<void> stop() async {
    await _unsent?.cancel();
    await _channel.invokeMethod<void>('stop');
    _channel.setMethodCallHandler(null);
    _setStatus(ZenSyncStatus.off);
    await _statusChanges.close();
  }

  Future<void> _changed(Set<String> names) async {
    if (names.isEmpty) return;
    await _channel.invokeMethod<void>('changed', {'names': names.toList()});
  }

  /// What the Swift side asks of the store. Each reply is awaited there before the engine moves on,
  /// so every write below is on disk before CloudKit's change token advances past it.
  Future<Object?> _handle(MethodCall call) async {
    final arguments = (call.arguments as Map<Object?, Object?>?) ?? const {};
    switch (call.method) {
      case 'outgoing':
        return [
          for (final name in (arguments['names'] as List<Object?>? ?? const []).cast<String>())
            if (_store.outgoing(name) case final record?)
              {'name': record.name, 'payload': record.payload, 'system': ?record.transportData},
        ];
      case 'fetched':
      case 'refused':
        final report = await _store.receive([
          for (final raw in _records(arguments)) ZenIncomingRecord(raw.$1, raw.$2, raw.$3),
        ]);
        switch (report) {
          case ZenSuccess(:final data) when data.problems.isNotEmpty:
            _setStatus(
              ZenSyncStatus(
                ZenSyncState.unavailable,
                issue: ZenSyncIssue.unreadableRecords,
                message: data.problems.join('; '),
              ),
            );
          case ZenFailure(:final error):
            _setStatus(
              ZenSyncStatus(
                ZenSyncState.unavailable,
                issue: ZenSyncIssue.other,
                message: error.message,
              ),
            );
          case ZenSuccess():
            break;
        }
        return null;
      case 'saved':
        await _store.acknowledge([
          for (final raw in _records(arguments)) ZenAcknowledgedRecord(raw.$1, raw.$2, raw.$3),
        ]);
        return null;
      case 'state':
        await _store.saveTransportState(arguments['state'] as Uint8List?);
        return null;
      case 'resetCloud':
        await _store.forgetTransport();
        return null;
      case 'status':
        _setStatus(_statusFrom(arguments));
        return null;
      default:
        throw MissingPluginException('zen_store_cloudkit has no method ${call.method}');
    }
  }

  static Iterable<(String, Uint8List, Uint8List?)> _records(Map<Object?, Object?> arguments) sync* {
    for (final raw
        in (arguments['records'] as List<Object?>? ?? const []).cast<Map<Object?, Object?>>()) {
      yield (raw['name']! as String, raw['payload']! as Uint8List, raw['system'] as Uint8List?);
    }
  }

  static ZenSyncStatus _statusFrom(Map<Object?, Object?> arguments) {
    final state = ZenSyncState.values.asNameMap()[arguments['state']] ?? ZenSyncState.unavailable;
    final issue = arguments['issue'] == null
        ? null
        : ZenSyncIssue.values.asNameMap()[arguments['issue']] ?? ZenSyncIssue.other;
    return ZenSyncStatus(state, issue: issue, message: arguments['message'] as String?);
  }

  void _setStatus(ZenSyncStatus status) {
    if (status == _status || _statusChanges.isClosed) return;
    _status = status;
    _statusChanges.add(status);
  }
}
