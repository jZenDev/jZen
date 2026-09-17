import 'package:flutter_test/flutter_test.dart';
import 'package:zen_demo_client/src/auth_deep_links_native.dart';

void main() {
  group('isRegisteredAuthLink', () {
    const redirectUri = 'zendemo://auth-callback';

    test('accepts the registered custom-scheme link', () {
      expect(
        isRegisteredAuthLink(
          Uri.parse('zendemo://auth-callback?auth=email-confirmed'),
          redirectUri: redirectUri,
        ),
        isTrue,
      );
    });

    test('accepts the https App Link path regardless of host', () {
      expect(
        isRegisteredAuthLink(
          Uri.parse('https://demo.example.com/auth/callback?auth=email-confirmed'),
          redirectUri: redirectUri,
        ),
        isTrue,
      );
    });

    test('rejects a URI with the wrong scheme', () {
      expect(
        isRegisteredAuthLink(
          Uri.parse('otherapp://auth-callback?auth=email-confirmed'),
          redirectUri: redirectUri,
        ),
        isFalse,
      );
    });

    test('rejects a URI with the right scheme but the wrong host', () {
      expect(
        isRegisteredAuthLink(
          Uri.parse('zendemo://not-auth-callback?auth=email-confirmed'),
          redirectUri: redirectUri,
        ),
        isFalse,
      );
    });

    test('rejects an https URI outside the App Link path', () {
      expect(
        isRegisteredAuthLink(
          Uri.parse('https://demo.example.com/some/other/path'),
          redirectUri: redirectUri,
        ),
        isFalse,
      );
    });

    test('rejects everything when no redirect URI is configured', () {
      expect(
        isRegisteredAuthLink(
          Uri.parse('zendemo://auth-callback?auth=email-confirmed'),
          redirectUri: '',
        ),
        isFalse,
      );
    });
  });
}
