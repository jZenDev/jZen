#!/usr/bin/env python3
"""Create (or promote) a local admin user so you can log into the admin panel.

Registers via the running backend, then flips its `users.role` to `admin` in Postgres — roles live
in the table and are loaded by `RoleAugmentor`, never read from the JWT, so registering is not
enough on its own.

    scripts/seed-admin.py [--email E] [--password P] [--port N]

**Why this one script is Python while the runners beside it are sh** (STANDARDS "Scripting",
ADR-032): it supervises no process and traps no signals. What it does is *construct* structured
text — a JSON body and a SQL statement — which is Rule 3, the same rule that puts the gates here.
`admin.sh`, `demo.sh` and `stop.sh` stay sh because they background a server, wait on a port and
clean up on Ctrl-C, which is Rule 1.

That distinction is not academic here. The sh version built both payloads by string interpolation:

    -d "{\\"email\\":\\"${EMAIL}\\",\\"password\\":\\"${PASSWORD}\\"}"
    "UPDATE users SET role='admin' WHERE email='${EMAIL}' RETURNING email;"

A password containing a quote or a backslash produced malformed JSON, and an email containing an
apostrophe produced either a SQL error or a statement nobody wrote. Both are now built by things
that understand the format: `json.dumps` for the body, and psql's `:'var'` interpolation — which
quotes and escapes a value as a SQL literal — for the statement. Nothing runs through a shell
either, because `subprocess` is given an argument list rather than a command string.

Written to the 3.9 floor, stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib  # noqa: E402  (sibling module; sys.path is set immediately above)

DEFAULT_EMAIL = "admin@jzen.local"
DEFAULT_PASSWORD = "password123"
DEFAULT_PORT = 8085
DB_CONTAINER = "supabase_db_jzen"
ADMIN_URL = "http://localhost:5173"

# psql expands :'name' as a correctly quoted and escaped SQL literal, which is what makes this
# statement a template rather than a string to be assembled. The email never appears in it.
#
# THE STATEMENT GOES IN ON STDIN, NOT VIA -c, and that is not a style choice: `psql -c` sends its
# string to the server without running psql's own lexer, so :'email' is never expanded and the
# server rejects it with `syntax error at or near ":"`. Verified against the running
# supabase_db_jzen container both ways. Reading SQL from stdin is the path where interpolation
# happens, which is why the docker exec below needs -i.
PROMOTE_SQL = "UPDATE users SET role='admin' WHERE email = :'email' RETURNING email;"


def register_body(email: str, password: str) -> bytes:
    """The registration payload, built by a JSON encoder rather than by concatenation."""
    return json.dumps({"email": email, "password": password}).encode("utf-8")


def promote_command(email: str) -> "list[str]":
    """The argv for the promotion, with the email passed as a psql variable, not spliced in.

    Carries no SQL: the statement arrives on stdin (see PROMOTE_SQL). `-i` keeps docker exec's
    stdin open, without which psql reads an empty script and reports nothing at all.
    """
    return [
        "docker", "exec", "-i", DB_CONTAINER,
        "psql", "-U", "postgres", "-d", "postgres",
        "-v", "email=" + email,
        "-tA",
    ]


def backend_is_up(api: str) -> bool:
    try:
        with urllib.request.urlopen(api + "/api/v1/health", timeout=5) as r:
            return 200 <= r.status < 300
    except (urllib.error.URLError, OSError):
        return False


def register(api: str, email: str, password: str) -> None:
    """Register the user, tolerating an account that already exists.

    A failure here is deliberately not fatal — re-running the script for an existing account is
    the normal case. It is not swallowed either: the promotion below reports an empty result if no
    row exists, which is the check that actually matters.
    """
    req = urllib.request.Request(
        api + "/api/v1/auth/register",
        data=register_body(email, password),
        headers={"Content-Type": "application/json", "X-Zen-Transport": "json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=15).close()
    except (urllib.error.HTTPError, urllib.error.URLError, OSError):
        pass


def promote(email: str) -> str:
    out = subprocess.run(
        promote_command(email), input=PROMOTE_SQL, capture_output=True, text=True
    )
    if out.returncode != 0:
        lib.die(f"psql failed: {out.stderr.strip()}")
    return out.stdout.strip()


def main(argv: "list[str] | None" = None) -> int:
    p = argparse.ArgumentParser(
        description="Create or promote a local admin user for the admin panel.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--email", default=DEFAULT_EMAIL)
    p.add_argument("--password", default=DEFAULT_PASSWORD)
    p.add_argument("--port", type=int, default=int(os.environ.get("ZEN_APP_PORT", DEFAULT_PORT)))
    args = p.parse_args(argv)

    api = f"http://localhost:{args.port}"
    if not backend_is_up(api):
        lib.die(f"Backend not reachable at {api} (start it with scripts/admin.sh).")

    lib.info(f"Registering {args.email} (ignored if it already exists)...")
    register(api, args.email, args.password)

    lib.info(f"Promoting {args.email} to admin in the users table...")
    if not promote(args.email):
        lib.die(f"No users row for {args.email} (did registration succeed?).")

    lib.info(f"Admin ready. Log in at {ADMIN_URL}")
    lib.info(f"  email:    {args.email}")
    lib.info(f"  password: {args.password}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
