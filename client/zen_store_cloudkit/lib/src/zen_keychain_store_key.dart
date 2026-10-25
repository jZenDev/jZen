import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zen_core/zen_core.dart';

/// The key a `ZenStore` encrypts its files with, kept in the Keychain and never beside the data.
///
/// `unlocked_this_device`: readable only while the device is unlocked, never in a backup, never on
/// another device. Each device has its own key for its own files; what travels between devices is
/// protected by CloudKit's own encryption, not by this key.
abstract final class ZenKeychainStoreKey {
  static const String _defaultName = 'zen_store.key';
  static const MethodChannel _channel = MethodChannel('zen_store_cloudkit');

  /// This device's store key, made on first use.
  ///
  /// Fails when the Keychain cannot be read — never by making a new key in its place, which would
  /// leave the existing files unreadable for good.
  static Future<ZenResult<List<int>>> load({
    FlutterSecureStorage? storage,
    String name = _defaultName,
  }) async {
    final keychain =
        storage ??
        const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
          mOptions: MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device),
        );
    try {
      final stored = await keychain.read(key: name);
      if (stored != null) {
        final key = base64Decode(stored);
        if (key.length != 32) {
          return const ZenResult.err(
            ZenUnknownError('The store key in the Keychain is not 32 bytes.'),
          );
        }
        return ZenResult.ok(key);
      }
      final random = Random.secure();
      final key = List<int>.generate(32, (_) => random.nextInt(256));
      await keychain.write(key: name, value: base64Encode(key));
      return ZenResult.ok(key);
    } on Object catch (e, stack) {
      return ZenResult.err(ZenUnknownError('The store key cannot be read: $e', stackTrace: stack));
    }
  }

  /// Gives [directory] iOS Data Protection `complete`: unreadable while the device is locked, and
  /// inherited by every file the store writes there. Call it before `ZenStore.open`. Succeeds with
  /// false on macOS, which has no such class — the store's own encryption protects it there.
  static Future<ZenResult<bool>> protectDirectory(Directory directory) async {
    try {
      final protected = await _channel.invokeMethod<bool>('protectDirectory', {
        'path': directory.path,
      });
      return ZenResult.ok(protected ?? false);
    } on MissingPluginException {
      return const ZenResult.ok(false);
    } on PlatformException catch (e, stack) {
      return ZenResult.err(
        ZenUnknownError(
          'Data Protection could not be set on ${directory.path}: ${e.message}',
          stackTrace: stack,
        ),
      );
    }
  }
}
