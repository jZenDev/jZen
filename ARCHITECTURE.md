# Architecture

jZen is a **framework/platform**, not a single deployable app: `server/` (Java/Quarkus) and
`client/` (Dart/Flutter) are reusable libraries, and `apps/<app>/{<app>_client, <app>_server,
<app>_admin}` are the applications that assemble them. The one mechanism the rest is arranged
around is a **dual-mode transport**: a developer defines a domain model and one request header,
`X-Zen-Transport`, negotiates whether it travels the wire as canonical proto3 JSON or Protobuf
binary — over the same typed endpoints, with no branch in the resource or the caller.

```
proto/zen/v1/*.proto  ──protoc──▶ Java DTOs + Dart messages + OpenAPI model schemas
Quarkus resources     ──▶ REST paths/verbs/status ──▶ openapi.json ──▶ admin TypeScript types
```

An application is either **full-stack** — client, server and admin panel, as above — or
**light**: the Flutter client alone, with no server and no sign-in, its data in `zen_store` on the
user's own devices and synced through their iCloud (macOS and iOS). Light sync merges edits field
by field and hands anything that cannot merge to the person as a conflict to decide, in
`zen_ui_store`'s screens; an optional
PIN (`zen_ui_lock`) closes the app in place of a login. The `.proto` models are the same in both
shapes, so a light app can later grow a server without changing them (ADR-065).

`.proto` is canonical for **models**; the Quarkus resources are canonical for the **REST
surface**. Everything else — Java DTOs, Dart messages, `openapi.json`, TS types — is generated,
and `task verify:contracts` fails the build if a generated file drifts from what its source
produces.

This file is a map, not the source of truth — it exists so a reader new to the repository knows
where to look next. The documents it points at are:

| Document | Answers |
|---|---|
| [`docs/ZEN_ARCHITECTURE.md`](docs/ZEN_ARCHITECTURE.md) | What is the design philosophy, independent of jZen's specific stack? |
| [`docs/architecture/MANIFESTO.md`](docs/architecture/MANIFESTO.md) | What does jZen specifically believe, and why these technology choices? |
| [`docs/architecture/BLUEPRINT.md`](docs/architecture/BLUEPRINT.md) | What is the architecture as actually built, module by module? |
| [`docs/architecture/STANDARDS.md`](docs/architecture/STANDARDS.md) | What are the rules that keep the architecture honest, enforced by which gate? |
| [`docs/architecture/ROADMAP.md`](docs/architecture/ROADMAP.md) | What is done, what is in progress, and in what order? |
| [`docs/architecture/DECISIONS.md`](docs/architecture/DECISIONS.md) | What changed since an earlier doc was written, and why — an append-only ADR log; newest wins on conflict. |

Read `MANIFESTO.md`, `BLUEPRINT.md`, and `STANDARDS.md` before non-trivial work — they are the
source of truth this file only points at. [`README.md`](README.md) is the practical entry point
for running and building the project.
