import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zen_core/zen_core.dart';

/// The key a `ZenStore` encrypts its files with, kept in the platform's secret storage and never
/// beside the data.
///
/// | Platform | Where | Guarantee |
/// |---|---|---|
/// | iOS, macOS | Keychain, `unlocked_this_device` | readable only while unlocked; never in a backup, never on another device |
/// | Android | Keystore-wrapped AES key; the wrapped value in the app's private storage | the wrapping key cannot leave the device; **not** tied to the screen lock |
/// | Windows | a key in Credential Manager (this machine, this user) encrypts a file under `%APPDATA%` | the file is useless on another machine |
/// | Linux | libsecret (GNOME Keyring, KWallet, or the portal) | as strong as the unlocked login keyring |
///
/// Each device has its own key for its own files; what travels between devices is protected by the
/// sync transport (CloudKit's encryption, or the shared sync key), not by this key.
abstract final class ZenDeviceStoreKey {
  static const String _defaultName = 'zen_store.key';

  /// This device's store key, made on first use.
  ///
  /// [dataDirectory] is the directory the store opens. It is how this class tells "no key yet"
  /// from "the key cannot be read": a plugin may answer a failed read with `null` (the Windows
  /// plugin does, whenever the stored value cannot be decrypted), and `null` with files already
  /// there means those files can no longer be opened -- making a key then would hide that and
  /// orphan them for good. So a missing key beside existing files, a key that cannot be read, a
  /// stored value that is not 32 bytes, a key that cannot be written and a secret service that is
  /// absent or locked all fail the load. None of them makes a new key.
  static Future<ZenResult<List<int>>> load({
    required Directory dataDirectory,
    FlutterSecureStorage? storage,
    String name = _defaultName,
  }) async {
    final secrets = storage ?? platformStorage;
    try {
      final stored = await secrets.read(key: name);
      if (stored != null) {
        final List<int> key;
        try {
          key = base64Decode(stored);
        } on FormatException {
          return const ZenResult.err(ZenUnknownError('The stored store key is not valid base64.'));
        }
        if (key.length != 32) {
          return const ZenResult.err(ZenUnknownError('The stored store key is not 32 bytes.'));
        }
        return ZenResult.ok(key);
      }
      if (_holdsFiles(dataDirectory)) {
        return ZenResult.err(
          ZenUnknownError(
            'The store key is missing but ${dataDirectory.path} already holds data. Making a new '
            'key would leave that data unreadable for good, so none was made. Restore the key, or '
            'erase this device\'s copy and let it sync again from your other devices.',
          ),
        );
      }
      final random = Random.secure();
      final key = List<int>.generate(32, (_) => random.nextInt(256));
      await secrets.write(key: name, value: base64Encode(key));
      return ZenResult.ok(key);
    } on Object catch (e, stack) {
      return ZenResult.err(ZenUnknownError('The store key cannot be read: $e', stackTrace: stack));
    }
  }

  static bool _holdsFiles(Directory directory) =>
      directory.existsSync() && directory.listSync().isNotEmpty;

  // `resetOnError: false` is load-bearing. The Android plugin's default answers a failed Keystore
  // call by deleting every stored value and reporting success, which turns "the key cannot be
  // unwrapped" into "there is no key" -- the very thing this class must never do silently.
  /// The storage [load] uses when none is passed; exposed so a test can pin its options.
  @visibleForTesting
  static const FlutterSecureStorage platformStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device),
    aOptions: AndroidOptions(resetOnError: false),
  );
}
