#!/usr/bin/env python3
"""Fail if a versioned Flyway migration that already exists on the base branch has changed.
Run by `task verify:migrations`.

WHY. Flyway stores a CRC32 of each applied `V*` file's text and refuses to start when the file on
disk no longer matches. The checksum covers comments and whitespace, so a reworded comment in an
applied migration stops every consumer database that applied the old text (ADR-071). The schema
did not change, yet the deploy does. An applied migration is append-only; a correction is a new
migration.

HOW. For each `V<n>__*.sql` under a `db/migration` directory in the base ref (default
`origin/main`), the bytes in the working tree must equal the bytes in the base ref. A changed file
and a deleted file both fail. Added files are the point of the mechanism and pass. Repeatable
`R__*` migrations are exempt: Flyway re-applies them when they change, by design.

One edit is allowed: restoring text the file already had earlier in the base ref's history. That
is how a bad edit that reached the base branch is undone, and it can only return the file to text
that was once committed, never to a new one.

A gate that examined nothing must not pass, so an unresolvable base ref, or a base ref with no
versioned migration in it, is itself a failure.

Written to the 3.9 floor, stdlib only.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib  # noqa: E402  (sibling module; sys.path is set immediately above)

DEFAULT_BASE = "origin/main"
VERSIONED = re.compile(r"(^|/)db/migration/V[^/]*__[^/]*\.sql$")


def git(root: Path, *args: str) -> bytes:
    result = subprocess.run(["git", *args], cwd=root, capture_output=True)
    if result.returncode != 0:
        lib.die(f"git {' '.join(args)} failed: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def base_migrations(root: Path, base: str) -> "list[str]":
    git(root, "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}")
    names = git(root, "ls-tree", "-r", "--name-only", base).decode().splitlines()
    return sorted(n for n in names if VERSIONED.search(n))


def history_blobs(root: Path, base: str, path: str) -> "set[str]":
    """Every blob id `path` has had in the base ref's history."""
    commits = git(root, "log", "--format=%H", base, "--", path).decode().split()
    blobs = set()
    for commit in commits:
        probe = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", f"{commit}:{path}"],
            cwd=root, capture_output=True,
        )
        if probe.returncode == 0:
            blobs.add(probe.stdout.decode().strip())
    return blobs


def changed(root: Path, base: str, reverted: "list[str]") -> "tuple[list[str], int]":
    """Return (violations, number of base migrations examined); `reverted` collects restored files."""
    paths = base_migrations(root, base)
    problems: "list[str]" = []
    for path in paths:
        current = root / path
        if not current.is_file():
            problems.append(f"{path}: deleted, but it exists on {base}")
        elif current.read_bytes() != git(root, "show", f"{base}:{path}"):
            blob = git(root, "hash-object", str(current)).decode().strip()
            if blob not in history_blobs(root, base, path):
                problems.append(f"{path}: text differs from every version on {base}")
            else:
                reverted.append(path)
    return problems, len(paths)


def main(argv: "list[str] | None" = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--base", default=DEFAULT_BASE, help=f"ref to compare against (default {DEFAULT_BASE})")
    parser.add_argument("--root", type=Path, default=lib.repo_root(), help="repository root")
    args = parser.parse_args(argv)

    reverted: "list[str]" = []
    problems, examined = changed(args.root, args.base, reverted)
    if examined == 0:
        lib.fail(f"no versioned migration found on {args.base}; the gate examined nothing")
        return 1
    if problems:
        lib.fail(
            "an applied migration was edited; revert it and put the change in a new migration",
            problems,
        )
        return 1
    for path in reverted:
        lib.warn(f"{path}: restored to earlier text from {args.base} history")
    lib.ok(f"{examined} versioned migrations unchanged against {args.base}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
