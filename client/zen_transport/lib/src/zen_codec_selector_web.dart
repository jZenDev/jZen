import 'zen_transport_header.dart';

/// Web platform codec selector.
///
/// On web, always use JSON even in production mode.
ZenTransportFormat selectPlatformCodec() => ZenTransportFormat.json;
