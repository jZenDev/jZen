#!/usr/bin/env python3
"""Check every Java dependency jZen ships against the OSV vulnerability database.

Reads `mvn dependency:list` output (Maven resolves, this understands the result — STANDARDS
"Orchestration"), asks https://api.osv.dev for each coordinate, and **exits non-zero when anything
is vulnerable or when the check could not be made**. That second half is the whole design.

WHY NOT A MAVEN PLUGIN, which is the obvious answer and was tried first.

  - `ossindex-maven-plugin` is the keyless option on paper. Sonatype's OSS Index now answers an
    anonymous request with `401 Unauthorized`, and the plugin logs `[WARNING] Failed to fetch
    component-reports` and **lets the build succeed**. Measured, not assumed: a full run over this
    repository's eight modules reported BUILD SUCCESS having checked nothing. A gate that goes
    green when it cannot see is worse than no gate, because it also removes the reason to look.
  - `dependency-check-maven` is the industry standard and does fail loudly. It needs an NVD API
    key: without one the database sync is throttled to the point of taking tens of minutes or
    erroring, and the usual remedy is a flag that makes it pass anyway. A key is a credential, it
    cannot be committed, and jZen's cost and secret discipline (ADR-027) is what rules it out
    rather than any doubt about the tool.
  - `osv-scanner` on `pom.xml` resolves transitively against Maven Central, so it cannot see the
    `zen:*` SNAPSHOT modules that are the point of this repository. It reports the resolution
    failure and **exits 0**, which is the ossindex failure again wearing different clothes.

So the resolution stays with Maven, which is the only thing that can do it correctly here, and
what remains is parsing a list and constructing a query — Rule 3 work, and therefore Python
(ADR-032). Stdlib only, 3.9 floor.

WHAT IT REFUSES TO DO. It never reports success on a network error, an HTTP error, a malformed
response, an empty dependency list, or a suppression it cannot read. Every one of those exits 1
with the reason, because each is a state in which the answer "no vulnerabilities" is not something
this script actually knows.

SUPPRESSIONS live in `audit-suppressions.txt` beside this file and each one **must carry a reason
on the same line** — the file will not parse otherwise, so an entry cannot be added silently the
way an empty XML suppression file invites. This mirrors how `CsrfRules` documents its exemptions.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

import lib

OSV_BATCH_URL = "https://api.osv.dev/v1/querybatch"
OSV_VULN_URL = "https://api.osv.dev/v1/vulns/"
OSV_ADVISORY_URL = "https://osv.dev/vulnerability/"

# How many coordinates go in one batch request. OSV accepts large batches; keeping them modest
# means a transient failure costs one slice rather than the whole run.
BATCH_SIZE = 100
TIMEOUT_SECONDS = 60

SUPPRESSIONS_FILE = Path(__file__).resolve().parent / "audit-suppressions.txt"

# A `mvn dependency:list` line, e.g.
#   [INFO]    io.quarkus:quarkus-rest:jar:3.32.2:compile -- module ... (auto)
# Classifier is optional, which is why the version is taken from the end of the coordinate rather
# than from a fixed field position: `g:a:jar:version:scope` and `g:a:jar:tests:version:scope` are
# both real, and counting from the left gets the second one wrong.
DEPENDENCY_LINE = re.compile(
    r"^\[INFO\]\s+(?P<group>[\w.\-]+):(?P<artifact>[\w.\-]+):(?P<rest>[\w.\-:]+?)"
    r":(?P<scope>compile|runtime|provided|test|system)\b"
)

# Scopes that reach a running server. `test` is excluded deliberately and the reason is worth
# stating: a vulnerable test library is a real finding about a developer's machine and a CI runner,
# but it is not shipped, and mixing the two makes the gate's verdict mean two different things at
# once. --include-test-scope asks the other question.
SHIPPED_SCOPES = {"compile", "runtime", "system"}


def parse_dependencies(text: str, include_test_scope: bool) -> "dict[str, set[str]]":
    """Coordinates -> versions, from `mvn dependency:list` output.

    A dict rather than a list because a multi-module reactor lists the same artifact once per
    module, and asking OSV about it eight times is eight times the traffic for one answer.
    """
    found: "dict[str, set[str]]" = {}
    for line in text.splitlines():
        match = DEPENDENCY_LINE.match(line)
        if not match:
            continue
        scope = match.group("scope")
        if scope not in SHIPPED_SCOPES and not include_test_scope:
            continue
        pieces = match.group("rest").split(":")
        if not pieces:
            continue
        version = pieces[-1]
        name = f"{match.group('group')}:{match.group('artifact')}"
        found.setdefault(name, set()).add(version)
    return found


def load_suppressions() -> "dict[str, str]":
    """Advisory id -> the reason it is accepted.

    Every non-comment line must read `<ID>  <reason>`. An id with no reason is a parse error and
    not a lenient default: the reason a suppression file rots is that adding to it is cheaper than
    justifying it, and this is the cheapest available way to make those two cost the same.
    """
    if not SUPPRESSIONS_FILE.exists():
        return {}
    suppressed: "dict[str, str]" = {}
    for number, raw in enumerate(SUPPRESSIONS_FILE.read_text().splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) != 2 or not parts[1].strip():
            lib.die(
                f"{SUPPRESSIONS_FILE.name}:{number}: '{line}' has no reason. A suppression"
                " without a stated reason is indistinguishable from one nobody remembers"
                " making. Write: <ADVISORY-ID>  why this one is accepted here."
            )
        suppressed[parts[0]] = parts[1].strip()
    return suppressed


def post_json(url: str, payload: dict) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode())


def get_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode())


def query_osv(coordinates: "list[tuple[str, str]]") -> "dict[tuple[str, str], list[str]]":
    """(name, version) -> advisory ids. Raises rather than returning empty on any failure."""
    hits: "dict[tuple[str, str], list[str]]" = {}
    for start in range(0, len(coordinates), BATCH_SIZE):
        chunk = coordinates[start : start + BATCH_SIZE]
        payload = {
            "queries": [
                {"package": {"ecosystem": "Maven", "name": name}, "version": version}
                for name, version in chunk
            ]
        }
        body = post_json(OSV_BATCH_URL, payload)
        results = body.get("results")
        if not isinstance(results, list) or len(results) != len(chunk):
            raise ValueError(
                f"OSV returned {len(results) if isinstance(results, list) else 'no'} results for"
                f" {len(chunk)} queries. The response cannot be lined up with what was asked, so"
                " no verdict is available."
            )
        for coordinate, result in zip(chunk, results):
            ids = [v["id"] for v in result.get("vulns", []) if "id" in v]
            if ids:
                hits[coordinate] = ids
    return hits


def describe(advisory_id: str) -> "tuple[str, str]":
    """(severity, summary) for an advisory, best effort.

    Deliberately the one place a failure is swallowed, and only because it cannot change the
    answer: this runs after a hit has already been decided, purely to make the output readable. A
    detail lookup that times out must not turn a real finding into a crash — the finding is still
    printed, with "(details unavailable)" where the prose would be.
    """
    try:
        detail = get_json(OSV_VULN_URL + advisory_id)
    except Exception:  # noqa: BLE001 - display only; the verdict is already made
        return ("?", "(details unavailable)")
    raw = detail.get("database_specific", {}).get("severity")
    severity = raw.title() if isinstance(raw, str) and raw else "?"
    summary = detail.get("summary") or detail.get("details", "").split("\n")[0] or "(no summary)"
    return (severity, summary[:110])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "dependency_list",
        type=Path,
        help="a file holding `mvn dependency:list` output (use - for stdin)",
    )
    parser.add_argument(
        "--include-test-scope",
        action="store_true",
        help="also check test-scoped dependencies, which are not shipped",
    )
    args = parser.parse_args()

    text = (
        sys.stdin.read()
        if str(args.dependency_list) == "-"
        else args.dependency_list.read_text()
    )

    dependencies = parse_dependencies(text, args.include_test_scope)
    if not dependencies:
        lib.die(
            "No dependencies were parsed from the Maven output. That is a broken gate, not a"
            " clean result — `mvn dependency:list` either failed or changed its format. Nothing"
            " was checked, so nothing can be reported as safe."
        )

    coordinates = sorted(
        (name, version) for name, versions in dependencies.items() for version in versions
    )
    lib.info(f"Checking {len(coordinates)} Java dependencies against OSV")

    suppressions = load_suppressions()

    try:
        hits = query_osv(coordinates)
    except (urllib.error.URLError, urllib.error.HTTPError, ValueError, json.JSONDecodeError) as e:
        lib.die(
            f"Could not reach the OSV database: {e}\n"
            "   The gate fails rather than passing, because 'we did not look' and 'we looked and"
            " it was clean' are not the same answer and must never produce the same exit code."
        )

    reported = 0
    accepted = 0
    for (name, version), advisory_ids in sorted(hits.items()):
        live = [i for i in advisory_ids if i not in suppressions]
        for advisory_id in advisory_ids:
            if advisory_id in suppressions:
                accepted += 1
                lib.warn(f"accepted  {name}@{version}  {advisory_id} — {suppressions[advisory_id]}")
        if not live:
            continue
        reported += 1
        for advisory_id in live:
            severity, summary = describe(advisory_id)
            lib.fail(
                f"{name}@{version}  {advisory_id} [{severity}]",
                [summary, OSV_ADVISORY_URL + advisory_id],
            )

    print()
    if reported:
        lib.die(
            f"{reported} vulnerable dependenc{'y' if reported == 1 else 'ies'}. Upgrade the"
            f" dependency, or record an accepted risk with its reason in"
            f" {SUPPRESSIONS_FILE.name}."
        )

    clean = len(coordinates)
    note = f" ({accepted} accepted by {SUPPRESSIONS_FILE.name})" if accepted else ""
    lib.ok(f"{clean} Java dependencies checked, no known vulnerabilities{note}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
