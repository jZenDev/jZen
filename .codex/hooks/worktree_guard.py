#!/usr/bin/env python3
"""Keep a session out of work it did not do.

The working tree is shared. The user edits files in the same repository while
a session runs, and a session that assumes otherwise commits their work by
accident. That happened twice in one sitting: once because a file was already
staged when `git commit` ran, and once because `git checkout` aborted on the
user's uncommitted changes, leaving a stash to pop back onto their branch.

Both are mechanical, so both are checked here rather than remembered:

  * `git commit` -- refuse when the index holds a file this session never
    wrote. The session's own files are recovered from the transcript, so the
    check needs no bookkeeping.
  * `git checkout <branch>` / `git switch <branch>` -- refuse while tracked
    files this session did not touch are modified. Switching branches under
    someone else's work is how the first mistake became the second; a
    `git worktree` does the same job without touching the tree.

Escape hatch, for when the foreign files really are meant to go in:
prefix the command with `ALLOW_FOREIGN=1`.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

# Bash forms that create or modify a file. The transcript records Edit/Write
# directly, but a session also writes files with a redirect or a heredoc, and
# those count as its own work just as much.
WRITE_FORMS = [
    re.compile(r">>?\s*([^\s|&;<>()]+)"),                  # > path, >> path
    re.compile(r"\btee\s+(?:-a\s+)?([^\s|&;<>()]+)"),
    re.compile(r"\bcp\s+(?:-[a-zA-Z]+\s+)*\S+\s+([^\s|&;<>()]+)"),
    re.compile(r"\bmv\s+(?:-[a-zA-Z]+\s+)*\S+\s+([^\s|&;<>()]+)"),
    re.compile(r"\bsed\s+-i(?:\s+\S+)?\s+([^\s|&;<>()]+)"),
    re.compile(r"\btouch\s+([^\s|&;<>()]+)"),
]


def run(args: list[str], cwd: str) -> str:
    try:
        p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return ""
    return p.stdout if p.returncode == 0 else ""


def repo_root(cwd: str) -> str | None:
    out = run(["git", "rev-parse", "--show-toplevel"], cwd).strip()
    # realpath both sides everywhere: on macOS a temp dir is /var/... while git
    # reports /private/var/..., and the two never compare equal.
    return os.path.realpath(out) if out else None


def session_paths(transcript: str, root: str) -> set[str]:
    """Repo-relative paths this session wrote, recovered from its transcript."""
    paths: set[str] = set()
    if not transcript or not os.path.exists(transcript):
        return paths

    def add(p: str) -> None:
        if not p or p.startswith("-"):
            return
        try:
            full = p if os.path.isabs(p) else os.path.join(root, p)
            rel = os.path.relpath(os.path.realpath(full), root)
        except (ValueError, OSError):
            return
        if not rel.startswith(".."):
            paths.add(rel)

    try:
        fh = open(transcript, encoding="utf-8", errors="replace")
    except OSError:
        return paths
    with fh:
        for line in fh:
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
                    add(inp.get("file_path") or inp.get("notebook_path") or "")
                elif name == "Bash":
                    cmd = inp.get("command") or ""
                    for rx in WRITE_FORMS:
                        for m in rx.finditer(cmd):
                            add(m.group(1).strip("\"'"))
    return paths


def staged(cwd: str) -> list[str]:
    return [l for l in run(["git", "diff", "--cached", "--name-only"], cwd).splitlines() if l]


def modified_tracked(cwd: str) -> list[str]:
    out = run(["git", "status", "--porcelain", "--untracked-files=no"], cwd)
    return [l[3:].strip() for l in out.splitlines() if l[:2].strip()]


def git_argv(command: str) -> list[list[str]]:
    found = []
    for seg in re.split(r"&&|\|\||;|\n", command):
        toks = seg.split()
        i = 0
        while i < len(toks) and ("=" in toks[i] or toks[i] in ("env", "sudo", "nohup")):
            i += 1
        if i < len(toks) and os.path.basename(toks[i]) == "git":
            found.append(toks[i:])
    return found


def subcommand(argv: list[str]) -> str | None:
    i = 1
    while i < len(argv):
        if argv[i] in ("-C", "-c", "--git-dir", "--work-tree"):
            i += 2
            continue
        if argv[i].startswith("-"):
            i += 1
            continue
        return argv[i]
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0
    command = (payload.get("tool_input") or {}).get("command") or ""
    if not command.strip() or "git" not in command:
        return 0
    if re.search(r"\bALLOW_FOREIGN=1\b", command):
        return 0

    cwd = payload.get("cwd") or os.getcwd()
    root = repo_root(cwd)
    if not root:
        return 0
    mine = session_paths(payload.get("transcript_path") or "", root)

    invocations = git_argv(command)
    names = [subcommand(a) for a in invocations]
    problems: list[str] = []

    if "commit" in names and not any(
            re.search(r"--amend", " ".join(a)) and "--no-edit" in a for a in invocations):
        foreign = [p for p in staged(cwd) if p not in mine]
        if foreign:
            shown = "\n".join(f"      {p}" for p in foreign[:12])
            more = f"\n      ... and {len(foreign) - 12} more" if len(foreign) > 12 else ""
            problems.append(
                "The index holds files this session never wrote:\n"
                f"{shown}{more}\n"
                "    They are probably the user's work in progress. Unstage them\n"
                "    (`git restore --staged <path>`) and commit only your own files.\n"
                "    If they genuinely belong in this commit, re-run the command\n"
                "    prefixed with ALLOW_FOREIGN=1.")

    for argv, name in zip(invocations, names):
        if name not in ("checkout", "switch"):
            continue
        flags = set(argv)
        creating = bool(flags & {"-b", "-B", "-c", "-C", "--create"})
        if creating:
            # Branching from HEAD carries the working tree along and always
            # succeeds. Branching from a START-POINT does not: git aborts if a
            # modified file differs between HEAD and that point, which is
            # exactly how a stash-and-switch ends up popped onto the wrong
            # branch. Only the start-point form is worth blocking.
            after = argv[2:]
            names = [a for a in after if not a.startswith("-")]
            start_point = len(names) >= 2
            if not start_point:
                continue
            foreign = [p for p in modified_tracked(cwd) if p not in mine]
            if foreign:
                shown = "\n".join(f"      {p}" for p in foreign[:8])
                more = f"\n      ... and {len(foreign) - 8} more" if len(foreign) > 8 else ""
                problems.append(
                    f"Branching from `{names[1]}` while files this session did not touch\n"
                    "    are modified:\n"
                    f"{shown}{more}\n"
                    "    git aborts this when a modified file differs between HEAD and the\n"
                    "    start point, and a stash taken first then pops back onto the branch\n"
                    "    you were trying to leave. Use a worktree, which needs no stash:\n"
                    f"        git worktree add -b {names[0]} <dir> {names[1]}\n"
                    "    Work there, commit, push, then `git worktree remove <dir>`.")
            continue
        if "--" in argv:
            continue                      # everything after `--` is a pathspec
        rest = [a for a in argv[2:] if not a.startswith("-")]
        if not rest:
            continue
        target = rest[0]
        # `git checkout somefile.txt` restores a file; only a name that is not
        # a path in the tree is a branch to switch to.
        if os.path.exists(os.path.join(root, target)):
            continue
        foreign = [p for p in modified_tracked(cwd) if p not in mine]
        if foreign:
            shown = "\n".join(f"      {p}" for p in foreign[:8])
            more = f"\n      ... and {len(foreign) - 8} more" if len(foreign) > 8 else ""
            problems.append(
                f"Switching to `{target}` while files this session did not touch are\n"
                "    modified:\n"
                f"{shown}{more}\n"
                "    A switch here either fails or carries the user's work onto another\n"
                "    branch. Use a worktree instead, which leaves this tree alone:\n"
                f"        git worktree add -b <branch> <dir> origin/main\n"
                "    Work there, commit, push, then `git worktree remove <dir>`.")

    if not problems:
        return 0
    print("Blocked by the working-tree guard (.claude/hooks/worktree_guard.py):\n",
          file=sys.stderr)
    for p in problems:
        print(f"  - {p}\n", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
