import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'zen_folder_access.dart';

/// [ZenFolderAccess] over a directory `dart:io` can open: Windows, Linux and macOS folders, and
/// Android's app-specific directories (not a SAF-chosen folder).
///
/// Writes go to a `.<name>.<random>.tmp` file in the target's own directory and are renamed over
/// it, so a sync service uploading mid-write sees either the old file or the whole new one - or,
/// if it grabs the temp file, a name the transport's readers ignore.
final class ZenDirectoryAccess implements ZenFolderAccess {
  static final Random _random = Random.secure();

  /// The chosen folder, or null while none is.
  final Directory? folder;

  /// Creates access to [folder].
  ZenDirectoryAccess(this.folder);

  @override
  Future<ZenFolderState> check() async {
    final folder = this.folder;
    if (folder == null) return ZenFolderState.notChosen;
    try {
      if (!await folder.exists()) return ZenFolderState.unreachable;
      await folder.list().isEmpty;
      return ZenFolderState.ready;
    } on FileSystemException catch (e) {
      // EPERM, EACCES, and Windows' ERROR_ACCESS_DENIED: the folder exists and we are refused.
      return switch (e.osError?.errorCode) {
        1 || 13 || 5 => ZenFolderState.accessRevoked,
        _ => ZenFolderState.unreachable,
      };
    }
  }

  @override
  Future<List<ZenFolderEntry>> list(String path) async {
    final directory = Directory(_resolve(path));
    if (!await directory.exists()) return const [];
    final entries = <ZenFolderEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
      if (entity is Directory) {
        entries.add(ZenFolderEntry(name, isDirectory: true));
      } else if (entity is File) {
        try {
          final stat = await entity.stat();
          entries.add(
            ZenFolderEntry(
              name,
              isDirectory: false,
              size: stat.size,
              modifiedMillis: stat.modified.millisecondsSinceEpoch,
            ),
          );
        } on FileSystemException {
          // Removed between the listing and the stat: the sync service is mid-change, and the
          // next listing settles it.
        }
      }
    }
    return entries;
  }

  @override
  Future<Uint8List?> read(String path) async {
    try {
      return await File(_resolve(path)).readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final target = File(_resolve(path));
    await target.parent.create(recursive: true);
    final name = target.uri.pathSegments.last;
    final temp = File(
      '${target.parent.path}${Platform.pathSeparator}.$name.${_random.nextInt(1 << 32).toRadixString(16)}.tmp',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } on Object {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  @override
  Stream<void>? watch() {
    final folder = this.folder;
    if (folder == null) return null;
    // Recursive where the platform supports it. A watcher that fails ends this stream, and the
    // transport's polling carries on - see ZenFolderAccess.watch.
    final controller = StreamController<void>();
    StreamSubscription<FileSystemEvent>? subscription;
    controller.onListen = () {
      try {
        subscription = folder
            .watch(recursive: true)
            .listen(
              (_) => controller.add(null),
              onError: (Object _) => controller.close(),
              onDone: controller.close,
            );
      } on Object {
        controller.close();
      }
    };
    controller.onCancel = () => subscription?.cancel();
    return controller.stream;
  }

  String _resolve(String path) {
    final folder = this.folder;
    if (folder == null) throw StateError('No folder is chosen.');
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.any((s) => s == '..' || s == '.')) {
      throw ArgumentError.value(path, 'path', 'must not contain . or ..');
    }
    return [folder.path, ...segments].join(Platform.pathSeparator);
  }
}
