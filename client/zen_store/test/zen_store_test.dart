import 'dart:convert';
import 'dart:io';

import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

// Api stands in for an application's message: two independent text fields (name, version) are
// all these tests need, and the store only ever sees proto bytes.
Api item(String name, [String? version]) => Api(name: name, version: version);

final List<int> key = List.generate(32, (i) => i);

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('zen_store_test'));
  tearDown(() async => root.delete(recursive: true));

  Directory dir(String name) => Directory('${root.path}/$name');

  Future<ZenStore> open(String name, {int Function()? now, List<int>? withKey}) async {
    final result = await ZenStore.open(
      dir(name),
      deviceName: 'device $name',
      key: withKey ?? key,
      now: now,
    );
    return result.dataOrNull ?? (throw StateError('open failed: ${result.errorOrNull}'));
  }

  /// A device: a store and the folder cloud it syncs through, synced only when a test says so.
  Future<(ZenStore, ZenFolderCloud)> device(String name, {int Function()? now}) async {
    final store = await open(name, now: now);
    final cloud = (await ZenFolderCloud.start(store, dir('cloud'), pollEvery: null)).dataOrNull!;
    addTearDown(cloud.stop);
    return (store, cloud);
  }

  ZenCollection<Api> items(ZenStore store) => store.collection('items', Api.fromBuffer);

  Future<void> syncAll(List<(ZenStore, ZenFolderCloud)> devices) async {
    for (var round = 0; round < 2; round++) {
      for (final (_, cloud) in devices) {
        await cloud.syncNow();
      }
    }
  }

  group('one device', () {
    test('a put is read back by get and list, ordered by id', () async {
      final store = await open('a');

      await items(store).put('2', item('second'));
      await items(store).put('1', item('first'));

      expect(items(store).get('1').dataOrNull?.name, 'first');
      expect(items(store).list().dataOrNull?.map((n) => n.name), ['first', 'second']);
    });

    test('a missing or deleted record is not found, and delete returns what it held', () async {
      final store = await open('a');
      await items(store).put('1', item('gone soon'));

      final deleted = await items(store).delete('1');

      expect(deleted.dataOrNull?.name, 'gone soon');
      expect(items(store).get('1').errorOrNull, isA<ZenNotFoundError>());
      expect((await items(store).delete('1')).errorOrNull, isA<ZenNotFoundError>());
      expect(items(store).list().dataOrNull, isEmpty);
    });

    test('a field cleared by a put is cleared, not kept from before', () async {
      final store = await open('a');
      await items(store).put('1', item('x', '1.0'));

      await items(store).put('1', item('x'));

      expect(items(store).get('1').dataOrNull?.hasVersion(), isFalse);
    });

    test('ids, collection names, device names and keys that cannot work are refused', () async {
      final store = await open('a');

      for (final id in ['', 'has space', 'ü', 'x' * 191]) {
        expect((await items(store).put(id, item('x'))).errorOrNull, isA<ZenValidationError>());
      }
      expect(() => store.collection('Items', Api.fromBuffer), throwsArgumentError);
      expect(
        (await ZenStore.open(dir('b'), deviceName: ' ', key: key)).errorOrNull,
        isA<ZenValidationError>(),
      );
      expect(
        (await ZenStore.open(dir('b'), deviceName: 'b', key: [1, 2, 3])).errorOrNull,
        isA<ZenValidationError>(),
      );
    });

    test('what was written survives a reopen, under the same device', () async {
      final first = await open('a');
      await items(first).put('1', item('kept'));
      await first.close();

      final second = await open('a');

      expect(second.deviceId, first.deviceId);
      expect(items(second).get('1').dataOrNull?.name, 'kept');
    });

    test('a write after close fails rather than being dropped', () async {
      final store = await open('a');
      await store.close();

      expect((await items(store).put('1', item('late'))).errorOrNull, isA<ZenStorageError>());
    });

    test('a collection reports its own writes and not another collection\'s', () async {
      final store = await open('a');
      final events = <void>[];
      final subscription = items(store).changes.listen(events.add);

      await items(store).put('1', item('x'));
      await store.collection('other', Api.fromBuffer).put('1', item('y'));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      await subscription.cancel();
    });

    test('resolving a record that has no conflict is refused', () async {
      final store = await open('a');
      await items(store).put('1', item('x'));

      expect((await items(store).resolve('1', item('y'))).errorOrNull, isA<ZenValidationError>());
    });

    test('a write is unsent until a transport acknowledges exactly what it sent', () async {
      final store = await open('a');
      await items(store).put('1', item('first'));
      final sent = store.outgoing('items:1')!;
      await items(store).put('1', item('second'));

      await store.acknowledge([ZenAcknowledgedRecord('items:1', sent.payload, null)]);
      expect(store.unsent, {'items:1'});

      final latest = store.outgoing('items:1')!;
      await store.acknowledge([ZenAcknowledgedRecord('items:1', latest.payload, null)]);
      expect(store.unsent, isEmpty);
    });

    test('unsent records and transport state survive a restart', () async {
      final first = await open('a');
      await items(first).put('1', item('x'));
      await first.saveTransportState(utf8.encode('token-7'));
      await first.close();

      final second = await open('a');

      expect(second.unsent, {'items:1'});
      expect(utf8.decode(second.transportState!), 'token-7');
    });
  });

  group('encryption at rest', () {
    Future<List<File>> filesOf(String name) async => [
      for (final entity in await dir(name).list(recursive: true).toList())
        if (entity is File) entity,
    ];

    test('no file but the device id holds the data in readable form', () async {
      final store = await open('a');
      await items(store).put('1', item('Secret salary 9000', 'IBAN UA00'));
      await store.close();

      for (final file in await filesOf('a')) {
        final bytes = await file.readAsBytes();
        final text = latin1.decode(bytes);
        expect(text, isNot(contains('Secret')), reason: file.path);
        expect(text, isNot(contains('U2VjcmV0')), reason: '${file.path} holds it in base64');
        if (!file.path.endsWith('device.id')) {
          expect(bytes.take(4), 'ZEN1'.codeUnits, reason: file.path);
        }
      }
    });

    test('the wrong key refuses to open, and leaves every file as it was', () async {
      final store = await open('a');
      await items(store).put('1', item('x'));
      await store.close();
      final before = {for (final f in await filesOf('a')) f.path: await f.readAsBytes()};

      final wrong = await ZenStore.open(dir('a'), deviceName: 'a', key: List.filled(32, 7));

      expect(wrong.errorOrNull, isA<ZenStorageError>());
      expect(wrong.errorOrNull?.message, contains('does not decrypt'));
      for (final f in await filesOf('a')) {
        expect(await f.readAsBytes(), before[f.path], reason: f.path);
      }
    });

    test('a single altered byte is caught, not decrypted into something else', () async {
      final store = await open('a');
      await items(store).put('1', item('x'));
      await store.close();
      final shard = (await filesOf('a')).firstWhere((f) => f.path.contains('records'));
      final bytes = await shard.readAsBytes();
      bytes[bytes.length - 20] ^= 1;
      await shard.writeAsBytes(bytes);

      expect(
        (await open('a').then<Object?>((s) => s, onError: (Object e) => e)),
        isA<StateError>(),
      );
    });

    test('a shard copied over another is caught, so records cannot be moved', () async {
      final store = await open('a');
      for (var i = 0; i < 200; i++) {
        await items(store).put('$i', item('x$i'));
      }
      await store.close();
      final shards = (await filesOf('a')).where((f) => f.path.contains('records')).toList();
      await shards[0].writeAsBytes(await shards[1].readAsBytes());

      final reopened = await ZenStore.open(dir('a'), deviceName: 'a', key: key);
      expect(reopened.errorOrNull, isA<ZenStorageError>());
    });

    test('erase is the deliberate way back from a lost key, and starts empty', () async {
      final store = await open('a');
      await items(store).put('1', item('x'));
      await store.close();

      expect((await ZenStore.erase(dir('a'))).isSuccess, isTrue);
      final fresh = await open('a', withKey: List.filled(32, 9));

      expect(items(fresh).list().dataOrNull, isEmpty);
    });
  });

  group('two devices: what merges on its own', () {
    test('a record written on one device appears on the other', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('from a'));

      await syncAll([a, b]);

      expect(items(b.$1).get('1').dataOrNull?.name, 'from a');
      expect(a.$2.status.state, ZenSyncState.upToDate);
      expect(a.$1.unsent, isEmpty);
    });

    test('edits made one after another, each having seen the last, never conflict', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('one'));
      await syncAll([a, b]);
      await items(b.$1).put('1', item('two'));
      await syncAll([a, b]);
      await items(a.$1).put('1', item('three'));
      await syncAll([a, b]);

      expect(items(b.$1).get('1').dataOrNull?.name, 'three');
      expect(a.$1.conflictCount + b.$1.conflictCount, 0);
    });

    test('offline edits to different fields of one record are both kept', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('draft', '1.0'));
      await syncAll([a, b]);

      await items(a.$1).put('1', item('final', '1.0'));
      await items(b.$1).put('1', item('draft', '2.0'));
      await syncAll([a, b]);

      for (final (store, _) in [a, b]) {
        expect(items(store).get('1').dataOrNull, item('final', '2.0'));
        expect(store.conflictCount, 0);
      }
    });

    test(
      'a save refused for a stale change tag is merged and sent again, as CloudKit makes it',
      () async {
        final a = await device('a');
        final b = await device('b');
        await items(a.$1).put('1', item('draft', '1.0'));
        await syncAll([a, b]);
        await items(a.$1).put('1', item('final', '1.0'));
        await a.$2.syncNow();

        // b has not fetched a's save, so its tag is stale: the folder refuses it like CloudKit.
        await items(b.$1).put('1', item('draft', '2.0'));
        await b.$2.syncNow();

        expect(items(b.$1).get('1').dataOrNull, item('final', '2.0'));
        expect(b.$1.unsent, isEmpty);
      },
    );

    test('the same edit made on two devices is not a conflict', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('x'));
      await syncAll([a, b]);

      await items(a.$1).put('1', item('same'));
      await items(b.$1).put('1', item('same'));
      await syncAll([a, b]);

      expect(a.$1.conflictCount, 0);
    });

    test('a delete made after seeing every edit removes the record everywhere', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('x'));
      await syncAll([a, b]);

      await items(b.$1).delete('1');
      await syncAll([a, b]);

      expect(items(a.$1).get('1').errorOrNull, isA<ZenNotFoundError>());
      expect(a.$1.conflictCount, 0);
    });

    test('a device installed from nothing receives everything', () async {
      final a = await device('a');
      await items(a.$1).put('1', item('one'));
      await items(a.$1).put('2', item('two'));
      await a.$2.syncNow();

      final fresh = await device('reinstalled');
      await fresh.$2.syncNow();

      expect(items(fresh.$1).list().dataOrNull?.map((n) => n.name), ['one', 'two']);
    });

    test('what a sync brought stays on the device, readable with no transport', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('offline copy'));
      await syncAll([a, b]);
      await b.$2.stop();
      await b.$1.close();

      final offline = await open('b');

      expect(items(offline).get('1').dataOrNull?.name, 'offline copy');
    });

    test('the transport picks up a local write on its own', () async {
      final a = await device('a');

      await items(a.$1).put('1', item('auto'));
      await a.$2.syncNow();

      expect(a.$1.unsent, isEmpty);
    });
  });

  group('two devices: what only a person may decide', () {
    test(
      'one field set differently on two devices is a conflict, and every side is kept',
      () async {
        var clock = 1000;
        final a = await device('a', now: () => clock);
        final b = await device('b', now: () => clock);
        await items(a.$1).put('1', item('original', '1.0'));
        await syncAll([a, b]);

        clock = 2000;
        await items(a.$1).put('1', item('from a', '1.0'));
        clock = 3000;
        await items(b.$1).put('1', item('from b', '1.0'));
        await syncAll([a, b]);

        final conflict = items(b.$1).conflictFor('1').dataOrNull!;
        expect(conflict.fields, {1});
        expect(conflict.sides.map((s) => s.deviceName), ['device b', 'device a']);
        expect(conflict.sides.map((s) => s.value?.name), ['from b', 'from a']);
        expect(conflict.sides.first.at, DateTime.fromMillisecondsSinceEpoch(3000));
        expect(items(a.$1).conflictFor('1').dataOrNull, isNotNull);
      },
    );

    test('a record in conflict is still shown, but refuses writes until it is resolved', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('original'));
      await syncAll([a, b]);
      await items(a.$1).put('1', item('from a'));
      await items(b.$1).put('1', item('from b'));
      await syncAll([a, b]);

      expect(items(a.$1).get('1').isSuccess, isTrue);
      expect((await items(a.$1).put('1', item('sneak'))).errorOrNull, isA<ZenConflictError>());
      expect((await items(a.$1).delete('1')).errorOrNull, isA<ZenConflictError>());
    });

    test('a resolution settles the conflict on every device', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('original'));
      await syncAll([a, b]);
      await items(a.$1).put('1', item('from a'));
      await items(b.$1).put('1', item('from b'));
      await syncAll([a, b]);

      final chosen = items(a.$1).conflictFor('1').dataOrNull!.sides.last.value!;
      await items(a.$1).resolve('1', chosen);
      await syncAll([a, b]);

      for (final (store, _) in [a, b]) {
        expect(store.conflictCount, 0);
        expect(items(store).get('1').dataOrNull, chosen);
      }
    });

    test('a delete against an edit that never saw it is a conflict, never a silent loss', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('original', '1.0'));
      await syncAll([a, b]);

      await items(a.$1).delete('1');
      await items(b.$1).put('1', item('original', '2.0'));
      await syncAll([a, b]);

      final conflict = items(a.$1).conflictFor('1').dataOrNull!;
      expect(conflict.isDeleteConflict, isTrue);
      expect(conflict.sides.firstWhere((s) => s.device == a.$1.deviceId).isDelete, isTrue);
      expect(items(a.$1).get('1').dataOrNull, item('original', '2.0'));
      expect(
        items(b.$1).conflictFor('1').dataOrNull!.sides.firstWhere((s) => !s.isDelete).value,
        item('original', '2.0'),
      );

      await items(a.$1).resolve('1', null);
      await syncAll([a, b]);
      expect(items(b.$1).get('1').errorOrNull, isA<ZenNotFoundError>());
      expect(b.$1.conflictCount, 0);
    });

    test('a conflict outlives a restart', () async {
      final a = await device('a');
      final b = await device('b');
      await items(a.$1).put('1', item('original'));
      await syncAll([a, b]);
      await items(a.$1).put('1', item('from a'));
      await items(b.$1).put('1', item('from b'));
      await syncAll([a, b]);
      await a.$2.stop();
      await a.$1.close();

      final reopened = await open('a');

      expect(reopened.conflictCount, 1);
      expect(items(reopened).conflicts().dataOrNull, hasLength(1));
    });

    test('three devices editing one field each keep all three sides', () async {
      final devices = [await device('a'), await device('b'), await device('c')];
      await items(devices[0].$1).put('1', item('original'));
      await syncAll(devices);

      for (final (store, _) in devices) {
        await items(store).put('1', item('from ${store.deviceName}'));
      }
      await syncAll(devices);

      expect(items(devices[1].$1).conflictFor('1').dataOrNull?.sides, hasLength(3));
    });
  });

  group('what the transport hands over', () {
    test('a record from a newer app version is reported and skipped; the rest merge', () async {
      final store = await open('a');
      final good = await open('b');
      await items(good).put('2', item('fine'));

      final report = (await store.receive([
        ZenIncomingRecord('items:1', utf8.encode(jsonEncode({'format': 99, 'record': {}})), null),
        ZenIncomingRecord('items:2', good.outgoing('items:2')!.payload, null),
      ])).dataOrNull!;

      expect(report.problems.single.record, 'items:1');
      expect(report.problems.single.message, contains('newer'));
      expect(items(store).get('2').dataOrNull?.name, 'fine');
    });

    test('forgetting the transport marks every record to be sent again', () async {
      final a = await device('a');
      await items(a.$1).put('1', item('x'));
      await items(a.$1).put('2', item('y'));
      await a.$2.syncNow();
      expect(a.$1.unsent, isEmpty);

      await a.$1.forgetTransport();

      expect(a.$1.unsent, {'items:1', 'items:2'});
      expect(a.$1.transportState, isNull);
    });
  });
}
