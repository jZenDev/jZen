import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_cloudkit/zen_store_cloudkit.dart';

// The Swift half needs CloudKit and a signed app, so these pin the Dart half's side of the
// conversation: what it sends the engine, and what it does with everything the engine sends back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zen_store_cloudkit');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final sent = <MethodCall>[];
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('zen_store_cloudkit_test');
    sent.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  Future<ZenStore> store(
    String name, {
    Future<void> Function(int replaced, int total)? afterFileReplaced,
  }) async => (await ZenStore.open(
    Directory('${root.path}/$name'),
    deviceName: name,
    key: List.filled(32, 1),
    afterFileReplaced: afterFileReplaced,
  )).dataOrNull!;

  /// A call from the Swift side, as the engine makes it, and Dart's reply.
  Future<Object?> fromSwift(String method, [Object? arguments]) async {
    Object? reply;
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      (data) => reply = data == null ? null : channel.codec.decodeEnvelope(data),
    );
    return reply;
  }

  Map<String, Object?> record(ZenOutgoingRecord outgoing, [String system = 'tag-1']) => {
    'name': outgoing.name,
    'payload': outgoing.payload,
    'system': Uint8List.fromList(utf8.encode(system)),
  };

  ZenCollection<Api> items(ZenStore store) => store.collection('items', Api.fromBuffer);

  /// Lets whatever is ready to run do so.
  Future<void> turns() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// The names the engine was asked to send, in every `changed` call so far.
  List<Object?> namesHandedToTheEngine() => [
    for (final call in sent.where((c) => c.method == 'changed'))
      ...(call.arguments as Map)['names'] as List<Object?>,
  ];

  /// Device `a` with its store's write queue held by a batch that has written its last file, so
  /// that what a test delivers next certainly waits behind a write in progress. The returned
  /// function lets the batch finish.
  Future<(ZenStore, Future<void> Function())> heldStore() async {
    final reached = Completer<void>();
    final gate = Completer<void>();
    final local = await store(
      'a',
      afterFileReplaced: (replaced, total) async {
        if (replaced < total) return;
        reached.complete();
        await gate.future;
      },
    );
    await local.saveTransportState(utf8.encode('before'));
    final batch = local.writeAll(ZenBatch()..put(items(local), 'held', Api(name: 'held')));
    await reached.future;
    Future<void> release() async {
      gate.complete();
      expect(await batch, isA<ZenSuccess<void>>());
    }

    return (local, release);
  }

  /// Waits for work that writes to disk and that nothing hands the test a future for.
  Future<void> pumpUntil(bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  test('start hands the engine its saved state and everything still unsent', () async {
    final local = await store('a');
    await items(local).put('1', Api(name: 'x'));
    await local.saveTransportState(utf8.encode('engine-state'));

    final sync = (await ZenCloudKitSync.start(local, containerId: 'iCloud.app')).dataOrNull!;

    expect(sent[0].method, 'start');
    expect(sent[0].arguments['containerId'], 'iCloud.app');
    expect(utf8.decode(sent[0].arguments['state'] as List<int>), 'engine-state');
    expect(sent[1].method, 'changed');
    expect(sent[1].arguments['names'], ['items:1']);
    await sync.stop();
  });

  test('a local write is handed to the engine at once', () async {
    final local = await store('a');
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;
    sent.clear();

    await items(local).put('7', Api(name: 'new'));
    await Future<void>.delayed(Duration.zero);

    expect(sent.single.method, 'changed');
    expect(sent.single.arguments['names'], ['items:7']);
    await sync.stop();
  });

  test(
    'the engine gets each record\'s payload, and a confirmed save stops it being unsent',
    () async {
      final local = await store('a');
      await items(local).put('1', Api(name: 'x'));
      final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;

      final batch = await fromSwift('outgoing', {
        'names': ['items:1', 'items:gone'],
      }) as List<Object?>;
      expect(batch, hasLength(1));
      final out = local.outgoing('items:1')!;
      expect((batch.single! as Map)['payload'], out.payload);

      await fromSwift('saved', {
        'records': [record(out)],
      });
      expect(local.unsent, isEmpty);
      expect(utf8.decode(local.outgoing('items:1')!.transportData!), 'tag-1');
      await sync.stop();
    },
  );

  test('records fetched from another device are merged into the store', () async {
    final other = await store('b');
    await items(other).put('1', Api(name: 'from b'));
    final local = await store('a');
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;

    await fromSwift('fetched', {
      'records': [record(other.outgoing('items:1')!)],
    });

    expect(items(local).get('1').dataOrNull?.name, 'from b');
    expect(local.unsent, isEmpty);
    await sync.stop();
  });

  test('a refused save is merged with the server copy and stays unsent to go again', () async {
    final other = await store('b');
    await items(other).put('1', Api(name: 'shared', version: '1'));
    final local = await store('a');
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;
    await fromSwift('fetched', {
      'records': [record(other.outgoing('items:1')!)],
    });
    await items(other).put('1', Api(name: 'renamed', version: '1'));
    await items(local).put('1', Api(name: 'shared', version: '2'));
    await turns();
    sent.clear();

    await fromSwift('refused', {
      'records': [record(other.outgoing('items:1')!, 'tag-2')],
    });
    await turns();

    expect(items(local).get('1').dataOrNull, Api(name: 'renamed', version: '2'));
    expect(local.unsent, {'items:1'});
    // The engine dropped the save it was refused, and nothing else tells it to try again.
    expect(namesHandedToTheEngine(), ['items:1']);
    await sync.stop();
  });

  test('a refused record whose server copy cannot be read is not sent again', () async {
    final local = await store('a');
    await items(local).put('1', Api(name: 'x'));
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;
    sent.clear();

    await fromSwift('refused', {
      'records': [
        {
          'name': 'items:1',
          'payload': Uint8List.fromList(utf8.encode(jsonEncode({'format': 99}))),
        },
      ],
    });
    await turns();

    // The save would be refused with the same copy, for ever.
    expect(namesHandedToTheEngine(), isEmpty);
    await sync.stop();
  });

  test('the engine\'s status reaches the app, with the issue named', () async {
    final local = await store('a');
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;
    final statuses = <ZenSyncStatus>[];
    final subscription = sync.statusChanges.listen(statuses.add);

    await fromSwift('status', {'state': 'unavailable', 'issue': 'accountChanged', 'message': 'm'});
    await Future<void>.delayed(Duration.zero);

    expect(sync.status.issue, ZenSyncIssue.accountChanged);
    expect(statuses, hasLength(1));
    await subscription.cancel();
    await sync.stop();
  });

  test('a reset of the cloud copy marks everything to be sent again', () async {
    final local = await store('a');
    await items(local).put('1', Api(name: 'x'));
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;
    await fromSwift('saved', {
      'records': [record(local.outgoing('items:1')!)],
    });
    expect(local.unsent, isEmpty);

    await fromSwift('resetCloud');

    expect(local.unsent, {'items:1'});
    await sync.stop();
  });

  test('a record from a newer app version makes the status say so', () async {
    final local = await store('a');
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;

    await fromSwift('fetched', {
      'records': [
        {
          'name': 'items:1',
          'payload': Uint8List.fromList(utf8.encode(jsonEncode({'format': 99}))),
        },
      ],
    });

    expect(sync.status.issue, ZenSyncIssue.unreadableRecords);
    await sync.stop();
  });

  test('on a platform without the plugin, start says CloudKit is not available', () async {
    messenger.setMockMethodCallHandler(channel, null);

    expect((await ZenCloudKitSync.start(await store('a'))).errorOrNull, isA<ZenNotFoundError>());
  });

  test('erasing everywhere erases the store, then asks iCloud to erase its zone', () async {
    final local = await store('a');
    await items(local).put('1', Api(name: 'x'));
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;
    sent.clear();

    final result = await sync.eraseEverywhere();

    expect(result, isA<ZenSuccess<void>>());
    expect(local.erasedEverywhere, isTrue);
    expect(items(local).list().dataOrNull, isEmpty);
    expect(sent.map((c) => c.method), ['eraseEverywhere']);
    expect(sync.status.issue, ZenSyncIssue.erasedEverywhere);
    await sync.stop();
  });

  test('an iCloud that cannot be reached leaves the store erased and says so', () async {
    final local = await store('a');
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      if (call.method == 'eraseEverywhere') {
        throw PlatformException(code: 'erase_failed', message: 'offline');
      }
      return null;
    });

    final result = await sync.eraseEverywhere();

    expect(result.errorOrNull!.message, contains('offline'));
    expect(local.erasedEverywhere, isTrue);
    expect(sync.status.issue, ZenSyncIssue.other);
    await sync.stop();
  });

  test('an erase the app did not finish is finished at the next start', () async {
    final local = await store('a');
    await local.eraseEverywhere();

    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;

    expect(sent.map((c) => c.method), contains('eraseEverywhere'));
    expect(sync.status.issue, ZenSyncIssue.erasedEverywhere);
    await sync.stop();
  });

  test('another device\'s erase, told by the engine, erases this copy', () async {
    final local = await store('a');
    await items(local).put('1', Api(name: 'x'));
    final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;

    await fromSwift('erased');

    expect(local.erasedEverywhere, isTrue);
    expect(items(local).list().dataOrNull, isEmpty);
    expect(sync.status.issue, ZenSyncIssue.erasedEverywhere);
    await sync.stop();
  });

  // The engine's change token moves past whatever it delivered, and CloudKit does not send it
  // again. So a token may reach the disk only after everything delivered before it has.
  group('when the store cannot write', () {
    /// Stops the store writing into [directory] of device `a`, or lets it again. `''` is the
    /// whole store; `records` leaves `meta.zen`, where the token is kept, writable.
    void unwritable(bool value, [String directory = '']) {
      final result = Process.runSync('chmod', [value ? 'u-w' : 'u+w', '${root.path}/a/$directory']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    tearDown(() => Process.runSync('chmod', ['-R', 'u+w', root.path]));

    /// A running sync on a store whose saved engine state is `before`.
    Future<(ZenStore, ZenCloudKitSync)> started({Duration? retryEvery}) async {
      final local = await store('a');
      await local.saveTransportState(utf8.encode('before'));
      final sync = await ZenCloudKitSync.start(local, retryEvery: retryEvery);
      return (local, sync.dataOrNull!);
    }

    Future<Map<String, Object?>> fromAnotherDevice(String id) async {
      final other = await store('b$id');
      await items(other).put(id, Api(name: 'from b'));
      return record(other.outgoing('items:$id')!);
    }

    Future<void> deliverState(String state) async {
      await fromSwift('state', {'state': utf8.encode(state)});
    }

    /// The app quits and starts again: what is on disk is all that is left.
    Future<ZenStore> relaunched(ZenStore local, ZenCloudKitSync sync) async {
      await sync.stop();
      await local.close();
      return store('a');
    }

    String savedState(ZenStore local) => utf8.decode(local.transportState!);

    for (final method in ['fetched', 'refused']) {
      test('$method: a token saved once writing works again is not past the record', () async {
        final incoming = await fromAnotherDevice('1');
        final (local, sync) = await started();
        unwritable(true);
        await fromSwift(method, {
          'records': [incoming],
        });
        expect(sync.status.state, ZenSyncState.unavailable);
        unwritable(false);
        await deliverState('after');

        final reopened = await relaunched(local, sync);

        expect(items(reopened).get('1').dataOrNull?.name, 'from b');
        expect(savedState(reopened), 'after');
      });

      test('$method: while the record is unwritten the old token stays on disk', () async {
        final incoming = await fromAnotherDevice('1');
        final (local, sync) = await started();
        unwritable(true, 'records');
        await fromSwift(method, {
          'records': [incoming],
        });
        await deliverState('after');
        await deliverState('later');

        final reopened = await relaunched(local, sync);

        expect(items(reopened).get('1').dataOrNull, isNull);
        expect(savedState(reopened), 'before');
      });
    }

    test('a later delivery does not take the token past an earlier one', () async {
      final first = await fromAnotherDevice('1');
      final (local, sync) = await started();
      unwritable(true);
      await fromSwift('fetched', {
        'records': [first],
      });
      await deliverState('after first');
      unwritable(false);
      final second = await fromAnotherDevice('2');
      await fromSwift('fetched', {
        'records': [second],
      });
      await deliverState('after second');

      final reopened = await relaunched(local, sync);

      expect(items(reopened).list().dataOrNull, hasLength(2));
      expect(savedState(reopened), 'after second');
    });

    test('the failure stays in the status until the record is written', () async {
      final incoming = await fromAnotherDevice('1');
      final (_, sync) = await started();
      unwritable(true);
      await fromSwift('fetched', {
        'records': [incoming],
      });

      await fromSwift('status', {'state': 'syncing'});
      await fromSwift('status', {'state': 'upToDate'});

      expect(sync.status.state, ZenSyncState.unavailable);
      expect(sync.status.issue, ZenSyncIssue.other);
      expect(sync.status.message, contains('Cannot save synced records'));

      unwritable(false);
      await fromSwift('status', {'state': 'upToDate'});
      await sync.syncNow();

      expect(sync.status.state, ZenSyncState.upToDate);
      await sync.stop();
    });

    test('syncNow writes what is waiting, with nothing new from the engine', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, sync) = await started();
      unwritable(true);
      await fromSwift('fetched', {
        'records': [incoming],
      });
      await deliverState('after');
      unwritable(false);
      sent.clear();

      await sync.syncNow();

      expect(sent.map((c) => c.method), ['syncNow']);
      expect(items(local).get('1').dataOrNull?.name, 'from b');
      expect(savedState(local), 'after');
      await sync.stop();
    });

    test('a local write brings the waiting records with it', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, sync) = await started();
      unwritable(true);
      await fromSwift('fetched', {
        'records': [incoming],
      });
      await deliverState('after');
      unwritable(false);

      await items(local).put('2', Api(name: 'mine'));
      await pumpUntil(() => utf8.decode(local.transportState!) == 'after');

      expect(items(local).get('1').dataOrNull?.name, 'from b');
      await sync.stop();
    });

    test('what is waiting is retried on its own', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, sync) = await started(retryEvery: const Duration(milliseconds: 20));
      unwritable(true);
      await fromSwift('fetched', {
        'records': [incoming],
      });
      await deliverState('after');
      unwritable(false);

      await pumpUntil(() => utf8.decode(local.transportState!) == 'after');

      expect(items(local).get('1').dataOrNull?.name, 'from b');
      expect(sync.status.issue, isNull);
      await sync.stop();
    });

    test('an unconfirmed save holds the token until it is recorded', () async {
      final (local, sync) = await started();
      await items(local).put('1', Api(name: 'x'));
      final out = local.outgoing('items:1')!;
      unwritable(true);
      await fromSwift('saved', {
        'records': [record(out)],
      });
      await deliverState('after');

      expect(sync.status.state, ZenSyncState.unavailable);
      expect(savedState(local), 'before');

      unwritable(false);
      await sync.syncNow();

      expect(local.unsent, isEmpty);
      expect(savedState(local), 'after');
      await sync.stop();
    });

    test('a reset of the cloud copy that cannot be recorded holds the token', () async {
      final (local, sync) = await started();
      await items(local).put('1', Api(name: 'x'));
      await fromSwift('saved', {
        'records': [record(local.outgoing('items:1')!)],
      });
      unwritable(true, 'records');
      await fromSwift('resetCloud');
      await deliverState('after');

      expect(sync.status.state, ZenSyncState.unavailable);
      expect(savedState(local), 'before');

      unwritable(false, 'records');
      await sync.syncNow();

      expect(local.unsent, {'items:1'});
      expect(savedState(local), 'after');
      await sync.stop();
    });

    test('an erase that cannot be written holds the token and is done later', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, sync) = await started();
      await items(local).put('2', Api(name: 'x'));
      unwritable(true);
      // The record is about to be erased anyway, so the erase must not wait behind it.
      await fromSwift('fetched', {
        'records': [incoming],
      });
      await fromSwift('erased');
      await deliverState('after');

      expect(local.erasedEverywhere, isFalse);
      expect(savedState(local), 'before');
      expect(sync.status.issue, ZenSyncIssue.other);

      unwritable(false);
      await sync.syncNow();

      expect(local.erasedEverywhere, isTrue);
      expect(items(local).list().dataOrNull, isEmpty);
      expect(sync.status.issue, ZenSyncIssue.erasedEverywhere);
      await sync.stop();
    });

    test('erasing everywhere from the app drops what was waiting to be written', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, sync) = await started();
      unwritable(true);
      await fromSwift('fetched', {
        'records': [incoming],
      });
      unwritable(false);

      expect(await sync.eraseEverywhere(), isA<ZenSuccess<void>>());
      await sync.syncNow();

      expect(items(local).list().dataOrNull, isEmpty);
      expect(sync.status.issue, ZenSyncIssue.erasedEverywhere);
      await sync.stop();
    });

    test('every change the store has taken is answered with true', () async {
      final incoming = await fromAnotherDevice('1');
      final (_, sync) = await started();
      unwritable(true);

      // The Swift side stops saving engine state on any other answer, so a change that is only
      // waiting here is answered the same as a written one.
      expect(
        await fromSwift('fetched', {
          'records': [incoming],
        }),
        isTrue,
      );
      unwritable(false);
      expect(await fromSwift('saved', {'records': <Object?>[]}), isTrue);
      await sync.stop();
    });

    test('a change Dart cannot take at all is answered with an error', () async {
      final (_, sync) = await started();

      await expectLater(
        fromSwift('fetched', {
          'records': [
            {'name': 'items:1'},
          ],
        }),
        throwsA(isA<PlatformException>()),
      );
      await sync.stop();
    });

    test('stop with a change still unwritten leaves the old token', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, sync) = await started();
      unwritable(true, 'records');
      await fromSwift('fetched', {
        'records': [incoming],
      });
      await deliverState('after');

      await sync.stop();

      expect(sync.status, ZenSyncStatus.off);
      unwritable(false, 'records');
      await local.close();
      expect(savedState(await store('a')), 'before');
    });

    test('a delivery during an erase that then fails is written, not dropped', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, sync) = await started();
      unwritable(true);

      final erase = sync.eraseEverywhere();
      final delivery = fromSwift('fetched', {
        'records': [incoming],
      });

      expect(await erase, isA<ZenFailure<void>>());
      await delivery;
      unwritable(false);
      await deliverState('after');

      final reopened = await relaunched(local, sync);
      expect(items(reopened).get('1').dataOrNull?.name, 'from b');
      expect(savedState(reopened), 'after');
    });

    test('a delivery being written when an erase starts and fails is not dropped', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, release) = await heldStore();
      final sync = (await ZenCloudKitSync.start(local, retryEvery: null)).dataOrNull!;

      final delivery = fromSwift('fetched', {
        'records': [incoming],
      });
      await turns();
      final erase = sync.eraseEverywhere();
      unwritable(true, 'records');
      await release();

      expect(await erase, isA<ZenFailure<void>>());
      await delivery;
      await deliverState('after');
      unwritable(false, 'records');
      await sync.syncNow();

      final reopened = await relaunched(local, sync);
      expect(items(reopened).get('1').dataOrNull?.name, 'from b');
      expect(savedState(reopened), 'after');
    });

    test('a store erased directly drops what was waiting, and syncing goes on', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, sync) = await started();
      unwritable(true);
      await fromSwift('fetched', {
        'records': [incoming],
      });
      unwritable(false);

      expect(await local.eraseEverywhere(), isA<ZenSuccess<void>>());
      await turns();
      await fromSwift('fetched', {
        'records': [incoming],
      });
      await deliverState('after');

      expect(items(local).list().dataOrNull, isEmpty);
      expect(savedState(local), 'after');
      await sync.stop();
    });

    test('an erase from another device does not write what was waiting first', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, sync) = await started();
      unwritable(true);
      await fromSwift('fetched', {
        'records': [incoming],
      });
      await fromSwift('erased');
      final changes = <Set<String>>[];
      final subscription = local.changes.listen(changes.add);
      unwritable(false);

      await sync.syncNow();
      await turns();

      expect(local.erasedEverywhere, isTrue);
      expect(changes, isEmpty);
      await subscription.cancel();
      await sync.stop();
    });

    test('a refused record that waited is sent again once it is written', () async {
      final other = await store('b');
      await items(other).put('1', Api(name: 'theirs'));
      final (local, sync) = await started();
      await items(local).put('1', Api(name: 'mine'));
      await turns();
      unwritable(true);
      await fromSwift('refused', {
        'records': [record(other.outgoing('items:1')!)],
      });
      sent.clear();
      unwritable(false);

      await sync.syncNow();
      await turns();

      expect(namesHandedToTheEngine(), ['items:1']);
      await sync.stop();
    });

    test('only the newest engine state waits', () async {
      final first = await fromAnotherDevice('1');
      final second = await fromAnotherDevice('2');
      final (local, sync) = await started();
      unwritable(true);
      await fromSwift('fetched', {
        'records': [first],
      });
      await deliverState('one');
      await fromSwift('fetched', {
        'records': [second],
      });
      await deliverState('two');
      await deliverState('three');

      expect(sync.waitingChanges, 3);

      unwritable(false);
      await sync.syncNow();
      expect(savedState(local), 'three');
      await sync.stop();
    });

    test('past the limit a change is not taken, so the engine saves no more state', () async {
      final incoming = await fromAnotherDevice('1');
      final large = {
        'name': 'items:large',
        'payload': Uint8List(ZenCloudKitSync.waitingBytesLimit),
      };
      final (local, sync) = await started();
      unwritable(true);
      expect(
        await fromSwift('fetched', {
          'records': [incoming],
        }),
        isTrue,
      );

      expect(
        await fromSwift('fetched', {
          'records': [large],
        }),
        isFalse,
      );
      expect(sync.waitingChanges, 1);
      // An erase needs no room: it drops what waits.
      expect(await fromSwift('erased'), isTrue);

      unwritable(false);
      await sync.syncNow();
      expect(local.erasedEverywhere, isTrue);
      await sync.stop();
    });

    test('a change with no payload is taken however much is waiting', () async {
      final incoming = await fromAnotherDevice('1');
      final (_, sync) = await started();
      unwritable(true);
      await fromSwift('fetched', {
        'records': [
          {'name': 'items:large', 'payload': Uint8List(ZenCloudKitSync.waitingBytesLimit + 1)},
        ],
      });

      expect(await fromSwift('state', {'state': utf8.encode('after')}), isTrue);
      expect(await fromSwift('resetCloud'), isTrue);
      expect(
        await fromSwift('fetched', {
          'records': [incoming],
        }),
        isFalse,
      );
      await sync.stop();
    });

    test('with nothing waiting, a change of any size is taken', () async {
      final (_, sync) = await started();

      expect(
        await fromSwift('fetched', {
          'records': [
            {'name': 'items:large', 'payload': Uint8List(ZenCloudKitSync.waitingBytesLimit + 1)},
          ],
        }),
        isTrue,
      );
      await sync.stop();
    });

    test('a newer state arriving while the older is being written is not lost', () async {
      final (local, release) = await heldStore();
      final sync = (await ZenCloudKitSync.start(local, retryEvery: null)).dataOrNull!;

      final older = deliverState('older');
      await turns();
      final newer = deliverState('newer');
      await turns();
      await release();
      await Future.wait([older, newer]);

      expect(savedState(local), 'newer');
      await sync.stop();
    });

    test('stop lets the write in progress finish and starts no other', () async {
      final incoming = await fromAnotherDevice('1');
      final (local, release) = await heldStore();
      final sync = (await ZenCloudKitSync.start(local, retryEvery: null)).dataOrNull!;
      final delivery = fromSwift('fetched', {
        'records': [incoming],
      });
      await turns();
      final state = deliverState('after');
      await turns();

      final stopped = sync.stop();
      await release();
      await Future.wait([stopped, delivery, state]);

      expect(items(local).get('1').dataOrNull?.name, 'from b');
      expect(savedState(local), 'before');
    });
  }, skip: Platform.isWindows ? 'needs chmod to make a directory unwritable' : null);

  group('when a record cannot be read', () {
    final unreadable = {
      'name': 'items:1',
      'payload': Uint8List.fromList(utf8.encode(jsonEncode({'format': 99}))),
    };

    test('the token is not saved past it, and the status keeps saying so', () async {
      final local = await store('a');
      await local.saveTransportState(utf8.encode('before'));
      final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;

      await fromSwift('fetched', {
        'records': [unreadable],
      });
      await fromSwift('state', {'state': utf8.encode('after')});
      await fromSwift('status', {'state': 'upToDate'});

      expect(utf8.decode(local.transportState!), 'before');
      expect(sync.status.issue, ZenSyncIssue.unreadableRecords);
      await sync.stop();
    });

    test('a reset of the cloud copy lets the token be saved again', () async {
      final local = await store('a');
      final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;
      await fromSwift('fetched', {
        'records': [unreadable],
      });

      // The copy it came from is gone.
      await fromSwift('resetCloud');
      await fromSwift('state', {'state': utf8.encode('after')});

      expect(utf8.decode(local.transportState!), 'after');
      expect(sync.status.issue, isNull);
      await sync.stop();
    });

    test('once it has been read, the token is saved again', () async {
      final other = await store('b');
      await items(other).put('1', Api(name: 'from b'));
      final local = await store('a');
      final sync = (await ZenCloudKitSync.start(local)).dataOrNull!;
      await fromSwift('fetched', {
        'records': [unreadable],
      });
      await fromSwift('status', {'state': 'upToDate'});

      await fromSwift('fetched', {
        'records': [record(other.outgoing('items:1')!)],
      });
      await fromSwift('state', {'state': utf8.encode('after')});

      expect(utf8.decode(local.transportState!), 'after');
      expect(sync.status.state, ZenSyncState.upToDate);
      await sync.stop();
    });
  });

  test(
    'protectDirectory asks the plugin to protect the directory and reports its answer',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent.add(call);
        return true;
      });

      final result = await ZenDataProtection.protectDirectory(root);

      expect(result.dataOrNull, isTrue);
      expect(sent.single.method, 'protectDirectory');
      expect((sent.single.arguments as Map)['path'], root.path);
    },
  );

  test('protectDirectory succeeds with false where there is no plugin', () async {
    messenger.setMockMethodCallHandler(channel, null);

    expect((await ZenDataProtection.protectDirectory(root)).dataOrNull, isFalse);
  });

  test('protectDirectory surfaces a platform failure as an error', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'denied', message: 'no');
    });

    expect((await ZenDataProtection.protectDirectory(root)).errorOrNull, isA<ZenUnknownError>());
  });
}
