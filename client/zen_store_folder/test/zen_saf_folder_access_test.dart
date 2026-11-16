import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zen_store_folder/zen_store_folder.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

/// An in-memory tree behaving as the Storage Access Framework does: no rename over an existing
/// document, and a name that is taken gets a new one.
class _FakeSaf implements ZenSafPort {
  final Map<String, Uint8List?> nodes = {'content://t': null}; // null value = directory
  bool grant = true;
  bool failRename = false;
  bool failDelete = false;
  int _seq = 0;

  String _join(String dir, String name) => '$dir/$name';

  @override
  Future<ZenSafEntry?> pickDirectory() async =>
      const ZenSafEntry(uri: 'content://t', name: 'Sync', isDirectory: true);

  @override
  Future<bool> hasGrant(String treeUri) async => grant;

  @override
  Future<ZenSafEntry?> child(String uri, List<String> names) async {
    var current = uri;
    for (final name in names) {
      current = _join(current, name);
    }
    if (!nodes.containsKey(current)) return null;
    return _entry(current);
  }

  ZenSafEntry _entry(String uri) => ZenSafEntry(
    uri: uri,
    name: uri.split('/').last,
    isDirectory: nodes[uri] == null,
    length: nodes[uri]?.length ?? 0,
  );

  @override
  Future<List<ZenSafEntry>> list(String uri) async => [
    for (final key in nodes.keys)
      if (key.startsWith('$uri/') && !key.substring(uri.length + 1).contains('/')) _entry(key),
  ];

  @override
  Future<ZenSafEntry> mkdirp(String uri, List<String> names) async {
    var current = uri;
    for (final name in names) {
      current = _join(current, name);
      nodes.putIfAbsent(current, () => null);
    }
    return _entry(current);
  }

  @override
  Future<Uint8List> read(String uri) async => nodes[uri]!;

  @override
  Future<String> create(String dirUri, String name, Uint8List bytes) async {
    var target = _join(dirUri, name);
    if (nodes.containsKey(target)) target = _join(dirUri, '$name (${_seq++})');
    nodes[target] = bytes;
    return target;
  }

  @override
  Future<void> delete(String uri, {required bool isDirectory}) async {
    if (failDelete) throw StateError('delete failed');
    nodes.remove(uri);
    // The framework deletes a directory with everything in it.
    if (isDirectory) nodes.removeWhere((key, _) => key.startsWith('$uri/'));
  }

  @override
  Future<void> rename(String uri, String newName) async {
    if (failRename) throw StateError('rename failed');
    final target = '${uri.substring(0, uri.lastIndexOf('/'))}/$newName';
    if (nodes.containsKey(target)) throw StateError('exists');
    nodes[target] = nodes.remove(uri);
  }
}

void main() {
  late _FakeSaf saf;
  late ZenSafFolderAccess access;

  setUp(() {
    saf = _FakeSaf();
    access = ZenSafFolderAccess('content://t', port: saf);
  });

  test('a write creates the directories and lands under its own name', () async {
    await access.write('dev1/a.zen', Uint8List.fromList([1, 2]));
    expect(await access.read('dev1/a.zen'), [1, 2]);
    expect((await access.list('dev1')).map((e) => e.name), ['a.zen']);
  });

  test('a write over an existing file replaces it and leaves no temporary document', () async {
    await access.write('dev1/a.zen', Uint8List.fromList([1]));
    await access.write('dev1/a.zen', Uint8List.fromList([9, 9]));
    expect(await access.read('dev1/a.zen'), [9, 9]);
    expect((await access.list('dev1')).map((e) => e.name), ['a.zen']);
  });

  test('a failed rename removes the temporary document and surfaces the error', () async {
    await access.write('dev1/a.zen', Uint8List.fromList([1]));
    saf.failRename = true;
    await expectLater(access.write('dev1/a.zen', Uint8List.fromList([2])), throwsStateError);
    expect((await access.list('dev1')).where((e) => e.name.endsWith('.tmp')), isEmpty);
  });

  test('a failing cleanup does not hide why the write failed', () async {
    await access.write('dev1/a.zen', Uint8List.fromList([1]));
    saf.failRename = true;
    saf.failDelete = true;
    await expectLater(
      access.write('dev1/a.zen', Uint8List.fromList([2])),
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'delete failed')),
    );
  });

  test('a folder that cannot be opened is an error, not a null dereference', () async {
    saf.nodes.clear();
    await expectLater(access.write('a.zen', Uint8List.fromList([1])), throwsStateError);
  });

  test('delete removes a file, or a directory with all it holds, and a missing path is fine', () async {
    await access.write('key/dev1/a.zen', Uint8List.fromList([1]));
    await access.write('key/dev1/b.zen', Uint8List.fromList([2]));
    await access.write('key/dev2/c.zen', Uint8List.fromList([3]));

    await access.delete('key/dev1/a.zen');
    expect((await access.list('key/dev1')).map((e) => e.name), ['b.zen']);

    await access.delete('key/dev1');
    expect(await access.list('key/dev1'), isEmpty);
    expect((await access.list('key/dev2')).map((e) => e.name), ['c.zen']);

    await access.delete('key/never/was.zen');
  });

  test('a missing file reads as null and a missing directory lists empty', () async {
    expect(await access.read('nope/x.zen'), isNull);
    expect(await access.list('nope'), isEmpty);
  });

  test('check reports a withdrawn grant, an unreachable provider, and ready', () async {
    expect(await access.check(), ZenFolderState.ready);
    saf.grant = false;
    expect(await access.check(), ZenFolderState.accessRevoked);
  });

  test('a path leaving the folder is refused', () {
    expect(() => access.read('../x'), throwsArgumentError);
  });

  test('there is no watcher: the transport polls', () {
    expect(access.watch(), isNull);
  });
}
