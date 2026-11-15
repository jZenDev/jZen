import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_store_sync/zen_store_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ZenStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zen_store_sync_test');
    final opened = await ZenStore.open(
      Directory('${root.path}/store')..createSync(),
      deviceName: 'Test device',
      key: List.generate(32, (i) => i),
    );
    store = opened.dataOrNull!;
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<ZenResult<ZenSyncTransport>> start(
    ZenSyncPlan plan, {
    ZenFolderAccess? access,
    String folder = '',
  }) => ZenSync.startFor(
    plan,
    store,
    sharedFolder: access,
    syncKey: List.generate(32, (i) => 100 + i),
    folderCloudPath: folder,
  );

  test('start() follows the defines this suite was built with', () async {
    // `task test:client` sets ZEN_PLATFORM to the host; a bare `flutter test` sets nothing. Either
    // way `start` must agree with the table, and an unset platform must be refused loudly.
    const sync = String.fromEnvironment('ZEN_SYNC');
    expect(ZenSync.plan, const ZenSyncPlan(zenPlatform, sync));
    if (zenPlatform.isEmpty) {
      final result = await ZenSync.start(store);
      expect(result.errorOrNull, isA<ZenValidationError>());
      expect(result.errorOrNull!.message, contains('ZEN_PLATFORM'));
    }
  });

  test('the web is refused with a ZenError, not a silent transport', () async {
    final result = await start(const ZenSyncPlan('web', ''));
    expect(result.errorOrNull, isA<ZenValidationError>());
    expect(result.errorOrNull!.message, contains('ADR-073'));
  });

  test('ios/macos ask CloudKit, which a host without the plugin reports as a ZenError', () async {
    for (final platform in ['ios', 'macos']) {
      final result = await start(ZenSyncPlan(platform, ''));
      expect(result.errorOrNull, isA<ZenNotFoundError>(), reason: platform);
      expect(result.errorOrNull!.message, contains('CloudKit'));
    }
  });

  test('android/windows/linux start the shared folder', () async {
    for (final platform in ['android', 'windows', 'linux']) {
      final folder = Directory('${root.path}/shared-$platform')..createSync();
      final result = await start(ZenSyncPlan(platform, ''), access: ZenDirectoryAccess(folder));
      final transport = result.dataOrNull;
      expect(transport, isA<ZenSharedFolderSync>(), reason: platform);
      await transport!.stop();
    }
  });

  test('the shared folder without a way to reach it is a ZenError', () async {
    final result = await start(const ZenSyncPlan('linux', ''));
    expect(result.errorOrNull, isA<ZenValidationError>());
    expect(result.errorOrNull!.message, contains('sharedFolder'));
  });

  test('ZEN_SYNC=folder starts ZenFolderCloud on every native platform', () async {
    for (final platform in ['ios', 'macos', 'android', 'windows', 'linux']) {
      final folder = '${root.path}/cloud-$platform';
      final result = await start(ZenSyncPlan(platform, 'folder'), folder: folder);
      final transport = result.dataOrNull;
      expect(transport, isA<ZenFolderCloud>(), reason: platform);
      await transport!.stop();
    }
  });

  test('ZEN_SYNC=folder without ZEN_SYNC_FOLDER is a ZenError', () async {
    final result = await start(const ZenSyncPlan('macos', 'folder'));
    expect(result.errorOrNull!.message, contains('ZEN_SYNC_FOLDER'));
  });

  test('ZEN_SYNC=cloudkit off Apple is refused before anything starts', () async {
    final result = await start(const ZenSyncPlan('android', 'cloudkit'));
    expect(result.errorOrNull, isA<ZenValidationError>());
  });
}
