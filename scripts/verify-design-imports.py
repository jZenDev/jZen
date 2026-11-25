#!/usr/bin/env python3
"""Fail if a Dart file imports Flutter's in-SDK Material or Cupertino library. Run by `task verify:design-imports`.

WHAT this enforces and WHY is ADR-082, STANDARDS "Client UI: the framework's controls first" and the
Taskfile's `verify:design-imports` summary (`task verify:design-imports --summary`), which is the
operator-facing contract and stays there. This docstring covers only HOW.

**Why a gate at all.** Since Flutter 3.50 `package:flutter/material.dart` and `cupertino.dart` are
deprecated in favour of the standalone `material_ui` and `cupertino_ui` packages. The analyzer says so
at *info* level, and an info fails no suite and no build: one stray import still compiles, still
renders and still passes every test, while the deprecation deadline the framework does not control
gets closer. A rule that nothing checks is a preference.

**What is flagged.** An `import` or `export` directive whose URI is `package:flutter/material.dart`,
`package:flutter/cupertino.dart`, or anything under `package:flutter/src/material/` or
`package:flutter/src/cupertino/`. It is flagged however it is spelled — `show`, `hide`, `as`,
`deferred`, a raw string, single or double quotes, split over several lines. `package:flutter/widgets.dart`,
`flutter/services.dart` and `flutter_localizations` are not Material or Cupertino and are left alone.

**How a directive is found.** `lib.blank_dart_non_code` blanks every comment and string literal,
keeping the length, so a directive is matched against code only: `import 'package:flutter/material.dart';`
inside a doc comment or a multi-line string is not a directive, and the reported line is the real one.
The blanked text still tells where a string starts, so the URI is then read from the original at the
same offset.

**What is scanned.** Every `.dart` file under each root — `lib/`, `test/`, `example/`,
`integration_test/`, `tool/` — because a test harness that imports the SDK library is the same defect as
a widget that does, and the harnesses are where one of them was found. Hidden directories (`.dart_tool`)
and `build`/`node_modules` are skipped; generated code is not, because it is built from this tree and
breaks the same way.

**Nothing passes vacuously.** "We did not look" and "we looked and it was clean" must not share an exit
code. A root that does not exist, a root with no Dart package under it, a file that cannot be read, a
`.dart` file that is a symlink out of its root, and a scan that read no Dart file at all are each a
non-zero exit with the reason.

**No exemptions.** There is no suppression file, unlike `verify:widget-files`: the one thing an
exemption would carry is an import ADR-082 forbids, and a dependency that still needs the SDK library is
what `MaterialUiCompatibilityBridge` is for. If a real case appears, it is argued in an ADR first.

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

# Directories never descended into: hidden ones (`.dart_tool`, `.symlinks`, `.git`) are skipped by
# rule; these two are the visible ones that hold build output and other people's sources.
SKIP_DIRS = frozenset({"build", "node_modules"})

# The libraries ADR-082 retires from jZen code. `material` and `cupertino` under `src/` are the same
# code reached by a deep import, which is no more allowed than the front door.
LEGACY_URI = re.compile(r"^package:flutter/(?:(?:material|cupertino)\.dart|src/(?:material|cupertino)/)")

# A directive keyword in blanked code. The lookbehind keeps `reimport(` and `a.import` out; what
# follows is checked separately, because a string is blanked and so cannot be matched here.
DIRECTIVE = re.compile(r"(?<![\w$.])(?:import|export)(?=\s)")

REPLACEMENT = {
    "material": "package:material_ui/material_ui.dart",
    "cupertino": "package:cupertino_ui/cupertino_ui.dart",
}


@dataclass(frozen=True)
class Hit:
    path: str
    line: int
    uri: str

    def __str__(self) -> str:
        kind = "cupertino" if "cupertino" in self.uri else "material"
        return f"{self.path}:{self.line}: imports '{self.uri}' (use '{REPLACEMENT[kind]}')"


@dataclass
class Result:
    hits: "list[Hit]"
    errors: "list[str]"
    files: int
    packages: int


def _relative(path: Path) -> str:
    try:
        return Path(os.path.relpath(path)).as_posix()
    except ValueError:  # a different drive on Windows has no relative form
        return path.as_posix()


def _uri_after(src: str, code: str, pos: int) -> "tuple[int, str] | None":
    """The string literal that follows a directive keyword ending at `pos`, as (offset, text).

    `code` is `src` with comments and strings blanked, same length. Whitespace and comments (blank in
    `code`, not whitespace in `src`) are stepped over; the first thing after them must be a string
    literal, a quote that `code` shows as blank, optionally behind the `r` of a raw string.
    """
    n = len(src)
    while pos < n:
        c = src[pos]
        if c in " \t\r\n" or (code[pos] == " " and c not in "'\""):
            pos += 1
            continue
        start = pos + 1 if c == "r" and code[pos] == "r" and code[pos + 1 : pos + 2] == " " else pos
        quote = src[start : start + 1]
        if quote not in ("'", '"') or code[start] != " ":
            return None
        end = src.find(quote, start + 1)
        nl = src.find("\n", start + 1)
        if end < 0 or 0 <= nl < end:  # unterminated on its own line: not a URI we can read
            return None
        return pos, src[start + 1 : end]
    return None


def find_legacy_imports(src: str, path: str = "") -> "list[Hit]":
    """Every `import`/`export` of an in-SDK Material or Cupertino library in `src`."""
    code = lib.blank_dart_non_code(src)
    hits: "list[Hit]" = []
    for m in DIRECTIVE.finditer(code):
        found = _uri_after(src, code, m.end())
        if found and LEGACY_URI.match(found[1]):
            hits.append(Hit(path, code.count("\n", 0, m.start()) + 1, found[1]))
    return hits


def find_packages(root: Path) -> "list[Path]":
    """Every directory at or under `root` that holds a `pubspec.yaml`."""
    return [Path(d) for d, _dirs, files in _walk(root) if "pubspec.yaml" in files]


def _walk(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not d.startswith("."))
        yield dirpath, dirnames, filenames


def scan(paths: "list[str]") -> Result:
    errors: "list[str]" = []
    hits: "list[Hit]" = []
    files = 0
    packages = 0
    for raw in paths:
        root = Path(raw)
        if not root.is_dir():
            errors.append(f"{raw}: not a directory, so nothing under it could be scanned")
            continue
        found = find_packages(root)
        if not found:
            errors.append(f"{raw}: no Dart package (a pubspec.yaml) found under it")
        packages += len(found)
        boundary = root.resolve()
        for dirpath, _dirs, filenames in _walk(root):
            for name in sorted(f for f in filenames if f.endswith(".dart")):
                f = Path(dirpath) / name
                try:
                    f.resolve().relative_to(boundary)
                except ValueError:
                    errors.append(
                        f"{_relative(f)}: resolves to {f.resolve()}, outside {raw}, so it was not read"
                    )
                    continue
                try:
                    text = f.read_text(encoding="utf-8")
                except (OSError, UnicodeDecodeError) as e:
                    errors.append(f"{_relative(f)}: could not be read ({e.__class__.__name__}: {e})")
                    continue
                files += 1
                hits.extend(find_legacy_imports(text, _relative(f)))
    if not files and not errors:
        errors.append("no Dart file was found to scan, so the gate has checked nothing")
    return Result(hits, errors, files, packages)


def main(argv: "list[str] | None" = None) -> int:
    ap = argparse.ArgumentParser(
        description="Fail if a Dart file imports package:flutter/material.dart or cupertino.dart."
    )
    ap.add_argument("paths", nargs="+", help="a Dart package, or a directory holding packages")
    args = ap.parse_args(argv)

    print("Checking design-library imports...")
    result = scan(args.paths)
    failed = False

    if result.errors:
        lib.fail("the scan could not be made, so it checked nothing it can vouch for:", result.errors)
        failed = True
    if result.hits:
        lib.fail(
            "a file imports Flutter's in-SDK Material or Cupertino library (ADR-082):",
            [str(h) for h in result.hits],
        )
        failed = True

    if not failed:
        lib.ok(f"{result.files} Dart files in {result.packages} packages: no in-SDK Material/Cupertino import")
        return 0
    print()
    print("Flutter 3.50 deprecates package:flutter/material.dart and cupertino.dart. Import")
    print("package:material_ui/material_ui.dart or package:cupertino_ui/cupertino_ui.dart, and declare the")
    print("package in the importing pubspec.yaml. `dart fix --apply --code=migrate_design_widgets` does it.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
