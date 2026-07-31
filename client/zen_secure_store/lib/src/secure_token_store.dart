import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zen_transport/zen_transport.dart';

/// A [TokenStore] backed by the operating system's own credential store.
///
/// Keychain on iOS and macOS, Keystore-backed `EncryptedSharedPreferences` on Android. No branch
/// picks between them: the plugin resolves the backend per platform, so the compile-time
/// `zenIsIOS` / `zenIsAndroid` / `zenIsMacOS` constants are deliberately not used here — they
/// would add a decision without changing an outcome.
///
/// **Why the OS store and not a file.** OWASP MASVS-STORAGE-1 requires persisted session tokens
/// to live in platform secure storage. That is not ceremony: an app-support file is readable by
/// any process running as the user on macOS, and rides along in device backups on mobile. A
/// refresh token is a seven-day credential for the account, so a file would make persistence a
/// downgrade rather than a feature.
///
/// Only the refresh token is ever handed here. The access token stays in memory for the life of
/// the process — an hour long and re-obtainable, so writing it down would widen what sits at
/// rest to save one round trip.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage, String key = _defaultKey})
      : _storage = storage ?? const FlutterSecureStorage(
              // The token is only ever needed while the app is in use, so it does not need to be
              // readable before the first unlock after a reboot. `first_unlock_this_device` is
              // the tighter accessibility class that still works: it keeps the item off backups
              // and off any other device, so a restored backup cannot carry the session with it.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
              // No AndroidOptions: `encryptedSharedPreferences` is deprecated from 10.x (Google
              // deprecated the Jetpack Security library behind it) and is ignored when passed.
              // The plugin now encrypts with its own ciphers by default and migrates existing
              // data on first access, so the secure default is the one you get by saying nothing.
            ),
        _key = key;

  static const String _defaultKey = 'zen_refresh_token';

  final FlutterSecureStorage _storage;
  final String _key;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
