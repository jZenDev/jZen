#!/usr/bin/env python3
"""Fail if a README names a non-existent task, or a module LICENSE drifted. `task verify:docs`.

WHAT this checks and why is the Taskfile's `verify:docs` summary (`task verify:docs --summary`),
which stays there as the operator-facing contract. This covers HOW.

**Why Python** (STANDARDS "Scripting", ADR-032): both checks parse text and return a verdict —
Rule 3. The sh version had to build its inline-code delimiter as `bt=$(printf '\140')`, because a
literal backtick reaches the task interpreter as command substitution before `grep` ever sees the
pattern. A gate whose central pattern cannot be *written down* is the clearest case the rule has.

**What this fixes.** The sh version already refused to pass vacuously on one thing — an unreadable
`task --list` was an error, not an empty set of valid names. That guard is kept and its reasoning
extended to the two places it was missing: `git ls-files '*README.md'` and `git ls-files
'*/LICENSE'` each fed a `for` loop that simply did not run when the pattern matched nothing, and
both then printed their success line. "All README task references resolve" is a true statement
about zero READMEs, which is exactly the shape of a gate that has quietly stopped looking.

Output is byte-identical to the sh implementation it replaces, deliberately: this is a port, and a
port that also restyles its output cannot be diffed against the thing it replaced.

Written to the 3.9 floor, stdlib only.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib  # noqa: E402  (sibling module; sys.path is set immediately above)

ANSI = re.compile(r"\x1b\[[0-9;]*m")
# `task --list` prints "* name:   description".
TASK_LINE = re.compile(r"^\* ([a-z0-9:_-]+):")

# Two ways a README names a command, and only these two — a bare "task" in prose is not a claim
# about a task existing. The character class admits spaces and hyphens so that a full command line
# is captured; the tokens are split out afterwards, and a leading `-` marks a flag, not a task.
INLINE_REF = re.compile(r"`task +([a-z][a-z0-9:_ -]*)`")
FENCE_REF = re.compile(r"^ *task +([a-z][a-z0-9:_ -]*)", re.MULTILINE)


class StaleScope(Exception):
    """A scan pattern matched nothing — the gate cannot vouch for what it never read."""


@dataclass(frozen=True)
class Problem:
    text: str


def _git(root: Path, *args: str) -> "list[str]":
    out = subprocess.run(
        ["git", *args], cwd=str(root), capture_output=True, text=True, check=False
    )
    if out.returncode != 0:
        raise StaleScope(f"git {' '.join(args)} failed: {out.stderr.strip()}")
    return [line for line in out.stdout.splitlines() if line]


def is_git_repo(root: Path) -> bool:
    out = subprocess.run(
        ["git", "rev-parse", "--git-dir"], cwd=str(root), capture_output=True, text=True
    )
    return out.returncode == 0


def task_names(root: Path) -> "set[str]":
    """The tasks `task --list` reports.

    NO_COLOR *and* an ANSI strip: `task` colourises when it believes it has a terminal, and a
    colourised line would not parse. Depending on TTY detection would make this gate pass or fail
    by accident.
    """
    import os

    env = dict(os.environ, NO_COLOR="1")
    out = subprocess.run(
        ["task", "--list"], cwd=str(root), capture_output=True, text=True, env=env, check=False
    )
    names = set()
    for line in ANSI.sub("", out.stdout).splitlines():
        m = TASK_LINE.match(line)
        if m:
            names.add(m.group(1))
    return names


def readme_refs(root: Path) -> "list[tuple[str, str]]":
    """Every (readme, task-name) a README claims exists."""
    readmes = [f for f in _git(root, "ls-files", "*README.md")]
    if not readmes:
        raise StaleScope("git ls-files '*README.md' matched nothing")
    refs: "list[tuple[str, str]]" = []
    for rel in readmes:
        text = (root / rel).read_text(encoding="utf-8", errors="replace")
        for pattern in (INLINE_REF, FENCE_REF):
            for m in pattern.finditer(text):
                for token in m.group(1).split():
                    if not token.startswith("-"):
                        refs.append((rel, token))
    return refs


def check_task_refs(root: Path, valid: "set[str]") -> "list[Problem]":
    return [
        Problem(f"  MISSING: '{md}' references 'task {name}', not in 'task --list'")
        for md, name in readme_refs(root)
        if name not in valid
    ]


def check_licenses(root: Path) -> "tuple[list[Problem], int]":
    """Every module LICENSE must be byte-identical to the root one.

    A licence that differs from the one it claims to be is a legal defect, and the copies exist
    because each published module carries its own.
    """
    copies = _git(root, "ls-files", "*/LICENSE")
    if not copies:
        raise StaleScope("git ls-files '*/LICENSE' matched nothing")
    root_bytes = (root / "LICENSE").read_bytes()
    problems, count = [], 0
    for rel in copies:
        if (root / rel).read_bytes() == root_bytes:
            count += 1
        else:
            problems.append(Problem(f"  DRIFTED: '{rel}' differs from the root LICENSE"))
    return problems, count


def main(root: "Path | None" = None, valid: "set[str] | None" = None) -> int:
    root = root or lib.repo_root()
    if not is_git_repo(root):
        print("Not a git repository, cannot verify docs.")
        return 1

    if valid is None:
        valid = task_names(root)
    if not valid:
        print("Could not read the task list; refusing to pass vacuously.")
        return 1

    failed = False

    print("Checking task references in READMEs...")
    try:
        problems = check_task_refs(root, valid)
    except StaleScope as e:
        print(f"  NO READMES: {e} — refusing to pass vacuously.")
        failed = True
    else:
        for p in problems:
            print(p.text)
        if problems:
            failed = True
        else:
            print("  All README task references resolve.")

    print("Checking LICENSE copies...")
    try:
        problems, count = check_licenses(root)
    except StaleScope as e:
        print(f"  NO LICENSES: {e} — refusing to pass vacuously.")
        failed = True
    else:
        for p in problems:
            print(p.text)
        if problems:
            failed = True
        else:
            print(f"  All {count} module LICENSE copies are byte-identical to root.")

    if failed:
        print("Docs verification FAILED.")
        return 1
    print("Docs verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
