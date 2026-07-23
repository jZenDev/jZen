# Changelog

## 0.1.0

- Initial release. The dual-mode transport seam and the HTTP client:
  - one header (`X-Zen-Transport`) negotiates canonical proto3 JSON or Protobuf binary over
    the same typed endpoints, with `selectDefaultCodec` choosing the default at compile time
    so the wrong platform's codec tree-shakes out of each bundle;
  - `ZenProtoCodec` carries typed protobuf bodies: binary via the protobuf runtime, JSON via
    canonical proto3 JSON. The generated messages are committed under `lib/src/generated/`;
  - request and response bodies are typed proto messages with no envelope. HTTP status
    carries the status, `X-Request-ID` carries the request id, and the shared `ZenError`
    proto carries errors;
  - `ZenClient` never swallows a failure: any decode failure surfaces a `ZenError` rather
    than a null payload;
  - `ZenWebSocket` sends and receives the same typed messages over binary frames.
