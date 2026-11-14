/// jZen shared-folder sync - a `ZenSyncTransport` for a jZen Local application on Android, Windows
/// and Linux, over a folder the person chooses and a sync service of their own keeps in step.
///
/// - [ZenSharedFolderSync]: the transport
/// - [ZenFolderAccess]: how the transport reaches the folder; [ZenDirectoryAccess] for `dart:io`,
///   an application-supplied one for an Android `content://` tree
///
/// See docs/architecture/DECISIONS.md ADR-075.
library;

export 'src/zen_directory_access.dart';
export 'src/zen_folder_access.dart';
export 'src/zen_shared_folder_sync.dart' show ZenSharedFolderSync;
