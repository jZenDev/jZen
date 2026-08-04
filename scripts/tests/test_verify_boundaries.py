"""Fixture tests for the client/server boundary gate. Run by `task test:scripts`.

The sh version of this gate had no tests and could not easily have any: its checks were `grep`
pipelines against the real tree, so the only way to prove one *fires* was to plant a violation in
the repository and remember to take it out. That is why `test_stale_scope_is_a_failure` below
matters most — it is the regression test for the defect the conversion existed to close, and it is
the one assertion the sh gate could not make about itself at all.

Written to the 3.9 floor, stdlib only (`unittest`, not pytest).
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent

# The script is named with a hyphen because it is executed, not imported (matching
# `pick-device.py`); `scripts/lib.py` keeps an underscore because it is imported, not executed.
# Loading an executable script by path is the cost of that convention, and it is paid once, here.
#
# The sys.modules registration is not optional: @dataclass resolves its own module out of
# sys.modules to read annotations, so a module executed without being registered there raises
# AttributeError on the decorator rather than anywhere near the cause.
_spec = importlib.util.spec_from_file_location("verify_boundaries", SCRIPTS / "verify-boundaries.py")
vb = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = vb
_spec.loader.exec_module(vb)


CLEAN_PUBSPEC = """\
name: zen_core
environment:
  sdk: ^3.9.0
dependencies:
  meta: ^1.16.0
"""


CLEAN_PACKAGE_JSON = """\
{
  "name": "@jzen/admin-core",
  "dependencies": {
    "react-admin": "^5.4.0"
  }
}
"""


def build_tree(root: Path) -> None:
    """A minimally realistic client tree: Dart packages, an app client, and the admin panels.

    The admin side mirrors the real layout, because both TypeScript exemptions are path-shaped:
    `*.generated.ts` anywhere, and `config.ts` only under `*_admin/src`.
    """
    core = root / "client" / "zen_core"
    ident = root / "client" / "zen_identity"
    app = root / "apps" / "zen_demo" / "zen_demo_client"
    for pkg in (core, ident, app):
        (pkg / "lib").mkdir(parents=True)
        (pkg / "pubspec.yaml").write_text(CLEAN_PUBSPEC)
    (core / "lib" / "zen_core.dart").write_text("class ZenResult {}\n")
    (ident / "lib" / "zen_identity_config.dart").write_text(
        "const zenApiUrl = String.fromEnvironment('ZEN_API_URL');\n"
    )
    (app / "lib" / "main.dart").write_text("void main() {}\n")

    scaffold = root / "admin"
    panel = root / "apps" / "zen_demo" / "zen_demo_admin"
    for ts in (scaffold, panel):
        (ts / "src").mkdir(parents=True)
        (ts / "package.json").write_text(CLEAN_PACKAGE_JSON)
    (scaffold / "src" / "dataProvider.ts").write_text("export const dp = {};\n")
    (panel / "src" / "config.ts").write_text("export const apiBase = '/api/v1';\n")
    (panel / "src" / "api").mkdir()
    (panel / "src" / "api" / "schema.generated.ts").write_text("export type Paths = {};\n")


class BoundaryGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        build_tree(self.root)
        self.core = self.root / "client" / "zen_core"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_gate(self, root: Path) -> "tuple[int, str]":
        """`main()` with stdout captured, returning (exit code, output).

        Capturing is not incidental tidiness. Half these tests drive the gate over a deliberately
        broken fixture, so letting it print would spill "The client/server boundary is broken"
        into the output of a *passing* suite — a green run that reads like a red one is how a real
        failure later gets scrolled past.
        """
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = vb.main(root)
        return code, buf.getvalue()

    # ── the tree as it should be ────────────────────────────────────────────────────────────
    def test_clean_tree_passes(self) -> None:
        self.assertEqual([], vb.check_provider_sdk(self.root))
        self.assertEqual([], vb.check_provider_secret(self.root))
        self.assertEqual([], vb.check_absolute_url(self.root))
        code, out = self.run_gate(self.root)
        self.assertEqual(0, code)
        self.assertIn("Boundary intact", out)

    # ── A: the provider SDK, the violation this gate exists for ─────────────────────────────
    def test_provider_sdk_dependency_is_caught(self) -> None:
        (self.core / "pubspec.yaml").write_text(
            CLEAN_PUBSPEC + "  supabase_flutter: ^2.5.0\n"
        )
        hits = vb.check_provider_sdk(self.root)
        self.assertEqual(1, len(hits))
        self.assertIn("supabase_flutter", hits[0].text)
        code, out = self.run_gate(self.root)
        self.assertEqual(1, code)
        self.assertIn("depends on an identity-provider SDK", out)

    def test_other_provider_clients_are_caught(self) -> None:
        for dep in ("gotrue", "postgrest", "realtime_client", "storage_client", "functions_client"):
            with self.subTest(dep=dep):
                (self.core / "pubspec.yaml").write_text(CLEAN_PUBSPEC + f"  {dep}: ^1.0.0\n")
                self.assertEqual(1, len(vb.check_provider_sdk(self.root)))

    def test_a_transitive_nested_key_is_not_a_dependency(self) -> None:
        # Four-space indent is a nested key, not a top-level dependency entry. The sh version
        # anchored on exactly two spaces for this reason and the port must keep that.
        (self.core / "pubspec.yaml").write_text(
            CLEAN_PUBSPEC + "  some_pkg:\n    supabase_hosted: true\n"
        )
        self.assertEqual([], vb.check_provider_sdk(self.root))

    # ── B: hosts and credentials ────────────────────────────────────────────────────────────
    def test_provider_credential_is_caught(self) -> None:
        (self.core / "lib" / "zen_core.dart").write_text(
            "const key = 'anon_key-abc';\n"
        )
        self.assertEqual(1, len(vb.check_provider_secret(self.root)))

    def test_provider_host_is_caught_case_insensitively(self) -> None:
        (self.core / "lib" / "zen_core.dart").write_text("const h = 'XYZ.SUPABASE.CO';\n")
        self.assertEqual(1, len(vb.check_provider_secret(self.root)))

    def test_generated_dart_is_exempt(self) -> None:
        gen = self.core / "lib" / "generated"
        gen.mkdir()
        (gen / "msg.pb.dart").write_text("const k = 'service_role';\n")
        self.assertEqual([], vb.check_provider_secret(self.root))

    # ── C: absolute URLs ────────────────────────────────────────────────────────────────────
    def test_hardcoded_url_is_caught(self) -> None:
        (self.core / "lib" / "zen_core.dart").write_text(
            "final c = ZenClient(baseUrl: 'https://api.example.com');\n"
        )
        self.assertEqual(1, len(vb.check_absolute_url(self.root)))

    def test_url_in_a_comment_is_documentation(self) -> None:
        (self.core / "lib" / "zen_core.dart").write_text(
            "// final c = ZenClient(baseUrl: 'https://api.example.com');\n"
        )
        self.assertEqual([], vb.check_absolute_url(self.root))

    def test_the_one_config_file_may_name_the_base_url(self) -> None:
        cfg = self.root / "client" / "zen_identity" / "lib" / "zen_identity_config.dart"
        cfg.write_text("const zenApiUrl = 'https://api.jzen.dev';\n")
        self.assertEqual([], vb.check_absolute_url(self.root))

    # ── the admin panel is a client too ─────────────────────────────────────────────────────
    def test_admin_provider_sdk_dependency_is_caught(self) -> None:
        (self.root / "admin" / "package.json").write_text(
            CLEAN_PACKAGE_JSON.replace(
                '"react-admin": "^5.4.0"',
                '"react-admin": "^5.4.0",\n    "@supabase/supabase-js": "^2.45.0"',
            )
        )
        hits = vb.check_provider_sdk(self.root)
        self.assertEqual(1, len(hits))
        self.assertIn("@supabase/supabase-js", hits[0].text)

    def test_admin_scoped_provider_clients_are_caught(self) -> None:
        for dep in ("gotrue-js", "postgrest-js", "realtime-js", "storage-js", "functions-js"):
            with self.subTest(dep=dep):
                (self.root / "admin" / "package.json").write_text(
                    CLEAN_PACKAGE_JSON.replace(
                        '"react-admin": "^5.4.0"', f'"{dep}": "^2.0.0"'
                    )
                )
                self.assertEqual(1, len(vb.check_provider_sdk(self.root)))

    def test_admin_credential_is_caught(self) -> None:
        (self.root / "admin" / "src" / "dataProvider.ts").write_text(
            "const key = 'service_role';\n"
        )
        self.assertEqual(1, len(vb.check_provider_secret(self.root)))

    def test_tsx_is_in_scope(self) -> None:
        (self.root / "admin" / "src" / "Login.tsx").write_text(
            "export const url = 'https://xyz.supabase.co';\n"
        )
        self.assertEqual(1, len(vb.check_provider_secret(self.root)))

    def test_generated_typescript_is_exempt(self) -> None:
        gen = self.root / "apps" / "zen_demo" / "zen_demo_admin" / "src" / "api"
        (gen / "schema.generated.ts").write_text("const k = 'anon_key';\n")
        self.assertEqual([], vb.check_provider_secret(self.root))

    def test_template_literal_url_is_caught(self) -> None:
        """A backtick URL is the natural TypeScript spelling — and the one sh could not type."""
        (self.root / "admin" / "src" / "dataProvider.ts").write_text(
            "const base = `https://api.example.com/v1`;\n"
        )
        hits = vb.check_absolute_url(self.root)
        self.assertEqual(1, len(hits))
        self.assertIn("`https://", hits[0].text)

    def test_url_in_a_jsdoc_block_is_documentation(self) -> None:
        (self.root / "admin" / "src" / "dataProvider.ts").write_text(
            "/**\n * See `https://api.example.com` for the shape.\n */\n"
            "// const base = 'https://api.example.com';\n"
        )
        self.assertEqual([], vb.check_absolute_url(self.root))

    def test_the_admin_config_file_may_name_the_base_url(self) -> None:
        cfg = self.root / "apps" / "zen_demo" / "zen_demo_admin" / "src" / "config.ts"
        cfg.write_text("export const apiBase = 'https://api.jzen.dev';\n")
        self.assertEqual([], vb.check_absolute_url(self.root))

    def test_a_config_ts_outside_an_admin_panel_is_not_exempt(self) -> None:
        # The exemption is `*_admin/src/config.ts`, not any file called config.ts: the scaffold
        # under admin/src is schema-generic and names no API base.
        (self.root / "admin" / "src" / "config.ts").write_text(
            "export const base = 'https://api.example.com';\n"
        )
        self.assertEqual(1, len(vb.check_absolute_url(self.root)))

    # ── the defect this conversion closes ───────────────────────────────────────────────────
    def test_stale_scope_is_a_failure(self) -> None:
        """A scope that matches nothing must fail, not pass.

        This is the regression test for the sh version's `2>/dev/null … || true`: rename a
        directory under `client/` and every scan returned empty, which the gate read as a clean
        repository and reported green forever.
        """
        for pkg in (self.root / "client").iterdir():
            (pkg / "lib").rename(pkg / "src")  # the rename that used to go unnoticed

        with self.assertRaises(vb.StaleScope):
            vb.check_provider_secret(self.root)
        with self.assertRaises(vb.StaleScope):
            vb.check_absolute_url(self.root)

    def test_stale_scope_exits_nonzero(self) -> None:
        for pkg in (self.root / "client").iterdir():
            (pkg / "lib").rename(pkg / "src")
        code, out = self.run_gate(self.root)
        self.assertEqual(1, code)
        self.assertIn("stale", out)

    def test_missing_tree_is_a_failure(self) -> None:
        import shutil

        shutil.rmtree(self.root / "apps")
        with self.assertRaises(vb.StaleScope):
            vb.check_provider_sdk(self.root)
        self.assertEqual(1, self.run_gate(self.root)[0])

    def test_stale_typescript_scope_is_a_failure(self) -> None:
        """The admin half needs its own guard: the Dart scopes can be perfectly healthy.

        Without this, moving the panel out of `admin/src` would silently narrow the gate to Dart
        and every Dart scope would still resolve, so nothing would look wrong.
        """
        (self.root / "admin" / "src").rename(self.root / "admin" / "source")

        self.assertEqual([], vb.check_provider_sdk(self.root))  # Dart side unaffected
        with self.assertRaises(vb.StaleScope):
            vb.ts_sources(self.root)
        with self.assertRaises(vb.StaleScope):
            vb.check_provider_secret(self.root)
        self.assertEqual(1, self.run_gate(self.root)[0])

    def test_a_missing_admin_package_json_is_a_failure(self) -> None:
        (self.root / "admin" / "package.json").unlink()
        with self.assertRaises(vb.StaleScope):
            vb.ts_packages(self.root)


if __name__ == "__main__":
    unittest.main()
