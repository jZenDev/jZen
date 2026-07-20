# jZen Manifesto

jZen is DartZen re-engineered. It keeps DartZen's architectural DNA — its Flutter
packages, its transport seam, its example applications — and transplants a new backend
runtime harvested from BugEater (`../BugEater/bugeater-quarkus`): Quarkus, PostgreSQL,
and Supabase in place of the Shelf-and-Firestore server that DartZen shipped with.

jZen is a **framework**: `server/` and `client/` are reusable Java and Dart libraries, and
applications — the `zen_demo` reference app today, real products like `workspaces` next — are
built on them under `apps/<app>/{<app>_client, <app>_server}`. The reference app proves the
framework composes end to end.

This document states what jZen believes. The concrete structure is in
[`BLUEPRINT.md`](./BLUEPRINT.md); the order of work is in [`ROADMAP.md`](./ROADMAP.md);
the rules that keep it honest are in [`STANDARDS.md`](./STANDARDS.md); decisions that change
earlier docs, with justification, are logged in [`DECISIONS.md`](./DECISIONS.md).

> **Provenance, and its expiry.** While the migration is in progress these docs cite
> DartZen and BugEater source files as evidence for each decision — that is deliberate
> (STANDARDS: "cite the source"). jZen is nonetheless a **standalone product**, not a fork
> of either. The final roadmap step strips every DartZen/BugEater reference and rewrites
> these documents to stand on their own; from that point jZen has only its own philosophy,
> its own history, and its own name.

## Inherited from Zen Architecture

DartZen's `docs/zen_architecture.md` is carried forward, with two principles unchanged:

- **Product-first, not architecture-first.** Packages are product capabilities, not
  layers. DartZen already lives this — `dartzen_identity`, `dartzen_payments`,
  `dartzen_transport` are capabilities, and `dartzen_core` depends on nothing but
  `meta` (`../DartZen/packages/dartzen_core/pubspec.yaml`). jZen preserves that graph.
- **Real dependencies are first-class.** DartZen refused to hide Firestore or GCP. jZen
  keeps the stance and only swaps the dependency: PostgreSQL, Supabase Auth, and
  Cloud Run are treated as real, named, non-abstracted infrastructure — not smuggled
  behind a portability layer that no second implementation will ever justify.

## Revised for jZen

Two of DartZen's original principles are **deliberately changed**. Naming the change is
the point — a silent reversal would be exactly the kind of hidden decision the
philosophy warns against.

### "Zero magic" is narrowed to "no *custom* magic"

DartZen's principle #2 rejected all code generation: "No code generation that obscures
logic." That was affordable because DartZen has literally none — no `build_runner`, no
`freezed`, no `*.g.dart` anywhere in the repo, and ~20 hand-written `toMap`/`fromMap`
pairs (e.g. `../DartZen/packages/dartzen_transport/lib/src/zen_request.dart:26`).

jZen is contract-first across three languages. Hand-syncing Java DTOs, Dart messages,
and TypeScript types by hand is not "zero magic" — it is manual magic that drifts
silently, which is worse. So jZen adopts **industry-standard, inspectable generators
only**:

- Java: **protoc**, **MapStruct**, **Hibernate Panache**
- Dart: **Freezed**, **json_serializable**, **protoc_plugin**
- TypeScript: **openapi-typescript**, **react-admin**

The line is bright: no custom DSLs, no bespoke frameworks, no generator whose output a
developer cannot read. Every generated file is committed and diffable, and
`task sync:contracts` fails the build if any of it drifts. Generation that you can read
and that a gate keeps honest is not magic — it is the opposite.

### The single source of truth is the contract, not the code

DartZen has no cross-language contract; its Dart is the only truth. jZen serves Flutter,
a React admin panel, and native apps from one backend, so the **contract is canonical**:

```
proto/zen/v1/*.proto   ── canonical models ──▶ Java DTOs, Dart messages, OpenAPI schemas
Quarkus resources + SmallRye ── canonical REST surface ──▶ openapi.json ──▶ TS types
```

Proto owns model shape; OpenAPI owns the REST surface (paths, verbs, status codes) that
proto cannot express. Neither is hand-edited downstream. See
[`BLUEPRINT.md`](./BLUEPRINT.md) for the full lineage and the one unproven link in it
(TA-1).

## The dual-mode transport is non-negotiable

DartZen ships a real dual-transport mechanism: one header selecting JSON or a binary
codec (`../DartZen/packages/dartzen_transport/lib/src/zen_transport_header.dart:4`).
jZen preserves the seam and its negotiation logic, with two changes: the binary codec
becomes Protobuf (DartZen's was hand-written MessagePack), and the header is renamed
`X-DZ-Transport` → `X-Zen-Transport`, because "DZ" stood for DartZen. Web and admin
clients get JSON/REST; native apps get Protobuf binary over the same endpoints. One
negotiation point, chosen by one header. The developer defines a domain model and nothing
else; the framework picks the wire format.

## What jZen explicitly discards

- **Firebase / Firestore.** DartZen's `dartzen_firestore` (a hand-rolled REST client,
  not a Firebase SDK) and `dartzen_server` (which has zero production consumers) are
  deleted, not ported.
- **BugEater's business domain.** Courses, gamification, quizzes, lessons, practice
  challenges — none of it is imported. BugEater is an architectural donor only.
- **Server-rendered HTML.** BugEater's 136 Qute `*PageResource` classes are dropped in
  favor of a unified REST API. Qute survives solely as a mail-templating engine.
- **The legacy Flutter admin.** `dartzen_ui_admin` is replaced by a clean `react-admin`
  panel in `admin/`.
