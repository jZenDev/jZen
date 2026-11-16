import 'dart:io';
import 'dart:typed_data';

import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

// Api stands in for an application's message: `name` (field 1) and `version` (field 4) are plain
// proto3 strings, which is all implicit presence needs. `version` is declared explicit where a
// test wants the other behaviour.
Api item(String name, [String? version]) => Api(name: name, version: version);

final List<int> key = List.generate(32, (i) => i);

const int _versionField = 4;

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('zen_store_presence_test'));
  tearDown(() async => root.delete(recursive: true));

  Directory dir(String name) => Directory('${root.path}/$name');

  Future<ZenStore> open(String name, {Future<void> Function(int, int)? afterFileReplaced}) async {
    final result = await ZenStore.open(
      dir(name),
      deviceName: 'device $name',
      key: key,
      afterFileReplaced: afterFileReplaced,
    );
    return result.dataOrNull ?? (throw StateError('open failed: ${result.errorOrNull}'));
  }

  Future<(ZenStore, ZenFolderCloud)> device(String name) async {
    final store = await open(name);
    final cloud = (await ZenFolderCloud.start(store, dir('cloud'), pollEvery: null)).dataOrNull!;
    addTearDown(cloud.stop);
    return (store, cloud);
  }

  Future<void> syncAll(List<(ZenStore, ZenFolderCloud)> devices) async {
    for (var round = 0; round < 2; round++) {
      for (final (_, cloud) in devices) {
        await cloud.syncNow();
      }
    }
  }

  ZenCollection<Api> items(ZenStore store, {Set<int> explicitPresence = const {}}) =>
      store.collection('items', Api.fromBuffer, explicitPresence: explicitPresence);

  group('implicit presence (#245)', () {
    test('the runtime really writes an explicit default, which the store must not version', () {
      expect(Api(version: '').writeToBuffer(), isNotEmpty);
      expect(Api().writeToBuffer(), isEmpty);
    });

    test('a field set to its default records no version and is no edit', () async {
      final store = await open('a');
      await items(store).put('r', item('n', 'v1'));

      // The same record rebuilt by something that assigns every field: `version` is the only
      // difference, and `description`-like defaults ride along.
      final rebuilt = Api(name: 'n', version: 'v1', methods: const [])..mixins.clear();
      final before = store.outgoing('items:r')!.payload;
      await items(store).put('r', rebuilt);
      expect(store.outgoing('items:r')!.payload, before);

      await items(store).put('r', Api(name: 'n', version: ''));
      await items(store).put('r', Api(name: 'n')..clearVersion());
      expect(items(store).get('r').dataOrNull?.version, '');
    });

    test('two devices clearing one field by "" and by clear() merge without a conflict', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('r', item('n', 'x'));
      await syncAll([a, b]);

      await items(a.$1).put('r', Api(name: 'n', version: ''));
      await items(b.$1).put('r', Api(name: 'n')..clearVersion());
      await syncAll([a, b]);

      expect(a.$1.conflictCount, 0);
      expect(b.$1.conflictCount, 0);
      expect(items(a.$1).get('r').dataOrNull?.version, '');
      expect(items(b.$1).get('r').dataOrNull?.version, '');
    });

    test('a field declared with explicit presence keeps "set to the default" apart', () async {
      final a = await device('a');
      final b = await device('b');
      final explicit = {_versionField};
      await items(a.$1, explicitPresence: explicit).put('r', item('n', 'x'));
      await syncAll([a, b]);

      await items(a.$1, explicitPresence: explicit).put('r', Api(name: 'n', version: ''));
      await items(b.$1, explicitPresence: explicit).put('r', Api(name: 'n')..clearVersion());
      await syncAll([a, b]);

      expect(a.$1.conflictCount, 1);
    });

    test('the same collection declared with other explicit-presence fields throws', () async {
      final store = await open('a');
      items(store);

      expect(() => items(store, explicitPresence: {1}), throwsArgumentError);
    });
  });

  group('write precondition (#251)', () {
    ZenError? mustExist(Api? current) =>
        current != null ? null : const ZenNotFoundError('items/r does not exist.');

    /// B deletes `r` after seeing it, and A has not yet heard of it: the payload A will receive.
    Future<(ZenStore, ZenIncomingRecord)> deletedElsewhere() async {
      final a = await open('a');
      final b = await open('b');
      await items(a).put('r', item('n', 'v'));
      await items(a).put('s', item('other'));
      await b.receive([ZenIncomingRecord('items:r', a.outgoing('items:r')!.payload, null)]);
      await items(b).delete('r');
      return (a, ZenIncomingRecord('items:r', b.outgoing('items:r')!.payload, null));
    }

    test('a put whose check runs after a queued receive of a delete does not resurrect', () async {
      final (a, theirDelete) = await deletedElsewhere();
      expect(items(a).get('r').isSuccess, isTrue); // the application's own check would pass here

      final received = a.receive([theirDelete]);
      final put = items(a).put('r', item('edited'), expect: mustExist);

      expect((await put).errorOrNull, isA<ZenNotFoundError>());
      expect((await received).isSuccess, isTrue);
      expect(items(a).get('r').errorOrNull, isA<ZenNotFoundError>());
      expect(a.conflictCount, 0);
    });

    test('a batch with a failing expectation writes nothing', () async {
      final (a, theirDelete) = await deletedElsewhere();

      final received = a.receive([theirDelete]);
      final batch = ZenBatch()
        ..put(items(a), 's', item('changed'))
        ..put(items(a), 'r', item('edited'), expect: mustExist);
      final result = await a.writeAll(batch);
      await received;

      expect(result.errorOrNull, isA<ZenNotFoundError>());
      expect(items(a).get('s').dataOrNull?.name, 'other');
      expect(items(a).get('r').errorOrNull, isA<ZenNotFoundError>());
    });

    test('delete expectations see the record and can refuse', () async {
      final store = await open('a');
      await items(store).put('r', item('keep'));

      final refused = await items(store).delete(
        'r',
        expect: (current) => current?.name == 'keep' ? const ZenValidationError('kept') : null,
      );
      final batchRefused = await store.writeAll(
        ZenBatch()
          ..delete(items(store), 'r', expect: (current) => const ZenValidationError('kept too')),
      );

      expect(refused.errorOrNull?.message, 'kept');
      expect(batchRefused.errorOrNull?.message, 'kept too');
      expect(items(store).get('r').isSuccess, isTrue);
    });

    test('without expect, put behaves as before', () async {
      final store = await open('a');

      expect((await items(store).put('r', item('first'))).isSuccess, isTrue);
      expect((await items(store).put('r', item('second'))).dataOrNull?.name, 'second');
    });

    test('an expectation passing lets the write through', () async {
      final store = await open('a');
      await items(store).put('r', item('first'));

      final result = await items(store).put('r', item('second'), expect: mustExist);

      expect(result.dataOrNull?.name, 'second');
    });
  });

  group('device-only collections (#252)', () {
    ZenCollection<Api> records(ZenStore store) => store.collection('records', Api.fromBuffer);
    ZenCollection<Api> sessions(ZenStore store) =>
        store.collection('sessions', Api.fromBuffer, syncs: false);

    test('a batch stopped half way leaves both collections or neither', () async {
      for (final replaced in [1, 2]) {
        final name = 'crash$replaced';
        var armed = false;
        final crashing = await open(
          name,
          afterFileReplaced: (count, total) async {
            if (armed && count == replaced) throw const FileSystemException('power lost');
          },
        );
        await records(crashing).put('seed', item('seed'));
        armed = true;
        final batch = ZenBatch()
          ..put(records(crashing), 'r1', item('one'))
          ..put(sessions(crashing), 's1', item('session'));

        // The journal is saved before the first rename, so whichever file the crash follows, the
        // batch is finished on reopen.
        final result = await crashing.writeAll(batch);
        expect(result.errorOrNull, isA<ZenStorageError>());

        final reopened = await open(name);
        final hasRecord = records(reopened).get('r1').isSuccess;
        final hasSession = sessions(reopened).get('s1').isSuccess;
        expect(hasRecord, hasSession, reason: 'after $replaced files replaced');
        expect(hasRecord, isTrue, reason: 'a saved journal is finished');
      }
    });

    test('a second device gets the records and nothing of the sessions', () async {
      final a = await device('a');
      final b = await device('b');
      await a.$1.writeAll(
        ZenBatch()
          ..put(records(a.$1), 'r1', item('statement row'))
          ..put(sessions(a.$1), 's1', item('bank statement text')),
      );
      sessions(b.$1);

      await syncAll([a, b]);

      expect(records(b.$1).get('r1').dataOrNull?.name, 'statement row');
      expect(sessions(b.$1).list().dataOrNull, isEmpty);
      expect(a.$1.unsent.where((n) => n.startsWith('sessions:')), isEmpty);
      expect(a.$1.outgoing('sessions:s1'), isNull);
      final shared = dir('cloud').listSync(recursive: true).whereType<File>();
      for (final file in shared) {
        expect(file.path, isNot(contains('sessions')));
        expect(_contains(file.readAsBytesSync(), 'sessions'), isFalse, reason: file.path);
      }
    });

    test('a device-only record offered by a transport is refused', () async {
      final a = await open('a');
      final b = await open('b');
      // On b the same collection syncs, so b can produce a payload for it.
      await b.collection('sessions', Api.fromBuffer).put('s1', item('x'));
      sessions(a);

      final report = await a.receive([
        ZenIncomingRecord('sessions:s1', b.outgoing('sessions:s1')!.payload, null),
      ]);

      expect(report.dataOrNull?.problems, hasLength(1));
      expect(sessions(a).list().dataOrNull, isEmpty);
    });

    test('a collection declared both ways throws', () async {
      final store = await open('a');
      sessions(store);

      expect(() => store.collection('sessions', Api.fromBuffer), throwsArgumentError);
    });
  });
}

bool _contains(Uint8List bytes, String needle) {
  final text = String.fromCharCodes(bytes);
  return text.contains(needle);
}
