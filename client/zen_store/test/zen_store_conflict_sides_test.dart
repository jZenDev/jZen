import 'dart:io';

import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:protobuf/well_known_types/google/protobuf/source_context.pb.dart';
import 'package:test/test.dart';
import 'package:zen_store/zen_store.dart';

/// Whatever a person might be asked to choose between must be in `ZenConflict.sides`: a value the
/// store still holds but no side shows cannot be seen, counted or chosen.
///
/// Api stands in for an application's message. `sourceContext` (field 5) is a nested message, so
/// it is versioned as one group, the way a ledger entry's account and amount would be; `name`
/// (field 1) and `version` (field 4) are two further, independent fields.
Api posting(String group, {String name = 'Groceries', String? version}) => Api(
  name: name,
  version: version,
  sourceContext: SourceContext(fileName: group),
);

void main() {
  late Directory root;
  late int clock;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zen_store_sides');
    clock = 1000;
  });
  tearDown(() async => root.delete(recursive: true));

  Future<ZenStore> open(String name) async {
    final store = (await ZenStore.open(
      Directory('${root.path}/$name'),
      deviceName: name,
      key: List.generate(32, (i) => i),
      now: () => clock,
    )).dataOrNull!;
    addTearDown(store.close);
    return store;
  }

  ZenCollection<Api> items(ZenStore store) => store.collection('items', Api.fromBuffer);

  /// One sync: the device is online only inside this call, so what it writes between two calls
  /// is made without having seen the others.
  Future<void> sync(ZenStore store) async {
    final cloud = (await ZenFolderCloud.start(
      store,
      Directory('${root.path}/cloud'),
      pollEvery: null,
    )).dataOrNull!;
    await cloud.syncNow();
    await cloud.stop();
  }

  Future<void> syncAll(List<ZenStore> stores) async {
    for (var round = 0; round < 3; round++) {
      for (final store in stores) {
        await sync(store);
      }
    }
  }

  Future<void> put(ZenStore store, Api value, {required int at}) async {
    clock = at;
    expect((await items(store).put('1', value)).errorOrNull, isNull);
  }

  ZenConflict<Api> conflictOn(ZenStore store) => items(store).conflictFor('1').dataOrNull!;

  /// Everything a side says, so that two devices can be compared side for side.
  List<(String, int, Api?)> sidesOn(ZenStore store) => [
    for (final side in conflictOn(store).sides)
      (side.deviceName, side.at.millisecondsSinceEpoch, side.value),
  ];

  Set<String?> groupsOn(ZenStore store) => {
    for (final side in conflictOn(store).sides) side.value?.sourceContext.fileName,
  };

  /// Steps 1 to 4: both devices change the group to the same value, the laptop merges the two
  /// into one version attributed to the phone, and the phone changes it again without having
  /// received that merge. Returns the two stores, not yet synced at the end.
  Future<(ZenStore, ZenStore)> sameAuthorTwice({int Function(int)? at}) async {
    final time = at ?? (int t) => t;
    final laptop = await open('Laptop');
    final phone = await open('Phone');
    await put(laptop, posting('wallet -1000'), at: time(1000));
    await syncAll([laptop, phone]);
    await put(laptop, posting('bank -1000'), at: time(2000));
    await put(phone, posting('bank -1000'), at: time(3000));
    await sync(phone);
    await sync(laptop);
    await put(phone, posting('bank -1800'), at: time(4000));
    return (laptop, phone);
  }

  group('two surviving values written under one device', () {
    test('every device answers both of them', () async {
      final (laptop, phone) = await sameAuthorTwice();

      await syncAll([laptop, phone]);

      for (final store in [laptop, phone]) {
        expect(conflictOn(store).fields, {5});
        expect(groupsOn(store), {'bank -1000', 'bank -1800'}, reason: store.deviceName);
        expect(conflictOn(store).sides.map((side) => side.device), everyElement(phone.deviceId));
      }
      expect(sidesOn(laptop), sidesOn(phone));
      // Latest first, each side dated by the write that made its value.
      expect(sidesOn(phone).map((side) => (side.$2, side.$3!.sourceContext.fileName)), [
        (4000, 'bank -1800'),
        (3000, 'bank -1000'),
      ]);
    });

    test('a third device that changed the field offline adds its value for all three', () async {
      final laptop = await open('Laptop');
      final phone = await open('Phone');
      final tablet = await open('Tablet');
      await put(laptop, posting('wallet -1000'), at: 1000);
      await syncAll([laptop, phone, tablet]);
      await put(tablet, posting('safe -1000'), at: 1500);
      await put(laptop, posting('bank -1000'), at: 2000);
      await put(phone, posting('bank -1000'), at: 3000);
      await sync(phone);
      await sync(laptop);
      await put(phone, posting('bank -1800'), at: 4000);

      await syncAll([laptop, phone, tablet]);

      for (final store in [laptop, phone, tablet]) {
        expect(groupsOn(store), {
          'bank -1000',
          'bank -1800',
          'safe -1000',
        }, reason: store.deviceName);
        expect(sidesOn(store), sidesOn(laptop), reason: store.deviceName);
      }
    });

    test('two values one device wrote in the same millisecond read the same everywhere', () async {
      // The phone's second write carries the time of its first, so time and device cannot order
      // the two values, only their bytes can.
      final (laptop, phone) = await sameAuthorTwice(at: (t) => t == 4000 ? 3000 : t);

      await syncAll([laptop, phone]);

      expect(groupsOn(laptop), {'bank -1000', 'bank -1800'});
      expect(conflictOn(laptop).sides.map((side) => side.device), everyElement(phone.deviceId));
      expect(sidesOn(laptop), sidesOn(phone));
      expect(items(laptop).get('1').dataOrNull, items(phone).get('1').dataOrNull);
    });

    test('the value shown by neither side before can be chosen, on every device', () async {
      final (laptop, phone) = await sameAuthorTwice();
      await syncAll([laptop, phone]);

      // On the laptop, 'bank -1800' is the value no side used to hold.
      final side = conflictOn(laptop).sides
          .singleWhere((side) => side.value?.sourceContext.fileName == 'bank -1800');
      clock = 5000;
      expect((await items(laptop).resolve('1', side.value)).errorOrNull, isNull);
      await syncAll([laptop, phone]);

      for (final store in [laptop, phone]) {
        expect(store.conflictCount, 0);
        expect(items(store).get('1').dataOrNull, side.value);
      }
    });

    test('a conflict read back after a restart answers the same sides', () async {
      final (laptop, phone) = await sameAuthorTwice();
      await syncAll([laptop, phone]);
      final before = sidesOn(laptop);
      await laptop.close();

      expect(sidesOn(await open('Laptop')), before);
    });
  });

  group('several fields in conflict', () {
    test('each surviving value of each field is in some side of its device', () async {
      final laptop = await open('Laptop');
      final phone = await open('Phone');
      await put(laptop, posting('wallet', name: 'old', version: '1'), at: 1000);
      await syncAll([laptop, phone]);
      await put(laptop, posting('bank', name: 'same'), at: 2000);
      await put(phone, posting('bank', name: 'same'), at: 3000);
      await sync(phone);
      await sync(laptop);
      // The phone changes the group but not the name; the laptop, holding the merge, changes
      // the name: the group has two versions under the phone, the name one under the laptop.
      await put(phone, posting('safe', name: 'same'), at: 4000);
      await put(laptop, posting('bank', name: 'laptop name'), at: 5000);
      await sync(laptop);
      await put(phone, posting('safe', name: 'phone name'), at: 6000);

      await syncAll([laptop, phone]);

      for (final store in [laptop, phone]) {
        final conflict = conflictOn(store);
        expect(conflict.fields, {1, 5});
        expect({for (final s in conflict.sides) s.value?.name}, {'laptop name', 'phone name'});
        expect(groupsOn(store), {'bank', 'safe'});
        expect(sidesOn(store), sidesOn(laptop));
      }
    });
  });

  group('a delete against an edit', () {
    test('a device that deleted and then wrote the record again has both sides', () async {
      final laptop = await open('Laptop');
      final phone = await open('Phone');
      await put(laptop, posting('wallet'), at: 1000);
      await syncAll([laptop, phone]);
      // Both delete; the laptop merges the two deletes into one, attributed to the phone, and
      // the phone writes the record again without having received that merge.
      clock = 2000;
      await items(laptop).delete('1');
      clock = 3000;
      await items(phone).delete('1');
      await sync(phone);
      await sync(laptop);
      await put(phone, posting('bank'), at: 4000);

      await syncAll([laptop, phone]);

      for (final store in [laptop, phone]) {
        final conflict = conflictOn(store);
        expect(conflict.isDeleteConflict, isTrue);
        expect(conflict.sides.map((s) => (s.deviceName, s.value?.sourceContext.fileName)), [
          ('Phone', 'bank'),
          ('Phone', null),
        ], reason: store.deviceName);
        expect(sidesOn(store), sidesOn(laptop));
      }
    });

    test('a device whose disputed edit it then deleted has the delete and the edit', () async {
      final laptop = await open('Laptop');
      final phone = await open('Phone');
      await put(laptop, posting('wallet', name: 'old'), at: 1000);
      await syncAll([laptop, phone]);
      await put(laptop, posting('wallet', name: 'laptop name'), at: 2000);
      await sync(laptop);
      await put(phone, posting('wallet', name: 'phone name'), at: 2500);
      await sync(phone);
      // The laptop has not received the phone's edit, so it may still delete.
      clock = 3000;
      expect((await items(laptop).delete('1')).errorOrNull, isNull);

      await syncAll([laptop, phone]);

      for (final store in [laptop, phone]) {
        expect(conflictOn(store).fields, {1});
        expect(conflictOn(store).sides.map((s) => (s.deviceName, s.value?.name)), [
          ('Laptop', null),
          ('Phone', 'phone name'),
          ('Laptop', 'laptop name'),
        ], reason: store.deviceName);
        expect(sidesOn(store), sidesOn(laptop));
      }
    });

    test('an edit that only cleared a field has a side beside the delete', () async {
      final laptop = await open('Laptop');
      final phone = await open('Phone');
      await put(laptop, posting('wallet', version: '1'), at: 1000);
      await syncAll([laptop, phone]);
      clock = 2000;
      await items(laptop).delete('1');
      await put(phone, posting('wallet'), at: 3000);

      await syncAll([laptop, phone]);

      for (final store in [laptop, phone]) {
        expect(conflictOn(store).sides.map((s) => (s.deviceName, s.value)), [
          ('Phone', posting('wallet')),
          ('Laptop', null),
        ], reason: store.deviceName);
      }
    });
  });
}
