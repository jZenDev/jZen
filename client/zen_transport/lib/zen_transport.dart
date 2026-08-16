/// Dual-mode transport for the jZen client.
///
/// One header (`X-Zen-Transport`) negotiates between canonical proto3 JSON and Protobuf
/// binary over the same typed endpoints. Callers send and receive typed protobuf messages;
/// there is no envelope.
library;

// The generated messages sit at `lib/generated/`, not `lib/src/generated/`, deliberately: they
// are a PUBLIC path (ADR-047). An application whose own `.proto` imports `zen/v1` gets generated
// code that must name these files one by one — a barrel import cannot satisfy a generated
// per-message import — and `package:zen_transport/src/…` is an implementation import, which the
// recommended lint set rejects. The directory keeps the name `generated` so the repository's
// existing `**/generated/**` conventions (the analyzer exclude, DART_FORMAT) keep covering it.
export 'generated/zen/v1/common.pb.dart';
export 'generated/zen/v1/demo.pb.dart';
export 'generated/zen/v1/health.pb.dart';
export 'generated/zen/v1/identity.pb.dart';
export 'src/http/session_client.dart' show createSessionClient;
export 'src/http/token_store.dart' show InMemoryTokenStore, TokenStore;
export 'src/http/zen_session_client.dart' show PassthroughSessionClient, ZenSessionClient;
export 'src/zen_client.dart' show ZenClient, acceptLanguageHeaderName, requestIdHeaderName;
export 'src/zen_codec_selector.dart' show selectDefaultCodec;
export 'src/zen_http_method.dart' show ZenHttpMethod;
export 'src/zen_proto_codec.dart';
export 'src/zen_transport_error.dart';
export 'src/zen_transport_exception.dart';
export 'src/zen_transport_header.dart';
export 'src/zen_websocket.dart' show ZenWebSocket;
