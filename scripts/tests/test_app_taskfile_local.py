"""Taskfile.app.yml for a Local application (ADR-073): the web refusal and the five native targets.

Runs the real `task` against a throwaway application tree that includes the repository's
Taskfile.app.yml, with a stub `flutter` (and `uname`, to play each host) first on PATH. The stub
records its arguments, so the test reads what the task would have asked Flutter to build without
compiling anything. Skipped when go-task is not installed.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TASKFILE_APP = REPO / "Taskfile.app.yml"
PLATFORM_DIRS = ("ios", "macos", "android", "windows", "linux")

STUB_FLUTTER = """#!/bin/sh
# `flutter config --list` is how build:runners reads the JDK; answer it with nothing.
if [ "$1" = config ]; then exit 0; fi
echo "flutter $*" >> "$STUB_LOG"
"""
STUB_UNAME = """#!/bin/sh
echo "$STUB_UNAME"
"""


@unittest.skipUnless(shutil.which("task"), "go-task is not installed")
class LocalApplicationTaskfile(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve() / "app"
        client = self.root / "apps" / "demo_local" / "demo_local_client"
        for d in PLATFORM_DIRS:
            (client / d).mkdir(parents=True)
        (self.root / "Taskfile.yml").write_text(
            f"version: '3'\nincludes:\n  zen:\n    taskfile: {TASKFILE_APP}\n    vars:\n"
            "      APP_NAME: demo_local\n      CLIENT_DIR: client\n      SERVER_DIR: server\n"
            "      DART_ROOTS: apps\n"
            "      APP_CLIENT_DIR: apps/demo_local/demo_local_client\n"
            "      APP_SERVER_MODULE: apps/demo_local/demo_local_server\n"
        )
        git = lambda *a: subprocess.run(["git", *a], cwd=self.root, check=True, capture_output=True)
        git("init", "-q")
        bindir = Path(tmp.name) / "bin"
        bindir.mkdir()
        for name, body in (("flutter", STUB_FLUTTER), ("uname", STUB_UNAME)):
            (bindir / name).write_text(body)
            (bindir / name).chmod(0o755)
        self.log = Path(tmp.name) / "flutter.log"
        self.env = {
            **os.environ,
            "PATH": f"{bindir}{os.pathsep}{os.environ['PATH']}",
            "STUB_LOG": str(self.log),
        }

    def task(self, *args: str, host: str = "Linux") -> subprocess.CompletedProcess:
        return subprocess.run(
            ["task", *args], cwd=self.root, env={**self.env, "STUB_UNAME": host},
            capture_output=True, text=True,
        )

    def flutter_calls(self) -> list[str]:
        return self.log.read_text().splitlines() if self.log.exists() else []

    def builds(self, host: str, *extra: str) -> list[str]:
        r = self.task("zen:build:runners", *extra, host=host)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return [c for c in self.flutter_calls() if c.startswith("flutter build")]

    def test_macos_host_builds_macos_ios_and_android(self) -> None:
        calls = self.builds("Darwin")
        self.assertEqual(len(calls), 3, calls)
        self.assertTrue(any(c.startswith("flutter build macos") for c in calls))
        self.assertTrue(any(c.startswith("flutter build ios --simulator") for c in calls))
        self.assertTrue(any(c.startswith("flutter build apk") for c in calls))

    def test_linux_host_builds_linux_and_android(self) -> None:
        calls = self.builds("Linux")
        self.assertEqual(len(calls), 2, calls)
        self.assertTrue(any(c.startswith("flutter build linux") for c in calls))
        self.assertTrue(any(c.startswith("flutter build apk") for c in calls))

    def test_windows_host_builds_windows_only(self) -> None:
        calls = self.builds("MINGW64_NT-10.0")
        self.assertEqual(len(calls), 1, calls)
        self.assertTrue(calls[0].startswith("flutter build windows"))

    def test_the_five_targets_are_covered_across_hosts(self) -> None:
        seen = set()
        for host in ("Darwin", "Linux", "MINGW64_NT-10.0"):
            self.log.unlink(missing_ok=True)
            seen.update(c.split()[2] for c in self.builds(host))
        self.assertEqual(seen, {"macos", "ios", "linux", "windows", "apk"})

    def test_no_server_means_no_api_url_or_redirect_and_never_web(self) -> None:
        calls = self.builds("Darwin", "ZEN_AUTH_REDIRECT_URI=demo://auth")
        for c in calls:
            self.assertNotIn("ZEN_API_URL", c)
            self.assertNotIn("ZEN_AUTH_REDIRECT_URI", c)
            self.assertNotIn("flutter build web", c)
            self.assertIn("--dart-define=ZEN_PLATFORM=", c)

    def test_app_with_a_server_still_gets_its_api_url(self) -> None:
        server = self.root / "apps" / "demo_local" / "demo_local_server"
        server.mkdir(parents=True)
        (server / "pom.xml").write_text("<project/>")
        calls = self.builds("Linux")
        self.assertTrue(all("ZEN_API_URL=" in c for c in calls), calls)

    def assert_refused_for_web(self, r: subprocess.CompletedProcess) -> None:
        self.assertNotEqual(r.returncode, 0, "the web target must be refused, not run")
        self.assertIn("ADR-073", r.stdout + r.stderr)
        self.assertEqual([c for c in self.flutter_calls() if " run" in c or "build web" in c], [])

    def test_run_client_refuses_web_by_device(self) -> None:
        self.assert_refused_for_web(self.task("zen:run:client", "DEVICE=chrome"))

    def test_run_client_refuses_web_by_platform(self) -> None:
        self.assert_refused_for_web(
            self.task("zen:run:client", "DEVICE=emulator-1", "CLIENT_PLATFORM=web"))

    def test_build_web_is_refused(self) -> None:
        self.assert_refused_for_web(self.task("zen:build:web"))

    def test_run_client_native_device_is_not_refused(self) -> None:
        r = self.task("zen:run:client", "DEVICE=macos")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        run = [c for c in self.flutter_calls() if c.startswith("flutter run -d macos")]
        self.assertEqual(len(run), 1, self.flutter_calls())
        self.assertIn("ZEN_PLATFORM=macos", run[0])


if __name__ == "__main__":
    unittest.main()
