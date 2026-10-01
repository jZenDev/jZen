"""Fixture tests for the one-widget-per-file gate. Run by `task test:scripts`.

The assertions that matter most are the ones about *not looking*: a path that does not exist, a
tree with no package in it, a file that cannot be read and a suppression that suppresses nothing
must each exit non-zero. A gate that reports green over a tree it never read is the defect
`verify-boundaries.py` was rewritten to close, and it is the easy one to reintroduce here, because
a scan that finds no widgets looks exactly like a scan of a clean tree.

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
_spec = importlib.util.spec_from_file_location("verify_widget_files", SCRIPTS / "verify-widget-files.py")
vw = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = vw
_spec.loader.exec_module(vw)


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def package(root: Path, name: str = "demo") -> Path:
    """A minimal Dart package: a pubspec beside a lib/."""
    pkg = root / name
    write(pkg / "pubspec.yaml", f"name: {name}\n")
    (pkg / "lib").mkdir(exist_ok=True)
    return pkg


class Fixture(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name).resolve()
        # Reported paths are relative to the working directory, as they are under `task`.
        self._cwd = os.getcwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, self._cwd)
        self.pkg = package(self.root)

    def lib(self, name: str, text: str) -> Path:
        return write(self.pkg / "lib" / name, text)

    def run_gate(self, *args: str) -> "tuple[int, str]":
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = vw.main(list(args) if args else ["demo"])
        return code, out.getvalue()


class TestRule(Fixture):
    def test_one_widget_passes(self) -> None:
        self.lib("a.dart", "class A extends StatelessWidget {\n  Widget build(c) => x;\n}\n")
        code, out = self.run_gate()
        self.assertEqual(code, 0, out)

    def test_two_widgets_in_one_file_fail_with_file_line_and_names(self) -> None:
        self.lib(
            "screen.dart",
            "import 'x.dart';\n\n"
            "class Screen extends StatelessWidget {}\n\n"
            "class Other extends StatelessWidget {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("demo/lib/screen.dart:3", out)
        self.assertIn("Screen (line 3)", out)
        self.assertIn("Other (line 5)", out)

    def test_stateful_widget_with_its_state_passes(self) -> None:
        self.lib(
            "counter.dart",
            "class Counter extends StatefulWidget {\n"
            "  State<Counter> createState() => _CounterState();\n}\n\n"
            "class _CounterState extends State<Counter> {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 0, out)

    def test_consumer_stateful_widget_with_its_consumer_state_passes(self) -> None:
        self.lib(
            "flow.dart",
            "class Flow extends ConsumerStatefulWidget {}\n\n"
            "class _FlowState extends ConsumerState<Flow> {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 0, out)

    def test_private_helper_widget_beside_a_widget_fails(self) -> None:
        self.lib(
            "screen.dart",
            "class Screen extends StatelessWidget {}\n\nclass _Helper extends StatelessWidget {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("_Helper", out)

    def test_two_stateful_widgets_fail_even_though_each_has_its_state(self) -> None:
        self.lib(
            "pair.dart",
            "class A extends StatefulWidget {}\nclass _AState extends State<A> {}\n"
            "class B extends StatefulWidget {}\nclass _BState extends State<B> {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("A (line 1) + _AState", out)
        self.assertIn("B (line 3) + _BState", out)

    def test_widget_families_beyond_the_two_core_ones_are_counted(self) -> None:
        for base in ("ConsumerWidget", "HookWidget", "HookConsumerWidget", "InheritedWidget",
                     "LeafRenderObjectWidget", "FormField<String>"):
            with self.subTest(base=base):
                self.lib("m.dart", f"class A extends {base} {{}}\nclass B extends {base} {{}}\n")
                code, _ = self.run_gate()
                self.assertEqual(code, 1)

    def test_modifiers_generics_bounds_and_prefixes_do_not_hide_a_widget(self) -> None:
        self.lib(
            "odd.dart",
            "abstract class A<T extends Foo<Bar>> extends StatelessWidget {}\n"
            "final class B extends material.StatelessWidget {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 1, out)
        self.assertIn("A (line 1)", out)
        self.assertIn("B (line 2)", out)

    def test_a_widget_that_extends_a_widget_in_another_file_is_counted(self) -> None:
        self.lib("base.dart", "abstract class ZenField extends StatelessWidget {}\n")
        self.lib("field.dart", "class A extends ZenField {}\nclass B extends ZenField {}\n")
        code, out = self.run_gate()
        self.assertEqual(code, 1, out)
        self.assertIn("lib/field.dart", out)
        self.assertNotIn("lib/base.dart", out)

    def test_non_widget_classes_are_outside_the_rule(self) -> None:
        self.lib(
            "notifiers.dart",
            "class A extends Notifier<int> {}\nclass B extends CustomPainter {}\n"
            "class C extends ChangeNotifier {}\nclass D {}\nclass E extends StatelessWidget {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 0, out)


class TestLexing(Fixture):
    def test_a_class_named_in_a_comment_or_string_is_not_a_class(self) -> None:
        self.lib(
            "doc.dart",
            "/// Compare `class Old extends StatelessWidget {}` in the docs.\n"
            "// class Gone extends StatelessWidget {}\n"
            "/* class Dead extends StatelessWidget {} /* nested */ class Dead2 extends StatelessWidget {} */\n"
            "const sample = 'class Fake extends StatelessWidget {}';\n"
            'const block = """\nclass Fake2 extends StatelessWidget {}\n""";\n'
            "const raw = r'class Fake3 extends StatelessWidget {}';\n"
            "class Real extends StatelessWidget {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 0, out)

    def test_a_nested_string_in_an_interpolation_does_not_end_the_string_early(self) -> None:
        self.lib(
            "interp.dart",
            "final s = 'a ${m['k']} class Fake extends StatelessWidget {} z';\n"
            "class Real extends StatelessWidget {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 0, out)

    def test_line_numbers_survive_blanked_comments_and_strings(self) -> None:
        self.lib(
            "lines.dart",
            "/* one\n   two\n   three */\nconst s = '''\na\nb''';\n"
            "class A extends StatelessWidget {}\nclass B extends StatelessWidget {}\n",
        )
        code, out = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("A (line 7)", out)
        self.assertIn("B (line 8)", out)


class TestScope(Fixture):
    TWO = "class A extends StatelessWidget {}\nclass B extends StatelessWidget {}\n"

    def test_a_generated_directory_is_skipped(self) -> None:
        self.lib("ok.dart", "class A extends StatelessWidget {}\n")
        self.lib("generated/messages.dart", self.TWO)
        self.lib("src/l10n/generated/loc.dart", self.TWO)
        code, out = self.run_gate()
        self.assertEqual(code, 0, out)

    def test_only_lib_is_scanned(self) -> None:
        self.lib("ok.dart", "class A extends StatelessWidget {}\n")
        write(self.pkg / "test" / "t.dart", self.TWO)
        write(self.pkg / "example" / "main.dart", self.TWO)
        code, out = self.run_gate()
        self.assertEqual(code, 0, out)

    def test_a_directory_of_packages_is_walked_and_a_hidden_one_is_not(self) -> None:
        second = package(self.root / "ws", "second")
        write(second / "lib" / "bad.dart", self.TWO)
        hidden = package(self.root / "ws" / ".dart_tool", "cache")
        write(hidden / "lib" / "bad.dart", self.TWO)
        self.lib("ok.dart", "class A extends StatelessWidget {}\n")
        code, out = self.run_gate("ws")
        self.assertEqual(code, 1)
        self.assertIn("ws/second/lib/bad.dart", out)
        self.assertNotIn(".dart_tool", out)

    def test_a_workspace_root_pubspec_without_a_lib_is_not_a_package(self) -> None:
        write(self.root / "pubspec.yaml", "name: root\nworkspace:\n  - demo\n")
        self.lib("ok.dart", "class A extends StatelessWidget {}\n")
        code, out = self.run_gate(".")
        self.assertEqual(code, 0, out)


class TestNotLooking(Fixture):
    def test_a_missing_path_is_a_failure_not_a_clean_tree(self) -> None:
        code, out = self.run_gate("nope")
        self.assertEqual(code, 1)
        self.assertIn("nope", out)

    def test_a_path_holding_no_package_is_a_failure(self) -> None:
        (self.root / "empty").mkdir()
        code, out = self.run_gate("empty")
        self.assertEqual(code, 1)
        self.assertIn("no Dart package", out)

    def test_a_package_with_no_dart_files_is_a_failure(self) -> None:
        code, out = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("checked nothing", out)

    def test_an_unreadable_file_is_a_failure(self) -> None:
        self.lib("good.dart", "class A extends StatelessWidget {}\n")
        (self.pkg / "lib" / "bad.dart").write_bytes(b"class A extends \xff\xfe {}\n")
        code, out = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("bad.dart", out)
        self.assertIn("could not be read", out)

    @unittest.skipIf(os.name == "nt" or (hasattr(os, "geteuid") and os.geteuid() == 0),
                     "permission bits are not enforced here")
    def test_a_file_with_no_read_permission_is_a_failure(self) -> None:
        locked = self.lib("locked.dart", "class A extends StatelessWidget {}\n")
        locked.chmod(0)
        self.addCleanup(locked.chmod, 0o644)
        code, out = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("locked.dart", out)

    def test_one_clean_path_does_not_vouch_for_a_missing_one(self) -> None:
        self.lib("ok.dart", "class A extends StatelessWidget {}\n")
        code, _ = self.run_gate("demo", "missing")
        self.assertEqual(code, 1)


class TestSuppressions(Fixture):
    TWO = "class A extends StatelessWidget {}\nclass B extends StatelessWidget {}\n"

    def sup(self, text: str) -> str:
        return str(write(self.root / "sup.txt", text))

    def test_a_suppressed_file_with_a_reason_passes(self) -> None:
        self.lib("pair.dart", self.TWO)
        code, out = self.run_gate(
            "--suppressions", self.sup("# comment\n\ndemo/lib/pair.dart  A is only ever B's slot\n"), "demo"
        )
        self.assertEqual(code, 0, out)

    def test_a_suppression_with_no_reason_is_an_error(self) -> None:
        self.lib("pair.dart", self.TWO)
        code, out = self.run_gate("--suppressions", self.sup("demo/lib/pair.dart\n"), "demo")
        self.assertEqual(code, 1)
        self.assertIn("has no reason", out)

    def test_a_suppression_matching_nothing_is_an_error(self) -> None:
        self.lib("ok.dart", "class A extends StatelessWidget {}\n")
        code, out = self.run_gate("--suppressions", self.sup("demo/lib/ok.dart  was two once\n"), "demo")
        self.assertEqual(code, 1)
        self.assertIn("matches no file with more than one widget", out)

    def test_a_suppression_does_not_cover_another_file(self) -> None:
        self.lib("pair.dart", self.TWO)
        self.lib("other.dart", self.TWO)
        code, out = self.run_gate("--suppressions", self.sup("demo/lib/pair.dart  argued\n"), "demo")
        self.assertEqual(code, 1)
        self.assertIn("other.dart", out)
        self.assertNotIn("pair.dart:", out)

    def test_a_missing_suppressions_file_is_a_failure(self) -> None:
        self.lib("ok.dart", "class A extends StatelessWidget {}\n")
        code, out = self.run_gate("--suppressions", str(self.root / "absent.txt"), "demo")
        self.assertEqual(code, 1)
        self.assertIn("could not be read", out)

    def test_the_shipped_suppressions_file_parses(self) -> None:
        shipped = SCRIPTS / "widget-files-suppressions.txt"
        self.assertTrue(shipped.is_file(), "scripts/widget-files-suppressions.txt is part of the gate")
        vw.load_suppressions(shipped)


if __name__ == "__main__":
    unittest.main()
