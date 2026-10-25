import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the lock keeps the PIN's hash and the count of wrong attempts.
abstract interface class ZenLockStorage {
  /// The value stored under [key], or null.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);

  /// Removes [key].
  Future<void> delete(String key);
}

/// The default [ZenLockStorage]: the Keychain on iOS and macOS.
///
/// `first_unlock_this_device` keeps the items off backups and off every other device, so a
/// restored backup or a second Mac signed into the same iCloud does not carry this device's PIN —
/// each device gets its own, which is what a person setting one expects.
final class ZenSecureLockStorage implements ZenLockStorage {
  final FlutterSecureStorage _storage;

  /// Uses [storage], or the Keychain with the options above.
  ZenSecureLockStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// A [ZenLockStorage] in memory, for tests and previews. It forgets everything when the process
/// ends, so it is never what a shipped app should use.
final class ZenMemoryLockStorage implements ZenLockStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
