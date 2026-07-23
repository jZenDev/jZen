# jZen Manifesto

jZen is a **framework** for building full-stack products: `server/` and `client/` are reusable
Java and Dart libraries, and applications — the `zen_demo` reference app today, real products
next — are built on them under `apps/<app>/{<app>_client, <app>_server, <app>_admin}`. The
reference app proves the framework composes end to end.

The stack is Quarkus, PostgreSQL, and Supabase on the server; Flutter on the client;
react-admin for administration; and one contract, declared in protobuf, binding all three.

This document states what jZen believes. The concrete structure is in
[`BLUEPRINT.md`](./BLUEPRINT.md); the order of work is in [`ROADMAP.md`](./ROADMAP.md);
the rules that keep it honest are in [`STANDARDS.md`](./STANDARDS.md); decisions that change
earlier docs, with justification, are logged in [`DECISIONS.md`](./DECISIONS.md).

## Product-first, not architecture-first

Packages are product capabilities, not layers. `zen_identity`, `zen_transport`, `zen_jobs` are
things the product *does*; there is no `zen_services` or `zen_repositories`, because those are
things a diagram does. The test of a package is whether you can name what a user gets from it.

`zen_core` depends on nothing but `meta` on the Dart side and nothing framework-shaped on the
Java side, and that isolation is defended rather than tolerated: it is what lets every other
module use the result types without inheriting a framework.

## Real dependencies are first-class

PostgreSQL, Supabase Auth, and Cloud Run are treated as real, named, non-abstracted
infrastructure. They are not smuggled behind a portability layer that no second implementation
will ever justify. A `Storage` interface with one implementation is not an abstraction, it is a
passthrough with a plausible name — and it costs a reader one extra indirection every time they
follow the code, forever, in exchange for a flexibility nobody has asked for.

The corollary is a real obligation: when a dependency is named, its constraints are the
product's constraints, and they belong in [`STANDARDS.md`](./STANDARDS.md) where they can be
enforced, not hidden behind a wrapper where they will surface as a bug.

## No *custom* magic

Code generation is not the enemy; **unreadable** code generation is. jZen is contract-first
across three languages, and hand-syncing Java DTOs, Dart messages, and TypeScript types is not
"zero magic" — it is manual magic that drifts silently, which is worse.

So jZen adopts **industry-standard, inspectable generators only**:

- Java: **protoc**, **MapStruct**, **Hibernate Panache**
- Dart: **Freezed**, **json_serializable**, **protoc_plugin**, **flutter gen-l10n**
- TypeScript: **openapi-typescript**, **react-admin**

The line is bright: no custom DSLs, no bespoke frameworks, no generator whose output a
developer cannot read. Every generated file is readable and reproducible, the ones that cross a
toolchain boundary are committed and diffable (STANDARDS "Code generation"), and
`task sync:contracts` fails the build if any of it drifts. Generation that you can read and
that a gate keeps honest is not magic — it is the opposite.

## The single source of truth is the contract, not the code

jZen serves Flutter, a React admin panel, and native apps from one backend, so the **contract
is canonical**:

```
proto/zen/v1/*.proto   ── canonical models ──▶ Java DTOs, Dart messages, OpenAPI schemas
Quarkus resources + SmallRye ── canonical REST surface ──▶ openapi.json ──▶ TS types
```

Proto owns model shape; OpenAPI owns the REST surface (paths, verbs, status codes) that proto
cannot express. Neither is hand-edited downstream, and a gate rather than a convention is what
enforces it. See [`BLUEPRINT.md`](./BLUEPRINT.md) for the full lineage.

## The dual-mode transport is non-negotiable

A developer defines a domain model and nothing else; the framework negotiates the wire format.
One header, `X-Zen-Transport`, selects canonical proto3 JSON or Protobuf binary over the same
typed endpoints: web and admin clients get JSON, native apps get binary, and neither the
resource nor the caller contains a branch about it. One negotiation point, chosen by one
header.

This is the mechanism the rest of the architecture is arranged around, which is why it is the
one thing here stated as an absolute.

## Boundaries — what jZen is not

Settled choices, not open questions. Each names a road jZen does not take, and why the one it
does take is sufficient. Reopening any of them takes a decision that supersedes this line.

- **Not a Firebase/Firestore stack.** The database is PostgreSQL and authentication is
  Supabase's — both named, first-class dependencies rather than abstractions. A document store
  would mean a second data model that no product here has asked for.
- **Not server-rendered.** jZen serves a REST API and clients render. Qute is present for one
  job only: templating mail.
- **Not a Flutter admin panel.** Administration is a `react-admin` stack — a reusable framework
  scaffold (`@jzen/admin-core` in `admin/`) that each app assembles into its own panel under
  `apps/<app>/<app>_admin` (ADR-005). One toolkit for the product surface, another for the back
  office, each chosen for its audience.
- **Not runtime-configured on the client.** Compile-time selectors are what let the toolchain
  tree-shake per platform; runtime config would defeat that (STANDARDS "Client config is
  compile-time"). This is the one client/server asymmetry the architecture mandates on purpose.
