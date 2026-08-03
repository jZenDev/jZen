// Stub implementation for platforms that are neither dart:io nor dart:html. Mirrors
// zen_codec_selector_stub.dart. It returns a plain client rather than throwing, so a
// consumer on an exotic platform still functions (just without cookie persistence).
import 'package:http/http.dart' as http;

import 'token_store.dart';
import 'zen_session_client.dart';

/// Fallback: a plain [http.Client] with no cookie handling.
///
/// [store] is accepted for signature parity across the seam and ignored, because a client that
/// cannot hold a cookie for the length of one session has nothing worth holding between two.
///
/// It echoes no CSRF token either, for the same reason and with the same consequence: with no
/// cookie store there is no session cookie to send, so the server has nothing to enforce against
/// and the request is refused as anonymous rather than as forged. Nothing is being skipped here
/// that would otherwise have been checked.
ZenSessionClient createPlatformSessionClient({TokenStore? store}) =>
    PassthroughSessionClient(http.Client());
