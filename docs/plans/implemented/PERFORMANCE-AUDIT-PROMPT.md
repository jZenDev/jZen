# Prompt: architectural performance & hosting-cost audit of jZen

This file is **the brief you hand to the auditing model**, not the audit. Everything below the
`---` is the prompt; paste it whole, or point the agent at this file. The material above the `---`
is for the person commissioning the audit.

**Why this exists.** jZen's architecture docs already reason about performance more carefully than
most codebases ever do — ADR-027 measured cold starts on the live service, ADR-028 lists what every
Cloud Run knob invalidates, ADR-029 splits the rate limiter on a latency boundary. An audit that
merely restates that is worthless. The value is in the seams those documents do **not** cover: the
static-asset payload, the decomposition of the 3.0s "native boot", the request-path database
round trips, and the arithmetic that turns all of it into a monthly bill.

**Scope note for the commissioner.** The prompt is written for an agent with repository access, a
shell, and *read-only* credentials to the deployed environment. If the auditor has no cloud access,
Phase 4 degrades to arithmetic over the local measurements — say so up front rather than letting the
auditor guess.

---

# You are conducting an architectural performance and hosting-cost audit of jZen

## 1. Your objective

Produce a ranked, evidence-backed list of the architectural decisions in this repository that cost
**money**, **latency**, or **both**, in the deployed production shape — and for each one, the change
that removes the cost, the invariant that change touches, and the number that justifies it.

Two things this audit is **not**:

- It is not a code review. Do not report style, naming, missing tests, or security findings unless
  they carry a measurable performance or cost consequence. A separate security audit already ran
  (`docs/plans/implemented/SECURITY-REMEDIATION.md`); do not re-run it.
- It is not a summary of the architecture documents. The documents are the *baseline you start
  from*, not the material you report back. A finding that any of `BLUEPRINT.md`, `STANDARDS.md`, or
  `DECISIONS.md` already states, in the terms it already states them, is not a finding.

The primary axis is **hosting cost**. The production service carries essentially no user traffic
today; its bill is therefore dominated by fixed and per-deploy costs, by the hourly scheduler tick,
and by whatever a single visitor's page load actually pulls down. Optimise your attention
accordingly: a change that saves 300ms of p99 under load nobody is generating is worth less than one
that removes 40MB from every cold container or 24 pointless container starts a day.

## 2. Rules of engagement

**The live production service must not be disturbed.** It is not serving real users, but it is
billable and it is the only deployed environment.

- **Read-only. No writes of any kind.** No `POST`/`PUT`/`PATCH`/`DELETE` against the API, no
  `gcloud run services update`, no `gcloud run deploy`, no changes to Secret Manager, no Supabase
  dashboard changes, no schema changes.
- **No load generation.** No benchmark tool, no `ab`/`wrk`/`hey`/`k6`, no loop of curls, no
  parallel requests. `--max-instances=1` means any load you generate is a self-inflicted denial of
  service, and every request you make also *wakes a container you are then billed for*.
- **Budget your live requests explicitly.** Decide up front how many requests you will make against
  production (a small number — single digits to low tens), state that number in the report, and
  stay inside it. Prefer reading Cloud Run request logs and Cloud Monitoring metrics, which are
  already-recorded evidence and cost nothing to look at, over generating new traffic.
- **`task destroy:cloudrun` deletes the GCP project and the Supabase project. Never run it.**
  Never run `task deploy:cloudrun` either — deploy is a manual human act in this repository.
- Anything you cannot establish without violating the above is **an open question in the report**,
  with the exact command a human should run to close it. Do not guess and do not present an
  estimate in a table that also holds measurements.

**Locally, you may do anything.** Build, run, profile, containerise, load-test a local container to
destruction. The local stack is the instrument; production is the thing under glass.

## 3. Orient yourself first

Read these before forming a single hypothesis. They are the source of truth, and ADRs win on
conflict with earlier documents:

| Read | For |
|---|---|
| `CLAUDE.md` | the shape of the repository in one pass |
| `docs/architecture/BLUEPRINT.md` | the architecture as built — transport seam, persistence, deployment |
| `docs/architecture/STANDARDS.md` | the rules, especially **"Deployment model"** and **"Client config is compile-time"** |
| `docs/architecture/DECISIONS.md` **ADR-027** | the *measured* cold/warm baseline on the live service, and the rejected edge options with their prices |
| `DECISIONS.md` **ADR-028** | what each Cloud Run knob silently invalidates |
| `DECISIONS.md` **ADR-029** | why the rate limiter is split across memory and Postgres |
| `DECISIONS.md` **ADR-016**, **ADR-015** | why the web app is Wasm, and why it is served same-origin |
| `DECISIONS.md` **ADR-037** | why a compile-time define reaching a deployed artifact is asserted, not trusted |
| `Taskfile.yml` — the `deploy:cloudrun` `summary:` block | the six capacity knobs and their stated consequences |
| `apps/zen_demo/zen_demo_server/src/main/resources/application.properties` | every runtime knob the service actually boots with |

Then run `task --list` and `task doctor`. Do not invent commands; this repository has exactly one
orchestrator and every operation you need is a task in it.

## 4. Invariants your recommendations must respect

These are not preferences. Each one is written down with its reasoning, and each fails **silently**
when broken — which is why they are stated rather than discovered. A recommendation that breaks one
without saying so is a defect in your report.

1. **The client talks to exactly one server, and it is jZen's.** No client-side call to Supabase or
   any third party. Enforced by `task verify:boundaries`.
2. **Client config is compile-time.** No runtime configuration in the Dart/Flutter client — it is
   what makes the tree-shaking of platform-specific code work. A "just fetch the config at
   startup" recommendation is rejected on arrival.
3. **The web app is served same-origin with the API.** `*.run.app` is on the Public Suffix List, so
   a page and an API on two different Cloud Run URLs are cross-site and the `SameSite=Lax` session
   cookie is never sent. Any proposal that moves the frontend to a different origin must solve the
   cookie problem explicitly, in the proposal, with the mechanism named.
4. **Nothing sits between the client and Cloud Run.** An edge that strips or renames cookies breaks
   the whole auth path (normally-named cookies + `mp.jwt.token.cookie` + `proactive=true`), and a
   rewritten or redirected `/.well-known/*` breaks App Links verification in a way both Android and
   iOS *cache*. ADR-027 already priced Cloud Armor (~$25–30/mo floor, rejected on cost) and deferred
   Cloudflare free tier on invariants rather than price. If your best finding requires an edge, you
   must engage with ADR-027's reasoning rather than re-propose what it already weighed.
5. **`--max-instances=1` is what makes in-process state correct**, and `--min-instances=0` is what
   makes in-process *time* invalid. State that must outlive an hour goes to Postgres; work that must
   happen on a clock is triggered from outside. Both directions are load-bearing.
6. **Flyway is the single migration authority**, and every new table ships RLS plus an application
   policy in the same change (ADR-036). A performance recommendation that adds a table inherits that
   obligation.
7. **One orchestrator (`task`), no second build driver** (ADR-014, ADR-032). "Add Bazel/Nx/Melos for
   build speed" is closed.
8. **No task swallows a failure**, and no gate is fingerprinted into skipping. Speeding up CI by
   letting a gate skip its work is the failure mode STANDARDS names explicitly.

**The escape hatch, and it is real:** any of these may be revisited if the measurement warrants it.
The requirement is that you *name the invariant*, *quantify what breaking it buys*, and *state what
it costs*, so the decision is a decision. That is what an ADR is for — see §9.

## 5. The cost model you are auditing

Enumerate the actual bill lines before you look for savings, so every finding lands on one:

- **Cloud Run** — vCPU-seconds and GiB-seconds billed per request-handling time, plus per-request
  charges, plus **internet egress**. With `--min-instances=0` there is no idle charge; with
  `--max-instances=1` an attack costs availability, not money (ADR-027). The consequence: cost here
  is driven by *how many container-seconds each visit and each tick consumes*, and by *how many
  bytes leave the container*.
- **Artifact Registry** — storage per GB-month of every image tag ever pushed. Tags are commit SHAs
  and nothing prunes them. Check how many exist and how large each is.
- **Cloud Scheduler** — the job entry itself is nearly free; its *consequence* is not. One hourly
  tick is 24 container starts a day, each paying full boot.
- **Supabase** — the project's own plan/compute, plus whatever the connection and query pattern
  implies. Establish which tier the deployed project is on before assuming anything is free.
- **Secret Manager** — per active secret version per month, plus access operations. There are 14–16
  secrets, and every cold start reads them.
- **Egress** — the one most likely to be mis-modelled. Work out, from the actual staged bundle, how
  many bytes a first-time visitor pulls and how many a returning one does, then multiply by
  plausible visit counts. State the per-GB rate you used and where it came from.

Give every finding a **unit**: `$/month at N visits`, `container-seconds/day`, `ms of cold start`,
`MB per first visit`. A finding without a unit is an opinion.

## 6. Method

Work in phases. Do not skip to recommendations.

### Phase 1 — Establish the local baseline

Get the thing running and instrumented before theorising.

- `task doctor`, `task deps`, `task build`.
- `task run:demo` for a manual walkthrough; `task run:server` for backend-only dev mode.
- `task test` runs every suite including the live e2e gate — expensive, but it tells you what the
  system does when it is whole.
- `task build:server:native` then `task test:native` gives you the **actual artifact production
  runs**. This is the only honest place to measure boot; a JVM dev-mode start tells you nothing
  about a native cold start.

Measure, locally, with numbers you can reproduce:

- the size of the native runner binary, and of the container image;
- the wall time from `docker run` to first successful `/q/health` — and, critically, **the
  decomposition of it**: how much is process start, how much is Flyway, how much is the datasource
  pool opening connections, how much is JWKS retrieval, how much is everything else. Quarkus logs
  startup timings; turn up what you need to see it;
- warm request latency for a representative endpoint in each of the three shapes: unauthenticated
  read, authenticated read (which triggers role augmentation), and an auth endpoint (which triggers
  the durable rate-limit write).

### Phase 2 — Trace the request paths

For each of these, count the **network round trips off the container** per request, and name each
one:

- an anonymous `GET` of a static asset;
- an anonymous API `GET`;
- an authenticated API `GET`;
- `POST /api/v1/auth/login`;
- `POST /api/v1/jobs/trigger` (the hourly tick).

Round trips to Postgres and to Supabase Auth are the currency here. A round trip that happens on
every request is worth far more attention than one that happens per session.

### Phase 3 — Weigh the delivered frontend

The web bundle is baked into the native image and served by the same container. Establish:

- what a **first** visit downloads, by file, in bytes on the wire (not on disk);
- what a **returning** visit downloads, given `StaticCacheHeaders` (`zen-transport`) forces
  `no-cache` revalidation on the fixed-name entry files and leaves everything else on the long
  default cache;
- **which of the shipped renderer variants the browser actually fetches** at runtime, versus which
  are merely present;
- whether each large response is actually compressed on the wire. Verify with a real request and
  read the `Content-Encoding` header — do not infer it from a configuration key.

### Phase 4 — Read the live evidence (read-only)

**Resolve the environment; do not expect to find it written down.** STANDARDS "Deployment model"
forbids committing a deployed fact — no service URL, no revision, no image tag — because
`destroy:cloudrun` cannot edit this repository, so anything recorded here outlives what it names.
Resolve the coordinates the way `build:web` and `run:demo:native` already do:

```
gcloud run services describe <SERVICE_NAME> --project=<GCP_PROJECT> \
  --region=<GCP_REGION> --format='value(status.url)'
```

`SERVICE_NAME` defaults to `zen-demo-server` and `GCP_REGION` to `europe-central2` (`Taskfile.yml`
vars); the project is the operator's. `gcloud run services list` will show you what exists. The one
environment fact that *is* in the repository is an observation inside ADR-037, and it is there as
evidence for that decision rather than as configuration — treat it as possibly stale and verify.

**The two-hostname trap, and it will corrupt your measurements if you miss it.** ADR-037 records
that the service answers on **two** names: the configured origin (the one `SITE_URL`,
`CORS_ORIGINS`, `AUTH_REDIRECT_URI` and `gcloud run services describe` all agree on) and a newer
name that `deploy:cloudrun` prints on success. The web bundle is compiled against the configured
one — client config is compile-time — so opening the other serves the same app and then blocks
every one of its own API calls as cross-origin. A page-load measurement taken on the wrong hostname
looks like a working page with a broken backend, and none of its numbers mean anything. Confirm
which hostname you are on before you record a single timing.

Within the request budget from §2:

- `task verify:deploy` — the repository's own answer to "is the deployment healthy?". Read what it
  checks before running it.
- Cloud Run **request logs** and **metrics**: request count, instance-time, container start count
  and startup latency distribution, memory utilisation against the 256Mi limit, CPU utilisation
  against 1 vCPU. This is recorded history; it costs nothing and it is better evidence than
  anything you can generate.
- The **billing breakdown by SKU** for the project over the last full month, if you can reach it.
  This is the single most valuable artifact in the whole audit — it tells you where the money
  actually goes rather than where you assumed it goes.
- The Artifact Registry image list and total size.
- The Supabase project's plan, and its own usage metrics.

If any of this is unreachable, say so and give the exact command.

### Phase 5 — Cost the findings

Turn each measurement into money or milliseconds, with the arithmetic shown. Two scenarios:

- **today** — effectively zero user traffic, one hourly tick, occasional manual visits;
- **the target the architecture was sized for** — ~2K MAU, per STANDARDS "Deployment model".

A finding that saves nothing today but dominates at 2K MAU is still a finding; label it as such.

## 7. Leads

These came from a static reading of the repository on 2026-08-05. They are **hypotheses with
evidence attached, not conclusions**. Verify each before reporting it, discard the ones that do not
survive, and — more importantly — do not let this list bound your search. The best finding in this
audit is probably not on it.

Measured locally by inspection (reproduce before citing):

| Fact | Where |
|---|---|
| 45MB staged into the app server's static resources, baked into the native image | `apps/zen_demo/zen_demo_server/src/main/resources/META-INF/resources` |
| 37MB of that is `canvaskit/`, containing **7 `.wasm` renderer variants** (`canvaskit.wasm` 6.9M, `chromium/canvaskit.wasm` 5.5M, `skwasm_heavy.wasm` 4.9M, `experimental_webparagraph/canvaskit.wasm` 3.9M, `wimp.wasm` 3.4M, `skwasm.wasm` 3.4M) | same |
| **8.3MB of `.symbols` files** — debug symbol maps, shipped to the container | same |
| `main.dart.js` (2.9M) ships **alongside** `main.dart.wasm` (2.4M) — the dart2js fallback | same |
| `assets/NOTICES` is ~1.3MB | same |
| `quarkus.http.enable-compression=true` is set with **no `quarkus.http.compress-media-types`** | `application.properties:154` |
| `quarkus.flyway.migrate-at-start=true` in **every** profile, including `%prod` | `application.properties:71` |
| `quarkus.datasource.jdbc.min-size=2`, `max-size=10` | `application.properties:40-41` |
| `--concurrency=200` against that pool of 10, on 1 vCPU / 256Mi | `Taskfile.yml:50-54` |
| `gcloud run deploy` passes **no `--cpu-boost`** and no `--execution-environment` | `Taskfile.yml:1796-1809` |
| Every authenticated request loads the role from `users` — no cache, by design | `RoleAugmentor` → `UserRoleLoader.loadRole` |
| Auth endpoints and the job trigger take a Postgres write per request (`INSERT … ON CONFLICT … RETURNING`) | `DurableLimiter.increment` |
| JWKS cached 3h, refreshed hourly — against a process replaced roughly hourly | `application.properties:98-99` |
| Baseline to beat: cold 2.9–4.8s (mean 3.7s), of which "Quarkus native boot" 2.6–3.3s (mean 3.0s); warm TTFB 26ms | ADR-027, measured on the live service |

The hypotheses worth testing first:

1. **The 3.0s "native boot" is not native boot.** A Quarkus native image ordinarily starts in tens
   of milliseconds. 3.0s means something expensive happens during startup — Flyway connecting to a
   remote Supabase pooler and validating history on *every cold start*, the datasource opening
   `min-size=2` connections across the internet, JWKS retrieval, Secret Manager reads, or the sheer
   size of a binary carrying 45MB of static resources. **Decompose it.** ADR-027 measured the
   number honestly and did not attribute it; attributing it is the highest-value thing in this
   audit, because at 24 cold starts a day plus every real visit, this single number is the service's
   dominant unit of billed time.
2. **Most of the 45MB is never requested by any browser.** Establish which renderer the Wasm build
   actually loads, and what the other variants and the `.symbols` files are doing in a production
   image. Then price what removing them saves: image pull, binary size, container start, and
   Artifact Registry storage across every tagged image.
3. **`application/wasm` is very likely not in Quarkus's default compressed media types.** If so, the
   largest single asset on the critical path ships uncompressed. Verify on the wire, both directions.
4. **`--cpu-boost` is free latency.** Cloud Run's startup CPU boost costs nothing extra on a
   scale-to-zero service and directly attacks the number in hypothesis 1. Establish whether it
   applies to the measured bottleneck, or whether the bottleneck is I/O-bound (in which case it does
   not, and saying so is also a finding).
5. **`concurrency=200` and a 10-connection pool on 1 vCPU is an unexamined ratio.** The 200 is
   defended in ADR-027/ADR-028 as a DoS-surface number. Whether 200 concurrent requests can actually
   be *served* by this instance shape — and what happens at slot 11 when every request needs a
   connection for role augmentation — is a different question, and one nothing in the docs answers.
6. **Flyway on every cold start.** The schema does not change between deploys. Consider whether
   migration belongs to the deploy rather than to the process start — and if you propose that, say
   precisely what it costs: the guarantee that a running binary and its schema agree, which
   `migrate-at-start` currently provides for free.
7. **24 container starts a day for a tick that usually has nothing to do.** The tick exists because
   in-process time is invalid under scale-to-zero (ADR-008) — that reasoning is sound and is not
   what to attack. What is worth pricing is the *frequency*: what the interval actually needs to be
   given that due-ness is computed from `last_run_at` and missed ticks coalesce, and what an hourly
   versus daily tick costs in container-seconds.
8. **Artifact Registry accumulates every commit-SHA tag.** Nothing prunes. Measure the total.
9. **The role lookup per authenticated request** is a deliberate correctness choice (revoking a role
   must not wait for a token to expire). Do not propose caching it without addressing that. What is
   fair game: whether the query, the pool behaviour, and the connection path to Supabase are as cheap
   as that decision assumes.
10. **The dual-mode transport seam's cost has never been measured.** Proto-binary versus proto3-JSON
    on the same payloads: bytes on the wire and CPU per request. The architecture's central mechanism
    should have a number attached to it, and does not.
11. **`main.dart.js` and `main.dart.wasm` both ship.** Establish whether the dart2js fallback is
    reachable in the delivered configuration, and what it costs to carry if it is not.
12. **Native build wall time.** ADR/pom comments record a duplicated `quarkus-maven-plugin` execution
    that once cost ~4.5 minutes per build. Verify the fix holds and measure the current build, since
    it is paid on every deploy and every `task test:native`.

## 8. What a finding must contain

Report findings in a consistent shape. Anything missing a field is not ready to report.

```
### F<n> — <one-line claim, stated as the defect, not the fix>

**Class:** cost | latency | both
**Confidence:** measured | inferred-from-measurement | unverified
**Where:** <file:line, or the deployed resource>
**Evidence:** <the command you ran and the number it produced. Not a citation of a doc.>
**Cost today:** <unit — $/mo, container-seconds/day, ms, MB>
**Cost at 2K MAU:** <same units>
**Fix:** <the specific change>
**Invariant touched:** <one of §4, or "none">
**What the fix costs:** <what gets worse, or what guarantee is given up — "nothing" is a valid
answer only if you looked>
**How to verify the fix worked:** <the measurement that would prove it>
```

Rank by **(cost or latency removed) ÷ (invariant risk incurred)**. A 40MB saving that touches no
invariant outranks a 400ms saving that requires an edge in front of Cloud Run. State the ranking
rule you applied.

Separate the findings into three groups and label them:

- **Free wins** — no invariant touched, no architectural decision reopened.
- **Priced trade-offs** — an invariant is touched; the report presents the number and the human
  decides.
- **Closed** — things you investigated that turned out to be correct as built. Say so explicitly,
  with the number. A verified non-problem is a real result and keeps the next auditor from
  re-treading it; ADR-027's rejected options are the model.

## 9. Deliverables

1. **`docs/plans/PERFORMANCE-AUDIT.md`** — the working document. Follow the shape of
   `docs/plans/implemented/DATA-API-EXPOSURE.md`: a header stating it is a working document and not
   a source of truth, the date, the scope, and **the method** — including what you measured, what
   you inferred, and what you could not reach. Then the findings per §8.
2. **No ADR unless a decision is actually taken.** `DECISIONS.md` is an append-only archive of
   accepted decisions, and an audit does not accept anything on its own. If the audit's conclusion
   *is* a decision the owner then takes, it is recorded with the `add-adr` skill, in the repository's
   exact ADR format, and never by editing an existing entry.
3. **Do not change code.** This audit produces a document and measurements. If a fix is trivial and
   obviously free, say so in the finding and let the owner decide — do not land it.
4. **Anything you did to the local environment, undo.** `task stop:supabase`, `task clean`, remove
   containers you started.

## 10. What would make this audit worthless

State these back to yourself before you begin:

- Restating `BLUEPRINT.md` / `STANDARDS.md` / an ADR as though it were a discovery.
- Reporting a number you did not produce, or presenting an estimate in the same table as a
  measurement without labelling it.
- Recommending Redis, Kubernetes, a CDN, an API gateway, a second orchestrator, or an edge, without
  engaging with the ADR that already rejected or deferred it and the price it named.
- Optimising throughput under load that does not exist, while ignoring the fixed cost of a bundle
  every visitor pulls and a boot every visitor waits for.
- Touching production with anything other than a read.
- A long report. Rank hard, cut everything that does not carry a number, and put the largest cost
  first. Ten findings with arithmetic beat forty with adjectives.
