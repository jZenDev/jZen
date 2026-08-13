// Direct import of the web branch of the seam in `secure_token_store.dart`. The conditional
// export in that file only ever compiles this branch into an actual web build, so the default
// `flutter test` run (which resolves `dart.library.io`) never exercises it — importing it by its
// concrete path, the way `secure_token_store_test.dart` never needs to, is what proves the F4 fix
// actually refuses on web rather than merely compiling.
//
// This file has no dart:js_interop or dart:html dependency of its own (it never reaches the
// browser at all — it throws before it would), so it runs on the plain VM/tester like any other
// test here; it does not need `-p chrome` the way `session_client_web_test.dart` does.
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_secure_store/src/secure_token_store_web.dart';

void main() {
  test('refuses to construct on web rather than falling back to localStorage', () {
    expect(() => SecureTokenStore(), throwsUnsupportedError);
  });

  test('the refusal names the reason, not just "unsupported"', () {
    try {
      SecureTokenStore();
      fail('expected UnsupportedError');
    } on UnsupportedError catch (e) {
      expect(e.message, contains('localStorage'));
      expect(e.message, contains('zen_refresh_token'));
    }
  });

  test('a custom key does not change the refusal', () {
    expect(() => SecureTokenStore(key: 'other_app_refresh'), throwsUnsupportedError);
  });
}
