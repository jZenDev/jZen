import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store_key/zen_store_key.dart';

// The plugin's native halves (Keystore, Credential Manager, libsecret) cannot run here, so these
// pin what this class does with every answer they can give: a value, nothing, a failure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zen_store_key_test');
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() => root.deleteSync(recursive: true));

  Directory data([String name = 'store']) => Directory('${root.path}/$name');

  test('the key is made once, 32 bytes, and the same on every later load', () async {
    final first = (await ZenDeviceStoreKey.load(dataDirectory: data())).dataOrNull!;
    final second = (await ZenDeviceStoreKey.load(dataDirectory: data())).dataOrNull!;

    expect(first, hasLength(32));
    expect(second, first);
  });

  test('a first run may find an empty directory', () async {
    final directory = data()..createSync();

    expect((await ZenDeviceStoreKey.load(dataDirectory: directory)).dataOrNull, hasLength(32));
  });

  test('a stored key is returned even when the directory holds files', () async {
    final directory = data()..createSync();
    final key = List<int>.generate(32, (i) => i);
    FlutterSecureStorage.setMockInitialValues({'zen_store.key': base64Encode(key)});
    File('${directory.path}/a.zen').writeAsBytesSync([1]);

    expect((await ZenDeviceStoreKey.load(dataDirectory: directory)).dataOrNull, key);
  });

  test('a missing key beside existing files fails the load and writes no key', () async {
    final directory = data()..createSync();
    File('${directory.path}/a.zen').writeAsBytesSync([1]);

    final result = await ZenDeviceStoreKey.load(dataDirectory: directory);

    expect(result.errorOrNull, isA<ZenUnknownError>());
    expect(await const FlutterSecureStorage().read(key: 'zen_store.key'), isNull);
  });

  test('a damaged key fails the load instead of making a new one', () async {
    for (final damaged in [
      base64Encode([1, 2, 3]),
      '%%not base64%%',
    ]) {
      FlutterSecureStorage.setMockInitialValues({'zen_store.key': damaged});

      expect(
        (await ZenDeviceStoreKey.load(dataDirectory: data())).errorOrNull,
        isA<ZenUnknownError>(),
        reason: damaged,
      );
      expect(await const FlutterSecureStorage().read(key: 'zen_store.key'), damaged);
    }
  });

  group('a secret service that answers with an error', () {
    // Every platform's plugin reports a failure as an exception on the channel; Linux uses the
    // codes below for no secret service and for a locked keyring.
    for (final code in ['Libsecret error', 'KeyringLocked']) {
      test('"$code" on read fails the load and never writes a key', () async {
        final secrets = _FakeSecrets(
          failRead: PlatformException(code: code, message: 'no'),
        );

        final result = await ZenDeviceStoreKey.load(dataDirectory: data(), storage: secrets);

        expect(result.errorOrNull, isA<ZenUnknownError>());
        expect(secrets.writes, 0);
      });
    }

    test('a key that cannot be written fails the load, so no key is handed out unsaved', () async {
      final secrets = _FakeSecrets(failWrite: PlatformException(code: 'Libsecret error'));

      final result = await ZenDeviceStoreKey.load(dataDirectory: data(), storage: secrets);

      expect(result.errorOrNull, isA<ZenUnknownError>());
      expect(result.dataOrNull, isNull);
    });
  });

  test('Android is told not to wipe the stored values when the Keystore fails', () {
    // The plugin's default deletes everything on an error and reports success, which would turn
    // "cannot unwrap the key" into "no key" and then into a new one.
    expect(ZenDeviceStoreKey.platformStorage.aOptions.toMap()['resetOnError'], 'false');
  });
}

class _FakeSecrets implements FlutterSecureStorage {
  _FakeSecrets({this.failRead, this.failWrite});

  final Object? failRead;
  final Object? failWrite;
  int writes = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failRead != null) throw failRead!;
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes++;
    if (failWrite != null) throw failWrite!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
