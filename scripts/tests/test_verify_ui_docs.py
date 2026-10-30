"""The UI guide gate must discover exports and reject missing documentation."""
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('ui_docs', Path(__file__).resolve().parents[1] / 'verify-ui-docs.py')
ui_docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui_docs)


class UiDocsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.package = self.root / ui_docs.PACKAGE
        (self.package / 'lib/src').mkdir(parents=True)
        (self.package / 'lib/zen_ui_widgets.dart').write_text("export 'src/widgets.dart' show PublicWidget;\n")
        (self.package / 'lib/src/widgets.dart').write_text(
            'class PublicWidget extends StatelessWidget {}\nclass PrivateWidget extends StatelessWidget {}\n')
        self.guide = self.package / 'README.md'
        self.guide.write_text('### PublicWidget\nA public control.\n```dart\nPublicWidget();\n```\n')

    def test_exported_widget_with_explanation_and_example_passes(self):
        self.assertEqual([], ui_docs.check(self.root))

    def test_missing_section_and_example_fail(self):
        self.guide.write_text('Mention PublicWidget elsewhere.\n')
        self.assertTrue(any('missing dedicated' in error for error in ui_docs.check(self.root)))
        self.guide.write_text('### PublicWidget\nDescription.\n')
        self.assertTrue(any('missing Dart usage' in error for error in ui_docs.check(self.root)))

    def test_example_in_another_section_does_not_count(self):
        self.guide.write_text('### PublicWidget\nDescription.\n### Other\n```dart\nPublicWidget();\n```\n')
        self.assertTrue(any('missing Dart usage' in error for error in ui_docs.check(self.root)))

    def test_new_export_and_missing_source_fail(self):
        entry = self.package / 'lib/zen_ui_widgets.dart'
        entry.write_text("export 'src/widgets.dart';\n")
        self.assertTrue(any('PrivateWidget' in error for error in ui_docs.check(self.root)))
        entry.write_text("export 'src/missing.dart';\n")
        self.assertTrue(any('Cannot inspect' in error for error in ui_docs.check(self.root)))

    def test_empty_scope_fails(self):
        (self.package / 'lib/zen_ui_widgets.dart').write_text('library;\n')
        self.assertTrue(any('No public widgets' in error for error in ui_docs.check(self.root)))

    def test_stop_hook_blocks_incomplete_guide_and_allows_reentry(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        original = Path(__file__).resolve().parents[1]
        for name in ('verify-ui-docs.py', 'ui-docs-stop-hook.py'):
            shutil.copy(original / name, scripts / name)
        self.guide.write_text('Undocumented.\n')
        def run(active):
            return subprocess.run([sys.executable, str(scripts / 'ui-docs-stop-hook.py')],
                                  input=json.dumps({'stop_hook_active': active}),
                                  capture_output=True, text=True)
        blocked = run(False)
        self.assertEqual(2, blocked.returncode)
        self.assertIn('PublicWidget', blocked.stderr)
        self.assertEqual(0, run(True).returncode)
