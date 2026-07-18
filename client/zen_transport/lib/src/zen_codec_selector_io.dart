// Ported from ../DartZen/packages/dartzen_transport/lib/src/zen_codec_selector_io.dart,
// with MessagePack replaced by Protobuf binary.
import 'zen_transport_header.dart';

/// Native platform (mobile/server/desktop) codec selector.
///
/// On native platforms in production mode, use Protobuf binary for efficiency.
ZenTransportFormat selectPlatformCodec() => ZenTransportFormat.protobuf;
