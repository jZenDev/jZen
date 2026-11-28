"""The command `run:dev`'s teardown prints must exist in the repository that ran it.

Runs the real `task`, the real Taskfile.app.yml and the real scripts/run-dev.sh from a throwaway
framework checkout, included by a throwaway application. Every tool the rollup calls is a stub:
`supabase` records where it was called, `mvnw` and `flutter` start nothing, and `lsof` / `pkill`
find nothing, so the teardown cannot reach a process or a stack of anyone else's. Skipped when
go-task is not installed.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

STUBS = {
    "supabase": """#!/bin/sh
echo "$(pwd -P) supabase $*" >> "$STUB_LOG"
if [ "$*" = "status -o env" ]; then
  echo 'API_URL="http://127.0.0.1:1"'
  echo 'ANON_KEY="stub"'
fi
""",
    "flutter": "#!/bin/sh\n",
    "curl": "#!/bin/sh\n",
    "lsof": "#!/bin/sh\nexit 1\n",
    "pkill": "#!/bin/sh\nexit 1\n",
}
STUB_MVNW = """#!/bin/sh
case "$*" in *quarkus:dev*) exec sleep 60 ;; esac
"""


def write_executable(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    path.chmod(0o755)


@unittest.skipUnless(shutil.which("task"), "go-task is not installed")
class RunDevNamesAStopTaskThatExists(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base = Path(tmp.name).resolve()

        self.jzen = base / "jzen"
        (self.jzen / "scripts").mkdir(parents=True)
        shutil.copy(REPO / "Taskfile.app.yml", self.jzen)
        shutil.copy(REPO / "scripts" / "run-dev.sh", self.jzen / "scripts")
        write_executable(self.jzen / "server" / "mvnw", STUB_MVNW)

        self.app = base / "app"
        (self.app / "server").mkdir(parents=True)
        (self.app / "server" / "pom.xml").write_text("<project/>")
        (self.app / "client" / "demo_client").mkdir(parents=True)
        # generate:l10n, which run:dev calls first, discovers packages through git.
        subprocess.run(["git", "init", "-q"], cwd=self.app, check=True, capture_output=True)

        for name, body in STUBS.items():
            write_executable(base / "bin" / name, body)
        self.log = base / "supabase.log"
        self.env = {
            **os.environ,
            "PATH": f"{base / 'bin'}{os.pathsep}{os.environ['PATH']}",
            "STUB_LOG": str(self.log),
        }

    def task(self, *args: str) -> str:
        r = subprocess.run(
            ["task", *args], cwd=self.app, env=self.env,
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout

    def assert_printed_task_stops_the_stack(self, namespace: str) -> None:
        # The application's own Taskfile: the include, and a one-line alias per task.
        (self.app / "Taskfile.yml").write_text(
            f"version: '3'\nincludes:\n  {namespace}:\n"
            f"    taskfile: {self.jzen / 'Taskfile.app.yml'}\n"
            "    vars:\n      APP_NAME: demo\n"
            f"tasks:\n  run:dev:\n    cmds: [{{task: '{namespace}:run:dev'}}]\n"
        )
        out = self.task("run:dev")
        printed = re.search(r"stop it with 'task ([^' ]+)'", out)
        self.assertIsNotNone(printed, out)
        name = printed.group(1)

        listed = [t["name"] for t in json.loads(self.task("--list-all", "--json"))["tasks"]]
        self.assertIn(name, listed, f"teardown names '{name}', which the application cannot run")
        self.assertEqual(name, f"{namespace}:stop:supabase")

        self.log.unlink()
        self.task(name)
        self.assertEqual(self.log.read_text().splitlines(), [f"{self.app} supabase stop"])

    def test_under_the_usual_zen_include(self) -> None:
        self.assert_printed_task_stops_the_stack("zen")

    def test_under_an_include_of_another_name(self) -> None:
        self.assert_printed_task_stops_the_stack("framework")


if __name__ == "__main__":
    unittest.main()
