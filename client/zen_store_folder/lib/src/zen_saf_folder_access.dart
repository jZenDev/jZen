import 'dart:math';
import 'dart:typed_data';

import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

import 'zen_saf_port.dart';

/// A folder chosen through Android's Storage Access Framework, reached as a [ZenFolderAccess].
///
/// A `content://` tree cannot be opened with `dart:io`, and the framework cannot rename over an
/// existing document, so [write] stores a temporary document, removes the target and renames the
/// temporary one. A reader in that instant sees no file, which the transport treats as "not
/// delivered yet" and never as a deletion (ADR-076).
final class ZenSafFolderAccess implements ZenFolderAccess {
  static final Random _random = Random.secure();

  /// The tree uri the person chose.
  final String treeUri;
  final ZenSafPort _port;

  ZenSafFolderAccess(this.treeUri, {ZenSafPort? port}) : _port = port ?? ZenPluginSafPort();

  @override
  Future<ZenFolderState> check() async {
    try {
      if (!await _port.hasGrant(treeUri)) return ZenFolderState.accessRevoked;
      await _port.list(treeUri);
      return ZenFolderState.ready;
    } on Object {
      // The provider is gone (an unmounted card, a stopped sync app) or the grant was withdrawn
      // between the two calls; either way the folder cannot be used right now.
      return ZenFolderState.unreachable;
    }
  }

  @override
  Future<List<ZenFolderEntry>> list(String path) async {
    final dir = await _port.child(treeUri, _segments(path));
    if (dir == null || !dir.isDirectory) return const [];
    return [
      for (final entry in await _port.list(dir.uri))
        ZenFolderEntry(
          entry.name,
          isDirectory: entry.isDirectory,
          size: entry.isDirectory ? 0 : entry.length,
          modifiedMillis: entry.modifiedMillis,
        ),
    ];
  }

  @override
  Future<Uint8List?> read(String path) async {
    final file = await _port.child(treeUri, _segments(path));
    if (file == null || file.isDirectory) return null;
    return _port.read(file.uri);
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final segments = _segments(path);
    final name = segments.last;
    final dir = await _directoryOf(segments);
    final temp = '.$name.${_random.nextInt(1 << 32).toRadixString(16)}.tmp';
    final tempUri = await _port.create(dir.uri, temp, bytes);
    try {
      final existing = await _port.child(dir.uri, [name]);
      if (existing != null) await _port.delete(existing.uri, isDirectory: false);
      await _port.rename(tempUri, name);
    } on Object {
      try {
        await _port.delete(tempUri, isDirectory: false);
      } on Object {
        // The cleanup failing must not hide why the write did: the caller needs that error. A
        // leftover `.tmp` document is ignored by the transport.
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    final entry = await _port.child(treeUri, _segments(path));
    if (entry == null) return;
    await _port.delete(entry.uri, isDirectory: entry.isDirectory);
  }

  Future<ZenSafEntry> _directoryOf(List<String> segments) async {
    if (segments.length > 1) return _port.mkdirp(treeUri, segments.sublist(0, segments.length - 1));
    final root = await _port.child(treeUri, const []);
    if (root == null) throw StateError('The sync folder $treeUri cannot be opened.');
    return root;
  }

  /// No watcher: a tree cannot be watched from Dart, so the transport polls.
  @override
  Stream<void>? watch() => null;

  static List<String> _segments(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.any((s) => s == '..' || s == '.')) {
      throw ArgumentError.value(path, 'path', 'must not contain . or ..');
    }
    return segments;
  }
}
