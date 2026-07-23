import 'zen_transport_header.dart';

/// Native platform (mobile/server/desktop) codec selector.
///
/// On native platforms in production mode, use Protobuf binary for efficiency.
ZenTransportFormat selectPlatformCodec() => ZenTransportFormat.protobuf;
