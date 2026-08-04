"""Shared helpers for the jZen Python dev scripts. Import this; do not execute it.

The counterpart of `lib.sh`, and deliberately its mirror: the same vocabulary (`info`, `warn`,
`die`, `ok`, `fail`) printing the same shapes, so the two halves of `scripts/` read as one thing
rather than as two conventions that happen to share a directory. Which language a given script
belongs in is decided by STANDARDS "Scripting" — sh runs things, Python understands things — and
this file exists because the scripts on the Python side of that line cannot source a shell file.

One deliberate difference from `lib.sh`: colour is suppressed when stdout is not a terminal, and
when `NO_COLOR` is set. `lib.sh` emits escape codes unconditionally, which is invisible in a
terminal and becomes noise the moment a gate's output is captured, piped, or read out of a CI log.
Detecting it costs one line here and cannot be done that cheaply in sh, so the sh side keeps its
behaviour and this side does the better thing.

Written to the 3.9 floor (STANDARDS "Scripting"), stdlib only.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None

GREEN = "\033[0;32m" if _COLOR else ""
YELLOW = "\033[0;33m" if _COLOR else ""
RED = "\033[0;31m" if _COLOR else ""
NC = "\033[0m" if _COLOR else ""


def info(msg: str) -> None:
    print(f"{GREEN}==>{NC} {msg}")


def warn(msg: str) -> None:
    print(f"{YELLOW}==>{NC} {msg}")


def die(msg: str, code: int = 1) -> "NoReturn":  # type: ignore[valid-type]
    print(f"{RED}!! {msg}{NC}", file=sys.stderr)
    raise SystemExit(code)


def ok(msg: str) -> None:
    """A passing check, indented to match `say_ok` in the sh gates."""
    print(f"  {GREEN}ok{NC}   {msg}")


def fail(msg: str, hits: "list[str] | None" = None) -> None:
    """A failing check, plus the offending lines indented beneath it (`say_fail`'s shape)."""
    print(f"  {RED}FAIL{NC} {msg}")
    for hit in hits or []:
        print(f"         {hit}")


def repo_root() -> Path:
    """The repository root, derived from this file's location rather than the cwd.

    A gate must produce the same verdict wherever it is invoked from — `task` runs it from the
    root, a developer may run it from `scripts/`, and an editor may run it from anywhere.
    """
    return Path(__file__).resolve().parent.parent
