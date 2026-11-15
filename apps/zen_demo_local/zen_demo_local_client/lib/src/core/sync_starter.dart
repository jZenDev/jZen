import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_store_sync/zen_store_sync.dart';

/// Starts sync for a store. The app's only route to a transport is [ZenSync.start] (ADR-079);
/// tests substitute another starter to run two devices through a transport of their choosing.
typedef SyncStarter =
    Future<ZenResult<ZenSyncTransport>> Function(
      ZenStore store, {
      required ZenFolderAccess folder,
      required List<int>? syncKey,
    });

/// The CloudKit container an Apple build syncs through. Needs the paid Apple Developer Program to
/// exist; until then Apple builds develop against `ZEN_SYNC=folder`.
const String demoCloudKitContainer = 'iCloud.dev.jzen.zenDemoLocalClient';

/// What a build does: let `ZenSync` choose by `ZEN_PLATFORM` and `ZEN_SYNC`.
Future<ZenResult<ZenSyncTransport>> startSyncForBuild(
  ZenStore store, {
  required ZenFolderAccess folder,
  required List<int>? syncKey,
}) => ZenSync.start(
  store,
  cloudKitContainerId: demoCloudKitContainer,
  sharedFolder: folder,
  syncKey: syncKey,
);
