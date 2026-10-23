"""Keep Artifact Registry, Cloud Run revisions and local Docker bounded after a deploy.

Run by `task zen:deploy:cleanup` (Taskfile.app.yml), which carries the operator-facing contract
(`task zen:deploy:cleanup --summary`); this docstring is about the implementation.

Three parts, in this order, and the order is the design:

1. REVISIONS first. A Cloud Run revision is not a reference the registry respects, so a revision
   whose image the registry has expired stays listed as a rollback target that cannot start. They
   are therefore deleted before the policy is armed, and the policy's window is refused unless it
   is longer than the revisions' (the image is older than its revision by the build time, so equal
   windows would expire the image first).
2. The REGISTRY POLICY. Keep the newest N versions per package; delete tagged versions (by tag
   prefix, never `latest`) and untagged versions older than the window. The untagged rule is safe
   only because of the Keep rule — the image Cloud Run runs is *untagged*, since the tag sits on
   the index above it — so `build_policy` refuses to produce a policy that has one without the
   other. Before the policy is armed it is simulated against the registry's own version list and
   the revisions that remain; a policy that would expire a digest a revision still runs is not
   armed (and an armed one that has become such a policy is put back into dry run).
3. LOCAL DOCKER: dangling layers, aged build cache, and this project's tagged images beyond the two
   newest per repository. Never `latest`, never anything outside this project's registry path.

Two-phase arming. The first run on a repository stages the policy in the registry's own dry-run
state and stops there; the run after that arms it. The registry is the memory, so "a dry run was
required once" cannot be skipped by a fresh checkout. `--dry-run` stages without arming and
deletes nothing anywhere.

Failure semantics: every step runs and reports; any failure makes the exit code non-zero
(`--on-failure fail`, the default) with the words "the deploy itself succeeded", or is printed as a
warning and exits 0 (`--on-failure warn`). Nothing is piped to `sh` or `|| true`d.

Deletions are not in Cloud Logging unless Data Access audit logs are enabled for
artifactregistry.googleapis.com, and the repository's reported size lags deletion, so the evidence
this prints is a before/after LISTING, not a size.

Written to the 3.9 floor, stdlib only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

import lib

# Bump when the SHAPE of the policy changes; the numbers are already in the rule names, so a changed
# number re-arms an existing repository without touching this.
POLICY_REVISION = "v1"

# A tag begins with a hex digit when it is a (short) commit SHA — what `deploy:cloudrun` pushes,
# with an optional `-dirty` — or with `sha256-` when it is a cosign signature/attestation, which is
# tagged on the registry and would otherwise outlive the image it signs. `latest` and `stable`
# start with neither. Any other tag that starts with a hex digit (`1.0.0`) is expiry-eligible too;
# an application that keeps such tags overrides the prefixes.
DEFAULT_TAG_PREFIXES = list("0123456789abcdef") + ["sha256-"]

DOCKER_KEEP_PER_REPOSITORY = 2
PROTECTED_TAGS = {"latest"}


class StepError(Exception):
    """A step could not be completed. Carries a sentence an operator can act on."""


# ──────────────────────────────── pure logic ────────────────────────────────


def parse_ts(value: str) -> dt.datetime:
    """RFC 3339 as gcloud and Docker print it, to an aware datetime (3.9's fromisoformat is stricter)."""
    text = value.strip().replace("Z", "+00:00")
    text = re.sub(r"\.(\d+)", lambda m: "." + (m.group(1) + "000000")[:6], text, count=1)
    parsed = dt.datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed


def build_policy(keep_versions: int, image_days: int, tag_prefixes: Sequence[str]) -> List[Dict[str, Any]]:
    """The repository cleanup policy. Refuses any shape that could expire a running image."""
    if keep_versions < 1:
        raise StepError("keep-versions must be at least 1: the Keep rule is what makes deleting "
                        "untagged versions safe, because the image Cloud Run runs is untagged.")
    if image_days < 1:
        raise StepError("image-days must be at least 1.")
    prefixes = list(tag_prefixes)
    if not prefixes:
        raise StepError("tag-prefixes is empty: the tagged rule would match every tagged version.")
    for tag in PROTECTED_TAGS:
        if any(tag.startswith(p) for p in prefixes):
            raise StepError("tag prefix %r would also match the protected tag %r." %
                            (next(p for p in prefixes if tag.startswith(p)), tag))
    seconds = "%ds" % (image_days * 86400)
    digest = hashlib.sha1("\n".join(prefixes).encode("utf-8")).hexdigest()[:8]
    policy = [
        {
            "name": "zen-%s-keep-newest-%d" % (POLICY_REVISION, keep_versions),
            "action": {"type": "Keep"},
            "mostRecentVersions": {"keepCount": keep_versions},
        },
        {
            "name": "zen-%s-delete-tagged-%s-older-than-%dd" % (POLICY_REVISION, digest, image_days),
            "action": {"type": "Delete"},
            "condition": {"tagState": "TAGGED", "tagPrefixes": prefixes, "olderThan": seconds},
        },
        {
            "name": "zen-%s-delete-untagged-older-than-%dd" % (POLICY_REVISION, image_days),
            "action": {"type": "Delete"},
            "condition": {"tagState": "UNTAGGED", "olderThan": seconds},
        },
    ]
    assert_policy_safe(policy)
    return policy


def assert_policy_safe(policy: Sequence[Dict[str, Any]]) -> None:
    """A Delete of untagged versions is allowed only beside a Keep of the newest ones."""
    has_keep = any(
        r["action"]["type"] == "Keep" and r.get("mostRecentVersions", {}).get("keepCount", 0) >= 1
        for r in policy
    )
    deletes_untagged = any(
        r["action"]["type"] == "Delete"
        and r.get("condition", {}).get("tagState", "ANY") in ("UNTAGGED", "ANY")
        for r in policy
    )
    if deletes_untagged and not has_keep:
        raise StepError("policy deletes untagged versions with no Keep rule; the image Cloud Run "
                        "runs is untagged, so this would delete the running image.")


def select_revisions(revisions: Sequence[Dict[str, Any]], serving: Set[str], now: dt.datetime,
                     older_than_days: int, keep_newest: int) -> List[Dict[str, Any]]:
    """Revisions to delete: older than the window, beyond the newest few, and not serving.

    `serving` is every revision that receives traffic or is the latest ready one. A deploy made
    with `--no-traffic` leaves an OLD revision serving, so age alone is never the criterion.
    """
    ordered = sorted(revisions, key=lambda r: parse_ts(r["metadata"]["creationTimestamp"]), reverse=True)
    cutoff = now - dt.timedelta(days=older_than_days)
    chosen = []
    for position, rev in enumerate(ordered):
        if position < keep_newest:
            continue
        if rev["metadata"]["name"] in serving:
            continue
        if parse_ts(rev["metadata"]["creationTimestamp"]) > cutoff:
            continue
        chosen.append(rev)
    return chosen


def version_tags(version: Dict[str, Any]) -> List[str]:
    tags = version.get("tags") or []
    if isinstance(tags, str):
        tags = [t for t in tags.split(",") if t]
    return list(tags)


def _matches(version: Dict[str, Any], condition: Dict[str, Any], now: dt.datetime) -> bool:
    tags = version_tags(version)
    state = condition.get("tagState", "ANY")
    if state == "TAGGED" and not tags:
        return False
    if state == "UNTAGGED" and tags:
        return False
    prefixes = condition.get("tagPrefixes")
    if prefixes and not any(t.startswith(p) for t in tags for p in prefixes):
        return False
    older = condition.get("olderThan")
    if older and now - parse_ts(version["createTime"]) <= dt.timedelta(seconds=int(older.rstrip("s"))):
        return False
    return True


def simulate(policy: Sequence[Dict[str, Any]], versions: Sequence[Dict[str, Any]],
             now: dt.datetime) -> List[Dict[str, Any]]:
    """The versions the policy would delete: matched by a Delete rule and by no Keep rule.

    Mirrors the registry's documented semantics (Keep wins; `mostRecentVersions` counts per
    package). It is a safety check, not a promise about what the registry will do.
    """
    kept: Set[Tuple[str, str]] = set()
    doomed: Set[Tuple[str, str]] = set()
    by_package: Dict[str, List[Dict[str, Any]]] = {}
    for v in versions:
        by_package.setdefault(v["package"], []).append(v)
    for rule in policy:
        is_keep = rule["action"]["type"] == "Keep"
        if "mostRecentVersions" in rule:
            n = rule["mostRecentVersions"]["keepCount"]
            for group in by_package.values():
                newest = sorted(group, key=lambda v: parse_ts(v["createTime"]), reverse=True)[:n]
                (kept if is_keep else doomed).update((v["package"], v["version"]) for v in newest)
        elif "condition" in rule:
            hits = {(v["package"], v["version"]) for v in versions if _matches(v, rule["condition"], now)}
            (kept if is_keep else doomed).update(hits)
    wanted = doomed - kept
    return [v for v in versions if (v["package"], v["version"]) in wanted]


def digest_of(image_digest: str) -> str:
    """`region-docker.pkg.dev/p/r/svc@sha256:abc` → `sha256:abc`."""
    return image_digest.rsplit("@", 1)[-1] if image_digest else ""


def running_hazards(selected: Sequence[Dict[str, Any]], revisions: Sequence[Dict[str, Any]]) -> List[str]:
    live = {digest_of(r.get("status", {}).get("imageDigest", "")) for r in revisions}
    live.discard("")
    return sorted({v["version"] for v in selected if v["version"] in live})


def policy_names(repo: Dict[str, Any]) -> Set[str]:
    policies = repo.get("cleanupPolicies") or {}
    if isinstance(policies, dict):
        return set(policies)
    return {p["name"] for p in policies}


def docker_victims(images: Sequence[Dict[str, Any]], prefix: str, keep: int) -> List[str]:
    """Tagged images under `prefix` to remove: all but the newest `keep` per repository.

    `images` is `docker image inspect` output. A reference outside `prefix` or tagged `latest` is
    never returned, so this cannot reach another project's images.
    """
    by_repo: Dict[str, List[Tuple[dt.datetime, str]]] = {}
    for img in images:
        created = parse_ts(img["Created"])
        for ref in img.get("RepoTags") or []:
            repo, _, tag = ref.rpartition(":")
            if not repo.startswith(prefix + "/") or tag in PROTECTED_TAGS or tag in ("", "<none>"):
                continue
            by_repo.setdefault(repo, []).append((created, ref))
    victims = []
    for entries in by_repo.values():
        entries.sort(key=lambda e: e[0], reverse=True)
        victims.extend(ref for _, ref in entries[keep:])
    return sorted(victims)


# ──────────────────────────────── tools ────────────────────────────────


def run(cmd: Sequence[str]) -> str:
    """Run a command and return stdout; a non-zero exit is a StepError that quotes the stderr."""
    try:
        proc = subprocess.run(list(cmd), capture_output=True, text=True)
    except FileNotFoundError:
        raise StepError("%s is not on PATH." % cmd[0])
    if proc.returncode != 0:
        raise StepError("`%s` exited %d: %s" % (" ".join(cmd), proc.returncode, proc.stderr.strip()))
    return proc.stdout


def run_json(cmd: Sequence[str]) -> Any:
    out = run(list(cmd) + ["--format=json"])
    try:
        return json.loads(out) if out.strip() else []
    except ValueError as exc:
        raise StepError("`%s` printed output that is not JSON (%s)." % (" ".join(cmd), exc))


# ──────────────────────────────── steps ────────────────────────────────


def list_revisions(a: argparse.Namespace) -> List[Dict[str, Any]]:
    return run_json(["gcloud", "run", "revisions", "list", "--service=" + a.service,
                     "--project=" + a.project, "--region=" + a.region])


def serving_revisions(a: argparse.Namespace) -> Set[str]:
    svc = run_json(["gcloud", "run", "services", "describe", a.service,
                    "--project=" + a.project, "--region=" + a.region])
    status = svc.get("status", {})
    names = {t["revisionName"] for t in status.get("traffic", []) if t.get("revisionName")}
    if status.get("latestReadyRevisionName"):
        names.add(status["latestReadyRevisionName"])
    if not names:
        raise StepError("could not establish which revision serves %s (no traffic entry, no latest "
                        "ready revision); refusing to choose revisions to delete." % a.service)
    return names


def step_revisions(a: argparse.Namespace, now: dt.datetime, ctx: Dict[str, Any]) -> List[str]:
    """Delete the selected revisions; leave in `ctx["remaining"]` what the registry step must protect."""
    failures: List[str] = []
    before = list_revisions(a)
    serving = serving_revisions(a)
    chosen = select_revisions(before, serving, now, a.revision_days, a.keep_revisions)
    lib.info("revisions: %d listed, serving %s; %d to delete (older than %dd, beyond the newest %d)"
             % (len(before), ", ".join(sorted(serving)), len(chosen), a.revision_days, a.keep_revisions))
    for rev in chosen:
        name = rev["metadata"]["name"]
        if a.dry_run:
            lib.ok("would delete revision %s" % name)
            continue
        try:
            run(["gcloud", "run", "revisions", "delete", name, "--project=" + a.project,
                 "--region=" + a.region, "--quiet"])
            lib.ok("deleted revision %s" % name)
        except StepError as exc:
            failures.append(str(exc))
            lib.fail("revision %s" % name, [str(exc)])
    if a.dry_run:
        gone = {r["metadata"]["name"] for r in chosen}
        ctx["remaining"] = [r for r in before if r["metadata"]["name"] not in gone]
    else:
        ctx["remaining"] = list_revisions(a)
        lib.info("revisions: %d before, %d after (listed again, not assumed)" % (len(before), len(ctx["remaining"])))
    return failures


def step_registry(a: argparse.Namespace, now: dt.datetime, ctx: Dict[str, Any]) -> List[str]:
    policy = build_policy(a.keep_versions, a.image_days, a.tag_prefixes)
    wanted = {r["name"] for r in policy}
    registry = "%s-docker.pkg.dev/%s/%s" % (a.region, a.project, a.repo)
    repo = run_json(["gcloud", "artifacts", "repositories", "describe", a.repo,
                     "--project=" + a.project, "--location=" + a.region])
    armed = policy_names(repo) == wanted and not repo.get("cleanupPolicyDryRun")
    staged = policy_names(repo) == wanted and bool(repo.get("cleanupPolicyDryRun"))

    versions = run_json(["gcloud", "artifacts", "docker", "images", "list", registry, "--include-tags"])
    revisions = ctx["remaining"] if "remaining" in ctx else list_revisions(a)
    selected = simulate(policy, versions, now)
    lib.info("registry %s: %d versions listed; the policy would expire %d" % (registry, len(versions), len(selected)))
    for v in selected:
        lib.ok("would expire %s %s %s" % (v["package"].rsplit("/", 1)[-1], v["version"][:19],
                                          ",".join(version_tags(v)) or "(untagged)"))

    hazards = running_hazards(selected, revisions)
    if hazards:
        if armed:
            _set_policy(a, policy, "--dry-run")
        raise StepError(
            "the policy would expire an image a revision still runs (%s)%s. Raise keep-versions, or "
            "delete the revisions that run them, then re-run." %
            (", ".join(hazards), "; the armed policy was put back into dry run" if armed else ""))

    if armed:
        lib.info("registry policy already current (%s); nothing to change." % ", ".join(sorted(wanted)))
        return []
    if a.dry_run or not staged:
        if staged:
            lib.info("registry policy already staged in dry run; --dry-run changes nothing.")
        else:
            _set_policy(a, policy, "--dry-run")
            lib.warn("registry policy STAGED IN DRY RUN, NOT ARMED. Read the list above; the next run arms it.")
        return []
    _set_policy(a, policy, "--no-dry-run")
    after = run_json(["gcloud", "artifacts", "repositories", "describe", a.repo,
                      "--project=" + a.project, "--location=" + a.region])
    if after.get("cleanupPolicyDryRun") or policy_names(after) != wanted:
        raise StepError("armed the policy but the repository does not report it as current; check "
                        "`gcloud artifacts repositories describe %s`." % a.repo)
    lib.ok("registry policy armed. The registry deletes asynchronously and meters size periodically: "
           "list versions again later, and do not claim a saving until the size is re-measured.")
    return []


def _write_policy(policy: Sequence[Dict[str, Any]]) -> str:
    handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(list(policy), handle)
    handle.close()
    return handle.name


def _set_policy(a: argparse.Namespace, policy: Sequence[Dict[str, Any]], mode: str) -> None:
    path = _write_policy(policy)
    try:
        run(["gcloud", "artifacts", "repositories", "set-cleanup-policies", a.repo,
             "--project=" + a.project, "--location=" + a.region, "--policy=" + path, mode])
    finally:
        Path(path).unlink(missing_ok=True)


def step_docker(a: argparse.Namespace) -> List[str]:
    if shutil.which("docker") is None:
        lib.info("docker: not on PATH, nothing local to clean.")
        return []
    failures: List[str] = []
    prefix = "%s-docker.pkg.dev/%s/%s" % (a.region, a.project, a.repo)
    refs = [r for r in run(["docker", "image", "ls", "--format", "{{.Repository}}:{{.Tag}}"]).split()
            if r.startswith(prefix + "/")]
    images = json.loads(run(["docker", "image", "inspect"] + refs)) if refs else []
    victims = docker_victims(images, prefix, DOCKER_KEEP_PER_REPOSITORY)
    lib.info("docker: %d of this project's tagged images to remove (keeping the newest %d per repository)"
             % (len(victims), DOCKER_KEEP_PER_REPOSITORY))
    steps = [("remove image %s" % v, ["docker", "rmi", v]) for v in victims]
    steps.append(("prune dangling layers", ["docker", "image", "prune", "-f"]))
    steps.append(("prune build cache older than %dh" % a.docker_cache_hours,
                  ["docker", "builder", "prune", "-f", "--filter", "until=%dh" % a.docker_cache_hours]))
    for label, cmd in steps:
        if a.dry_run:
            lib.ok("would " + label)
            continue
        try:
            run(cmd)
            lib.ok(label)
        except StepError as exc:
            failures.append(str(exc))
            lib.fail(label, [str(exc)])
    return failures


# ──────────────────────────────── entry ────────────────────────────────


def parse_args(argv: Optional[Sequence[str]]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    for name in ("project", "region", "service", "repo"):
        p.add_argument("--" + name, required=True)
    for name in ("keep-revisions", "revision-days", "keep-versions", "image-days", "docker-cache-hours"):
        p.add_argument("--" + name, type=int, required=True)
    p.add_argument("--tag-prefixes", default=",".join(DEFAULT_TAG_PREFIXES),
                   help="comma-separated tag prefixes the tagged-delete rule may expire")
    for name in ("revisions", "registry", "docker"):
        p.add_argument("--" + name, choices=("on", "off"), required=True)
    p.add_argument("--on-failure", choices=("fail", "warn"), default="fail")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args(argv)
    a.tag_prefixes = [t for t in a.tag_prefixes.split(",") if t]
    if a.keep_revisions < 1:
        p.error("--keep-revisions must be at least 1")
    if a.revision_days >= a.image_days:
        p.error("--revision-days (%d) must be shorter than --image-days (%d): an image is older than "
                "its revision, so equal windows let the registry expire an image whose revision is "
                "still listed." % (a.revision_days, a.image_days))
    return a


def main(argv: Optional[Sequence[str]] = None, now: Optional[dt.datetime] = None) -> int:
    a = parse_args(argv)
    now = now or dt.datetime.now(dt.timezone.utc)
    failures: List[str] = []
    ctx: Dict[str, Any] = {}

    def guarded(label: str, step) -> bool:
        try:
            failures.extend(step())
            return True
        except StepError as exc:
            failures.append("%s: %s" % (label, exc))
            lib.fail(label, [str(exc)])
            return False

    lib.info("cleanup%s for %s/%s (%s)" % (" [DRY RUN]" if a.dry_run else "", a.project, a.service, a.region))
    revisions_ok = True
    if a.revisions == "on":
        revisions_ok = guarded("revisions", lambda: step_revisions(a, now, ctx))
    else:
        lib.info("revisions: skipped (off)")
    if a.registry == "on":
        # Never arm a policy past a revision step that did not finish: what still lists as a
        # rollback target is exactly what the policy must not outrun.
        if revisions_ok:
            guarded("registry", lambda: step_registry(a, now, ctx))
        else:
            failures.append("registry: skipped because the revision step failed")
            lib.fail("registry skipped: the revision step failed")
    else:
        lib.info("registry: skipped (off)")
    if a.docker == "on":
        guarded("docker", lambda: step_docker(a))
    else:
        lib.info("docker: skipped (off)")

    if not failures:
        lib.ok("cleanup finished with no failures")
        return 0
    print()
    print("Cleanup problems (the deploy itself succeeded; this is the cleanup after it):")
    for f in failures:
        print("  - " + f)
    if a.on_failure == "warn":
        lib.warn("--on-failure warn: reporting and exiting 0.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
