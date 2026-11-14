import 'dart:io';
import 'dart:typed_data';

import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

import 'support/devices.dart';

void main() {
  late Directory root;
  late Directory shared;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zen_shared_folder_test');
    shared = Directory('${root.path}/folder');
  });
  tearDown(() async => root.delete(recursive: true));

  group('devices through one folder', () {
    test('a record put on one device appears on the other', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('hello'));

      await syncAll([a, b]);

      expect(b.items.get('1').dataOrNull?.name, 'hello');
    });

    test('edits to different fields merge, and the same field is a conflict', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('start', '1.0'));
      await syncAll([a, b]);

      await a.items.put('1', item('renamed', '1.0'));
      await b.items.put('1', item('start', '2.0'));
      await syncAll([a, b]);
      expect(a.items.get('1').dataOrNull?.name, 'renamed');
      expect(a.items.get('1').dataOrNull?.version, '2.0');
      expect(b.items.get('1').dataOrNull?.name, 'renamed');
      expect(a.store.conflictCount + b.store.conflictCount, 0);

      await a.items.put('1', item('from a', '2.0'));
      await b.items.put('1', item('from b', '2.0'));
      await syncAll([a, b]);
      for (final device in [a, b]) {
        final conflict = device.items.conflictFor('1').dataOrNull!;
        expect(conflict.sides.map((s) => s.value?.name), unorderedEquals(['from a', 'from b']));
      }
    });

    test('a resolution settles the conflict on every device', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('x'));
      await syncAll([a, b]);
      await a.items.put('1', item('from a'));
      await b.items.put('1', item('from b'));
      await syncAll([a, b]);

      final chosen = a.items.conflictFor('1').dataOrNull!.sides.last.value!;
      await a.items.resolve('1', chosen);
      await syncAll([a, b]);

      expect(a.store.conflictCount + b.store.conflictCount, 0);
      expect(b.items.get('1').dataOrNull?.name, chosen.name);
    });

    test('three devices converge, each writing only inside its own directory', () async {
      final devices = [
        for (final n in ['a', 'b', 'c']) await openDevice(root, n),
      ];
      for (final (i, device) in devices.indexed) {
        await device.items.put('rec$i', item('from ${device.name}'));
      }

      await syncAll(devices);

      for (final device in devices) {
        expect(
          device.items.list().dataOrNull!.map((m) => m.name),
          unorderedEquals(['from a', 'from b', 'from c']),
        );
        // Every file it wrote is under its own device id, and nowhere else.
        expect(device.access.writes, isNotEmpty);
        expect(
          device.access.writes.every((p) => p.startsWith('${device.store.deviceId}/')),
          isTrue,
        );
      }
      final top = shared
          .listSync()
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toSet();
      expect(top, devices.map((d) => d.store.deviceId).toSet());
    });

    test('a device keeps a copy of what it merged in its own directory, once', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('only a'));
      await syncAll([a, b]);

      expect(b.access.writes, hasLength(1));
      expect(b.access.writes.single, startsWith('${b.store.deviceId}/'));

      // Once the devices agree, nothing is written again.
      await syncAll([a, b]);
      expect(b.access.writes, hasLength(1));
      expect(a.access.writes, hasLength(1));
    });
  });

  group('what the folder exposes', () {
    test('no plaintext on disk: neither payloads, names, collection nor ids', () async {
      final a = await openDevice(root, 'a');
      final id = a.store.newId();
      await a.items.put(id, item('SuperSecretPayload-12345', 'VersionSecret-777'));
      await a.sync.syncNow();

      final files = filesUnder(shared);
      expect(files, isNotEmpty);
      final needles = ['SuperSecretPayload', 'VersionSecret', 'items', id, 'device a'];
      for (final file in files) {
        final text = String.fromCharCodes(file.readAsBytesSync());
        for (final needle in needles) {
          expect(text, isNot(contains(needle)), reason: '${file.path} leaks "$needle"');
        }
        for (final needle in needles) {
          expect(file.path, isNot(contains(needle)), reason: 'the path leaks "$needle"');
        }
      }
    });

    test('file names are 64 hex characters, directories a 32-hex device id', () async {
      final a = await openDevice(root, 'a');
      await a.items.put('1', item('x'));
      await a.sync.syncNow();

      final files = filesUnder(shared);
      expect(files, hasLength(1));
      expect(files.single.uri.pathSegments.last, matches(RegExp(r'^[0-9a-f]{64}\.zen$')));
      expect(
        files.single.parent.uri.pathSegments.where((s) => s.isNotEmpty).last,
        a.store.deviceId,
      );
    });

    test('a record is rewritten in place, so the folder holds one file per record', () async {
      final a = await openDevice(root, 'a');
      await a.items.put('1', item('one'));
      await a.sync.syncNow();
      await a.items.put('1', item('two'));
      await a.sync.syncNow();

      expect(filesUnder(shared), hasLength(1));
      expect(filesUnder(shared).where((f) => f.path.endsWith('.tmp')), isEmpty);
    });
  });

  group('files that cannot be used are skipped, reported, and retried', () {
    test('a half-delivered file is skipped, named in the report, and merged once whole', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('first'));
      await a.items.put('2', item('second'));
      await a.sync.syncNow();
      final files = filesUnder(shared);
      final victim = files.first;
      final whole = victim.readAsBytesSync();
      victim.writeAsBytesSync(whole.sublist(0, whole.length ~/ 2));

      await b.sync.syncNow();

      // The other record was merged: one unreadable file stops nobody else's.
      expect(b.items.list().dataOrNull, hasLength(1));
      expect(b.sync.lastReport!.problems, hasLength(1));
      expect(b.sync.lastReport!.problems.single.record, endsWith(victim.uri.pathSegments.last));
      expect(b.sync.status.state, ZenSyncState.unavailable);
      expect(b.sync.status.issue, ZenSyncIssue.unreadableRecords);

      victim.writeAsBytesSync(whole);
      await b.sync.syncNow();

      expect(b.items.list().dataOrNull, hasLength(2));
      expect(b.sync.status.state, ZenSyncState.upToDate);
    });

    test('an altered file is never merged', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('real'));
      await a.sync.syncNow();
      final file = filesUnder(shared).single;
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      bytes[bytes.length - 20] ^= 0xff;
      file.writeAsBytesSync(bytes);

      await b.sync.syncNow();

      expect(b.items.list().dataOrNull, isEmpty);
      expect(b.sync.lastReport!.problems, hasLength(1));
    });

    test('a file copied under another device or another name does not merge', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      final c = await openDevice(root, 'c');
      await a.items.put('1', item('real'));
      await a.sync.syncNow();
      final original = filesUnder(shared).single;
      // As if a sync service filed a's file under b's directory, and under another file name.
      final inB = File('${shared.path}/${b.store.deviceId}/${original.uri.pathSegments.last}');
      inB.parent.createSync(recursive: true);
      original.copySync(inB.path);
      final renamed = File('${original.parent.path}/${'0' * 64}.zen');
      original.copySync(renamed.path);

      await c.sync.syncNow();

      expect(c.items.list().dataOrNull, hasLength(1)); // only a's real file merged
      expect(c.sync.lastReport!.problems, hasLength(2));
    });

    test('files written under another sync key are never merged', () async {
      final stranger = await openDevice(root, 'stranger', withSyncKey: otherSyncKey);
      final b = await openDevice(root, 'b');
      await stranger.items.put('1', item('not for you'));
      await stranger.sync.syncNow();

      await b.sync.syncNow();

      expect(b.items.list().dataOrNull, isEmpty);
      expect(b.sync.lastReport!.problems, hasLength(1));
      expect(b.sync.status.issue, ZenSyncIssue.unreadableRecords);
    });

    test('a file from a newer format is left alone and says the app is out of date', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('from the future'));
      await a.sync.syncNow();
      final file = filesUnder(shared).single;
      final bytes = Uint8List.fromList(file.readAsBytesSync())..[3] = 99;
      file.writeAsBytesSync(bytes);

      await b.sync.syncNow();

      expect(b.items.list().dataOrNull, isEmpty);
      expect(b.sync.status.issue, ZenSyncIssue.newerAppVersion);
      expect(b.sync.lastReport!.problems.single.message, contains('99'));
    });

    test('a sync service\'s conflicted copies are ignored by name and cause no problem', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('real'));
      await a.sync.syncNow();
      final original = filesUnder(shared).single;
      final stem = original.uri.pathSegments.last.replaceAll('.zen', '');
      for (final name in [
        '$stem (conflicted copy 2026-11-14).zen',
        '$stem.sync-conflict-20261114-101010-ABCDEFG.zen',
        '$stem-DESKTOP-1.zen',
        '$stem (1).zen',
        '.$stem.zen.1234.tmp',
        '$stem.zen.part',
      ]) {
        original.copySync('${original.parent.path}/$name');
      }
      Directory('${shared.path}/${a.store.deviceId} (conflicted copy)').createSync();
      original.copySync(
        '${shared.path}/${a.store.deviceId} (conflicted copy)/${original.uri.pathSegments.last}',
      );

      await b.sync.syncNow();

      expect(b.items.list().dataOrNull, hasLength(1));
      expect(b.sync.lastReport?.problems ?? const [], isEmpty);
      expect(b.sync.status.state, ZenSyncState.upToDate);
    });
  });

  group('status', () {
    test('a device that is not paired reports so and touches nothing', () async {
      final a = await openDevice(root, 'a', paired: false);
      await a.items.put('1', item('x'));

      await a.sync.syncNow();

      expect(a.sync.status.issue, ZenSyncIssue.notPaired);
      expect(a.sync.status.state, ZenSyncState.unavailable);
      expect(shared.existsSync() ? shared.listSync() : [], isEmpty);
    });

    test('no folder chosen', () async {
      final a = await openDevice(root, 'a', accessFor: (_) => ZenDirectoryAccess(null));

      await a.sync.syncNow();

      expect(a.sync.status.issue, ZenSyncIssue.noFolder);
    });

    test('an unreachable folder reports so, and recovers when it is back', () async {
      final a = await openDevice(root, 'a');
      await a.items.put('1', item('x'));
      await a.syncUntilQuiet();
      expect(a.sync.status.state, ZenSyncState.upToDate);

      final moved = Directory('${root.path}/moved');
      shared.renameSync(moved.path);
      await a.syncUntilQuiet();
      expect(a.sync.status.issue, ZenSyncIssue.folderUnreachable);

      moved.renameSync(shared.path);
      await a.syncUntilQuiet();
      expect(a.sync.status.state, ZenSyncState.upToDate);
    });

    test('a revoked grant reports so and recovers when it is granted again', () async {
      final revoked = _ScriptedAccess(ZenFolderState.accessRevoked);
      final a = await openDevice(root, 'a', accessFor: (_) => revoked);

      await a.sync.syncNow();
      expect(a.sync.status.issue, ZenSyncIssue.accessRevoked);
      expect(revoked.writes, isEmpty);

      revoked.state = ZenFolderState.ready;
      await a.sync.syncNow();
      expect(a.sync.status.state, ZenSyncState.upToDate);
    });

    test(
      'a write that fails is reported, keeps the record unsent, and is sent next time',
      () async {
        final flaky = _ScriptedAccess(ZenFolderState.ready)..failWrites = true;
        final a = await openDevice(root, 'a', accessFor: (_) => flaky);
        await a.items.put('1', item('x'));

        await a.syncUntilQuiet();
        expect(a.sync.status.issue, ZenSyncIssue.other);
        expect(a.store.unsent, isNotEmpty);

        flaky.failWrites = false;
        await a.syncUntilQuiet();
        expect(a.sync.status.state, ZenSyncState.upToDate);
        expect(a.store.unsent, isEmpty);
      },
    );

    test('a folder that never shows our files is reported, not refilled forever', () async {
      final blind = _ScriptedAccess(ZenFolderState.ready);
      final a = await openDevice(root, 'a', accessFor: (_) => _BlindAccess(blind));
      await a.items.put('1', item('x'));
      await a.syncUntilQuiet();
      await a.syncUntilQuiet();
      await a.syncUntilQuiet();

      expect(a.sync.status.issue, ZenSyncIssue.other);
      expect(a.sync.status.message, contains('do not appear'));
      expect(blind.writes.length, lessThan(6));
    });

    test('a sync key of the wrong length is refused', () async {
      final store = (await ZenStore.open(
        Directory('${root.path}/s'),
        deviceName: 'x',
        key: storeKey,
      )).dataOrNull!;
      addTearDown(store.close);

      final result = await ZenSharedFolderSync.start(
        store,
        ZenDirectoryAccess(shared),
        syncKey: [1, 2],
      );

      expect(result.errorOrNull, isA<ZenValidationError>());
    });
  });

  group('devices coming and going', () {
    test('a device removed from the folder and paired again gets everything back', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      final c = await openDevice(root, 'c');
      await a.items.put('a1', item('from a'));
      await b.items.put('b1', item('from b'));
      await c.items.put('c1', item('from c'));
      await syncAll([a, b, c]);

      // c is removed: its directory goes, and the device is erased and joins again as a new one.
      await c.sync.stop();
      await c.store.close();
      Directory('${shared.path}/${c.store.deviceId}').deleteSync(recursive: true);
      await ZenStore.erase(c.storeDirectory);
      final again = await openDevice(root, 'c');
      await syncAll([a, b, again]);

      expect(again.store.deviceId, isNot(c.store.deviceId));
      // c's own record survived because a and b had merged it and published it.
      expect(
        again.items.list().dataOrNull!.map((m) => m.name),
        unorderedEquals(['from a', 'from b', 'from c']),
      );
      expect(a.items.list().dataOrNull, hasLength(3));
      expect(a.store.conflictCount + b.store.conflictCount + again.store.conflictCount, 0);
    });

    test('a device whose directory is gone from the folder sends everything again', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('one'));
      await a.items.put('2', item('two'));
      await syncAll([a, b]);
      Directory('${shared.path}/${a.store.deviceId}').deleteSync(recursive: true);
      // A new person joins knowing only the folder: a fresh store, nothing else.
      final fresh = await openDevice(root, 'fresh');

      await syncAll([a, fresh]);

      expect(filesUnder(Directory('${shared.path}/${a.store.deviceId}')), hasLength(2));
      expect(fresh.items.list().dataOrNull, hasLength(2));
    });

    test('a delete against an edit it never saw is a conflict, never a silent loss', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('original'));
      await syncAll([a, b]);

      await b.items.delete('1');
      await a.items.put('1', item('edited meanwhile'));
      await syncAll([a, b]);

      for (final device in [a, b]) {
        final conflict = device.items.conflictFor('1').dataOrNull!;
        expect(conflict.isDeleteConflict, isTrue);
        expect(conflict.sides.map((s) => s.value?.name), contains('edited meanwhile'));
      }
    });
  });

  group('finding changes', () {
    test('polling brings another device\'s change without a call to syncNow', () async {
      final a = await openDevice(root, 'a');
      final store = (await ZenStore.open(
        Directory('${root.path}/poller'),
        deviceName: 'p',
        key: storeKey,
      )).dataOrNull!;
      final poller = (await ZenSharedFolderSync.start(
        store,
        ZenDirectoryAccess(shared),
        syncKey: syncKey,
        pollEvery: const Duration(milliseconds: 100),
        watch: false,
      )).dataOrNull!;
      addTearDown(() async {
        await poller.stop();
        await store.close();
      });

      await a.items.put('1', item('polled'));
      await a.sync.syncNow();

      await _until(() => store.collection('items', Api.fromBuffer).get('1').dataOrNull != null);
    });

    test('the folder\'s watcher brings it forward without polling', () async {
      final a = await openDevice(root, 'a');
      await a.sync.syncNow(); // the folder exists before anyone watches it
      final store = (await ZenStore.open(
        Directory('${root.path}/watcher'),
        deviceName: 'w',
        key: storeKey,
      )).dataOrNull!;
      final watcher = (await ZenSharedFolderSync.start(
        store,
        ZenDirectoryAccess(shared),
        syncKey: syncKey,
        pollEvery: null,
        watchDebounce: const Duration(milliseconds: 50),
      )).dataOrNull!;
      addTearDown(() async {
        await watcher.stop();
        await store.close();
      });
      await watcher.syncNow();

      await a.items.put('1', item('watched'));
      await a.sync.syncNow();

      await _until(() => store.collection('items', Api.fromBuffer).get('1').dataOrNull != null);
    });

    test('a stopped transport does nothing and reports off', () async {
      final a = await openDevice(root, 'a');
      await a.sync.syncNow();

      await a.sync.stop();
      await a.items.put('1', item('after stop'));
      await a.sync.syncNow();

      expect(a.sync.status, ZenSyncStatus.off);
      expect(filesUnder(shared), isEmpty);
    });
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// An in-memory folder whose state a test sets, and whose writes it can make fail.
final class _ScriptedAccess implements ZenFolderAccess {
  ZenFolderState state;
  bool failWrites = false;
  final List<String> writes = [];
  final Map<String, Uint8List> files = {};
  _ScriptedAccess(this.state);

  @override
  Future<ZenFolderState> check() async => state;
  @override
  Future<List<ZenFolderEntry>> list(String path) async {
    final prefix = path.isEmpty ? '' : '$path/';
    final names = <String, bool>{};
    for (final file in files.keys.where((p) => p.startsWith(prefix))) {
      final rest = file.substring(prefix.length);
      final slash = rest.indexOf('/');
      names[slash < 0 ? rest : rest.substring(0, slash)] = slash >= 0;
    }
    return [
      for (final e in names.entries)
        ZenFolderEntry(
          e.key,
          isDirectory: e.value,
          size: e.value ? 0 : files['$prefix${e.key}']!.length,
        ),
    ];
  }

  @override
  Future<Uint8List?> read(String path) async => files[path];
  @override
  Future<void> write(String path, Uint8List bytes) async {
    if (failWrites) throw const FileSystemException('disk full');
    writes.add(path);
    files[path] = bytes;
  }

  @override
  Stream<void>? watch() => null;
}

/// A folder that takes writes and never lists them: a sync service that is not working.
final class _BlindAccess implements ZenFolderAccess {
  final _ScriptedAccess inner;
  _BlindAccess(this.inner);

  @override
  Future<ZenFolderState> check() => inner.check();
  @override
  Future<List<ZenFolderEntry>> list(String path) async => const [];
  @override
  Future<Uint8List?> read(String path) => inner.read(path);
  @override
  Future<void> write(String path, Uint8List bytes) => inner.write(path, bytes);
  @override
  Stream<void>? watch() => null;
}
