"""Fixture tests for the applied-migrations-are-append-only gate. Run by `task test:scripts`.

Each test builds a throwaway git repository whose `main` holds the migrations, then edits the
working tree. The ones that matter most are about *not looking*: a missing base ref and a base
with no migration must exit non-zero rather than report a clean tree.

Written to the 3.9 floor, stdlib only (`unittest`, not pytest).
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent

_spec = importlib.util.spec_from_file_location("verify_migrations", SCRIPTS / "verify-migrations.py")
vm = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = vm
_spec.loader.exec_module(vm)

MIGRATION = "mod/src/main/resources/db/migration/V1__init.sql"
REPEATABLE = "mod/src/main/resources/db/migration/R__rls.sql"


def git(root: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=root, check=True, capture_output=True,
    )


def repo(files: "dict[str, bytes]") -> Path:
    root = Path(tempfile.mkdtemp())
    git(root, "init", "-q", "-b", "main")
    for name, data in files.items():
        (root / name).parent.mkdir(parents=True, exist_ok=True)
        (root / name).write_bytes(data)
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "base")
    return root


def run(root: Path, base: str = "main") -> int:
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try:
            return vm.main(["--root", str(root), "--base", base])
        except SystemExit as exit_:
            return int(exit_.code or 0)


class VerifyMigrations(unittest.TestCase):
    def test_unchanged_passes(self) -> None:
        self.assertEqual(run(repo({MIGRATION: b"CREATE TABLE a (x INT);\n"})), 0)

    def test_comment_only_edit_fails(self) -> None:
        root = repo({MIGRATION: b"/* old */\nCREATE TABLE a (x INT);\n"})
        (root / MIGRATION).write_bytes(b"/* new */\nCREATE TABLE a (x INT);\n")
        self.assertEqual(run(root), 1)

    def test_restoring_earlier_text_passes(self) -> None:
        root = repo({MIGRATION: b"/* old */\nSELECT 1;\n"})
        (root / MIGRATION).write_bytes(b"/* new */\nSELECT 1;\n")
        git(root, "commit", "-q", "-am", "edit")
        (root / MIGRATION).write_bytes(b"/* old */\nSELECT 1;\n")
        self.assertEqual(run(root), 0)

    def test_new_text_after_history_still_fails(self) -> None:
        root = repo({MIGRATION: b"/* old */\nSELECT 1;\n"})
        (root / MIGRATION).write_bytes(b"/* new */\nSELECT 1;\n")
        git(root, "commit", "-q", "-am", "edit")
        (root / MIGRATION).write_bytes(b"/* third */\nSELECT 1;\n")
        self.assertEqual(run(root), 1)

    def test_trailing_newline_edit_fails(self) -> None:
        root = repo({MIGRATION: b"SELECT 1;\n"})
        (root / MIGRATION).write_bytes(b"SELECT 1;")
        self.assertEqual(run(root), 1)

    def test_deleted_migration_fails(self) -> None:
        root = repo({MIGRATION: b"SELECT 1;\n"})
        (root / MIGRATION).unlink()
        self.assertEqual(run(root), 1)

    def test_added_migration_passes(self) -> None:
        root = repo({MIGRATION: b"SELECT 1;\n"})
        (root / MIGRATION.replace("V1__init", "V2__more")).write_bytes(b"SELECT 2;\n")
        self.assertEqual(run(root), 0)

    def test_repeatable_migration_may_change(self) -> None:
        root = repo({MIGRATION: b"SELECT 1;\n", REPEATABLE: b"-- a\n"})
        (root / REPEATABLE).write_bytes(b"-- b\n")
        self.assertEqual(run(root), 0)

    def test_base_without_migrations_fails(self) -> None:
        self.assertEqual(run(repo({"README.md": b"x\n"})), 1)

    def test_unknown_base_fails(self) -> None:
        self.assertEqual(run(repo({MIGRATION: b"SELECT 1;\n"}), base="origin/nope"), 1)


if __name__ == "__main__":
    unittest.main()
