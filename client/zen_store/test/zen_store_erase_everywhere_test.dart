import 'dart:io';

import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

final List<int> key = List.generate(32, (i) => i);

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('zen_store_erase_test'));
  tearDown(() async => root.delete(recursive: true));

  Directory dir(String name) => Directory('${root.path}/$name');

  Future<ZenStore> open(String name) async =>
      (await ZenStore.open(dir(name), deviceName: name, key: key)).dataOrNull!;

  ZenCollection<Api> items(ZenStore store) => store.collection('items', Api.fromBuffer);

  test('erasing everywhere removes every record and every unsent change', () async {
    final store = await open('a');
    await items(store).put('1', Api(name: 'x'));
    expect(store.unsent, isNotEmpty);

    expect(await store.eraseEverywhere(), isA<ZenSuccess<void>>());

    expect(store.erasedEverywhere, isTrue);
    expect(items(store).list().dataOrNull, isEmpty);
    expect(items(store).get('1').errorOrNull, isA<ZenNotFoundError>());
    expect(store.unsent, isEmpty);
    expect(store.transportState, isNull);
  });

  test('an erased store refuses writes, batches and merges, by name', () async {
    final store = await open('a');
    await store.eraseEverywhere();

    expect((await items(store).put('1', Api(name: 'x'))).errorOrNull, isA<ZenStorageError>());
    expect(
      (await store.writeAll(ZenBatch()..put(items(store), '2', Api(name: 'y')))).errorOrNull,
      isA<ZenStorageError>(),
    );
    final result = await store.receive(const []);
    expect(result.errorOrNull, isA<ZenStorageError>());
    expect(result.errorOrNull!.message, contains('erased everywhere'));
  });

  test('the mark survives a restart, and no record comes back', () async {
    final store = await open('a');
    await items(store).put('1', Api(name: 'x'));
    await store.eraseEverywhere();
    await store.close();

    final reopened = await open('a');

    expect(reopened.erasedEverywhere, isTrue);
    expect(items(reopened).list().dataOrNull, isEmpty);
  });

  test('erasing twice is fine, and announces itself once', () async {
    final store = await open('a');
    var announced = 0;
    store.erasures.listen((_) => announced++);

    await store.eraseEverywhere();
    expect(await store.eraseEverywhere(), isA<ZenSuccess<void>>());
    await Future<void>.delayed(Duration.zero);

    expect(announced, 1);
  });

  test('a store opened in an erased directory after ZenStore.erase starts fresh', () async {
    final store = await open('a');
    await store.eraseEverywhere();
    await store.close();
    await ZenStore.erase(dir('a'));

    final fresh = await open('a');

    expect(fresh.erasedEverywhere, isFalse);
    expect((await items(fresh).put('1', Api(name: 'again'))), isA<ZenSuccess<void>>());
  });

  group('through the development folder', () {
    Future<(ZenStore, ZenFolderCloud)> device(String name) async {
      final store = await open(name);
      final cloud = (await ZenFolderCloud.start(store, dir('cloud'), pollEvery: null)).dataOrNull!;
      addTearDown(cloud.stop);
      return (store, cloud);
    }

    test('one device erases, and the others erase at their next sync', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', Api(name: 'x'));
      for (final (_, cloud) in [a, b, a]) {
        await cloud.syncNow();
      }
      expect(items(b.$1).get('1').dataOrNull?.name, 'x');

      expect(await a.$2.eraseEverywhere(), isA<ZenSuccess<void>>());
      await b.$2.syncNow();

      expect(b.$1.erasedEverywhere, isTrue);
      expect(items(b.$1).list().dataOrNull, isEmpty);
      expect(b.$2.status.issue, ZenSyncIssue.erasedEverywhere);
      final left = Directory(dir('cloud').path).listSync(recursive: true).whereType<File>();
      expect(left.map((f) => f.uri.pathSegments.last), unorderedEquals(['lock', 'erased']));
    });
  });
}
