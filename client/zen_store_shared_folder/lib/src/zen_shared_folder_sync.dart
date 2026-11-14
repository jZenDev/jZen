import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'zen_folder_access.dart';
import 'zen_shared_folder_cipher.dart';

/// Sync for a jZen Local application through a folder that a sync service of the person's own
/// (Syncthing, Dropbox, OneDrive, Nextcloud, ...) keeps in step between their devices (ADR-075).
///
/// ```
/// <folder>/<device id>/<64 hex>.zen     one file per record, written by that device only
/// ```
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
  static final Uint8List _publishedMarker = Uint8List.fromList(utf8.encode('published:1'));

  final ZenStore _store;
  final ZenFolderAccess _access;
  final ZenSharedFolderCipher? _cipher;
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
      await _republishIfOurDirectoryIsGone();
      final fetched = await _fetch(cipher);
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

  /// A folder that has lost this device's directory (chosen anew, or someone deleted it) holds
  /// nothing of ours, though the store believes it was all delivered. Send everything again; the
  /// files are whole states, so doing so twice costs bytes and nothing else.
  Future<void> _republishIfOurDirectoryIsGone() async {
    final published = _store.transportState;
    if (published == null || !_sameBytes(published, _publishedMarker)) return;
    if ((await _access.list(_store.deviceId)).isNotEmpty) {
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

  Future<({List<ZenSyncProblem> problems, bool newerVersion})> _fetch(
    ZenSharedFolderCipher cipher,
  ) async {
    final problems = <ZenSyncProblem>[];
    var newerVersion = false;
    final incoming = <ZenIncomingRecord>[];
    final fingerprints = <String, String>{};
    final pathOfRecord = <ZenIncomingRecord, String>{};
    for (final device in await _access.list('')) {
      if (!device.isDirectory || !_deviceDirectory.hasMatch(device.name)) continue;
      if (device.name == _store.deviceId) continue;
      for (final file in await _access.list(device.name)) {
        if (file.isDirectory || !_recordFile.hasMatch(file.name)) continue;
        final path = '${device.name}/${file.name}';
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
    return (problems: problems, newerVersion: newerVersion);
  }

  Future<void> _send(ZenSharedFolderCipher cipher) async {
    final saved = <ZenAcknowledgedRecord>[];
    Object? failure;
    StackTrace? failureStack;
    for (final name in _store.unsent) {
      final outgoing = _store.outgoing(name);
      if (outgoing == null) continue;
      try {
        final path = '${_store.deviceId}/${await cipher.fileName(name)}';
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
  /// holds every record once per device (ADR-075). A file already holding the current state is
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
      final path = '${_store.deviceId}/${await cipher.fileName(name)}';
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
