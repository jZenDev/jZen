#!/usr/bin/env python3
"""Deliver a skill's rules when a file it governs is about to be edited.

The skills in this repo encode real production incidents, and the session
transcripts show them almost never loading: a skill fires when the agent
recognises "this is a design task", but the agent is usually part-way
through something else when it opens a template, and by then the framing is
set. Recognition is the wrong trigger. The file path is the right one.

So: a PreToolUse hook on Edit/Write matches the path against
.claude/hooks/skill-map.json and, the first time in a session that a
governed file is touched, blocks the edit and puts the skill's rules on
stderr, which is fed back to the agent. It fires once per skill per
session -- the second edit of the same kind goes straight through.

Blocking is deliberate. Rules that arrive after the edit are advice; rules
that arrive before it are a gate.
"""

from __future__ import annotations

import fnmatch
import json
import os
import sys
import tempfile

MAX_INLINE_LINES = 140


def load_map(root: str) -> list[dict]:
    path = os.path.join(root, ".claude", "hooks", "skill-map.json")
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return []
    except (OSError, ValueError) as exc:
        print(f"skill-map.json is unreadable ({exc}).", file=sys.stderr)
        return []
    rules = data.get("rules", [])
    return rules if isinstance(rules, list) else []


def edited_path(payload: dict) -> str | None:
    ti = payload.get("tool_input") or {}
    for key in ("file_path", "notebook_path", "path"):
        value = ti.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def matches(rel: str, patterns: list[str]) -> bool:
    base = os.path.basename(rel)
    for pattern in patterns:
        if fnmatch.fnmatch(rel, pattern) or fnmatch.fnmatch(base, pattern):
            return True
        # Let "templates/" style prefixes match a whole subtree.
        if pattern.endswith("/") and rel.startswith(pattern):
            return True
    return False


def marker_dir(root: str, session: str) -> str:
    git_dir = os.path.join(root, ".git")
    base = git_dir if os.path.isdir(git_dir) else tempfile.gettempdir()
    return os.path.join(base, "claude-skill-guard", session or "nosession")


def already_delivered(root: str, session: str, skill: str) -> bool:
    return os.path.exists(os.path.join(marker_dir(root, session), skill))


def mark_delivered(root: str, session: str, skill: str) -> None:
    directory = marker_dir(root, session)
    try:
        os.makedirs(directory, exist_ok=True)
        open(os.path.join(directory, skill), "w").close()
    except OSError:
        # If the marker cannot be written the guard fires again next edit --
        # noisy, but never wrong. Do not fail the tool call over it.
        pass


def skill_body(root: str, skill: str) -> tuple[str, str | None]:
    path = os.path.join(root, ".claude", "skills", skill, "SKILL.md")
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return "", None
    lines = text.split("\n")
    if len(lines) > MAX_INLINE_LINES:
        head = "\n".join(lines[:MAX_INLINE_LINES])
        return (
            f"{head}\n\n[...{len(lines) - MAX_INLINE_LINES} more lines. "
            f"Read the rest before you continue: {path}]"
        ), path
    return text, path


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0

    path = edited_path(payload)
    if not path:
        return 0
    cwd = payload.get("cwd") or os.getcwd()
    root = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
    session = payload.get("session_id") or ""

    try:
        rel = os.path.relpath(os.path.abspath(path), root)
    except ValueError:
        rel = path
    if rel.startswith(".."):
        return 0  # outside the project; not ours to govern

    pending: list[tuple[str, str, str]] = []  # (skill, why, body)
    for rule in load_map(root):
        skill = rule.get("skill")
        patterns = rule.get("paths") or []
        if not skill or not matches(rel, patterns):
            continue
        if matches(rel, rule.get("exclude") or []):
            continue  # build output and vendored trees are not authored here
        if already_delivered(root, session, skill):
            continue
        body, skill_path = skill_body(root, skill)
        if not body:
            continue
        why = rule.get("why") or f"it governs `{rel}`"
        pending.append((skill, why, f"Source: {skill_path}\n\n{body}"))

    if not pending:
        return 0

    for skill, _, _ in pending:
        mark_delivered(root, session, skill)

    names = ", ".join(f"`{s}`" for s, _, _ in pending)
    print(
        f"Blocked once by the skill guard (.claude/hooks/skill_guard.py).\n\n"
        f"Editing `{rel}` engages {names}. Their rules are below -- apply them, then\n"
        f"re-issue this edit. Each skill fires once per session, so the next edit of\n"
        f"this kind goes straight through.",
        file=sys.stderr,
    )
    for skill, why, body in pending:
        print(
            f"\n{'=' * 70}\n{skill} -- {why}\n{'=' * 70}\n{body}",
            file=sys.stderr,
        )
    return 2


if __name__ == "__main__":
    sys.exit(main())
