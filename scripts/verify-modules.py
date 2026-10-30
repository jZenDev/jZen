#!/usr/bin/env python3
"""Fail if a jZen backend module holds the Jandex or no-Jackson rule by comment only.

WHAT this enforces and WHY it is a gate is in the Taskfile's `verify:modules` summary, the
operator-facing contract (`task verify:modules --summary`). This docstring covers HOW.

STANDARDS "Backend multi-module rules" states two mandatory properties for every `server/zen-*`
module: a module that contributes CDI beans or JAX-RS providers must run `jandex-maven-plugin`
(silent failure otherwise — Quarkus cannot see the providers in a dependency jar with no index),
and no `pom.xml` may declare server-side `quarkus-rest-jackson` (it greedily claims
`application/json` and serializes proto builder internals). Until this script, both rules were
enforced by five javadoc comments and one line in STANDARDS — nothing failed a build if either
one drifted. The 2026-08-13 architectural security review's F9 names this the same shape as
`verify:boundaries`: a missing declaration produces no error and no signal.

**Rule 3 work** (STANDARDS "Scripting"): this has to *understand* a `pom.xml` (is
`jandex-maven-plugin` a real `<plugin>`, is `quarkus-rest-jackson` a real `<dependency>`, as
opposed to either name appearing in a comment or as a substring of `quarkus-rest-client-jackson`)
and Java source (does a class carry a bean/provider annotation). `pom.xml` is parsed with
`xml.etree.ElementTree`, which is comment-blind by construction — an XML parser does not need a
bespoke comment stripper the way the Dart/TypeScript line-scanners in `verify-boundaries.py` do,
because a well-formed `<!-- ... -->` block was never a `<dependency>` element to begin with.

**The stale-scope guard** (STANDARDS "no gate composes a task that can pass having checked
nothing", ADR-034 invariant 8; the `verify-boundaries.py` header explains the general defect).
`MODULE_GLOB` matching no directory, or the Jackson scan matching no `pom.xml` at all, is reported
as a failure — "examined nothing" must never look like "found nothing wrong".

**Trust boundary for the XML.** The `pom.xml` files read here are whatever the checkout holds, and
CI runs this gate on a branch before anyone has reviewed it, so a contributed POM is untrusted
input. `ElementTree` does not fetch external entities, but before expat 2.4.1 (the one bundled with
Python builds older than 3.11 can be older still) a document that declares nested internal entities
expands them without a limit, so a few hundred bytes can exhaust memory. A Maven POM never needs a
DTD, so `_parse_pom` refuses any document that declares one, before any entity is defined, on every
supported Python. A POM that is not well-formed, or declares a DTD, is a failure of the scan, not
a pom with nothing to report.

**Python 3.11 or newer, unlike the other scripts** (ADR-069). The rest of `scripts/` is written to a
3.9 floor so it runs on a Mac with only Xcode's Command Line Tools; this one reads files a
contributor controls and hands them to an XML parser, and the parser that ships with 3.10 and older
is the one with the known entity-expansion and external-entity weaknesses. `_parse_pom`'s DOCTYPE
refusal already closes that hole on every version, so the floor is a second layer, not the only
one. A runtime below it is a failure that says why and how to fix it, never a pass.

Stdlib only.
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from xml.parsers import expat

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib  # noqa: E402  (sibling module; sys.path is set immediately above)

# Every jZen backend library module. `server/zen-proto` and `server/zen-core` legitimately have
# no beans and no jandex-maven-plugin (the census in the security review confirms both are 0/0),
# so the check below is "beans imply jandex", never "every module needs jandex".
MODULE_GLOB = "server/zen-*"

# Every pom.xml in the repository is in scope for the Jackson prohibition — an application
# server (apps/*/*_server) could reintroduce it just as easily as a library could.
POM_GLOB = "**/pom.xml"
POM_EXCLUDE_DIR = "/target/"

# The annotations that mark a class Quarkus must discover via Jandex when the class ships inside
# a dependency jar: JAX-RS providers and CDI bean-defining annotations. Mirrors the grep the
# security review ran by hand (SECURITY-ARCHITECTURE-REVIEW.md F9).
BEAN_ANNOTATION = re.compile(r"@(Provider|ApplicationScoped|Singleton|Observes)\b")
JAVA_LINE_COMMENT = re.compile(r"^\s*//")

JANDEX_ARTIFACT = "jandex-maven-plugin"
FORBIDDEN_JACKSON_ARTIFACT = "quarkus-rest-jackson"

# The oldest interpreter this gate runs on (ADR-069). Checked in `main`, not at import, so the
# fixture tests can still load the module on the repository's 3.9 floor and exercise the parts that
# matter there, the DOCTYPE refusal first among them.
MIN_PYTHON = (3, 11)

# Maven's POM namespace. ElementTree requires the namespace prefix on every tag when the
# document declares a default xmlns, which every jZen pom.xml does.
POM_NS = "http://maven.apache.org/POM/4.0.0"


class StaleScope(Exception):
    """A scan pattern matched nothing — the gate cannot vouch for a tree it never read."""


class UnreadablePom(Exception):
    """A pom.xml could not be read safely, so the gate cannot say what it declares."""


@dataclass(frozen=True)
class Hit:
    path: str
    detail: str

    def __str__(self) -> str:
        return f"{self.path}: {self.detail}"


def runtime_problem() -> "str | None":
    """Why this interpreter may not run the gate, or None if it may."""
    if sys.version_info[:2] >= MIN_PYTHON:
        return None
    want = ".".join(str(n) for n in MIN_PYTHON)
    have = ".".join(str(n) for n in sys.version_info[:3])
    return (f"verify-modules.py needs Python {want} or newer and this is {have}. The XML parser in "
            f"older versions expands entities without a limit (ADR-069). Install a newer python3 "
            f"(brew install python) and put it first on PATH.")


def _modules(root: Path) -> "list[Path]":
    """Every `server/zen-*` module directory. Raises StaleScope if none match."""
    dirs = sorted(d for d in root.glob(MODULE_GLOB) if d.is_dir())
    if not dirs:
        raise StaleScope(f"scope '{MODULE_GLOB}' matched no directory under {root}")
    return dirs


def _poms(root: Path) -> "list[Path]":
    """Every pom.xml in the repository, excluding build output. Raises StaleScope if none."""
    poms = sorted(
        p for p in root.glob(POM_GLOB) if p.is_file() and POM_EXCLUDE_DIR not in p.as_posix()
    )
    if not poms:
        raise StaleScope(f"pattern '{POM_GLOB}' matched no pom.xml under {root}")
    return poms


def _parse_pom(pom: Path) -> ET.Element:
    """The root element of `pom`, refusing a document that declares a DTD (see the module docstring).

    The DOCTYPE handler fires as soon as the declaration starts, before any entity in it is
    defined, so nothing is ever expanded. The same pass rejects a document that is not well-formed,
    which `ET.parse` would otherwise surface as a traceback instead of a reported failure.
    """
    try:
        data = pom.read_bytes()
    except OSError as e:
        raise UnreadablePom(f"{pom}: could not be read ({e.__class__.__name__}: {e})") from e

    def refuse_dtd(*_args: object) -> None:
        raise UnreadablePom(
            f"{pom}: declares a DOCTYPE; a Maven POM needs no DTD, and entity declarations are "
            "how a small document is made to expand without limit"
        )

    guard = expat.ParserCreate()
    guard.StartDoctypeDeclHandler = refuse_dtd
    try:
        guard.Parse(data, True)
        return ET.fromstring(data)
    except (expat.ExpatError, ET.ParseError) as e:
        raise UnreadablePom(f"{pom}: is not well-formed XML ({e})") from e


def _local(tag: str) -> str:
    """Strip the `{namespace}` prefix ElementTree puts on every tag."""
    return tag.rsplit("}", 1)[-1]


def _artifact_ids(pom: Path, container_tag: str) -> "set[str]":
    """Every `<artifactId>` text found under `container_tag` elements (`dependency`/`plugin`).

    Comments are never seen: `ElementTree` drops them by default, which is the whole reason this is
    Python-with-ElementTree rather than a `grep` for the artifact name — a name mentioned only in
    an XML comment (the kind this repository already has, explaining *why* a plugin is present)
    must not count as the plugin being declared, or as the forbidden dependency being present.
    """
    ids: "set[str]" = set()
    for el in _parse_pom(pom).iter():
        if _local(el.tag) != container_tag:
            continue
        for child in el:
            if _local(child.tag) == "artifactId" and child.text:
                ids.add(child.text.strip())
    return ids


def has_jandex_plugin(pom: Path) -> bool:
    return JANDEX_ARTIFACT in _artifact_ids(pom, "plugin")


def declares_forbidden_jackson(pom: Path) -> bool:
    # Exact match only: quarkus-rest-client-jackson (zen-identity's outbound Supabase client)
    # and its transitive quarkus-rest-jackson-common are legitimate and must not be flagged.
    return FORBIDDEN_JACKSON_ARTIFACT in _artifact_ids(pom, "dependency")


def has_bean_annotation(module: Path) -> bool:
    """True if any non-comment line under `module/src/main/java` carries a bean/provider annotation."""
    src = module / "src" / "main" / "java"
    if not src.is_dir():
        return False
    for java_file in src.rglob("*.java"):
        for line in java_file.read_text(encoding="utf-8", errors="replace").splitlines():
            if JAVA_LINE_COMMENT.match(line):
                continue
            if BEAN_ANNOTATION.search(line):
                return True
    return False


def check_jandex(root: Path) -> "list[Hit]":
    """A. A module with bean/provider classes must run jandex-maven-plugin."""
    hits: "list[Hit]" = []
    for module in _modules(root):
        pom = module / "pom.xml"
        if not pom.is_file():
            hits.append(Hit(str(module.relative_to(root)), "module has no pom.xml"))
            continue
        if has_bean_annotation(module) and not has_jandex_plugin(pom):
            hits.append(Hit(
                str(module.relative_to(root)),
                "contributes a CDI/JAX-RS bean but pom.xml has no jandex-maven-plugin — "
                "its providers would be silently invisible to an app that depends on this jar",
            ))
    return hits


def check_no_server_jackson(root: Path) -> "list[Hit]":
    """B. No pom.xml declares server-side quarkus-rest-jackson."""
    hits: "list[Hit]" = []
    for pom in _poms(root):
        if declares_forbidden_jackson(pom):
            hits.append(Hit(
                str(pom.relative_to(root)),
                "declares quarkus-rest-jackson — this claims application/json ahead of "
                "ProtoJsonMessageBodyWriter and serializes proto builder internals (500s)",
            ))
    return hits


CHECKS = (
    (check_jandex,
     "a module contributes beans/providers without jandex-maven-plugin:",
     "every server/zen-* module with beans or providers runs jandex-maven-plugin"),
    (check_no_server_jackson,
     "a pom.xml declares the forbidden server-side quarkus-rest-jackson:",
     "no pom.xml declares server-side quarkus-rest-jackson"),
)


def main(root: "Path | None" = None) -> int:
    print("Checking the Jandex and no-Jackson module rules...")
    problem = runtime_problem()
    if problem:
        lib.fail("this interpreter is too old to vouch for the poms:", [problem])
        return 1
    root = root or lib.repo_root()

    failed = False
    for check, bad, good in CHECKS:
        try:
            hits = check(root)
        except StaleScope as e:
            # Not "no violations found" — "nothing was examined".
            lib.fail(f"the scan is stale and checked nothing: {e}")
            failed = True
            continue
        except UnreadablePom as e:
            lib.fail(f"a pom.xml could not be read safely, so this check vouches for nothing: {e}")
            failed = True
            continue
        if hits:
            lib.fail(bad, [str(h) for h in hits])
            failed = True
        else:
            lib.ok(good)

    print()
    if not failed:
        print("Module rules intact: Jandex is wired wherever it must be, and no module has")
        print("reintroduced server-side Jackson. See STANDARDS 'Backend multi-module rules'.")
        return 0
    print("A module rule that STANDARDS states as mandatory is not actually enforced by the")
    print("build. See STANDARDS 'Backend multi-module rules'.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
