# The architectural performance & hosting-cost audit

A working document, not a source of truth. The architecture docs in
[`../architecture/`](../architecture/) remain authoritative, and ADRs win on conflict. **No decision
is taken here** — an audit accepts nothing on its own. If the owner takes one, it is recorded with
the `add-adr` skill.

**Audited:** 2026-08-06 / 2026-08-07
**Scope, in:** the deployed shape of `zen-demo-server` in `jzen-prod` — cold-start composition, the
five request paths, the delivered web bundle, and every bill line the project generates.
**Scope, out:** security (a separate audit ran; `implemented/SECURITY-REMEDIATION.md`), code style,
and throughput under load that does not exist.

## Method

| | |
|---|---|
| **Host** | arm64 (Apple silicon), Docker Desktop 29.6.2. **Every local container ran `linux/amd64` emulated**, so local CPU-bound work is inflated and local I/O is not. Local numbers appear here only as **counts and deltas**, never as absolutes. |
| **Production requests spent** | **5**, budgeted at 6. Ledger in §7.1. All against the configured origin `zen-demo-server-tovqpjhspa-lm.a.run.app`, re-resolved from `gcloud run services describe` at measurement time, revision `zen-demo-server-00018-mn5`. |
| **`task verify:deploy`** | **Skipped, deliberately.** It costs ~32 requests including a `POST /api/v1/auth/restore-password` that writes `zen_rate_limit_counters`. It is a deployment-health gate, not a performance instrument, and nothing here depends on it. |
| **Where the numbers came from** | **Recorded logs** (2,962 Cloud Logging entries over 7 days, 173 cold starts, 648 request-log entries) and the **Cloud Monitoring v3 REST API** for everything about production. **The Cloud Billing Catalog API** for every rate. **Local containers** for round-trip counts, ablations, and the bundle. |
| **Labels used throughout** | *measured* = produced by a command here. *inferred-from-measurement* = arithmetic over measured inputs, shown inline. *unverified* = stated as open. |
| **Toolchain** | `task doctor` green. One trap: the first `doctor` of a session can report a false `DRIFT flutter` with an empty observed version — `flutter --version` does not put the version on line 1 after a cold tool cache (`Taskfile.yml:172`). |

**A measurement trap that would corrupt any repeat of this work.** `docker images`,
`docker image inspect --format '{{.Size}}'`, `docker history` and `docker save | wc -c` all report
this project's image as **64 MB**, with the runner `COPY` layer as **0 B** — for a binary of
**156 MiB**. It is a buildx manifest list for a foreign platform; the local daemon accounts what it
materialised, not what the image contains. Use `docker create` + `docker cp` + `stat`.

**A second one, which cost four of the five production requests.** `HEAD` against Quarkus's static
handler returns `content-type: text/html` and **no** `content-encoding` for every path — including
`main.dart.wasm`, which `GET` correctly serves as `application/wasm`. Any compression or
content-type conclusion drawn from a `HEAD` against this service is wrong.

---

## 1. Summary — ranked

Ranking rule, as applied: **(cost or latency removed) ÷ (invariant risk incurred)**.

| # | Finding | Unit today | Unit at 2K MAU |
|---|---|---|---|
| **F1** | `application/wasm` ships uncompressed; `application/x-protobuf` is compressed and *inflated* | 3.45 MiB / first visit | **$3.48/mo** |
| **F2** | `Last-Modified` is container-start time and no `ETag` is sent, so revalidation can never survive a container replacement | 2.37 MiB / returning visit — **93% of all egress today** | **$1.60/mo** |
| **F3** | Six superseded secret versions are billed | **$0.36/mo — 29% of the entire bill** | $0.36/mo |
| **F4** | The `users` row is read **twice** per authenticated request, in two transactions | **~135 ms / authenticated request** | same |
| **F5** | `jdbc.min-size=2` opens two cross-region connections during boot | **~330 ms of cold start** | same |
| **F6** | 37.13 MiB of the shipped bundle is never fetched by any browser | 15.6 MiB / image pull; $0.025/mo | same |
| **F7** | Flyway runs on every cold start to conclude there is nothing to do | **~2,100 ms of cold start**; $0.05/mo | same |
| **F8** | ADR-031's privilege split adds a cross-region connection to every boot, unpriced | ~660 ms of cold start | same |

**The one-sentence result:** the service costs **about a dollar a month**, the largest line is
**Secret Manager version storage**, and at 2K MAU **egress becomes 82% of the bill** — where two
changes touching no invariant remove three quarters of it. Every latency finding here is worth **less
than a nickel a month**, and is reported as latency for that reason.

---

## 2. The cost model

Every rate **read from the Cloud Billing Catalog API on 2026-08-06**, filtered to `europe-central2`.
No rate here is recalled.

| Bill line | SKU (verbatim) | Rate | Free tier in catalog |
|---|---|---|---|
| Cloud Run CPU | `Services CPU Tier 2 (Request-based billing)` | $3.36×10⁻⁵ / vCPU-s | no |
| Cloud Run memory | `Services Memory Tier 2 (Request-based billing)` | $3.5×10⁻⁶ / GiB-s | no |
| Cloud Run requests | `Requests` | $4×10⁻⁷ | **$0 to 2,000,000/mo** |
| Cloud Run egress | `Cloud Run Network Internet Data Transfer Out Europe to Europe` | **$0.105 / GiB** | no |
| Artifact Registry | `Artifact Registry Storage` | $0.10 / GiB-mo | **$0 to 0.5 GiB** |
| Secret Manager storage | `Secret version replica storage` | $0.06 / version-mo | **$0 to 6** |
| Secret Manager access | `Secret access operations` | $3×10⁻⁶ | **$0 to 10,000** |
| Cloud Logging | `Log Storage cost` | $0.50 / GiB | **$0 to 50 GiB** |

Cloud Run's *compute* free tier is **not published in the catalog**. Compute figures below are
therefore **gross**, with the free-tier reading given separately and labelled model knowledge.

### Today

| Line | Arithmetic | $/mo |
|---|---|---|
| Secret Manager, versions | 23 enabled − 6 free = 17 × $0.06 | **1.0200** |
| Cloud Run CPU | 129 s/day × 30.44 = 3,927 vCPU-s × $3.36e-5 | 0.1319 |
| Cloud Run egress | 0.475 GiB × $0.105 | 0.0499 |
| Artifact Registry | 0.844 − 0.5 free = 0.344 GiB × $0.10 | 0.0344 |
| Secret Manager, ops | 12,419 − 10,000 free = 2,419 × $3e-6 | 0.0073 |
| Cloud Run memory | 3,927 s × 0.25 GiB × $3.5e-6 | 0.0034 |
| Requests / Scheduler / Logging | all inside free tiers | 0.0000 |
| **Supabase** | **free plan** (owner, 2026-08-06) | 0.0000 |
| **Total** | | **$1.25** *(→ $1.11 with the compute free tier)* |

### At 2K MAU

**The visit model, stated before the arithmetic**, because the whole number turns on it:
`implemented/SECURITY-REMEDIATION.md:138` sizes the durable limiter at ~20K auth events/month at 2K
MAU. Reused as **20,000 visits/month = 2,000 first + 18,000 returning**, ~12 origin requests each
(measured: 11 static + 1 API).

| | Egress | **Total $/mo** |
|---|---|---|
| As built | 53.24 GiB | **$6.82** |
| + F1 (compress wasm) | 20.14 GiB | $3.34 |
| + F1 and F2 | **4.88 GiB** | **$1.75** |

Compute barely moves: 240,000 requests × 7 ms warm + 24 cold starts/day × 4.5 s ≈ **4,968
instance-s/month = $0.17**, ~2.7% of the free tier; requests stay free.

**Sensitivity:** the total is near-linear in visits — $3.9 at 5 visits/user/month, $12.7 at 20. The
*ranking* is unchanged in every case.

---

## 3. Free wins

### F1 — `application/wasm` is not compressed, while `application/x-protobuf` is compressed and made larger

**Class:** cost · **Confidence:** measured · **Where:** `application.properties:154`
**Evidence:** `quarkus.http.enable-compression=true` with no `compress-media-types` anywhere in the
repository. On the wire, against production (request 5 of the ledger):

```
GET https://zen-demo-server-tovqpjhspa-lm.a.run.app/main.dart.wasm
  content-type: application/wasm   content-length: 2488203
  wire bytes:   2488203            (no content-encoding header at all)
```

The default list is exactly inverted: it **includes** `application/x-protobuf`, inflating a 28-byte
health response to **55 bytes (+96%)**, and **excludes** `application/wasm`, the 2.4 MB asset on
every visitor's critical path. `gzip -6` over the real files: `main.dart.wasm` 2,488,178 → **910,148**;
`canvaskit/skwasm.wasm` 3,580,947 → **1,535,387**.
**Cost today:** 3.45 MiB per first visit; ~$0.02/mo.
**Cost at 2K MAU:** 33 GiB, **$3.48/mo**.
**Fix:** set `quarkus.http.compress-media-types` explicitly — include `application/wasm`, drop
`application/x-protobuf`.
**Invariant touched:** none.
**What the fix costs:** CPU per response, on a service at 2.7% of its compute free tier. Nothing else.
**How to verify:** `curl -s -o /dev/null -H 'Accept-Encoding: gzip' -w '%{size_download}'` on
`/main.dart.wasm` returns ≈910,000, and the response carries `content-encoding: gzip`.

### F2 — `Last-Modified` is the container's start time and no `ETag` is sent, so a returning visitor re-downloads the app on every container replacement

**Class:** both · **Confidence:** measured · **Where:** Quarkus static handler over resources
embedded in the native binary; interacts with `StaticCacheHeaders` (`zen-transport`) and
`--min-instances=0`.
**Evidence:** restarting the container moved `main.dart.wasm`'s validator, and replaying the previous
one returned the whole body:

```
before restart:  Last-Modified: Fri, 7 Aug 2026 13:52:06 GMT
after  restart:  Last-Modified: Fri, 7 Aug 2026 13:53:55 GMT
replayed If-Modified-Since  ->  200, 2,488,178 bytes   (not 304)
If-None-Match               ->  200, 2,488,178 bytes   (no ETag is ever sent)
```

Confirmed in production inside request 5: the live service answered
`last-modified: Fri, 7 Aug 2026 14:00:11 GMT` — one minute earlier, when the container cold-started
for request 1. Measured from the server's own access log, a returning visitor with a fully warm
cache meeting a new container transfers **2,500,802 bytes**; with a stable validator it would be four
304s ≈ **12 KB**.

**This is already the dominant cost, not a projection.** Joining the 648 recorded request-log entries
to measured wire sizes: `main.dart.wasm` was fetched **44 times in 7 days** — **109 MB of the
117 MB this service has ever sent, 93%** — at ~93 requests/day.
**Cost today:** 2.37 MiB per returning visit; ~$0.03/mo.
**Cost at 2K MAU:** 15 GiB, **$1.60/mo**.
**Fix:** emit a build-stable validator — a content `ETag`, or a `Last-Modified` derived from the
build rather than from process start.
**Invariant touched:** none.
**What the fix costs:** nothing found. `immutable, max-age=86400` files are already unaffected within
their day; this only makes revalidation capable of succeeding.
**How to verify:** restart the container, replay the prior `If-Modified-Since`, expect **304**.

### F3 — Six superseded secret versions are billed for nothing

**Class:** cost · **Confidence:** measured · **Where:** Secret Manager in `jzen-prod`
**Evidence:** `gcloud secrets versions list --filter='state=ENABLED'` over all 17 secrets returns
**23 enabled versions**. `APP_DB_PASSWORD`, `APP_DB_USERNAME`, `AUTH_REDIRECT_URI`, `CORS_ORIGINS`,
`SITE_URL` and `ZEN_JOBS_TRIGGER_TOKEN` each carry 2. `deploy:cloudrun` pins `:latest`
(`Taskfile.yml:1784`), so six are unreferenced.
**Cost today:** 6 × $0.06 = **$0.36/mo — 29% of the whole bill.**
**Cost at 2K MAU:** unchanged.
**Fix:** disable the superseded versions.
**Invariant touched:** none.
**What the fix costs:** the previous value stops being available for a manual rollback. Destroying a
version is irreversible, which is why this is presented for decision rather than as an obvious win.
**How to verify:** the enabled-version count falls to 17.

### F4 — The `users` row is read twice per authenticated request, in two separate transactions

**Class:** latency · **Confidence:** measured · **Where:** `RoleAugmentor.java:60` →
`UserRoleLoader.java:51-59`, plus the resource's own load.
**Evidence:** from the database log on one authenticated `GET /api/v1/demo/profile`:

```
BEGIN → select …17 columns… from users where id=$1 → COMMIT
BEGIN → select …17 columns… from users where id=$1 → COMMIT
```

Byte-identical SQL, same parameter. Two `@Transactional` units mean two persistence contexts, so
Hibernate's first-level cache cannot serve the second. Priced at the measured cross-region round-trip
cost (§7.3).
**Cost today:** ~135 ms per authenticated request. **Cost at 2K MAU:** same per request.
**Fix:** let the resource use the entity the augmentor already loaded, or run both in one transaction.
**Invariant touched:** **none** — the role is still read from the database on **every** request, so
ADR-017's revocation guarantee is untouched. This is explicitly *not* a cache.
**What the fix costs:** nothing found.
**How to verify:** `log_statement=all`; one `users` select per authenticated request, not two.

### F5 — `jdbc.min-size=2` opens two cross-region connections during boot

**Class:** latency · **Confidence:** inferred-from-measurement · **Where:**
`application.properties:40`
**Evidence:** connections opened at boot, by configuration (measured):

| Configuration | Connections |
|---|---|
| as shipped | **4** |
| `min-size=0` **or** `min-size=1` | 3 |
| Flyway off | 2 |
| both off | 1 |

**This is the trap the plan warned about.** Locally `min-size=0` changes boot by **+12 ms** — noise,
and a timing-only reading would have discarded it. The connection count is the measurement; §7.3
prices a cross-region connection at **~332 ms**.
**Cost today:** ~330 ms of cold start, ~8 s/day. **Cost at 2K MAU:** same.
**Fix:** `quarkus.datasource.jdbc.min-size=1`.
**Invariant touched:** none.
**What the fix costs:** the pool opens that connection on first use instead. Under
`--min-instances=0` the first request is the scheduler tick, which has a 60 s budget and uses ~4 s.
**How to verify:** `log_connections=on`; three connections at boot, not four.

### F6 — 37.13 MiB of the shipped bundle is never fetched by any browser

**Class:** cost · **Confidence:** measured · **Where:**
`apps/zen_demo/zen_demo_server/src/main/resources/META-INF/resources`
**Evidence:** Chrome's network panel on a hard reload fetches **11 files** from the origin. The
renderer selected is **skwasm** — one variant of six, as ADR-016 intends. Never requested: five
renderer variants (25.8 MB), six `.symbols` maps (8.6 MB), `main.dart.js` (3.1 MB), `assets/NOTICES`
(1.4 MB) — **38,936,150 B = 37.13 MiB, 83.5% of the 44.49 MiB bundle.**

Ablation B4 (a native build with the bundle removed, validated by the image answering **404** for
`/main.dart.wasm`): binary 163,511,352 → **114,400,312 B (−30%)**; compressed layer 54,859,662 →
**38,542,959 B (−15.6 MiB)**; **boot time −7 ms, inside the noise.** The registry model checks out
against reality — 16 tags × 54.86 MB = 0.817 GiB against the 0.844 GiB Artifact Registry reports.
**Cost today:** 15.6 MiB per image pull; **$0.025/mo** of storage; **0 ms of boot**.
**Cost at 2K MAU:** unchanged — none of it is on the visitor's path.
**Fix:** prune the unused renderer variants and `.symbols` from the staged bundle. `main.dart.js` is
**not** in scope here — see F9.
**Invariant touched:** none. Flutter's loader selects skwasm at runtime and never asks for the rest.
**What the fix costs:** a future Flutter version could select a different renderer; the pruning must
be derived from the build rather than hand-maintained, or it becomes a trap.
**How to verify:** the bundle shrinks and `task test:native` still passes — 9 of its 136 tests fail
if the bundle goes missing entirely, so they are a real guard.

---

## 4. Priced trade-offs

### F7 — Flyway runs on every cold start to conclude there is nothing to do

**Class:** latency · **Confidence:** measured · **Where:** `application.properties:71`
**Evidence:** the window `Database:` → `Schema "public" is up to date` measured in production logs:
**1.423 s** median over 44 boots of `00013-qw9` and **1.434 s** over 36 boots of `00018-mn5` — flat
to within 25 ms across every revision, i.e. a fixed charge on all 24 daily boots. Of that, the log
reports only **0.180 s** as validation *execution*; the rest is round trips. Ablation: Flyway is
**41 of the boot's 53 DB round trips** and **2 of its 4 connections**.
**Cost today:** ~2,100 ms of cold start (41 round trips + 2 connections); ~50 s/day; **$0.05/mo**.
**Cost at 2K MAU:** unchanged — it is per container start, not per visit.

**The 2,100 ms does not all belong to migration, and this is the decisive detail.** Measured by
splitting the two Flyway phases:

| Configuration | DB round trips | Connections | Inferred production saving |
|---|---|---|---|
| As shipped (migrate + validate at start) | 53 | 4 | — |
| `migrate-at-start=false`, **`validate-at-start=true`** | **41** | **4** | **~420 ms** |
| …and `min-size=1` | 41 | 3 | ~750 ms |
| `migrate-at-start=false`, **`validate-at-start=false`** | **12** | **2** | **~2,100 ms** |

**Validation, not migration, is ~80% of the cost** — and validation *is* the guarantee. So:

- **Relocating migration to the deploy while keeping the agreement check buys ~420 ms**, and needs
  deploy-time migration machinery plus an ADR.
- **The remaining ~1,680 ms is only available by not checking at all**, which is not relocating the
  guarantee but abandoning it.

For comparison, **F5 alone buys ~330 ms for one environment variable.**

**Fix:** `migrate-at-start=false` with migration run at deploy time, `validate-at-start=true` retained.
**Invariant touched:** **6.** Not *whether* Flyway is the single authority — unchanged — but *when* it
runs.
**What the fix costs, precisely:** the schema can now be migrated ahead of the binary that will serve
it, so the deploy must order migration before the revision goes live, and a rollback to an older image
faces a newer schema. Keeping `validate-at-start=true` means that rollback still **fails closed at
boot** rather than serving against a schema it does not understand — which is why dropping validation
as well is a materially different decision from this one.
**How to verify:** boot logs contain `DbValidate` but not `DbMigrate`; `started in` drops by ~0.4 s;
a deliberately un-migrated database still refuses to boot.

### F8 — ADR-031's privilege split adds a cross-region connection to every cold start, and was never priced

**Class:** latency · **Confidence:** measured · **Where:** `application.properties:81-83`
**Evidence:** production's boot regressed **+0.804 s (+26%)** from `00013` to `00018`. Attribution,
by booting all four shipped images locally against fresh databases (all four were already present
locally, so this cost no registry egress):

| Revision | Local boot | **Production boot** | Round trips | **Connections** |
|---|---|---|---|---|
| 00013 `28b42da` | 0.976 s | 3.069 s | 49 | **2** |
| 00014 `e529c83` | 1.022 s | 3.387 s | 50 | **2** |
| **00015 `97a7f45`** | 1.052 s | **3.961 s** | 53 | **4** |
| 00018 `6794b49` | 1.000 s | 3.873 s | 53 | **4** |

**The connection count doubles at exactly the revision where production's boot jumps**, and locally
the same change costs 24–76 ms because a sibling container is free. `%prod.quarkus.flyway.jdbc-url`
gives Flyway its own DDL-role connection, so the application pool then opens its own `min-size=2`
afterwards — which is why the time lands in the post-Flyway window. Confirmed on one boot's timeline:
two Flyway connections, then two datasource connections, the last 0.32 s later.
**Cost today:** ~660 ms of cold start. **Cost at 2K MAU:** same.
**Fix:** none recommended.
**Invariant touched:** reversing it undoes a security decision made on blast radius (ADR-031).
**What the fix costs:** the least-privilege runtime role, which is the whole point of that ADR.
**The finding is that the cost existed and was invisible**, not that the decision was wrong.
**How to verify:** `log_connections=on`; four connections at boot today, two without the split.

### F9 — `main.dart.js` (3.08 MiB) ships and is never fetched

**Class:** cost · **Confidence:** measured · **Where:** the staged bundle
**Evidence:** absent from all 12 requests a browser makes; `flutter_bootstrap.js` probes WasmGC and
takes the Wasm path.
**Cost:** 3.08 MiB of binary and image; **0 ms of boot**; ~$0.002/mo of storage.
**Fix:** none recommended. **Invariant touched:** ADR-016 keeps the dart2js fallback deliberately, so
removing it narrows the browser floor from "WasmGC preferred" to "WasmGC required".
**What the fix costs:** every sub-WasmGC browser, for 3 MiB of image nobody downloads.
**How to verify:** n/a — listed so the next auditor does not re-propose it.

### F10 — The hourly tick may be load-bearing for keeping the free Supabase project awake

**Class:** cost · **Confidence:** unverified · **Where:** Cloud Scheduler `zen-jobs-tick`
**Evidence:** the tick costs ~129 s/day of billed instance time in total, **$0.13/mo gross and $0
after the free tier** — so Lead 7's compute argument for reducing its frequency does not survive
contact with the rates. Separately, the Supabase project is on the **free plan** and this tick is the
only thing that touches its database.
**Cost:** ~$0.001/mo of compute attributable to frequency.
**Fix:** none recommended without checking the pause behaviour first.
**Invariant touched:** none directly, but a paused database is an outage.
**What the fix costs:** possibly the database staying awake — **this is model knowledge and must be
confirmed on the Supabase dashboard before anyone reduces the interval.**
**How to verify:** the dashboard's idle-pause policy for the free plan.

---

## 5. Closed — investigated, correct as built, with the number

| Finding | Result |
|---|---|
| `proactive=true` making anonymous calls to authenticated paths do work | **0 DB round trips.** ADR-030's `SessionCookieAuthenticationMechanism` yields *no identity* before the augmentor is reached |
| JWKS retrieved at boot | **Not retrieved.** Boot is identical within 3 ms whether the endpoint is unreachable or real — retrieval is lazy |
| Artifact Registry accumulating every commit-SHA tag | **$0.034/mo.** The mechanism is real (one `COPY` layer per build, nothing dedupes); it would need ~30× growth to reach $1 |
| Cloud Logging ingestion | **$0.00.** 324 entries/day against 50 GiB/month free |
| Cloud Run request charges | **$0.00** today and at 2K MAU — 240,000 against a 2,000,000 free tier |
| Native build wall time (Lead 12) | **303–350 s** warm. The ~4.5-minute duplicated-plugin defect the pom records is gone |
| 45 MB of embedded resources slowing the boot | **−7 ms, inside noise** (B4). A size cost, not a time cost |
| The transport seam's CPU cost (Lead 10) | **Unmeasurable at jZen's payloads.** Protobuf is **23–62% smaller** than JSON (health 28 B vs 73 B); TTFB identical within noise |
| `--cpu-boost` being free latency (Lead 4) | **Premise refuted.** `run.googleapis.com/startup-cpu-boost: 'true'` is already set on the service. See F11 below |
| Cold-start baseline (ADR-027) | **Independently reproduced.** ADR-027 reported 2.6–3.3 s, mean 3.0 s on `00013-qw9` from 15 samples; 44 samples of the same revision give 2.592–3.375, mean **3.009** |

### F11 — the repository does not set what production runs on

Not a performance finding, but it falls out of the above and is worth recording. `deploy:cloudrun`
passes ten flags (`Taskfile.yml:1796-1809`) and **neither `--cpu-boost` nor `--execution-environment`
is among them**, while the deployed service carries `startup-cpu-boost: 'true'`. Every boot number in
this document is *already* a boosted boot. **The next `gcloud run deploy` that recreates the service
loses it silently.** The execution environment is likewise unannotated, so the service runs on
whatever generation Cloud Run currently defaults to — an unpinned generation is a reproducibility gap.

---

## 6. Open questions

| # | Question | The exact command / action |
|---|---|---|
| Q1 | Actual spend by SKU | Console → Billing → account **`01625D-FE6351-130968`** ("jLogic Software") → Reports; group by **SKU**, filter project `jzen-prod`. **No full month exists** — `jzen-prod` was created `2026-07-24T17:44:48Z`, so the honest range is 2026-07-24 → today. At ~$1.25/mo the report may round to $0.00 per SKU per day, which is itself corroboration |
| Q2 | Which Cloud Run execution environment serves | `gcloud run services describe zen-demo-server --project=jzen-prod --region=europe-central2 --format='value(spec.template.metadata.annotations)'` — confirms the annotation is absent |
| Q3 | Lead 5: can 200 concurrent requests actually be served by 1 vCPU / 256Mi against a 10-connection pool? | **Deliberately left open.** It needs load generation, which the ROE forbids against production, and no local instrument is representative when the local database is 0.1 ms away and production's is ~35 ms. The only headroom number this audit produced: **peak memory 73% of 256Mi** (`memory/utilizations` p99) at one request per hour |
| Q4 | Supabase free-tier quotas | Owner/dashboard. These are quotas, not bills — a breach is an interruption, not a charge |
| Q5 | The +283 ms of revision `00014` | **Unattributed.** No extra connections, one extra round trip, n=18 with one 4.294 s outlier. Stated rather than distributed |
| Q6 | Whether a one-off instrumented revision is acceptable | **No** — the ROE forbids deploys. Not needed: the INFO log answered everything it was reserved for |

---

## 7. Appendix

### 7.1 Production request ledger — 5 of 6

All against `https://zen-demo-server-tovqpjhspa-lm.a.run.app`, revision `zen-demo-server-00018-mn5`.

| # | Method + path | Purpose | Response | Cold or warm |
|---|---|---|---|---|
| 1 | `HEAD /` | confirm the configured origin serves | 200, 1.33 s | **cold** — this request started the container |
| 2 | `HEAD /main.dart.wasm` | compression — **answered nothing**, see Method | 200, 1.25 s | warm |
| 3 | `HEAD /canvaskit/skwasm.wasm` | compression — **answered nothing** | 200, 1.20 s | warm |
| 4 | `HEAD /flutter_bootstrap.js` | compression — **answered nothing** | 200, 0.64 s | warm |
| 5 | `GET /main.dart.wasm` | compression + content-type, on the wire | 200, ttfb 0.40 s, 2,488,203 B | warm |

Requests 2–4 were a method error on my part; request 5 answered the question. **One request unspent.**
Total egress caused by this audit ≈ 2.5 MB ≈ $0.0003. No image pulls: all four historical images were
already local.

### 7.2 The cold start, decomposed — revision `00018-mn5`

Medians. Cold request ≈ **4.51 s** end to end.

| Phase | Cost | Share | Confidence | Basis |
|---|---|---|---|---|
| Platform: image pull, sandbox, 17 secret injections | 726 ms | 16% | measured | `startup_latencies` mean − `started in` mean |
| Native init before the first log line | ~500 ms | 11% | inferred | 3.873 s − 3.373 s log window |
| **Flyway: 2 connections + 41 round trips** | **1,434 ms** | **32%** | **measured** | production log window, 36 boots |
| **Datasource pool: 2 connections (`min-size=2`)** | ~664 ms | 15% | inferred | 2 × 332 ms |
| Hibernate/JAX-RS/CDI init, `zen_jobs` read, residual | ~1,190 ms | 26% | subtraction | includes Q5's unattributed 283 ms |

Boot samples per revision, from 173 `started in` lines over 7 days: `00011` 3.243 s (n=40),
`00012` 3.022 (22), `00013` **3.009** (44), `00014` 3.313 (18), `00015` 4.030 (7), `00016` 4.041 (5),
`00018` **3.788** (36) — means.

**On `startup_latencies`:** it is a DISTRIBUTION, and its percentiles are bucket edges — the values
3045, 3868, 4681 and 6853 ms each recur across unrelated revisions, and the API even returns points
for revisions with no starts in the window. Used here for trend only; every absolute boot number
comes from the `started in` log line.

### 7.3 The price of a round trip and of a connection

**35.0 ms per round trip on an established connection**, derived without circularity: Flyway's round
trips are **41** (ablation B0 − B1, measured locally); production's Flyway window is **1.434 s**
(measured); 1.434 ÷ 41 = **35.0 ms**.

Applying that to the revision table leaves a residual only the connection count explains:

| Revision | Δ boot vs 00013 | explained by round trips | residual | per extra connection |
|---|---|---|---|---|
| 00014 | +318 ms | 35 ms | +283 ms | — (no extra connection) → **Q5** |
| 00015 | +892 ms | 140 ms | +752 ms | **376 ms** |
| 00018 | +804 ms | 140 ms | +664 ms | **332 ms** |

Cross-check: the same image boots in **0.961 s** locally against a sibling Postgres and **3.873 s** in
production. The 2.91 s gap over 53 round trips is ~55 ms — a **lower bound** on the network share,
since the local run is emulated and its CPU time is inflated.

### 7.4 Round trips per request path

| Path | DB round trips | GoTrue |
|---|---|---|
| static asset · `/api/v1/health` · anonymous `/api/v1/demo/ping` | **0** | 0 |
| **anonymous** call to an authenticated path (401) | **0** | 0 |
| `POST /api/v1/auth/login` | 3 (1 tx) | 1 |
| `POST /api/v1/jobs/trigger` — valid, nothing due | 6 (2 tx) | 0 |
| `POST /api/v1/jobs/trigger` — **bad token** (401) | 3 (1 tx) | 0 |
| authenticated GET using **no** user data (`/demo/ping`) | 3 (1 tx) | 0 |
| **authenticated GET returning user data** | **6 (2 tx)** | 0 |

### 7.5 The delivered frontend

**First visit = 6,125,916 B = 5.84 MiB** across 11 origin files, of which **99.1%** is two
uncompressed wasm files (`skwasm.wasm` 3,580,947 + `main.dart.wasm` 2,488,178).
**Returning visit = 2,500,802 B = 2.38 MiB**; it would be ~12 KB with a stable validator.
Staged bundle: **43 files, 46,654,420 B = 44.49 MiB** — `canvaskit/` 36.69 MiB (82.5%), of which
`.symbols` 8.24 MiB; root 5.37 MiB; `assets/` 1.35 MiB; `admin/` 0.95 MiB; `icons/` 0.13 MiB.

The app also fetches Roboto from **`fonts.gstatic.com`** — explicitly permitted by the CSP
(`font-src 'self' https://fonts.gstatic.com`), so a deliberate allowance costing jZen no egress, but a
third party on the first-render path that no architecture document names.

### 7.6 Two build observations

- **A resource deleted from source can survive into a shipped native image.**
  `task build:server:native` does not `clean`, so a stale `target/classes/META-INF/resources`
  re-embeds it. Measured: the first B4 attempt produced an image that served the full bundle it was
  built without. Same family as ADR-037's cached web bundle — a build that succeeds, reports success,
  and ships bytes no source tree contains — but with no assertion that would catch it.
- **`task test` is 122 s; one native build is 303–350 s.** The expensive part of the feedback loop is
  the native image, by ~3×, and `task test` deliberately does not build one.

### 7.7 Instance lifetime

Pairing each `started in` with the next `stopped in` (n=173): median uptime **902.5 s ≈ 15 min**, with
157 of 173 in that bucket. `billable_instance_time` is **110–158 s/day**, so idle retention is **not
billed**. Two consequences: a visitor arriving within ~15 minutes of a tick gets a warm instance
(~7 ms median across 648 recorded requests), and ADR-029's premise holds — the process is replaced
hourly because retention (15 min) is shorter than the tick interval (60 min).
