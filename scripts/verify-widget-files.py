#!/usr/bin/env python3
"""Fail if a Dart file defines more than one Flutter widget. Run by `task verify:widget-files`.

WHAT this enforces and WHY is STANDARDS "One widget per file" and the Taskfile's
`verify:widget-files` summary (`task verify:widget-files --summary`), which is the operator-facing
contract and stays there. This docstring covers only HOW, and the three things about the how that
are worth knowing.

**Why this is Python** (STANDARDS "Scripting", ADR-032): it has to *understand* Dart source — tell
a class declaration from the word "class" in a comment or a string, read an `extends` clause past a
type-parameter bound — which is Rule 3. A `grep '^class .* extends StatelessWidget'` finds the
common case and misses `abstract class`, a generic bound, a prefixed import and a doc comment that
quotes a class, and it cannot tell the lines it should not count from the lines it should.

**How a class is found.** `_blank_non_code` replaces every comment and string literal with
whitespace, keeping the newlines, so the declarations are matched against code only and a reported
line number is the real one. Strings are the part that earns its keep: a `${...}` interpolation can
hold a nested string (`'${a['b']}'`), so the string scanner recurses into it rather than ending at
the first inner quote.

**What counts as a widget.** A class whose `extends` clause names a widget base. The base is
recognised by name — anything ending in `Widget` (`StatelessWidget`, `ConsumerWidget`,
`HookWidget`, `LeafRenderObjectWidget`, ...) plus a short list that does not (`FormField`,
`InheritedModel`, ...) — and transitively across every package being scanned, so
`class ZenDateField extends ZenField` counts when `ZenField` is itself a widget declared in a
scanned package. What it cannot see is a widget that extends a base declared *outside* the scanned
packages and whose name does not end in `Widget`: the script has no way to resolve it, and says so
here rather than pretending otherwise.

A `State` (`State<Foo>`, `ConsumerState<Foo>`) is not a widget and is never counted; it is
attributed to the widget named in its type argument and printed beside it. That is the exception in
the rule, by construction: Flutter needs `State` private to, and beside, its own widget.

**Nothing passes vacuously.** "We did not look" and "we looked and it was clean" must not share an
exit code, the property `verify-boundaries.py` was rewritten to have. A path that does not exist, a
path under which no Dart package was found, a file that cannot be read, a scan that read no Dart
file at all, and a suppression that matches nothing are each a non-zero exit with the reason.

**Suppressions** (`--suppressions FILE`) are one file, `<path>  <reason>` per line, same-line reason
required — the shape of `audit-*-suppressions.txt`. A path is relative to where the script runs.
An entry that suppresses nothing (the file is gone, or no longer holds two widgets) is itself a
failure, because a list that only ever grows is how an exemption turns into a habit.

Written to the 3.9 floor, stdlib only.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib  # noqa: E402  (sibling module; sys.path is set immediately above)

# Directories never descended into when looking for packages. Hidden directories (`.dart_tool`,
# `.symlinks`, `.git`) are skipped by rule; these two are the visible ones that hold other people's
# manifests and build output rather than this repository's source.
SKIP_DIRS = frozenset({"build", "node_modules"})

# Generated code is exempt: it is a derived artifact, and editing it is already a defect the
# contract-sync gate catches. The component match covers `lib/generated/` and
# `lib/src/l10n/generated/` alike.
GENERATED_DIR = "generated"

# A widget base is recognised by name. `Widget` as a suffix covers the whole family and the
# Riverpod and flutter_hooks additions without a list that has to be kept current.
WIDGET_BASE_SUFFIX = "Widget"
WIDGET_BASES_EXTRA = frozenset({"FormField", "InheritedModel", "InheritedNotifier", "InheritedTheme"})
STATE_BASES = frozenset({"State", "ConsumerState", "HookConsumerState"})

CLASS_DECL = re.compile(r"(?<![\w$])class\s+([A-Za-z_$][\w$]*)")
EXTENDS_CLAUSE = re.compile(r"\s*extends\s+([\w$.]+)")
IDENT = re.compile(r"[A-Za-z_$][\w$]*")


class ScanProblem(Exception):
    """Raised for a suppression file the script cannot trust."""


@dataclass(frozen=True)
class DartClass:
    name: str
    base: "str | None"
    type_arg: "str | None"  # first type argument of the base: `Foo` in `State<Foo>`
    line: int


@dataclass(frozen=True)
class Offender:
    path: str
    line: int
    widgets: "tuple[tuple[str, int, str | None], ...]"  # (name, line, its State's name)

    def __str__(self) -> str:
        listed = ", ".join(
            f"{name} (line {line})" + (f" + {state}" if state else "")
            for name, line, state in self.widgets
        )
        return f"{self.path}:{self.line}: {len(self.widgets)} widgets in one file: {listed}"


@dataclass
class Result:
    offenders: "list[Offender]"
    errors: "list[str]"
    files: int
    packages: int


# --- lexing ----------------------------------------------------------------------------------


def _blank_non_code(src: str) -> str:
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


def _balanced_angle(text: str, start: int) -> int:
    """Index just past the `>` closing the `<` at `text[start]` (or the end if unbalanced)."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "<":
            depth += 1
        elif text[i] == ">":
            depth -= 1
            if depth == 0:
                return i + 1
    return len(text)


def _header(code: str, pos: int) -> str:
    """The class header after its name: up to the `{` or `;` that ends it, parentheses balanced."""
    depth = 0
    i = pos
    while i < len(code):
        c = code[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif depth <= 0 and c in "{;":
            break
        i += 1
    return code[pos:i]


def parse_classes(src: str) -> "list[DartClass]":
    """Every class declared in `src`, with the base it extends and that base's first type argument."""
    code = _blank_non_code(src)
    found: "list[DartClass]" = []
    for m in CLASS_DECL.finditer(code):
        header = _header(code, m.end())
        i = len(header) - len(header.lstrip())
        if header[i : i + 1] == "<":  # type parameters, whose own `extends` is a bound, not a base
            i = _balanced_angle(header, i)
        base = type_arg = None
        ext = EXTENDS_CLAUSE.match(header, i)
        if ext:
            base = ext.group(1).split(".")[-1]
            after = header[ext.end() :].lstrip()
            if after.startswith("<"):
                inner = after[1 : _balanced_angle(after, 0) - 1]
                first = IDENT.search(inner)
                type_arg = first.group(0) if first else None
        found.append(DartClass(m.group(1), base, type_arg, code.count("\n", 0, m.start()) + 1))
    return found


# --- classification --------------------------------------------------------------------------


def _is_widget_base_name(name: str) -> bool:
    return name.endswith(WIDGET_BASE_SUFFIX) or name in WIDGET_BASES_EXTRA


def _resolver(all_classes: "list[DartClass]"):
    """A predicate: does a class extending `base` end up a widget, across every scanned package?"""
    bases: "dict[str, set[str]]" = {}
    for c in all_classes:
        if c.base:
            bases.setdefault(c.name, set()).add(c.base)

    def reaches_widget(name: str, seen: "set[str]") -> bool:
        if _is_widget_base_name(name):
            return True
        if name in seen:
            return False
        seen.add(name)
        return any(reaches_widget(b, seen) for b in bases.get(name, ()))

    return lambda base: base is not None and reaches_widget(base, set())


def widgets_in(classes: "list[DartClass]", is_widget) -> "list[tuple[str, int, str | None]]":
    """The widgets among `classes` as (name, line, name of its State if it has one here)."""
    widgets = [c for c in classes if is_widget(c.base)]
    names = {c.name for c in widgets}
    state_of: "dict[str, str]" = {}
    for c in classes:
        if c.base in STATE_BASES and c.type_arg in names:
            state_of[c.type_arg] = c.name
    return [(c.name, c.line, state_of.get(c.name)) for c in widgets]


# --- scanning --------------------------------------------------------------------------------


def _relative(path: Path) -> str:
    try:
        return Path(os.path.relpath(path)).as_posix()
    except ValueError:  # a different drive on Windows has no relative form
        return path.as_posix()


def find_packages(root: Path) -> "list[Path]":
    """Every directory at or under `root` that holds a `pubspec.yaml` and a `lib/`."""
    packages: "list[Path]" = []
    for dirpath, dirnames, filenames in os.walk(root):
        here = Path(dirpath)
        if "pubspec.yaml" in filenames and (here / "lib").is_dir():
            packages.append(here)
        # `lib` is a package's source, never a place packages live; hidden and build directories
        # hold derived output or other people's manifests.
        dirnames[:] = sorted(
            d for d in dirnames if d != "lib" and d not in SKIP_DIRS and not d.startswith(".")
        )
    return packages


def dart_files(package: Path) -> "list[Path]":
    return sorted(
        f
        for f in (package / "lib").rglob("*.dart")
        if f.is_file() and GENERATED_DIR not in f.relative_to(package / "lib").parts
    )


def scan(paths: "list[str]") -> Result:
    errors: "list[str]" = []
    packages: "dict[Path, None]" = {}
    for raw in paths:
        root = Path(raw)
        if not root.is_dir():
            errors.append(f"{raw}: not a directory, so nothing under it could be scanned")
            continue
        found = find_packages(root)
        if not found:
            errors.append(f"{raw}: no Dart package (a pubspec.yaml beside a lib/) found under it")
        for p in found:
            packages[p.resolve()] = None

    parsed: "dict[Path, list[DartClass]]" = {}
    for package in packages:
        for f in dart_files(package):
            try:
                parsed[f] = parse_classes(f.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError) as e:
                errors.append(f"{_relative(f)}: could not be read ({e.__class__.__name__}: {e})")

    if not parsed and not errors:
        errors.append("no Dart file was found to scan, so the gate has checked nothing")

    is_widget = _resolver([c for classes in parsed.values() for c in classes])
    offenders: "list[Offender]" = []
    for f in sorted(parsed):
        widgets = widgets_in(parsed[f], is_widget)
        if len(widgets) > 1:
            offenders.append(Offender(_relative(f), widgets[0][1], tuple(widgets)))
    return Result(offenders, errors, len(parsed), len(packages))


# --- suppressions ----------------------------------------------------------------------------


def load_suppressions(path: Path) -> "dict[str, str]":
    """`<path>  <reason>` per line. A line with no reason is an error, not a skipped line."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        raise ScanProblem(f"suppressions file {path} could not be read: {e}") from e
    entries: "dict[str, str]" = {}
    for n, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) < 2:
            raise ScanProblem(
                f"{path}:{n}: '{parts[0]}' has no reason. An exemption is argued, not taken: say "
                "what this file carries that would be lost by splitting it."
            )
        if parts[0] in entries:
            raise ScanProblem(f"{path}:{n}: '{parts[0]}' is listed twice")
        entries[parts[0]] = parts[1]
    return entries


# --- entry point -----------------------------------------------------------------------------


def main(argv: "list[str] | None" = None) -> int:
    ap = argparse.ArgumentParser(description="Fail if a Dart file defines more than one widget.")
    ap.add_argument("paths", nargs="+", help="a Dart package, or a directory holding packages")
    ap.add_argument("--suppressions", metavar="FILE", help="'<path>  <reason>' per line")
    args = ap.parse_args(argv)

    print("Checking one widget per file...")
    try:
        suppressed = load_suppressions(Path(args.suppressions)) if args.suppressions else {}
    except ScanProblem as e:
        lib.fail("the suppressions cannot be trusted:", [str(e)])
        return 1

    result = scan(args.paths)
    failed = False

    if result.errors:
        lib.fail("the scan could not be made, so it checked nothing it can vouch for:", result.errors)
        failed = True

    offenders = [o for o in result.offenders if o.path not in suppressed]
    stale = sorted(set(suppressed) - {o.path for o in result.offenders})
    if stale:
        lib.fail(
            "a suppression matches no file with more than one widget (remove it):",
            [f"{p}  {suppressed[p]}" for p in stale],
        )
        failed = True
    if offenders:
        lib.fail('a file defines more than one widget (STANDARDS "One widget per file"):',
                 [str(o) for o in offenders])
        failed = True

    if not failed:
        lib.ok(f"{result.files} Dart files in {result.packages} packages: one widget per file")
        return 0
    print()
    print("Every widget class lives in its own file, named for the class. Extract a helper as a")
    print("public class in its own file; a StatefulWidget and its private State stay together.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
