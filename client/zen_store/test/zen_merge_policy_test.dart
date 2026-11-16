import 'dart:io';
import 'dart:typed_data';

import 'package:protobuf/well_known_types/google/protobuf/type.pb.dart';
import 'package:test/test.dart';
import 'package:zen_store/src/zen_merge_policy.dart';
import 'package:zen_store/src/zen_proto_fields.dart';
import 'package:zen_store/src/zen_record_state.dart';
import 'package:zen_store/zen_store.dart';

// Field stands in for an application's message: `number` (3) holds "when" as an integer and
// `packed` (8) holds a bool. The store only ever sees proto bytes.
Field entry({int? at, bool? flag}) => Field(number: at, packed: flag);

final List<int> key = List.generate(32, (i) => i);
const policies = {3: ZenMergePolicy.earliest, 8: ZenMergePolicy.or};

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('zen_merge_policy_test'));
  tearDown(() async => root.delete(recursive: true));

  Future<(ZenStore, ZenFolderCloud)> device(
    String name, {
    Map<int, ZenMergePolicy> mergePolicies = policies,
  }) async {
    final store = (await ZenStore.open(
      Directory('${root.path}/$name'),
      deviceName: name,
      key: key,
    )).dataOrNull!;
    final cloud = (await ZenFolderCloud.start(
      store,
      Directory('${root.path}/cloud'),
      pollEvery: null,
    )).dataOrNull!;
    addTearDown(cloud.stop);
    return (store, cloud);
  }

  ZenCollection<Field> entries(ZenStore store, {Map<int, ZenMergePolicy> p = policies}) =>
      store.collection('entries', Field.fromBuffer, mergePolicies: p);

  Future<void> syncAll(List<(ZenStore, ZenFolderCloud)> devices, {bool reversed = false}) async {
    final order = reversed ? devices.reversed.toList() : devices;
    for (var round = 0; round < 2; round++) {
      for (final (_, cloud) in order) {
        await cloud.syncNow();
      }
    }
  }

  test('the same intent at two times merges to the earliest, without a conflict', () async {
    final a = await device('a');
    final b = await device('b');
    await entries(a.$1).put('1', entry(at: 0, flag: false));
    await syncAll([a, b]);

    await entries(a.$1).put('1', entry(at: 2000, flag: true));
    await entries(b.$1).put('1', entry(at: 1000, flag: true));
    await syncAll([a, b]);

    for (final (store, _) in [a, b]) {
      expect(entries(store).get('1').dataOrNull, entry(at: 1000, flag: true));
      expect(store.conflictCount, 0);
    }
  });

  test(
    'or keeps true against the default, and the result is the same whoever syncs first',
    () async {
      for (final reversed in [false, true]) {
        final a = await device('a$reversed');
        final b = await device('b$reversed');
        await entries(a.$1).put('1', entry(flag: false));
        await syncAll([a, b]);
        await entries(a.$1).put('1', entry(flag: true));
        await entries(b.$1).put('1', entry(at: 5));
        await syncAll([a, b], reversed: reversed);

        expect(entries(a.$1).get('1').dataOrNull, entry(at: 5, flag: true));
        expect(entries(b.$1).get('1').dataOrNull, entry(at: 5, flag: true));
        expect(a.$1.conflictCount + b.$1.conflictCount, 0);
      }
    },
  );

  test('a clock cannot choose: the earlier value wins whichever device wrote it later', () async {
    var clockA = 9000;
    var clockB = 1;
    final storeA = (await ZenStore.open(
      Directory('${root.path}/ca'),
      deviceName: 'a',
      key: key,
      now: () => clockA,
    )).dataOrNull!;
    final storeB = (await ZenStore.open(
      Directory('${root.path}/cb'),
      deviceName: 'b',
      key: key,
      now: () => clockB,
    )).dataOrNull!;
    final cloudA = (await ZenFolderCloud.start(
      storeA,
      Directory('${root.path}/cloud'),
      pollEvery: null,
    )).dataOrNull!;
    final cloudB = (await ZenFolderCloud.start(
      storeB,
      Directory('${root.path}/cloud'),
      pollEvery: null,
    )).dataOrNull!;
    addTearDown(cloudA.stop);
    addTearDown(cloudB.stop);
    await entries(storeA).put('1', entry(at: 100));
    await entries(storeB).put('1', entry(at: 200));
    for (var i = 0; i < 2; i++) {
      await cloudB.syncNow();
      await cloudA.syncNow();
    }
    expect(entries(storeA).get('1').dataOrNull, entry(at: 100));
    expect(entries(storeB).get('1').dataOrNull, entry(at: 100));
  });

  test('a field without a policy still conflicts', () async {
    final a = await device('a');
    final b = await device('b');
    await entries(a.$1).put('1', Field(name: 'x'));
    await syncAll([a, b]);
    await entries(a.$1).put('1', Field(name: 'y'));
    await entries(b.$1).put('1', Field(name: 'z'));
    await syncAll([a, b]);
    expect(entries(a.$1).conflictFor('1').dataOrNull?.fields, {4});
  });

  test('a policy cannot merge a side that cleared the field: that stays a conflict', () async {
    final a = await device('a');
    final b = await device('b');
    await entries(a.$1).put('1', entry(at: 7));
    await syncAll([a, b]);
    await entries(a.$1).put('1', entry(at: 3));
    await entries(b.$1).put('1', entry());
    await syncAll([a, b]);
    expect(entries(a.$1).conflictFor('1').dataOrNull?.fields, {3});
  });

  test('a policy declared after the conflict arose settles it', () async {
    final a = await device('a');
    final b = await device('b');
    await entries(a.$1, p: const {}).put('1', entry(at: 7));
    await syncAll([a, b]);
    await entries(a.$1, p: const {}).put('1', entry(at: 9));
    await entries(b.$1, p: const {}).put('1', entry(at: 8));
    await syncAll([a, b]);
    expect(a.$1.conflictCount, 1);

    expect(entries(a.$1).get('1').dataOrNull, entry(at: 8));
    expect(a.$1.conflictCount, 0);
  });

  test('declaring a collection twice with different policies is refused', () async {
    final a = await device('a');
    entries(a.$1);
    expect(() => entries(a.$1, p: const {3: ZenMergePolicy.latest}), throwsArgumentError);
  });

  group('reading the field', () {
    ZenFieldVersion version(List<int> bytes, int at, String author) => ZenFieldVersion(
      const ZenVersionVector().bump(author),
      author,
      at,
      Uint8List.fromList(bytes),
    );

    test('a Timestamp message compares by seconds, then nanos', () {
      Uint8List stamp(int s, int n) {
        // field 9, length-delimited: a Timestamp { seconds = 1, nanos = 2 } (values under 128).
        final inner = [0x08, s, 0x10, n];
        return Uint8List.fromList([0x4a, inner.length, ...inner]);
      }

      final early = ZenFieldVersion(const ZenVersionVector().bump('a'), 'a', 1, stamp(10, 5));
      final late = ZenFieldVersion(const ZenVersionVector().bump('b'), 'b', 2, stamp(10, 9));
      expect(applyMergePolicy(ZenMergePolicy.earliest, [late, early]), same(early));
      expect(applyMergePolicy(ZenMergePolicy.latest, [early, late]), same(late));
    });

    test('bytes that are not a scalar are left to a person', () {
      final text = version(splitFields(Field(name: 'x').writeToBuffer())[4]!, 1, 'a');
      final other = version(splitFields(Field(name: 'y').writeToBuffer())[4]!, 2, 'b');
      expect(applyMergePolicy(ZenMergePolicy.earliest, [text, other]), isNull);
    });
  });
}
