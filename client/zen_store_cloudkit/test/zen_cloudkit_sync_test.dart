import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  Future<ZenStore> store(String name) async => (await ZenStore.open(
    Directory('${root.path}/$name'),
    deviceName: name,
    key: List.filled(32, 1),
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

      final batch =
          await fromSwift('outgoing', {
                'names': ['items:1', 'items:gone'],
              })
              as List<Object?>;
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

    await fromSwift('refused', {
      'records': [record(other.outgoing('items:1')!, 'tag-2')],
    });

    expect(items(local).get('1').dataOrNull, Api(name: 'renamed', version: '2'));
    expect(local.unsent, {'items:1'});
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

  test('the store key is made once, 32 bytes, and the same on every later load', () async {
    FlutterSecureStorage.setMockInitialValues({});

    final first = (await ZenKeychainStoreKey.load()).dataOrNull!;
    final second = (await ZenKeychainStoreKey.load()).dataOrNull!;

    expect(first, hasLength(32));
    expect(second, first);
  });

  test('a damaged key in the Keychain fails the load instead of making a new one', () async {
    FlutterSecureStorage.setMockInitialValues({
      'zen_store.key': base64Encode([1, 2, 3]),
    });

    expect((await ZenKeychainStoreKey.load()).errorOrNull, isA<ZenUnknownError>());
  });
}
