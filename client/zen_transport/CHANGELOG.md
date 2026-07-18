# Changelog

## 0.1.0

- Initial re-architecture from `dartzen_transport`. Keeps the negotiation seam (renamed
  header `X-Zen-Transport`, `selectDefaultCodec` compile-time selector) and the HTTP client,
  but:
  - replaces the hand-written MessagePack binary codec with **Protobuf** (`ZenProtoCodec`:
    binary via the protobuf runtime, JSON via canonical proto3 JSON), committing the
    generated messages under `lib/src/generated/`;
  - drops the `{id,status,data,error}` envelope in favor of typed proto request/response
    bodies;
  - removes the Shelf server middleware, the `ZenTransport`/executor facade, the duplicate
    barrels, and the `shelf` dependency;
  - fixes two donor bugs (TA-6): `ZenClient` now defaults its format via `selectDefaultCodec`
    and surfaces a `ZenError` (common.proto) on any decode failure instead of silently
    returning null.
