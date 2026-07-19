// The compile-time platform seam for session persistence, structured exactly like
// zen_codec_selector.dart (TA-7, docs/architecture/STANDARDS.md): a default library that
// imports the stub, with `dart.library.io` / `dart.library.html` swapping in the native or
// web implementation so the toolchain tree-shakes the wrong platform's code out of each bundle.
//
// The gap this closes (ROADMAP step 4): the Supabase session lives in httpOnly cookies the
// server sets; SupabaseIdentityRepository relies on them being resent on later requests. On
// the web the browser does that automatically - but only if the client sends credentials
// cross-origin - and on native nothing did it at all, so a login -> getCurrentIdentity round
// trip could not hold a session off-web. createSessionClient() returns the right http.Client
// for the platform: a native cookie jar, or a credentialed browser client.
import 'package:http/http.dart' as http;

import 'session_client_stub.dart'
    if (dart.library.html) 'session_client_web.dart'
    if (dart.library.io) 'session_client_io.dart';

/// Returns an [http.Client] that persists and resends the session cookies for the current
/// platform, so a `ZenClient` built with it maintains a Supabase session across requests.
///
/// - Native (`dart:io`): an in-memory cookie jar backed by a `dart:io` `HttpClient`, reading
///   `Set-Cookie` and attaching `Cookie` on subsequent requests to the same host.
/// - Web (`dart:html`): a `BrowserClient` with `withCredentials = true`, so the browser sends
///   the httpOnly session cookies cross-origin.
/// - Other: a plain client (the stub); it should never be selected in practice.
http.Client createSessionClient() => createPlatformSessionClient();
