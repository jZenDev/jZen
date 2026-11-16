import 'dart:io';

import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

Api item(String name, [String? version]) => Api(name: name, version: version);

final List<int> key = List.generate(32, (i) => i);

/// A batch big enough that its records sit in many of the 64 shards, so "between two renames" is
/// a real place to stop.
const int _spread = 40;

void main() {
  late Directory root;
  late Directory dir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zen_store_batch_test');
    dir = Directory('${root.path}/a');
  });
  tearDown(() async => root.delete(recursive: true));

  Future<ZenStore> open({Future<void> Function(int, int)? afterFileReplaced}) async {
    final result = await ZenStore.open(
      dir,
      deviceName: 'device a',
      key: key,
      afterFileReplaced: afterFileReplaced,
    );
    return result.dataOrNull ?? (throw StateError('open failed: ${result.errorOrNull}'));
  }

  ZenCollection<Api> accounts(ZenStore store) => store.collection('accounts', Api.fromBuffer);
  ZenCollection<Api> entries(ZenStore store) => store.collection('entries', Api.fromBuffer);

  /// An account with [_spread] entries, saved one record at a time as an application does today.
  Future<ZenStore> seeded() async {
    final store = await open();
    await accounts(store).put('acc', item('Cash'));
    for (var i = 0; i < _spread; i++) {
      await entries(store).put('e$i', item('entry $i'));
    }
    return store;
  }

  /// Deleting the account with all of its entries, and adding a replacement: the operation the
  /// server runs as one transaction.
  ZenBatch deleteAccountAndAddNew(ZenStore store) {
    final batch = ZenBatch()..delete(accounts(store), 'acc');
    for (var i = 0; i < _spread; i++) {
      batch.delete(entries(store), 'e$i');
    }
    batch.put(accounts(store), 'new', item('Card'));
    return batch;
  }

  void expectBefore(ZenStore store) {
    expect(accounts(store).get('acc').dataOrNull?.name, 'Cash');
    expect(accounts(store).get('new').errorOrNull, isA<ZenNotFoundError>());
    expect(entries(store).list().dataOrNull, hasLength(_spread));
  }

  void expectAfter(ZenStore store) {
    expect(accounts(store).get('acc').errorOrNull, isA<ZenNotFoundError>());
    expect(accounts(store).get('new').dataOrNull?.name, 'Card');
    expect(entries(store).list().dataOrNull, isEmpty);
  }

  group('writeAll', () {
    test('puts and deletes across collections and shards land together', () async {
      final store = await seeded();

      final result = await store.writeAll(deleteAccountAndAddNew(store));

      expect(result.isSuccess, isTrue);
      expectAfter(store);
      expect(store.unsent, containsAll(['accounts:acc', 'accounts:new', 'entries:e0']));
    });

    test('what it wrote is there after reopening', () async {
      final store = await seeded();
      await store.writeAll(deleteAccountAndAddNew(store));
      await store.close();

      expectAfter(await open());
    });

    test('announces each collection once, however many records it changed', () async {
      final store = await seeded();
      final seen = <Set<String>>[];
      store.changes.listen(seen.add);

      await store.writeAll(deleteAccountAndAddNew(store));
      await Future<void>.delayed(Duration.zero);

      expect(seen, [
        {'accounts', 'entries'},
      ]);
    });

    test('an empty batch is a success that writes nothing', () async {
      final store = await seeded();
      final before = {...store.unsent};

      expect((await store.writeAll(ZenBatch())).isSuccess, isTrue);
      expect(store.unsent, before);
    });

    test('a put replaces only the fields that differ, as a single put does', () async {
      final store = await open();
      await accounts(store).put('acc', item('Cash', '1'));

      await store.writeAll(ZenBatch()..put(accounts(store), 'acc', item('Cash', '2')));

      expect(accounts(store).get('acc').dataOrNull?.version, '2');
    });
  });

  group('writeAll refuses as a whole', () {
    test('a delete of a record that is not there writes none of the batch', () async {
      final store = await seeded();

      final result = await store.writeAll(
        ZenBatch()
          ..delete(entries(store), 'e0')
          ..delete(entries(store), 'missing'),
      );

      expect(result.errorOrNull, isA<ZenNotFoundError>());
      expect(entries(store).get('e0').dataOrNull?.name, 'entry 0');
    });

    test('the same record twice is ambiguous, so it is refused', () async {
      final store = await seeded();

      final result = await store.writeAll(
        ZenBatch()
          ..put(accounts(store), 'acc', item('A'))
          ..delete(accounts(store), 'acc'),
      );

      expect(result.errorOrNull, isA<ZenValidationError>());
      expect(accounts(store).get('acc').dataOrNull?.name, 'Cash');
    });

    test('an id that cannot travel is refused before anything is written', () async {
      final store = await seeded();

      final result = await store.writeAll(
        ZenBatch()
          ..put(accounts(store), 'fine', item('x'))
          ..put(accounts(store), 'not valid', item('y')),
      );

      expect(result.errorOrNull, isA<ZenValidationError>());
      expect(accounts(store).get('fine').errorOrNull, isA<ZenNotFoundError>());
    });

    test("a collection of another store is refused", () async {
      final store = await seeded();
      final other = (await ZenStore.open(
        Directory('${root.path}/b'),
        deviceName: 'device b',
        key: key,
      )).dataOrNull!;

      final result = await store.writeAll(ZenBatch()..put(accounts(other), 'x', item('x')));

      expect(result.errorOrNull, isA<ZenValidationError>());
    });

    test('a record in conflict refuses the batch, like a single write', () async {
      final a = await open();
      final bResult = await ZenStore.open(
        Directory('${root.path}/b'),
        deviceName: 'device b',
        key: key,
      );
      final b = bResult.dataOrNull!;
      await accounts(a).put('acc', item('Cash', '1'));
      await b.receive([
        for (final name in ['accounts:acc'])
          ZenIncomingRecord(name, a.outgoing(name)!.payload, null),
      ]);
      await accounts(a).put('acc', item('Cash', 'from a'));
      await accounts(b).put('acc', item('Cash', 'from b'));
      await a.receive([
        ZenIncomingRecord('accounts:acc', b.outgoing('accounts:acc')!.payload, null),
      ]);
      expect(accounts(a).conflictFor('acc').dataOrNull, isNotNull);

      final result = await a.writeAll(
        ZenBatch()
          ..put(accounts(a), 'other', item('x'))
          ..put(accounts(a), 'acc', item('y')),
      );

      expect(result.errorOrNull, isA<ZenConflictError>());
      expect(accounts(a).get('other').errorOrNull, isA<ZenNotFoundError>());
    });
  });

  group('a crash in the middle of a batch', () {
    test('before the journal is saved leaves none of it, and the store keeps working', () async {
      final store = await seeded();
      // A directory where the journal's temporary file goes: saving the journal fails, which is
      // as far as a crash before it got.
      await Directory('${dir.path}/.journal.zen.tmp').create();

      final result = await store.writeAll(deleteAccountAndAddNew(store));

      expect(result.errorOrNull, isA<ZenStorageError>());
      expectBefore(store);
      await store.close();
      expectBefore(await open());

      await Directory('${dir.path}/.journal.zen.tmp').delete();
      final again = await open();
      expect((await again.writeAll(deleteAccountAndAddNew(again))).isSuccess, isTrue);
      expectAfter(again);
    });

    for (final replaced in [0, 1, 2, 5]) {
      test('after $replaced file(s) were replaced leaves all of it once reopened', () async {
        await (await seeded()).close();
        var done = -1;
        final crashing = await open(
          afterFileReplaced: (count, total) async {
            done = count;
            expect(total, greaterThan(replaced));
            if (count == replaced) throw const FileSystemException('power lost');
          },
        );
        // Zero replaced: the crash is before the first rename, with the journal already saved.
        final batch = deleteAccountAndAddNew(crashing);

        final result = await (replaced == 0
            ? _crashBeforeFirstRename(dir, crashing, batch)
            : crashing.writeAll(batch));

        expect(result.errorOrNull, isA<ZenStorageError>());
        expect(result.errorOrNull?.message, contains('opening it again finishes the batch'));
        expect(done, replaced == 0 ? -1 : replaced);
        // The crashed store stops accepting writes: its memory is behind its disk.
        expect(
          (await crashing.writeAll(ZenBatch()..put(accounts(crashing), 'x', item('x')))).isFailure,
          isTrue,
        );

        final reopened = await open();

        expectAfter(reopened);
        expect(File('${dir.path}/journal.zen').existsSync(), isFalse);
      });
    }

    test('a journal left behind after every file was replaced is harmless to replay', () async {
      await (await seeded()).close();
      late final List<int> journal;
      final crashing = await open(
        afterFileReplaced: (count, total) async {
          if (count == total) {
            journal = File('${dir.path}/journal.zen').readAsBytesSync();
            throw const FileSystemException('power lost before the journal was deleted');
          }
        },
      );
      await crashing.writeAll(deleteAccountAndAddNew(crashing));

      final reopened = await open();

      expectAfter(reopened);
      expect(journal, isNotEmpty);
      expect(File('${dir.path}/journal.zen').existsSync(), isFalse);
    });

    test('a journal that does not decrypt refuses to open and is left in place', () async {
      await (await seeded()).close();
      File('${dir.path}/journal.zen').writeAsBytesSync(List.filled(64, 3));

      final result = await ZenStore.open(dir, deviceName: 'device a', key: key);

      expect(result.errorOrNull, isA<ZenStorageError>());
      expect(File('${dir.path}/journal.zen').existsSync(), isTrue);
    });
  });

  group('what the transport sees', () {
    test('a batch goes out as ordinary per-record changes', () async {
      final a = await seeded();
      final bResult = await ZenStore.open(
        Directory('${root.path}/b'),
        deviceName: 'device b',
        key: key,
      );
      final b = bResult.dataOrNull!;
      await a.writeAll(
        ZenBatch()
          ..put(accounts(a), 'new', item('Card'))
          ..delete(entries(a), 'e0'),
      );

      expect(a.unsent, containsAll(['accounts:new', 'entries:e0']));
      final outgoing = [
        for (final name in ['accounts:new', 'entries:e0']) a.outgoing(name)!,
      ];
      // One record arrives alone; the other has not yet.
      await b.receive([ZenIncomingRecord(outgoing[0].name, outgoing[0].payload, null)]);
      expect(accounts(b).get('new').dataOrNull?.name, 'Card');
      expect(entries(b).get('e0').errorOrNull, isA<ZenNotFoundError>());
    });
  });
}

/// A crash with the journal saved and no file yet replaced: the first rename is made to fail by
/// a directory standing in its place.
Future<ZenResult<void>> _crashBeforeFirstRename(
  Directory dir,
  ZenStore store,
  ZenBatch batch,
) async {
  final blocker = Directory('${dir.path}/.meta.zen.tmp')..createSync();
  final result = await store.writeAll(batch);
  blocker.deleteSync();
  return result;
}
