# 🧘 Zen Architecture

Zen Architecture is the design philosophy jZen is built on. It is not unique to this codebase —
the same philosophy underlies other Zen-family projects — and this document states it on its own
terms, independent of any one stack. **How jZen specifically applies it** — the protobuf contract,
the dual-mode transport, PostgreSQL and Supabase named directly, and the rest of the concrete
choices — is [`docs/architecture/MANIFESTO.md`](architecture/MANIFESTO.md); this document is the
philosophy that MANIFESTO is an instance of.

It is not a framework, not a pattern catalog, and not a layered model. Zen Architecture is a set
of **constraints, defaults, and decisions** that shape how a system is built and how it evolves.

The goal is simple: **reduce cognitive load while staying honest about the real system you are
building.**

## What Zen Architecture is not

Zen Architecture explicitly rejects:

- Clean Architecture
- Hexagonal / Onion / Ports & Adapters
- Domain-Driven Design layers
- Artificial separation into "domain", "contract", and "infrastructure"
- Abstractions created "just in case"

These approaches are powerful in enterprise environments, but they add ceremony, indirection, and
vocabulary that Zen Architecture deliberately avoids. It optimizes for **clarity, speed, and
product reality**, not architectural purity.

## Core principles

### 1. Product-first, not architecture-first

Zen Architecture starts with the product, not with diagrams. Packages represent **product
capabilities**, not architectural layers. If something exists because the product needs it, it
belongs in the system. If something exists only to satisfy an architectural idea, it does not.

### 2. See with your eyes (zero *custom* magic)

Zen Architecture avoids hidden behavior:

- No code generation whose output a developer cannot read
- No implicit wiring
- No runtime magic

What the system does should be visible by reading the code — or, where generation is used, by
reading its generated output, which is committed and readable rather than synthesized invisibly
at runtime. If something happens, you should be able to find it. Predictability is valued over
cleverness.

### 3. Real dependencies are first-class

Zen Architecture does not pretend that external systems are optional. Whatever a product actually
depends on — a database, an identity provider, a cloud platform — is treated as a real, stable,
**named** dependency, not smuggled behind a portability layer that no second implementation will
ever justify. A wrapper around a single implementation is not an abstraction; it is a passthrough
with a plausible name, and it costs a reader one extra indirection every time they follow the
code, forever, in exchange for a flexibility nobody has asked for.

This is not a limitation. It is a deliberate trade-off for simplicity, performance, and developer
experience — and it comes with an obligation: once a dependency is named, its constraints are the
product's constraints, and they belong in a place they can be enforced, not hidden behind a
wrapper where they will surface as a bug.

### 4. No artificial purity

There is no concept of a "pure domain" in Zen Architecture. Business logic, persistence logic, and
integration logic may live close to each other **when that reflects reality**. The goal is not
purity. The goal is **coherence**.

### 5. Utilities over abstractions

Zen Architecture favors small utility packages, explicit helpers, and boring, readable APIs over
deep inheritance trees, generic interfaces, and swap-ready abstractions. If a dependency is not
meant to be swapped, it should not pretend to be.

### 6. Environment is explicit

Zen Architecture embraces environment differences instead of hiding them. Development should run
against the real shape of production — local, cheap, and safe — rather than a "mock world" that
behaves unlike it. Configuration is driven by explicit settings, not implicit detection.

## Packages as capabilities

In Zen Architecture, a package answers one question: **"What capability does this give to the
product?"** Identity, transport, jobs, telemetry — these are things a product *does*. Packages are
not layers, tiers, or technical boundaries; they are **capabilities with clear responsibility**.

## Client and server are one system

Zen Architecture does not treat client and server as separate worlds. They are developed together,
versioned together, and reasoned about together. Consistency between client and server matters
more than theoretical separation — which is why a Zen Architecture system typically has *one*
mechanism, stated once, that keeps them honest with each other, rather than a contract maintained
by convention on both sides.

## Why "Zen"

Zen Architecture is about removing noise: fewer concepts, fewer files, fewer indirections, fewer
decisions per line of code. This creates space for what matters — product logic, user experience,
reliability, long-term maintainability.

Zen is not minimalism for its own sake. Zen is **clarity through deliberate constraint**.

## Summary

Zen Architecture is:

- Product-driven
- Explicit about its real dependencies
- Free of custom magic
- Boring in the right places
- Optimized for human understanding

If a design decision increases confusion, it is not Zen. If it makes the system easier to reason
about, it probably is.
