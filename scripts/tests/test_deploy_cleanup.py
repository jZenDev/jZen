"""Tests for the post-deploy cleanup. Run by `task test:scripts`.

`gcloud` and `docker` are stubs on PATH holding their state in a JSON file, so the script is
exercised end to end — its real command lines, its real ordering — against a registry and a service
that a delete actually changes. That is what lets "a re-run changes nothing" be asserted rather than
claimed. What no test here can show is that a real repository agrees with the stub's JSON shapes;
the first run on a real repository is a `--dry-run`, and its before/after listing is that evidence.

Written to the 3.9 floor, stdlib only.
"""

from __future__ import annotations

import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

_spec = importlib.util.spec_from_file_location("deploy_cleanup", SCRIPTS / "deploy-cleanup.py")
dc = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = dc
_spec.loader.exec_module(dc)

NOW = dt.datetime(2026, 10, 23, 12, 0, tzinfo=dt.timezone.utc)
PROJECT, REGION, SERVICE, REPO = "proj", "europe-central2", "svc", "jzen"
PREFIX = "%s-docker.pkg.dev/%s/%s" % (REGION, PROJECT, REPO)
PACKAGE = "%s/%s" % (PREFIX, SERVICE)

STUB = '''#!%(python)s
import json, os, sys
path = os.environ["FAKE_STATE"]
with open(path) as f:
    state = json.load(f)
argv = sys.argv[1:]
state["calls"].append(os.path.basename(sys.argv[0]) + " " + " ".join(argv))
out = ""
if os.path.basename(sys.argv[0]) == "gcloud":
    if argv[:3] == ["run", "services", "describe"]:
        out = json.dumps(state["service"])
    elif argv[:3] == ["run", "revisions", "list"]:
        if state.get("fail_list"):
            print("PERMISSION_DENIED", file=sys.stderr)
            with open(path, "w") as f:
                json.dump(state, f)
            sys.exit(1)
        out = json.dumps(state["revisions"])
    elif argv[:3] == ["run", "revisions", "delete"]:
        if argv[3] in state.get("fail_delete", []):
            print("PERMISSION_DENIED", file=sys.stderr)
            with open(path, "w") as f:
                json.dump(state, f)
            sys.exit(1)
        state["revisions"] = [r for r in state["revisions"] if r["metadata"]["name"] != argv[3]]
    elif argv[:3] == ["artifacts", "repositories", "describe"]:
        out = json.dumps(state["repo"])
    elif argv[:3] == ["artifacts", "repositories", "set-cleanup-policies"]:
        policy_file = [a for a in argv if a.startswith("--policy=")][0].split("=", 1)[1]
        with open(policy_file) as pf:
            rules = json.load(pf)
        state["repo"]["cleanupPolicies"] = {r["name"]: r for r in rules}
        state["repo"]["cleanupPolicyDryRun"] = "--no-dry-run" not in argv
    elif argv[:3] == ["artifacts", "docker", "images"]:
        out = json.dumps(state["versions"])
else:
    if argv[:2] == ["image", "ls"]:
        out = "\\n".join(r for i in state["images"] for r in i["RepoTags"])
    elif argv[:2] == ["image", "inspect"]:
        out = json.dumps([i for i in state["images"] if set(i["RepoTags"]) & set(argv[2:])])
    elif argv[0] == "rmi":
        state["images"] = [i for i in state["images"] if argv[1] not in i["RepoTags"]]
with open(path, "w") as f:
    json.dump(state, f)
sys.stdout.write(out)
'''


def ago(days: float) -> str:
    return (NOW - dt.timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%S.123456Z")


def revision(name: str, age_days: float, digest: str) -> dict:
    return {"metadata": {"name": name, "creationTimestamp": ago(age_days)},
            "status": {"imageDigest": "%s@%s" % (PACKAGE, digest)}}


def deploy_versions(n: int, age_days: float, tag: str) -> list:
    """What one deploy leaves: a tagged index, the untagged image Cloud Run runs, an attestation."""
    return [
        {"package": PACKAGE, "version": "sha256:index%d" % n, "createTime": ago(age_days), "tags": [tag]},
        {"package": PACKAGE, "version": "sha256:image%d" % n, "createTime": ago(age_days), "tags": []},
        {"package": PACKAGE, "version": "sha256:att%d" % n, "createTime": ago(age_days), "tags": []},
    ]


# Ten deploys, newest first. With keep-versions 20 the newest 20 of 30 versions (deploys 1-6 and
# two of deploy 7) are kept; the rest are old enough to expire under a 30-day window.
AGES = [1, 3, 5, 20, 40, 60, 80, 100, 120, 140]


def scenario(serving=("r1",), staged=False, armed=False) -> dict:
    versions = []
    for i, age in enumerate(AGES, start=1):
        versions += deploy_versions(i, age, "abc%04d" % i)
    state = {
        "calls": [],
        "service": {"status": {"traffic": [{"revisionName": r, "percent": 100} for r in serving],
                               "latestReadyRevisionName": "r1"}},
        "revisions": [revision("r%d" % i, age, "sha256:image%d" % i) for i, age in enumerate(AGES, start=1)],
        "repo": {"cleanupPolicies": {}, "cleanupPolicyDryRun": False},
        "versions": versions,
        "images": [
            {"RepoTags": ["%s:abc000%d" % (PACKAGE, i)], "Created": ago(age) }
            for i, age in enumerate(AGES[:4], start=1)
        ] + [
            {"RepoTags": ["%s:latest" % PACKAGE], "Created": ago(200)},
            {"RepoTags": ["other.example/team/app:v1", "other.example/team/app:v0"], "Created": ago(300)},
        ],
    }
    if staged or armed:
        policy = dc.build_policy(20, 30, dc.DEFAULT_TAG_PREFIXES)
        state["repo"]["cleanupPolicies"] = {r["name"]: r for r in policy}
        state["repo"]["cleanupPolicyDryRun"] = not armed
    return state


class Harness(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        root = Path(self.dir.name)
        for tool in ("gcloud", "docker"):
            path = root / tool
            path.write_text(STUB % {"python": sys.executable})
            path.chmod(path.stat().st_mode | stat.S_IEXEC)
        self.state_file = root / "state.json"
        old = dict(os.environ)
        os.environ["PATH"] = "%s%s%s" % (root, os.pathsep, old["PATH"])
        os.environ["FAKE_STATE"] = str(self.state_file)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(old)))

    def load(self, state: dict) -> None:
        self.state_file.write_text(json.dumps(state))

    def state(self) -> dict:
        return json.loads(self.state_file.read_text())

    def run_cleanup(self, *extra: str, **opts):
        argv = ["--project", PROJECT, "--region", REGION, "--service", SERVICE, "--repo", REPO,
                "--keep-revisions", "3", "--revision-days", "14", "--keep-versions", "20",
                "--image-days", "30", "--docker-cache-hours", "168",
                "--revisions", opts.get("revisions", "on"), "--registry", opts.get("registry", "on"),
                "--docker", opts.get("docker", "on")] + list(extra)
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = dc.main(argv, now=NOW)
        return code, out.getvalue()

    def mutating(self, calls: list) -> list:
        marks = ("revisions delete", "set-cleanup-policies", "rmi ", "prune")
        return [c for c in calls if any(m in c for m in marks)]

    def test_failed_revision_delete_skips_registry_in_fail_and_warn_modes(self) -> None:
        for mode, expected in (("fail", 1), ("warn", 0)):
            with self.subTest(mode=mode):
                state = scenario(staged=True)
                state["fail_delete"] = ["r8"]
                self.load(state)
                code, out = self.run_cleanup("--on-failure", mode)
                calls = self.state()["calls"]
                self.assertEqual(expected, code)
                self.assertIn("the deploy itself succeeded", out)
                self.assertIn("revision step failed", out)
                self.assertTrue(any("revisions delete r8" in c for c in calls))
                self.assertFalse(any("artifacts repositories" in c or "artifacts docker" in c
                                     for c in calls))
                self.assertTrue(any("docker " in c for c in calls))

    def test_failed_revision_list_skips_registry_in_fail_and_warn_modes(self) -> None:
        for mode, expected in (("fail", 1), ("warn", 0)):
            with self.subTest(mode=mode):
                state = scenario(staged=True)
                state["fail_list"] = True
                self.load(state)
                code, out = self.run_cleanup("--on-failure", mode)
                calls = self.state()["calls"]
                self.assertEqual(expected, code)
                self.assertIn("the deploy itself succeeded", out)
                self.assertIn("PERMISSION_DENIED", out)
                self.assertFalse(any("artifacts repositories" in c or "artifacts docker" in c
                                     for c in calls))
                self.assertTrue(any("docker " in c for c in calls))


class PolicyTest(unittest.TestCase):
    def test_policy_keeps_newest_and_never_deletes_untagged_without_it(self) -> None:
        policy = dc.build_policy(20, 30, dc.DEFAULT_TAG_PREFIXES)
        keeps = [r for r in policy if r["action"]["type"] == "Keep"]
        self.assertEqual(20, keeps[0]["mostRecentVersions"]["keepCount"])
        self.assertTrue(any(r["action"]["type"] == "Delete" and r["condition"]["tagState"] == "UNTAGGED"
                            for r in policy))

    def test_a_policy_that_deletes_untagged_with_no_keep_is_refused(self) -> None:
        bare = [{"name": "x", "action": {"type": "Delete"},
                 "condition": {"tagState": "UNTAGGED", "olderThan": "86400s"}}]
        with self.assertRaises(dc.StepError):
            dc.assert_policy_safe(bare)
        with self.assertRaises(dc.StepError):
            dc.build_policy(0, 30, dc.DEFAULT_TAG_PREFIXES)

    def test_latest_is_never_matched_by_a_tag_prefix(self) -> None:
        for rule in dc.build_policy(20, 30, dc.DEFAULT_TAG_PREFIXES):
            for prefix in rule.get("condition", {}).get("tagPrefixes", []):
                self.assertFalse("latest".startswith(prefix))
        with self.assertRaises(dc.StepError):
            dc.build_policy(20, 30, ["l"])

    def test_changing_a_number_changes_the_rule_names(self) -> None:
        a = {r["name"] for r in dc.build_policy(20, 30, dc.DEFAULT_TAG_PREFIXES)}
        self.assertNotEqual(a, {r["name"] for r in dc.build_policy(21, 30, dc.DEFAULT_TAG_PREFIXES)})
        self.assertNotEqual(a, {r["name"] for r in dc.build_policy(20, 31, dc.DEFAULT_TAG_PREFIXES)})

    def test_revision_window_must_be_shorter_than_the_image_window(self) -> None:
        for revision_days in ("30", "31"):
            with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                dc.parse_args(["--project", "p", "--region", "r", "--service", "s", "--repo", "x",
                               "--keep-revisions", "3", "--revision-days", revision_days,
                               "--keep-versions", "20", "--image-days", "30",
                               "--docker-cache-hours", "1", "--revisions", "on", "--registry", "on",
                               "--docker", "on"])


class SelectionTest(unittest.TestCase):
    def test_the_newest_few_and_the_serving_revision_are_never_selected(self) -> None:
        revs = [revision("r%d" % i, age, "sha256:image%d" % i) for i, age in enumerate(AGES, start=1)]
        chosen = {r["metadata"]["name"] for r in dc.select_revisions(revs, {"r1"}, NOW, 14, 3)}
        self.assertEqual({"r4", "r5", "r6", "r7", "r8", "r9", "r10"}, chosen)

    def test_an_old_revision_that_serves_traffic_survives(self) -> None:
        """A `--no-traffic` deploy leaves an old revision serving; age alone must not condemn it."""
        revs = [revision("r%d" % i, age, "sha256:image%d" % i) for i, age in enumerate(AGES, start=1)]
        chosen = {r["metadata"]["name"] for r in dc.select_revisions(revs, {"r1", "r8"}, NOW, 14, 3)}
        self.assertNotIn("r8", chosen)
        self.assertNotIn("r1", chosen)

    def test_nothing_inside_the_window_is_selected(self) -> None:
        revs = [revision("r%d" % i, i, "sha256:image%d" % i) for i in range(1, 8)]
        self.assertEqual([], dc.select_revisions(revs, {"r1"}, NOW, 14, 3))


class DockerSelectionTest(unittest.TestCase):
    def test_keeps_two_newest_per_repository_and_never_touches_latest_or_strangers(self) -> None:
        images = [
            {"RepoTags": ["%s:a" % PACKAGE], "Created": ago(1)},
            {"RepoTags": ["%s:b" % PACKAGE], "Created": ago(2)},
            {"RepoTags": ["%s:c" % PACKAGE], "Created": ago(3)},
            {"RepoTags": ["%s:latest" % PACKAGE], "Created": ago(400)},
            {"RepoTags": ["other.example/team/app:v1"], "Created": ago(500)},
            {"RepoTags": ["%s-other/x/y/z:t" % PREFIX], "Created": ago(500)},
        ]
        self.assertEqual(["%s:c" % PACKAGE], dc.docker_victims(images, PREFIX, 2))


class EndToEndTest(Harness):
    def test_missing_revision_digest_does_not_arm_policy(self) -> None:
        state = scenario(staged=True)
        state["revisions"][0]["status"] = {}
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("no usable image digest", out)
        self.assertFalse(any("--no-dry-run" in c for c in self.state()["calls"]))

    def test_first_run_stages_the_policy_in_dry_run_and_does_not_arm_it(self) -> None:
        self.load(scenario())
        code, out = self.run_cleanup()
        self.assertEqual(0, code, out)
        calls = self.state()["calls"]
        self.assertTrue(any("set-cleanup-policies" in c and "--dry-run" in c for c in calls))
        self.assertFalse(any("--no-dry-run" in c for c in calls))
        self.assertIn("NOT ARMED", out)

    def test_a_staged_policy_is_armed_by_the_next_run_after_the_revisions_are_deleted(self) -> None:
        self.load(scenario(staged=True))
        code, out = self.run_cleanup()
        self.assertEqual(0, code, out)
        calls = self.state()["calls"]
        deletes = [i for i, c in enumerate(calls) if "revisions delete" in c]
        arm = [i for i, c in enumerate(calls) if "--no-dry-run" in c]
        self.assertEqual(7, len(deletes))
        self.assertEqual(1, len(arm))
        self.assertLess(max(deletes), arm[0], "every old revision goes before the policy is armed")
        repo = self.state()["repo"]
        self.assertFalse(repo["cleanupPolicyDryRun"])
        self.assertEqual({"r1", "r2", "r3"}, {r["metadata"]["name"] for r in self.state()["revisions"]})

    def test_a_rerun_changes_nothing(self) -> None:
        self.load(scenario(staged=True))
        self.assertEqual(0, self.run_cleanup()[0])
        first = self.state()
        n = len(first["calls"])
        code, out = self.run_cleanup()
        self.assertEqual(0, code, out)
        second = self.state()
        self.assertEqual([], [c for c in self.mutating(second["calls"][n:]) if "prune" not in c], out)
        for key in ("revisions", "repo", "versions", "images"):
            self.assertEqual(first[key], second[key], key)
        self.assertIn("already current", out)

    def test_dry_run_deletes_and_arms_nothing(self) -> None:
        self.load(scenario(staged=True))
        code, out = self.run_cleanup("--dry-run")
        self.assertEqual(0, code, out)
        self.assertEqual([], self.mutating(self.state()["calls"]))

    def test_a_policy_that_would_expire_a_running_image_is_not_armed(self) -> None:
        """With the revision step off, r8's old image is still run by a listed revision."""
        self.load(scenario(staged=True))
        code, out = self.run_cleanup(revisions="off")
        self.assertEqual(1, code, out)
        self.assertIn("still runs", out)
        self.assertTrue(self.state()["repo"]["cleanupPolicyDryRun"])

    def test_the_same_scenario_is_safe_once_the_old_revisions_are_deleted(self) -> None:
        self.load(scenario(staged=True))
        self.assertEqual(0, self.run_cleanup()[0])

    def test_an_armed_policy_that_has_become_hazardous_is_put_back_into_dry_run(self) -> None:
        state = scenario(armed=True, serving=("r1", "r8"))
        self.load(state)
        code, out = self.run_cleanup(revisions="off")
        self.assertEqual(1, code, out)
        self.assertTrue(self.state()["repo"]["cleanupPolicyDryRun"])

    def test_a_serving_old_revision_is_kept_and_so_is_its_image_check(self) -> None:
        self.load(scenario(staged=True, serving=("r1", "r8")))
        code, out = self.run_cleanup()
        self.assertEqual(1, code, "r8's image would expire, so the policy must not arm: " + out)
        self.assertIn("r8", {r["metadata"]["name"] for r in self.state()["revisions"]})
        self.assertTrue(self.state()["repo"]["cleanupPolicyDryRun"])

    def test_a_failed_delete_fails_loudly_and_says_the_deploy_succeeded(self) -> None:
        state = scenario(staged=True)
        state["fail_delete"] = ["r5"]
        self.load(state)
        code, out = self.run_cleanup()
        self.assertEqual(1, code, out)
        self.assertIn("the deploy itself succeeded", out)
        self.assertIn("PERMISSION_DENIED", out)

    def test_warn_mode_reports_the_same_failure_and_exits_zero(self) -> None:
        state = scenario(staged=True)
        state["fail_delete"] = ["r5"]
        self.load(state)
        code, out = self.run_cleanup("--on-failure", "warn")
        self.assertEqual(0, code, out)
        self.assertIn("PERMISSION_DENIED", out)

    def test_docker_removes_old_project_images_only(self) -> None:
        self.load(scenario(staged=True))
        self.assertEqual(0, self.run_cleanup(revisions="off", registry="off")[0])
        tags = [t for i in self.state()["images"] for t in i["RepoTags"]]
        self.assertIn("%s:abc0001" % PACKAGE, tags)
        self.assertIn("%s:abc0002" % PACKAGE, tags)
        self.assertNotIn("%s:abc0003" % PACKAGE, tags)
        self.assertNotIn("%s:abc0004" % PACKAGE, tags)
        self.assertIn("%s:latest" % PACKAGE, tags)
        self.assertIn("other.example/team/app:v1", tags)
        calls = self.state()["calls"]
        self.assertTrue(any("image prune -f" in c for c in calls))
        self.assertTrue(any("builder prune -f --filter until=168h" in c for c in calls))

    def test_every_step_can_be_switched_off(self) -> None:
        self.load(scenario(staged=True))
        code, out = self.run_cleanup(revisions="off", registry="off", docker="off")
        self.assertEqual(0, code, out)
        self.assertEqual([], self.state()["calls"])


if __name__ == "__main__":
    unittest.main()
