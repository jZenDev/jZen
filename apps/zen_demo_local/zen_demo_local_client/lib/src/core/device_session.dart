import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_folder/zen_store_folder.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'chore_repository.dart';
import 'sync_starter.dart';

/// Everything this device holds: the open store, the chore list on it, the sync key and chosen
/// folder, and the transport keeping it in step with the person's other devices.
///
/// The screens read it and listen to it; they never open a store or start a transport themselves.
/// Sync is restarted here whenever its inputs change (a folder chosen, a key made or joined, the
/// copy erased), and only ever through [SyncStarter] — by default `ZenSync.start` (ADR-079).
final class DeviceSession extends ChangeNotifier {
  static const String _keyName = 'zen_demo_local.sync_key';
  static const String _folderName = 'zen_demo_local.sync_folder';

  final Directory directory;
  final String deviceName;
  final List<int> _storeKey;
  final ZenLockStorage _secrets;
  final SyncStarter _start;
  final ZenFolderChoice Function(String reference) _restoreFolder;
  final Future<ZenFolderChoice?> Function() _pickFolder;

  ZenStore _store;
  late ChoreRepository _chores;
  ZenSyncTransport? _transport;
  String? _syncProblem;
  ZenFolderChoice? _folder;
  List<int>? _syncKey;
  bool _closed = false;

  DeviceSession._(
    this.directory,
    this.deviceName,
    this._storeKey,
    this._secrets,
    this._start,
    this._restoreFolder,
    this._pickFolder,
    this._store,
  ) {
    _chores = ChoreRepository(_store);
  }

  /// Opens the store in [directory] and starts sync. Fails, writing nothing, if the store cannot
  /// be read: a wrong key or a damaged file is never answered with an empty store.
  static Future<ZenResult<DeviceSession>> open({
    required Directory directory,
    required String deviceName,
    required List<int> storeKey,
    required ZenLockStorage secrets,
    SyncStarter start = startSyncForBuild,
    ZenFolderChoice Function(String reference)? restoreFolder,
    Future<ZenFolderChoice?> Function()? pickFolder,
  }) async {
    final ZenStore store;
    switch (await ZenStore.open(directory, deviceName: deviceName, key: storeKey)) {
      case ZenSuccess(:final data):
        store = data;
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    final session = DeviceSession._(
      directory,
      deviceName,
      storeKey,
      secrets,
      start,
      restoreFolder ?? ZenFolderPicker.restore,
      pickFolder ?? ZenFolderPicker.pick,
      store,
    );
    try {
      final key = await secrets.read(_keyName);
      if (key != null) session._syncKey = base64Decode(key);
      final folder = await secrets.read(_folderName);
      if (folder != null) session._folder = session._restoreFolder(folder);
    } on Object catch (e, stack) {
      await store.close();
      return ZenResult.err(
        ZenUnknownError('This device\'s sync settings cannot be read: $e', stackTrace: stack),
      );
    }
    await session._restartSync();
    return ZenResult.ok(session);
  }

  ZenStore get store => _store;
  ChoreRepository get chores => _chores;

  /// Null while sync could not start; [syncProblem] says why.
  ZenSyncTransport? get transport => _transport;
  String? get syncProblem => _syncProblem;

  ZenFolderChoice? get folder => _folder;
  bool get hasSyncKey => _syncKey != null;

  /// The key a new device joins with. Held only by devices that are part of the group.
  List<int>? get syncKey => _syncKey == null ? null : List.unmodifiable(_syncKey!);

  String newId() => _store.newId();

  /// Lets the person pick the folder, keeps the choice and restarts sync through it.
  Future<void> chooseFolder() async {
    final choice = await _pickFolder();
    if (choice == null) return;
    await _secrets.write(_folderName, choice.reference);
    _folder = choice;
    await _restartSync();
  }

  /// Makes this device the first of the group: a fresh 32-byte sync key, kept in the keystore.
  Future<ZenResult<void>> createSyncKey() {
    final random = Random.secure();
    return adoptSyncKey(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  /// Joins the group whose sync [key] a paired device showed (`ZenJoinScreen`'s `onKey`).
  Future<ZenResult<void>> adoptSyncKey(List<int> key) async {
    try {
      await _secrets.write(_keyName, base64Encode(key));
    } on Object catch (e, stack) {
      return ZenResult.err(ZenUnknownError('The sync key cannot be kept: $e', stackTrace: stack));
    }
    _syncKey = List<int>.of(key);
    await _restartSync();
    return const ZenResult.ok(null);
  }

  /// Deletes this device's copy and starts over, empty. The sync key and folder stay, so what the
  /// other devices hold comes back. Never routed through the sync engine: a deletion record would
  /// erase the data on every device (ZenPinLock's contract for "Forgot PIN?").
  Future<ZenResult<void>> eraseThisDevice() async {
    await _stopSync();
    await _store.close();
    final erased = await ZenStore.erase(directory);
    if (erased case ZenFailure(:final error)) {
      // Reopen what is still there so the app keeps working, and say what happened.
      await _reopen();
      return ZenResult.err(error);
    }
    await _reopen();
    return const ZenResult.ok(null);
  }

  Future<void> _reopen() async {
    switch (await ZenStore.open(directory, deviceName: deviceName, key: _storeKey)) {
      case ZenSuccess(:final data):
        _store = data;
        _chores = ChoreRepository(_store);
      case ZenFailure(:final error):
        throw StateError('The store cannot be reopened: $error');
    }
    await _restartSync();
  }

  Future<void> _restartSync() async {
    await _stopSync();
    final ZenFolderAccess folder = _folder?.access ?? ZenDirectoryAccess(null);
    final result = await _start(_store, folder: folder, syncKey: _syncKey);
    switch (result) {
      case ZenSuccess(:final data):
        _transport = data;
        _syncProblem = null;
      case ZenFailure(:final error):
        _transport = null;
        _syncProblem = error.message;
    }
    if (!_closed) notifyListeners();
  }

  Future<void> _stopSync() async {
    final transport = _transport;
    _transport = null;
    if (transport != null) await transport.stop();
  }

  /// Stops sync and closes the store; the session is unusable afterwards.
  Future<void> shutDown() async {
    _closed = true;
    await _stopSync();
    await _store.close();
    super.dispose();
  }
}
