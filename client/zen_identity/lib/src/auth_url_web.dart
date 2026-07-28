import 'dart:js_interop';

/// Web implementation of the address-bar cleanup.
///
/// Selected on `dart.library.js_interop`, which every web compiler defines — dart2js *and*
/// dart2wasm. Keying on `dart.library.html` instead would miss under Wasm and silently fall
/// through to the stub, leaving the token in the URL on exactly the build jZen deploys.
///
/// `replaceState` rather than an assignment to `location`: it rewrites the current history entry
/// in place, so nothing reloads and no extra Back-button step appears. Both the fragment (the
/// tokens) and the `?auth` flag go, because both describe a landing that has already happened.
void clearAuthLinkFromUrl() {
  final base = Uri.base.removeFragment();
  final params = Map<String, String>.of(base.queryParameters)..remove('auth');
  final path = base.path.isEmpty ? '/' : base.path;
  final url = params.isEmpty ? path : '$path?${Uri(queryParameters: params).query}';
  _replaceState(null, ''.toJS, url.toJS);
}

// A relative URL is what replaceState wants here: it resolves against the current document, so
// the origin cannot drift and no absolute URL has to be reconstructed correctly.
@JS('window.history.replaceState')
external void _replaceState(JSAny? data, JSString unused, JSString url);
