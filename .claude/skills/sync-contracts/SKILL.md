---
name: sync-contracts
description: The jZen contract-first loop. Use whenever you change a proto model, a REST resource's shape, or need to regenerate/commit generated Java DTOs, Dart messages, or admin TypeScript, or when `task sync:contracts` fails with a drift error.
---

# Syncing jZen contracts

`.proto` under `proto/zen/v1/` is canonical for **models**; SmallRye-annotated Quarkus resources
are canonical for the **REST surface** (paths/verbs/status). Everything else is **derived and
committed** — Java DTOs (`zen-proto`), Dart messages (`client/zen_transport/lib/src/generated/`),
`openapi.json`, and admin TS (`schema.generated.ts`). **Never hand-edit a generated file.** Fix the
source and regenerate.

## The loop

1. Edit the source: a `proto/zen/v1/*.proto` file (models) and/or a resource's annotations (paths).
2. Regenerate everything: `task generate:proto generate:api`.
   - `generate:proto` → Java DTOs (`./mvnw -pl zen-proto generate-sources`) + Dart messages
     (needs `protoc` + `protoc-gen-dart`; run `task doctor` if missing).
   - `generate:api` → builds the reference backend to emit `openapi.json`, then runs
     `openapi-typescript` for the admin panel.
3. Verify + commit: `task sync:contracts` runs both generators then `sync:verify`, which fails if
   any `*.pb.dart`, `*.pbjson.dart`, `*.pbenum.dart`, `*.generated.ts`, or `proto/**` file differs
   from what's committed. Commit the regenerated output (with approval — see CLAUDE.md).

## When `task sync:contracts` fails

The error `Contracts are OUT OF SYNC` means either a generated file was hand-edited, or a `.proto`
changed without regenerating. **Fix by running `task generate:proto generate:api` and committing the
result — never by editing generated output.** This gate is meant to be wired into CI as a required
check.

## Adding proto3 canonical JSON note

Generated JSON is proto3 canonical JSON (lowerCamelCase field names) from `JsonFormat`. That's the
same shape Dart's `protoc_plugin` and `openapi-typescript` emit, so all three languages agree. When
hand-authoring OpenAPI component schemas (see the `add-endpoint` skill / TA-1), match those camelCase
names.
