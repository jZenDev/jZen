"""Keep Artifact Registry, Cloud Run revisions and local Docker bounded after a deploy.

Run by `task zen:deploy:cleanup` (Taskfile.app.yml), which carries the operator-facing contract
(`task zen:deploy:cleanup --summary`); this docstring is about the implementation.

Three parts, in this order, and the order is the design:

1. REVISIONS first. A Cloud Run revision is not a reference the registry respects, so the revisions
   that remain are bounded here and the registry step below is told about every one of them.
   Revisions are deleted before the policy is armed, and the policy's window is refused unless it
   is longer than the revisions' (the image is older than its revision by the build time, so equal
   windows would expire the image first).
2. The REGISTRY POLICY. Keep the newest N versions per package; delete tagged versions (by tag
   prefix, never `latest`) and untagged versions older than the window. A count and an age cannot
   protect an arbitrarily old image that something still runs — a serving revision, a rollback
   target, a Cloud Run job — so protection is carried by the image itself: every digest a
   consumer needs gets a PIN TAG (`zen-pin-<digest>`) and the policy has a Keep rule on that tag
   prefix. A Keep rule outranks every Delete rule, and a pinned version is *tagged*, so it is
   outside the untagged Delete rule as well; the protection does not depend on how old the image
   is, how many newer ones exist, or when the policy next runs. Pins are added BEFORE the policy
   is staged, armed or left armed, and released only for a digest no consumer needs — for every
   consumer this script can enumerate (all revisions and jobs in the project and region), and
   never for an operator `zen-hold-*` tag, which is how a consumer it cannot see is protected.
   The untagged rule remains safe only beside the Keep rules, so `build_policy` refuses a policy
   that deletes anything without them. Before the policy is armed it is simulated against the
   registry's own version list, with the parent/child references between a tagged index and the
   images it lists; a digest a consumer needs that the simulation still expires means a pin
   failed, and the policy is not armed (an armed one is put back into dry run).
3. LOCAL DOCKER: dangling layers, aged build cache, and this project's tagged images beyond the two
   newest per repository. Never `latest`, never anything outside this project's registry path.

A deploy pins its own image with `pin` (below) BEFORE any job or service is pointed at it, so a new
consumer is never ahead of its protection.

Two-phase arming. The first run on a repository stages the policy in the registry's own dry-run
state and stops there; the run after that arms it. The registry is the memory, so "a dry run was
required once" cannot be skipped by a fresh checkout. Replacing an already ARMED policy of an older
shape stages the new one in dry run the same way, after the pins exist, so enforcement pauses for
one run instead of continuing without protection. `--dry-run` stages without arming, adds and
releases no pin, and deletes nothing anywhere: it prints the pins it would add and release.

Failure semantics: every step runs and reports; any failure makes the exit code non-zero
(`--on-failure fail`, the default) with the words "the deploy itself succeeded", or is printed as a
warning and exits 0 (`--on-failure warn`). Nothing is piped to `sh` or `|| true`d.

Deletions are not in Cloud Logging unless Data Access audit logs are enabled for
artifactregistry.googleapis.com, and the repository's reported size lags deletion, so the evidence
this prints is a before/after LISTING, not a size.

Every value the operator supplies reaches `subprocess` as one element of an argument list, so a
shell never sees it and `;`, `$()` or a space in a name is just a character. What a list does not
prevent is an element that the called tool reads as an OPTION: `gcloud run services describe
--impersonate-service-account=...` is a service whose name starts with a dash. `--project=VALUE`
forms are immune (the value cannot start a new option), the positional ones are not (the service,
the repository, an image reference). So each name is checked once, where it enters
(`parse_args`, `pin_image`), against the shape its resource allows, and in every case the first
character is a letter or a digit. A value that does not fit is a usage error before any command
runs; the cleanup is not partially run on a name it could not vouch for.

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
# number re-arms an existing repository without touching this. v2 added the pin Keep rule.
POLICY_REVISION = "v2"

# A tag on a digest that a consumer (a revision, a job) needs. Owned by this script: added when a
# consumer needs the digest, removed when none does. Neither prefix begins with a hex digit or
# `sha256-`, so the tagged Delete rule can never match a pin even if the Keep rule were missing.
PIN_PREFIX = "zen-pin-"
# A tag an OPERATOR adds for a consumer this script cannot enumerate (another project, another
# region, a non-Cloud-Run puller). Never removed by this script.
HOLD_PREFIX = "zen-hold-"
PROTECTING_PREFIXES = [PIN_PREFIX, HOLD_PREFIX]

# A pin is not released while its version is younger than this, so a cleanup that runs while a
# deploy has pushed and pinned an image but not yet pointed a job or service at it cannot undo it.
PIN_RELEASE_GRACE = dt.timedelta(hours=24)

# A tag begins with a hex digit when it is a (short) commit SHA — what `deploy:cloudrun` pushes,
# with an optional `-dirty` — or with `sha256-` when it is a cosign signature/attestation, which is
# tagged on the registry and would otherwise outlive the image it signs. `latest` and `stable`
# start with neither. Any other tag that starts with a hex digit (`1.0.0`) is expiry-eligible too;
# an application that keeps such tags overrides the prefixes.
DEFAULT_TAG_PREFIXES = list("0123456789abcdef") + ["sha256-"]

DOCKER_KEEP_PER_REPOSITORY = 2
PROTECTED_TAGS = {"latest"}

# The shape of each name taken from the command line. Deliberately no stricter than the resource
# allows (a short name is fine; length is the platform's to enforce); what they all share, and what
# matters here, is that the first character is a letter or digit, so no value can be read by gcloud
# or docker as an option, and that nothing in them is whitespace or a control character.
NAME_SHAPES = {
    "project": re.compile(r"[a-z][a-z0-9-]*"),
    "region": re.compile(r"[a-z][a-z0-9-]*"),
    "service": re.compile(r"[a-z][a-z0-9-]*"),
    "repo": re.compile(r"[a-z0-9][a-z0-9._-]*"),
    "image": re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/@-]*"),
}
# A tag prefix is the start of a tag, and a tag starts with [A-Za-z0-9_].
TAG_PREFIX_SHAPE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]*")


def name_arg(kind: str):
    """An argparse `type=` that accepts only a value of `kind`'s shape (see NAME_SHAPES)."""
    shape = NAME_SHAPES[kind]

    def parse(value: str) -> str:
        if not shape.fullmatch(value):
            raise argparse.ArgumentTypeError(
                "%r is not a valid %s name (it must start with a letter or digit and contain no "
                "whitespace or shell characters)" % (value, kind))
        return value

    parse.__name__ = kind
    return parse


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


def policy_id(prefixes: Sequence[str]) -> str:
    """The short identifier of a tag-prefix list, embedded in the tagged Delete rule's name.

    It names a policy, it does not authenticate one: the input is the operator's own flag, nobody
    else chooses it, and there is no secret to protect or signature to forge, so collision
    resistance against an adversary is not a requirement (`usedforsecurity=False` says so, and keeps
    it working where a build refuses SHA-1 for security uses). What it must be is STABLE: the value
    is part of a rule name already stored in every repository this script has armed, and changing
    the function would rename the rule and put each of those repositories back through a dry run.
    The delimiter cannot appear in a prefix (`build_policy` refuses anything outside a tag's
    characters), so two different lists never share an input.
    """
    return hashlib.sha1("\n".join(prefixes).encode("utf-8"), usedforsecurity=False).hexdigest()[:8]


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
    for prefix in prefixes:
        if not TAG_PREFIX_SHAPE.fullmatch(prefix):
            raise StepError("tag prefix %r cannot begin any tag (tags use letters, digits, '_', '.' "
                            "and '-', and start with a letter, digit or '_')." % prefix)
    for tag in sorted(PROTECTED_TAGS) + PROTECTING_PREFIXES:
        if any(tag.startswith(p) for p in prefixes):
            raise StepError("tag prefix %r would also match the protected tag %r." %
                            (next(p for p in prefixes if tag.startswith(p)), tag))
    seconds = "%ds" % (image_days * 86400)
    digest = policy_id(prefixes)
    policy = [
        {
            "name": "zen-%s-keep-newest-%d" % (POLICY_REVISION, keep_versions),
            "action": {"type": "Keep"},
            "mostRecentVersions": {"keepCount": keep_versions},
        },
        {
            "name": "zen-%s-keep-pinned" % POLICY_REVISION,
            "action": {"type": "Keep"},
            "condition": {"tagState": "TAGGED", "tagPrefixes": list(PROTECTING_PREFIXES)},
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
    # The pin rule is what protects an image that is old and no longer among the newest: without
    # it the count and the age are the only protection, and neither covers an arbitrary old consumer.
    has_pin_keep = any(
        r["action"]["type"] == "Keep"
        and r.get("condition", {}).get("tagState") == "TAGGED"
        and set(PROTECTING_PREFIXES) <= set(r.get("condition", {}).get("tagPrefixes", []))
        for r in policy
    )
    if any(r["action"]["type"] == "Delete" for r in policy) and not has_pin_keep:
        raise StepError("policy deletes versions with no Keep rule for the pin tags (%s); an image "
                        "a revision or job needs would be protected only by age and count." %
                        ", ".join(PROTECTING_PREFIXES))


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


Key = Tuple[str, str]  # (package, version digest)


def simulate(policy: Sequence[Dict[str, Any]], versions: Sequence[Dict[str, Any]],
             now: dt.datetime, children: Optional[Dict[Key, Sequence[str]]] = None) -> List[Dict[str, Any]]:
    """The versions the policy would delete, over successive runs of the registry's evaluation.

    Mirrors the registry's documented semantics (Keep wins; `mostRecentVersions` counts per
    package; a version listed by a parent manifest is not deleted while the parent exists). It is a
    safety check, not a promise about what the registry will do.

    `children` maps a parent (an image index) to the digests it lists. A selected child whose
    parent survives is shielded, so it is not proof of anything that it matched a Delete rule; but
    once the parent is itself deleted the child is evaluated again by the same rules, so a child is
    reported only when every parent it has would also go. That is the *eventual* set: the registry
    evaluates asynchronously and repeatedly, and an answer for one pass would be false safety for
    the next. Without `children` this is an upper bound, which is the safe direction to be wrong.
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
    known = {(v["package"], v["version"]) for v in versions}
    parents: Dict[Key, List[Key]] = {}
    for (package, parent), kids in (children or {}).items():
        if (package, parent) not in known:
            continue  # a parent the listing does not show shields nothing we can verify
        for kid in kids:
            parents.setdefault((package, kid), []).append((package, parent))
    memo: Dict[Key, bool] = {}

    def eventually_deleted(key: Key) -> bool:
        if key not in memo:
            memo[key] = False  # a reference cycle shields nothing it cannot prove
            memo[key] = key in wanted and all(eventually_deleted(p) for p in parents.get(key, []))
        return memo[key]

    return [v for v in versions if eventually_deleted((v["package"], v["version"]))]


def digest_of(image_digest: str) -> str:
    """`region-docker.pkg.dev/p/r/svc@sha256:abc` → `sha256:abc`."""
    return image_digest.rsplit("@", 1)[-1] if image_digest else ""


def usable_digest(digest: str) -> bool:
    return digest.startswith("sha256:") and len(digest) > len("sha256:")


def pin_tag(digest: str) -> str:
    return PIN_PREFIX + digest.split(":", 1)[1]


def package_of(image: str) -> str:
    """`host/p/r/svc:tag@sha256:abc`, `host/p/r/svc@sha256:abc` or `host/p/r/svc:tag` → `host/p/r/svc`."""
    path = image.split("@", 1)[0]
    head, _, last = path.rpartition("/")
    return (head + "/" if head else "") + last.split(":", 1)[0]


def consumer(kind: str, name: str, package: str, digest: str = "", tag: str = "") -> Dict[str, str]:
    return {"kind": kind, "name": name, "package": package, "digest": digest, "tag": tag}


def revision_consumers(revisions: Sequence[Dict[str, Any]], registry: str,
                       strict: bool = True) -> List[Dict[str, str]]:
    """The digests that Cloud Run revisions run, for those in `registry`.

    A revision of THIS service with no usable digest is an error, not a skip: it cannot be proven to
    be outside the registry, and a policy assessed without it is assessed without a consumer. With
    `strict=False` (another service's revisions) it is skipped with a warning instead, because a
    revision that never started has no image to protect and one unrelated broken service must not
    block this service's cleanup for good.
    """
    found = []
    for revision in revisions:
        name = revision.get("metadata", {}).get("name", "(unknown)")
        image_digest = revision.get("status", {}).get("imageDigest", "")
        digest = digest_of(image_digest)
        if not usable_digest(digest):
            if not strict:
                lib.warn("revision %s (another service) reports no image digest; not treated as a "
                         "consumer." % name)
                continue
            raise StepError("revision %s has no usable image digest; refusing to assess registry safety."
                            % name)
        if package_of(image_digest).startswith(registry + "/"):
            found.append(consumer("revision", name, package_of(image_digest), digest))
    return found


def job_consumers(jobs: Sequence[Dict[str, Any]], registry: str) -> List[Dict[str, str]]:
    """The images that Cloud Run jobs name, for those in `registry`. A job names a tag or a digest."""
    found = []
    for job in jobs:
        name = job.get("metadata", {}).get("name", "(unknown)")
        containers = (job.get("spec", {}).get("template", {}).get("spec", {})
                      .get("template", {}).get("spec", {}).get("containers", []))
        for container in containers:
            image = container.get("image", "")
            if not image:
                raise StepError("job %s has a container with no image; refusing to assess registry "
                                "safety." % name)
            if not package_of(image).startswith(registry + "/"):
                continue
            if "@" in image:
                digest = digest_of(image)
                if not usable_digest(digest):
                    raise StepError("job %s names image %s with no usable digest." % (name, image))
                found.append(consumer("job", name, package_of(image), digest))
            else:
                last = image.rsplit("/", 1)[-1]
                found.append(consumer("job", name, package_of(image), tag=last.split(":", 1)[1] if ":" in last else "latest"))
    return found


def resolve_consumers(consumers: Sequence[Dict[str, str]], versions: Sequence[Dict[str, Any]]
                      ) -> Tuple[List[Dict[str, str]], List[str]]:
    """Resolve a consumer that names a tag to the digest the registry has under it.

    Returns the resolved consumers whose digest is in the registry, and a sentence for each that is
    not: an image already gone cannot be protected, and arming past it would hide that it is.
    """
    by_tag: Dict[Tuple[str, str], str] = {}
    present: Set[Key] = set()
    for v in versions:
        present.add((v["package"], v["version"]))
        for tag in version_tags(v):
            by_tag[(v["package"], tag)] = v["version"]
    resolved, missing = [], []
    for c in consumers:
        digest = c["digest"] or by_tag.get((c["package"], c["tag"]), "")
        if not digest or (c["package"], digest) not in present:
            missing.append("%s %s runs %s@%s, which is not in the registry; it cannot be protected and "
                           "cannot start. Delete or redeploy it." %
                           (c["kind"], c["name"], c["package"], digest or ":" + c["tag"]))
            continue
        resolved.append(dict(c, digest=digest))
    return resolved, missing


def current_pins(versions: Sequence[Dict[str, Any]]) -> Set[Key]:
    """Versions that carry a pin tag. A pin tag names its own digest, so one that does not is corrupt."""
    pinned: Set[Key] = set()
    for v in versions:
        for tag in version_tags(v):
            if tag.startswith(PIN_PREFIX):
                if tag != pin_tag(v["version"]):
                    raise StepError("tag %s on %s does not name that version; remove it by hand "
                                    "(`gcloud artifacts docker tags delete`) so protection is not "
                                    "attributed to the wrong digest." % (tag, v["version"]))
                pinned.add((v["package"], v["version"]))
    return pinned


def plan_pins(needed: Set[Key], versions: Sequence[Dict[str, Any]], now: dt.datetime
              ) -> Tuple[List[Key], List[Key], Set[Key]]:
    """(to add, to release, the pins that exist once both are done).

    A pin is released only when no consumer needs the digest and its version is older than
    PIN_RELEASE_GRACE. Operator `zen-hold-*` tags are not pins and are never touched here.
    """
    existing = current_pins(versions)
    created = {(v["package"], v["version"]): parse_ts(v["createTime"]) for v in versions}
    to_add = sorted(needed - existing)
    to_release = sorted(k for k in existing - needed if now - created[k] > PIN_RELEASE_GRACE)
    return to_add, to_release, (existing | needed) - set(to_release)


def with_pins(versions: Sequence[Dict[str, Any]], pins: Set[Key]) -> List[Dict[str, Any]]:
    """Copies of `versions` as they will list once exactly `pins` carry a pin tag."""
    out = []
    for v in versions:
        tags = [t for t in version_tags(v) if not t.startswith(PIN_PREFIX)]
        if (v["package"], v["version"]) in pins:
            tags.append(pin_tag(v["version"]))
        out.append(dict(v, tags=tags))
    return out


def running_hazards(selected: Sequence[Dict[str, Any]], consumers: Sequence[Dict[str, str]]) -> List[str]:
    """Digests a consumer needs that the policy would still expire: a pin did not take effect."""
    live = {(c["package"], c["digest"]) for c in consumers}
    return sorted({v["version"] for v in selected if (v["package"], v["version"]) in live})


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


def list_other_revisions(a: argparse.Namespace) -> List[Dict[str, Any]]:
    """Every revision in the region that belongs to another service: they pull from this registry too.

    A revision with no service label cannot be shown to be this service's, so it is kept here:
    pinning a digest twice costs nothing, and not pinning one is the failure this exists to prevent.
    """
    everything = run_json(["gcloud", "run", "revisions", "list", "--project=" + a.project,
                           "--region=" + a.region])
    return [r for r in everything
            if r.get("metadata", {}).get("labels", {}).get("serving.knative.dev/service") != a.service]


def list_jobs(a: argparse.Namespace) -> List[Dict[str, Any]]:
    return run_json(["gcloud", "run", "jobs", "list", "--project=" + a.project, "--region=" + a.region])


def fetch_children(versions: Sequence[Dict[str, Any]]) -> Tuple[Dict[Key, List[str]], List[str]]:
    """Which digests each tagged version lists, read from the manifest itself.

    The version listing does not say that an index references an image; the manifest does. `docker
    buildx imagetools inspect --raw` prints it with the credentials `docker push` already uses. A
    manifest that cannot be read is reported, not guessed: the simulation then has no parent for it
    and so reports more deletions than the registry will make, which is the safe direction.
    """
    if shutil.which("docker") is None:
        return {}, ["docker is not on PATH, so no parent/child reference could be read"]
    children: Dict[Key, List[str]] = {}
    unreadable: List[str] = []
    for v in versions:
        if not version_tags(v):
            continue
        ref = "%s@%s" % (v["package"], v["version"])
        try:
            manifest = json.loads(run(["docker", "buildx", "imagetools", "inspect", "--raw", ref]))
        except (StepError, ValueError) as exc:
            unreadable.append("%s: %s" % (ref, exc))
            continue
        kids = [m["digest"] for m in manifest.get("manifests", []) if m.get("digest")]
        if kids:
            children[(v["package"], v["version"])] = kids
    return children, unreadable


def _tag_add(package: str, digest: str, tag: str) -> None:
    run(["gcloud", "artifacts", "docker", "tags", "add", "%s@%s" % (package, digest),
         "%s:%s" % (package, tag)])


def _tag_delete(package: str, tag: str) -> None:
    run(["gcloud", "artifacts", "docker", "tags", "delete", "%s:%s" % (package, tag), "--quiet"])


def step_registry(a: argparse.Namespace, now: dt.datetime, ctx: Dict[str, Any]) -> List[str]:
    policy = build_policy(a.keep_versions, a.image_days, a.tag_prefixes)
    wanted = {r["name"] for r in policy}
    registry = "%s-docker.pkg.dev/%s/%s" % (a.region, a.project, a.repo)
    repo = run_json(["gcloud", "artifacts", "repositories", "describe", a.repo,
                     "--project=" + a.project, "--location=" + a.region])
    armed = policy_names(repo) == wanted and not repo.get("cleanupPolicyDryRun")
    staged = policy_names(repo) == wanted and bool(repo.get("cleanupPolicyDryRun"))
    # Whatever policy is active right now, of this shape or an older one, is enforcing.
    enforcing = bool(policy_names(repo)) and not repo.get("cleanupPolicyDryRun")
    failures: List[str] = []

    def stand_down(why: str) -> str:
        """Stop an enforcing policy enforcing, so that a failure here cannot be the failure that expires an image."""
        if not enforcing or a.dry_run:
            return why
        _set_policy(a, policy, "--dry-run")
        return why + "; the active policy was put back into dry run"

    versions = run_json(["gcloud", "artifacts", "docker", "images", "list", registry, "--include-tags"])
    # Every consumer, not only this service's: a job and another service pull from this repository
    # too, and a digest is released only when none of them needs it.
    try:
        service_revisions = ctx["remaining"] if "remaining" in ctx else list_revisions(a)
        consumers, missing = resolve_consumers(
            revision_consumers(service_revisions, registry)
            + revision_consumers(list_other_revisions(a), registry, strict=False)
            + job_consumers(list_jobs(a), registry), versions)
    except StepError as exc:
        # Without the consumer list nothing can be pinned, so an enforcing policy is running
        # unprotected: stop it enforcing rather than leave it to the next run.
        raise StepError(stand_down("could not establish which images are in use (%s)" % exc))
    needed = {(c["package"], c["digest"]) for c in consumers}
    to_add, to_release, pins = plan_pins(needed, versions, now)
    if missing:
        to_release = []  # a consumer we could not resolve makes "nothing needs this" unprovable
        pins = current_pins(versions) | needed
    lib.info("registry %s: %d versions listed; %d consumers (%d revisions, %d jobs) need %d digests; "
             "%d pinned already, %d to pin, %d to release" %
             (registry, len(versions), len(consumers),
              sum(c["kind"] == "revision" for c in consumers), sum(c["kind"] == "job" for c in consumers),
              len(needed), len(needed & current_pins(versions)), len(to_add), len(to_release)))

    # Protection first, before the policy is staged, armed or left armed.
    for package, digest in to_add:
        if a.dry_run:
            lib.ok("would pin %s@%s" % (package.rsplit("/", 1)[-1], digest[:19]))
            continue
        try:
            _tag_add(package, digest, pin_tag(digest))
            lib.ok("pinned %s@%s" % (package.rsplit("/", 1)[-1], digest[:19]))
        except StepError as exc:
            raise StepError(stand_down("could not pin %s@%s, so nothing may expire past it (%s)" %
                                       (package, digest, exc)))
    for package, digest in to_release:
        if a.dry_run:
            lib.ok("would release the pin on %s@%s: no revision or job needs it" %
                   (package.rsplit("/", 1)[-1], digest[:19]))
            continue
        try:
            _tag_delete(package, pin_tag(digest))
            lib.ok("released the pin on %s@%s: no revision or job needs it" %
                   (package.rsplit("/", 1)[-1], digest[:19]))
        except StepError as exc:
            pins.add((package, digest))  # still pinned, which is the safe way to have failed
            failures.append("registry: could not release a pin (%s)" % exc)
            lib.fail("release pin %s" % digest[:19], [str(exc)])

    future = with_pins(versions, pins)
    children, unreadable = fetch_children(future)
    if unreadable:
        lib.warn("parent/child references not fully modelled; the list below is an upper bound: %s"
                 % "; ".join(unreadable[:3]))
    selected = simulate(policy, future, now, children)
    lib.info("the policy would expire %d versions, over its successive runs" % len(selected))
    for v in selected:
        lib.ok("would expire %s %s %s" % (v["package"].rsplit("/", 1)[-1], v["version"][:19],
                                          ",".join(version_tags(v)) or "(untagged)"))

    hazards = running_hazards(selected, consumers)
    if hazards:
        raise StepError(stand_down(
            "the policy would still expire a digest a revision or job needs (%s) although it is "
            "pinned" % ", ".join(hazards)))
    if missing:
        for sentence in missing:
            lib.fail("registry", [sentence])
        raise StepError("not arming or advancing the policy past an image that is already gone: "
                        + " ".join(missing))

    if armed:
        lib.info("registry policy already current (%s); nothing to change." % ", ".join(sorted(wanted)))
        return failures
    if a.dry_run or not staged:
        if staged:
            lib.info("registry policy already staged in dry run; --dry-run changes nothing.")
        else:
            _set_policy(a, policy, "--dry-run")
            lib.warn("registry policy STAGED IN DRY RUN, NOT ARMED. Read the list above; the next run arms it.")
        return failures
    _set_policy(a, policy, "--no-dry-run")
    after = run_json(["gcloud", "artifacts", "repositories", "describe", a.repo,
                      "--project=" + a.project, "--location=" + a.region])
    if after.get("cleanupPolicyDryRun") or policy_names(after) != wanted:
        raise StepError("armed the policy but the repository does not report it as current; check "
                        "`gcloud artifacts repositories describe %s`." % a.repo)
    lib.ok("registry policy armed. The registry deletes asynchronously and meters size periodically: "
           "list versions again later, and do not claim a saving until the size is re-measured.")
    return failures


def pin_image(argv: Sequence[str]) -> int:
    """`pin`: protect an image BEFORE a job or service is pointed at it. Exits non-zero if it cannot."""
    p = argparse.ArgumentParser(prog="deploy-cleanup.py pin",
                                description="pin an image so the registry policy cannot expire it")
    for name in ("project", "region", "repo", "image"):
        p.add_argument("--" + name, required=True, type=name_arg(name))
    p.add_argument("--hold", default="",
                   help="add an operator hold (zen-hold-NAME) instead of a pin; the cleanup never removes it")
    a = p.parse_args(argv)
    if a.hold and not re.fullmatch(r"[A-Za-z0-9_.-]{1,60}", a.hold):
        p.error("--hold may contain letters, digits, '_', '.' and '-' only")
    try:
        registry = "%s-docker.pkg.dev/%s/%s" % (a.region, a.project, a.repo)
        package = package_of(a.image)
        if not package.startswith(registry + "/"):
            raise StepError("%s is not under %s; refusing to tag an image in another repository." %
                            (a.image, registry))
        versions = run_json(["gcloud", "artifacts", "docker", "images", "list", registry, "--include-tags"])
        wanted_tag = a.image.split("@", 1)[0].rsplit("/", 1)[-1].partition(":")[2]
        digest = digest_of(a.image) if "@" in a.image else ""
        for v in versions:
            if v["package"] == package and (v["version"] == digest or (wanted_tag and wanted_tag in version_tags(v))):
                digest = v["version"]
                break
        else:
            raise StepError("%s is not in the registry; nothing was pinned, and nothing should point at it." % a.image)
        tag = (HOLD_PREFIX + a.hold) if a.hold else pin_tag(digest)
        for v in versions:
            if v["package"] == package and tag in version_tags(v) and v["version"] != digest:
                raise StepError("tag %s already protects %s; a tag names one digest, so use another "
                                "--hold name rather than move it." % (tag, v["version"]))
        _tag_add(package, digest, tag)
        lib.ok("%s %s@%s as %s" % ("held" if a.hold else "pinned", package, digest, tag))
        return 0
    except StepError as exc:
        lib.fail("pin", [str(exc)])
        return 1


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
        p.add_argument("--" + name, required=True, type=name_arg(name))
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
    args = list(sys.argv[1:] if argv is None else argv)
    if args[:1] == ["pin"]:
        return pin_image(args[1:])
    a = parse_args(argv)
    now = now or dt.datetime.now(dt.timezone.utc)
    failures: List[str] = []
    ctx: Dict[str, Any] = {}

    def guarded(label: str, step) -> bool:
        try:
            step_failures = step()
            failures.extend(step_failures)
            return not step_failures
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
