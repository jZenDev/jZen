/// Dual-mode transport for the jZen client.
///
/// One header (`X-Zen-Transport`) negotiates between canonical proto3 JSON and Protobuf
/// binary over the same typed endpoints. Callers send and receive typed protobuf messages;
/// there is no envelope.
library;

export 'src/generated/zen/v1/common.pb.dart';
export 'src/generated/zen/v1/demo.pb.dart';
export 'src/generated/zen/v1/health.pb.dart';
export 'src/generated/zen/v1/identity.pb.dart';
export 'src/http/session_client.dart' show createSessionClient;
export 'src/zen_client.dart'
    show ZenClient, acceptLanguageHeaderName, requestIdHeaderName;
export 'src/zen_codec_selector.dart' show selectDefaultCodec;
export 'src/zen_http_method.dart' show ZenHttpMethod;
export 'src/zen_proto_codec.dart';
export 'src/zen_transport_error.dart';
export 'src/zen_transport_exception.dart';
export 'src/zen_transport_header.dart';
export 'src/zen_websocket.dart' show ZenWebSocket;
