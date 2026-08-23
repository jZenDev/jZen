#!/usr/bin/env python3
"""Refuse to end a turn that changed source without running anything.

The audit that produced these hooks found the same shape over and over: a
change reported as done, and the user discovering it was not. The project's
own `verify` skill says to run the suite before reporting done, and it loaded
four times in fifty-six sessions -- because remembering to verify is exactly
the kind of rule that loses to a long task.

So this runs as a `Stop` hook. It reads the session transcript, finds the last
edit to a source file and the last test command, and if the edit came after the
test it exits 2, which blocks the stop and hands the reason back.

It is deliberately hard to annoy:

  * only source files count -- docs, .claude/, and anything in `exempt` do not;
  * `stop_hook_active` short-circuits it, so it can never loop;
  * once a test has run after the last edit, it is silent for the rest of the
    session unless source changes again.

Rules live in .claude/hooks/verify-rules.json; see DEFAULTS.
"""

from __future__ import annotations

import fnmatch
import json
import os
import re
import sys

DEFAULTS = {
    # Editing one of these means the session owes a test run.
    "source": ["*.java", "*.dart", "*.ts", "*.tsx", "*.sql", "*.proto",
               "*.qute.html", "*.css", "*.py"],
    # ...unless it also matches one of these.
    "exempt": [".claude/*", "docs/*", "*.md", "target/*", "*/node_modules/*",
               "build/*", "*/generated/*", "*.generated.ts"],
    # Any of these having run counts as verification.
    "tests": [r"\bmvnw\b[^|;&]*\b(test|verify)\b", r"\btask\s+test\b",
              r"\bdart\s+test\b", r"\bflutter\s+test\b", r"\bpnpm\s+test\b",
              r"\bnpm\s+test\b", r"\bpytest\b", r"\btask\s+verify\b"],
    "message": "Run the test suite before ending the turn.",
}


def load_rules(root: str) -> dict:
    rules = dict(DEFAULTS)
    path = os.path.join(root, ".claude", "hooks", "verify-rules.json")
    try:
        with open(path, encoding="utf-8") as fh:
            rules.update(json.load(fh))
    except FileNotFoundError:
        pass
    except (OSError, ValueError) as exc:
        print(f"verify-rules.json is unreadable ({exc}); using defaults.", file=sys.stderr)
    return rules


def matches(rel: str, patterns: list[str]) -> bool:
    base = os.path.basename(rel)
    return any(fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(base, p) for p in patterns)


def scan(transcript: str, root: str, rules: dict) -> tuple[int, str | None, int]:
    """Return (index of last source edit, its path, index of last test run)."""
    last_edit, last_edit_path, last_test = -1, None, -1
    try:
        fh = open(transcript, encoding="utf-8", errors="replace")
    except OSError:
        return -1, None, -1
    with fh:
        for i, line in enumerate(fh):
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("type") != "assistant":
                continue
            content = (e.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for b in content:
                if b.get("type") != "tool_use":
                    continue
                name, inp = b.get("name"), b.get("input") or {}
                if name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
                    p = inp.get("file_path") or inp.get("notebook_path") or ""
                    if not p:
                        continue
                    try:
                        rel = os.path.relpath(os.path.abspath(p), root)
                    except ValueError:
                        continue
                    if rel.startswith("..") or matches(rel, rules["exempt"]):
                        continue
                    if matches(rel, rules["source"]):
                        last_edit, last_edit_path = i, rel
                elif name == "Bash":
                    cmd = inp.get("command") or ""
                    if any(re.search(rx, cmd) for rx in rules["tests"]):
                        last_test = i
    return last_edit, last_edit_path, last_test


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0

    # The hook's own block re-triggers Stop; never act on that pass.
    if payload.get("stop_hook_active"):
        return 0

    transcript = payload.get("transcript_path") or ""
    cwd = payload.get("cwd") or os.getcwd()
    root = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
    if not transcript or not os.path.exists(transcript):
        return 0

    rules = load_rules(root)
    last_edit, path, last_test = scan(transcript, root, rules)

    if last_edit < 0 or last_test > last_edit:
        return 0

    ran = "no test command has run in this session" if last_test < 0 else \
          "the last test run was before that edit"
    print(
        f"Blocked by the verify guard (.claude/hooks/verify_guard.py).\n\n"
        f"Source changed and {ran}. Most recent source edit: `{path}`.\n\n"
        f"{rules['message']}\n\n"
        f"If the change genuinely has no runtime surface, say so explicitly and\n"
        f"end the turn again -- this guard does not fire twice in a row.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
