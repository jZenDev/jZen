# zen_transport

The client half of jZen's **dual-mode transport**. A developer names a domain model; this package
negotiates the wire format. `ZenClient` speaks to a jZen backend over HTTP, and one setting — the
`X-Zen-Transport` header — chooses whether a request travels as canonical proto3 **JSON** or
**Protobuf binary**, over the same typed endpoints. It also carries `ZenWebSocket` (typed proto
frames) and the generated Protobuf message classes.

> Part of the [jZen](https://github.com/jZenDev/jZen) monorepo. Inside the repo it is a path
> dependency in the `client/` pub workspace, versioned in lockstep with the product; this README
> also stands on its own for a reader who meets the package by itself.

## What it provides

- **`ZenClient`** — the dual-mode HTTP client. It returns a `ZenResult` (from `zen_core`) and
  **surfaces a `ZenError` on a decode failure** rather than a null payload — a silent failure is
  worse than a loud one.
- **`ZenWebSocket`** — a typed WebSocket that sends and receives proto messages; single-format
  (binary Protobuf), because the dual JSON/Protobuf negotiation is an HTTP-only concern.
- **The compile-time codec selector** — `selectDefaultCodec()` computes the default wire format
  from the build (`dev` → JSON; `prd` native → Protobuf; `prd` web → JSON). It is **computed,
  never hardcoded**: a literal default would silently disable negotiation on the platform it is
  wrong for.
- **Generated messages** (`lib/src/generated/`) — the Dart output of `proto/zen/v1/*.proto`. These
  are **tracked** generated files (a Flutter developer must compile without `protoc` or a JDK);
  never hand-edit them, and `task sync:contracts` fails if they drift. See [`../README.md`](../README.md).

## Client config is compile-time

Wire format and platform come from `String.fromEnvironment` build defines (`ZEN_ENV`,
`ZEN_PLATFORM`) plus `dart.library.io` / `dart.library.html` conditional imports, so the toolchain
can tree-shake the Protobuf binary path out of a web bundle and web code out of a native binary.
Runtime config on the client is forbidden (STANDARDS "Client config is compile-time").

## Using it

```yaml
dependencies:
  zen_transport:
    path: ../zen_transport
```

## Testing

`task test:client` runs the suite; `task test:client:matrix` recompiles the codec selector per
`ZEN_ENV`/platform. Directly: `cd client/zen_transport && dart test test/zen_client_test.dart`.
