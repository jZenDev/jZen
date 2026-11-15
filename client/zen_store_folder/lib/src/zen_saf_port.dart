import 'dart:typed_data';

import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

/// One entry of a Storage Access Framework directory.
final class ZenSafEntry {
  final String uri;
  final String name;
  final bool isDirectory;
  final int length;
  final int modifiedMillis;

  const ZenSafEntry({
    required this.uri,
    required this.name,
    required this.isDirectory,
    this.length = 0,
    this.modifiedMillis = 0,
  });
}

/// The few Storage Access Framework operations the folder access needs, so a suite can stand in
/// for the two plugins (ADR-076) and the adapter's rules are tested without an Android device.
abstract interface class ZenSafPort {
  /// Lets the person pick a directory; its persistable read-write grant is taken. Null if cancelled.
  Future<ZenSafEntry?> pickDirectory();

  /// Whether the app still holds a read-write grant on [treeUri].
  Future<bool> hasGrant(String treeUri);

  /// The entry at [names] below [uri], or null.
  Future<ZenSafEntry?> child(String uri, List<String> names);

  Future<List<ZenSafEntry>> list(String uri);

  /// Creates [names] below [uri] as directories where missing; returns the last.
  Future<ZenSafEntry> mkdirp(String uri, List<String> names);

  Future<Uint8List> read(String uri);

  /// Writes a new file [name] in directory [dirUri]; returns its uri.
  Future<String> create(String dirUri, String name, Uint8List bytes);

  Future<void> delete(String uri, {required bool isDirectory});

  Future<void> rename(String uri, String newName);
}

/// The port over `saf_util` and `saf_stream`.
final class ZenPluginSafPort implements ZenSafPort {
  final SafUtil _util = SafUtil();
  final SafStream _stream = SafStream();

  ZenPluginSafPort();

  static ZenSafEntry _entry(SafDocumentFile file) => ZenSafEntry(
    uri: file.uri,
    name: file.name,
    isDirectory: file.isDir,
    length: file.length,
    modifiedMillis: file.lastModified,
  );

  @override
  Future<ZenSafEntry?> pickDirectory() async {
    final picked = await _util.pickDirectory(writePermission: true, persistablePermission: true);
    return picked == null ? null : _entry(picked);
  }

  @override
  Future<bool> hasGrant(String treeUri) =>
      _util.hasPersistedPermission(treeUri, checkRead: true, checkWrite: true);

  @override
  Future<ZenSafEntry?> child(String uri, List<String> names) async {
    final found = await _util.child(uri, names);
    return found == null ? null : _entry(found);
  }

  @override
  Future<List<ZenSafEntry>> list(String uri) async => [
    for (final file in await _util.list(uri)) _entry(file),
  ];

  @override
  Future<ZenSafEntry> mkdirp(String uri, List<String> names) async =>
      _entry(await _util.mkdirp(uri, names));

  @override
  Future<Uint8List> read(String uri) => _stream.readFileBytes(uri);

  @override
  Future<String> create(String dirUri, String name, Uint8List bytes) async {
    final made = await _stream.writeFileBytes(
      dirUri,
      name,
      'application/octet-stream',
      bytes,
      overwrite: false,
    );
    return made.uri.toString();
  }

  @override
  Future<void> delete(String uri, {required bool isDirectory}) => _util.delete(uri, isDirectory);

  @override
  Future<void> rename(String uri, String newName) async {
    await _util.rename(uri, false, newName);
  }
}
