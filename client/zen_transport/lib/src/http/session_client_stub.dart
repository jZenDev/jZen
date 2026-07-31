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
ZenSessionClient createPlatformSessionClient({TokenStore? store}) =>
    PassthroughSessionClient(http.Client());
