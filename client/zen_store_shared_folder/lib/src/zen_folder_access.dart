import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Whether a folder can be used right now, and if not, which of the things a person can fix it is.
enum ZenFolderState {
  /// Usable.
  ready,

  /// No folder has been chosen.
  notChosen,

  /// It was chosen and is not there: moved, deleted, a drive or share that is not mounted.
  unreachable,

  /// It is there and this app may no longer use it: Android's persisted grant was revoked, or the
  /// operating system refuses the app.
  accessRevoked,
}

/// One entry of a folder listing.
@immutable
final class ZenFolderEntry {
  /// The entry's name, without its parent's path.
  final String name;

  /// Whether it is a directory.
  final bool isDirectory;

  /// A file's size in bytes; 0 for a directory, -1 when the platform does not know it.
  final int size;

  /// A file's last change, in milliseconds since the epoch; 0 when the platform does not know it.
  final int modifiedMillis;

  /// Creates an entry.
  const ZenFolderEntry(
    this.name, {
    required this.isDirectory,
    this.size = 0,
    this.modifiedMillis = 0,
  });
}

/// How [ZenSharedFolderSync] reaches the folder: the seam that keeps the transport pure Dart.
///
/// On desktop it is `dart:io` ([ZenDirectoryAccess]). On Android a chosen folder is a
/// `content://` tree that `dart:io` cannot open, so an implementation on the Storage Access
/// Framework plugs in here (ADR-075) and nothing in the transport changes.
///
/// Paths are relative to the chosen folder, `/`-separated, and never contain `..`. The transport
/// only ever writes a file under its own device's directory, so an implementation needs no notion
/// of ownership.
abstract interface class ZenFolderAccess {
  /// Whether the folder can be used. Called before every sync: the answer changes while the app
  /// runs (a drive unplugged, a grant withdrawn).
  Future<ZenFolderState> check();

  /// The entries of the directory at [path] (`''` for the folder itself); empty if it does not
  /// exist.
  Future<List<ZenFolderEntry>> list(String path);

  /// The file at [path], or null if it is not there (a sync service may remove or not yet have
  /// delivered it between a listing and this call).
  Future<Uint8List?> read(String path);

  /// Writes [bytes] as the file at [path], creating its directories. A reader never sees half of
  /// it: an implementation writes elsewhere and renames over the target. Where the platform
  /// cannot rename over an existing file (Android's SAF), it deletes then renames, so a reader
  /// may briefly see no file, which the transport treats as "not delivered yet" - never as a
  /// deletion.
  Future<void> write(String path, Uint8List bytes);

  /// Fires when something in the folder may have changed, or null where the platform has no
  /// watcher. A watcher only brings the next sync forward: polling stays the guarantee, because a
  /// watcher misses changes made while the app was not running and, on some network or cloud
  /// drives, ones made by the sync service itself.
  Stream<void>? watch();
}
