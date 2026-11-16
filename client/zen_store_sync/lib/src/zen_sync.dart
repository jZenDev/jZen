import 'dart:io';

import 'package:meta/meta.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_cloudkit/zen_store_cloudkit.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

import 'zen_sync_plan.dart';

/// Starts a Local application's sync, through the transport its build names (ADR-073, ADR-079).
///
/// The application passes what each transport needs and reads no `ZEN_SYNC` of its own:
///
/// ```dart
/// final sync = await ZenSync.start(
///   store,
///   cloudKitContainerId: 'iCloud.com.example.app', // iOS, macOS
///   sharedFolder: access,                          // Android, Windows, Linux: the chosen folder
///   syncKey: pairedKey,                            // null until the device is paired
/// );
/// ```
abstract final class ZenSync {
  // The define `task zen:run:client ZEN_SYNC=...` bakes in (ADR-072); a release build refuses it (`ZenSyncPlan`).
  static const String _define = String.fromEnvironment('ZEN_SYNC');
  // The folder `ZenFolderCloud` syncs through, with `ZEN_SYNC=folder`.
  static const String _folderDefine = String.fromEnvironment('ZEN_SYNC_FOLDER');

  /// What this build syncs through, decided at compile time.
  static const ZenSyncPlan plan = ZenSyncPlan(
    zenPlatform,
    _define,
    release: bool.fromEnvironment('dart.vm.product'),
  );

  /// Starts syncing [store] through the transport this build's `ZEN_PLATFORM` and `ZEN_SYNC` name:
  /// CloudKit on iOS and macOS, the shared folder on Android, Windows and Linux, and
  /// `ZenFolderCloud` with `ZEN_SYNC=folder`.
  ///
  /// Each transport's own arguments are used only by that transport and ignored by the others:
  /// - [cloudKitContainerId]: the CloudKit container (the app's default when null), [cloudKitZone]
  ///   the record zone.
  /// - [sharedFolder]: how the chosen folder is reached, required for the shared folder;
  ///   [syncKey] is the 32-byte key paired devices share, null on a device not yet paired (the
  ///   transport then reports `notPaired`).
  ///
  /// Fails with a [ZenValidationError] when the build's combination is refused (the web, an
  /// unknown platform, `ZEN_SYNC=cloudkit` off Apple) or when what the chosen transport needs was
  /// not passed. Never returns a transport that silently does nothing.
  static Future<ZenResult<ZenSyncTransport>> start(
    ZenStore store, {
    String? cloudKitContainerId,
    String cloudKitZone = 'zen_store',
    ZenFolderAccess? sharedFolder,
    List<int>? syncKey,
  }) {
    // Switching on the constant, here and not in a helper taking the plan, is what lets the
    // compiler see that the other branches are never reached.
    switch (plan.kind) {
      case ZenSyncKind.cloudKit:
        return _cloudKit(store, cloudKitContainerId, cloudKitZone);
      case ZenSyncKind.sharedFolder:
        return _sharedFolder(store, sharedFolder, syncKey);
      case ZenSyncKind.folderCloud:
        return _folderCloud(store, _folderDefine);
      case null:
        return _refused(plan);
    }
  }

  /// [start] for an arbitrary [plan], so a test can run every row of the table. Nothing but a
  /// test reaches it, so a build drops it with the branches [start] cannot take.
  @visibleForTesting
  static Future<ZenResult<ZenSyncTransport>> startFor(
    ZenSyncPlan plan,
    ZenStore store, {
    String? cloudKitContainerId,
    String cloudKitZone = 'zen_store',
    ZenFolderAccess? sharedFolder,
    List<int>? syncKey,
    String folderCloudPath = '',
  }) {
    switch (plan.kind) {
      case ZenSyncKind.cloudKit:
        return _cloudKit(store, cloudKitContainerId, cloudKitZone);
      case ZenSyncKind.sharedFolder:
        return _sharedFolder(store, sharedFolder, syncKey);
      case ZenSyncKind.folderCloud:
        return _folderCloud(store, folderCloudPath);
      case null:
        return _refused(plan);
    }
  }

  static Future<ZenResult<ZenSyncTransport>> _refused(ZenSyncPlan plan) async =>
      ZenResult.err(ZenValidationError(plan.refusal ?? 'No sync transport is chosen.'));

  static Future<ZenResult<ZenSyncTransport>> _cloudKit(
    ZenStore store,
    String? containerId,
    String zone,
  ) async => await ZenCloudKitSync.start(store, containerId: containerId, zone: zone);

  static Future<ZenResult<ZenSyncTransport>> _sharedFolder(
    ZenStore store,
    ZenFolderAccess? access,
    List<int>? syncKey,
  ) async {
    if (access == null) {
      return const ZenResult.err(
        ZenValidationError(
          'Syncing through the shared folder needs `sharedFolder`: how the folder the person '
          'chose is reached.',
        ),
      );
    }
    return ZenSharedFolderSync.start(store, access, syncKey: syncKey);
  }

  static Future<ZenResult<ZenSyncTransport>> _folderCloud(ZenStore store, String path) async {
    if (path.isEmpty) {
      return const ZenResult.err(
        ZenValidationError(
          'ZEN_SYNC=folder needs ZEN_SYNC_FOLDER, an absolute path every syncing build shares.',
        ),
      );
    }
    return ZenFolderCloud.start(store, Directory(path));
  }
}
