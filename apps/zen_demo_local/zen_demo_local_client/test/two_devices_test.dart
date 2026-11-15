import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';

import 'package:zen_demo_local_client/generated/zen_demo_local/v1/chore.pb.dart';

import 'support/two_devices.dart';

/// The Local mode end to end on the host: two app sessions, each with its own encrypted store,
/// joined through each transport a build can run here. Every behaviour the demo exists to show.
void main() {
  for (final kind in TransportKind.values) {
    group(kind.name, () {
      late TwoDevices devices;

      setUp(() async => devices = await TwoDevices.create(kind));
      tearDown(() async => devices.dispose());

      Future<String> makeChore() async {
        final chore = Chore(id: devices.laptop.newId(), title: 'Water plants', note: 'Fern too');
        expect((await devices.laptop.chores.save(chore)).isSuccess, isTrue);
        await devices.sync();
        return chore.id;
      }

      test('a chore made on one device appears on the other', () async {
        final id = await makeChore();
        expect(devices.phone.chores.get(id)?.title, 'Water plants');
      });

      test('edits to different fields made offline merge, nothing is asked', () async {
        final id = await makeChore();

        await devices.laptop.chores.save(
          devices.laptop.chores.get(id)!.deepCopy()..note = 'Fern and cactus',
        );
        await devices.phone.chores.save(
          devices.phone.chores.get(id)!.deepCopy()..priority = Priority.PRIORITY_HIGH,
        );
        await devices.sync();

        for (final device in [devices.laptop, devices.phone]) {
          final chore = device.chores.get(id)!;
          expect(chore.note, 'Fern and cactus');
          expect(chore.priority, Priority.PRIORITY_HIGH);
          expect(device.store.conflictCount, 0);
        }
      });

      test('the same field edited on both is a conflict until the person chooses', () async {
        final id = await makeChore();

        await devices.laptop.chores.save(
          devices.laptop.chores.get(id)!.deepCopy()..title = 'Water the plants',
        );
        await devices.phone.chores.save(
          devices.phone.chores.get(id)!.deepCopy()..title = 'Water the ferns',
        );
        await devices.sync();

        expect(devices.laptop.store.conflictCount, 1);
        expect(devices.phone.store.conflictCount, 1);
        // Nothing is overwritten while it waits: a save over the record is refused.
        final refused = await devices.phone.chores.save(
          devices.phone.chores.get(id)!.deepCopy()..done = true,
        );
        expect(refused.errorOrNull, isA<ZenConflictError>());

        final conflict = devices.laptop.chores.collection.conflicts().dataOrNull!.single;
        expect(
          conflict.sides.map((side) => side.value?.title),
          containsAll(['Water the plants', 'Water the ferns']),
        );
        final keep = conflict.sides.firstWhere((side) => side.value?.title == 'Water the ferns');
        await devices.laptop.chores.collection.resolve(id, keep.value);
        await devices.sync();

        expect(devices.laptop.store.conflictCount, 0);
        expect(devices.phone.store.conflictCount, 0);
        expect(devices.phone.chores.get(id)!.title, 'Water the ferns');
      });

      test(
        'a delete against an edit is a conflict, and keeping the edit keeps the chore',
        () async {
          final id = await makeChore();

          await devices.laptop.chores.remove(id);
          await devices.phone.chores.save(
            devices.phone.chores.get(id)!.deepCopy()..note = 'Also the basil',
          );
          await devices.sync();

          expect(devices.laptop.store.conflictCount, 1);
          final conflict = devices.laptop.chores.collection.conflicts().dataOrNull!.single;
          expect(conflict.sides.any((side) => side.isDelete), isTrue);
          final keepEdit = conflict.sides.firstWhere((side) => !side.isDelete);
          await devices.laptop.chores.collection.resolve(id, keepEdit.value);
          await devices.sync();

          expect(devices.phone.chores.get(id)?.note, 'Also the basil');
          expect(devices.laptop.chores.get(id)?.note, 'Also the basil');
        },
      );

      test('erasing one device\'s copy leaves the other, which sends it back', () async {
        final id = await makeChore();

        expect((await devices.phone.eraseThisDevice()).isSuccess, isTrue);
        expect(devices.phone.chores.get(id), isNull);
        await devices.sync();

        expect(devices.laptop.chores.get(id)?.title, 'Water plants');
        expect(devices.phone.chores.get(id)?.title, 'Water plants');
      });
    });
  }
}
