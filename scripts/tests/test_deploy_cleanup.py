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
    elif argv[:3] == ["artifacts", "repositories", "delete-cleanup-policies"]:
        if state.get("fail_policy_delete"):
            print("PERMISSION_DENIED", file=sys.stderr)
            with open(path, "w") as f:
                json.dump(state, f)
            sys.exit(1)
        names = [a for a in argv if a.startswith("--policynames=")][0].split("=", 1)[1].split(",")
        for name in names:
            state["repo"]["cleanupPolicies"].pop(name)
    elif argv[:4] == ["artifacts", "docker", "images", "list"]:
        out = json.dumps(state["versions"])
    elif argv[:4] == ["artifacts", "docker", "images", "delete"]:
        package, digest = argv[4].split("@")
        problem = None
        if "--delete-tags" not in argv or "--quiet" not in argv:
            problem = "INVALID_ARGUMENT: a version with tags needs --delete-tags"
        elif digest in state.get("fail_image_delete", []):
            problem = "PERMISSION_DENIED"
        elif not any(v["package"] == package and v["version"] == digest for v in state["versions"]):
            problem = "NOT_FOUND"
        if problem:
            print(problem, file=sys.stderr)
            with open(path, "w") as f:
                json.dump(state, f)
            sys.exit(1)
        # The registry deletes a version's attachments (OCI referrers) together with it.
        # `cascade` models a registry that also removes an index's images with the index.
        gone = ({digest} | set(state.get("referrers", {}).get(digest, []))
                | set(state.get("cascade", {}).get(digest, [])))
        state["versions"] = [v for v in state["versions"]
                             if not (v["package"] == package and v["version"] in gone)]
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
        if argv[4] in state.get("unreadable", []):
            print("manifest unknown", file=sys.stderr)
            with open(path, "w") as f:
                json.dump(state, f)
            sys.exit(1)
        kids = state.get("manifests", {}).get(argv[4])
        subject = state.get("subjects", {}).get(argv[4])
        doc = {}
        if kids:
            doc["manifests"] = [{"digest": d} for d in kids]
        if subject:
            doc["subject"] = {"digest": subject}
        out = json.dumps(doc or {"layers": []})
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


# Ten deploys, newest first. With keep-versions 20 the newest 20 of 30 versions (deploys 1-6 and two
# of deploy 7, whose attestation is the one left over) are kept. Everything of deploys 8-10 is older
# than the 30-day window and beyond the newest 20, so the plan is exactly those nine versions, each
# index before the image and attestation it lists.
AGES = [1, 3, 5, 20, 40, 60, 80, 100, 120, 140]
HEX_TARGET = "sha256:" + "a1" * 32
HEX_SIG_TAG = "sha256-" + "a1" * 32 + ".sig"


def scenario(serving=("r1",), policies=()) -> dict:
    versions = []
    for i, age in enumerate(AGES, start=1):
        versions += deploy_versions(i, age, "abc%04d" % i)
    state = {
        "calls": [],
        "service": {"status": {"traffic": [{"revisionName": r, "percent": 100} for r in serving],
                               "latestReadyRevisionName": "r1"}},
        "revisions": [revision("r%d" % i, age, "sha256:image%d" % i) for i, age in enumerate(AGES, start=1)],
        "repo": {"cleanupPolicies": {n: {"name": n} for n in policies}, "cleanupPolicyDryRun": False},
        "versions": versions,
        # What each index lists: the image Cloud Run runs and the attestation.
        "manifests": {"%s@sha256:index%d" % (PACKAGE, n): ["sha256:image%d" % n, "sha256:att%d" % n]
                      for n in range(1, len(AGES) + 1)},
        "subjects": {},
        "referrers": {},
        "unreadable": [],
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
    return state


def version(digest: str, age: float, tags=()) -> dict:
    return {"package": PACKAGE, "version": digest, "createTime": ago(age), "tags": list(tags)}


def mini(versions: list, manifests=None, **extra) -> dict:
    """A small registry. The first version is young and is what the one revision runs."""
    state = scenario()
    state["versions"] = versions
    state["manifests"] = {"%s@%s" % (PACKAGE, k): v for k, v in (manifests or {}).items()}
    state["revisions"] = [revision("r1", 1, versions[0]["version"])]
    state.update(extra)
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
                "--keep-revisions", "3", "--revision-days", "14", "--keep-versions", opts.get("keep_versions", "20"),
                "--image-days", "30", "--docker-cache-hours", "168",
                "--revisions", opts.get("revisions", "on"), "--registry", opts.get("registry", "on"),
                "--docker", opts.get("docker", "on")] + list(extra)
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = dc.main(argv, now=NOW)
        return code, out.getvalue()

    def mutating(self, calls: list) -> list:
        marks = ("revisions delete", "images delete", "delete-cleanup-policies", "rmi ", "prune",
                 "tags add", "tags delete")
        return [c for c in calls if any(m in c for m in marks)]

    def deleted(self, calls=None) -> list:
        """The digests passed to `images delete`, in the order they were deleted."""
        calls = self.state()["calls"] if calls is None else calls
        return [c.split("@", 1)[1].split()[0] for c in calls if "images delete" in c]

    def digests(self) -> set:
        return {v["version"] for v in self.state()["versions"]}

    def test_failed_revision_delete_skips_registry_in_fail_and_warn_modes(self) -> None:
        for mode, expected in (("fail", 1), ("warn", 0)):
            with self.subTest(mode=mode):
                state = scenario()
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
                state = scenario()
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


class PlanTest(Harness):
    """ADR-074 "Consequence": the plan, and what it never touches."""

    NINE = ["sha256:%s%d" % (kind, n) for n in (8, 9, 10) for kind in ("index", "image", "att")]

    def test_the_plan_deletes_what_the_old_policy_would_have_expired_and_nothing_else(self) -> None:
        self.load(scenario())
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(0, code, out)
        self.assertEqual(sorted(self.NINE), sorted(self.deleted()))
        # deploys 1-7 are kept whole: count-kept, window-kept, and deploy 7's leftover attestation
        # shielded by its surviving index.
        self.assertEqual(21, len(self.state()["versions"]))
        self.assertIn("sha256:att7", self.digests())

    def test_every_deletion_is_one_version_per_call_with_its_tags_and_no_shell(self) -> None:
        self.load(scenario())
        self.run_cleanup(docker="off")
        calls = [c for c in self.state()["calls"] if "images delete" in c]
        self.assertEqual(9, len(calls))
        for c in calls:
            self.assertRegex(c, r"^gcloud artifacts docker images delete \S+@sha256:\S+ --delete-tags --quiet$")

    def test_the_before_and_after_listings_are_printed(self) -> None:
        self.load(scenario())
        code, out = self.run_cleanup(docker="off")
        self.assertIn("before: 30 versions", out)
        self.assertIn("after: 21 versions", out)
        self.assertIn("30 versions before, 21 after", out)

    def test_the_newest_versions_are_never_deleted(self) -> None:
        self.load(scenario())
        self.assertEqual(0, self.run_cleanup(docker="off", keep_versions="30")[0])
        self.assertEqual([], self.deleted())
        self.assertEqual(30, len(self.state()["versions"]))

    def test_a_pinned_version_is_never_deleted_even_when_old_and_beyond_the_newest(self) -> None:
        """r8 serves traffic from a `--no-traffic` deploy: it is kept, and so is its image."""
        self.load(scenario(serving=("r1", "r8")))
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        self.assertIn("sha256:image8", self.digests())
        self.assertNotIn("sha256:image8", self.deleted())
        pins = [t for v in self.state()["versions"] for t in v["tags"] if t.startswith(dc.PIN_PREFIX)]
        self.assertIn(dc.pin_tag("sha256:image8"), pins)

    def test_a_held_version_is_never_deleted_and_its_hold_is_never_released(self) -> None:
        state = scenario()
        for v in state["versions"]:
            if v["version"] == "sha256:image10":
                v["tags"] = ["zen-hold-other-project"]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        self.assertIn("sha256:image10", self.digests())
        self.assertNotIn("sha256:image10", self.deleted())
        self.assertFalse(any("tags delete" in c and "zen-hold" in c for c in self.state()["calls"]))

    def test_a_parent_is_deleted_before_its_children(self) -> None:
        self.load(scenario())
        self.run_cleanup(docker="off")
        order = self.deleted()
        for n in (8, 9, 10):
            self.assertLess(order.index("sha256:index%d" % n), order.index("sha256:image%d" % n))
            self.assertLess(order.index("sha256:index%d" % n), order.index("sha256:att%d" % n))

    def test_a_child_of_a_surviving_parent_is_not_deleted(self) -> None:
        """A job pins index8: its image and attestation are old and untagged and still stay."""
        state = scenario()
        state["jobs"] = [job("migrate", "%s:abc0008" % PACKAGE)]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        for d in ("index8", "image8", "att8"):
            self.assertIn("sha256:" + d, self.digests())
        self.assertNotIn("sha256:index9", self.digests())

    def test_an_untagged_index_shields_its_children(self) -> None:
        """The tag moved off a young index; its old untagged child must not be deleted from under it."""
        versions = [version("sha256:run", 1), version("sha256:idx", 2), version("sha256:child", 100)]
        manifests = {"sha256:idx": ["sha256:child"]}
        self.load(mini(versions, manifests))
        self.assertEqual(0, self.run_cleanup(revisions="off", docker="off", keep_versions="1")[0])
        self.assertIn("sha256:child", self.digests())
        # The control: with nothing to read, the child is just an old untagged version.
        self.load(mini(versions, {}))
        self.assertEqual(0, self.run_cleanup(revisions="off", docker="off", keep_versions="1")[0])
        self.assertNotIn("sha256:child", self.digests())

    def test_a_child_whose_other_parent_survives_is_not_deleted(self) -> None:
        versions = [version("sha256:run", 1), version("sha256:old", 60, ["abc1"]),
                    version("sha256:young", 2), version("sha256:child", 100)]
        manifests = {"sha256:old": ["sha256:child"], "sha256:young": ["sha256:child"]}
        self.load(mini(versions, manifests))
        self.assertEqual(0, self.run_cleanup(revisions="off", docker="off", keep_versions="1")[0])
        self.assertIn("sha256:child", self.digests())
        self.assertNotIn("sha256:old", self.digests())

    def test_latest_is_never_deleted(self) -> None:
        versions = [version("sha256:run", 1), version("sha256:old", 90, ["abc1", "latest"])]
        self.load(mini(versions))
        self.assertEqual(0, self.run_cleanup(revisions="off", docker="off", keep_versions="1")[0])
        self.assertIn("sha256:old", self.digests())

    def test_a_rerun_deletes_nothing_more(self) -> None:
        self.load(scenario())
        self.assertEqual(0, self.run_cleanup()[0])
        first = self.state()
        n = len(first["calls"])
        code, out = self.run_cleanup()
        self.assertEqual(0, code, out)
        second = self.state()
        self.assertEqual([], [c for c in self.mutating(second["calls"][n:]) if "prune" not in c], out)
        for key in ("revisions", "repo", "versions", "images"):
            self.assertEqual(first[key], second[key], key)


class AttachmentTest(Harness):
    """An attachment leaves only with its target."""

    def versions(self, target_tags=("abc1",), with_sig=True, with_referrer=True):
        v = [version("sha256:run", 1), version(HEX_TARGET, 60, list(target_tags))]
        if with_sig:
            v.append(version("sha256:" + "b2" * 32, 200, [HEX_SIG_TAG]))
        if with_referrer:
            v.append(version("sha256:referrer", 200))
        return v

    def go(self, versions, **extra):
        state = mini(versions, subjects={"%s@sha256:referrer" % PACKAGE: HEX_TARGET},
                     referrers={HEX_TARGET: ["sha256:referrer"]}, **extra)
        self.load(state)
        return self.run_cleanup(revisions="off", docker="off", keep_versions="1")

    def test_attachments_are_deleted_with_their_target_and_the_signature_after_it(self) -> None:
        code, out = self.go(self.versions())
        self.assertEqual(0, code, out)
        self.assertEqual({"sha256:run"}, self.digests())
        order = self.deleted()
        self.assertEqual([HEX_TARGET, "sha256:" + "b2" * 32], order,
                         "the target, then its signature; the referrer goes with the target")
        self.assertNotIn("sha256:referrer", order)

    def test_attachments_are_never_deleted_on_their_own(self) -> None:
        """200 days old and untagged or `sha256-`-tagged, yet the target is held, so they stay."""
        code, out = self.go(self.versions(target_tags=("abc1", "zen-hold-x")))
        self.assertEqual(0, code, out)
        self.assertEqual([], self.deleted())
        self.assertEqual(4, len(self.state()["versions"]))

    def test_a_signature_whose_target_is_gone_is_left_alone(self) -> None:
        versions = [version("sha256:run", 1), version("sha256:" + "b2" * 32, 200, [HEX_SIG_TAG])]
        self.load(mini(versions))
        self.assertEqual(0, self.run_cleanup(revisions="off", docker="off", keep_versions="1")[0])
        self.assertEqual([], self.deleted())

    def test_a_referrer_is_never_in_the_plan_even_when_nothing_holds_its_target(self) -> None:
        code, out = self.go(self.versions(with_sig=False))
        self.assertEqual(0, code, out)
        self.assertEqual([HEX_TARGET], self.deleted())
        self.assertIn("goes with its target", out)

    def test_sha256_is_not_a_default_prefix_and_a_prefix_matching_it_is_refused(self) -> None:
        self.assertNotIn("sha256-", dc.DEFAULT_TAG_PREFIXES)
        for prefix in ("s", "sh", "sha256-"):
            with self.assertRaises(dc.StepError, msg=prefix):
                dc.validate_tag_prefixes(20, 30, [prefix])
        self.load(mini(self.versions()))
        code, out = self.run_cleanup("--tag-prefixes", "a,sha256-", revisions="off", docker="off")
        self.assertEqual(1, code, out)
        self.assertEqual([], self.deleted())


class FailClosedTest(Harness):
    """Anything that makes the plan unprovable deletes nothing in the run."""

    def assertNothingDeleted(self, out: str = "") -> None:
        self.assertEqual([], self.deleted(), out)
        self.assertEqual(30, len(self.state()["versions"]))

    def test_an_unreadable_manifest_deletes_nothing(self) -> None:
        state = scenario()
        state["unreadable"] = ["%s@sha256:att9" % PACKAGE]   # an untagged attestation, not an index
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("could not be read", out)
        self.assertIn("the deploy itself succeeded", out)
        self.assertNothingDeleted(out)

    def test_every_version_is_read_not_only_tagged_ones(self) -> None:
        self.load(scenario())
        self.run_cleanup(docker="off")
        inspected = [c for c in self.state()["calls"] if "imagetools inspect" in c]
        self.assertEqual(30, len(inspected))
        self.assertTrue(any("sha256:att9" in c for c in inspected))

    def test_docker_missing_deletes_nothing(self) -> None:
        self.load(scenario())
        old = dc.shutil.which
        dc.shutil.which = lambda name: None if name == "docker" else old(name)
        try:
            code, out = self.run_cleanup(docker="off")
        finally:
            dc.shutil.which = old
        self.assertEqual(1, code, out)
        self.assertNothingDeleted(out)

    def test_a_hazard_deletes_nothing(self) -> None:
        """Defence in depth: a plan that contains a digest a revision runs is refused whole."""
        self.load(scenario())
        real = dc.build_plan

        def bad(versions, *rest):
            plan = real(versions, *rest)
            runs = [v for v in versions if v["version"] == "sha256:image1"][0]
            plan.delete.insert(0, runs)
            return plan

        dc.build_plan = bad
        try:
            code, out = self.run_cleanup(docker="off")
        finally:
            dc.build_plan = real
        self.assertEqual(1, code, out)
        self.assertIn("a revision or job needs", out)
        self.assertNothingDeleted(out)

    def test_a_consumer_whose_image_is_gone_deletes_nothing(self) -> None:
        state = scenario()
        state["jobs"] = [job("migrate", "%s:expired" % PACKAGE)]
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("job migrate", out)
        self.assertIn("already gone", out)
        self.assertNothingDeleted(out)
        self.assertFalse(any("tags delete" in c for c in self.state()["calls"]))

    def test_an_unreadable_consumer_list_deletes_nothing(self) -> None:
        state = scenario()
        state["fail_jobs"] = True
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("PERMISSION_DENIED", out)
        self.assertNothingDeleted(out)
        self.assertFalse(any("tags add" in c or "tags delete" in c for c in self.state()["calls"]))

    def test_a_revision_without_a_digest_deletes_nothing(self) -> None:
        state = scenario()
        state["revisions"][0]["status"] = {}
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("no usable image digest", out)
        self.assertNothingDeleted(out)

    def test_a_failed_pin_deletes_nothing(self) -> None:
        state = scenario()
        state["fail_tag_add"] = True
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("could not pin", out)
        self.assertIn("the deploy itself succeeded", out)
        self.assertNothingDeleted(out)

    def test_a_failed_revision_step_never_reaches_the_registry(self) -> None:
        state = scenario()
        state["fail_delete"] = ["r8"]
        self.load(state)
        self.run_cleanup()
        calls = self.state()["calls"]
        self.assertFalse(any("tags add" in c or "tags delete" in c or "images delete" in c for c in calls))


class TransitionTest(Harness):
    OWN = ("zen-v2-keep-newest-20", "zen-v2-keep-pinned", "zen-v2-delete-untagged-older-than-30d")

    def test_jzens_own_policies_are_removed_before_any_version_is_deleted(self) -> None:
        self.load(scenario(policies=self.OWN))
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(0, code, out)
        calls = self.state()["calls"]
        removal = [i for i, c in enumerate(calls) if "delete-cleanup-policies" in c]
        deletes = [i for i, c in enumerate(calls) if "images delete" in c]
        self.assertEqual(1, len(removal))
        self.assertTrue(deletes and removal[0] < min(deletes))
        self.assertEqual({}, self.state()["repo"]["cleanupPolicies"])
        self.assertIn("--policynames=" + ",".join(sorted(self.OWN)), calls[removal[0]])

    def test_a_foreign_policy_blocks_deletion_and_is_named(self) -> None:
        self.load(scenario(policies=("zen-v2-keep-pinned", "teams-own-policy")))
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("teams-own-policy", out)
        self.assertIn("CLEANUP_REGISTRY=off", out)
        self.assertEqual([], self.deleted())
        self.assertFalse(any("delete-cleanup-policies" in c for c in self.state()["calls"]))
        self.assertEqual(2, len(self.state()["repo"]["cleanupPolicies"]))

    def test_a_policy_that_cannot_be_removed_deletes_nothing(self) -> None:
        state = scenario(policies=self.OWN)
        state["fail_policy_delete"] = True
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertEqual([], self.deleted())

    def test_no_policy_is_ever_armed(self) -> None:
        self.load(scenario())
        self.run_cleanup()
        self.assertFalse(any("set-cleanup-policies" in c for c in self.state()["calls"]))
        self.assertEqual({}, self.state()["repo"]["cleanupPolicies"])


class FailedDeletionTest(Harness):
    def test_a_failed_parent_deletion_skips_its_children_and_fails_the_step(self) -> None:
        state = scenario()
        state["fail_image_delete"] = ["sha256:index9"]
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("the deploy itself succeeded", out)
        self.assertIn("PERMISSION_DENIED", out)
        self.assertIn("sha256:index9", out)
        attempted = self.deleted()
        self.assertNotIn("sha256:image9", attempted)
        self.assertNotIn("sha256:att9", attempted)
        # the independent deletions still happened
        self.assertEqual({"sha256:index9", "sha256:image9", "sha256:att9"} | {"sha256:%s%d" % (k, n)
                         for n in range(1, 8) for k in ("index", "image", "att")},
                         self.digests())

    def test_a_version_the_registry_already_removed_is_not_a_failure(self) -> None:
        state = scenario()
        state["cascade"] = {"sha256:index9": ["sha256:image9", "sha256:att9"]}
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(0, code, out)
        self.assertIn("already gone", out)
        self.assertNotIn("could not delete", out)
        self.assertTrue({"sha256:index9", "sha256:image9", "sha256:att9"}.isdisjoint(self.digests()))

    def test_a_failed_delete_of_a_version_still_listed_stays_a_failure(self) -> None:
        state = scenario()
        state["fail_image_delete"] = ["sha256:image9"]
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("could not delete", out)
        self.assertNotIn("already gone", out)
        self.assertIn("sha256:image9", self.digests())

    def test_warn_mode_reports_the_same_failure_and_exits_zero(self) -> None:
        state = scenario()
        state["fail_image_delete"] = ["sha256:index9"]
        self.load(state)
        code, out = self.run_cleanup("--on-failure", "warn", docker="off")
        self.assertEqual(0, code, out)
        self.assertIn("PERMISSION_DENIED", out)
        self.assertIn("the deploy itself succeeded", out)

    def test_a_failed_attachment_target_keeps_the_signature(self) -> None:
        versions = [version("sha256:run", 1), version(HEX_TARGET, 60, ["abc1"]),
                    version("sha256:" + "b2" * 32, 200, [HEX_SIG_TAG])]
        state = mini(versions, fail_image_delete=[HEX_TARGET])
        self.load(state)
        code, out = self.run_cleanup(revisions="off", docker="off", keep_versions="1")
        self.assertEqual(1, code, out)
        self.assertEqual([HEX_TARGET], self.deleted())
        self.assertIn("sha256:" + "b2" * 32, self.digests())


class DryRunTest(Harness):
    def test_dry_run_prints_the_plan_and_changes_nothing(self) -> None:
        self.load(scenario(policies=TransitionTest.OWN))
        code, out = self.run_cleanup("--dry-run")
        self.assertEqual(0, code, out)
        self.assertEqual([], self.mutating(self.state()["calls"]))
        self.assertEqual(30, len(self.state()["versions"]))
        self.assertEqual(3, len(self.state()["repo"]["cleanupPolicies"]))
        self.assertIn("would delete", out)
        self.assertIn("sha256:index9", out)
        self.assertIn("would pin", out)
        self.assertIn("would remove the cleanup policies", out)

    def test_nothing_is_pinned_or_released_in_a_dry_run(self) -> None:
        self.load(scenario())
        code, out = self.run_cleanup("--dry-run", docker="off")
        self.assertEqual(0, code, out)
        self.assertEqual([], self.mutating(self.state()["calls"]))


class OperationsTest(Harness):
    def test_a_failed_delete_of_a_revision_fails_loudly_and_says_the_deploy_succeeded(self) -> None:
        state = scenario()
        state["fail_delete"] = ["r5"]
        self.load(state)
        code, out = self.run_cleanup()
        self.assertEqual(1, code, out)
        self.assertIn("the deploy itself succeeded", out)
        self.assertIn("PERMISSION_DENIED", out)

    def test_docker_removes_old_project_images_only(self) -> None:
        self.load(scenario())
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
        self.load(scenario())
        code, out = self.run_cleanup(revisions="off", registry="off", docker="off")
        self.assertEqual(0, code, out)
        self.assertEqual([], self.state()["calls"])

    def test_revisions_are_deleted_before_any_version(self) -> None:
        self.load(scenario())
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        calls = self.state()["calls"]
        revs = [i for i, c in enumerate(calls) if "revisions delete" in c]
        vers = [i for i, c in enumerate(calls) if "images delete" in c]
        self.assertEqual(7, len(revs))
        self.assertLess(max(revs), min(vers))
        self.assertEqual({"r1", "r2", "r3"}, {r["metadata"]["name"] for r in self.state()["revisions"]})

    def test_pins_are_added_before_anything_is_deleted(self) -> None:
        self.load(scenario())
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        calls = self.state()["calls"]
        pins = [i for i, c in enumerate(calls) if "tags add" in c]
        deletes = [i for i, c in enumerate(calls) if "images delete" in c]
        self.assertEqual(3, len(pins))
        self.assertLess(max(pins), min(deletes))

    def test_revisions_switched_off_still_pins_what_remains(self) -> None:
        self.load(scenario())
        self.assertEqual(0, self.run_cleanup(revisions="off", docker="off")[0])
        for n in range(1, 11):
            self.assertIn(dc.pin_tag("sha256:image%d" % n),
                          [t for v in self.state()["versions"] for t in v["tags"]], n)
        # every revision still lists, so every image it runs survives the plan
        for n in range(1, 11):
            self.assertIn("sha256:image%d" % n, self.digests())

    def test_a_revision_older_than_the_window_that_still_exists_keeps_its_image(self) -> None:
        """r3 retained, its image pushed out of the newest 20 and past the window."""
        state = scenario()
        for v in state["versions"]:
            if v["version"] in ("sha256:image3", "sha256:index3"):
                v["createTime"] = ago(100)
        for n in range(11, 21):
            state["versions"] += deploy_versions(n, 0.5, "new%04d" % n)
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        self.assertIn("sha256:image3", self.digests())
        self.assertNotIn("sha256:image8", self.digests())


class ConsumerTest(Harness):
    def test_a_job_naming_a_digest_pins_that_digest(self) -> None:
        state = scenario()
        state["jobs"] = [job("migrate", "%s@sha256:image9" % PACKAGE)]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        self.assertIn("sha256:image9", self.digests())

    def test_another_services_revision_pins_its_image(self) -> None:
        state = scenario()
        state["other_revisions"] = [revision("other-1", 90, "sha256:image7", service="other")]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        self.assertIn("sha256:image7", self.digests())

    def test_an_image_outside_this_registry_is_not_a_consumer(self) -> None:
        state = scenario()
        state["jobs"] = [job("elsewhere", "gcr.io/other/app:1")]
        state["other_revisions"] = [{"metadata": {"name": "x", "labels": {}},
                                     "status": {"imageDigest": "gcr.io/other/app@sha256:zzz"}}]
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])

    def test_a_pin_is_released_only_when_no_consumer_needs_the_digest(self) -> None:
        """A digest shared by a revision and a job stays pinned until both are gone."""
        state = scenario()
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
        state = scenario()
        state["versions"].append(version("sha256:fresh", 0.1, [dc.pin_tag("sha256:fresh")]))
        self.load(state)
        self.assertEqual(0, self.run_cleanup(docker="off")[0])
        tags = [t for v in self.state()["versions"] if v["version"] == "sha256:fresh" for t in v["tags"]]
        self.assertEqual([dc.pin_tag("sha256:fresh")], tags)

    def test_a_failed_release_keeps_the_pin_and_is_reported(self) -> None:
        state = scenario()
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
        state = scenario()
        state["versions"][1]["tags"] = [dc.pin_tag("sha256:other")]
        self.load(state)
        code, out = self.run_cleanup(docker="off")
        self.assertEqual(1, code, out)
        self.assertIn("does not name that version", out)
        self.assertEqual([], self.deleted())

    def test_another_services_revision_without_a_digest_does_not_block_this_service(self) -> None:
        state = scenario()
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


class PlanUnitTest(unittest.TestCase):
    """build_plan on its own: the reference-cycle and ordering cases the harness cannot easily make."""

    def plan(self, versions, manifests, keep=1):
        full = {dc.key_of(v): dict({"children": [], "subject": ""}, **manifests.get(v["version"], {}))
                for v in versions}
        return dc.build_plan(versions, full, NOW, keep, 30, dc.DEFAULT_TAG_PREFIXES)

    def test_a_reference_cycle_plans_none_of_its_members(self) -> None:
        versions = [version("sha256:new", 1), version("sha256:a", 90), version("sha256:b", 90)]
        plan = self.plan(versions, {"sha256:a": {"children": ["sha256:b"]},
                                    "sha256:b": {"children": ["sha256:a"]}})
        self.assertEqual([], plan.delete)

    def test_parents_come_before_children_whatever_the_listing_order(self) -> None:
        versions = [version("sha256:new", 1), version("sha256:z-child", 90),
                    version("sha256:a-parent", 90, ["abc1"])]
        plan = self.plan(versions, {"sha256:a-parent": {"children": ["sha256:z-child"]}})
        self.assertEqual(["sha256:a-parent", "sha256:z-child"], [v["version"] for v in plan.delete])

    def test_a_pinned_child_outlives_its_deleted_parent(self) -> None:
        versions = [version("sha256:new", 1), version("sha256:p", 90, ["abc1"]),
                    version("sha256:c", 90, [dc.pin_tag("sha256:c")])]
        plan = self.plan(versions, {"sha256:p": {"children": ["sha256:c"]}})
        self.assertEqual(["sha256:p"], [v["version"] for v in plan.delete])

    def test_versions_inside_the_window_are_never_planned(self) -> None:
        versions = [version("sha256:new", 1), version("sha256:mid", 29), version("sha256:t", 29, ["abc1"])]
        self.assertEqual([], self.plan(versions, {}).delete)


class PrefixTest(unittest.TestCase):
    def test_latest_is_never_matched_by_a_tag_prefix(self) -> None:
        with self.assertRaises(dc.StepError):
            dc.validate_tag_prefixes(20, 30, ["l"])

    def test_a_tag_prefix_that_would_match_a_pin_or_hold_is_refused(self) -> None:
        for prefix in ("z", "zen-", "zen-pin-", "zen-hold-"):
            with self.assertRaises(dc.StepError, msg=prefix):
                dc.validate_tag_prefixes(20, 30, [prefix])

    def test_the_defaults_are_valid_and_match_no_protected_tag(self) -> None:
        dc.validate_tag_prefixes(20, 30, dc.DEFAULT_TAG_PREFIXES)
        for tag in (dc.PIN_PREFIX, dc.HOLD_PREFIX, "sha256-", "latest"):
            self.assertFalse(any(tag.startswith(p) for p in dc.DEFAULT_TAG_PREFIXES))

    def test_a_count_below_one_is_refused(self) -> None:
        with self.assertRaises(dc.StepError):
            dc.validate_tag_prefixes(0, 30, dc.DEFAULT_TAG_PREFIXES)
        with self.assertRaises(dc.StepError):
            dc.validate_tag_prefixes(20, 0, dc.DEFAULT_TAG_PREFIXES)

    def test_a_prefix_that_could_blur_a_list_is_refused(self) -> None:
        for bad in ("a\nb", "a b", "", "-a", ".a", "a;b", "a/b", "a\u00fc"):
            with self.assertRaises(dc.StepError, msg=repr(bad)):
                dc.validate_tag_prefixes(20, 30, [bad])

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


class ArgumentShapeTest(Harness):
    """Operator-supplied names are argv elements, so a leading dash would be read as an option."""

    GOOD = {"project": "proj", "region": "europe-central2", "service": "svc", "repo": "jzen"}
    HOSTILE = ["--impersonate-service-account=x@y", "-h", "-", "a b", "a;b", "a$(id)", "a`id`",
               "a|b", "a&b", "a\nb", "A", "1abc", ""]

    def setUp(self) -> None:
        super().setUp()
        self.load(scenario())

    def argv(self, **override: str) -> "list[str]":
        values = dict(self.GOOD, **override)
        return ["--project", values["project"], "--region", values["region"],
                "--service", values["service"], "--repo", values["repo"],
                "--keep-revisions", "3", "--revision-days", "14", "--keep-versions", "20",
                "--image-days", "30", "--docker-cache-hours", "168",
                "--revisions", "on", "--registry", "on", "--docker", "on"]

    def test_the_real_names_are_accepted(self) -> None:
        a = dc.parse_args(self.argv())
        self.assertEqual(("proj", "europe-central2", "svc", "jzen"),
                         (a.project, a.region, a.service, a.repo))

    def test_a_hostile_name_is_a_usage_error_and_nothing_runs(self) -> None:
        for field in self.GOOD:
            for bad in self.HOSTILE:
                if field == "repo" and bad == "1abc":
                    continue  # a repository id may start with a digit
                with self.subTest(field=field, value=bad):
                    err = io.StringIO()
                    with self.assertRaises(SystemExit) as caught, contextlib.redirect_stderr(err):
                        dc.parse_args(self.argv(**{field: bad}))
                    self.assertEqual(2, caught.exception.code)
                    # argparse itself refuses a dash-leading value given as a separate word; the
                    # shape check is what refuses everything else, and the `--flag=value` form.
                    self.assertRegex(err.getvalue(), "not a valid %s name|expected one argument" % field)

    def test_a_dash_leading_value_in_the_equals_form_reaches_the_shape_check(self) -> None:
        for field in self.GOOD:
            argv = [a for a in self.argv() if a not in ("--" + field, self.GOOD[field])]
            err = io.StringIO()
            with self.assertRaises(SystemExit) as caught, contextlib.redirect_stderr(err):
                dc.parse_args(argv + ["--%s=--impersonate-service-account=x" % field])
            self.assertEqual(2, caught.exception.code)
            self.assertIn("not a valid %s name" % field, err.getvalue())

    def test_a_hostile_name_never_reaches_a_subprocess(self) -> None:
        for field in self.GOOD:
            before = len(self.calls())
            code, out = self.run_main(self.argv(**{field: "--impersonate-service-account=x"}))
            self.assertEqual(2, code, out)
            self.assertEqual(before, len(self.calls()), "no gcloud or docker call may be made")

    def test_pin_refuses_an_option_shaped_value_before_any_call(self) -> None:
        good = ["pin", "--project", PROJECT, "--region", REGION, "--repo", REPO]
        for argv in (
            ["pin", "--project", "--x", "--region", REGION, "--repo", REPO, "--image", PACKAGE + ":t"],
            good + ["--image", "--format=json"],
            good + ["--image", "-" + PACKAGE],
            good + ["--image", PACKAGE + ":t; rm -rf /"],
            good + ["--image", PACKAGE + ":t\n--quiet"],
        ):
            before = len(self.calls())
            code, out = self.run_main(argv)
            self.assertEqual(2, code, (argv, out))
            self.assertEqual(before, len(self.calls()))

    def run_main(self, argv: "list[str]"):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            try:
                code = dc.main(argv, now=NOW)
            except SystemExit as exc:
                code = exc.code
        return code, out.getvalue()

    def calls(self) -> list:
        return self.state()["calls"]


if __name__ == "__main__":
    unittest.main()
