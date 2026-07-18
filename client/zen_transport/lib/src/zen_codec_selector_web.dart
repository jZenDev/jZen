// Ported verbatim from
// ../DartZen/packages/dartzen_transport/lib/src/zen_codec_selector_web.dart.
import 'zen_transport_header.dart';

/// Web platform codec selector.
///
/// On web, always use JSON even in production mode.
ZenTransportFormat selectPlatformCodec() => ZenTransportFormat.json;
