import 'dart:io';

import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_folder/zen_store_folder.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_demo_local_client/src/core/device_session.dart';

/// How a test's two devices reach each other. Both are what a build can run on the host: the
/// development emulation of CloudKit, and the shared-folder transport every non-Apple build uses.
enum TransportKind { folderCloud, sharedFolder }

/// Two real app sessions — real stores, real encryption, real files — joined through one real
/// folder. Nothing is mocked: a conflict seen here is the one a person would see.
final class TwoDevices {
  final Directory root;
  final DeviceSession laptop;
  final DeviceSession phone;

  TwoDevices._(this.root, this.laptop, this.phone);

  static Future<TwoDevices> create(TransportKind kind) async {
    final root = await Directory.systemTemp.createTemp('zen_demo_local_two_devices');
    final folder = Directory('${root.path}/cloud')..createSync();

    // `pollEvery: null`: a test syncs when it says so, which is what makes "offline" exact.
    Future<ZenResult<ZenSyncTransport>> start(
      ZenStore store, {
      required ZenFolderAccess folder_,
      required List<int>? syncKey,
    }) async {
      final result = switch (kind) {
        TransportKind.folderCloud => await ZenFolderCloud.start(store, folder, pollEvery: null),
        TransportKind.sharedFolder => await ZenSharedFolderSync.start(
          store,
          ZenDirectoryAccess(folder),
          syncKey: syncKey,
          pollEvery: null,
          watch: false,
        ),
      };
      return result;
    }

    Future<DeviceSession> open(String name, String deviceName) async {
      final session = await DeviceSession.open(
        directory: Directory('${root.path}/$name'),
        deviceName: deviceName,
        storeKey: List.filled(32, name.length),
        secrets: ZenMemoryLockStorage(),
        start: (store, {required folder, required syncKey}) =>
            start(store, folder_: folder, syncKey: syncKey),
        restoreFolder: (reference) => ZenFolderChoice(
          reference: reference,
          label: reference,
          access: ZenDirectoryAccess(Directory(reference)),
        ),
        pickFolder: () async => ZenFolderChoice(
          reference: folder.path,
          label: 'cloud',
          access: ZenDirectoryAccess(folder),
        ),
      );
      return session.dataOrNull!;
    }

    final laptop = await open('laptop', 'Laptop');
    final phone = await open('phone', 'Phone');
    final devices = TwoDevices._(root, laptop, phone);
    // The shared folder syncs once the devices share a key; CloudKit-like emulation needs none.
    await laptop.chooseFolder();
    await phone.chooseFolder();
    if (kind == TransportKind.sharedFolder) {
      await laptop.createSyncKey();
      await phone.adoptSyncKey(laptop.syncKey!);
    }
    return devices;
  }

  /// Both devices exchange what they hold, twice, so a change made on one has reached the other
  /// and anything that came back has been merged.
  Future<void> sync() async {
    for (var round = 0; round < 3; round++) {
      await laptop.transport!.syncNow();
      await phone.transport!.syncNow();
    }
  }

  Future<void> dispose() async {
    await laptop.shutDown();
    await phone.shutDown();
    await root.delete(recursive: true);
  }
}
