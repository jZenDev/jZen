"""Fixture tests for the Jandex/no-Jackson module gate. Run by `task test:scripts`.

Mirrors `test_verify_boundaries.py`'s shape: build a minimal fixture tree, plant the violation
the gate exists to catch, assert it fires, and assert a stale scope fails rather than passes.

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

_spec = importlib.util.spec_from_file_location("verify_modules", SCRIPTS / "verify-modules.py")
vm = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = vm
_spec.loader.exec_module(vm)


POM_NO_BEANS_NO_JANDEX = """\
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>zen</groupId>
    <artifactId>zen-parent</artifactId>
    <version>0.1.0-SNAPSHOT</version>
  </parent>
  <artifactId>zen-leaf</artifactId>
</project>
"""

POM_WITH_JANDEX = """\
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>zen</groupId>
    <artifactId>zen-parent</artifactId>
    <version>0.1.0-SNAPSHOT</version>
  </parent>
  <artifactId>zen-beans</artifactId>
  <build>
    <plugins>
      <!-- jandex-maven-plugin mentioned in a comment must NOT count as the plugin being run -->
      <plugin>
        <groupId>io.smallrye</groupId>
        <artifactId>jandex-maven-plugin</artifactId>
        <version>3.2.7</version>
        <executions>
          <execution>
            <goals><goal>jandex</goal></goals>
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
"""

POM_CLEAN_JACKSON = """\
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <artifactId>zen-transport</artifactId>
  <dependencies>
    <!-- Client-side outbound Jackson (zen-identity's Supabase client) is legitimate. -->
    <dependency>
      <groupId>io.quarkus</groupId>
      <artifactId>quarkus-rest-client-jackson</artifactId>
    </dependency>
    <!-- A comment mentioning quarkus-rest-jackson must not be flagged either. -->
  </dependencies>
</project>
"""

POM_FORBIDDEN_JACKSON = """\
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <artifactId>zen-transport</artifactId>
  <dependencies>
    <dependency>
      <groupId>io.quarkus</groupId>
      <artifactId>quarkus-rest-jackson</artifactId>
    </dependency>
  </dependencies>
</project>
"""


def build_tree(root: Path) -> None:
    """A minimally realistic backend tree: a beanless leaf and a module with providers."""
    leaf = root / "server" / "zen-core"
    leaf.mkdir(parents=True)
    (leaf / "pom.xml").write_text(POM_NO_BEANS_NO_JANDEX)

    beans = root / "server" / "zen-transport"
    (beans / "src" / "main" / "java" / "zen" / "transport").mkdir(parents=True)
    (beans / "pom.xml").write_text(POM_WITH_JANDEX)
    (beans / "src" / "main" / "java" / "zen" / "transport" / "ZenTransportFilter.java").write_text(
        "package zen.transport;\n\nimport jakarta.ws.rs.ext.Provider;\n\n"
        "@Provider\npublic class ZenTransportFilter {}\n"
    )


class ModuleGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        build_tree(self.root)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_gate(self, root: Path) -> "tuple[int, str]":
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = vm.main(root)
        return code, buf.getvalue()

    # ── the tree as it should be ────────────────────────────────────────────────────────────
    def test_clean_tree_passes(self) -> None:
        self.assertEqual([], vm.check_jandex(self.root))
        self.assertEqual([], vm.check_no_server_jackson(self.root))
        code, out = self.run_gate(self.root)
        self.assertEqual(0, code)
        self.assertIn("Module rules intact", out)

    def test_a_beanless_module_needs_no_jandex(self) -> None:
        # zen-core / zen-proto in the real repo: no beans, correctly no jandex-maven-plugin.
        self.assertEqual([], vm.check_jandex(self.root))

    # ── A: a bean-bearing module with no jandex-maven-plugin ───────────────────────────────
    def test_missing_jandex_is_caught(self) -> None:
        pom = self.root / "server" / "zen-transport" / "pom.xml"
        pom.write_text(POM_NO_BEANS_NO_JANDEX.replace("zen-leaf", "zen-transport"))
        hits = vm.check_jandex(self.root)
        self.assertEqual(1, len(hits))
        self.assertIn("zen-transport", hits[0].path)

    def test_jandex_mentioned_only_in_a_comment_does_not_count(self) -> None:
        pom = self.root / "server" / "zen-transport" / "pom.xml"
        pom.write_text(
            POM_NO_BEANS_NO_JANDEX.replace("zen-leaf", "zen-transport").replace(
                "</project>",
                "<!-- jandex-maven-plugin should run here -->\n</project>",
            )
        )
        hits = vm.check_jandex(self.root)
        self.assertEqual(1, len(hits))

    def test_annotation_in_a_comment_is_not_a_bean(self) -> None:
        java = (
            self.root / "server" / "zen-transport" / "src" / "main" / "java"
            / "zen" / "transport" / "ZenTransportFilter.java"
        )
        java.write_text(
            "package zen.transport;\n\nimport jakarta.ws.rs.ext.Provider;\n\n"
            "// @Provider — not real\npublic class X {}\n"
        )
        pom = self.root / "server" / "zen-transport" / "pom.xml"
        pom.write_text(POM_NO_BEANS_NO_JANDEX.replace("zen-leaf", "zen-transport"))
        self.assertEqual([], vm.check_jandex(self.root))

    def test_missing_pom_is_caught(self) -> None:
        (self.root / "server" / "zen-transport" / "pom.xml").unlink()
        hits = vm.check_jandex(self.root)
        self.assertEqual(1, len(hits))
        self.assertIn("no pom.xml", hits[0].detail)

    # ── B: the forbidden server-side Jackson dependency ────────────────────────────────────
    def test_clean_jackson_setup_passes(self) -> None:
        pom = self.root / "server" / "zen-transport" / "pom.xml"
        pom.write_text(POM_CLEAN_JACKSON)
        self.assertEqual([], vm.check_no_server_jackson(self.root))

    def test_forbidden_jackson_dependency_is_caught(self) -> None:
        pom = self.root / "server" / "zen-transport" / "pom.xml"
        pom.write_text(POM_FORBIDDEN_JACKSON)
        hits = vm.check_no_server_jackson(self.root)
        self.assertEqual(1, len(hits))
        self.assertIn("zen-transport", hits[0].path)

    def test_client_jackson_is_not_confused_with_server_jackson(self) -> None:
        pom = self.root / "server" / "zen-transport" / "pom.xml"
        pom.write_text(POM_CLEAN_JACKSON)  # declares quarkus-rest-client-jackson only
        self.assertEqual([], vm.check_no_server_jackson(self.root))

    def test_target_directory_is_excluded(self) -> None:
        stale_pom = self.root / "server" / "zen-transport" / "target" / "classes" / "pom.xml"
        stale_pom.parent.mkdir(parents=True)
        stale_pom.write_text(POM_FORBIDDEN_JACKSON)
        hits = vm.check_no_server_jackson(self.root)
        self.assertEqual([], hits)

    # ── the defect this gate closes: passing having checked nothing ────────────────────────
    def test_stale_module_scope_is_a_failure(self) -> None:
        import shutil

        shutil.rmtree(self.root / "server")
        with self.assertRaises(vm.StaleScope):
            vm.check_jandex(self.root)
        code, out = self.run_gate(self.root)
        self.assertEqual(1, code)
        self.assertIn("stale", out)

    def test_stale_pom_scope_is_a_failure(self) -> None:
        for pom in self.root.rglob("pom.xml"):
            pom.unlink()
        with self.assertRaises(vm.StaleScope):
            vm.check_no_server_jackson(self.root)
        self.assertEqual(1, self.run_gate(self.root)[0])


if __name__ == "__main__":
    unittest.main()
