import 'dart:io';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';
import 'package:protobuf/well_known_types/google/protobuf/type.pb.dart' show Field_Kind;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/src/zen_proto_fields.dart';
import 'package:zen_store/zen_store.dart';

// Hand-built stand-ins for what protoc would emit for
//   message Detail   { optional uint32 days = 1; bool on = 2; }
//   message Reminder { bool enabled = 1; optional uint32 lead_days = 2; Field.Kind channel = 3;
//                      oneof kind { int32 kind_int = 4; string kind_str = 5; } Detail detail = 6; }
//   message Plan     { string name = 1; Reminder reminder = 8; repeated Reminder history = 9; }
// so the test needs no generated file; the runtime behaves the same.
class Detail extends GeneratedMessage {
  Detail({int? days, bool? on}) {
    if (days != null) setField(1, days);
    if (on != null) setField(2, on);
  }
  Detail._();

  static final BuilderInfo _i =
      BuilderInfo('Detail', package: const PackageName('test'), createEmptyInstance: Detail._)
        ..a<int>(1, 'days', PbFieldType.OU3)
        ..aOB(2, 'on');

  @override
  BuilderInfo get info_ => _i;
  @override
  Detail createEmptyInstance() => Detail._();
  @override
  Detail clone() => Detail._()..mergeFromMessage(this);
  static Detail fromBuffer(List<int> bytes) => Detail._()..mergeFromBuffer(bytes);
}

class Reminder extends GeneratedMessage {
  Reminder({bool? enabled, int? leadDays, Field_Kind? channel, int? kindInt, Detail? detail}) {
    if (enabled != null) setField(1, enabled);
    if (leadDays != null) setField(2, leadDays);
    if (channel != null) setField(3, channel);
    if (kindInt != null) setField(4, kindInt);
    if (detail != null) setField(6, detail);
  }
  Reminder._();

  static final BuilderInfo _i =
      BuilderInfo('Reminder', package: const PackageName('test'), createEmptyInstance: Reminder._)
        ..aOB(1, 'enabled')
        ..a<int>(2, 'leadDays', PbFieldType.OU3)
        ..e<Field_Kind>(
          3,
          'channel',
          PbFieldType.OE,
          defaultOrMaker: Field_Kind.TYPE_UNKNOWN,
          valueOf: Field_Kind.valueOf,
          enumValues: Field_Kind.values,
        )
        ..a<int>(4, 'kindInt', PbFieldType.O3)
        ..aOS(5, 'kindStr')
        ..oo(0, [4, 5])
        ..aOM<Detail>(6, 'detail', subBuilder: Detail._);

  @override
  BuilderInfo get info_ => _i;
  @override
  Reminder createEmptyInstance() => Reminder._();
  @override
  Reminder clone() => Reminder._()..mergeFromMessage(this);
  static Reminder fromBuffer(List<int> bytes) => Reminder._()..mergeFromBuffer(bytes);

  int get leadDays => $_getIZ(1);
  int get kindInt => $_getIZ(3);
  bool hasKindInt() => $_has(3);
  Detail get detail => $_getN(5);
}

class Plan extends GeneratedMessage {
  Plan({String? name, Reminder? reminder, Iterable<Reminder>? history}) {
    if (name != null) setField(1, name);
    if (reminder != null) setField(8, reminder);
    if (history != null) (getField(9) as List).addAll(history);
  }
  Plan._();

  static final BuilderInfo _i =
      BuilderInfo('Plan', package: const PackageName('test'), createEmptyInstance: Plan._)
        ..aOS(1, 'name')
        ..aOM<Reminder>(8, 'reminder', subBuilder: Reminder._)
        ..pc<Reminder>(9, 'history', PbFieldType.PM, subBuilder: Reminder._);

  @override
  BuilderInfo get info_ => _i;
  @override
  Plan createEmptyInstance() => Plan._();
  @override
  Plan clone() => Plan._()..mergeFromMessage(this);
  static Plan fromBuffer(List<int> bytes) => Plan._()..mergeFromBuffer(bytes);

  String get name => $_getSZ(0);
  Reminder get reminder => $_getN(1);
}

final List<int> key = List.generate(32, (i) => i);

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('zen_store_nested_test'));
  tearDown(() async => root.delete(recursive: true));

  Future<(ZenStore, ZenFolderCloud)> device(String name) async {
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

  Future<void> syncAll(List<(ZenStore, ZenFolderCloud)> devices) async {
    for (var round = 0; round < 2; round++) {
      for (final (_, cloud) in devices) {
        await cloud.syncNow();
      }
    }
  }

  ZenCollection<Plan> plans(
    ZenStore s, {
    Set<int> explicit = const {},
    Map<int, ZenPresence> nested = const {},
  }) => s.collection('plans', Plan.fromBuffer, explicitPresence: explicit, explicitNested: nested);

  test('an implicit default inside a nested message is not versioned', () async {
    final a = await device('a');
    final b = await device('b');
    await plans(a.$1).put('p', Plan(name: 'n', reminder: Reminder(leadDays: 2)));
    await plans(b.$1).put('p', Plan(name: 'n', reminder: Reminder(enabled: false, leadDays: 2)));
    await syncAll([a, b]);

    expect(a.$1.conflictCount, 0);
    expect(b.$1.conflictCount, 0);
    expect(plans(a.$1).get('p').dataOrNull?.reminder.leadDays, 2);
    expect(plans(b.$1).get('p').dataOrNull?.reminder.leadDays, 2);
  });

  test('a nested optional field declared explicit keeps 0 apart from unset', () async {
    final a = await device('a');
    final b = await device('b');
    const explicit = {
      8: ZenPresence({2}),
    };
    await plans(
      a.$1,
      nested: explicit,
    ).put('p', Plan(name: 'n', reminder: Reminder(enabled: true, leadDays: 5)));
    await syncAll([a, b]);
    await plans(
      a.$1,
      nested: explicit,
    ).put('p', Plan(name: 'n', reminder: Reminder(enabled: true, leadDays: 0)));
    await plans(
      b.$1,
      nested: explicit,
    ).put('p', Plan(name: 'n', reminder: Reminder(enabled: true)));
    await syncAll([a, b]);

    expect(a.$1.conflictCount, 1);
    expect(b.$1.conflictCount, 1);
  });

  test('without the declaration the same two writes agree', () async {
    final a = await device('a');
    final b = await device('b');
    await plans(a.$1).put('p', Plan(name: 'n', reminder: Reminder(enabled: true, leadDays: 5)));
    await syncAll([a, b]);
    await plans(a.$1).put('p', Plan(name: 'n', reminder: Reminder(enabled: true, leadDays: 0)));
    await plans(b.$1).put('p', Plan(name: 'n', reminder: Reminder(enabled: true)));
    await syncAll([a, b]);

    expect(a.$1.conflictCount, 0);
    expect(b.$1.conflictCount, 0);
  });

  group('declaring', () {
    test('a different nested path than before throws', () async {
      final a = await device('a');
      plans(
        a.$1,
        nested: {
          8: const ZenPresence({2}),
        },
      );
      expect(() => plans(a.$1), throwsArgumentError);
      expect(
        () => plans(
          a.$1,
          nested: {
            8: const ZenPresence({1}),
          },
        ),
        throwsArgumentError,
      );
    });

    test('a path naming a missing or non-message field throws', () async {
      final a = await device('a');
      expect(
        () => plans(
          a.$1,
          nested: {
            99: const ZenPresence({2}),
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => plans(
          a.$1,
          nested: {
            1: const ZenPresence({2}),
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => plans(
          a.$1,
          nested: {
            9: const ZenPresence({2}),
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => plans(
          a.$1,
          nested: {
            8: const ZenPresence({99}),
          },
        ),
        throwsArgumentError,
      );
      expect(() => plans(a.$1, explicit: {99}), throwsArgumentError);
      expect(
        () => plans(
          a.$1,
          nested: {
            8: const ZenPresence({}, {
              2: ZenPresence({1}),
            }),
          },
        ),
        throwsArgumentError,
      );
    });
  });

  group('splitMessage', () {
    Uint8List split(Plan p, [ZenPresence presence = ZenPresence.none]) =>
        joinFields(splitMessage(p, presence));

    test('a top-level-only message is byte for byte what it was', () {
      final plan = Plan(name: 'n', reminder: Reminder(enabled: true, leadDays: 2));
      expect(joinFields(splitMessage(plan, ZenPresence.none)), plan.writeToBuffer());
      final flat = Plan(name: 'n');
      expect(joinFields(splitMessage(flat, ZenPresence.none)), flat.writeToBuffer());
      expect(splitMessage(Plan(), ZenPresence.none), isEmpty);
    });

    test('deep nesting: {8: {6: {1}}} keeps days 0, drops on false', () {
      final plan = Plan(reminder: Reminder(detail: Detail(days: 0, on: false)));
      final plain = Plan.fromBuffer(split(plan));
      expect(plain.reminder.detail.writeToBuffer(), isEmpty);
      final kept = Plan.fromBuffer(
        split(
          plan,
          const ZenPresence({}, {
            8: ZenPresence({}, {
              6: ZenPresence({1}),
            }),
          }),
        ),
      );
      expect(kept.reminder.detail.writeToBuffer(), [8, 0]);
    });

    test('a nested enum at its default is left out', () {
      final plan = Plan(reminder: Reminder(channel: Field_Kind.TYPE_UNKNOWN, leadDays: 2));
      expect(Plan.fromBuffer(split(plan)).reminder.writeToBuffer(), [16, 2]);
    });

    test('the mixed form: a top-level and a nested optional field together', () {
      final plan = Plan(name: '', reminder: Reminder(leadDays: 0));
      const mixed = ZenPresence(
        {1},
        {
          8: ZenPresence({2}),
        },
      );
      final out = Plan.fromBuffer(split(plan, mixed));
      expect(out.hasField(1), isTrue);
      expect(out.reminder.hasField(2), isTrue);
      final bare = Plan.fromBuffer(split(plan));
      expect(bare.hasField(1), isFalse);
      expect(bare.reminder.hasField(2), isFalse);
    });

    test('unknown fields inside a nested message survive', () {
      // name = 'n', then field 8 (length 5): enabled = false, unknown field 50 = varint 7.
      final withUnknown = Plan.fromBuffer([10, 1, 110, 66, 5, 8, 0, 144, 3, 7]);
      final out = Plan.fromBuffer(split(withUnknown));
      expect(out.reminder.unknownFields.getField(50)!.varints.single.toInt(), 7);
      expect(out.reminder.hasField(1), isFalse);
    });

    test('a set but empty nested message stays present', () {
      final plan = Plan(reminder: Reminder(enabled: false));
      final out = Plan.fromBuffer(split(plan));
      expect(out.hasField(8), isTrue);
      expect(out.reminder.writeToBuffer(), isEmpty);
    });

    test('a oneof member set to its default is kept, nested and not', () {
      final plan = Plan(reminder: Reminder(kindInt: 0));
      final out = Plan.fromBuffer(split(plan));
      expect(out.reminder.hasKindInt(), isTrue);
      expect(out.reminder.kindInt, 0);
    });

    test('messages in a repeated field are not normalised', () {
      final plan = Plan(history: [Reminder(enabled: false, leadDays: 2)]);
      expect(split(plan), plan.writeToBuffer());
    });
  });

  test('a record stored before normalisation does not conflict with an edit elsewhere', () async {
    final a = await device('a');
    final b = await device('b');
    final old = Plan(name: 'n', reminder: Reminder(enabled: false, leadDays: 2));
    // What an older build stored: the nested bytes as the runtime wrote them, explicit default
    // and all.
    await a.$1.write<void>(
      'plans',
      'p',
      (_) => ZenResult.ok((splitFields(old.writeToBuffer()), null)),
    );
    await syncAll([a, b]);

    // This build edits another field of the record with the same nested value; the other device
    // changes the nested message itself.
    await plans(b.$1).put('p', Plan(name: 'm', reminder: Reminder(enabled: false, leadDays: 2)));
    await plans(a.$1).put('p', Plan(name: 'n', reminder: Reminder(enabled: false, leadDays: 3)));
    await syncAll([a, b]);

    expect(a.$1.conflictCount, 0);
    expect(b.$1.conflictCount, 0);
    final merged = plans(a.$1).get('p').dataOrNull!;
    expect(merged.name, 'm');
    expect(merged.reminder.leadDays, 3);
  });

  test('the same through ZenBatch.put and writeAll', () async {
    final a = await device('a');
    final b = await device('b');
    final old = Plan(name: 'n', reminder: Reminder(enabled: false, leadDays: 2));
    await a.$1.write<void>(
      'plans',
      'p',
      (_) => ZenResult.ok((splitFields(old.writeToBuffer()), null)),
    );
    await syncAll([a, b]);

    final batch = ZenBatch()
      ..put(plans(b.$1), 'p', Plan(name: 'm', reminder: Reminder(enabled: false, leadDays: 2)));
    expect((await b.$1.writeAll(batch)).errorOrNull, isNull);
    await plans(a.$1).put('p', Plan(name: 'n', reminder: Reminder(enabled: false, leadDays: 3)));
    await syncAll([a, b]);

    expect(a.$1.conflictCount, 0);
    expect(b.$1.conflictCount, 0);
    final merged = plans(a.$1).get('p').dataOrNull!;
    expect(merged.name, 'm');
    expect(merged.reminder.leadDays, 3);
  });
}
