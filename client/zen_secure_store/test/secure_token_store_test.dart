// Mocks the plugin's platform channel rather than the plugin's Dart class: FlutterSecureStorage
// is a concrete class, so faking it would mean faking the thing under test. Driving the channel
// asserts what actually crosses into the keystore.
//
// The behaviour of persistence itself - rotation, expiry, logout - is tested in zen_transport
// against the port, where it runs on the VM. This file covers only what is specific to the
// keystore adapter, and the key it stores under, because changing that key would sign every
// existing user out silently.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_secure_store/zen_secure_store.dart';
import 'package:zen_transport/zen_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late List<MethodCall> calls;
  late Map<String, String> backing;

  setUp(() {
    calls = [];
    backing = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String?;
        switch (call.method) {
          case 'write':
            backing[key!] = args['value'] as String;
            return null;
          case 'read':
            return backing[key];
          case 'delete':
            backing.remove(key);
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  test('is a TokenStore, so the transport port can hold it', () {
    expect(SecureTokenStore(), isA<TokenStore>());
  });

  test('round-trips a token through the platform channel', () async {
    final store = SecureTokenStore();

    expect(await store.read(), isNull);

    await store.write('refresh-token-value');
    expect(await store.read(), 'refresh-token-value');

    await store.delete();
    expect(await store.read(), isNull);
  });

  test('stores under the agreed key', () async {
    await SecureTokenStore().write('v');

    final write = calls.firstWhere((c) => c.method == 'write');
    // Pinned deliberately: a renamed key is not a migration, it is every signed-in user being
    // quietly signed out on the update that ships it.
    expect((write.arguments as Map)['key'], 'zen_refresh_token');
  });

  test('a custom key is honoured, so two apps can share a device', () async {
    await SecureTokenStore(key: 'other_app_refresh').write('v');

    final write = calls.firstWhere((c) => c.method == 'write');
    expect((write.arguments as Map)['key'], 'other_app_refresh');
  });

  test('delete succeeds when nothing was ever stored', () async {
    // The port requires this: a launch that finds a corrupt entry deletes before it ever wrote.
    await expectLater(SecureTokenStore().delete(), completes);
  });
}
