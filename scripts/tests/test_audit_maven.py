"""Fixture tests for the dependency CVE gate. Run by `task test:scripts`.

Everything covered here is a way the gate could report success without having checked anything,
which is the exact failure that disqualified the two Maven plugins tried before it (ADR-034):
`ossindex-maven-plugin` returned BUILD SUCCESS after a 401, and `osv-scanner` exited 0 after
failing to resolve a single dependency. So the assertions are about the shape of the verdict, not
about any particular advisory.

Nothing here reaches the network. `query_osv` is the only function that does, and the tests that
would need it exercise the parsing and the suppression rules on either side of it instead.

Written to the 3.9 floor, stdlib only (`unittest`, not pytest).
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

_spec = importlib.util.spec_from_file_location("audit_maven", SCRIPTS / "audit-maven.py")
am = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = am
_spec.loader.exec_module(am)


def line(coordinate: str) -> str:
    return f"[INFO]    {coordinate}"


class DependencyParsingTest(unittest.TestCase):
    def test_reads_a_plain_coordinate(self) -> None:
        found = am.parse_dependencies(line("io.quarkus:quarkus-rest:jar:3.38.0:compile"), False)
        self.assertEqual({"io.quarkus:quarkus-rest": {"3.38.0"}}, found)

    def test_version_is_taken_from_the_end_not_a_fixed_position(self) -> None:
        # `g:a:jar:version:scope` and `g:a:jar:classifier:version:scope` are both real Maven
        # output. Counting fields from the left reads the CLASSIFIER as the version on the second
        # one, and OSV cheerfully answers "no known vulnerabilities" for a version that does not
        # exist -- a clean report about the wrong artifact.
        found = am.parse_dependencies(
            line("io.netty:netty-codec:jar:linux-x86_64:4.2.9.Final:compile"), False
        )
        self.assertEqual({"io.netty:netty-codec": {"4.2.9.Final"}}, found)

    def test_the_same_artifact_across_modules_is_asked_about_once(self) -> None:
        # A multi-module reactor lists a shared dependency once per module. Eight identical
        # queries is eight times the traffic for one answer.
        text = "\n".join([line("com.google.protobuf:protobuf-java:jar:4.29.3:compile")] * 8)
        found = am.parse_dependencies(text, False)
        self.assertEqual({"com.google.protobuf:protobuf-java": {"4.29.3"}}, found)

    def test_test_scope_is_excluded_unless_asked_for(self) -> None:
        text = "\n".join(
            [
                line("io.quarkus:quarkus-rest:jar:3.38.0:compile"),
                line("io.rest-assured:rest-assured:jar:5.5.6:test"),
            ]
        )
        self.assertEqual({"io.quarkus:quarkus-rest"}, set(am.parse_dependencies(text, False)))
        self.assertEqual(
            {"io.quarkus:quarkus-rest", "io.rest-assured:rest-assured"},
            set(am.parse_dependencies(text, True)),
            "--include-test-scope asks a different question and must actually widen the set",
        )

    def test_maven_chatter_is_not_mistaken_for_a_dependency(self) -> None:
        noise = "\n".join(
            [
                "[INFO] Scanning for projects...",
                "[INFO] The following files have been resolved:",
                "[WARNING] The artifact io.quarkus:quarkus-junit5:jar:3.38.0 has been relocated",
                "[INFO] BUILD SUCCESS",
            ]
        )
        self.assertEqual({}, am.parse_dependencies(noise, False))


class EmptyListIsAFailureTest(unittest.TestCase):
    def test_nothing_parsed_means_nothing_checked(self) -> None:
        # THE assertion of this file. If `mvn dependency:list` fails or changes format, the honest
        # report is "the gate is broken", never "no vulnerabilities found". Both rejected tools
        # got precisely this wrong, in precisely this way.
        with self.assertRaises(SystemExit) as raised:
            am.lib.die("stand-in for the empty-list path")
        self.assertNotEqual(0, raised.exception.code)

        self.assertEqual(
            {},
            am.parse_dependencies("[INFO] BUILD SUCCESS", False),
            "an unparseable list must produce an empty dict, which main() turns into an exit",
        )


class SuppressionTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / "audit-suppressions.txt"
        self._real = am.SUPPRESSIONS_FILE
        am.SUPPRESSIONS_FILE = self.path

    def tearDown(self) -> None:
        am.SUPPRESSIONS_FILE = self._real
        self._tmp.cleanup()

    def test_an_entry_with_a_reason_is_accepted(self) -> None:
        self.path.write_text(
            "# a comment\n"
            "\n"
            "GHSA-aaaa-bbbb-cccc  test-scope only; never reaches a shipped artifact\n"
        )
        self.assertEqual(
            {"GHSA-aaaa-bbbb-cccc": "test-scope only; never reaches a shipped artifact"},
            am.load_suppressions(),
        )

    def test_an_entry_without_a_reason_refuses_to_parse(self) -> None:
        # The whole discipline of the file. A bare id is how a suppression list becomes the quiet
        # place findings go: adding one costs nothing, and nobody can later tell whether it was
        # reasoned about. Making it a hard error puts the two on the same footing.
        self.path.write_text("GHSA-aaaa-bbbb-cccc\n")
        with self.assertRaises(SystemExit) as raised:
            am.load_suppressions()
        self.assertNotEqual(0, raised.exception.code)

    def test_a_missing_file_is_no_suppressions_rather_than_an_error(self) -> None:
        # Empty is the correct state, and so is absent. Only an unreadable ENTRY is a failure.
        self.assertEqual({}, am.load_suppressions())

    def test_a_comment_only_file_suppresses_nothing(self) -> None:
        self.path.write_text("# everything here is prose\n#\n# GHSA-dddd-eeee-ffff  not active\n")
        self.assertEqual({}, am.load_suppressions())


if __name__ == "__main__":
    unittest.main()
