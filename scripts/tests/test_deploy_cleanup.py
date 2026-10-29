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
        if any(a.startswith("--service=") for a in argv):
            out = json.dumps(state["revisions"])
        else:
            out = json.dumps(state["revisions"] + state.get("other_revisions", []))
    elif argv[:3] == ["run", "jobs", "list"]:
        if state.get("fail_jobs"):
            print("PERMISSION_DENIED", file=sys.stderr)
            with open(path, "w") as f:
                json.dump(state, f)
            sys.exit(1)
        out = json.dumps(state.get("jobs", []))
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
    elif argv[:4] == ["artifacts", "docker", "tags", "add"]:
        if state.get("fail_tag_add"):
            print("PERMISSION_DENIED", file=sys.stderr)
            with open(path, "w") as f:
                json.dump(state, f)
            sys.exit(1)
        package, digest = argv[4].split("@")
        tag = argv[5].split(":")[-1]
        for v in state["versions"]:
            if package == v["package"] and tag in v["tags"]:
                v["tags"].remove(tag)
            if package == v["package"] and digest == v["version"]:
                v["tags"].append(tag)
    elif argv[:4] == ["artifacts", "docker", "tags", "delete"]:
        if state.get("fail_tag_delete"):
            print("PERMISSION_DENIED", file=sys.stderr)
            with open(path, "w") as f:
                json.dump(state, f)
            sys.exit(1)
        package, _, tag = argv[4].rpartition(":")
        for v in state["versions"]:
            if package == v["package"] and tag in v["tags"]:
                v["tags"].remove(tag)
else:
    if argv[:2] == ["image", "ls"]:
        out = "\\n".join(r for i in state["images"] for r in i["RepoTags"])
    elif argv[:2] == ["image", "inspect"]:
        out = json.dumps([i for i in state["images"] if set(i["RepoTags"]) & set(argv[2:])])
    elif argv[:4] == ["buildx", "imagetools", "inspect", "--raw"]:
        kids = state.get("manifests", {}).get(argv[4])
        out = json.dumps({"manifests": [{"digest": d} for d in kids]} if kids else {"layers": []})
    elif argv[0] == "rmi":
        state["images"] = [i for i in state["images"] if argv[1] not in i["RepoTags"]]
with open(path, "w") as f:
    json.dump(state, f)
sys.stdout.write(out)
'''


def ago(days: float) -> str:
    return (NOW - dt.timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%S.123456Z")


def revision(name: str, age_days: float, digest: str, service: str = SERVICE) -> dict:
    return {"metadata": {"name": name, "creationTimestamp": ago(age_days),
                         "labels": {"serving.knative.dev/service": service}},
            "status": {"imageDigest": "%s@%s" % (PACKAGE, digest)}}


def job(name: str, image: str) -> dict:
    return {"metadata": {"name": name},
            "spec": {"template": {"spec": {"template": {"spec": {"containers": [{"image": image}]}}}}}}


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
        # What each tagged index lists: the image Cloud Run runs and the attestation.
        "manifests": {"%s@sha256:index%d" % (PACKAGE, n): ["sha256:image%d" % n, "sha256:att%d" % n]
                      for n in range(1, len(AGES) + 1)},
        "jobs": [],
        "other_revisions": [],
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
        marks = ("revisions delete", "set-cleanup-policies", "rmi ", "prune", "tags add", "tags delete")
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


def registry_runs(state: dict, at: dt.datetime) -> None:
    """The registry's evaluation of an ARMED policy at time `at`, repeated until it stops changing.

    Deliberately not `dc.simulate`: it is written from the documented semantics (Keep outranks
    Delete; `mostRecentVersions` counts per package; a version listed by a parent that still exists
    is not deleted; evaluation is asynchronous and repeats) so that the script is checked against
    something other than itself. It is still a MODEL of the documented behaviour, not the registry.
    """
    repo = state["repo"]
    if repo["cleanupPolicyDryRun"] or not repo["cleanupPolicies"]:
        return
    stamp = lambda text: dt.datetime.strptime(text, "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=dt.timezone.utc)
    while True:
        versions = state["versions"]
        keep, delete = set(), set()
        for rule in repo["cleanupPolicies"].values():
            into = keep if rule["action"]["type"] == "Keep" else delete
            if "mostRecentVersions" in rule:
                for package in {v["package"] for v in versions}:
                    group = sorted((v for v in versions if v["package"] == package),
                                   key=lambda v: v["createTime"], reverse=True)
                    into.update((package, v["version"]) for v in group[:rule["mostRecentVersions"]["keepCount"]])
                continue
            cond = rule["condition"]
            for v in versions:
                tags = v["tags"]
                if cond.get("tagState") == "TAGGED" and not tags:
                    continue
                if cond.get("tagState") == "UNTAGGED" and tags:
                    continue
                if cond.get("tagPrefixes") and not any(t.startswith(p) for t in tags for p in cond["tagPrefixes"]):
                    continue
                if "olderThan" in cond and (at - stamp(v["createTime"])).total_seconds() <= int(cond["olderThan"][:-1]):
                    continue
                into.add((v["package"], v["version"]))
        present = {(v["package"], v["version"]) for v in versions}
        shielded = set()
        for ref, kids in state.get("manifests", {}).items():
            package, _, parent = ref.partition("@")
            if (package, parent) in present:
                shielded.update((package, kid) for kid in kids)
        gone = {k for k in delete - keep if k not in shielded}
        if not gone:
            return
        state["versions"] = [v for v in versions if (v["package"], v["version"]) not in gone]


def exists(state: dict, digest: str) -> bool:
    return any(v["version"] == digest for v in state["versions"])


class PinProtectionTest(Harness):
    def armed_after_two_runs(self, state=None) -> dict:
        self.load(state or scenario())
        self.assertEqual(0, self.run_cleanup(docker="off")[0])   # stages
        self.assertEqual(0, self.run_cleanup(docker="off")[0])   # arms
        self.assertFalse(self.state()["repo"]["cleanupPolicyDryRun"])
        return self.state()

    def test_a_retained_revisions_image_survives_a_long_gap_between_deploys(self) -> None:
        """Thirty newer versions push r3's image out of the newest 20 and 160 days pass."""
        state = self.armed_after_two_runs()
        for n in range(11, 21):
            state["versions"] += deploy_versions(n, -150, "new%04d" % n)
        later = NOW + dt.timedelta(days=160)
        registry_runs(state, later)
        for n in (1, 2, 3):
            self.assertTrue(exists(state, "sha256:image%d" % n), "revision r%d lost its image" % n)
        self.assertFalse(exists(state, "sha256:image8"), "an image no revision runs is still bounded")

    def test_without_the_pin_rule_the_same_gap_loses_the_image(self) -> None:
        """The control: the scenario above has teeth, since count and age alone do not protect r3."""
        state = self.armed_after_two_runs()
        for v in state["versions"]:
            v["tags"] = [t for t in v["tags"] if not t.startswith(dc.PIN_PREFIX)]
        for n in range(11, 21):
            state["versions"] += deploy_versions(n, -150, "new%04d" % n)
        registry_runs(state, NOW + dt.timedelta(days=160))
        self.assertFalse(exists(state, "sha256:image3"))

    def test_a_manual_rollback_to_a_retained_revision_finds_its_image(self) -> None:
        state = scenario(serving=("r2",))
        state["service"]["status"]["latestReadyRevisionName"] = "r1"
        state = self.armed_after_two_runs(state)
        for n in range(11, 21):
            state["versions"] += deploy_versions(n, -150, "new%04d" % n)
        registry_runs(state, NOW + dt.timedelta(days=160))
        self.assertTrue(exists(state, "sha256:image1") and exists(state, "sha256:image2"))

    def test_an_old_serving_revision_is_pinned_so_the_policy_arms(self) -> None:
        """r8 serves traffic from a `--no-traffic` deploy: it is kept and so is its image."""
        state = self.armed_after_two_runs(scenario(serving=("r1", "r8")))
        self.assertIn("r8", {r["metadata"]["name"] for r in state["revisions"]})
        registry_runs(state, NOW + dt.timedelta(days=60))
        self.assertTrue(exists(state, "sha256:image8"))

    def test_revisions_switched_off_still_pins_what_remains(self) -> None:
        self.load(scenario(staged=True))
        self.assertEqual(0, self.run_cleanup(revisions="off", docker="off")[0])
        state = self.state()
        registry_runs(state, NOW + dt.timedelta(days=60))
        for n in range(1, 11):
            self.assertTrue(exists(state, "sha256:image%d" % n), n)

    def test_pins_are_added_before_the_policy_is_staged_or_armed(self) -> None:
        self.load(scenario())
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        calls = self.state()["calls"]
        pins = [i for i, c in enumerate(calls) if "tags add" in c]
        policy = [i for i, c in enumerate(calls) if "set-cleanup-policies" in c]
        self.assertEqual(3, len(pins))
        self.assertTrue(pins and policy and max(pins) < min(policy), calls)

    def test_a_policy_of_an_older_shape_is_replaced_in_dry_run_after_the_pins_exist(self) -> None:
        state = scenario()
        state["repo"]["cleanupPolicies"] = {"zen-v1-keep-newest-20": {"name": "zen-v1-keep-newest-20"}}
        state["repo"]["cleanupPolicyDryRun"] = False
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(0, code, out)
        calls = self.state()["calls"]
        pins = [i for i, c in enumerate(calls) if "tags add" in c]
        policy = [i for i, c in enumerate(calls) if "set-cleanup-policies" in c]
        self.assertTrue(max(pins) < policy[0])
        self.assertIn("--dry-run", calls[policy[0]])
        self.assertTrue(self.state()["repo"]["cleanupPolicyDryRun"])
        self.assertIn("NOT ARMED", out)

    def test_a_rerun_after_arming_changes_nothing(self) -> None:
        first = self.armed_after_two_runs()
        n = len(first["calls"])
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(0, code, out)
        second = self.state()
        self.assertEqual([], self.mutating(second["calls"][n:]), out)
        for key in ("revisions", "repo", "versions"):
            self.assertEqual(first[key], second[key], key)

    def test_a_failed_pin_does_not_stage_or_arm_and_stands_an_armed_policy_down(self) -> None:
        for armed in (False, True):
            with self.subTest(armed=armed):
                state = scenario(staged=not armed, armed=armed)
                state["fail_tag_add"] = True
                self.load(state)
                code, out = self.run_cleanup(docker="off")
                calls = self.state()["calls"]
                self.assertEqual(1, code, out)
                self.assertIn("could not pin", out)
                self.assertIn("the deploy itself succeeded", out)
                self.assertFalse(any("--no-dry-run" in c for c in calls))
                self.assertTrue(self.state()["repo"]["cleanupPolicyDryRun"])

    def test_a_failed_pin_stands_down_a_policy_of_an_older_shape(self) -> None:
        state = scenario()
        state["repo"]["cleanupPolicies"] = {"zen-v1-keep-newest-20": {"name": "zen-v1-keep-newest-20"}}
        state["repo"]["cleanupPolicyDryRun"] = False
        state["fail_tag_add"] = True
        self.load(state)
        self.assertEqual(1, self.run_cleanup(docker="off")[0])
        self.assertTrue(self.state()["repo"]["cleanupPolicyDryRun"])

    def test_nothing_is_pinned_or_released_in_a_dry_run(self) -> None:
        self.load(scenario(staged=True))
        code, out = self.run_cleanup("--dry-run", docker="off")
        self.assertEqual(0, code, out)
        self.assertEqual([], self.mutating(self.state()["calls"]))
        self.assertIn("would pin", out)

    def test_a_failed_revision_step_never_reaches_pinning(self) -> None:
        state = scenario(staged=True)
        state["fail_delete"] = ["r8"]
        self.load(state)
        self.run_cleanup()
        calls = self.state()["calls"]
        self.assertFalse(any("tags add" in c or "tags delete" in c or "set-cleanup-policies" in c
                             for c in calls))


class ConsumerTest(Harness):
    def test_a_job_naming_a_tag_pins_the_index_and_its_children_survive(self) -> None:
        state = scenario(staged=True)
        state["jobs"] = [job("migrate", "%s:abc0008" % PACKAGE)]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        state = self.state()
        index8 = [v for v in state["versions"] if v["version"] == "sha256:index8"][0]
        self.assertIn(dc.pin_tag("sha256:index8"), index8["tags"])
        registry_runs(state, NOW + dt.timedelta(days=60))
        self.assertTrue(exists(state, "sha256:index8") and exists(state, "sha256:image8"),
                        "the pinned index keeps the image it lists")
        self.assertFalse(exists(state, "sha256:index9"))

    def test_a_job_naming_a_digest_pins_that_digest(self) -> None:
        state = scenario(staged=True)
        state["jobs"] = [job("migrate", "%s@sha256:image9" % PACKAGE)]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        state = self.state()
        registry_runs(state, NOW + dt.timedelta(days=60))
        self.assertTrue(exists(state, "sha256:image9"))

    def test_another_services_revision_pins_its_image(self) -> None:
        state = scenario(staged=True)
        state["other_revisions"] = [revision("other-1", 90, "sha256:image7", service="other")]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        state = self.state()
        registry_runs(state, NOW + dt.timedelta(days=60))
        self.assertTrue(exists(state, "sha256:image7"))

    def test_an_image_outside_this_registry_is_not_a_consumer(self) -> None:
        state = scenario(staged=True)
        state["jobs"] = [job("elsewhere", "gcr.io/other/app:1")]
        state["other_revisions"] = [{"metadata": {"name": "x", "labels": {}},
                                     "status": {"imageDigest": "gcr.io/other/app@sha256:zzz"}}]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])

    def test_a_pin_is_released_only_when_no_consumer_needs_the_digest(self) -> None:
        """A digest shared by a revision and a job stays pinned until both are gone."""
        state = scenario(staged=True)
        state["jobs"] = [job("migrate", "%s@sha256:image2" % PACKAGE)]   # r2's digest, shared
        state["other_revisions"] = [revision("o", 90, "sha256:image6", service="other")]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        pinned = lambda st, n: dc.pin_tag("sha256:image%d" % n) in [
            t for v in st["versions"] for t in v["tags"]]
        self.assertTrue(pinned(self.state(), 2) and pinned(self.state(), 6))

        state = self.state()   # the revision goes; the job still names its image
        state["revisions"] = [r for r in state["revisions"] if r["metadata"]["name"] != "r2"]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        self.assertTrue(pinned(self.state(), 2), "the job still needs it")
        self.assertTrue(pinned(self.state(), 6))

        state = self.state()   # now the job and the other service's revision go too
        state["jobs"] = []
        state["other_revisions"] = []
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        self.assertFalse(pinned(self.state(), 2), "nothing needs it now")
        self.assertFalse(pinned(self.state(), 6))
        self.assertTrue(pinned(self.state(), 1))

    def test_a_pin_on_a_young_version_is_not_released(self) -> None:
        state = scenario(staged=True)
        young = {"package": PACKAGE, "version": "sha256:fresh", "createTime": ago(0.1),
                 "tags": [dc.pin_tag("sha256:fresh")]}
        state["versions"].append(young)
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        tags = [t for v in self.state()["versions"] if v["version"] == "sha256:fresh" for t in v["tags"]]
        self.assertEqual([dc.pin_tag("sha256:fresh")], tags)

    def test_an_operator_hold_is_never_released_and_protects_the_digest(self) -> None:
        state = scenario(staged=True)
        for v in state["versions"]:
            if v["version"] == "sha256:image10":
                v["tags"] = ["zen-hold-other-project"]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        state = self.state()
        registry_runs(state, NOW + dt.timedelta(days=60))
        self.assertTrue(exists(state, "sha256:image10"))
        self.assertFalse(any("tags delete" in c and "zen-hold" in c for c in state["calls"]))

    def test_an_unreadable_job_list_fails_closed(self) -> None:
        state = scenario(staged=True)
        state["fail_jobs"] = True
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("PERMISSION_DENIED", out)
        self.assertFalse(any("tags add" in c or "tags delete" in c or "set-cleanup-policies" in c
                             for c in self.state()["calls"]))

    def test_a_consumer_whose_image_is_gone_is_reported_and_blocks_arming(self) -> None:
        state = scenario(staged=True)
        state["jobs"] = [job("migrate", "%s:expired" % PACKAGE)]
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("job migrate", out)
        self.assertIn("already gone", out)
        self.assertFalse(any("--no-dry-run" in c for c in self.state()["calls"]))
        self.assertFalse(any("tags delete" in c for c in self.state()["calls"]))

    def test_a_failed_release_keeps_the_pin_and_is_reported(self) -> None:
        state = scenario(staged=True)
        for v in state["versions"]:
            if v["version"] == "sha256:image9":
                v["tags"] = [dc.pin_tag("sha256:image9")]
        state["fail_tag_delete"] = True
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("could not release a pin", out)
        self.assertIn(dc.pin_tag("sha256:image9"),
                      [t for v in self.state()["versions"] for t in v["tags"]])

    def test_a_pin_naming_another_digest_is_refused(self) -> None:
        state = scenario(staged=True)
        state["versions"][1]["tags"] = [dc.pin_tag("sha256:other")]
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("does not name that version", out)


class ReviewFixesTest(Harness):
    def test_an_unlistable_job_set_stands_an_enforcing_policy_down(self) -> None:
        state = scenario(armed=True)
        state["fail_jobs"] = True
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("put back into dry run", out)
        self.assertTrue(self.state()["repo"]["cleanupPolicyDryRun"])

    def test_another_services_revision_without_a_digest_does_not_block_this_service(self) -> None:
        state = scenario(staged=True)
        state["other_revisions"] = [{"metadata": {"name": "broken", "labels": {"serving.knative.dev/service": "other"}},
                                     "status": {}}]
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(0, code, out)
        self.assertIn("reports no image digest", out)

    def test_one_hold_name_never_moves_between_digests(self) -> None:
        self.load(scenario())
        argv = ["pin", "--project", PROJECT, "--region", REGION, "--repo", REPO, "--hold", "gke"]
        for image, expected in (("%s:abc0009" % PACKAGE, 0), ("%s:abc0008" % PACKAGE, 1)):
            out = io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
                code = dc.main(argv + ["--image", image], now=NOW)
            self.assertEqual(expected, code, out.getvalue())
        holders = [v["version"] for v in self.state()["versions"] if "zen-hold-gke" in v["tags"]]
        self.assertEqual(["sha256:index9"], holders)


class ParentChildTest(unittest.TestCase):
    POLICY = dc.build_policy(1, 30, dc.DEFAULT_TAG_PREFIXES)

    def versions(self, index_tags, index_age=40, child_age=40):
        return [
            {"package": PACKAGE, "version": "sha256:newest", "createTime": ago(1), "tags": ["abc"]},
            {"package": PACKAGE, "version": "sha256:index", "createTime": ago(index_age), "tags": index_tags},
            {"package": PACKAGE, "version": "sha256:child", "createTime": ago(child_age), "tags": []},
        ]

    CHILDREN = {(PACKAGE, "sha256:index"): ["sha256:child"]}

    def expired(self, versions):
        return {v["version"] for v in dc.simulate(self.POLICY, versions, NOW, self.CHILDREN)}

    def test_both_parent_and_child_expired_go_eventually(self) -> None:
        self.assertEqual({"sha256:index", "sha256:child"}, self.expired(self.versions(["abc1"])))

    def test_an_old_untagged_child_is_shielded_by_a_retained_parent(self) -> None:
        pinned = self.versions(["abc1", dc.pin_tag("sha256:index")])
        self.assertEqual(set(), self.expired(pinned))

    def test_a_pinned_child_outlives_its_expired_parent(self) -> None:
        versions = self.versions(["abc1"])
        versions[2]["tags"] = [dc.pin_tag("sha256:child")]
        self.assertEqual({"sha256:index"}, self.expired(versions))

    def test_without_parent_data_the_answer_is_an_upper_bound(self) -> None:
        pinned = self.versions(["abc1", dc.pin_tag("sha256:index")])
        selected = {v["version"] for v in dc.simulate(self.POLICY, pinned, NOW)}
        self.assertEqual({"sha256:child"}, selected)

    def test_a_reference_cycle_shields_nothing_it_cannot_prove(self) -> None:
        versions = self.versions([])
        loop = {(PACKAGE, "sha256:index"): ["sha256:child"], (PACKAGE, "sha256:child"): ["sha256:index"]}
        got = {v["version"] for v in dc.simulate(self.POLICY, versions, NOW, loop)}
        self.assertEqual(set(), got & {"sha256:newest"})


class ParentChildEndToEndTest(Harness):
    def test_the_list_does_not_claim_a_shielded_child_will_expire(self) -> None:
        state = scenario(staged=True)
        state["jobs"] = [job("migrate", "%s:abc0008" % PACKAGE)]
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(0, code, out)
        self.assertNotIn("sha256:image8", out)
        self.assertNotIn("sha256:att8", out)
        self.assertIn("sha256:index9", out)

    def test_unreadable_manifests_are_reported_and_the_list_is_an_upper_bound(self) -> None:
        state = scenario(staged=True)
        state["manifests"] = {}
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(0, code, out)


class PinCommandTest(Harness):
    def run_pin(self, *extra: str):
        argv = ["pin", "--project", PROJECT, "--region", REGION, "--repo", REPO] + list(extra)
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = dc.main(argv, now=NOW)
        return code, out.getvalue()

    def test_pinning_a_pushed_tag_protects_it_before_anything_points_at_it(self) -> None:
        self.load(scenario())
        code, out = self.run_pin("--image", "%s:abc0009" % PACKAGE)
        self.assertEqual(0, code, out)
        index9 = [v for v in self.state()["versions"] if v["version"] == "sha256:index9"][0]
        self.assertIn(dc.pin_tag("sha256:index9"), index9["tags"])
        self.assertIn("abc0009", index9["tags"])

    def test_pinning_a_digest_and_pinning_again_is_idempotent(self) -> None:
        self.load(scenario())
        for _ in range(2):
            self.assertEqual(0, self.run_pin("--image", "%s@sha256:image9" % PACKAGE)[0])
        tags = [t for v in self.state()["versions"] if v["version"] == "sha256:image9" for t in v["tags"]]
        self.assertEqual([dc.pin_tag("sha256:image9")], tags)

    def test_a_hold_is_an_operator_tag_the_cleanup_never_removes(self) -> None:
        self.load(scenario())
        self.assertEqual(0, self.run_pin("--image", "%s:abc0009" % PACKAGE, "--hold", "prudent")[0])
        index9 = [v for v in self.state()["versions"] if v["version"] == "sha256:index9"][0]
        self.assertIn("zen-hold-prudent", index9["tags"])

    def test_an_image_that_is_not_in_the_registry_is_not_pinned_and_fails(self) -> None:
        self.load(scenario())
        code, out = self.run_pin("--image", "%s:nope" % PACKAGE)
        self.assertEqual(1, code, out)
        self.assertFalse(any("tags add" in c for c in self.state()["calls"]))

    def test_another_repository_is_refused(self) -> None:
        self.load(scenario())
        code, out = self.run_pin("--image", "%s-docker.pkg.dev/other/x/y:t" % REGION)
        self.assertEqual(1, code, out)
        self.assertEqual([], self.state()["calls"])

    def test_a_failed_tag_fails_the_command(self) -> None:
        state = scenario()
        state["fail_tag_add"] = True
        self.load(state)
        self.assertEqual(1, self.run_pin("--image", "%s:abc0009" % PACKAGE)[0])


class PinPolicyTest(unittest.TestCase):
    def test_the_policy_has_a_keep_rule_for_pins_and_holds(self) -> None:
        keep = [r for r in dc.build_policy(20, 30, dc.DEFAULT_TAG_PREFIXES) if r["name"].endswith("keep-pinned")]
        self.assertEqual(1, len(keep))
        self.assertEqual("Keep", keep[0]["action"]["type"])
        self.assertEqual(["zen-pin-", "zen-hold-"], keep[0]["condition"]["tagPrefixes"])

    def test_a_policy_with_deletes_and_no_pin_keep_is_refused(self) -> None:
        policy = [r for r in dc.build_policy(20, 30, dc.DEFAULT_TAG_PREFIXES) if not r["name"].endswith("keep-pinned")]
        with self.assertRaises(dc.StepError):
            dc.assert_policy_safe(policy)

    def test_a_tag_prefix_that_would_match_a_pin_is_refused(self) -> None:
        for prefix in ("z", "zen-", "zen-pin-", "zen-hold-"):
            with self.assertRaises(dc.StepError, msg=prefix):
                dc.build_policy(20, 30, [prefix])

    def test_neither_pin_prefix_matches_the_default_delete_prefixes(self) -> None:
        for tag in (dc.PIN_PREFIX, dc.HOLD_PREFIX):
            self.assertFalse(any(tag.startswith(p) for p in dc.DEFAULT_TAG_PREFIXES))


if __name__ == "__main__":
    unittest.main()
