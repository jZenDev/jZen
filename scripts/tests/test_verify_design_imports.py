"""Fixture tests for the design-library import gate. Run by `task test:scripts`.

The assertions that matter most are the ones about *not looking*: a path that does not exist, a tree
with no package in it, a tree with no Dart file in it and a file that cannot be read must each exit
non-zero. A gate that reports green over a tree it never read is the defect `verify-boundaries.py` was
rewritten to close, and it is easy to reintroduce here, because a scan that finds no import looks
exactly like a scan of a clean tree.

The other half is the directive reader: every spelling of the forbidden import is caught, and the text
that merely *mentions* it (a comment, a doc example, a string) is not.

Written to the 3.9 floor, stdlib only (`unittest`, not pytest).
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent

# Loaded by path because the script is executed, not imported (hence its hyphen). Registered in
# sys.modules because @dataclass resolves its own module from there.
_spec = importlib.util.spec_from_file_location("verify_design_imports", SCRIPTS / "verify-design-imports.py")
vd = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = vd
_spec.loader.exec_module(vd)

MATERIAL = "package:flutter/material.dart"
CUPERTINO = "package:flutter/cupertino.dart"


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def uris(src: str) -> "list[str]":
    return [h.uri for h in vd.find_legacy_imports(src)]


class Directives(unittest.TestCase):
    def test_plain_imports_of_both_libraries(self) -> None:
        self.assertEqual(uris(f"import '{MATERIAL}';\nimport '{CUPERTINO}';\n"), [MATERIAL, CUPERTINO])

    def test_every_spelling_is_caught(self) -> None:
        spellings = [
            f"import '{MATERIAL}' show Colors;",
            f"import '{MATERIAL}' hide Colors;",
            f"import '{MATERIAL}' as m;",
            f"import '{MATERIAL}' deferred as m;",
            f'import "{MATERIAL}";',
            f"import r'{MATERIAL}';",
            f"export '{MATERIAL}';",
            f"export '{CUPERTINO}' show CupertinoIcons;",
            f"import\n    '{MATERIAL}'\n    show Colors;",
            f"import /* why */ '{MATERIAL}';",
            f"  import '{MATERIAL}';",
        ]
        for src in spellings:
            with self.subTest(src=src):
                self.assertEqual(len(uris(src)), 1)

    def test_deep_imports_of_the_sdk_libraries_are_caught(self) -> None:
        self.assertEqual(
            len(uris("import 'package:flutter/src/material/colors.dart';\n"
                     "import 'package:flutter/src/cupertino/button.dart';")),
            2,
        )

    def test_the_replacements_and_neighbours_are_clean(self) -> None:
        clean = [
            "import 'package:material_ui/material_ui.dart';",
            "import 'package:cupertino_ui/cupertino_ui.dart';",
            "import 'package:flutter/widgets.dart';",
            "import 'package:flutter/services.dart';",
            "import 'package:flutter/foundation.dart';",
            "import 'package:flutter_localizations/flutter_localizations.dart';",
            "import 'package:flutter/src/widgets/framework.dart';",
            "import 'package:flutter/materialish.dart';",
        ]
        for src in clean:
            with self.subTest(src=src):
                self.assertEqual(uris(src), [])

    def test_a_mention_is_not_an_import(self) -> None:
        mentions = [
            f"// import '{MATERIAL}';\n",
            f"/// ```dart\n/// import '{MATERIAL}';\n/// ```\nclass A {{}}\n",
            f"/* import '{MATERIAL}'; */\n",
            f"const s = \"import '{MATERIAL}';\";\n",
            f"const s = '''\nimport '{MATERIAL}';\n''';\n",
            f"const note = 'never {MATERIAL}';\n",
        ]
        for src in mentions:
            with self.subTest(src=src):
                self.assertEqual(uris(src), [])

    def test_a_method_named_import_is_not_a_directive(self) -> None:
        self.assertEqual(uris(f"void f() {{ loader.import '{MATERIAL}'; }}\n"), [])

    def test_line_numbers_are_the_real_ones(self) -> None:
        src = f"// one\n/* two\nthree */\nimport '{MATERIAL}';\n"
        self.assertEqual([h.line for h in vd.find_legacy_imports(src)], [4])

    def test_a_string_with_an_interpolated_string_does_not_hide_the_next_import(self) -> None:
        src = f"final s = '${{a['b']}}';\nimport '{MATERIAL}';\n"
        self.assertEqual(len(uris(src)), 1)

    def test_the_message_names_the_replacement(self) -> None:
        (m,) = vd.find_legacy_imports(f"import '{MATERIAL}';", "a.dart")
        (c,) = vd.find_legacy_imports(f"import '{CUPERTINO}';", "b.dart")
        self.assertIn("package:material_ui/material_ui.dart", str(m))
        self.assertIn("package:cupertino_ui/cupertino_ui.dart", str(c))
        self.assertIn("a.dart:1:", str(m))


class Fixture(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name).resolve()
        # Reported paths are relative to the working directory, as they are under `task`.
        self._cwd = os.getcwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, self._cwd)
        self.pkg = self.root / "demo"
        write(self.pkg / "pubspec.yaml", "name: demo\n")

    def dart(self, rel: str, text: str) -> Path:
        return write(self.pkg / rel, text)

    def run_gate(self, *paths: str) -> "tuple[int, str]":
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = vd.main(list(paths))
        return code, out.getvalue()


class Scanning(Fixture):
    def test_a_clean_tree_passes(self) -> None:
        self.dart("lib/a.dart", "import 'package:material_ui/material_ui.dart';\n")
        code, out = self.run_gate("demo")
        self.assertEqual(code, 0, out)
        self.assertIn("1 Dart files in 1 packages", out)

    def test_a_forbidden_import_fails_and_names_file_and_line(self) -> None:
        self.dart("lib/a.dart", f"\nimport '{MATERIAL}';\n")
        code, out = self.run_gate("demo")
        self.assertEqual(code, 1)
        self.assertIn("demo/lib/a.dart:2:", out)
        self.assertIn("material_ui", out)

    def test_tests_examples_and_tools_are_scanned_too(self) -> None:
        for rel in ("test/a_test.dart", "example/lib/main.dart", "integration_test/a.dart", "tool/gen.dart"):
            with self.subTest(rel=rel):
                self.dart(rel, f"import '{CUPERTINO}';\n")
                code, out = self.run_gate("demo")
                self.assertEqual(code, 1, out)
                self.assertIn(rel, out)
                (self.pkg / rel).unlink()

    def test_generated_code_is_scanned_too(self) -> None:
        self.dart("lib/src/l10n/generated/x.dart", f"import '{MATERIAL}';\n")
        self.assertEqual(self.run_gate("demo")[0], 1)

    def test_hidden_and_build_directories_are_not_scanned(self) -> None:
        self.dart("lib/a.dart", "class A {}\n")
        self.dart(".dart_tool/x.dart", f"import '{MATERIAL}';\n")
        self.dart("build/x.dart", f"import '{MATERIAL}';\n")
        self.assertEqual(self.run_gate("demo")[0], 0)

    def test_several_roots_are_all_read(self) -> None:
        other = self.root / "other"
        write(other / "pubspec.yaml", "name: other\n")
        write(other / "lib" / "b.dart", f"import '{MATERIAL}';\n")
        self.dart("lib/a.dart", "class A {}\n")
        code, out = self.run_gate("demo", "other")
        self.assertEqual(code, 1)
        self.assertIn("other/lib/b.dart", out)


class NotLooking(Fixture):
    """"We did not look" never shares an exit code with "clean"."""

    def test_a_missing_root_fails(self) -> None:
        code, out = self.run_gate("nowhere")
        self.assertEqual(code, 1)
        self.assertIn("not a directory", out)

    def test_a_root_with_no_package_fails(self) -> None:
        write(self.root / "bare" / "a.dart", "class A {}\n")
        code, out = self.run_gate("bare")
        self.assertEqual(code, 1)
        self.assertIn("no Dart package", out)

    def test_a_package_with_no_dart_file_fails(self) -> None:
        code, out = self.run_gate("demo")
        self.assertEqual(code, 1)
        self.assertIn("checked nothing", out)

    def test_one_bad_root_among_good_ones_still_fails(self) -> None:
        self.dart("lib/a.dart", "class A {}\n")
        code, _ = self.run_gate("demo", "nowhere")
        self.assertEqual(code, 1)

    def test_an_unreadable_file_fails(self) -> None:
        self.dart("lib/a.dart", "class A {}\n")
        (self.pkg / "lib" / "bad.dart").write_bytes(b"\xff\xfe\xfa not utf-8")
        code, out = self.run_gate("demo")
        self.assertEqual(code, 1)
        self.assertIn("could not be read", out)

    @unittest.skipIf(os.name == "nt", "symlinks need privileges on Windows")
    def test_a_file_that_is_a_symlink_out_of_the_root_fails(self) -> None:
        outside = write(self.root / "outside" / "x.dart", f"import '{MATERIAL}';\n")
        self.dart("lib/a.dart", "class A {}\n")
        os.symlink(outside, self.pkg / "lib" / "link.dart")
        code, out = self.run_gate("demo")
        self.assertEqual(code, 1)
        self.assertIn("outside", out)


if __name__ == "__main__":
    unittest.main()
