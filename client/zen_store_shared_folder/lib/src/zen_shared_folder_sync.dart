import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'zen_folder_access.dart';
import 'zen_shared_folder_cipher.dart';

/// Sync for a jZen Local application through a folder that a sync service of the person's own
/// (Syncthing, Dropbox, OneDrive, Nextcloud, ...) keeps in step between their devices (ADR-076).
///
/// ```
/// <folder>/<key id>/<device id>/<64 hex>.zen   one file per record, written by that device only
/// <folder>/<key id>/<device id>/erased.zen     that device saw the store erased everywhere
/// <folder>/<key id>/rekeyed.zen                the sync key was replaced; stop writing here
/// ```
///
/// **The key id** is 32 hex characters derived from the sync key, so a device holding another key
/// (a removed device, once the key is replaced) works in a directory nobody else reads: what it
/// writes afterwards is not decrypted, not reported, not even looked at (ADR-085).
///
/// **One writer per file.** A device writes only inside its own directory and only reads the
/// others', so the folder never holds a file two devices changed - which is what a sync service
/// cannot cope with, and the reason it makes "conflicted copies". Every file is a record's whole
/// state, so combining devices is `ZenStore.receive`'s per-field merge, and a real conflict still
/// goes to the person. A file that arrives late, twice, out of order or stale merges to the same
/// result; none of this transport's code decides which edit wins.
///
/// **Encrypted.** Each file is sealed with a key derived from the shared sync key, its path bound
/// in as associated data, and is named by an HMAC of the record's name. The folder exposes the
/// number of devices, how many records each holds, their sizes and when they changed - never a
/// record, a name or an id.
///
/// **Bad files are skipped, never merged and never fatal.** A half-delivered, damaged, foreign-key,
/// moved or newer-format file is left alone, named in [ZenSyncReport.problems], and read again on
/// the next pass, when the sync service may have finished. A name that is not exactly 64 hex
/// characters and `.zen` - every sync service's "conflicted copy" - is ignored.
///
/// There is no network code: the folder is the only thing this reads or writes. Changes are found
/// by polling, brought forward by the folder's watcher where the platform has one.
final class ZenSharedFolderSync implements ZenSyncTransport {
  static final RegExp _deviceDirectory = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _recordFile = RegExp(r'^[0-9a-f]{64}\.zen$');
  static const String _erasedFile = 'erased.zen';
  static const String _rekeyedFile = 'rekeyed.zen';
  static final Uint8List _publishedMarker = Uint8List.fromList(utf8.encode('published:1'));

  final ZenStore _store;
  final ZenFolderAccess _access;
  ZenSharedFolderCipher? _cipher;
  final Duration _watchDebounce;
  final StreamController<ZenSyncStatus> _statusChanges =
      StreamController<ZenSyncStatus>.broadcast();
  final StreamController<ZenSyncReport> _reports = StreamController<ZenSyncReport>.broadcast();
  // path -> "<size>:<modified>" of the version already merged, so an unchanged file is not read
  // again. A file that failed is never recorded, which is what makes it retried.
  final Map<String, String> _merged = {};
  // Records merged from another device's file since this device last made sure its own directory
  // holds them (see _send).
  final Set<String> _toMirror = {};
  StreamSubscription<Set<String>>? _unsentChanges;
  StreamSubscription<void>? _watcher;
  Timer? _poll;
  Timer? _debounce;
  ZenSyncStatus _status = ZenSyncStatus.off;
  ZenSyncReport? _lastReport;
  Future<void> _running = Future<void>.value();
  bool _stopped = false;
  // Set when this device sent everything again because its directory was gone, cleared once the
  // directory is seen to exist. Stops a folder that never shows our files from being refilled on
  // every pass.
  bool _republishing = false;
  // The cipher a replaced key leaves behind until its folder directory has been cleaned.
  ZenSharedFolderCipher? _retiring;

  ZenSharedFolderSync._(this._store, this._access, this._cipher, this._watchDebounce);

  /// Starts syncing [store] through [access].
  ///
  /// [syncKey] is the 32-byte key every paired device shares, or null on a device that has not
  /// been paired: the transport then reports [ZenSyncIssue.notPaired] and touches nothing. Start a
  /// new transport once pairing has given it the key.
  ///
  /// Changes are found every [pollEvery] (null: only on [syncNow], as a test wants) and, when
  /// [watch] is set and the platform has a watcher, within [watchDebounce] of the folder changing.
  static Future<ZenResult<ZenSharedFolderSync>> start(
    ZenStore store,
    ZenFolderAccess access, {
    required List<int>? syncKey,
    Duration? pollEvery = const Duration(seconds: 15),
    bool watch = true,
    Duration watchDebounce = const Duration(milliseconds: 500),
  }) async {
    if (syncKey != null && syncKey.length != 32) {
      return ZenResult.err(ZenValidationError('A sync key is 32 bytes, not ${syncKey.length}.'));
    }
    final cipher = syncKey == null ? null : await ZenSharedFolderCipher.derive(syncKey);
    final sync = ZenSharedFolderSync._(store, access, cipher, watchDebounce);
    sync._unsentChanges = store.unsentChanges.listen((_) => unawaited(sync.syncNow()));
    if (pollEvery != null) {
      sync._poll = Timer.periodic(pollEvery, (_) => unawaited(sync.syncNow()));
    }
    if (watch && cipher != null) {
      sync._watcher = access.watch()?.listen((_) => sync._watchFired());
    }
    unawaited(sync.syncNow());
    return ZenResult.ok(sync);
  }

  @override
  ZenSyncStatus get status => _status;

  @override
  Stream<ZenSyncStatus> get statusChanges => _statusChanges.stream;

  /// What the last sync that had anything to report merged and skipped, with the files it could
  /// not read in [ZenSyncReport.problems]; null before the first one.
  ZenSyncReport? get lastReport => _lastReport;

  /// Each sync's report, when it merged something or skipped something.
  Stream<ZenSyncReport> get reports => _reports.stream;

  @override
  Future<void> syncNow() {
    if (_stopped) return Future.value();
    final run = _running.then((_) => _syncOnce());
    _running = run.catchError((Object _) {});
    return run;
  }

  /// The name of the directory [syncKey]'s files live in, `<folder>/<key id>`. For a test, or a
  /// person's support request ("which of these directories is mine?"); nothing needs it to sync.
  static Future<String> keyIdOf(List<int> syncKey) async =>
      (await ZenSharedFolderCipher.derive(syncKey)).keyId;

  /// Erases the person's data on every device, in the folder and in this store (ADR-085).
  ///
  /// The store is marked erased (`ZenStore.eraseEverywhere`), this device's files are removed from
  /// the folder, and a marker is left in its directory. Every other paired device finds a marker
  /// at its next sync, erases its own copy and removes its own files the same way, which is how
  /// "each device removes its own directory" works with a folder only its owner may write: a device
  /// that syncs a month later erases then.
  ///
  /// **What stays:** one empty-of-data marker file per device, which the person may delete with
  /// the folder once every device has erased. It is what tells a device that was off. It holds no
  /// record, name or id.
  ///
  /// Fails when the folder cannot be reached, after the store was erased: the cleanup resumes at
  /// every sync, including after a restart, so a failure here is "not yet", never "not erased".
  /// Afterwards the application erases the store's directory (`ZenStore.erase`) and creates a new
  /// sync key before pairing again: this key's directory is marked erased for good.
  Future<ZenResult<void>> eraseEverywhere() async {
    if (_stopped) return const ZenResult.err(ZenStorageError('The transport is stopped.'));
    if (await _store.eraseEverywhere() case ZenFailure(:final error)) return ZenResult.err(error);
    await syncNow();
    await whenIdle();
    if (_cipher == null) return const ZenResult.ok(null); // never paired: nothing in the folder
    if (_status.issue == ZenSyncIssue.erasedEverywhere) return const ZenResult.ok(null);
    return ZenResult.err(
      ZenStorageError(
        'The store was erased here, but the folder was not cleaned (${_status.issue?.name}: '
        '${_status.message ?? 'unavailable'}). It is finished at the next sync that can reach it.',
      ),
    );
  }

  /// Replaces the sync key, so a device that holds the old one (lost, sold, photographed) can no
  /// longer read or write what the others share (ADR-085).
  ///
  /// Makes a new random key, hands it to [persist] - which must store it as durably as the key
  /// was stored before, and may fail - then writes everything this device holds under the new
  /// key's directory and leaves only a `rekeyed.zen` marker in the old one. Each of the person's
  /// remaining devices shows that marker as [ZenSyncIssue.keyReplaced] and is paired again with
  /// this one (`ZenPairing.offer` with the returned key). Files written with the old key are
  /// never read again, and what a removed device writes with it lands where nobody looks.
  ///
  /// **Order is the safety.** [persist] runs before anything in the folder changes: if it fails,
  /// nothing happened; if the app dies after it, the next start has the new key and the transport
  /// sends everything again (an empty own directory under the new key is exactly "send all").
  ///
  /// **What it cannot do:** take back what the removed device already read, or stop it reading the
  /// folder's encrypted files as long as the folder is shared with it. The person stops sharing
  /// the folder with that device as well.
  Future<ZenResult<List<int>>> rekey({
    required Future<void> Function(List<int> newKey) persist,
  }) async {
    if (_stopped) return const ZenResult.err(ZenStorageError('The transport is stopped.'));
    final before = _cipher;
    final run = _running.then((_) => _rekey(persist));
    _running = run.then<void>((_) {}, onError: (Object _) {});
    final result = await run;
    // Sends everything under the new key, queued behind this run so it never interleaves with it.
    if (!identical(before, _cipher)) await syncNow();
    return result;
  }

  Future<ZenResult<List<int>>> _rekey(Future<void> Function(List<int> newKey) persist) async {
    final old = _cipher;
    if (old == null) {
      return const ZenResult.err(
        ZenValidationError('This device is not paired, so there is no sync key to replace.'),
      );
    }
    if (_store.erasedEverywhere) {
      return const ZenResult.err(ZenStorageError('The store was erased everywhere.'));
    }
    try {
      final state = await _access.check();
      if (state != ZenFolderState.ready) {
        return ZenResult.err(
          ZenStorageError('The folder cannot be reached (${state.name}); try again once it can.'),
        );
      }
      final random = Random.secure();
      final newKey = List<int>.generate(32, (_) => random.nextInt(256));
      final fresh = await ZenSharedFolderCipher.derive(newKey);
      await persist(List.unmodifiable(newKey));
      _cipher = fresh;
      _merged.clear();
      _toMirror.clear();
      _republishing = false;
      if (await _store.forgetTransport() case ZenFailure(:final error)) {
        throw StateError(error.message);
      }
      _retiring = old;
      try {
        await _retireOldKey();
      } on Object catch (e, stack) {
        return ZenResult.err(
          ZenStorageError(
            'The sync key was replaced and handed to persist, but the folder still holds files '
            'under the old key: $e. They are removed at the next sync that can reach the folder.',
            stackTrace: stack,
          ),
        );
      }
      return ZenResult.ok(List.unmodifiable(newKey));
    } on Object catch (e, stack) {
      return ZenResult.err(
        ZenStorageError('Could not replace the sync key: $e', stackTrace: stack),
      );
    }
  }

  /// Whatever the folder holds under the old key is now the removed device's to read: remove it,
  /// and leave the one file that tells a remaining device to stop and pair again.
  Future<void> _retireOldKey() async {
    final old = _retiring;
    if (old == null) return;
    await _access.delete(old.keyId);
    final path = '${old.keyId}/$_rekeyedFile';
    await _access.write(path, await old.sealMarker(ZenSharedFolderCipher.rekeyedMarker, path));
    _retiring = null;
  }

  /// Completes once no sync is running or queued. A sync can queue another (merging a record that
  /// holds more than the sender's makes it unsent, which asks for a send), so "my `syncNow`
  /// returned" does not mean the transport is at rest; this does. [status] is `upToDate` or
  /// `unavailable` then, never `syncing`.
  Future<void> whenIdle() async {
    while (true) {
      final running = _running;
      await running;
      if (identical(running, _running)) return;
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _poll?.cancel();
    _debounce?.cancel();
    await _watcher?.cancel();
    await _unsentChanges?.cancel();
    await _running;
    _setStatus(ZenSyncStatus.off);
    await _statusChanges.close();
    await _reports.close();
  }

  void _watchFired() {
    _debounce?.cancel();
    _debounce = Timer(_watchDebounce, () => unawaited(syncNow()));
  }

  Future<void> _syncOnce() async {
    if (_stopped) return;
    final cipher = _cipher;
    if (cipher == null) {
      _setStatus(const ZenSyncStatus(ZenSyncState.unavailable, issue: ZenSyncIssue.notPaired));
      return;
    }
    _setStatus(const ZenSyncStatus(ZenSyncState.syncing));
    try {
      final folder = await _access.check();
      if (folder != ZenFolderState.ready) {
        _setStatus(_unusable(folder));
        return;
      }
      await _retireOldKey();
      if (await _keyWasReplaced(cipher)) {
        _setStatus(
          const ZenSyncStatus(
            ZenSyncState.unavailable,
            issue: ZenSyncIssue.keyReplaced,
            message: 'a device was removed and the sync key replaced',
          ),
        );
        return;
      }
      if (_store.erasedEverywhere) {
        await _cleanAfterErasure(cipher);
        _setErased();
        return;
      }
      await _republishIfOurDirectoryIsGone(cipher);
      final fetched = await _fetch(cipher);
      if (fetched.erased) {
        if (await _store.eraseEverywhere() case ZenFailure(:final error)) {
          throw StateError(error.message);
        }
        await _cleanAfterErasure(cipher);
        _setErased();
        return;
      }
      await _send(cipher);
      final problems = fetched.problems;
      _setStatus(
        fetched.newerVersion
            ? ZenSyncStatus(
                ZenSyncState.unavailable,
                issue: ZenSyncIssue.newerAppVersion,
                message: problems.join('; '),
              )
            : problems.isEmpty
            ? const ZenSyncStatus(ZenSyncState.upToDate)
            : ZenSyncStatus(
                ZenSyncState.unavailable,
                issue: ZenSyncIssue.unreadableRecords,
                message: problems.join('; '),
              ),
      );
    } on Object catch (e) {
      // The folder may have gone while we worked: say so in its own terms if it did.
      final folder = await _access.check().then<ZenFolderState?>((s) => s, onError: (_) => null);
      _setStatus(
        folder != null && folder != ZenFolderState.ready
            ? _unusable(folder)
            : ZenSyncStatus(ZenSyncState.unavailable, issue: ZenSyncIssue.other, message: '$e'),
      );
    }
  }

  void _setErased() => _setStatus(
    const ZenSyncStatus(
      ZenSyncState.unavailable,
      issue: ZenSyncIssue.erasedEverywhere,
      message: 'the store was erased everywhere',
    ),
  );

  /// Whether a device that replaced the sync key left its marker where this key's files were.
  Future<bool> _keyWasReplaced(ZenSharedFolderCipher cipher) async {
    final path = '${cipher.keyId}/$_rekeyedFile';
    final bytes = await _access.read(path);
    if (bytes == null) return false;
    try {
      return await cipher.isMarker(bytes, ZenSharedFolderCipher.rekeyedMarker, path);
    } on ZenSharedFileException {
      return false; // a damaged marker is no reason to stop; the files themselves are checked
    }
  }

  /// Removes every record file this device wrote and leaves its erased marker, which is what a
  /// device that was off finds later. Idempotent, so an interrupted cleanup finishes at the next
  /// sync, and so does one that could not reach the folder.
  Future<void> _cleanAfterErasure(ZenSharedFolderCipher cipher) async {
    _merged.clear();
    _toMirror.clear();
    final own = '${cipher.keyId}/${_store.deviceId}';
    for (final entry in await _access.list(own)) {
      if (entry.name == _erasedFile) continue;
      await _access.delete('$own/${entry.name}');
    }
    final marker = '$own/$_erasedFile';
    final existing = await _access.read(marker);
    var valid = false;
    if (existing != null) {
      try {
        valid = await cipher.isMarker(existing, ZenSharedFolderCipher.erasedMarker, marker);
      } on ZenSharedFileException {
        valid = false;
      }
    }
    if (!valid) {
      await _access.write(
        marker,
        await cipher.sealMarker(ZenSharedFolderCipher.erasedMarker, marker),
      );
    }
  }

  /// A folder that has lost this device's directory (chosen anew, or someone deleted it) holds
  /// nothing of ours, though the store believes it was all delivered. Send everything again; the
  /// files are whole states, so doing so twice costs bytes and nothing else.
  Future<void> _republishIfOurDirectoryIsGone(ZenSharedFolderCipher cipher) async {
    final published = _store.transportState;
    if (published == null || !_sameBytes(published, _publishedMarker)) return;
    if ((await _access.list('${cipher.keyId}/${_store.deviceId}')).isNotEmpty) {
      _republishing = false;
      return;
    }
    if (_republishing) {
      throw StateError(
        'this device\'s files do not appear in the folder after being written; '
        'is the folder\'s sync service working?',
      );
    }
    _republishing = true;
    _merged.clear();
    if (await _store.forgetTransport() case ZenFailure(:final error)) {
      throw StateError(error.message);
    }
  }

  Future<({List<ZenSyncProblem> problems, bool newerVersion, bool erased})> _fetch(
    ZenSharedFolderCipher cipher,
  ) async {
    final problems = <ZenSyncProblem>[];
    var newerVersion = false;
    var erased = false;
    final incoming = <ZenIncomingRecord>[];
    final fingerprints = <String, String>{};
    final pathOfRecord = <ZenIncomingRecord, String>{};
    for (final device in await _access.list(cipher.keyId)) {
      if (!device.isDirectory || !_deviceDirectory.hasMatch(device.name)) continue;
      if (device.name == _store.deviceId) continue;
      for (final file in await _access.list('${cipher.keyId}/${device.name}')) {
        if (file.isDirectory) continue;
        final path = '${cipher.keyId}/${device.name}/${file.name}';
        if (file.name == _erasedFile) {
          final bytes = await _access.read(path);
          if (bytes == null) continue;
          try {
            erased =
                await cipher.isMarker(bytes, ZenSharedFolderCipher.erasedMarker, path) || erased;
          } on ZenSharedFileException catch (e) {
            problems.add(ZenSyncProblem(path, e.message));
          }
          continue;
        }
        if (!_recordFile.hasMatch(file.name)) continue;
        final fingerprint = '${file.size}:${file.modifiedMillis}';
        if (_merged[path] == fingerprint) continue;
        final bytes = await _access.read(path);
        if (bytes == null) continue; // not delivered yet, or gone since the listing
        try {
          final record = await cipher.open(bytes, path);
          final item = ZenIncomingRecord(record.name, record.payload, null);
          incoming.add(item);
          pathOfRecord[item] = path;
          fingerprints[path] = fingerprint;
        } on ZenSharedFileException catch (e) {
          newerVersion = newerVersion || e.newerVersion;
          problems.add(ZenSyncProblem(path, e.message));
        }
      }
    }
    // Someone erased everything: nothing they or anyone else wrote is merged any more.
    if (erased) return (problems: problems, newerVersion: newerVersion, erased: true);
    ZenSyncReport? received;
    if (incoming.isNotEmpty) {
      switch (await _store.receive(incoming)) {
        case ZenSuccess(:final data):
          received = data;
          problems.addAll(data.problems);
        case ZenFailure(:final error):
          throw StateError(error.message);
      }
      // A file whose record the store refused (a newer record format inside a readable file) is
      // reported by name, and is read again next pass like any other problem.
      final refused = {for (final problem in received.problems) problem.record};
      for (final item in incoming) {
        final path = pathOfRecord[item]!;
        if (refused.contains(item.name)) continue;
        _merged[path] = fingerprints[path]!;
        _toMirror.add(item.name);
      }
      // The store words a newer record format as "written by a newer version".
      newerVersion =
          newerVersion || received.problems.any((p) => p.message.contains('newer version'));
    }
    if (received != null || problems.isNotEmpty) {
      final report = ZenSyncReport(
        changed: received?.changed ?? const {},
        conflicts: _store.conflictCount,
        problems: problems,
      );
      _lastReport = report;
      if (!_reports.isClosed) _reports.add(report);
    }
    return (problems: problems, newerVersion: newerVersion, erased: false);
  }

  Future<void> _send(ZenSharedFolderCipher cipher) async {
    final saved = <ZenAcknowledgedRecord>[];
    Object? failure;
    StackTrace? failureStack;
    for (final name in _store.unsent) {
      final outgoing = _store.outgoing(name);
      if (outgoing == null) continue;
      try {
        final path = '${cipher.keyId}/${_store.deviceId}/${await cipher.fileName(name)}';
        await _access.write(path, await cipher.seal(name, outgoing.payload, path));
        saved.add(ZenAcknowledgedRecord(name, outgoing.payload, null));
      } on Object catch (e, stack) {
        failure = e;
        failureStack = stack;
        break;
      }
    }
    if (failure == null) {
      try {
        await _mirror(cipher, {for (final record in saved) record.name});
      } on Object catch (e, stack) {
        failure = e;
        failureStack = stack;
      }
    }
    if (saved.isNotEmpty) {
      if (await _store.acknowledge(saved) case ZenFailure(:final error)) {
        throw StateError(error.message);
      }
      if (await _store.saveTransportState(_publishedMarker) case ZenFailure(:final error)) {
        throw StateError(error.message);
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  /// Makes sure this device's directory holds every record it merged from another device, in the
  /// state it now has them.
  ///
  /// Each directory is then a whole copy of what its device knows, so a new or re-paired device
  /// needs one directory to learn everything, and a record does not vanish from the folder when
  /// the device that wrote it is removed or its directory deleted. The price is that the folder
  /// holds every record once per device (ADR-076). A file already holding the current state is
  /// left alone, so nothing is rewritten once the devices agree.
  Future<void> _mirror(ZenSharedFolderCipher cipher, Set<String> alreadyWritten) async {
    for (final name in _toMirror.toList()) {
      if (alreadyWritten.contains(name)) {
        _toMirror.remove(name);
        continue;
      }
      final outgoing = _store.outgoing(name);
      if (outgoing == null) {
        _toMirror.remove(name);
        continue;
      }
      final path = '${cipher.keyId}/${_store.deviceId}/${await cipher.fileName(name)}';
      final existing = await _access.read(path);
      if (existing != null) {
        try {
          final held = await cipher.open(existing, path);
          if (_sameBytes(held.payload, outgoing.payload)) {
            _toMirror.remove(name);
            continue;
          }
        } on ZenSharedFileException {
          // Our own file is damaged or foreign: replace it.
        }
      }
      await _access.write(path, await cipher.seal(name, outgoing.payload, path));
      _toMirror.remove(name);
    }
  }

  static ZenSyncStatus _unusable(ZenFolderState state) => ZenSyncStatus(
    ZenSyncState.unavailable,
    issue: switch (state) {
      ZenFolderState.notChosen => ZenSyncIssue.noFolder,
      ZenFolderState.unreachable => ZenSyncIssue.folderUnreachable,
      ZenFolderState.accessRevoked => ZenSyncIssue.accessRevoked,
      ZenFolderState.ready => ZenSyncIssue.other,
    },
  );

  void _setStatus(ZenSyncStatus status) {
    if (status == _status || _statusChanges.isClosed) return;
    _status = status;
    _statusChanges.add(status);
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
