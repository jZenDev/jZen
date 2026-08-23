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
import hashlib
import sys
import tempfile

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


def cache_path(root: str, session: str) -> str:
    """Where the resume point lives. Inside .git so it is never committed."""
    git_dir = os.path.join(root, ".git")
    base = git_dir if os.path.isdir(git_dir) else tempfile.gettempdir()
    return os.path.join(base, "claude-verify-guard", f"{session or 'nosession'}.json")


def head_digest(transcript: str) -> str:
    """Fingerprint of the file's opening bytes.

    Size alone cannot tell a resumed transcript from a rewritten one: a file
    replaced with same-or-larger content would let the cache resume at an
    offset that now points into different data. The opening bytes of a given
    session's transcript never change, so a changed digest means re-scan.
    """
    try:
        with open(transcript, "rb") as fh:
            return hashlib.sha256(fh.read(512)).hexdigest()
    except OSError:
        return ""


def load_cache(root: str, session: str, size: int, head: str) -> dict | None:
    """The saved scan state, or None if it cannot be trusted for this file.

    A transcript only ever grows within a session, so a cache whose recorded
    size exceeds the file's is stale -- truncated, rotated or replaced -- and
    so is one whose opening bytes no longer match.
    """
    try:
        with open(cache_path(root, session), encoding="utf-8") as fh:
            c = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(c, dict):
        return None
    try:
        if int(c["size"]) > size or int(c["offset"]) > size:
            return None
        if c.get("head") != head:
            return None
        return c
    except (KeyError, TypeError, ValueError):
        return None


def save_cache(root: str, session: str, state: dict) -> None:
    path = cache_path(root, session)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(state, fh)
        os.replace(tmp, path)          # atomic; a torn cache would be worse than none
    except OSError:
        pass                            # a cache that cannot be written costs speed, not correctness


def scan(transcript: str, root: str, rules: dict, session: str = "") -> tuple[int, str | None, int]:
    """Return (index of last source edit, its path, index of last test run).

    Resumes from a byte offset saved on the previous turn. Without that this
    re-read the whole transcript on every turn end, which is quadratic across a
    session -- fine at 3 MB, and not fine at the 90 MB these sessions reach.
    """
    last_edit, last_edit_path, last_test = -1, None, -1
    start_offset, start_line = 0, 0
    try:
        size = os.path.getsize(transcript)
    except OSError:
        return -1, None, -1

    head = head_digest(transcript)
    cached = load_cache(root, session, size, head)
    if cached:
        start_offset = int(cached["offset"])
        start_line = int(cached.get("line", 0))
        last_edit = int(cached.get("last_edit", -1))
        last_edit_path = cached.get("last_edit_path")
        last_test = int(cached.get("last_test", -1))

    try:
        fh = open(transcript, encoding="utf-8", errors="replace")
    except OSError:
        return -1, None, -1
    with fh:
        fh.seek(start_offset)
        offset, i = start_offset, start_line
        while True:
            # readline() rather than iterating the handle: tell() is disabled
            # inside a `for line in fh` loop, and the byte offset is the whole
            # point of this pass.
            raw = fh.readline()
            if not raw:
                break
            # A transcript is appended to while a session runs, so the final
            # line can be half-written. Stop before it and resume there next
            # turn rather than parsing a fragment.
            if not raw.endswith("\n"):
                break
            i += 1
            offset = fh.tell()
            line = raw
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
        save_cache(root, session, {
            "size": size, "head": head, "offset": offset, "line": i,
            "last_edit": last_edit, "last_edit_path": last_edit_path,
            "last_test": last_test,
        })
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
    last_edit, path, last_test = scan(transcript, root, rules,
                                      payload.get("session_id") or "")

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
