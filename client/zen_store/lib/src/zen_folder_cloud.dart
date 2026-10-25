import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:zen_core/zen_core.dart';

import 'zen_storage_error.dart';
import 'zen_store.dart';
import 'zen_store_log.dart';
import 'zen_sync_transport.dart';

/// A stand-in for CloudKit in a folder on disk, for developing and testing a light application
/// without a paid Apple Developer Program membership (ADR-065).
///
/// It keeps what CloudKit keeps — one record per store record, each with a change tag, and a
/// sequence that fetches resume from — and refuses a save whose tag is stale the way CloudKit does,
/// handing back the server's copy to merge. So the store meets the same situations under it as
/// under `zen_store_cloudkit`. Every device, or process, pointed at one folder syncs with the
/// others; a file lock keeps two of them from interleaving.
///
/// **Development only.** Payloads are stored as they are — not encrypted end to end, as CloudKit's
/// encrypted fields are — and nothing is uploaded anywhere. An iOS Simulator app runs as a process
/// on the Mac and can reach the Mac's files, so a macOS build and a simulator build given the same
/// folder sync as two devices. Choose it at compile time, never at runtime:
///
/// ```dart
/// const sync = String.fromEnvironment('ZEN_SYNC'); // 'folder' in development, 'cloudkit' in release
/// ```
final class ZenFolderCloud implements ZenSyncTransport {
  final ZenStore _store;
  final Directory _folder;
  final StreamController<ZenSyncStatus> _statusChanges =
      StreamController<ZenSyncStatus>.broadcast();
  StreamSubscription<Set<String>>? _unsentChanges;
  Timer? _poll;
  ZenSyncStatus _status = ZenSyncStatus.off;
  Future<void> _running = Future<void>.value();
  bool _stopped = false;

  ZenFolderCloud._(this._store, this._folder);

  /// Starts syncing [store] through [folder]: whenever a record becomes unsent, and every
  /// [pollEvery] to pick up other devices' changes (null: only on [syncNow], as a test wants).
  static Future<ZenResult<ZenFolderCloud>> start(
    ZenStore store,
    Directory folder, {
    Duration? pollEvery = const Duration(seconds: 2),
  }) async {
    try {
      await Directory(_join(folder.path, 'records')).create(recursive: true);
    } on FileSystemException catch (e, stack) {
      return ZenResult.err(
        ZenStorageError('Cannot use ${folder.path} as a sync folder: $e', stackTrace: stack),
      );
    }
    final cloud = ZenFolderCloud._(store, folder);
    cloud._unsentChanges = store.unsentChanges.listen((_) => unawaited(cloud.syncNow()));
    if (pollEvery != null) {
      cloud._poll = Timer.periodic(pollEvery, (_) => unawaited(cloud.syncNow()));
    }
    unawaited(cloud.syncNow());
    return ZenResult.ok(cloud);
  }

  @override
  ZenSyncStatus get status => _status;

  @override
  Stream<ZenSyncStatus> get statusChanges => _statusChanges.stream;

  @override
  Future<void> syncNow() {
    if (_stopped) return Future.value();
    final run = _running.then((_) => _syncOnce());
    _running = run.catchError((Object _) {});
    return run;
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _poll?.cancel();
    await _unsentChanges?.cancel();
    await _running;
    _setStatus(ZenSyncStatus.off);
    await _statusChanges.close();
  }

  Future<void> _syncOnce() async {
    if (_stopped) return;
    _setStatus(const ZenSyncStatus(ZenSyncState.syncing));
    final lock = await File(_join(_folder.path, 'lock')).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      final problems = <String>[];
      // Fetch first, as CKSyncEngine does: what others saved since this device last looked.
      problems.addAll(await _fetch());
      // Then send. A stale tag is refused with the server's copy, which the store merges; the
      // record stays unsent and goes on the next pass, now holding both sides.
      for (var pass = 0; pass < 3 && _store.unsent.isNotEmpty; pass++) {
        problems.addAll(await _send());
      }
      _setStatus(
        problems.isEmpty
            ? const ZenSyncStatus(ZenSyncState.upToDate)
            : ZenSyncStatus(
                ZenSyncState.unavailable,
                issue: ZenSyncIssue.unreadableRecords,
                message: problems.join('; '),
              ),
      );
    } on Object catch (e) {
      _setStatus(ZenSyncStatus(ZenSyncState.unavailable, issue: ZenSyncIssue.other, message: '$e'));
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }

  Future<List<String>> _fetch() async {
    final since = _token(_store.transportState);
    final changed = <_CloudRecord>[];
    var latest = since;
    await for (final entity in Directory(_join(_folder.path, 'records')).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final record = _CloudRecord.decode(await entity.readAsBytes());
      if (record.sequence > since) changed.add(record);
      if (record.sequence > latest) latest = record.sequence;
    }
    if (changed.isEmpty) return const [];
    final report = await _store.receive([
      for (final record in changed)
        ZenIncomingRecord(record.name, record.payload, _tag(record.tag)),
    ]);
    final problems = switch (report) {
      ZenSuccess(:final data) => [for (final problem in data.problems) '$problem'],
      ZenFailure(:final error) => throw StateError(error.message),
    };
    await _store.saveTransportState(_tokenBytes(latest));
    return problems;
  }

  Future<List<String>> _send() async {
    final saved = <ZenAcknowledgedRecord>[];
    final refused = <ZenIncomingRecord>[];
    for (final name in _store.unsent) {
      final outgoing = _store.outgoing(name);
      if (outgoing == null) continue;
      final file = File(_join(_join(_folder.path, 'records'), '${_fileName(name)}.json'));
      final server = await file.exists() ? _CloudRecord.decode(await file.readAsBytes()) : null;
      final ourTag = outgoing.transportData == null ? null : _tagOf(outgoing.transportData!);
      if (server != null && server.tag != ourTag) {
        refused.add(ZenIncomingRecord(name, server.payload, _tag(server.tag)));
        continue;
      }
      final next = _CloudRecord(
        name,
        (server?.tag ?? 0) + 1,
        await _nextSequence(),
        outgoing.payload,
      );
      await writeAtomically(file, next.encode());
      saved.add(ZenAcknowledgedRecord(name, outgoing.payload, _tag(next.tag)));
    }
    final problems = <String>[];
    if (saved.isNotEmpty) {
      if (await _store.acknowledge(saved) case ZenFailure(:final error)) {
        throw StateError(error.message);
      }
    }
    if (refused.isNotEmpty) {
      switch (await _store.receive(refused)) {
        case ZenSuccess(:final data):
          problems.addAll([for (final problem in data.problems) '$problem']);
        case ZenFailure(:final error):
          throw StateError(error.message);
      }
    }
    return problems;
  }

  Future<int> _nextSequence() async {
    final file = File(_join(_folder.path, 'sequence'));
    final current = await file.exists() ? int.parse((await file.readAsString()).trim()) : 0;
    await writeAtomically(file, utf8.encode('${current + 1}'));
    return current + 1;
  }

  void _setStatus(ZenSyncStatus status) {
    if (status == _status || _statusChanges.isClosed) return;
    _status = status;
    _statusChanges.add(status);
  }

  static int _token(Uint8List? state) => state == null ? 0 : int.parse(utf8.decode(state));
  static Uint8List _tokenBytes(int sequence) => utf8.encode('$sequence');
  static Uint8List _tag(int tag) => utf8.encode('$tag');
  static int _tagOf(Uint8List data) => int.parse(utf8.decode(data));
  static String _fileName(String name) => base64Url.encode(utf8.encode(name));
  static String _join(String directory, String name) => '$directory${Platform.pathSeparator}$name';
}

/// One record as the folder holds it, the shape of a CloudKit record: name, change tag, the
/// sequence number of its last save, and the payload.
final class _CloudRecord {
  final String name;
  final int tag;
  final int sequence;
  final Uint8List payload;

  _CloudRecord(this.name, this.tag, this.sequence, this.payload);

  Uint8List encode() => utf8.encode(
    jsonEncode({'name': name, 'tag': tag, 'sequence': sequence, 'payload': base64Encode(payload)}),
  );

  static _CloudRecord decode(List<int> bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    return _CloudRecord(
      json['name']! as String,
      json['tag']! as int,
      json['sequence']! as int,
      base64Decode(json['payload']! as String),
    );
  }
}
