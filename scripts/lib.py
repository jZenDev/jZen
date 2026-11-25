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


# --- Dart source ------------------------------------------------------------------------------


def blank_dart_non_code(src: str) -> str:
    """`src` with every comment and string literal replaced by spaces, newlines kept.

    The length and the line structure are preserved, so an offset into the result is an offset into
    the original and a line number counted in it is the real one.
    """
    out = list(src)
    n = len(src)

    def blank(a: int, b: int) -> None:
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    def skip_block_comment(i: int) -> int:
        depth = 0
        while i < n:
            if src.startswith("/*", i):
                depth += 1
                i += 2
            elif src.startswith("*/", i):
                depth -= 1
                i += 2
                if depth == 0:
                    return i
            else:
                i += 1
        return n

    def skip_string(i: int) -> int:
        quote = src[i]
        raw = i > 0 and src[i - 1] == "r" and (
            i < 2 or not (src[i - 2].isalnum() or src[i - 2] in "_$")
        )
        delim = quote * 3 if src.startswith(quote * 3, i) else quote
        j = i + len(delim)
        while j < n:
            if not raw and src[j] == "\\":
                j += 2
            elif not raw and src.startswith("${", j):
                j = skip_code(j + 2, True)
            elif src.startswith(delim, j):
                j += len(delim)
                break
            elif len(delim) == 1 and src[j] == "\n":
                break  # unterminated single-line string: stop at the line rather than eat the file
            else:
                j += 1
        blank(i, j)
        return j

    def skip_code(i: int, in_interpolation: bool) -> int:
        depth = 0
        while i < n:
            c = src[i]
            if src.startswith("//", i):
                j = src.find("\n", i)
                j = n if j < 0 else j
                blank(i, j)
                i = j
            elif src.startswith("/*", i):
                j = skip_block_comment(i)
                blank(i, j)
                i = j
            elif c in "'\"":
                i = skip_string(i)
            elif c == "{":
                depth += 1
                i += 1
            elif c == "}":
                if depth == 0 and in_interpolation:
                    return i + 1
                depth -= 1
                i += 1
            else:
                i += 1
        return n

    skip_code(0, False)
    return "".join(out)
