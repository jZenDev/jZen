"""Fixture tests for the documentation drift gate. Run by `task test:scripts`.

The fixtures are real git repositories, because both checks go through `git ls-files` and stubbing
that would test a different program than the one that ships. `git init` plus `git add` is enough —
`ls-files` reads the index, so nothing here needs a commit, an identity, or a default branch.

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

_spec = importlib.util.spec_from_file_location("verify_docs", SCRIPTS / "verify-docs.py")
vd = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = vd
_spec.loader.exec_module(vd)

LICENSE_TEXT = "Apache License\nVersion 2.0\n" + ("x" * 40 + "\n") * 20
VALID = {"build", "test", "run:demo", "verify:docs", "deploy:cloudrun"}


class DocsGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "LICENSE").write_text(LICENSE_TEXT)
        (self.root / "README.md").write_text("# jZen\n\nRun `task build` to build.\n")
        mod = self.root / "server" / "zen-core"
        mod.mkdir(parents=True)
        (mod / "LICENSE").write_text(LICENSE_TEXT)
        (mod / "README.md").write_text("# zen-core\n\nSee `task test`.\n")
        self.git("init", "-q")
        self.git("add", "-A")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def git(self, *args: str) -> None:
        subprocess.run(["git", *args], cwd=str(self.root), check=True, capture_output=True)

    def write(self, rel: str, text: str) -> None:
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        self.git("add", "-A")

    def run_gate(self, valid=VALID) -> "tuple[int, str]":
        """`main()` with stdout captured — see the boundary gate's suite for why."""
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = vd.main(self.root, valid=valid)
        return code, buf.getvalue()

    # ── the tree as it should be ────────────────────────────────────────────────────────────
    def test_clean_tree_passes(self) -> None:
        code, out = self.run_gate()
        self.assertEqual(0, code)
        self.assertIn("All README task references resolve.", out)
        self.assertIn("All 1 module LICENSE copies are byte-identical to root.", out)
        self.assertIn("Docs verified.", out)

    # ── 1: README task references ───────────────────────────────────────────────────────────
    def test_missing_task_is_caught(self) -> None:
        self.write("README.md", "Run `task run:all` to boot everything.\n")
        code, out = self.run_gate()
        self.assertEqual(1, code)
        self.assertIn("references 'task run:all'", out)
        self.assertIn("Docs verification FAILED.", out)

    def test_reference_in_a_code_fence_is_checked(self) -> None:
        self.write("README.md", "```\n    task nope:missing\n```\n")
        self.assertEqual(1, self.run_gate()[0])

    def test_a_flag_is_not_a_task(self) -> None:
        # `task --list` in prose is a flag, not a claim that a task named "--list" exists.
        self.write("README.md", "Run `task --list` to see everything.\n")
        self.assertEqual(0, self.run_gate()[0])

    def test_flags_are_skipped_and_the_task_is_checked(self) -> None:
        self.write("README.md", "```\ntask nope:gone --port\n```\n")
        code, out = self.run_gate()
        self.assertEqual(1, code)
        self.assertIn("'task nope:gone'", out)
        self.assertNotIn("--port", out)

    def test_a_numeric_argument_is_treated_as_a_task_name_KNOWN_QUIRK(self) -> None:
        """Faithfully ported, NOT fixed here — and locked so a fix is a deliberate act.

        The extraction captures a whole command line and then splits it, skipping only tokens that
        begin with `-`. A numeric argument survives that filter and is checked as though it were a
        task, so documenting `task run:demo --port 8085` in a code fence fails the gate with
        "references 'task 8085'".

        This is pre-existing sh behaviour, not something the port introduced — POSIX sh
        word-splits the unquoted `$refs`, and only `-*` is filtered. It is latent today because no
        README documents a task command with a numeric argument. Changing it would make the gate
        more permissive, which is a different kind of change from the vacuity guards this
        conversion exists to add, so it is recorded rather than smuggled in.
        """
        self.write("README.md", "```\ntask run:demo --port 8085\n```\n")
        code, out = self.run_gate()
        self.assertEqual(1, code)
        self.assertIn("references 'task 8085'", out)
        self.assertNotIn("'task run:demo'", out)  # the real task still resolves

    def test_bare_task_word_in_prose_is_not_a_reference(self) -> None:
        self.write("README.md", "The `task` runner orchestrates everything.\n")
        self.assertEqual(0, self.run_gate()[0])

    def test_a_nested_readme_is_in_scope(self) -> None:
        self.write("server/zen-core/README.md", "See `task nope:nested`.\n")
        code, out = self.run_gate()
        self.assertEqual(1, code)
        self.assertIn("server/zen-core/README.md", out)

    # ── 2: LICENSE copies ───────────────────────────────────────────────────────────────────
    def test_drifted_license_is_caught(self) -> None:
        self.write("server/zen-core/LICENSE", LICENSE_TEXT + "extra clause\n")
        code, out = self.run_gate()
        self.assertEqual(1, code)
        self.assertIn("DRIFTED", out)
        self.assertIn("server/zen-core/LICENSE", out)

    def test_a_one_byte_difference_is_drift(self) -> None:
        self.write("server/zen-core/LICENSE", LICENSE_TEXT[:-1])
        self.assertEqual(1, self.run_gate()[0])

    def test_license_count_is_reported(self) -> None:
        self.write("client/zen_ui/LICENSE", LICENSE_TEXT)
        _, out = self.run_gate()
        self.assertIn("All 2 module LICENSE copies", out)

    # ── refusing to pass vacuously ──────────────────────────────────────────────────────────
    def test_unreadable_task_list_refuses(self) -> None:
        """The one non-vacuity guard the sh version already had. It must survive the port."""
        code, out = self.run_gate(valid=set())
        self.assertEqual(1, code)
        self.assertIn("refusing to pass vacuously", out)

    def test_no_readmes_refuses(self) -> None:
        """Previously a silent pass: `for` over an empty list, then the success line."""
        for md in self.root.rglob("README.md"):
            md.unlink()
        self.git("add", "-A")
        with self.assertRaises(vd.StaleScope):
            vd.readme_refs(self.root)
        code, out = self.run_gate()
        self.assertEqual(1, code)
        self.assertIn("NO READMES", out)
        self.assertNotIn("All README task references resolve.", out)

    def test_no_module_licenses_refuses(self) -> None:
        """Previously printed 'All 0 module LICENSE copies are byte-identical to root.'"""
        (self.root / "server" / "zen-core" / "LICENSE").unlink()
        self.git("add", "-A")
        with self.assertRaises(vd.StaleScope):
            vd.check_licenses(self.root)
        code, out = self.run_gate()
        self.assertEqual(1, code)
        self.assertIn("NO LICENSES", out)
        self.assertNotIn("All 0 module LICENSE copies", out)

    def test_not_a_git_repository_fails(self) -> None:
        with tempfile.TemporaryDirectory() as plain:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = vd.main(Path(plain), valid=VALID)
            self.assertEqual(1, code)
            self.assertIn("Not a git repository", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
