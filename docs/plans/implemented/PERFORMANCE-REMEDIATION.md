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

---

## 8. Verification against production, 2026-08-10 / 2026-08-11

Waves 0–3 measured on revision `00019-lk8` (§8.1–8.7); Wave 4 deployed and measured on
`00020-x8c` (§8.8).

Measured after Waves 0–3 shipped, against `https://zen-demo-server-tovqpjhspa-lm.a.run.app`
(the origin `gcloud run services describe` returns — **not** the hostname `services list` prints,
which is what the scheduler calls). Deployed commit `e774290`, confirmed by the running
revision's `ZEN_BUILD_ID`.

**§5's numbers are predictions and stay as written. This section records what was measured.**
The audit's numbers are dated observations of `00018-mn5` and remain true of it.

**§8.1–8.7 are a Waves 0–3 measurement against `00019`, taken while Wave 4 was still undeployed.**
They are left exactly as measured. **Wave 4 shipped the next day** — see §8.8, which closes F11.
Every boot figure in this section is a *boosted* boot either way; what changed is who owns the
setting.

**Production request budget: 8 allowed, 7 spent** — 5 against `00019` (§8.3) and 2 against `00020`
(§8.8). Everything else came from Cloud Logging, the
Cloud Monitoring v3 API and the Cloud Billing Catalog API, which cost nothing and wake no container.

### 8.1 The predictions, and what they measured

| Metric | Baseline `00018` | Predicted | **Measured `00019`** | |
|---|---|---|---|---|
| `started in`, median | 3.873 s | ~1.4 s | **1.084 s** (n=3; mean 1.229, range 1.017–1.587) | **hit, beat** |
| DB round trips at boot | 53 | ~11–12 | **not re-measured** — see 8.4 | — |
| Connections at boot | 4 | 1 | **not re-measured** — see 8.4 | — |
| `startup_latencies` mean | 4,514 ms | lower, by more than the app's share | **1,493 ms** (n=3) — −3,021 ms against an app share of −2,801 ms | **hit** |
| Flyway log lines | present | absent | **absent** — no `DbMigrate`/`DbValidate` in any `00019` boot | **hit** |
| `billable_instance_time` | 110–158 s/day | — | **2.93 s/instance** vs 5.74 (`00018`); ≈70 s/day projected | −47% |
| `memory/utilizations` p99 | — | expected to fall | **0.5994** vs `00018`'s concurrent 0.5573 | **miss — see 8.2** |
| Artifact Registry total | 906.058 MB | — | **915.567 MB** (+9.5 MB for a whole revision) | — |

`00018`'s own window (n=71 boots, 2026-08-08 → 2026-08-10) reads median **3.885 s**, mean 3.823 s,
range 3.310–4.194 s — which is where the audit's single 3.873 s tick sits, so the baseline holds.

**N is 3, not the 12 the brief asked for, and that is a limitation of the measurement, not a
finding.** `00019` was deployed at 18:27 UTC on the measurement day and boots once an hour; only
three had occurred by the close of the session. All three sit far below every one of `00018`'s 71
samples, so the direction is not in doubt, but the median is thin. Re-read the log after a full day
before quoting it as settled.

The spread is itself informative: the two **scheduler-tick** boots are 1.017 s and 1.084 s, within
67 ms of each other, while the 1.587 s outlier is the **first boot after the deploy**, when no image
layer was warm anywhere. Steady-state cold start is the tighter pair, not the mean.

### 8.2 The one miss: memory utilisation went up, not down

p99 memory rose from 0.5573 to 0.5997 of 256 MiB. **The prediction was wrong, not the change.**
Wave 2 pruned renderer variants and `.symbols` maps out of the *image*; those are files on disk that
no boot ever reads, so shrinking them was never going to move resident memory. Nothing in Waves 0–3
frees heap. At n=2, on a 256 MiB limit, this is noise around a flat line — but it is recorded as a
miss because the prediction was stated and did not hold.

Note also that the audit's baseline p99 of 0.73 does not reproduce: `00018` over the same recent
window reads 0.557. The two are different aggregation windows over the same revision; the
`00018`-vs-`00019` comparison above is the like-for-like one.

### 8.3 The frontend, on the wire

The two findings worth real money, verified on the deployed native image rather than a local
container. `HEAD` is useless against this server, so every check is a `GET`.

| # | Request | Result |
|---|---|---|
| 1 | `GET /main.dart.wasm` | **200, 909,639 wire bytes** (was 2,488,203 — **−63.4%**), `content-encoding: gzip`, `content-type: application/wasm` intact, `etag: "e774290"` |
| 2 | same, `If-None-Match: "e774290"`, same container | **304, 0 bytes** |
| 3 | same, **across a container replacement** | **304, 0 bytes** — where the audit measured 200 and 2,488,178 bytes |
| 4 | `GET /canvaskit/skwasm.wasm` | **200, 1,546,647 wire bytes** gzip; still shipped, so Wave 2 did not over-prune |
| 5 | `GET /` | **200, 768 wire bytes**, gzip, `text/html;charset=UTF-8` |

**F1 holds in production.** The audit predicted ≈910,000 bytes for `main.dart.wasm`; the wire
carried 909,639. Compression survived the native image and Google's frontend, and the
`application/wasm` content type was not damaged by adding it to `compress-media-types`.

**F2 is fixed, and the container replacement was proved from the logs, not assumed.** A 304 from the
same process would prove nothing — it is the easiest way to declare victory falsely here — so the
replacement was established before the request was spent:

```
19:00:05.697  started in 1.084s          <- the process that issued the ETag (requests 1, 2, 4, 5)
19:29:46.122  zen-demo-server stopped in 0.005s
20:00:04.157  Starting new instance. Reason: AUTOSCALING
20:00:05.669  started in 1.017s          <- a different process
20:02:15      request 3  ->  304, 0 bytes
```

The process holding the original response was dead for 32 minutes before the conditional request was
replayed. This is precisely the scenario the audit measured at 200 and 2,488,178 bytes.

**The `ETag` busts correctly across builds.** `ZEN_BUILD_ID` is set by `deploy:cloudrun` to the git
short SHA plus a dirty marker, so a new deploy always mints a new validator. It is a *commit*
identifier and not a content hash, which means redeploying the same clean commit reuses the ETag —
correct, because the same source produces the same bytes, but worth knowing if a build is ever
non-reproducible.

**`Last-Modified` is worse than the audit recorded, and it no longer matters.** The audit found it
to be container-start time. On `00019` it is *request* time: requests 1, 4 and 5 hit one container
(started 19:00:05) yet reported 19:13:11, 19:14:39 and 19:14:40. It is useless as a validator either
way; the `ETag` is now the one that works, which is exactly what Wave 1 was for.

### 8.4 What was not re-measured, and why

Boot **round-trip and connection counts were measured in the audit against local containers with
`log_connections=on`**, not against production, and there is no free way to read them off the
deployed service. They were not re-measured here. What was verified instead:

- The configuration that produces them is present in the deployed commit `e774290`:
  `quarkus.datasource.jdbc.min-size=1`, `%prod.quarkus.flyway.migrate-at-start=false`,
  `%prod.quarkus.flyway.validate-at-start=false`.
- No Flyway line appears in any `00019` boot, which is the direct observable for the 41 round trips
  and 2 connections Wave 3 removed.
- The production boot fell **2,549 ms** against a predicted 2,430 ms (2,100 from Wave 3, 330 from
  F5). The change applied; the estimate was, if anything, slightly conservative.

Anyone wanting the counts themselves should re-run the audit's local ablation, not spend a
production request on it.

### 8.5 Recomputed cost

Rates **re-read from the Cloud Billing Catalog API on 2026-08-10**, filtered to `europe-central2`.
**Every one of the eight is unchanged** from the audit's 2026-08-06 read.

| | Audit baseline | §5 predicted | **Measured 2026-08-10** |
|---|---|---|---|
| Cold start (`startup_latencies` mean) | 4.51 s | ~2.1 s | **1.49 s** — beat by ~0.6 s |
| First visit | 5.84 MiB | 2.39 MiB | **2.36–2.40 MiB** |
| Returning visit | 2.38 MiB | ~12 KB | **~12 KB** — mechanism proved, model unchanged |
| Bill today | $1.25/mo | ~$0.86/mo | **~$0.78/mo** |
| Bill at 2K MAU | $6.82/mo | ~$1.75/mo | **~$1.34/mo** |

**First visit was recomputed, not re-measured in a browser.** The audit established which 11 files a
browser fetches and that two of them are 99.1% of the bytes. Both were measured on the wire above
(909,639 + 1,546,647 = 2,456,286 B). The remaining nine totalled 56,791 B uncompressed in the audit
and were carried at that figure as an **upper bound**, giving 2,513,077 B = 2.396 MiB; at a
plausible 3:1 on the compressible ones the floor is 2.361 MiB. §5's 2.39 MiB sits inside the band.

**Returning visit** is the audit's own four-304 header model, unchanged. What is new is that the
304 now actually happens: the measured response header block is 727 bytes with a zero-byte body.

**Today's bill**, with measured usage:

| Line | Arithmetic | $/mo |
|---|---|---|
| Secret Manager, versions | **17 enabled − 6 free = 11** × $0.06 | **0.6600** |
| Cloud Run CPU | 70 s/day × 30.44 = 2,131 vCPU-s × $3.36e-5 | 0.0716 |
| Artifact Registry | 0.853 − 0.5 free = 0.353 GiB × $0.10 | 0.0353 |
| Secret Manager, ops | 2,419 billable × $3e-6 | 0.0073 |
| Cloud Run egress | ~0.016 GiB × $0.105 | 0.0017 |
| Cloud Run memory | 2,131 s × 0.25 GiB × $3.5e-6 | 0.0019 |
| Requests / Scheduler / Logging / Supabase | inside free tiers | 0.0000 |
| **Total** | | **$0.778** |

The 70 s/day is deliberately conservative: `00019`'s measured 2.93 s/instance includes the five
verification requests this session sent, which kept one container alive longer than a bare tick
would. The true steady-state figure is lower.

**At 2K MAU**, on the audit's visit model (2,000 first + 18,000 returning), egress lands at the
audit's 4.88 GiB = $0.512; secrets are now $0.66 rather than $1.02; compute falls with the shorter
cold start. Total **≈$1.34/mo**. It beats §5's $1.75 for one unglamorous reason: §5's 2K MAU row
still carried the secret line at 17 billable versions, and the operator task has since removed six.

**Read the units honestly, still.** Of the ~$0.48/month saved today, **$0.36 is the six destroyed
secret versions** — an operator action, not an engineering one. Wave 3 is worth ~$0.07/month here
and remains a latency change, exactly as §5 insisted.

### 8.6 The operator task (D2), done

Six secrets carried a superseded version 1. Every Cloud Run reference is `latest`, and `latest`
resolves to the highest enabled version, so version 2 was live in all six and version 1 was
destroyable by construction — verified per secret before each destroy, then verified after.

`APP_DB_PASSWORD`, `APP_DB_USERNAME`, `AUTH_REDIRECT_URI`, `CORS_ORIGINS`, `SITE_URL`,
`ZEN_JOBS_TRIGGER_TOKEN` — version 1 destroyed, one at a time. **Enabled versions 23 → 17.**
Irreversible, as D2 chose.

**The next hourly tick then succeeded, which is the check that matters** and cost no request budget:

```
20:00:04  Starting new instance
20:00:05  started in 1.017s
20:00:06  Removed 2 rate-limit counter row(s) whose window closed before 2026-08-08T20:00:06Z
20:00:06  Job tick ran 1 due job(s): 1 succeeded, 0 failed
```

That single line exercises all three of the risky secrets end to end: Cloud Scheduler authenticated
against `ZEN_JOBS_TRIGGER_TOKEN`, and the cleanup performed a real **write** against Postgres using
`APP_DB_USERNAME`/`APP_DB_PASSWORD`. A wrong version destroyed on any of the three would have shown
up here as a failed tick rather than a silent one.

### 8.7 F10 answered: a free Supabase project does pause

**Yes.** Supabase pauses a Free Plan project after roughly a week of insufficient database activity,
with a warning email about a week ahead; "a few user requests to the database each day over the
previous week" is enough to prevent it. Restoring is a one-click dashboard action available for up
to a year. This is now documentation, not model knowledge.

**The hourly tick is what keeps the database awake, and it does so with enormous margin.** The tick
runs `RateLimitCleanupJob`, which issues a Panache delete — a real database write, not just an HTTP
touch — 24 times a day against a threshold of "a few per day". Its frequency is therefore safe to
reduce a long way on the Supabase axis. Any such change must keep the job's *database* call, not
merely an endpoint hit: an endpoint that stops touching Postgres would let the project pause while
every check still looked green.

### 8.8 Wave 4 deployed and verified, 2026-08-11

Wave 4 shipped from **`main`** at `ffe8ca0` (the merge of PR #43, which carries `06fc93e` and this
verification), tagged and deployed as revision **`zen-demo-server-00020-x8c`**, 100% of traffic.
Two production requests, taking the session total to 7 of 8.

**The deploy behaved as Wave 3 and Wave 4 designed it to.**

- `build:web` **refused to run** on the first attempt, because the service URL resolved empty and it
  will not bake a wrong origin into the bundle. That is ADR-037's guard firing on a real deploy,
  and it failed *before* building rather than shipping a bundle that calls the wrong host.
- The **migration job ran before the service deployed** (`zen-demo-migrate-w4m6b`, succeeded), and
  the deploy read its exit code. Since ADR-038 this is the only thing that changes the schema.
- The summary printed `Startup CPU boost: true; execution environment: platform default (UNPINNED)`
  — the deploy now *states* the capacity it runs on.

**F11 is closed.** `startup-cpu-boost=true` is still the live value, but it is now set by
`deploy:cloudrun` from `SERVICE_CPU_BOOST` rather than by an out-of-band change no file described.
`execution-environment` remains absent, i.e. platform default, deliberately unpinned.
**F11a is not closed and was not touched**: the service-level `maxScale=20` above the template's `1`
is still set out of band, exactly as `06fc93e` recorded.

| Check | Result |
|---|---|
| Boot, first-after-deploy | **1.569 s** — matches `00019`'s equivalent 1.587 s |
| Flyway lines at boot | absent |
| `/main.dart.wasm` wire bytes | **909,639** — byte-identical to `00019` |
| `content-type` | `application/wasm` |
| ETag on `00020` | **`"ffe8ca0"`** ≠ `00019`'s `"e774290"` |
| Stale `If-None-Match: "e774290"` | **200 + 909,639 bytes** — correctly busted, not a stale 304 |
| Current `If-None-Match: "ffe8ca0"` | **304, 0 bytes** |

**This is the one Wave 1 property that a single revision could not prove.** §8.3 established that
the ETag *must* change per deploy because it is the commit SHA; here it was **observed** changing
across two live revisions, with a stale validator correctly refused and the current one honoured.
Had the ETag been build-stable, the stale request would have returned 304 and every client would
have kept superseded bytes forever — a worse defect than the one Wave 1 fixed.

**One cost this exposes, recorded and not fixed.** The two revisions serve a **byte-identical**
`main.dart.wasm` (only `Taskfile.yml` and documentation changed between them), yet the ETag changed,
so every returning visitor re-downloads 909,639 bytes after a deploy that altered nothing they run.
The validator is a *commit* identifier, not a content hash. That is the conservative direction — it
can never serve stale bytes — but it means deploy frequency, not bundle churn, drives returning-visit
egress. A content-addressed validator would eliminate it. Worth a decision only if deploys become
frequent enough for the egress to show; at today's rates it does not.
