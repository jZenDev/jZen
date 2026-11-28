import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// **A change the store cannot write is kept** (ADR-088). The engine's change token moves past
/// whatever it has delivered, so everything it hands over is written in the order it arrived, and
/// its state only after all before it. While a write fails (a full disk, a locked phone under Data
/// Protection) the change waits here with what followed, [status] says so, and it is tried again
/// every few seconds, at [syncNow] and at a local write. An app that stops before then, or has
/// more waiting than is kept (16 MiB of records), starts from the old state, from which CloudKit
/// should deliver the change again; that, like the rest of the engine's behaviour, has not been
/// run against real CloudKit. A record this version of the app cannot read holds the state back
/// the same way, until it has been read.
///
/// It needs the CloudKit capability and a container in the app's entitlements, which need a paid
/// Apple Developer Program membership. Until then, develop against [ZenFolderCloud], chosen at
/// compile time.
final class ZenCloudKitSync implements ZenSyncTransport {
  static const MethodChannel _channel = MethodChannel('zen_store_cloudkit');

  final ZenStore _store;
  final Duration? _retryEvery;
  final StreamController<ZenSyncStatus> _statusChanges =
      StreamController<ZenSyncStatus>.broadcast();
  StreamSubscription<Set<String>>? _unsent;
  StreamSubscription<void>? _erasures;
  ZenSyncStatus _status = ZenSyncStatus.off;

  /// What the engine, or this class, last said about syncing with iCloud.
  ZenSyncStatus _reported = ZenSyncStatus.off;

  /// The engine's changes the store has not taken yet, oldest first.
  final Queue<_Delivery> _waiting = Queue<_Delivery>();

  /// The delivered records the store could not read, by name, and why.
  final Map<String, String> _unreadable = {};

  Future<void> _writing = Future<void>.value();
  String? _writeFailure;
  Timer? _retry;
  bool _stopped = false;

  /// Whether the store is erased on disk. Its own `erasedEverywhere` is already true while an
  /// erase is being written, and is taken back if that write fails.
  bool _erased;

  ZenCloudKitSync._(this._store, this._retryEvery) : _erased = _store.erasedEverywhere;

  /// The most payload bytes that wait for a store that cannot write. A change that would pass it
  /// is not taken, and CloudKit is left to deliver it again.
  @visibleForTesting
  static const int waitingBytesLimit = 16 * 1024 * 1024;

  /// How many changes wait to be written.
  @visibleForTesting
  int get waitingChanges => _waiting.length;

  /// Starts syncing [store] through the CloudKit container [containerId] (the app's default
  /// container when null), in the record zone [zone]. A change the store could not write is tried
  /// again every [retryEvery] (null: only at [syncNow] and at a local write, as a test wants).
  ///
  /// Fails with a [ZenNotFoundError] on a platform that is not iOS or macOS. A missing iCloud
  /// account is not a failure here: sync starts, and [status] says why it is waiting.
  static Future<ZenResult<ZenCloudKitSync>> start(
    ZenStore store, {
    String? containerId,
    String zone = 'zen_store',
    Duration? retryEvery = const Duration(seconds: 5),
  }) async {
    // An erase still being written already reports the store erased, and is taken back if it
    // fails. A merge of nothing takes its turn after it, so what is read next is on disk.
    if (store.erasedEverywhere) await store.receive(const []);
    final sync = ZenCloudKitSync._(store, retryEvery);
    _channel.setMethodCallHandler(sync._handle);
    sync._erasures = store.erasures.listen((_) {
      sync._noteErased();
      sync._write();
    });
    try {
      await _channel.invokeMethod<void>('start', {
        'containerId': containerId,
        'zone': zone,
        'state': store.transportState,
      });
    } on MissingPluginException {
      _channel.setMethodCallHandler(null);
      await sync._erasures?.cancel();
      return const ZenResult.err(
        ZenNotFoundError('CloudKit sync is available only on iOS and macOS.'),
      );
    } on PlatformException catch (e, stack) {
      _channel.setMethodCallHandler(null);
      await sync._erasures?.cancel();
      return ZenResult.err(
        ZenUnknownError('CloudKit sync could not start: ${e.message}', stackTrace: stack),
      );
    }
    sync._unsent = store.unsentChanges.listen((names) {
      sync._changed(names);
      // A local write just succeeded, so what is waiting may now be written too.
      sync._write();
    });
    await sync._changed(store.unsent);
    if (sync._erased) {
      // Erased, and the app stopped before iCloud was cleaned: finish it now.
      await sync._eraseInCloud();
    }
    return ZenResult.ok(sync);
  }

  @override
  ZenSyncStatus get status => _status;

  @override
  Stream<ZenSyncStatus> get statusChanges => _statusChanges.stream;

  @override
  Future<void> syncNow() async {
    await _write();
    try {
      await _channel.invokeMethod<void>('syncNow');
    } on PlatformException catch (e) {
      _report(
        ZenSyncStatus(ZenSyncState.unavailable, issue: ZenSyncIssue.other, message: e.message),
      );
    }
  }

  /// Erases the person's data on every device, here and in iCloud (ADR-085).
  ///
  /// The store is erased and marked so (`ZenStore.eraseEverywhere`); iCloud gets a marker record
  /// in a zone of its own and the data zone is deleted. Each other device finds the marker at its
  /// next sync, or at start if it was off, erases its own copy and does not make the zone again.
  /// **What stays in iCloud** is that marker zone, one record holding no data, so a device that was
  /// off can still tell an erase from a deletion in Settings.
  ///
  /// Fails with the cause when iCloud cannot be reached, after the store was erased: the iCloud
  /// part is repeated at every start, so "not yet", never "not erased". CloudKit is end-to-end
  /// encrypted, so this removes what Apple holds; a device that has not synced keeps its own copy
  /// until it does, as with every transport.
  Future<ZenResult<void>> eraseEverywhere() async {
    if (await _store.eraseEverywhere() case ZenFailure(:final error)) return ZenResult.err(error);
    _noteErased();
    await _write();
    return _eraseInCloud();
  }

  Future<ZenResult<void>> _eraseInCloud() async {
    try {
      await _channel.invokeMethod<void>('eraseEverywhere');
    } on PlatformException catch (e, stack) {
      _report(
        ZenSyncStatus(ZenSyncState.unavailable, issue: ZenSyncIssue.other, message: e.message),
      );
      return ZenResult.err(
        ZenUnknownError(
          'The store was erased here, but iCloud was not cleaned: ${e.message}. It is retried at '
          'the next start.',
          stackTrace: stack,
        ),
      );
    }
    _report(_erasedStatus);
    return const ZenResult.ok(null);
  }

  static const ZenSyncStatus _erasedStatus = ZenSyncStatus(
    ZenSyncState.unavailable,
    issue: ZenSyncIssue.erasedEverywhere,
    message: 'the store was erased everywhere',
  );

  @override
  Future<void> stop() async {
    // What is still waiting stays unwritten, and so does the state past it.
    _stopped = true;
    _retry?.cancel();
    await _unsent?.cancel();
    await _erasures?.cancel();
    await _writing;
    await _channel.invokeMethod<void>('stop');
    _channel.setMethodCallHandler(null);
    _waiting.clear();
    _unreadable.clear();
    _writeFailure = null;
    _report(ZenSyncStatus.off);
    await _statusChanges.close();
  }

  Future<void> _changed(Set<String> names) async {
    if (names.isEmpty) return;
    await _channel.invokeMethod<void>('changed', {'names': names.toList()});
  }

  /// What the Swift side asks of the store.
  ///
  /// A change to the store is answered `true` once this class has taken it: it is on disk, or it
  /// is waiting here and no later engine state will be saved before it. It is answered `false`
  /// when too much is waiting already. The Swift side stops saving engine state on any answer but
  /// `true`, an error among them.
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
        final incoming = [
          for (final raw in _records(arguments)) ZenIncomingRecord(raw.$1, raw.$2, raw.$3),
        ];
        final refused = call.method == 'refused';
        return _take(
          _Delivery(
            () => _receive(incoming, refused: refused),
            bytes: incoming.fold(
              0,
              (sum, record) => sum + record.payload.length + (record.transportData?.length ?? 0),
            ),
          ),
        );
      case 'saved':
        final saved = [
          for (final raw in _records(arguments)) ZenAcknowledgedRecord(raw.$1, raw.$2, raw.$3),
        ];
        return _take(
          _Delivery(
            () => _store.acknowledge(saved),
            bytes: saved.fold(
              0,
              (sum, record) => sum + record.payload.length + (record.transportData?.length ?? 0),
            ),
          ),
        );
      case 'state':
        final state = arguments['state'] as Uint8List?;
        return _take(_Delivery(() => _saveState(state), isEngineState: true));
      case 'erased':
        // Another device erased everything (its marker is in iCloud): erase this copy too. What
        // is waiting would be erased with it, so the erase does not wait behind it.
        _waiting.clear();
        return _take(_Delivery(_eraseHere));
      case 'resetCloud':
        return _take(_Delivery(_forgetCloud));
      case 'status':
        _report(_statusFrom(arguments));
        return null;
      default:
        throw MissingPluginException('zen_store_cloudkit has no method ${call.method}');
    }
  }

  Future<bool> _take(_Delivery delivery) async {
    // Only while writes fail does anything pile up. A change that carries no payload, an erase
    // among them, always has room.
    bool noRoom() =>
        _writeFailure != null &&
        delivery.bytes > 0 &&
        _waiting.fold(delivery.bytes, (sum, other) => sum + other.bytes) > waitingBytesLimit;
    if (noRoom()) {
      // The store may have recovered since the last attempt.
      await _write();
      if (noRoom()) return false;
    }
    // A newer engine state covers everything an older one does, and is written after more.
    if (delivery.isEngineState) _waiting.removeWhere((other) => other.isEngineState);
    _waiting.add(delivery);
    await _write();
    return true;
  }

  /// Writes what is waiting, after any write already running.
  Future<void> _write() => _writing = _writing.then((_) => _writeWaiting());

  /// Writes the waiting changes in order, stopping at the first the store cannot take.
  Future<void> _writeWaiting() async {
    while (!_stopped && _waiting.isNotEmpty) {
      final next = _waiting.first;
      ZenResult<void> result;
      try {
        result = await next.write();
      } on Object catch (e, stack) {
        result = ZenResult.err(
          ZenUnknownError('Cannot save synced changes: $e', stackTrace: stack),
        );
      }
      // An erase, or a newer engine state, may have taken its place while it was being written.
      if (!identical(_waiting.firstOrNull, next)) continue;
      if (result case ZenFailure(:final error)) {
        _writeFailure = error.message;
        if (_retryEvery case final every? when !_stopped) {
          _retry ??= Timer.periodic(every, (_) => _write());
        }
        _publish();
        return;
      }
      _waiting.removeFirst();
    }
    if (_stopped) return;
    _writeFailure = null;
    _retry?.cancel();
    _retry = null;
    _publish();
  }

  Future<ZenResult<void>> _receive(
    List<ZenIncomingRecord> incoming, {
    required bool refused,
  }) async {
    // A store erased everywhere takes no record ever again: there is nothing to wait for.
    if (_erased) return const ZenResult.ok(null);
    switch (await _store.receive(incoming)) {
      case ZenFailure(:final error):
        return ZenResult.err(error);
      case ZenSuccess(:final data):
        final problems = {for (final problem in data.problems) problem.record: '$problem'};
        for (final record in incoming) {
          if (problems[record.name] case final problem?) {
            _unreadable[record.name] = problem;
          } else {
            _unreadable.remove(record.name);
          }
        }
        if (refused) {
          // The engine does not send a refused save again by itself, and a record that was
          // already unsent is announced by nothing else. One that cannot be read here is left:
          // its next save would be refused with the same copy.
          _changed(
            {
              for (final record in incoming)
                if (!problems.containsKey(record.name)) record.name,
            }.intersection(_store.unsent),
          );
        }
        return const ZenResult.ok(null);
    }
  }

  Future<ZenResult<void>> _saveState(Uint8List? state) async {
    // The state is past every record the engine has delivered, the unreadable ones too. Dropping
    // it is enough: the engine sends a newer one after its next change.
    if (_unreadable.isNotEmpty) return const ZenResult.ok(null);
    return _store.saveTransportState(state);
  }

  Future<ZenResult<void>> _eraseHere() async {
    if (await _store.eraseEverywhere() case ZenFailure(:final error)) return ZenResult.err(error);
    _noteErased();
    _reported = _erasedStatus;
    return const ZenResult.ok(null);
  }

  /// An erased store takes nothing more, and nothing that was waiting has a place in it.
  void _noteErased() {
    _erased = true;
    _waiting.clear();
    _unreadable.clear();
  }

  Future<ZenResult<void>> _forgetCloud() async {
    if (await _store.forgetTransport() case ZenFailure(:final error)) return ZenResult.err(error);
    // The copy in iCloud they came from is gone.
    _unreadable.clear();
    return const ZenResult.ok(null);
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

  void _report(ZenSyncStatus status) {
    _reported = status;
    _publish();
  }

  /// Sets what the app sees. A change the store has not written, or cannot read, outlasts
  /// whatever the engine says about its own progress until it is resolved.
  void _publish() {
    final ZenSyncStatus status;
    if (_writeFailure case final message?) {
      status = ZenSyncStatus(ZenSyncState.unavailable, issue: ZenSyncIssue.other, message: message);
    } else if (_unreadable.isNotEmpty && _reported.state != ZenSyncState.unavailable) {
      status = ZenSyncStatus(
        ZenSyncState.unavailable,
        issue: ZenSyncIssue.unreadableRecords,
        message: _unreadable.values.join('; '),
      );
    } else {
      status = _reported;
    }
    if (status == _status || _statusChanges.isClosed) return;
    _status = status;
    _statusChanges.add(status);
  }
}

/// A change from the engine on its way into the store.
final class _Delivery {
  final Future<ZenResult<void>> Function() write;

  /// Whether it is the engine's own state, which a newer one replaces.
  final bool isEngineState;

  /// The record bytes it holds while it waits.
  final int bytes;

  _Delivery(this.write, {this.isEngineState = false, this.bytes = 0});
}
