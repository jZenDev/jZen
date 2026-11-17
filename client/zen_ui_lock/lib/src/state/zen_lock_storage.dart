import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zen_core/zen_core.dart';

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
///
/// A macOS *non-release development* build (`ZEN_ENV=dev`, not `--release`; the Taskfile defaults
/// `ZEN_ENV` to `dev`, so it alone does not mean development) uses the file (login) keychain instead, because the
/// data-protection keychain fails with -34018 in a build with no signing identity (ADR-087). There
/// the hash and the failure counter can be in a backup, and restoring one resets the lockout. A dev
/// build accepts that only because whoever holds the backup also holds the store key and the data,
/// so the PIN there is a lock on the screen, not on the data. A release build keeps the
/// data-protection keychain and `first_unlock_this_device`.
final class ZenSecureLockStorage implements ZenLockStorage {
  final FlutterSecureStorage _storage;

  /// Uses [storage], or the Keychain with the options above.
  ZenSecureLockStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          FlutterSecureStorage(
            iOptions: const IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            mOptions: macOsOptions(dev: zenIsDevBuild),
          );

  /// The macOS keychain options for a non-release development build ([dev], from `zenIsDevBuild`)
  /// or any other build.
  @visibleForTesting
  static MacOsOptions macOsOptions({required bool dev}) => dev
      ? const MacOsOptions(usesDataProtectionKeychain: false)
      : const MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device);

  /// The storage [ZenSecureLockStorage] uses when none is passed; exposed so a test can pin it.
  @visibleForTesting
  FlutterSecureStorage get storage => _storage;

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
