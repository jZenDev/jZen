#!/usr/bin/env python3
"""Check every hosted Dart/Flutter dependency jZen ships against the OSV vulnerability database.

Reads one or more `pubspec.lock` files (pub resolves, this understands the result — STANDARDS
"Orchestration", the same split `audit-maven.py` uses for Maven), asks https://api.osv.dev about
every `hosted` package with ecosystem `Pub`, and **exits non-zero when anything is vulnerable or
when the check could not be made**. That second half is the whole design, carried over unchanged
from `audit-maven.py` — "we did not look" and "we looked and it was clean" must never share an
exit code.

WHY THIS SCRIPT AND NOT A TOOL. `osv-scanner` cannot run against `pubspec.lock` directly against
this repository the way it can against `pom.xml`: as of this writing it does not resolve a pub
workspace, and jZen has no interest in shelling out to a binary that has to be installed
separately when OSV's own batch API is one stdlib HTTP call away and `audit-maven.py` already
proved the pattern. Two workspace lockfiles (`client/pubspec.lock`, `apps/pubspec.lock`) cover
every package in every member, because pub resolves one lockfile per workspace, not one per
package — reading each member's own `pubspec.yaml` would only re-derive what the lockfile already
settled.

WHAT IT SKIPS, deliberately: `sdk` and `git`/`path` sourced entries. An `sdk` entry (e.g. `flutter`,
`flutter_test`) is not a pub.dev package with its own advisory history; a `git`/`path` entry has no
resolvable version OSV's Pub ecosystem can be asked about. Both are absent from the shipped
dependency surface this gate is checking, not silently waved through — `parse_lockfile` never
extracts them in the first place.

SUPPRESSIONS live in `audit-client-suppressions.txt` beside this file, same format and same
same-line-reason requirement as `audit-maven.py`'s — a separate file because "accepted for the
Java surface" and "accepted for the Dart surface" are different claims about different code.

Written to the 3.9 floor (STANDARDS "Scripting"), stdlib only.
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

SUPPRESSIONS_FILE = Path(__file__).resolve().parent / "audit-client-suppressions.txt"

# A top-level package entry in `pubspec.lock`, e.g. `  http:` at exactly two spaces of indent.
# Anything more deeply indented (`    version: "1.2.3"`) belongs to the package above it.
PACKAGE_HEADER = re.compile(r"^  (?P<name>\S+):\s*$")
SOURCE_LINE = re.compile(r'^\s+source:\s*"?(?P<source>[\w.-]+)"?\s*$')
VERSION_LINE = re.compile(r'^\s+version:\s*"?(?P<version>[^"\s]+)"?\s*$')


def parse_lockfile(text: str) -> "dict[str, set[str]]":
    """Package name -> versions, from one `pubspec.lock`'s `hosted` entries.

    A dict rather than a list for the same reason as `audit-maven.py`'s `parse_dependencies`: the
    same package can be pinned to the same version by more than one lockfile passed on the command
    line, and asking OSV about it twice is twice the traffic for one answer.
    """
    found: "dict[str, set[str]]" = {}
    name: "str | None" = None
    source: "str | None" = None
    version: "str | None" = None

    def flush() -> None:
        if name and source == "hosted" and version:
            found.setdefault(name, set()).add(version)

    for raw in text.splitlines():
        header = PACKAGE_HEADER.match(raw)
        if header:
            flush()
            name, source, version = header.group("name"), None, None
            continue
        if name is None:
            continue
        source_match = SOURCE_LINE.match(raw)
        if source_match:
            source = source_match.group("source")
            continue
        version_match = VERSION_LINE.match(raw)
        if version_match:
            version = version_match.group("version")
    flush()
    return found


def load_suppressions() -> "dict[str, str]":
    """Advisory id -> the reason it is accepted. Mirrors `audit-maven.py`'s of the same name."""
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
                {"package": {"ecosystem": "Pub", "name": name}, "version": version}
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
    """(severity, summary) for an advisory, best effort. See `audit-maven.py`'s twin."""
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
        "pubspec_locks",
        nargs="+",
        type=Path,
        help="one or more pubspec.lock files (one per pub workspace)",
    )
    args = parser.parse_args()

    dependencies: "dict[str, set[str]]" = {}
    for path in args.pubspec_locks:
        for name, versions in parse_lockfile(path.read_text()).items():
            dependencies.setdefault(name, set()).update(versions)

    if not dependencies:
        lib.die(
            "No hosted packages were parsed from the given pubspec.lock file(s). That is a"
            " broken gate, not a clean result — the lockfile either does not exist, is empty, or"
            " changed format. Nothing was checked, so nothing can be reported as safe."
        )

    coordinates = sorted(
        (name, version) for name, versions in dependencies.items() for version in versions
    )
    lib.info(f"Checking {len(coordinates)} Dart/Flutter dependencies against OSV")

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
    lib.ok(f"{clean} Dart/Flutter dependencies checked, no known vulnerabilities{note}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
