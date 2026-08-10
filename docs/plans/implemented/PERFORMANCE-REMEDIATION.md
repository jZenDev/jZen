# Performance & cost remediation

A working document, not a source of truth. The architecture docs in
[`../../architecture/`](../../architecture/) remain authoritative, and ADRs win on conflict.

**Written:** 2026-08-08
**Evidence:** [`PERFORMANCE-AUDIT.md`](PERFORMANCE-AUDIT.md) — every number below comes from it. This
file states *what to change*; that one states *why, and how it was measured*. Do not restate its
findings here, and **do not re-derive its numbers** — re-measure only what a wave's verification asks
for.
**Produces:** code, configuration and operator changes, one ADR, and the documentation debt in §6.

**Read before starting:** `CLAUDE.md`; STANDARDS "Deployment model", "Database migrations",
"Failures surface; nothing is swallowed"; ADR-027, ADR-028, ADR-029, ADR-031, ADR-036, ADR-037.

---

## 1. What is already correct — do not touch

Verified during the audit and closed **with numbers**. Changing any of these makes the system worse
or is measurably pointless.

- **Anonymous requests cost zero database round trips**, including anonymous calls to authenticated
  paths. ADR-030's `SessionCookieAuthenticationMechanism` is what makes `proactive=true` free here.
- **JWKS is not fetched at boot.** Retrieval is lazy; boot is identical within 3 ms whether the
  endpoint is reachable or not. Do not "optimise" it.
- **The burst rate limiter is in memory and the durable tier is in Postgres** (ADR-029). The durable
  write on a *rejected* auth call is correct — it is what makes an attacker pay.
- **Artifact Registry accumulation is real and costs $0.034/month.** Do not build a pruning job.
- **Cloud Logging, Cloud Scheduler and Cloud Run request charges are all $0** and remain so at 2K MAU.
- **The native build's duplicated-plugin defect is gone** (303–350 s warm). Do not re-investigate.
- **The transport seam has no measurable CPU cost**; protobuf is 23–62% smaller than JSON. Do not
  change the default format on performance grounds.
- **`main.dart.js` stays.** ADR-016 keeps the dart2js fallback deliberately. It is 3.08 MiB of image
  and 0 ms of boot. **Excluded from F6's pruning — see §4.3.**

---

## 2. Decisions taken by the owner, 2026-08-08

These were open in the audit and are now settled. They are recorded here because a plan that carries
an unmade decision is not a plan.

| # | Decision | Consequence |
|---|---|---|
| D1 | **Supabase stays on the free plan** | Total hosting cost is GCP only. Confirmed 2026-08-06 |
| D2 | **Destroy the six superseded secret versions** — not disable | $0.36/month recovered, **irreversibly**. The previous values stop being available for a rollback |
| D3 | **Move migration to the deploy AND drop boot-time validation** | The full ~2,100 ms. **Invariant 6 is amended, not merely relocated** — see §4.4 and the ADR it requires |
| D4 | **The plan covers the priced trade-offs, not only the free wins** | Wave 3 exists |

**D3 was taken with the split measurement in hand**: relocating migration alone buys ~420 ms;
validation is the other ~1,680 ms and validation *is* the guarantee. The owner chose the full saving
knowing that. §4.4 proposes a deploy-time gate that recovers most of the protection at zero runtime
cost — that is a mitigation, not a reversal, and it does not require the decision to be revisited.

---

## 3. Ordering

| Wave | Contains | Touches an invariant? | Needs an ADR? | Can run unattended? |
|---|---|---|---|---|
| **0** | F1, F5 — configuration only | no | no | yes |
| **0-op** | D2 — destroy secret versions | no | no | **operator only, outside the repo** |
| **1** | F2, F4 — code, no new infrastructure | no | no | yes |
| **2** | F6 — build-time bundle pruning | no | no | yes |
| **3** | F7 — migration moves to the deploy | **yes, Invariant 6** | **yes** | **no** |
| **4** | F11 — the deploy sets the capacity it runs on | no | no (ADR-028 already covers it) | yes |

Waves 0–2 are independent of each other and of Wave 3. **Wave 3 is the only one that can break a
deploy**, so it ships alone, after the others are green. Wave 4 was added after the fact: F11 was
recorded in the audit and never assigned to a wave. It is `Taskfile.yml`-only and changes no
deployed behaviour.

F8 (ADR-031's privilege split adding a connection to every boot) **needs no work of its own**: Wave 3
removes Flyway from the boot path entirely, which removes both of its connections. That is the whole
of F8's cost, and it disappears as a side effect rather than by reversing a security decision.

---

## 4. The waves

### 4.1 Wave 0 — configuration only

**F1 — compress `application/wasm`, stop compressing `application/x-protobuf`.**

`application.properties:154` sets `quarkus.http.enable-compression=true` with no
`quarkus.http.compress-media-types`, so the default list applies: it includes `application/x-protobuf`
(inflating a 28-byte response to 55) and excludes `application/wasm` (2.4 MB, on every visitor's
critical path).

- Set `quarkus.http.compress-media-types` **explicitly**. It must include the text types the default
  already covers — establish that list from the running server rather than from documentation, or the
  change will silently *stop* compressing HTML and JS.
- Include `application/wasm`. Exclude `application/x-protobuf`.

**F5 — stop opening a second database connection eagerly at boot.**

`application.properties:40`: `quarkus.datasource.jdbc.min-size=2` → **`1`**. Locally this changes
nothing measurable; the connection count is the measurement, and a connection is ~332 ms in
production. Leave `max-size=10` alone.

**Verification for Wave 0** — all of it local, none of it against production:

```
# F1: the wasm is compressed, and the compressed set did not lose the text types
curl -s -o /dev/null -H 'Accept-Encoding: gzip' -w '%{size_download}\n' http://localhost:18080/main.dart.wasm   # ~910,000, not 2,488,178
curl -sD- -o /dev/null -H 'Accept-Encoding: gzip' http://localhost:18080/flutter_bootstrap.js | grep -i content-encoding   # still gzip
curl -sD- -o /dev/null -H 'Accept-Encoding: gzip' -H 'X-Zen-Transport: protobuf' http://localhost:18080/api/v1/health | grep -i content-encoding  # ABSENT
# F5: three connections at boot, not four
docker run ... -c log_connections=on ; docker logs <db> | grep -c 'connection authorized'
```

**Make F1 a gate, not a check.** Add the wasm-compression assertion to `verify:endpoints`, beside the
existing `application/wasm` content-type assertion (`Taskfile.yml`, the `test:native` smoke). A
property that can silently revert needs something that fails when it does — this is the same class of
defect as ADR-037's build define.

---

### 4.2 Wave 1 — code, no new infrastructure

**F2 — give static resources a build-stable validator.**

The defect: `Last-Modified` is the *container's start time*, not the build's, and no `ETag` is ever
sent. Under `--min-instances=0` the container is replaced ~24 times a day, so conditional requests can
never succeed and every returning visitor re-downloads `main.dart.wasm`. Measured: **44 fetches in
7 days = 93% of all bytes this service has ever sent.**

**`StaticCacheHeaders`'s own javadoc asserts the opposite** — *"The static handler already sends an
`ETag`, so revalidation is … answered with 304"*. That sentence is false in the deployed shape and is
the reason nobody noticed. **Correcting it is part of this task, not a follow-up.**

Design, and the parts that must be settled during implementation rather than assumed:

1. **Introduce a build-stamped value.** Nothing in the repository carries one today: the app version
   is `0.1.0-SNAPSHOT` (lockstep, ADR-012) and `version.json` says `0.1.0` — neither changes per
   build. Use `${maven.build.timestamp}` as the default so every build differs, overridable by the
   `GIT_SHA` `deploy:cloudrun` already computes (`Taskfile.yml:1422`). Expose it as a config property.
2. **Emit it as a strong `ETag` on static responses**, in `StaticCacheHeaders` — that class already
   owns this concern and already installs an early Vert.x route at `Integer.MIN_VALUE`.
3. **Answer `If-None-Match` with 304** before the static handler reads the resource.
4. **Mind the precedence rule.** RFC 9110: when `If-None-Match` is present the server must ignore
   `If-Modified-Since`. Since the static handler will still stamp a process-start `Last-Modified`, the
   `ETag` path has to win, or browsers sending both will still get 200s. **Verify this rather than
   assume it** — it is the single most likely way this fix passes review and does not work.
5. The same value should serve the `immutable, max-age=86400` resources too, so that when their day
   expires they revalidate successfully instead of re-downloading `canvaskit/`.

**F4 — read the `users` row once per authenticated request, not twice.**

`RoleAugmentor.java:60` → `UserRoleLoader.java:51-59` loads the full `User` entity in its own
`@Transactional` unit; the resource then loads the identical row in a second transaction. Two
persistence contexts, so Hibernate's first-level cache cannot help. **~135 ms per authenticated
request** in production.

- Make the resource use the entity the augmentor already loaded, or run both in one transaction.
- **This is not a cache and must not become one.** The role is still read from the database on every
  request; ADR-017's revocation guarantee is untouched. Any implementation that survives across
  requests is wrong.
- Secondary, optional: `loadUser` returns only `(exists, role, analyticsConsent)` but gets there via a
  full-entity `findById` of 17 columns. Narrowing the query is worth little over a link where latency
  dominates payload — do it only if it falls out of the change.

**Verification for Wave 1:**

```
# F2: revalidation survives a container replacement — the whole point
etag=$(curl -sI http://localhost:18080/main.dart.wasm | awk 'BEGIN{IGNORECASE=1}/^etag:/{sub(/^[^:]*: */,"");print}' | tr -d '\r')
docker restart <app>
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' -H "If-None-Match: $etag" http://localhost:18080/main.dart.wasm   # 304 0
# and a REBUILD must bust it
# F4: one users select per authenticated request
docker logs <db> | grep -c 'from users u1_0 where u1_0.id'
```

**Both need a regression test.** F2's belongs beside `StaticCacheHeaders`' existing coverage and must
assert the 304 **across a restart**, which is the property that failed. F4's asserts the query count,
not the absence of an exception — the same reasoning ADR-031 gives for asserting row counts.

---

### 4.3 Wave 2 — stop shipping what no browser fetches

**F6 — prune the unused renderer variants and debug symbol maps.**

Measured: a browser fetches **11 files**; the renderer selected is **skwasm**. Never requested:
five renderer variants (25.8 MB), six `.symbols` maps (8.6 MB), `assets/NOTICES` (1.4 MB) —
**37.13 MiB, 83.5% of the bundle.** Ablation B4: removing the bundle costs **0 ms of boot** and 30%
of the binary, so this is a size fix only.

- Prune in `build:web` (`Taskfile.yml:554`), **after** `flutter build web --wasm` and **before** the
  `rsync` that stages into `META-INF/resources`.
- **Derive the keep-set from the build, never hand-maintain it.** A hardcoded list of renderer
  filenames is a trap: a Flutter SDK upgrade changes which variant the loader selects, and the failure
  is a blank page in a browser, invisible to every suite. If the keep-set cannot be derived reliably,
  **prune only the `.symbols` files** (8.24 MiB, unambiguously debug artefacts) and record why the
  rest was left.
- **`main.dart.js` is out of scope** — ADR-016 keeps the dart2js fallback deliberately (§1).
- `assets/NOTICES` is a licence file. Do not delete it without checking the obligation; it is not on
  the load path anyway.

**Verification:** `task test:native` stays green — 9 of its 136 tests fail if the bundle goes missing,
so they are a real guard — and a real browser still renders the app. `verify:endpoints`' web-shell
assertion keys on `flutter_bootstrap.js`, which both compilations emit.

---

### 4.4 Wave 3 — migration moves to the deploy (D3)

**This wave amends an invariant and ships alone.**

Today `quarkus.flyway.migrate-at-start=true` (`application.properties:71`) both migrates and validates
on every cold start: **41 of the boot's 53 round trips and 2 of its 4 connections, ~2,100 ms**. D3
takes the full saving, which means validation goes too.

**What is given up, stated plainly:** the guarantee that a running binary and its schema agree. Today
an image whose migration set is behind the database refuses to boot (`FlywayValidateException`, the
mechanism ADR-031 hit by accident). After this wave it boots and serves.

**What replaces it — and this is required, not optional.** The guarantee moves to the deploy:

1. **A migrate-only mode on the same image.** A bean that, when `zen.migrate-only=true`, runs Flyway
   and exits. **The same binary, the same Flyway, the same migrations** — so "Flyway is the single
   migration authority" is preserved exactly. A Flyway CLI container is **rejected**: it is a second
   runner and a version-drift risk against that rule.
   - It must exit **non-zero on failure**, or `deploy:cloudrun` will deploy over a failed migration.
   - Layering: the app assembles it, but Flyway ownership sits with `zen-identity` (it owns the schema
     baseline). Settle where the bean lives before writing it; do not scatter it.
2. **A Cloud Run Job** running that image with the DDL credentials from Secret Manager. None exists
   today — it is new, and belongs in `deploy:cloudrun`'s ONE-TIME SETUP. Prefer it over a local
   `docker run`, which would need the production database password on the deploying machine.
3. **Deploy ordering, which is the part that will bite.** Build → push → **run the migration job with
   the new image** → only then `gcloud run deploy`. Migration must not run against the old revision's
   image, and the service must not go live before the schema is ready.
4. **A deploy-time schema gate replacing the boot-time one.** Before deploying, compare the image's
   migration set against `flyway_schema_history` and **refuse a deploy whose migrations are behind the
   database**. This is what keeps D3 from being a pure loss: the rollback case that boot validation
   used to catch is caught by the deploy instead. A rollback that genuinely must proceed overrides
   explicitly, the way `ALLOW_DIRTY=1` already does.
5. `%prod.quarkus.flyway.migrate-at-start=false` and `validate-at-start=false`. **`%dev` and `%test`
   keep migrate-at-start=true** — Dev Services provisions a throwaway database per run, and
   `task test:e2e` depends on migration happening at boot. Changing them would break the suites for no
   gain.

**Consequences to carry:**

- `UserRoleLoader`'s javadoc reasons about "before Flyway has created the table (e.g. very early
  boot)". That reasoning changes when Flyway no longer runs at boot; its `hasUsersTable()` latch
  becomes the only thing standing between a mis-ordered deploy and a confusing failure.
- A deploy now has two failure points instead of one, and the second is a Cloud Run Job whose failure
  must not be swallowed (STANDARDS "Failures surface").

**The ADR this wave requires** — write it with the `add-adr` skill, after the wave is verified, never
before:

> Migration runs at deploy, not at boot; the binary-and-schema agreement check moves from process
> start to the deploy gate.
> **Supersedes:** STANDARDS "Deployment model" and "Database migrations" in respect of *when* Flyway
> runs. **Refines:** ADR-031 (whose separate Flyway connection leaves the boot path entirely as a
> result), ADR-008 (the version-band reasoning is unaffected).
> It must state the measurement (41 round trips, 2 connections, ~2,100 ms), what is given up, and what
> the deploy gate now guarantees instead.

**Verification for Wave 3:**

```
# migration no longer runs at boot
docker logs <app> | grep -E 'DbMigrate|DbValidate'          # nothing
docker logs <db>  | grep -c 'connection authorized'          # 2, was 4
# the deploy gate actually refuses
#   point it at a database ahead of the image's migrations -> the deploy must FAIL, loudly
# the release gate still passes end to end
task test:native && task test          # test:e2e included; %dev/%test still migrate at boot
```

---

### 4.5 Wave 4 — the deploy sets the capacity it runs on (F11)

`Taskfile.yml` only: two flags, two vars, and the summary that documents them. **It changes no
deployed behaviour** — it stops the deployed behaviour depending on settings made outside the repo.

- `SERVICE_CPU_BOOST` (default `true`) → `--cpu-boost` / `--no-cpu-boost`. Boost was already on in
  production, set out of band; the deploy never passed the flag, so the first deploy that recreated
  the service would have dropped it silently. Every cold-start number in the audit and in ADR-027
  is therefore *already* a boosted boot.
- `SERVICE_EXECUTION_ENVIRONMENT` (default **empty**) → `--execution-environment=gen1|gen2`, or no
  flag at all. **Left unpinned deliberately.** This closes Q2 as *unanswerable from the control
  plane*: `gcloud run revisions describe`, the Cloud Run v2 API and the Console's revision detail
  all report the request, not the resolution (the Console prints the literal word "Default"). A pin
  is not inert — the wrong one migrates production to a different runtime, with different
  cold-start and syscall behaviour, on the next deploy.

Each var maps to one complete flag or fails the deploy; neither can render a bare flag or a dangling
backslash. No ADR: ADR-028 already rules that capacity knobs are the application's `vars` and that
the framework must document what each invalidates. This applies that decision to two knobs it had
not yet reached.

**Verification for Wave 4** (this wave cannot be verified by deploying, and must not be):

```
task deploy:cloudrun --summary                              # says eight knobs, documents both
grep -n 'cpu-boost\|execution-environment' Taskfile.yml     # was 0 before this wave
gcloud run deploy --help | grep -E 'cpu-boost|execution-environment'
task deploy:cloudrun --dry                                  # render, both default and overridden
task test
```

---

### 4.6 Wave 0-op — operator work, outside the repository (D2)

Six secret versions are superseded and unreferenced (`deploy:cloudrun` pins `:latest`). **D2 destroys
them, which is irreversible.**

Affected: `APP_DB_PASSWORD`, `APP_DB_USERNAME`, `AUTH_REDIRECT_URI`, `CORS_ORIGINS`, `SITE_URL`,
`ZEN_JOBS_TRIGGER_TOKEN` — each has 2 enabled versions; destroy the **older** of each.

```
# list first, and read what you are about to destroy
gcloud secrets versions list <SECRET> --project=jzen-prod --filter='state=ENABLED'
gcloud secrets versions destroy <VERSION> --secret=<SECRET> --project=jzen-prod
```

**Do this one secret at a time, confirming the surviving version is the one in use.** Destroying the
wrong version of `APP_DB_PASSWORD` or `ZEN_JOBS_TRIGGER_TOKEN` breaks the deployed service, and there
is no undo. Verify after: the enabled-version count falls from **23 to 17**, and the service still
answers — the next scheduler tick is a free check that costs no request budget.

---

## 5. What this is worth when it is done

From the audit's cost model — rates read from the Cloud Billing Catalog API, usage measured.

| | Today | At 2K MAU |
|---|---|---|
| **Before** | **$1.25/mo** | **$6.82/mo** |
| After Waves 0–2 | ~$0.86/mo | **~$1.75/mo** |
| Cold start | 4.51 s | **~2.1 s** after Wave 3 (plus ~330 ms from F5) |
| First visit | 5.84 MiB | **2.39 MiB** |
| Returning visit | 2.38 MiB | **~12 KB** |
| Authenticated request | — | **~135 ms faster** |

**Read the units honestly.** Waves 0–2 are worth ~$5/month at 2K MAU and essentially nothing today.
**Wave 3 is worth ~$0.05/month at any load** — it is a latency change, and the case for it is the
2.1 seconds a visitor waits, not the bill. A report of this work that presents Wave 3 as a saving is
misrepresenting it.

---

## 6. Documentation debt this plan creates

Each item is part of the wave that causes it, not a follow-up.

| Document | Change | Caused by |
|---|---|---|
| `StaticCacheHeaders` javadoc | **Delete the false claim** that the static handler already sends an `ETag`, and say what actually happens | F2 |
| `application.properties:71-83` | Flyway comments describe boot-time migration; rewrite for the new topology | Wave 3 |
| `UserRoleLoader` javadoc | Its "before Flyway has created the table" reasoning changes | Wave 3 |
| STANDARDS "Database migrations" | Gains the rule that migration runs at deploy and what the deploy gate guarantees | Wave 3 |
| STANDARDS "Deployment model" | The boot decomposition it quotes (ADR-027's 3.0 s) is superseded by the audit's measurements | Waves 0–3 |
| `deploy:cloudrun` summary | The Cloud Run Job, the new ordering, and the schema gate | Wave 3 |
| `DECISIONS.md` | One new ADR (§4.4). **Never edit an accepted entry** | Wave 3 |
| `deploy:cloudrun` summary | CAPACITY grows from six knobs to eight; each new one states what it invalidates, per ADR-028 | Wave 4 |
| ADR-031 | Untouched — it is accepted and sealed. Its unpriced boot cost is recorded in the audit and in the new ADR | — |

---

## 7. Rules for whoever executes this

- **Never `git commit` or `git push` without explicit approval.** Project working agreement.
- **Never run `task deploy:cloudrun` or `task destroy:cloudrun`.** Deploy is a manual human act;
  `destroy` deletes the GCP *and* Supabase projects.
- **Do not generate load against production**, and do not "verify" a wave by hitting the live service.
  Every verification above is local by construction.
- **Nothing swallows a failure.** The migration job's exit code and the deploy gate are the two places
  this plan could introduce one.
- **A tracked generated file is never hand-edited**; run `task sync:contracts` and let it fail.
- **`task test` is 122 s and `task test:native` is 5–6 minutes.** Run the first constantly and the
  second before declaring a wave done — it is the only thing that exercises the artefact production
  runs.
- **Write the ADR after the wave is verified, never before.** An ADR records a decision that was
  taken and proved, not one that is intended.
