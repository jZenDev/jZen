# Execution plan: the architectural performance & hosting-cost audit

A working document, not a source of truth. The architecture docs in
[`../../architecture/`](../../architecture/) remain authoritative, and ADRs win on conflict.

**Written:** 2026-08-05
**Briefed by:** [`PERFORMANCE-AUDIT-PROMPT.md`](PERFORMANCE-AUDIT-PROMPT.md) — that file states *what*
the audit must produce and what would make it worthless. This file states *how*: the order of work,
the exact commands, the shape of each measurement, and the traps that would make a number wrong
without making it look wrong.
**Produces:** `docs/plans/PERFORMANCE-AUDIT.md` and nothing else. No code change, no ADR, no
committed measurement artifact.

**§1 is the part to read first.** A reconnaissance pass on 2026-08-05 — control-plane reads and
recorded logs only, zero requests against the service — resolved most of what a cold auditor would
have spent Phase 4 discovering, and it **refutes one of the brief's twelve hypotheses outright while
handing another one its answer**. The phase order below departs from the brief's for that reason, and
§5.1 says why.

---

## 1. What is already resolved

Every row was obtained on **2026-08-05** by a read that touched no request path: `gcloud` control
plane, Cloud Logging (recorded history), Cloud Monitoring REST. Nothing here woke a container.

**These are dated observations offered as evidence, not configuration.** STANDARDS "Deployment model"
forbids committing a deployed fact because `destroy:cloudrun` cannot edit this repository, so
anything recorded here outlives what it names. The precedent is ADR-037, which records a live
observation for the same reason. Each row therefore carries the command that re-establishes it, and
**every one must be re-run at audit time** rather than cited from this table.

### 1.1 The environment

| Fact | Value as observed 2026-08-05 | Re-establish with |
|---|---|---|
| GCP project | `jzen-prod` (also named in ADR-027, ADR-031, ADR-037, and both implemented plans) | `gcloud projects list` |
| Credentials | the owner's account, **full read/write** — so the ROE is a discipline, not a permission boundary | `gcloud auth list` |
| Region / service | `europe-central2`, `zen-demo-server`, one revision at 100% traffic | `gcloud run services describe` |
| Capacity, as deployed | concurrency 200, timeout 60s, maxScale 1, 1 vCPU, 256Mi — matches `Taskfile.yml` defaults exactly | `--format='yaml(spec.template.spec)'` |
| **Startup CPU boost** | **`run.googleapis.com/startup-cpu-boost: 'true'` — already ON** | `--format='value(spec.template.metadata.annotations)'` |
| Execution environment | **no annotation** — the service runs on Cloud Run's default generation, whatever that currently is. Unresolved and worth resolving | same |
| Scheduler | one job, `0 * * * *`, `ENABLED` — the hourly tick, confirmed live | `gcloud scheduler jobs list` |
| Secrets | **17** (the 14 config + `ZEN_JOBS_TRIGGER_TOKEN` + `APP_DB_USERNAME`/`APP_DB_PASSWORD`), all injected as env vars per instance start | `gcloud secrets list` |
| Artifact Registry | **51 images, 16 tagged, 906.058 MB repository total**, oldest 2026-07-24 | `gcloud artifacts repositories describe jzen` |
| Supabase | **AWS `eu-west-1` (Ireland)**, reached through the session pooler, **PostgreSQL 17.6**, 9 migrations applied | the `DB_URL` secret; the pooler host is echoed in every boot's Flyway log line |
| Supabase plan | **still unknown** — the CLI needs `SUPABASE_ACCESS_TOKEN` | `supabase login` then `supabase projects list` |
| Billing | account linked and open; **no BigQuery dataset in the project**, so there is no billing export to query | `gcloud billing projects describe`, `bq ls` |
| Log volume | **~319 entries/day** for the whole service | `gcloud logging read … --freshness=1d` |
| Monitoring access | `gcloud monitoring time-series` **does not exist** in this SDK; the v3 REST API works with `gcloud auth print-access-token` | see §5.2 |

### 1.2 The cold start is already decomposed in the production logs

This is the reconnaissance pass's main result, and it changes the audit's centre of gravity. Quarkus
logs at INFO in `%prod`, Cloud Logging keeps it, and **one hourly tick is one complete cold start**.
No instrumented build, no deploy, no emulation, no requests. One tick's window, verbatim timestamps:

| Time (2026-08-05) | Line | Δ |
|---|---|---|
| `20:00:04.190` | first container log line | — |
| `20:00:05.535` | `io.quarkus.config` deprecation warning | +1.345s |
| `20:00:06.139` | `FlywayExecutor` — `Database: …aws-0-eu-west-1.pooler.supabase.com… (PostgreSQL 17.6)` | +0.604s |
| `20:00:06.711` | `DbValidate` — `Successfully validated 9 migrations (execution time 00:00.180s)` | +0.572s |
| `20:00:07.455` | `DbMigrate` — `Current version of schema "public": 20260804113000` | +0.744s |
| `20:00:07.493` | `DbMigrate` — **`Schema "public" is up to date. No migration necessary.`** | +0.038s |
| `20:00:08.612` | `started in 3.433s. Listening on: http://0.0.0.0:8080` | +1.119s |

**Flyway spans 1.354s of a 3.433s boot — roughly 40% — to conclude that there is nothing to do**,
across Warsaw ↔ Ireland, on every one of 24 container starts a day. Of that 1.354s only 0.180s is
validation *execution*; the rest is round trips. Hypotheses 1 and 6 are therefore not speculative
any more: they have a number, and the audit's job is to confirm it across N ticks, attribute the
remaining ~2.1s, and price the fix.

Twelve `started in` samples from 2026-08-05: **3.310, 3.333, 3.433, 3.608, 3.903, 3.994, 4.006,
4.010, 4.049, 4.059, 4.066, 4.177** — mean **3.83s**, median **4.00s**, range 3.31–4.18s.

**Against ADR-027's baseline that is a regression.** ADR-027 measured 2.6–3.3s (mean 3.0s) of Quarkus
boot on revision `00013-qw9` on 2026-08-03. Cloud Run's own `startup_latencies` metric agrees on the
direction across revisions. **Establishing what grew — Quarkus 3.32→3.38, the web bundle, the
privilege cutover's extra connection, or something else — is a finding the brief did not ask for and
is worth more than most that it did.** It is also free: every revision's boots are still in the log.

### 1.3 What this does to the brief's twelve leads, before the audit starts

| Lead | Status after reconnaissance |
|---|---|
| **1** — the 3.0s boot is not native boot | **Confirmed, and partly decomposed** (§1.2). ~40% is Flyway doing nothing. Remaining work: attribute the other ~2.1s. |
| **4** — `--cpu-boost` is free latency | **Premise refuted.** The brief reasoned from `Taskfile.yml` passing no `--cpu-boost`; the deployed service carries `startup-cpu-boost: 'true'` regardless. Every number in §1.2 is *already* a boosted boot. The finding is now the inverse and it is a real one: **the repository does not set what production runs on**, so the next `gcloud run deploy` that recreates the service loses it silently. Reframe from "turn it on" to "the deploy and the deployment disagree, and the deployment is not in version control." |
| **6** — Flyway on every cold start | **Measured: 1.354s of 3.433s.** Goes straight to pricing. |
| **7** — 24 container starts/day | **Confirmed live** — scheduler `0 * * * *`, `ENABLED`, and 24 boots visible in a day of logs. |
| **8** — Artifact Registry accumulates | **Measured: 51 images / 16 tagged / 906 MB.** Note the total is Google's deduplicated repository size, not 51 × image size — the audit must not multiply. |
| **9** — role lookup per authenticated request | Unchanged, and now sharper: every such lookup is a **cross-region** round trip, Warsaw → Ireland. |
| **2, 3, 5, 10, 11, 12** | Unchanged; local work resolves them. |
| *(new)* Cloud Logging ingestion | ~319 entries/day is far inside any free allowance. **Likely a "Closed" finding** — measure it once, say the number, move on. |
| *(new)* Supabase is in another country | `eu-west-1` vs `europe-central2` multiplies every boot-path and request-path round trip. This is upstream of leads 1, 6 and 9 and is probably the single largest structural cost in the service. |

---

## 2. Preconditions

| # | Precondition | Check | If absent |
|---|---|---|---|
| 2.1 | Toolchain at the pinned versions | `task doctor` | Fix with the tool doctor names. Do not proceed on a red doctor — a different Dart produces a different bundle, and the bundle is Phase 5's subject. |
| 2.2 | Docker running, ≥25 GB free | `docker info`, `df -h` | The native build, smoke Postgres, and ablation images are all containers. |
| 2.3 | Host architecture recorded | `uname -m` | Not a blocker — a **required field in the report**. See §4.1. |
| 2.4 | `gcloud` authenticated | **satisfied** (§1.1) | — |
| 2.5 | Supabase dashboard / `SUPABASE_ACCESS_TOKEN` | **outstanding** — the one genuinely open owner question | Supabase plan, compute size and its own usage stay unknown; label every Supabase-dependent number inferred. |
| 2.6 | Local Supabase stack free to start/stop | `task run:supabase` / `task stop:supabase` | Phase 4 needs it for the Supabase-Auth round-trip count. |

Nothing outside the repository is modified (CLAUDE.md "Working discipline"). Raw logs and
intermediate CSVs go to the session scratchpad; only `docs/plans/PERFORMANCE-AUDIT.md` is created.

---

## 3. Rules of engagement

### 3.1 Forbidden, without exception

```
task destroy:cloudrun          # deletes the GCP project AND the Supabase project
task deploy:cloudrun           # deploy is a manual human act in this repository
gcloud run services update     # any mutation of the live service
gcloud run deploy
gcloud secrets create/update/delete
ab / wrk / hey / k6 / siege    # against production, in any quantity
for i in $(seq …); do curl …   # a loop of curls is load generation
```

The credentials permit all of these (§1.1). That is exactly why the list is written down.

### 3.2 The production request budget: **6**

The reconnaissance in §1 spent **zero** requests, and it produced the boot decomposition, the
capacity facts, the registry total and the scheduler cadence. Almost everything else the audit needs
from production is likewise already recorded. Six is therefore not austerity — it is what is left
over once recorded evidence has been used properly:

| Reserved for | Requests |
|---|---|
| Confirm which hostname serves, and that it is the configured origin (§4.3) | 1 |
| `Content-Encoding` / `Content-Length` of `main.dart.wasm` **as production actually serves it** | 2 |
| The same for one `canvaskit/*.wasm` and one text asset | 2 |
| Spare | 1 |

Log every one in the report:

| # | Method + path | Purpose | Response | Cold or warm |
|---|---|---|---|---|

The first request of a sitting is a cold start and the container then stays warm for minutes — so
request 1 is a free cold-start sample and requests 2+ are not independent of it. Record which.

### 3.3 `task verify:deploy` does not fit the budget, and it writes

The brief tells the auditor to run it *and* forbids writes and caps requests in the low tens. Counted
from `Taskfile.yml:1197` and `Taskfile.yml:1273`:

| Source | Requests |
|---|---|
| `verify:endpoints` — 5 paths × 3 transport modes | 15 |
| `verify:endpoints` — body, `/`, bootstrap, wasm ×3, `/admin/`, admin JS, headers ×3, CSP, `/openapi`, `/q/swagger-ui/` | ~14 |
| `verify:deploy` — **`POST /api/v1/auth/restore-password`** | 1 |
| `verify:deploy` — `/.well-known/assetlinks.json` | 1–3 |
| **Total** | **~32, one a POST** |

The POST is not inert: it passes `RateLimitFilter` → `DurableLimiter.increment`, an
`INSERT … ON CONFLICT … RETURNING` against `zen_rate_limit_counters`
(`server/zen-ratelimit/src/main/java/zen/ratelimit/DurableLimiter.java:59`), and it calls GoTrue. It
mails no one — the probe address is `@example.invalid` and `/restore-password` answers `204`
regardless — but it is a write to production state.

**Default: skip it.** It is a deployment-health gate, not a performance instrument, and nothing in
the audit depends on it. If the owner wants it run, `verify:endpoints` alone is read-only and costs
~29 requests, which means declaring a budget of ~35 in the report. Do not resolve this silently.

### 3.4 Locally, anything goes

Build, containerise, ablate, load-test to destruction. The local stack is the instrument; production
is the thing under glass.

---

## 4. Measurement hygiene — five traps

Ordered by how badly each corrupts the audit. Every one produces plausible numbers that are wrong.

### 4.1 Emulation distorts every local boot timing, in a known direction

`build:server:native` pins `linux/amd64` (`Taskfile.yml:416`) so the image matches Cloud Run. On an
arm64 Mac that binary runs emulated: **CPU-bound work inflates, network-bound work does not**. A local
decomposition therefore overstates CPU and understates I/O relative to production.

Two rules, both stated in the report:

1. Report local boot phases as **shares and deltas**, never as "this is what production does".
2. Prefer **production's own log timeline** (§1.2) for absolute boot numbers — it is exact,
   unemulated, free, and already recorded. Local ablation is for *attribution and for pricing a fix*,
   not for establishing the baseline.

Record `uname -m`, the Docker backend, and whether Rosetta/qemu is in play.

### 4.2 The local database is 0.1 ms away; Supabase is 1,800 km away

`test:native` runs Postgres as a sibling container (`Taskfile.yml:1172`). Production connects from
`europe-central2` (Warsaw) to a pooler in AWS `eu-west-1` (Ireland) — a round trip on the order of
tens of milliseconds, not microseconds.

**Method: count round trips locally, price them with production's own evidence.** A count is
architecture and transfers; a duration is environment and does not. Production's Flyway window
(§1.2) is a directly usable price for "what a handful of sequential round trips to that pooler
costs", and it needs no new measurement.

### 4.3 The two-hostname trap

ADR-037 records two names: the configured origin (`SITE_URL`, `CORS_ORIGINS`, `AUTH_REDIRECT_URI` and
`gcloud run services describe` all agree) and a newer one `deploy:cloudrun` prints on success. The
bundle is compiled against the configured one — client config is compile-time — so the other serves
the same app and blocks its own API calls as cross-origin. As of 2026-08-05 `describe` still returns
the hostname ADR-037 names, but treat that as possibly stale and confirm before recording a timing:

```
gcloud run services describe zen-demo-server --project=jzen-prod \
  --region=europe-central2 --format='value(status.url,status.latestReadyRevisionName)'
```

### 4.4 In a native image, a runtime log-level bump is silently ignored

`quarkus.log.min-level` is **build-time**, default `INFO`. Setting
`QUARKUS_LOG_CATEGORY__ORG_FLYWAYDB__LEVEL=DEBUG` on a native container changes nothing, errors
nothing, and looks exactly like "that component had nothing to say". Ways out:

- **Production's INFO log is already enough** for the Flyway and total-boot numbers (§1.2). Start
  there and stop if it answers the question.
- **Ablation on the shipping image** (§5.4 Method B) needs no extra logging at all.
- **One instrumented native build** for what neither reaches:
  `./mvnw -B package -Dnative -Dquarkus.log.min-level=DEBUG …` — on the command line, so no tracked
  file changes. Budget it once.

JVM mode (`task run:server`) is fine for **counting** round trips and reading DEBUG freely, and
useless for **timing** a native boot.

### 4.5 `startup_latencies` is a distribution; its percentiles are bucket edges

Cloud Monitoring's `run.googleapis.com/container/startup_latencies` is a DISTRIBUTION metric, so
`ALIGN_PERCENTILE_50` returns the *bucket boundary* containing the median — which is why the same
values (3045, 3546, 3868, 4681, 6853 ms) recur across unrelated revisions. Use it for **shape and
trend across revisions**; use the log line `started in X.XXXs` for any number that goes in a table as
a measurement. Saying which is which is the difference between evidence and decoration.

---

## 5. The phases

Eight phases. The order departs from the brief's deliberately (§5.1).

### 5.1 Why live evidence comes first here

The brief puts "read the live evidence" in Phase 4, after local baselining. That ordering assumes the
production side is expensive and risky to reach. It is neither: it is recorded history, it costs
nothing, it wakes no container — and, as §1.2 shows, it contains a **more accurate boot decomposition
than any local experiment can produce**, because it is unemulated and measured across the real
network path. Doing it first also stops the auditor from spending a day building a local instrument
to measure something the log already answers.

Local work is not thereby demoted. It is repositioned: it exists to **attribute what the log leaves
unattributed** and to **price fixes**, which is what a local instrument is genuinely good for.

---

### Phase 0 — Orientation (~1 h)

1. Read, in order: `CLAUDE.md`; `BLUEPRINT.md`; `STANDARDS.md` §§ "Deployment model", "Client config
   is compile-time", "Frontend split"; `DECISIONS.md` ADR-037, ADR-036, ADR-031, ADR-029, ADR-028,
   ADR-027, ADR-016, ADR-015, ADR-008.
2. Read the `deploy:cloudrun` `summary:` block (`Taskfile.yml:1419`) whole, and
   `apps/zen_demo/zen_demo_server/src/main/resources/application.properties` whole.
3. Reproduce the static inventory the brief's Leads table claims — **every row gets a verdict**:

```
R=apps/zen_demo/zen_demo_server/src/main/resources/META-INF/resources
du -sh $R $R/*
find $R -name '*.wasm'    -exec ls -l {} \; | sort -k5 -n
find $R -name '*.symbols' -exec ls -l {} \; | sort -k5 -n
```

**Done when:** every Leads row is marked `reproduced` / `not reproduced` / `changed`, and §1.3's
pre-resolved verdicts have been re-verified rather than inherited from this plan.

---

### Phase 1 — Harvest the recorded production evidence (~2 h, zero requests)

**Purpose:** everything production already knows, before anything is built locally.

```
P=jzen-prod; R=europe-central2

# Configuration, as deployed — the source for §1.1, all of it re-run rather than cited
gcloud run services describe zen-demo-server --project=$P --region=$R --format=yaml > describe.yaml
gcloud run revisions list --service=zen-demo-server --project=$P --region=$R
gcloud scheduler jobs describe zen-jobs-tick --project=$P --location=$R
gcloud secrets list --project=$P --format='value(name.basename())'
gcloud artifacts repositories describe jzen --location=$R --project=$P     # sizeBytes
gcloud artifacts docker images list $R-docker.pkg.dev/$P/jzen/zen-demo-server --include-tags

# The boot timeline, per tick. This is the audit's primary instrument.
gcloud logging read 'resource.type="cloud_run_revision" AND jsonPayload.message:"started in"' \
  --project=$P --freshness=7d --limit=200 --format='value(timestamp,jsonPayload.message)'

# One complete cold start, window by window (repeat for N ticks and for several revisions)
gcloud logging read 'resource.type="cloud_run_revision"
  AND timestamp>="…T19:59:00Z" AND timestamp<="…T20:01:00Z"' \
  --project=$P --limit=50 --format='value(timestamp,jsonPayload.loggerName,jsonPayload.message)'

# Log volume, for the ingestion bill line
gcloud logging read 'resource.type="cloud_run_revision"' --project=$P --freshness=1d \
  --limit=2000 --format='value(timestamp)' | wc -l
```

Cloud Monitoring has no `time-series` subcommand in this SDK (§1.1). Use the REST API:

```
T=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $T" \
  "https://monitoring.googleapis.com/v3/projects/$P/timeSeries?\
filter=metric.type%3D%22run.googleapis.com%2Fcontainer%2Fstartup_latencies%22\
&interval.startTime=<ISO>&interval.endTime=<ISO>\
&aggregation.alignmentPeriod=86400s&aggregation.perSeriesAligner=ALIGN_PERCENTILE_50\
&aggregation.crossSeriesReducer=REDUCE_MEAN&aggregation.groupByFields=resource.label.revision_name"
```

Worth pulling, same pattern: `billable_instance_time`, `instance_count`, `memory/utilizations`,
`cpu/utilizations`, `request_count`, `request_latencies`. Mind §4.5 on distributions.

**Records produced:**

| Record | Why it matters |
|---|---|
| N ≥ 24 `started in` samples for the current revision | the boot baseline, exact and unemulated |
| The same for revisions `00013` (ADR-027's) and each since | the regression trend (§1.2) — free, and nobody has looked |
| A per-phase cold-start timeline, N ticks | the decomposition; Flyway is already at ~1.35s |
| Memory utilisation vs 256Mi, CPU vs 1 vCPU | the real headroom for Lead 5 |
| Log entries/day | the Cloud Logging bill line, probably to close |
| Registry total + image count + tag count | Lead 8, already 906 MB / 51 / 16 |

**Traps:** §4.5 (bucketed percentiles). Also, a `jsonPayload.message` filter misses lines Quarkus
emits without a logger name — read whole windows, not only matching lines.

---

### Phase 2 — Billing reality (~1 h, or an owner round-trip)

The single most valuable artifact in the audit is the **billing breakdown by SKU for the last full
month**. There is no BigQuery billing export in the project (§1.1), and `gcloud` exposes no cost
report, so there are exactly two routes:

1. The **Cloud Console** billing report — group by SKU, filter to `jzen-prod`, last full month. The
   owner has access. A screenshot or CSV export is enough, and it settles the entire cost model.
2. Failing that, model it — and label every line **inferred**, per §6.

Also record: whether the project is inside any free-tier allowance, and the Supabase plan (§2.5).

**Precedent worth honouring:** `SECURITY-REMEDIATION.md`'s preamble states plainly that its Cloud
Armor pricing "comes from model knowledge rather than a live pricing page". That is the standard —
say where a number came from, every time.

---

### Phase 3 — Local baseline: build it, size it (~2–3 h wall, mostly waiting)

```
task deps
task build                     # includes sync:contracts — must pass clean first
task build:web ; task build:web:admin
time task build:server:native  # Lead 12: paid on every deploy
task test:native               # builds + boots the image in Docker, asserts both transports
```

| Measurement | How |
|---|---|
| Native runner binary size | `ls -l apps/zen_demo/zen_demo_server/target/*-runner` |
| Image size, total and per layer | `docker images`, `docker history --no-trunc` |
| Share of the image that is static assets | image size vs `du -sh $R` |
| **Whether the 45 MB sits in a layer that changes every deploy** | `docker history` — this decides whether 51 tags cost 51× or dedupe to the 906 MB observed |
| Native build wall time | `time`, ≥2 runs, cold and warm Maven repo |
| `task test` incl. `test:e2e` | once, for completeness — it is the release gate |

**Trap:** record whether the Maven repo and GraalVM builder image were warm; a cold first build
includes a multi-GB pull and is not the number to report.

---

### Phase 4 — Attribute the rest of the boot, and price the fix (~2–3 h)

Production has already given ~1.35s of 3.43s to Flyway (§1.2). This phase attributes the remaining
~2.1s and establishes what each candidate fix actually buys.

| Candidate | Mechanism | Method |
|---|---|---|
| Flyway | `migrate-at-start=true` in every profile (`application.properties:71`), own DDL-role connection (`:78–83`), cross-region | **already measured**; ablation B1 prices removal |
| Datasource `min-size=2` | `application.properties:40` — two connections opened across Europe before serving | B2 |
| JWKS retrieval | `mp.jwt.verify.publickey.location` is a URL (`:95`); eager vs lazy unestablished | B3 |
| Secrets + image pull | 17 secrets injected per instance start; both precede the process | not app-visible — read `startup_latencies` minus `started in` (Phase 1) |
| 45 MB of embedded resources | baked into the binary | B4 |
| Residual framework init | — | subtraction |

**Method B — ablation, one variable per run**, same image, N ≥ 5 each, median of `started in`:

| # | Override | Isolates |
|---|---|---|
| B1 | `QUARKUS_FLYWAY_MIGRATE_AT_START=false` | Flyway entirely |
| B2 | `QUARKUS_DATASOURCE_JDBC_MIN_SIZE=0` | eager pool fill |
| B3 | `SUPABASE_JWKS_URL=http://127.0.0.1:1/jwks.json` | whether JWKS is fetched at boot at all — a boot that does not slow down proves it is lazy, which is itself a finding |
| B4 | native image built with `$R` emptied | the cost of carrying 45 MB |
| B5 | B1 + B2 | the floor with no database work |

Server config is runtime by design (CLAUDE.md), so none of B1–B3 needs a rebuild — **but verify that
per property**: an override that changes nothing may mean the component is cheap *or* that the
property is build-time fixed, and those look identical (§4.4). B4 costs one extra native build
(~10 min); it is worth it, because it prices Lead 2 in milliseconds rather than megabytes.

**Method D — round-trip counting**, to convert local counts into the cross-region price:

```
docker run -d --name zen-smoke-db --network zen-smoke-net \
  -e POSTGRES_PASSWORD=smoke -e POSTGRES_DB=postgres postgres:17-alpine \
  -c log_statement=all -c log_connections=on -c log_disconnections=on
docker logs zen-smoke-db 2>&1 | grep -c 'statement:'
```

**Records produced:** a decomposition table — phase, production ms (from the log), local median
(emulated), DB round trips, attribution confidence — plus an explicit "unattributed" residual.

**Done when:** production's boot is accounted for to within ~10%, every row carries either a measured
delta or an honest "unattributed", and the ADR-027 → today regression has a named cause or an
explicit "not established".

---

### Phase 5 — Trace the five request paths (~2 h)

Count network round trips **off the container** per request, and name each one. Remember every
Postgres round trip is Warsaw → Ireland.

| Path | What to establish |
|---|---|
| Anonymous `GET` of a static asset | zero round trips — confirm, don't assume |
| Anonymous API `GET` (`/api/v1/health`, `/api/v1/demo/ping`) | burst limiter is in-memory (ADR-029); is anything else on the path? |
| Authenticated API `GET` (`/api/v1/demo/profile`) | `RoleAugmentor:60` → `UserRoleLoader.loadRole` — one `users` read **per request**, cross-region, by design |
| `POST /api/v1/auth/login` | GoTrue call + `DurableLimiter` write + cookie mint |
| `POST /api/v1/jobs/trigger` | the hourly tick: durable write + `zen_jobs` read + job work + status write |

Instruments: Postgres `log_statement=all` (above); `task run:supabase` plus GoTrue/Kong logs for the
auth round trips; `curl -w '%{time_starttransfer}'`, N ≥ 10, median and p95, against the local
container, labelled local/emulated/sub-ms-DB.

**Also here — Lead 10, the seam has never been priced:** the same payload through
`X-Zen-Transport: json` and `X-Zen-Transport: protobuf`. Bytes on the wire (with and without
`Accept-Encoding: gzip`) and CPU per request. The architecture's central mechanism should have a
number attached to it and does not.

**Trap:** `quarkus.http.auth.proactive=true` means authentication runs before resource matching, so
an anonymous request to an authenticated path still does work. Measure both.

---

### Phase 6 — Weigh the delivered frontend (~2 h)

The fixed cost every visitor pays. Serve the **local smoke container** for all of it — same bundle,
same static handler, zero production requests — then spend 4 of the 6 budgeted requests confirming
compression on production itself, because that is the one property a local container could plausibly
differ on.

1. **First visit, on the wire**, per file:

```
curl -s -o /dev/null -H 'Accept-Encoding: gzip, br, zstd' \
  -w '%{url_effective} %{size_download} %{content_type} %{time_total}\n' http://localhost:18080/<path>
curl -sI -H 'Accept-Encoding: gzip, br' http://localhost:18080/main.dart.wasm \
  | grep -i 'content-encoding\|content-length\|cache-control\|etag'
```

`%{size_download}` is post-decompression — read `Content-Length` for the wire figure and say which
you used.

2. **Which files does the browser actually request?** Leads 2 and 11, and no directory listing can
   answer it. Load the local container in a real browser and read the network panel. Establish:
   - which of the **7 `.wasm` renderer variants** is fetched (`canvaskit.wasm` 6.9M,
     `chromium/canvaskit.wasm` 5.5M, `skwasm_heavy.wasm` 4.9M,
     `experimental_webparagraph/canvaskit.wasm` 3.9M, `wimp.wasm` 3.4M, `skwasm.wasm` 3.4M);
   - whether `main.dart.js` (2.9M) is ever fetched in the Wasm build;
   - whether any `.symbols` file (**8.3 MB across six files**) is ever requested by anything;
   - whether `assets/NOTICES` (~1.3MB) is fetched, and when;
   - whether `/admin/` (980K) is fetched by an ordinary visitor at all.

   Read `flutter_bootstrap.js` / `flutter.js` to understand the selection logic, then confirm on the
   wire. The loader is inference; the network panel is measurement.

3. **Returning visit.** `StaticCacheHeaders`
   (`server/zen-transport/src/main/java/zen/transport/StaticCacheHeaders.java`) forces `no-cache`
   revalidation on exactly the fixed-name entry files and leaves everything else — including all of
   `canvaskit/` and `assets/` — on `public, immutable, max-age=86400`:

```
etag=$(curl -sI http://localhost:18080/main.dart.wasm | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' -H "If-None-Match: $etag" \
  http://localhost:18080/main.dart.wasm
```

   A `304` is the point of that class; a `200` means revalidation re-downloads 2.4 MB and is a
   finding. Also price the 24-hour boundary: a daily returning visitor re-pulls all of `canvaskit/`.

4. **Compression, on the wire, both directions.** `quarkus.http.enable-compression=true` with **no
   `quarkus.http.compress-media-types`** (`application.properties:154`). Establish the effective
   default list, then verify per type — and verify `application/wasm` **on production**, since it is
   the largest asset on the critical path:

| Asset | Type | `Content-Encoding` | Wire bytes | Ratio |
|---|---|---|---|---|
| `main.dart.wasm` | `application/wasm` | | | |
| `canvaskit/*.wasm` | `application/wasm` | | | |
| `main.dart.js` | `application/javascript` | | | |
| `index.html` | `text/html` | | | |
| `assets/NOTICES` | (check) | | | |
| `/api/v1/demo/terms` | `application/json` | | | |

Read the header; never infer from a config key.

**Records produced:** first-visit table, returning-visit table, compression table, and two headlines
— **MB per first visit** and **MB per returning visit**.

---

### Phase 7 — Cost the findings (~1–2 h)

Two scenarios:

- **Today** — no user traffic, 24 ticks/day, occasional manual visits.
- **2K MAU** — STANDARDS "Deployment model". The repository already carries one usable traffic
  assumption: `SECURITY-REMEDIATION.md:138` sizes the durable limiter at **~20K auth events/month at
  2K MAU** (≈10/user/month). Reuse it and say so; state the visit model explicitly before the
  arithmetic, because the whole frontend number turns on it.

**Establish rates; do not recall them.** Record each rate *and* its source (pricing page URL + date
read, or the SKU line from Phase 2).

| Bill line | Unit to establish | Input |
|---|---|---|
| Cloud Run vCPU-s / GiB-s / requests | $/unit, `europe-central2`, incl. free tier | Phase 1 metrics × Phase 4 boot |
| **Internet egress from Cloud Run** | $/GB by destination | Phase 6 MB/visit × visits |
| Artifact Registry storage | $/GB-month | 906 MB observed (dedup, §1.3) |
| Secret Manager | $/version/month + $/10k access ops | 17 secrets × 24 starts/day |
| Cloud Scheduler | $/job/month beyond free jobs | 1 job |
| Cloud Logging ingestion | $/GiB beyond free allowance | ~319 entries/day — expect to **close** it |
| Supabase | plan + compute + egress | §2.5, if reachable |

Then per finding: **$/month at N visits**, **container-seconds/day**, **ms of cold start**, or **MB
per first visit**, with the arithmetic inline. A finding without a unit is an opinion.

---

### Phase 8 — Write, then clean up (~2 h)

§6 and §9 below.

---

## 6. What a finding must contain

```
### F<n> — <one-line claim, stated as the defect, not the fix>

**Class:** cost | latency | both
**Confidence:** measured | inferred-from-measurement | unverified
**Where:** <file:line, or the deployed resource>
**Evidence:** <the command you ran and the number it produced. Not a citation of a doc.>
**Cost today:** <unit — $/mo, container-seconds/day, ms, MB>
**Cost at 2K MAU:** <same units>
**Fix:** <the specific change>
**Invariant touched:** <one of the brief's §4, or "none">
**What the fix costs:** <what gets worse, or what guarantee is given up — "nothing" is a valid
answer only if you looked>
**How to verify the fix worked:** <the measurement that would prove it>
```

**Ranking rule** (state it): **(cost or latency removed) ÷ (invariant risk incurred)**. A 40 MB saving
that touches no invariant outranks a 400 ms saving that requires an edge in front of Cloud Run.

**Three groups, labelled:** **Free wins** (no invariant touched) · **Priced trade-offs** (an invariant
is touched; the number is presented and the human decides) · **Closed** (investigated, correct as
built, *with the number* — ADR-027's rejected options are the model).

### The invariants, as a pre-submission checklist

1. The client talks to exactly one server, and it is jZen's (`task verify:boundaries`).
2. Client config is compile-time. "Fetch the config at startup" is rejected on arrival.
3. The web app is served same-origin with the API (`*.run.app` is on the Public Suffix List).
4. Nothing sits between the client and Cloud Run. ADR-027 priced Cloud Armor (~$25–30/mo floor,
   rejected) and deferred Cloudflare free on invariants, not price.
5. `--max-instances=1` makes in-process state correct; `--min-instances=0` makes in-process time
   invalid. Both load-bearing.
6. Flyway is the single migration authority; a new table ships RLS + a policy in the same change
   (ADR-036). **Note this bites hypothesis 6**: moving migration out of process start is a change to
   *when* the single authority runs, not to *whether* — say precisely what is given up, namely the
   guarantee that a running binary and its schema agree.
7. One orchestrator (ADR-014, ADR-032).
8. No task swallows a failure; no gate is fingerprinted into skipping.

---

## 7. Deliverable skeleton

`docs/plans/PERFORMANCE-AUDIT.md`, following `docs/plans/implemented/DATA-API-EXPOSURE.md`:

```
# <title>

A working document, not a source of truth. The architecture docs in ../architecture/ remain
authoritative.

**Audited:** <date>
**Scope:** <in and out>
**Method:** measured / inferred-from-measurement / unreachable
           — host architecture and emulation status (§4.1)
           — the production request ledger, and the verify:deploy decision (§3.3)
           — the hostname every production measurement was taken against (§4.3)
           — which numbers came from recorded logs vs new requests vs local containers

## 1. Summary — the ranked list, one line each, with the unit
## 2. The cost model — bill lines, rates, and their sources
## 3. Free wins
## 4. Priced trade-offs
## 5. Closed — verified non-problems, with numbers
## 6. Open questions — each with the exact command a human should run
## 7. Appendix — raw measurement tables
```

Rank hard, cut anything without a number. Ten findings with arithmetic beat forty with adjectives.

**No ADR.** `DECISIONS.md` is an append-only archive of accepted decisions and an audit accepts
nothing on its own. If the owner then takes a decision, record it with the `add-adr` skill.

**No code changes.** If a fix is trivial and obviously free, say so and let the owner decide.

---

## 8. Effort and ordering

| Phase | Wall time | Attention | Unattended |
|---|---|---|---|
| 0 Orientation | ~1 h | high | no |
| 1 Recorded production evidence | ~2 h | **highest** | no |
| 2 Billing reality | ~1 h + owner | high | no |
| 3 Local build + sizes | 2–3 h | low | mostly |
| 4 Boot attribution + pricing | 2–3 h | high | no |
| 5 Request paths | ~2 h | high | no |
| 6 Frontend weighing | ~2 h | high | no |
| 7 Costing | 1–2 h | high | no |
| 8 Write + clean up | ~2 h | high | no |

**Constraints:** Phase 3's native build gates Phases 4 and 6 — start it early and read while it runs.
Phase 4's B4 needs a *second* native build; queue it once B1–B3 justify the ten minutes. Phase 2 can
run in parallel with everything, and its result may reweight the whole ranking, so do not leave it to
the end. Phase 7 needs 1, 4, 6 complete.

---

## 9. Stop conditions

Stop and ask rather than improvise if:

- A production read returns something unexpected — a 5xx, an unfamiliar revision or hostname. Do not
  probe to "understand it"; every probe spends budget and wakes a container.
- The request ledger reaches 6. Raising it is the owner's call, in writing, in the report.
- An ablation appears to require editing a tracked file. It does not: every server knob is runtime
  config or a `-D` on a build command. If one seems to require a source edit, that is a finding about
  configurability, not a licence to edit.
- The local Supabase stack or a container will not come down cleanly (§10).

---

## 10. Cleanup, verified

```
task stop:supabase
docker rm -f zen-smoke-app zen-smoke-db zen-boot 2>/dev/null; docker network rm zen-smoke-net 2>/dev/null
docker images | grep -E 'zen-native-smoke|zen-ablation'   # remove what this audit created
docker ps -a                                              # nothing from this audit
git status --porcelain                                    # ONLY docs/plans/PERFORMANCE-AUDIT.md
```

`git status` clean-but-for-the-report is the real check — verify it, don't assume it. If B4 emptied
`$R`, restore it with `task build:web && task build:web:admin` so the next `task test:native` does not
fail on a missing frontend.

---

## 11. What is still open

Everything else in §1 is resolved. These are not:

| # | Question | Default if unanswered |
|---|---|---|
| Q1 | **Supabase plan, compute size and usage** — needs `supabase login` or the dashboard | Recorded as unknown; every Supabase-dependent number labelled inferred. The region (`eu-west-1`) is already established and is the part that matters most. |
| Q2 | **The billing report by SKU** (Console; no export exists) | Model it and label every line inferred, per `SECURITY-REMEDIATION.md`'s own precedent. |
| Q3 | **`verify:deploy`: skip, `verify:endpoints` only, or whole?** (§3.3) | **Skip.** |
| Q4 | Which Cloud Run **execution environment** the service actually runs on — no annotation is set | Report as "default, unpinned", and note that an unpinned generation is itself a reproducibility gap. |
| Q5 | Is a one-off instrumented revision acceptable later, to close any residual the INFO log cannot reach? | **No** — the ROE forbids deploys. Record it as an open question with the exact command. Note that §1.2 makes this much less likely to be needed. |
| Q6 | The 2K-MAU visit model (visits/user/month, first vs returning) | Reuse `SECURITY-REMEDIATION.md:138`'s ~20K auth events/month, state the assumption, and show the arithmetic's sensitivity to it. |

---

## 12. What would make this audit worthless

- Restating `BLUEPRINT.md` / `STANDARDS.md` / an ADR as though it were a discovery.
- Reporting a number you did not produce, or putting an estimate in the same table as a measurement
  without labelling it. **Including the numbers in §1 of this plan** — they are dated observations to
  re-run, not results to cite.
- Recommending Redis, Kubernetes, a CDN, an API gateway, a second orchestrator, or an edge without
  engaging with the ADR that already rejected or deferred it and the price it named.
- Optimising throughput under load that does not exist, while ignoring the fixed cost of a bundle
  every visitor pulls and a boot every visitor waits for.
- Touching production with anything other than a read.
- A long report.
