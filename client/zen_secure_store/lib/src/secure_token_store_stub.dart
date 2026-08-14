import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zen_transport/zen_transport.dart';

/// Fallback branch of the seam in `secure_token_store.dart`, for a platform that is neither
/// `dart.library.io` nor `dart.library.js_interop`. This should never be selected in practice —
/// every jZen delivery target is one or the other — but if it ever is, refusing is still the
/// correct behaviour: there is no platform secure storage to reach here, and constructing a
/// stand-in that silently drops the token would be the exact class of defect F4 exists to close.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage, String key = 'zen_refresh_token'}) {
    throw UnsupportedError('SecureTokenStore: platform not supported (neither io nor web).');
  }

  @override
  Future<String?> read() => throw UnsupportedError('unreachable: the constructor already threw');

  @override
  Future<void> write(String token) =>
      throw UnsupportedError('unreachable: the constructor already threw');

  @override
  Future<void> delete() => throw UnsupportedError('unreachable: the constructor already threw');
}
