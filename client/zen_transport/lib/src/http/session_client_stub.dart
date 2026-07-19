// Stub implementation for platforms that are neither dart:io nor dart:html. Mirrors
// zen_codec_selector_stub.dart. It returns a plain client rather than throwing, so a
// consumer on an exotic platform still functions (just without cookie persistence).
import 'package:http/http.dart' as http;

/// Fallback: a plain [http.Client] with no cookie handling.
http.Client createPlatformSessionClient() => http.Client();
