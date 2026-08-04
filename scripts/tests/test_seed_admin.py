"""Tests for the admin seeder. Run by `task test:scripts`.

Only the pure parts are covered, and deliberately so: registering needs a live backend and
promoting needs the Supabase container, so an end-to-end test here would be `task test:e2e` with
extra steps. What *is* tested is the whole reason this script stopped being sh — that a value
containing a quote or a backslash reaches JSON and SQL as data rather than as syntax.

Written to the 3.9 floor, stdlib only.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent

_spec = importlib.util.spec_from_file_location("seed_admin", SCRIPTS / "seed-admin.py")
sa = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = sa
_spec.loader.exec_module(sa)

# Values that broke the sh implementation, plus the ones that would have broken a naive fix.
HOSTILE = [
    "o'brien@example.com",           # apostrophe: closed the SQL literal
    'quote"inside@example.com',      # double quote: closed the JSON string
    "back\\slash@example.com",       # backslash: JSON escape
    "semi;colon@example.com",
    "a'; DROP TABLE users; --@x.io",
]


class RegisterBodyTest(unittest.TestCase):
    def test_body_is_valid_json_and_round_trips(self) -> None:
        for value in HOSTILE:
            with self.subTest(value=value):
                body = sa.register_body(value, value)
                parsed = json.loads(body.decode("utf-8"))
                self.assertEqual(value, parsed["email"])
                self.assertEqual(value, parsed["password"])

    def test_a_quote_does_not_terminate_the_json_string(self) -> None:
        """The sh version produced `{"email":"quote"inside@..."}` — not parseable."""
        body = sa.register_body('quote"inside@example.com', "pw").decode("utf-8")
        self.assertIn('\\"', body)
        self.assertEqual('quote"inside@example.com', json.loads(body)["email"])

    def test_body_is_bytes_for_urlopen(self) -> None:
        self.assertIsInstance(sa.register_body("a@b.c", "pw"), bytes)


class PromoteCommandTest(unittest.TestCase):
    def test_the_email_never_appears_in_the_sql(self) -> None:
        """The statement is a constant; the value travels beside it as a psql variable."""
        for value in HOSTILE:
            with self.subTest(value=value):
                self.assertNotIn(value, sa.PROMOTE_SQL)
                self.assertIn("email=" + value, sa.promote_command(value))

    def test_the_command_carries_no_sql_at_all(self) -> None:
        """The statement goes in on stdin, so `-c` must not appear anywhere in argv.

        `psql -c` does not run psql's own lexer, so `:'email'` is never expanded and the server
        rejects the statement with `syntax error at or near ":"`. Verified against the running
        container. This test is what keeps someone from "simplifying" it back to `-c`.
        """
        argv = sa.promote_command("a@b.c")
        self.assertNotIn("-c", argv)
        self.assertNotIn("-tAc", argv)
        self.assertFalse(any("UPDATE" in a for a in argv))

    def test_stdin_stays_open(self) -> None:
        """Without `docker exec -i`, psql reads an empty script and silently promotes nobody."""
        argv = sa.promote_command("a@b.c")
        self.assertIn("-i", argv[: argv.index(sa.DB_CONTAINER)])

    def test_the_sql_uses_quoting_interpolation_not_bare_substitution(self) -> None:
        # :'email' quotes and escapes; a bare :email would paste the value in unquoted.
        self.assertIn(":'email'", sa.PROMOTE_SQL)
        self.assertNotIn(":email", sa.PROMOTE_SQL.replace(":'email'", ""))

    def test_argv_is_a_list_so_nothing_reaches_a_shell(self) -> None:
        argv = sa.promote_command("a'; rm -rf /; --@x.io")
        self.assertIsInstance(argv, list)
        self.assertTrue(all(isinstance(a, str) for a in argv))
        self.assertEqual("docker", argv[0])

    def test_psql_flags_are_separate_argv_entries(self) -> None:
        argv = sa.promote_command("a@b.c")
        self.assertIn("-v", argv)
        self.assertIn("-tA", argv)
        self.assertEqual(argv[argv.index("-v") + 1], "email=a@b.c")


class ArgumentTest(unittest.TestCase):
    def test_defaults_match_the_documented_ones(self) -> None:
        self.assertEqual("admin@jzen.local", sa.DEFAULT_EMAIL)
        self.assertEqual("password123", sa.DEFAULT_PASSWORD)
        self.assertEqual(8085, sa.DEFAULT_PORT)


if __name__ == "__main__":
    unittest.main()
