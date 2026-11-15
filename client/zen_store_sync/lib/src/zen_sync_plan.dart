import 'package:meta/meta.dart';

/// The transport a Local application syncs through.
enum ZenSyncKind {
  /// CloudKit (`zen_store_cloudkit`), iOS 17 and macOS 14.
  cloudKit,

  /// A folder the person chooses and a sync service of their own keeps in step
  /// (`zen_store_shared_folder`), Android, Windows and Linux.
  sharedFolder,

  /// `ZenFolderCloud`, the development stand-in for CloudKit.
  folderCloud,
}

/// Which transport a build syncs through, decided from `ZEN_PLATFORM` and `ZEN_SYNC` alone, or why
/// it syncs through none (ADR-073, ADR-079).
///
/// **A constant constructor, on purpose.** [ZenSync.start] builds one from the compile-time
/// defines, so [kind] and [refusal] are compile-time constants and the tree-shaker drops the
/// transports the platform never reaches (STANDARDS "Client config is compile-time"). The tests
/// call the same constructor with every combination, so no second copy of the table exists to
/// drift from the one that ships.
///
/// | `ZEN_PLATFORM` | `ZEN_SYNC` unset | `folder` | `cloudkit` |
/// |---|---|---|---|
/// | `ios`, `macos` | [ZenSyncKind.cloudKit] | [ZenSyncKind.folderCloud] | [ZenSyncKind.cloudKit] |
/// | `android`, `windows`, `linux` | [ZenSyncKind.sharedFolder] | [ZenSyncKind.folderCloud] | refused |
/// | `web`, unset, anything else | refused | refused | refused |
@immutable
final class ZenSyncPlan {
  /// The transport, or null when the combination is refused and [refusal] says why.
  final ZenSyncKind? kind;

  /// Why no transport is chosen; null when [kind] is set.
  final String? refusal;

  /// Decides for [platform] (`ZEN_PLATFORM`) and [sync] (`ZEN_SYNC`; empty when unset).
  const ZenSyncPlan(String platform, String sync)
    : kind =
          (platform == 'ios' ||
              platform == 'macos' ||
              platform == 'android' ||
              platform == 'windows' ||
              platform == 'linux')
          ? (sync == ''
                ? ((platform == 'ios' || platform == 'macos')
                      ? ZenSyncKind.cloudKit
                      : ZenSyncKind.sharedFolder)
                : sync == 'folder'
                ? ZenSyncKind.folderCloud
                : (sync == 'cloudkit' && (platform == 'ios' || platform == 'macos'))
                ? ZenSyncKind.cloudKit
                : null)
          : null,
      refusal =
          (platform == 'ios' ||
              platform == 'macos' ||
              platform == 'android' ||
              platform == 'windows' ||
              platform == 'linux')
          ? (sync == '' || sync == 'folder'
                ? null
                : sync == 'cloudkit'
                ? ((platform == 'ios' || platform == 'macos')
                      ? null
                      : 'ZEN_SYNC=cloudkit is CloudKit, which exists only on iOS and macOS, not on '
                            '$platform. Leave ZEN_SYNC unset to use the shared folder.')
                : "ZEN_SYNC='$sync' is neither folder nor cloudkit.")
          : platform == 'web'
          ? 'A Local application does not build for the web (ADR-073): the browser has no durable '
                'place for an encrypted store and no secure key storage.'
          : "ZEN_PLATFORM='$platform' is not one a Local application runs on: ios, macos, android, "
                'windows or linux. Build with --dart-define=ZEN_PLATFORM=<platform>.';

  @override
  bool operator ==(Object other) =>
      other is ZenSyncPlan && other.kind == kind && other.refusal == refusal;

  @override
  int get hashCode => Object.hash(kind, refusal);

  @override
  String toString() => kind != null ? 'ZenSyncPlan($kind)' : 'ZenSyncPlan(refused: $refusal)';
}
