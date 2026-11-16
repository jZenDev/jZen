import 'dart:io';

import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

import 'support/devices.dart';

void main() {
  late Directory root;
  late Directory shared;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zen_shared_folder_erase_test');
    shared = Directory('${root.path}/folder');
  });
  tearDown(() async => root.delete(recursive: true));

  /// Every file under the folder, as `<key id>/<device id>/<name>` with the ids shortened to what
  /// a test can read: the file name only.
  List<String> names(Directory folder) => [
    for (final file in filesUnder(folder)) file.uri.pathSegments.last,
  ];

  group('erase everywhere', () {
    test('this device erases, and its files leave the folder but for a marker', () async {
      final a = await openDevice(root, 'a');
      await a.items.put('1', item('secret'));
      await a.sync.syncNow();
      expect(filesUnder(shared), hasLength(1));

      final result = await a.sync.eraseEverywhere();

      expect(result, isA<ZenSuccess<void>>());
      expect(a.store.erasedEverywhere, isTrue);
      expect(a.items.list().dataOrNull, isEmpty);
      expect(names(shared), ['erased.zen']);
      expect(a.sync.status.issue, ZenSyncIssue.erasedEverywhere);
    });

    test('every paired device erases at its next sync, and the folder holds no record', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      final c = await openDevice(root, 'c');
      await a.items.put('a1', item('from a'));
      await b.items.put('b1', item('from b'));
      await c.items.put('c1', item('from c'));
      await syncAll([a, b, c]);
      expect(filesUnder(shared).length, greaterThan(3));

      await a.sync.eraseEverywhere();
      await b.syncUntilQuiet();
      await c.syncUntilQuiet();

      for (final device in [a, b, c]) {
        expect(device.store.erasedEverywhere, isTrue, reason: device.name);
        expect(device.items.list().dataOrNull, isEmpty, reason: device.name);
        expect(device.store.unsent, isEmpty, reason: device.name);
      }
      // One marker per device and nothing else: no record, no name, no id.
      expect(names(shared), ['erased.zen', 'erased.zen', 'erased.zen']);
    });

    test('a device that syncs only after everything was erased erases too', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('shared'));
      await syncAll([a, b]);
      await b.sync.stop();
      await b.store.close();

      await a.sync.eraseEverywhere();
      // Only a device removes its own files (one writer per file), so what b left stays until b
      // comes back: its copy of the record, and the marker a left for it to find.
      expect(names(shared), unorderedEquals([endsWith('.zen'), 'erased.zen']));
      expect(names(shared).where((n) => n == 'erased.zen'), hasLength(1));

      // b comes back a month later with its copy and its own files in the folder.
      final back = await openDevice(root, 'b');
      expect(back.items.get('1').dataOrNull?.name, 'shared');
      await back.syncUntilQuiet();

      expect(back.store.erasedEverywhere, isTrue);
      expect(back.items.list().dataOrNull, isEmpty);
      expect(names(shared), ['erased.zen', 'erased.zen']);
    });

    test('nothing an erased device sends is merged by one that has not heard yet', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('shared'));
      await syncAll([a, b]);

      await a.sync.eraseEverywhere();
      await b.items.put('2', item('written before b heard'));
      await b.syncUntilQuiet();

      expect(b.store.erasedEverywhere, isTrue);
      expect(b.items.list().dataOrNull, isEmpty);
      expect(names(shared), ['erased.zen', 'erased.zen']);
    });

    test('an unreachable folder leaves the store erased and finishes the cleanup later', () async {
      final a = await openDevice(root, 'a');
      await a.items.put('1', item('secret'));
      await a.sync.syncNow();
      final gone = Directory('${root.path}/away');
      shared.renameSync(gone.path);

      final result = await a.sync.eraseEverywhere();

      expect(result, isA<ZenFailure<void>>());
      expect(a.store.erasedEverywhere, isTrue);
      gone.renameSync(shared.path);
      await a.syncUntilQuiet();
      expect(names(shared), ['erased.zen']);
      expect(a.sync.status.issue, ZenSyncIssue.erasedEverywhere);
    });

    test('the mark survives a restart, and the new transport finishes the cleanup', () async {
      final a = await openDevice(root, 'a');
      await a.items.put('1', item('secret'));
      await a.sync.syncNow();
      // The store is erased but the transport never got to clean (the app died).
      await a.store.eraseEverywhere();
      await a.sync.stop();
      await a.store.close();

      final again = await openDevice(root, 'a');
      await again.syncUntilQuiet();

      expect(again.store.erasedEverywhere, isTrue);
      expect(names(shared), ['erased.zen']);
    });

    test('a device that was never paired erases without touching the folder', () async {
      final a = await openDevice(root, 'a', paired: false);
      await a.items.put('1', item('secret'));

      final result = await a.sync.eraseEverywhere();

      expect(result, isA<ZenSuccess<void>>());
      expect(a.store.erasedEverywhere, isTrue);
      expect(filesUnder(shared), isEmpty);
    });

    test('a new sync key starts clean beside the erased one', () async {
      final a = await openDevice(root, 'a');
      await a.items.put('1', item('old life'));
      await a.sync.syncNow();
      await a.sync.eraseEverywhere();
      await a.sync.stop();
      await a.store.close();
      await ZenStore.erase(a.storeDirectory);

      final fresh = await openDevice(root, 'a', withSyncKey: otherSyncKey);
      await fresh.items.put('1', item('new life'));
      await fresh.syncUntilQuiet();

      expect(fresh.store.erasedEverywhere, isFalse);
      expect(fresh.sync.status.state, ZenSyncState.upToDate);
      expect(fresh.items.get('1').dataOrNull?.name, 'new life');
    });
  });

  group('replacing the sync key', () {
    test('writes everything under the new key and leaves a marker under the old', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('one'));
      await b.items.put('2', item('two'));
      await syncAll([a, b]);
      final oldDirectory = await keyDirectory(shared);
      List<int>? handed;

      final result = await a.sync.rekey(persist: (key) async => handed = key);

      final newKey = result.dataOrNull!;
      expect(newKey, hasLength(32));
      expect(newKey, isNot(syncKey));
      expect(handed, newKey);
      expect(names(oldDirectory), ['rekeyed.zen']);
      final newDirectory = await keyDirectory(shared, newKey);
      // Both records, a's own and the one it merged from b: this device's directory is a whole copy.
      expect(
        filesUnder(newDirectory).where((f) => f.uri.pathSegments.last != 'erased.zen'),
        hasLength(2),
      );
    });

    test('a device still on the old key stops, and says why', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('one'));
      await syncAll([a, b]);
      await a.sync.rekey(persist: (_) async {});
      b.access.writes.clear();

      await b.items.put('2', item('written after the key was replaced'));
      await b.syncUntilQuiet();

      expect(b.sync.status.issue, ZenSyncIssue.keyReplaced);
      expect(b.access.writes, isEmpty);
      expect(b.store.unsent, isNotEmpty); // nothing was lost, nothing was sent under the old key
    });

    test('what a removed device writes with the old key is ignored, not even reported', () async {
      final a = await openDevice(root, 'a');
      final removed = await openDevice(root, 'removed');
      await a.items.put('1', item('one'));
      await syncAll([a, removed]);
      final result = await a.sync.rekey(persist: (_) async {});
      final newKey = result.dataOrNull!;
      // A removed device that ignores the marker, as a hostile one would.
      File('${(await keyDirectory(shared)).path}/rekeyed.zen').deleteSync();

      await removed.items.put('forged', item('forged transaction'));
      await removed.items.put('1', item('overwritten'));
      await removed.syncUntilQuiet();
      await a.syncUntilQuiet();

      expect(removed.sync.status.state, ZenSyncState.upToDate); // it believes it is syncing
      expect(a.sync.status.state, ZenSyncState.upToDate);
      expect(a.sync.lastReport?.problems ?? const [], isEmpty);
      expect(a.items.get('forged').errorOrNull, isA<ZenNotFoundError>());
      expect(a.items.get('1').dataOrNull?.name, 'one');
      // And it cannot read what a writes next either.
      await a.items.put('2', item('private to the new key'));
      await a.syncUntilQuiet();
      await removed.syncUntilQuiet();
      expect(removed.items.get('2').errorOrNull, isA<ZenNotFoundError>());
      expect(newKey, isNot(syncKey));
    });

    test('a remaining device pairs again with the new key and loses nothing', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('one'));
      await syncAll([a, b]);
      final newKey = (await a.sync.rekey(persist: (_) async {})).dataOrNull!;
      await b.items.put('2', item('b edited while it still held the old key'));
      await b.syncUntilQuiet();
      await b.sync.stop();
      await b.store.close();

      final paired = await openDevice(root, 'b', withSyncKey: newKey);
      await syncAll([a, paired]);

      expect(paired.sync.status.state, ZenSyncState.upToDate);
      expect(a.items.get('2').dataOrNull?.name, 'b edited while it still held the old key');
      expect(paired.items.get('1').dataOrNull?.name, 'one');
      expect(a.store.conflictCount + paired.store.conflictCount, 0);
    });

    test('a failure to store the new key changes nothing', () async {
      final a = await openDevice(root, 'a');
      final b = await openDevice(root, 'b');
      await a.items.put('1', item('one'));
      await syncAll([a, b]);
      final before = names(shared);

      final result = await a.sync.rekey(persist: (_) async => throw StateError('keychain locked'));

      expect(result, isA<ZenFailure<List<int>>>());
      expect(result.errorOrNull!.message, contains('keychain locked'));
      expect(names(shared), before);
      await a.items.put('2', item('still syncing on the old key'));
      await syncAll([a, b]);
      expect(b.items.get('2').dataOrNull?.name, 'still syncing on the old key');
      expect(a.sync.status.state, ZenSyncState.upToDate);
    });

    test('a device that is not paired has no key to replace', () async {
      final a = await openDevice(root, 'a', paired: false);

      final result = await a.sync.rekey(persist: (_) async {});

      expect(result.errorOrNull, isA<ZenValidationError>());
    });

    test('an unreachable folder refuses before the key is handed out', () async {
      final a = await openDevice(root, 'a');
      await a.items.put('1', item('one'));
      await a.sync.syncNow();
      shared.renameSync('${root.path}/away');
      var persisted = false;

      final result = await a.sync.rekey(persist: (_) async => persisted = true);

      expect(result, isA<ZenFailure<List<int>>>());
      expect(persisted, isFalse);
    });
  });
}
