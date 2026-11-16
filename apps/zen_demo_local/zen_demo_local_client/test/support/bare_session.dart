import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_folder/zen_store_folder.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'package:zen_demo_local_client/src/core/device_session.dart';

/// A transport that says whatever the test tells it to, so every status the banner can show is
/// shown without a sync service to provoke it.
final class FakeTransport implements ZenSyncTransport {
  final StreamController<ZenSyncStatus> _changes = StreamController<ZenSyncStatus>.broadcast(sync: true);
  ZenSyncStatus _status = const ZenSyncStatus(ZenSyncState.upToDate);

  @override
  ZenSyncStatus get status => _status;

  @override
  Stream<ZenSyncStatus> get statusChanges => _changes.stream;

  void emit(ZenSyncStatus status) {
    _status = status;
    _changes.add(status);
  }

  @override
  Future<void> syncNow() async {}

  @override
  Future<ZenResult<void>> eraseEverywhere() async => const ZenResult.ok(null);
  @override
  Future<void> stop() async {}
}

/// A secret store that refuses to write, as a locked or full keystore does.
final class RefusingStorage implements ZenLockStorage {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async => throw StateError('keystore is locked');

  @override
  Future<void> delete(String key) async {}
}

/// A session with no folder and no key yet — what a freshly installed Android, Windows or Linux
/// build starts as — over [transport] and a store in a temporary directory.
Future<DeviceSession> openBareSession(
  WidgetTester tester, {
  FakeTransport? transport,
  ZenLockStorage? secrets,
  Future<ZenFolderChoice?> Function()? pickFolder,
  String? refusal,
}) async {
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('zen_demo_local_bare'),
  ))!;
  final session = (await tester.runAsync(
    () => DeviceSession.open(
      directory: Directory('${root.path}/store'),
      deviceName: 'Test device',
      storeKey: List.filled(32, 7),
      secrets: secrets ?? ZenMemoryLockStorage(),
      start: (store, {required folder, required syncKey}) async => refusal != null
          ? ZenResult<ZenSyncTransport>.err(ZenValidationError(refusal))
          : ZenResult.ok(transport ?? FakeTransport()),
      restoreFolder: (reference) => ZenFolderChoice(
        reference: reference,
        label: reference,
        access: ZenDirectoryAccess(Directory(reference)),
      ),
      pickFolder: pickFolder,
    ),
  ))!.dataOrNull!;
  addTearDown(
    () => tester.runAsync(() async {
      await session.shutDown();
      await root.delete(recursive: true);
    }),
  );
  return session;
}
