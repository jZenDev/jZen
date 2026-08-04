#!/usr/bin/env python3
"""Fail if a client package reaches past the jZen backend. Run by `task verify:boundaries`.

WHAT this enforces and WHY it is a gate is in the Taskfile's `verify:boundaries` summary, which is
the operator-facing contract and stays there (`task verify:boundaries --summary`). This docstring
covers only HOW, and the two things about the how that are worth knowing.

**Why this is Python and the launchers beside it are sh** (STANDARDS "Scripting", ADR-032): the
three checks below read source and return a verdict, which is Rule 3 work. In sh they were a nest
of `grep` pipelines feeding an `awk` program that stripped comments by field-splitting on `:` —
correct, but not correct *by inspection*, which is the property a gate most needs. The TypeScript
half made the point sharper still: a template literal is the most natural way to write a URL there,
so the quote set has to include a backtick, and a backtick cannot be *typed* into a sh gate because
it is command substitution before `grep` ever sees it. It had to be built as `$(printf '\140')`.
Here it is a character in a character class.

**Both languages, one rule.** Each check spans Dart (`client/*/lib`, `apps/*/*/lib`) and TypeScript
(`admin/src`, `apps/*/*_admin/src`), because the admin panel is a client: react-admin is a browser
application holding a session cookie, and a panel that reached the provider directly would break
the same property in the same silent way.

**The defect this conversion closes.** The sh version ended every scan with `2>/dev/null … ||
true`. That is load-bearing in sh, because a glob matching nothing is an error there — but it also
means a stale glob produces no hits, and no hits is indistinguishable from a clean repository. Rename
a directory under `client/` and the gate reports success having examined nothing, forever, in
exactly the silent way STANDARDS "Failures surface; nothing is swallowed" forbids. So the scopes
here are resolved first and a scope that matches nothing is itself a failure. `test:client`'s
`found=0` guard is the same instinct in sh; this is that guard made unavoidable.

Written to the 3.9 floor, stdlib only.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib  # noqa: E402  (sibling module; sys.path is set immediately above)

# Where a client lives. `client/*/lib` is a framework package's source, `apps/*/*/lib` an
# application's — test directories are deliberately outside both, since a test server's URL is not
# a call the product makes.
DART_LIB_SCOPES = ("client/*/lib", "apps/*/*/lib")

# THE ADMIN PANEL IS A CLIENT, and scoped exactly the way the Dart side is: source only, generated
# output excluded, tests excluded. react-admin is a browser application holding a session cookie,
# and `@supabase/supabase-js` is one `pnpm add` away and better documented than the Dart SDK — a
# panel that talked to the provider directly would break the same property in the same silent way.
TS_SRC_SCOPES = ("admin/src", "apps/*/*_admin/src")

# Check A reads dependency manifests, which are not under `lib/` or `src/`, so it scans separately.
PUBSPEC_ROOTS = ("client", "apps")
TS_PACKAGE_GLOBS = ("admin/package.json", "apps/*/*_admin/package.json")

# Generated code is exempt on both sides: it is a derived artifact, and editing it is already a
# defect the contract-sync gate catches (CLAUDE.md, "A tracked generated file is never
# hand-edited"). Dart marks it by directory, TypeScript by filename.
GENERATED_DIR = "/generated/"
GENERATED_TS_SUFFIX = ".generated.ts"

# The two files allowed to name the API base, and the reason check C can be strict everywhere else.
# `config.ts` is the TypeScript analogue of `zen_identity_config.dart`; it resolves to a relative
# `/api/v1` today, so the exemption belongs to the file's role rather than to what it contains.
DART_CONFIG_FILE = "zen_identity_config.dart"
TS_CONFIG_SUFFIX = "_admin/src/config.ts"

PROVIDER_SDK_DART = re.compile(
    r"^[ \t]{2}(supabase|gotrue|postgrest|realtime_client|storage_client|functions_client)"
    r"[a-z_]*[ \t]*:"
)
PROVIDER_SDK_TS = re.compile(
    r"^\s*\"(@supabase/[^\"]+|gotrue[^\"]*|postgrest[^\"]*|realtime-js|storage-js|functions-js)\"\s*:"
)
PROVIDER_SECRET = re.compile(
    r"supabase\.co|:54321|apikey|anon_key|service_role|SUPABASE_(URL|KEY)", re.IGNORECASE
)
ABSOLUTE_URL_DART = re.compile(r"['\"]https?://")
# The quote set gains the template literal's backtick, which is how a URL would most naturally be
# written in TypeScript. In sh this delimiter had to be built with `printf '\140'` rather than
# typed, because a literal backtick is command substitution before grep ever sees it.
ABSOLUTE_URL_TS = re.compile(r"['\"`]https?://")
DART_COMMENT = re.compile(r"^\s*//")
# JSDoc blocks mean a continuation line starting with `*` is comment too.
TS_COMMENT = re.compile(r"^\s*(//|/\*|\*)")


class StaleScope(Exception):
    """A scan pattern matched nothing — the gate cannot vouch for a tree it never read."""


@dataclass(frozen=True)
class Hit:
    path: str
    line: int
    text: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}:{self.text.strip()}"


def _read_lines(path: Path) -> "list[str]":
    # A file that is not valid UTF-8 is not Dart source; skipping it beats crashing the gate, and
    # `errors="replace"` keeps a stray byte from hiding the rest of an otherwise scannable file.
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def _sources(root: Path, scopes, patterns, exclude) -> "list[Path]":
    """Every source file under `scopes` matching `patterns`, minus `exclude`.

    Raises StaleScope if a scope pattern matches no directory — see the module docstring.
    """
    files: "list[Path]" = []
    for scope in scopes:
        dirs = [d for d in root.glob(scope) if d.is_dir()]
        if not dirs:
            raise StaleScope(f"scope '{scope}' matched no directory under {root}")
        for d in dirs:
            for pattern in patterns:
                files.extend(f for f in d.rglob(pattern) if f.is_file() and not exclude(f))
    return sorted(files)


def dart_sources(root: Path) -> "list[Path]":
    """Every Dart library source in scope, generated output excluded."""
    return _sources(
        root, DART_LIB_SCOPES, ("*.dart",), lambda f: GENERATED_DIR in f.as_posix()
    )


def ts_sources(root: Path) -> "list[Path]":
    """Every admin panel source in scope, generated output excluded."""
    return _sources(
        root, TS_SRC_SCOPES, ("*.ts", "*.tsx"), lambda f: f.name.endswith(GENERATED_TS_SUFFIX)
    )


def pubspecs(root: Path) -> "list[Path]":
    """Every Dart package manifest under the client and app trees."""
    found: "list[Path]" = []
    for name in PUBSPEC_ROOTS:
        tree = root / name
        if not tree.is_dir():
            raise StaleScope(f"tree '{name}/' does not exist under {root}")
        found.extend(p for p in tree.rglob("pubspec.yaml") if ".dart_tool" not in p.as_posix())
    if not found:
        raise StaleScope(f"no pubspec.yaml found under {PUBSPEC_ROOTS} in {root}")
    return sorted(found)


def ts_packages(root: Path) -> "list[Path]":
    """The admin scaffold's and each panel's package.json.

    Globbed rather than walked: `node_modules` is full of manifests that are somebody else's
    dependencies, and a recursive scan would report those as this repository's choices.
    """
    found: "list[Path]" = []
    for pattern in TS_PACKAGE_GLOBS:
        hits = [p for p in root.glob(pattern) if p.is_file()]
        if not hits:
            raise StaleScope(f"pattern '{pattern}' matched no package.json under {root}")
        found.extend(hits)
    return sorted(found)


def _scan(files: "list[Path]", root: Path, keep) -> "list[Hit]":
    hits: "list[Hit]" = []
    for f in files:
        rel = f.relative_to(root).as_posix()
        for n, text in enumerate(_read_lines(f), start=1):
            if keep(rel, text):
                hits.append(Hit(rel, n, text))
    return hits


def check_provider_sdk(root: Path) -> "list[Hit]":
    """A. No client, app, or admin package may depend on an identity-provider SDK."""
    dart = _scan(pubspecs(root), root, lambda rel, t: PROVIDER_SDK_DART.search(t) is not None)
    ts = _scan(ts_packages(root), root, lambda rel, t: PROVIDER_SDK_TS.search(t) is not None)
    return dart + ts


def check_provider_secret(root: Path) -> "list[Hit]":
    """B. No client or admin source may name a provider host or credential.

    The anon key is public by design, which is exactly why its absence is checked: shipping it
    looks harmless and is how a second door into the provider gets built.
    """
    hit = lambda rel, t: PROVIDER_SECRET.search(t) is not None  # noqa: E731
    return _scan(dart_sources(root), root, hit) + _scan(ts_sources(root), root, hit)


def check_absolute_url(root: Path) -> "list[Hit]":
    """C. No absolute URL literal in client or admin source, except the one compile-time base.

    Comments are exempt on both sides: `ZenClient(baseUrl: 'http://...')` in a doc block is
    documentation, not a call the product makes.
    """

    def keep_dart(rel: str, text: str) -> bool:
        if rel.endswith(DART_CONFIG_FILE) or DART_COMMENT.match(text):
            return False
        return ABSOLUTE_URL_DART.search(text) is not None

    def keep_ts(rel: str, text: str) -> bool:
        if rel.endswith(TS_CONFIG_SUFFIX) or TS_COMMENT.match(text):
            return False
        return ABSOLUTE_URL_TS.search(text) is not None

    return _scan(dart_sources(root), root, keep_dart) + _scan(ts_sources(root), root, keep_ts)


CHECKS = (
    (check_provider_sdk,
     "a client package depends on an identity-provider SDK:",
     "no client or admin package depends on a provider SDK"),
    (check_provider_secret,
     "client code names a provider host or credential:",
     "no provider host or credential in client or admin code"),
    (check_absolute_url,
     "client code hard-codes an absolute URL (the base is zenApiUrl / config.ts):",
     "the only base URL in client and admin code is the compile-time one"),
)


def main(root: "Path | None" = None) -> int:
    root = root or lib.repo_root()
    print("Checking the client/server boundary...")

    failed = False
    for check, bad, good in CHECKS:
        try:
            hits = check(root)
        except StaleScope as e:
            # Not "no violations found" — "nothing was examined". Reported as a failure precisely
            # because the sh version reported it as a pass.
            lib.fail(f"the scan is stale and checked nothing: {e}")
            failed = True
            continue
        if hits:
            lib.fail(bad, [str(h) for h in hits])
            failed = True
        else:
            lib.ok(good)

    print()
    if not failed:
        print("Boundary intact: the client talks to the jZen backend and nothing else.")
        return 0
    print("The client/server boundary is broken. The jZen backend is the ONLY thing a client")
    print("may call: it is where a session is minted, where the provider's credentials live,")
    print("and where roles are resolved. See STANDARDS 'The client talks to one server'.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
