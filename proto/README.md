# proto/ — the canonical contract

`proto/zen/v1/` holds the **protobuf contract**, and it is the single source of truth for jZen's
**models**. jZen serves a Flutter client, a react-admin panel, and native apps from one backend,
so the contract is canonical and everything downstream is derived — Java DTOs, Dart messages,
OpenAPI model schemas, and TypeScript types are all **generated** from these files. This is the
mechanism the MANIFESTO calls "no *custom* magic": hand-syncing three languages is manual magic
that drifts silently, so a standard, inspectable generator plus a gate does it instead.

The directory path mirrors the proto package: `proto/zen/v1/` ⇒ package `zen.v1`. **`v1` is the
API/wire version** and evolves on its own schedule, independent of the product version — a
product major can ship while the API stays `zen.v1`, and a breaking API change would introduce
`zen.v2` protos *alongside* `v1` (STANDARDS "Versioning").

## The files

| File | Models for |
|---|---|
| `common.proto` | Cross-cutting shapes used everywhere: `ZenError`, `PageRequest`. |
| `health.proto` | The health surface. |
| `identity.proto` | The Supabase auth flows (register, login, identity, …). |
| `admin.proto` | The admin panel's management surface (`AdminUser`). |
| `demo.proto` | The reference app's demo endpoints (ping, terms, profile, the WebSocket echo). |
| `jobs.proto` | Guaranteed scheduled work (`zen-jobs`). |

Every endpoint declares its **own** request and response messages here — there is no generic
payload type and no envelope. HTTP status carries the status, `X-Request-ID` carries the request
id, and `ZenError` carries the error. That per-endpoint cost is what buys the contract-first
guarantee: an untyped `data` field would put the payload shape back outside the contract, where
nothing could generate a client from it (STANDARDS "Source of truth").

Note the division of authority: **proto is canonical for models; the SmallRye-annotated Quarkus
resources are canonical for the REST surface** (paths, verbs, status codes) that proto cannot
express. Both feed the same `openapi.json`.

## How each language consumes it

```
proto/zen/v1/*.proto
  ├─ protoc ──▶ Java DTOs      (protobuf-maven-plugin, in server/zen-proto)
  ├─ protoc ──▶ Dart messages  (protoc_plugin, via the Taskfile)
  └─ protoc ──▶ model schemas ─┐
                               ├─▶ merged openapi.json ─▶ openapi-typescript ─▶ admin types
  Quarkus resources ── paths ──┘
```

Some generated output is **tracked** and some is not — an artifact is committed exactly when the
toolchain that consumes it cannot produce it (STANDARDS "Code generation"):

- **Tracked:** the Dart messages (`client/zen_transport/lib/src/generated/**`) and the admin
  `schema.generated.ts` — so a Flutter or frontend developer never needs `protoc` or a JDK to
  compile.
- **Not tracked:** the Java DTOs (`server/zen-proto/target/…`) and `openapi.json`, which live
  under `target/` because Maven resolves `protoc` from Maven Central itself.

## Regenerating, and the drift gate

Edit a `.proto`, then run the contract-first loop:

```bash
task sync:contracts
```

It regenerates every cross-language artifact and **fails if any committed generated file
changed** — the exact bug class the gate exists to stop. A red `sync:contracts` means a
generated file was hand-edited, or a `.proto` changed without regenerating. Fix it by running
`task generate:proto generate:api` and committing the result, **never** by editing generated
output. Wire `sync:contracts` into CI as a required check.

Regenerating the Dart messages needs a *system* `protoc` plus `protoc-gen-dart` (see `task
doctor`); the Java DTOs are produced hermetically by `./mvnw` alone.
