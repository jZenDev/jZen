import 'dart:io';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';
import 'package:protobuf/well_known_types/google/protobuf/type.pb.dart';
import 'package:test/test.dart';
import 'package:zen_store/src/zen_merge_policy.dart';
import 'package:zen_store/src/zen_proto_fields.dart';
import 'package:zen_store/src/zen_record_state.dart';
import 'package:zen_store/zen_store.dart';

// Field stands in for an application's message: `number` (3) holds "when" as an integer and
// `packed` (8) holds a bool. The store only ever sees proto bytes.
Field entry({int? at, bool? flag}) => Field(number: at, packed: flag);

/// A group: who revoked, and when (milliseconds, as an int32). Hand-written, as protoc would write it.
class Revocation extends GeneratedMessage {
  factory Revocation({String? by, int? atMs}) {
    final result = Revocation._();
    if (by != null) result.by = by;
    if (atMs != null) result.atMs = atMs;
    return result;
  }
  Revocation._();

  static final BuilderInfo _i = BuilderInfo('Revocation', createEmptyInstance: Revocation.new)
    ..aOS(1, 'by')
    ..a<int>(2, 'atMs', PbFieldType.O3)
    ..hasRequiredFields = false;

  @override
  BuilderInfo get info_ => _i;
  @override
  Revocation createEmptyInstance() => Revocation._();
  @override
  Revocation clone() => Revocation._()..mergeFromMessage(this);

  String get by => $_getSZ(0);
  set by(String value) => $_setString(0, value);
  int get atMs => $_getIZ(1);
  set atMs(int value) => $_setSignedInt32(1, value);
}

/// A record holding a [Revocation] as field 2, beside an unrelated scalar in field 1.
class Reset extends GeneratedMessage {
  factory Reset({String? name, Revocation? revoked}) {
    final result = Reset._();
    if (name != null) result.name = name;
    if (revoked != null) result.revoked = revoked;
    return result;
  }
  Reset._();
  factory Reset.fromBuffer(List<int> data) => Reset._()..mergeFromBuffer(data);

  static final BuilderInfo _i = BuilderInfo('Reset', createEmptyInstance: Reset.new)
    ..aOS(1, 'name')
    ..aOM<Revocation>(2, 'revoked', subBuilder: () => Revocation._())
    ..hasRequiredFields = false;

  @override
  BuilderInfo get info_ => _i;
  @override
  Reset createEmptyInstance() => Reset._();
  @override
  Reset clone() => Reset._()..mergeFromMessage(this);

  String get name => $_getSZ(0);
  set name(String value) => $_setString(0, value);
  Revocation get revoked => $_getN(1);
  set revoked(Revocation value) => setField(2, value);
}

Revocation by(String by, int atMs) => Revocation(by: by, atMs: atMs);

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

  group('a group: a time together with its author', () {
    const byTime = {2: ZenMergePolicy.earliestBy(2)};

    ZenCollection<Reset> resets(ZenStore store, {Map<int, ZenMergePolicy> p = byTime}) =>
        store.collection('resets', Reset.fromBuffer, mergePolicies: p);

    Future<void> revokedOnTwoDevices({required bool reversed, Map<int, ZenMergePolicy>? p}) async {
      final a = await device('a$reversed');
      final b = await device('b$reversed');
      final policy = p ?? byTime;
      await resets(a.$1, p: policy).put('1', Reset(name: 'carry-over'));
      await syncAll([a, b]);
      await resets(a.$1, p: policy).put('1', Reset(name: 'carry-over', revoked: by('a', 2000)));
      await resets(b.$1, p: policy).put('1', Reset(name: 'carry-over', revoked: by('b', 1000)));
      await syncAll([a, b], reversed: reversed);
      for (final (store, _) in [a, b]) {
        expect(store.conflictCount, 0);
        final revoked = resets(store, p: policy).get('1').dataOrNull!.revoked;
        // The whole version of the device that revoked first: its author with its time.
        final expected = policy == byTime ? by('b', 1000) : by('a', 2000);
        expect(revoked.by, expected.by);
        expect(revoked.atMs, expected.atMs);
      }
    }

    test('two devices revoking at two times merge to the earliest whole version', () async {
      await revokedOnTwoDevices(reversed: false);
    });

    test('the result is the same in whichever order the devices sync', () async {
      await revokedOnTwoDevices(reversed: true);
    });

    test('latestBy keeps the whole version with the larger time', () async {
      await revokedOnTwoDevices(reversed: false, p: const {2: ZenMergePolicy.latestBy(2)});
    });

    test('a side that cleared the group is a conflict, not a merge', () async {
      final a = await device('a');
      final b = await device('b');
      await resets(a.$1).put('1', Reset(name: 'x', revoked: by('a', 7)));
      await syncAll([a, b]);
      await resets(a.$1).put('1', Reset(name: 'x', revoked: by('a', 3)));
      await resets(b.$1).put('1', Reset(name: 'x'));
      await syncAll([a, b]);
      expect(resets(a.$1).conflictFor('1').dataOrNull?.fields, {2});
    });

    test('a group whose ordering sub-field is unset is a conflict', () async {
      final a = await device('a');
      final b = await device('b');
      await resets(a.$1).put('1', Reset(name: 'x', revoked: by('a', 7)));
      await syncAll([a, b]);
      await resets(a.$1).put(
        '1',
        Reset(
          name: 'x',
          revoked: Revocation(by: 'a'),
        ),
      );
      await resets(b.$1).put('1', Reset(name: 'x', revoked: by('b', 3)));
      await syncAll([a, b]);
      expect(resets(a.$1).conflictFor('1').dataOrNull?.fields, {2});
    });

    test('declaring another sub-field for the same collection is refused', () async {
      final a = await device('a');
      resets(a.$1);
      expect(() => resets(a.$1, p: const {2: ZenMergePolicy.earliestBy(1)}), throwsArgumentError);
      expect(() => resets(a.$1, p: const {2: ZenMergePolicy.latestBy(2)}), throwsArgumentError);
    });

    test('a sub-field number below 1 is refused', () async {
      final a = await device('a');
      expect(() => resets(a.$1, p: const {2: ZenMergePolicy.earliestBy(0)}), throwsArgumentError);
    });

    group('reading the group', () {
      const policy = ZenMergePolicy.earliestBy(2);

      ZenFieldVersion version(Reset reset, int at, String author) => ZenFieldVersion(
        const ZenVersionVector().bump(author),
        author,
        at,
        splitFields(reset.writeToBuffer())[2],
      );

      test('every other sub-field comes from the winning version', () {
        final early = version(Reset(revoked: by('phone', 10)), 5, 'phone');
        final late = version(Reset(revoked: by('mac', 20)), 1, 'mac');
        expect(applyMergePolicy(policy, [late, early]), same(early));
        expect(applyMergePolicy(policy, [early, late]), same(early));
      });

      test('a Timestamp sub-field orders by seconds, then nanos', () {
        // field 7, a message { 1: string "x", 3: Timestamp { seconds = 1, nanos = 2 } }.
        Uint8List group(int seconds, int nanos) {
          final stamp = [0x08, seconds, 0x10, nanos];
          final inner = [0x0a, 1, 0x78, 0x1a, stamp.length, ...stamp];
          return Uint8List.fromList([0x3a, inner.length, ...inner]);
        }

        ZenFieldVersion v(Uint8List bytes, String author) =>
            ZenFieldVersion(const ZenVersionVector().bump(author), author, 1, bytes);
        final early = v(group(10, 5), 'a');
        final late = v(group(10, 9), 'b');
        expect(applyMergePolicy(const ZenMergePolicy.earliestBy(3), [late, early]), same(early));
        expect(applyMergePolicy(const ZenMergePolicy.latestBy(3), [early, late]), same(late));
      });

      test('a tie on the sub-field is broken the same way in every arrival order', () {
        // Same time, different authors of the revocation, and even the same device and write time.
        final versions = [
          version(Reset(revoked: by('x', 10)), 5, 'a'),
          version(Reset(revoked: by('y', 10)), 5, 'a'),
          version(Reset(revoked: by('z', 10)), 9, 'b'),
          version(Reset(revoked: by('w', 10)), 9, 'c'),
        ];
        final results = <List<int>?>{};
        void permute(List<ZenFieldVersion> rest, List<ZenFieldVersion> done) {
          if (rest.isEmpty) {
            results.add(applyMergePolicy(policy, done)!.bytes);
            return;
          }
          for (var i = 0; i < rest.length; i++) {
            permute([...rest]..removeAt(i), [...done, rest[i]]);
          }
        }

        permute(versions, []);
        expect(results.map((bytes) => bytes.toString()).toSet(), hasLength(1));
        expect(Reset.fromBuffer(results.single!).revoked.by, 'w');
      });

      test(
        'bytes that are not one message, or a sub-field that cannot be read, are left alone',
        () {
          final good = version(Reset(revoked: by('a', 1)), 1, 'a');
          ZenFieldVersion raw(List<int> bytes) => ZenFieldVersion(
            const ZenVersionVector().bump('b'),
            'b',
            2,
            Uint8List.fromList(bytes),
          );
          final cleared = ZenFieldVersion(const ZenVersionVector().bump('b'), 'b', 2, null);
          // A scalar where a message is expected.
          final scalar = raw([0x10, 0x05]);
          // Two occurrences of the field, which proto merges into one message.
          final twice = raw([...good.bytes!, ...good.bytes!]);
          // A message without the ordering sub-field.
          final unset = version(Reset(revoked: Revocation(by: 'b')), 2, 'b');
          // The ordering sub-field is a string, which no policy can order.
          final text = raw([0x12, 0x05, 0x12, 0x03, 0x61, 0x62, 0x63]);
          // A length running past the end.
          final truncated = raw([0x12, 0x09, 0x08]);
          for (final other in [cleared, scalar, twice, unset, text, truncated]) {
            expect(applyMergePolicy(policy, [good, other]), isNull);
            expect(applyMergePolicy(policy, [other, good]), isNull);
          }
        },
      );
    });
  });
}
