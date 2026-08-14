import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zen_transport/zen_transport.dart';

/// The web branch of the seam in `secure_token_store.dart`. Refuses loudly rather than
/// constructing: `flutter_secure_storage` resolves to `flutter_secure_storage_web` on a web
/// build, which stores in `window.localStorage` — readable by any XSS, with
/// `KeychainAccessibility.first_unlock_this_device` silently meaningless because there is no
/// Keychain in a browser. See the 2026-08-13 architectural security review, F4.
///
/// The refresh token belongs in the httpOnly `zen_refresh_token` cookie on web instead, which the
/// browser already attaches to same-origin requests on its own — see `zen_transport`'s
/// `BrowserSessionClient`. There is nothing for a `TokenStore` to do on this platform, so nothing
/// should construct one; a caller that reaches this constructor has a bug to fix, not a value to
/// receive.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage, String key = 'zen_refresh_token'}) {
    throw UnsupportedError(
      'SecureTokenStore cannot be used on web: flutter_secure_storage falls back to '
      'window.localStorage there, which any XSS can read. The refresh token belongs in the '
      "httpOnly zen_refresh_token cookie on web — the browser's own cookie jar already holds it, "
      'so no TokenStore is needed on this platform. Pass null instead (zen_demo\'s main.dart is '
      'the reference: `zenIsWeb ? null : SecureTokenStore()`).',
    );
  }

  @override
  Future<String?> read() => throw UnsupportedError('unreachable: the constructor already threw');

  @override
  Future<void> write(String token) =>
      throw UnsupportedError('unreachable: the constructor already threw');

  @override
  Future<void> delete() => throw UnsupportedError('unreachable: the constructor already threw');
}
