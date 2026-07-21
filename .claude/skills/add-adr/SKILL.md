---
name: add-adr
description: Record an architectural decision in docs/architecture/DECISIONS.md using jZen's exact ADR format. Use when a decision changes or supersedes something in an earlier architecture doc (MANIFESTO/BLUEPRINT/STANDARDS/ROADMAP or a prior ADR), or the user asks to log/document a decision.
---

# Adding a jZen ADR

`docs/architecture/DECISIONS.md` is the running log of architectural decisions and, crucially, where
they **change earlier docs and why**. The architecture docs (`MANIFESTO`, `BLUEPRINT`, `STANDARDS`,
`ROADMAP`) describe intent; when the product drifts from them, the drift is recorded here with
justification — **newest ADRs win on conflict**. Any non-trivial decision that contradicts or refines
an earlier doc needs an entry.

## Format (match the existing entries exactly)

Entries are **newest first** — insert directly under the intro, above `ADR-<highest>`. Number
sequentially (check the current highest `ADR-NNN`). Use this shape:

```markdown
## ADR-0NN — <short imperative title>

**Date:** YYYY-MM-DD. **Status:** accepted | deferred | proposed.

### Decision

<What was decided, concretely. Bullet the moving parts.>

### What this supersedes, and why

- **"<the exact earlier wording/decision>"** (<which doc/ADR + section>) → **reversed | changed |
  refined | reframed.** *Why:* <the justification — this is the load-bearing part>.

### Consequence

<What now holds as a result — invariants, versioning impact, what was verified green.>
```

Notes on fidelity to the house style:
- A short entry may collapse to **Decision** / **Supersedes** / **Why** inline (see ADR-002/003) —
  match the weight of the decision.
- Cite the **exact prior wording** you're superseding and name the doc + section, as existing ADRs do.
- Convert relative dates to absolute (`YYYY-MM-DD`).
- Prefer stating what was **verified** (tests green, builds pass) in the Consequence.

## After writing

If the decision changes wording elsewhere, the ADR is authoritative — but update the affected doc's
prose too when practical (existing ADRs note "MANIFESTO/BLUEPRINT wording updated to match"). Do not
delete the superseded text from history; the ADR *is* the record of the change.
