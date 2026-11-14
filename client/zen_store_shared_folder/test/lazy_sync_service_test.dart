import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:zen_store/zen_store.dart';

import 'support/devices.dart';
import 'support/lazy_sync_service.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('zen_lazy_service_test'));
  tearDown(() async => root.delete(recursive: true));

  /// [count] devices, each with a replica of the folder of its own, joined by a lazy service.
  Future<(List<Device>, LazySyncService)> world(int count, {int seed = 1}) async {
    final devices = <Device>[];
    for (var i = 0; i < count; i++) {
      devices.add(await openDevice(root, 'd$i', folder: Directory('${root.path}/replica$i')));
    }
    final service = LazySyncService(
      [for (final d in devices) d.folder],
      [for (final d in devices) d.store.deviceId],
      seed: seed,
    );
    return (devices, service);
  }

  /// Alternates sync and delivery until nothing changes any more, with the faults off.
  Future<void> settle(List<Device> devices, LazySyncService service, List<String> ids) async {
    service.behave();
    String? last;
    for (var round = 0; round < 12; round++) {
      await syncAll(devices, rounds: 1);
      await service.pump();
      await syncAll(devices, rounds: 1);
      final now = devices.map((d) => d.snapshot(ids)).join('\n--\n');
      if (now == last) return;
      last = now;
    }
    fail('the devices did not settle');
  }

  test('a delayed file is simply not there yet, and arrives', () async {
    final (devices, service) = await world(2);
    final [a, b] = devices;
    service.delay = 1; // nothing is delivered
    await a.items.put('1', item('late'));
    await a.sync.syncNow();

    await service.pump();
    await b.sync.syncNow();
    expect(b.items.list().dataOrNull, isEmpty);
    expect(b.sync.status.state, ZenSyncState.upToDate);

    service.behave();
    await service.pump();
    await b.sync.syncNow();
    expect(b.items.get('1').dataOrNull?.name, 'late');
  });

  test(
    'a truncated delivery is reported and merges nothing, then the whole file arrives',
    () async {
      final (devices, service) = await world(2);
      final [a, b] = devices;
      service.truncate = 1;
      await a.items.put('1', item('whole'));
      await a.sync.syncNow();
      await service.pump(); // the half file is what b sees
      await b.sync.syncNow();

      expect(b.items.list().dataOrNull, isEmpty);
      expect(b.sync.lastReport!.problems, isNotEmpty);
      expect(b.sync.status.issue, ZenSyncIssue.unreadableRecords);

      service.behave();
      await service.pump();
      await b.sync.syncNow();
      expect(b.items.get('1').dataOrNull?.name, 'whole');
      expect(b.sync.status.state, ZenSyncState.upToDate);
    },
  );

  test(
    'an older version arriving after the newer one changes nothing and conflicts with nothing',
    () async {
      final (devices, service) = await world(2);
      final [a, b] = devices;
      await a.items.put('1', item('v1'));
      await a.sync.syncNow();
      await service.pump(); // the service sees v1
      await b.sync.syncNow();
      await a.items.put('1', item('v2'));
      await a.sync.syncNow();
      await service.pump(); // ...then v2
      await b.sync.syncNow();
      expect(b.items.get('1').dataOrNull?.name, 'v2');

      service.stale = 1; // now it hands b the old v1 file again, over the new one
      await service.pump();
      await b.sync.syncNow();
      await a.sync.syncNow();

      expect(b.items.get('1').dataOrNull?.name, 'v2');
      expect(b.store.conflictCount + a.store.conflictCount, 0);
    },
  );

  test('conflicted copies from the service are ignored and do not disturb sync', () async {
    final (devices, service) = await world(2);
    final [a, b] = devices;
    service.conflictedCopy = 1;
    await a.items.put('1', item('one'));
    await b.items.put('2', item('two'));

    for (var i = 0; i < 3; i++) {
      await syncAll([a, b], rounds: 1);
      await service.pump();
    }
    await syncAll([a, b], rounds: 1);

    expect(a.items.list().dataOrNull, hasLength(2));
    expect(b.items.list().dataOrNull, hasLength(2));
    expect(a.sync.status.state, ZenSyncState.upToDate);
    expect(b.sync.status.state, ZenSyncState.upToDate);
    expect(filesUnder(b.folder).length, greaterThan(2), reason: 'the copies were really written');
  });

  test(
    'the same field edited on two devices is a conflict with both sides, delays or not',
    () async {
      final (devices, service) = await world(2);
      final [a, b] = devices;
      await a.items.put('1', item('start'));
      await a.sync.syncNow();
      await service.pump();
      await syncAll([a, b], rounds: 1);

      service.delay = 0.6;
      await a.items.put('1', item('from a'));
      await b.items.put('1', item('from b'));
      for (var i = 0; i < 4; i++) {
        await syncAll([a, b], rounds: 1);
        await service.pump();
      }
      await settle(devices, service, ['1']);

      for (final device in devices) {
        expect(
          device.items.conflictFor('1').dataOrNull!.sides.map((s) => s.value?.name),
          unorderedEquals(['from a', 'from b']),
        );
      }
    },
  );

  test('a delete against an unseen edit is a conflict on every device', () async {
    final (devices, service) = await world(2);
    final [a, b] = devices;
    await a.items.put('1', item('original'));
    await a.sync.syncNow();
    await settle(devices, service, ['1']);

    service.delay = 0.5;
    service.stale = 0.5;
    await b.items.delete('1');
    await a.items.put('1', item('edited'));
    for (var i = 0; i < 3; i++) {
      await syncAll([a, b], rounds: 1);
      await service.pump();
    }
    await settle(devices, service, ['1']);

    for (final device in devices) {
      final conflict = device.items.conflictFor('1').dataOrNull!;
      expect(conflict.isDeleteConflict, isTrue);
      expect(conflict.sides.map((s) => s.value?.name), contains('edited'));
    }
  });

  for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
    test('three devices, every fault at once, converge to one state (seed $seed)', () async {
      final (devices, service) = await world(3, seed: seed);
      final random = Random(seed * 31);
      final ids = ['r0', 'r1', 'r2', 'r3'];
      service
        ..delay = 0.4
        ..stale = 0.3
        ..truncate = 0.2
        ..conflictedCopy = 0.3;

      for (var step = 0; step < 40; step++) {
        final device = devices[random.nextInt(devices.length)];
        final id = ids[random.nextInt(ids.length)];
        switch (random.nextInt(4)) {
          case 0:
            await device.items.delete(id);
          case 1:
            await device.items.put(
              id,
              item('${device.name} name $step', device.items.get(id).dataOrNull?.version),
            );
          default:
            await device.items.put(
              id,
              item(device.items.get(id).dataOrNull?.name ?? 'new $step', '${device.name} v$step'),
            );
        }
        if (random.nextInt(3) == 0) await device.sync.syncNow();
        if (random.nextInt(4) == 0) await service.pump();
      }
      await settle(devices, service, ids);

      final first = devices.first.snapshot(ids);
      for (final device in devices.skip(1)) {
        expect(device.snapshot(ids), first, reason: '${device.name} differs from d0');
      }
      for (final device in devices) {
        expect(device.sync.status.state, ZenSyncState.upToDate);
      }
    });
  }
}
