#!/usr/bin/env python3
"""Fail if a client package reaches past the jZen backend. Run by `task verify:boundaries`.

WHAT this enforces and WHY it is a gate is in the Taskfile's `verify:boundaries` summary, which is
the operator-facing contract and stays there (`task verify:boundaries --summary`). This docstring
covers only HOW, and the two things about the how that are worth knowing.

**Why this is Python and the launchers beside it are sh** (STANDARDS "Scripting", ADR-029): the
three checks below read source and return a verdict, which is Rule 3 work. In sh they were a nest
of `grep` pipelines feeding an `awk` program that stripped Dart comments by field-splitting on `:`
— correct, but not correct *by inspection*, which is the property a gate most needs.

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

# Check A reads dependency manifests, which are not under `lib/`, so it scans whole trees.
PUBSPEC_ROOTS = ("client", "apps")

# Generated Dart is exempt everywhere: it is a derived artifact, and editing it is already a defect
# the contract-sync gate catches (CLAUDE.md, "A tracked generated file is never hand-edited").
GENERATED = "/generated/"

# The one file allowed to name the API base, and the reason check C can be strict everywhere else.
CONFIG_FILE = "zen_identity_config.dart"

PROVIDER_SDK = re.compile(
    r"^[ \t]{2}(supabase|gotrue|postgrest|realtime_client|storage_client|functions_client)"
    r"[a-z_]*[ \t]*:"
)
PROVIDER_SECRET = re.compile(
    r"supabase\.co|:54321|apikey|anon_key|service_role|SUPABASE_(URL|KEY)", re.IGNORECASE
)
ABSOLUTE_URL = re.compile(r"['\"]https?://")
DART_COMMENT = re.compile(r"^\s*//")


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


def dart_sources(root: Path) -> "list[Path]":
    """Every Dart library source in scope, generated output excluded.

    Raises StaleScope if a scope pattern matches no directory — see the module docstring.
    """
    files: "list[Path]" = []
    for scope in DART_LIB_SCOPES:
        dirs = [d for d in root.glob(scope) if d.is_dir()]
        if not dirs:
            raise StaleScope(f"scope '{scope}' matched no directory under {root}")
        for d in dirs:
            files.extend(
                f for f in d.rglob("*.dart") if GENERATED not in f.as_posix() and f.is_file()
            )
    return sorted(files)


def pubspecs(root: Path) -> "list[Path]":
    """Every package manifest under the client and app trees."""
    found: "list[Path]" = []
    for name in PUBSPEC_ROOTS:
        tree = root / name
        if not tree.is_dir():
            raise StaleScope(f"tree '{name}/' does not exist under {root}")
        found.extend(p for p in tree.rglob("pubspec.yaml") if ".dart_tool" not in p.as_posix())
    if not found:
        raise StaleScope(f"no pubspec.yaml found under {PUBSPEC_ROOTS} in {root}")
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
    """A. No client or app package may depend on an identity-provider SDK."""
    return _scan(pubspecs(root), root, lambda rel, text: PROVIDER_SDK.search(text) is not None)


def check_provider_secret(root: Path) -> "list[Hit]":
    """B. No client library source may name a provider host or credential.

    The anon key is public by design, which is exactly why its absence is checked: shipping it
    looks harmless and is how a second door into the provider gets built.
    """
    return _scan(
        dart_sources(root), root, lambda rel, text: PROVIDER_SECRET.search(text) is not None
    )


def check_absolute_url(root: Path) -> "list[Hit]":
    """C. No absolute URL literal in client library code, except the one compile-time base URL.

    Comments are exempt: `ZenClient(baseUrl: 'http://...')` in a doc block is documentation, not a
    call the product makes.
    """

    def keep(rel: str, text: str) -> bool:
        if rel.endswith(CONFIG_FILE) or DART_COMMENT.match(text):
            return False
        return ABSOLUTE_URL.search(text) is not None

    return _scan(dart_sources(root), root, keep)


CHECKS = (
    (check_provider_sdk,
     "a client package depends on an identity-provider SDK:",
     "no client package depends on a provider SDK"),
    (check_provider_secret,
     "client code names a provider host or credential:",
     "no provider host or credential in client code"),
    (check_absolute_url,
     "client code hard-codes an absolute URL (the base URL is zenApiUrl):",
     "the only base URL in client code is the compile-time zenApiUrl"),
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
