"""Keep Artifact Registry, Cloud Run revisions and local Docker bounded after a deploy.

Run by `task zen:deploy:cleanup` (Taskfile.app.yml), which carries the operator-facing contract
(`task zen:deploy:cleanup --summary`); this docstring is about the implementation. The decision is
ADR-074 (which supersedes the registry-policy half of ADR-064 and the policy mechanics of ADR-068).

Three parts, in this order, and the order is the design:

1. REVISIONS first. A Cloud Run revision is not a reference the registry respects, so the revisions
   that remain are bounded here and the registry step below is told about every one of them.
   Revisions are deleted before any registry version, and the registry window is refused unless it
   is longer than the revisions' (the image is older than its revision by the build time, so equal
   windows would delete the image first).
2. The REGISTRY, deleted by this script in the run, with no cleanup policy armed. Google's
   asynchronous evaluator is not a bound we can rely on (it never acted on the `jzen` repository),
   and a plan carried out here is deterministic, testable against stubs, and prints its own
   before/after listing. In order:
   a. list the versions (before);
   b. PINS: every digest a consumer needs (every revision and job in the project and region) gets a
      PIN TAG (`zen-pin-<digest>`), released only for a digest no consumer needs; an operator
      `zen-hold-*` tag is never touched and is how a consumer this script cannot see is protected;
   c. read EVERY version's manifest (`docker buildx imagetools inspect --raw`), not only tagged
      ones: an index whose tag moved is untagged and still lists its children;
   d. PLAN: keep the newest N per package and every pinned or held version; delete versions tagged
      with a `--tag-prefixes` prefix, and untagged ones, once older than the window. A child is
      planned only when every parent that lists it is planned, and goes after them;
   e. HAZARDS: a planned digest a consumer needs, a consumer whose image is already gone, a
      consumer list that cannot be read, an unreadable manifest: delete NOTHING in the run;
   f. TRANSITION: remove the cleanup policies an earlier version of this script armed (every id
      starts `zen-`); any other id is the operator's, is reported, and blocks deletion;
   g. delete one version per call (`gcloud artifacts docker images delete <package>@<digest>
      --delete-tags --quiet`), parents before children, skipping the children of a parent whose
      deletion failed; then list again (after).
   An ATTACHMENT leaves only with its target. A version whose manifest has a `subject` (an OCI
   referrer: a cosign v3 sigstore bundle, an SBOM or attestation) is never planned: the registry
   deletes it with its target. A version tagged `sha256-<hex>.sig|.att|.sbom` (cosign before v3) is
   attached to `sha256:<hex>` and is deleted after that target in the same run, never alone; a tag
   scheme that expired a signature on its own clock would break `cosign verify` of a kept image.
3. LOCAL DOCKER: dangling layers, aged build cache, and this project's tagged images beyond the two
   newest per repository. Never `latest`, never anything outside this project's registry path.

A deploy pins its own image with `pin` (below) BEFORE any job or service is pointed at it, so a new
consumer is never ahead of its protection.

`--dry-run` prints the plan and the pins, releases, policy removals and deletions it would make,
and changes nothing anywhere.

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
runs; the cleanup is not partially run on a name it could not vouch for. Names read BACK from the
registry that become an argument (a cleanup policy id) are checked the same way.

Written to the 3.9 floor, stdlib only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import subprocess
import sys
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

import lib

# A tag on a digest that a consumer (a revision, a job) needs. Owned by this script: added when a
# consumer needs the digest, removed when none does. Neither prefix begins with a hex digit, so the
# tagged-delete rule can never match a pin even if the exclusion were missing.
PIN_PREFIX = "zen-pin-"
# A tag an OPERATOR adds for a consumer this script cannot enumerate (another project, another
# region, a non-Cloud-Run puller). Never removed by this script.
HOLD_PREFIX = "zen-hold-"
PROTECTING_PREFIXES = [PIN_PREFIX, HOLD_PREFIX]

# The id prefix of every cleanup policy an earlier version of this script armed. Only policies that
# all begin with it are removed; anything else belongs to the operator.
OWN_POLICY_PREFIX = "zen-"
POLICY_ID_SHAPE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")

# A pin is not released while its version is younger than this, so a cleanup that runs while a
# deploy has pushed and pinned an image but not yet pointed a job or service at it cannot undo it.
PIN_RELEASE_GRACE = dt.timedelta(hours=24)

# A tag begins with a hex digit when it is a (short) commit SHA — what `deploy:cloudrun` pushes,
# with an optional `-dirty`. `latest` and `stable` start with neither. Any other tag that starts
# with a hex digit (`1.0.0`) is expiry-eligible too; an application that keeps such tags overrides
# the prefixes. `sha256-` is deliberately NOT here: it is cosign's tag for a signature or
# attestation, which leaves with the image it signs and never on its own clock (ADR-074).
DEFAULT_TAG_PREFIXES = list("0123456789abcdef")

# `sha256-<hex>.sig|.att|.sbom`: cosign (before v3) tags an attachment with its target's digest.
ATTACHMENT_TAG = re.compile(r"sha256-([0-9a-f]+)\.(?:sig|att|sbom)")
ATTACHMENT_TAG_PREFIX = "sha256-"

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


def validate_tag_prefixes(keep_versions: int, image_days: int, tag_prefixes: Sequence[str]) -> None:
    """Refuse a setting that could delete a running, protected or attached image."""
    if keep_versions < 1:
        raise StepError("keep-versions must be at least 1: the newest versions are what the plan "
                        "never touches, and the image Cloud Run runs is untagged.")
    if image_days < 1:
        raise StepError("image-days must be at least 1.")
    prefixes = list(tag_prefixes)
    if not prefixes:
        raise StepError("tag-prefixes is empty: the tagged rule would match every tagged version.")
    for prefix in prefixes:
        if not TAG_PREFIX_SHAPE.fullmatch(prefix):
            raise StepError("tag prefix %r cannot begin any tag (tags use letters, digits, '_', '.' "
                            "and '-', and start with a letter, digit or '_')." % prefix)
    for tag in sorted(PROTECTED_TAGS) + PROTECTING_PREFIXES + [ATTACHMENT_TAG_PREFIX]:
        if any(tag.startswith(p) for p in prefixes):
            raise StepError("tag prefix %r would also match the protected tag %r." %
                            (next(p for p in prefixes if tag.startswith(p)), tag))


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


Key = Tuple[str, str]  # (package, version digest)


def key_of(version: Dict[str, Any]) -> Key:
    return (version["package"], version["version"])


class Plan:
    """What a run deletes: `delete` in the order to do it, and what it depends on."""

    def __init__(self, delete: List[Dict[str, Any]], after: Dict[Key, Set[Key]],
                 with_target: List[Dict[str, Any]]) -> None:
        self.delete = delete            # versions to delete explicitly, parents before children
        self.after = after              # key -> the planned keys that must be deleted before it
        self.with_target = with_target  # referrers the registry deletes together with their target


def build_plan(versions: Sequence[Dict[str, Any]], manifests: Dict[Key, Dict[str, Any]],
               now: dt.datetime, keep_versions: int, image_days: int,
               tag_prefixes: Sequence[str]) -> Plan:
    """The versions to delete, computed from a fresh listing and every version's manifest.

    This is the selection the registry's cleanup policy used to express, now carried out here:
    keep the newest `keep_versions` per package and every pinned or held version; a tagged version
    is eligible when a tag begins with a prefix and an untagged one when it is older than
    `image_days`. `latest` is never eligible. On top of that:

    - A child is planned only when every parent that lists it is planned (an untagged index shields
      the image Cloud Run runs and the attestation), and is deleted after them. A reference cycle
      shields nothing it cannot prove, so none of its members is planned.
    - An attachment is never eligible on its own. A version whose manifest has a `subject` goes
      with its target (the registry's doing, so it is not deleted here); a version tagged
      `sha256-<hex>.sig|.att|.sbom` is attached to `sha256:<hex>` and is deleted after that target
      in this run, and only when that target is planned.

    `manifests` must hold every version: an unread manifest is the caller's refusal to plan, not a
    guess made here.
    """
    now_age = dt.timedelta(days=image_days)
    by_key = {key_of(v): v for v in versions}
    kept: Set[Key] = set()
    by_package: Dict[str, List[Dict[str, Any]]] = {}
    for v in versions:
        by_package.setdefault(v["package"], []).append(v)
    for group in by_package.values():
        newest = sorted(group, key=lambda v: parse_ts(v["createTime"]), reverse=True)[:keep_versions]
        kept.update(key_of(v) for v in newest)
    for v in versions:
        if any(t.startswith(p) for t in version_tags(v) for p in PROTECTING_PREFIXES):
            kept.add(key_of(v))

    parents: Dict[Key, Set[Key]] = {}
    referrer_of: Dict[Key, Key] = {}   # a version with a `subject` -> its target
    tag_attached: Dict[Key, Key] = {}  # a `sha256-<hex>.sig` version -> its target
    for v in versions:
        k = key_of(v)
        m = manifests[k]
        for kid in m.get("children", []):
            if (k[0], kid) in by_key:
                parents.setdefault((k[0], kid), set()).add(k)
        if m.get("subject") and (k[0], m["subject"]) in by_key:
            referrer_of[k] = (k[0], m["subject"])
        for tag in version_tags(v):
            hit = ATTACHMENT_TAG.fullmatch(tag)
            if hit and (k[0], "sha256:" + hit.group(1)) in by_key:
                tag_attached[k] = (k[0], "sha256:" + hit.group(1))
    attached = set(referrer_of) | set(tag_attached)

    def eligible(v: Dict[str, Any]) -> bool:
        k = key_of(v)
        tags = version_tags(v)
        if k in kept or k in attached or manifests[k].get("subject") or PROTECTED_TAGS & set(tags):
            return False
        if now - parse_ts(v["createTime"]) <= now_age:
            return False
        return not tags or any(t.startswith(p) for t in tags for p in tag_prefixes)

    memo: Dict[Key, bool] = {}

    def planned(k: Key) -> bool:
        if k not in memo:
            memo[k] = False  # a cycle shields nothing it cannot prove
            v = by_key[k]
            if k in tag_attached:
                ok = (k not in kept and not (PROTECTED_TAGS & set(version_tags(v)))
                      and planned(tag_attached[k]))
            else:
                ok = eligible(v)
            memo[k] = ok and all(planned(p) for p in parents.get(k, ()))
        return memo[k]

    chosen = [k for k in sorted(by_key) if planned(k)]
    after: Dict[Key, Set[Key]] = {}
    for k in chosen:
        deps = set(parents.get(k, ()))
        if k in tag_attached:
            deps.add(tag_attached[k])
        after[k] = deps
    ordered: List[Key] = []
    seen: Set[Key] = set()

    def visit(k: Key) -> None:
        if k in seen:
            return
        seen.add(k)
        for d in sorted(after[k]):
            visit(d)
        ordered.append(k)

    for k in chosen:
        visit(k)
    cascade = sorted(k for k, target in referrer_of.items() if planned(target) and k not in after)
    return Plan([by_key[k] for k in ordered], after, [by_key[k] for k in cascade])


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
    """Digests a consumer needs that the plan would delete: a pin did not take effect."""
    live = {(c["package"], c["digest"]) for c in consumers}
    return sorted({v["version"] for v in selected if (v["package"], v["version"]) in live})


def policy_names(repo: Dict[str, Any]) -> List[str]:
    """The ids of the repository's cleanup policies (`describe` prints them as a map keyed by id)."""
    policies = repo.get("cleanupPolicies") or {}
    if isinstance(policies, dict):
        return sorted(policies)
    return sorted(p["name"] for p in policies)


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


def read_manifests(versions: Sequence[Dict[str, Any]]) -> Dict[Key, Dict[str, Any]]:
    """Every version's manifest: which digests it lists (`children`) and what it is attached to.

    The version listing does not say that an index references an image or that a signature is
    attached to one; the manifest does. `docker buildx imagetools inspect --raw` prints it with the
    credentials `docker push` already uses. ALL versions are read, tagged or not: an index whose
    tag moved is untagged and still lists its children. A manifest that cannot be read deletes
    nothing in this run. The old simulation could report an upper bound, which is the safe way to be
    wrong in a report; for an action it is the unsafe one.
    """
    if shutil.which("docker") is None:
        raise StepError("docker is not on PATH, so no manifest can be read; nothing is deleted "
                        "without knowing which version lists or is attached to which.")
    manifests: Dict[Key, Dict[str, Any]] = {}
    unreadable: List[str] = []
    for v in versions:
        ref = "%s@%s" % (v["package"], v["version"])
        try:
            raw = json.loads(run(["docker", "buildx", "imagetools", "inspect", "--raw", ref]))
            if not isinstance(raw, dict):
                raise ValueError("not a manifest object")
        except (StepError, ValueError) as exc:
            unreadable.append("%s: %s" % (ref, exc))
            continue
        subject = raw.get("subject") or {}
        manifests[key_of(v)] = {
            "children": [m["digest"] for m in raw.get("manifests", []) if m.get("digest")],
            "subject": subject.get("digest", "") if isinstance(subject, dict) else "",
        }
    if unreadable:
        raise StepError("%d of %d manifests could not be read, so nothing is deleted in this run "
                        "(first: %s)" % (len(unreadable), len(versions), "; ".join(unreadable[:3])))
    return manifests


def _tag_add(package: str, digest: str, tag: str) -> None:
    run(["gcloud", "artifacts", "docker", "tags", "add", "%s@%s" % (package, digest),
         "%s:%s" % (package, tag)])


def _tag_delete(package: str, tag: str) -> None:
    run(["gcloud", "artifacts", "docker", "tags", "delete", "%s:%s" % (package, tag), "--quiet"])


def describe_version(v: Dict[str, Any]) -> str:
    return "%s %s %s" % (v["package"].rsplit("/", 1)[-1], v["version"][:19],
                         ",".join(version_tags(v)) or "(untagged)")


def print_listing(label: str, versions: Sequence[Dict[str, Any]]) -> None:
    lib.info("%s: %d versions" % (label, len(versions)))
    for v in sorted(versions, key=lambda x: (x["package"], parse_ts(x["createTime"]))):
        print("    %s  %s" % (v["createTime"][:19], describe_version(v)))


def step_registry(a: argparse.Namespace, now: dt.datetime, ctx: Dict[str, Any]) -> List[str]:
    validate_tag_prefixes(a.keep_versions, a.image_days, a.tag_prefixes)
    registry = "%s-docker.pkg.dev/%s/%s" % (a.region, a.project, a.repo)
    repo = run_json(["gcloud", "artifacts", "repositories", "describe", a.repo,
                     "--project=" + a.project, "--location=" + a.region])
    policies = policy_names(repo)
    foreign = [n for n in policies if not n.startswith(OWN_POLICY_PREFIX)]
    failures: List[str] = []

    versions = run_json(["gcloud", "artifacts", "docker", "images", "list", registry, "--include-tags"])
    print_listing("registry %s, before" % registry, versions)
    # Every consumer, not only this service's: a job and another service pull from this repository
    # too, and a digest is released only when none of them needs it. An unreadable list deletes
    # nothing: without it nothing can be pinned, so nothing can be shown to be unneeded.
    try:
        service_revisions = ctx["remaining"] if "remaining" in ctx else list_revisions(a)
        consumers, missing = resolve_consumers(
            revision_consumers(service_revisions, registry)
            + revision_consumers(list_other_revisions(a), registry, strict=False)
            + job_consumers(list_jobs(a), registry), versions)
    except StepError as exc:
        raise StepError("could not establish which images are in use, so nothing is deleted (%s)" % exc)
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

    # Protection first, before anything is selected or deleted.
    for package, digest in to_add:
        if a.dry_run:
            lib.ok("would pin %s@%s" % (package.rsplit("/", 1)[-1], digest[:19]))
            continue
        try:
            _tag_add(package, digest, pin_tag(digest))
            lib.ok("pinned %s@%s" % (package.rsplit("/", 1)[-1], digest[:19]))
        except StepError as exc:
            raise StepError("could not pin %s@%s, so nothing is deleted (%s)" % (package, digest, exc))
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

    if foreign:
        raise StepError(
            "the repository has cleanup policies this script did not create (%s); a second deleter "
            "with another model must not act on the same repository, so nothing is deleted. Remove "
            "them (`gcloud artifacts repositories delete-cleanup-policies %s --project=%s "
            "--location=%s --policynames=...`) or opt out with CLEANUP_REGISTRY=off." %
            (", ".join(foreign), a.repo, a.project, a.region))

    future = with_pins(versions, pins)
    manifests = read_manifests(future)
    plan = build_plan(future, manifests, now, a.keep_versions, a.image_days, a.tag_prefixes)
    lib.info("plan: delete %d versions (and %d attachments that go with their targets); keep the "
             "newest %d per package, every pinned or held version, and everything newer than %dd" %
             (len(plan.delete), len(plan.with_target), a.keep_versions, a.image_days))
    for v in plan.delete:
        lib.ok("%s %s" % ("would delete" if a.dry_run else "planned:", describe_version(v)))
    for v in plan.with_target:
        lib.ok("goes with its target: %s" % describe_version(v))

    hazards = running_hazards(list(plan.delete) + list(plan.with_target), consumers)
    if hazards:
        raise StepError("the plan would delete a digest a revision or job needs (%s) although it "
                        "is pinned; nothing is deleted." % ", ".join(hazards))
    if missing:
        for sentence in missing:
            lib.fail("registry", [sentence])
        raise StepError("nothing is deleted past an image that is already gone: " + " ".join(missing))

    # The transition: the policies this script armed before ADR-074 go before any version does, so
    # that two deleters with different models never act on one repository.
    if policies:
        bad = [n for n in policies if not POLICY_ID_SHAPE.fullmatch(n)]
        if bad:
            raise StepError("cleanup policy id %r is not a name this script will pass to gcloud; "
                            "nothing is deleted." % bad[0])
        if a.dry_run:
            lib.ok("would remove the cleanup policies jZen armed earlier: %s" % ", ".join(policies))
        else:
            try:
                run(["gcloud", "artifacts", "repositories", "delete-cleanup-policies", a.repo,
                     "--project=" + a.project, "--location=" + a.region,
                     "--policynames=" + ",".join(policies)])
            except StepError as exc:
                raise StepError("could not remove the earlier cleanup policies, so nothing is "
                                "deleted (%s)" % exc)
            lib.ok("removed the cleanup policies jZen armed earlier: %s" % ", ".join(policies))

    if a.dry_run:
        lib.info("--dry-run: nothing was changed.")
        return failures

    stuck: Set[Key] = set()  # versions whose deletion failed or was skipped
    for v in plan.delete:
        k = key_of(v)
        blocked = plan.after[k] & stuck
        if blocked:
            stuck.add(k)
            lib.warn("skipped %s: %s was not deleted" % (describe_version(v),
                                                         ", ".join(sorted(b[1][:19] for b in blocked))))
            continue
        try:
            run(["gcloud", "artifacts", "docker", "images", "delete", "%s@%s" % k,
                 "--delete-tags", "--quiet"])
            lib.ok("deleted %s" % describe_version(v))
        except StepError as exc:
            # A version can leave before its own call: the registry removes an attachment with its
            # target, and may remove an index's images with the index. The goal is that the version
            # is gone, so a failed call is checked against a fresh listing rather than assumed; a
            # version still listed, or a listing that cannot be read, is the failure it looks like.
            try:
                still_there = any(key_of(x) == k for x in run_json(
                    ["gcloud", "artifacts", "docker", "images", "list", registry, "--include-tags"]))
            except StepError:
                still_there = True
            if not still_there:
                lib.ok("already gone %s (removed by the registry with a parent or target)" %
                       describe_version(v))
                continue
            stuck.add(k)
            failures.append("registry: could not delete %s@%s (%s)" % (k[0], k[1], exc))
            lib.fail("delete %s" % describe_version(v), [str(exc)])
    after = run_json(["gcloud", "artifacts", "docker", "images", "list", registry, "--include-tags"])
    print_listing("registry %s, after" % registry, after)
    lib.info("registry: %d versions before, %d after (listed again, not assumed). The repository's "
             "reported size lags deletion: do not claim a saving until it is re-measured." %
             (len(versions), len(after)))
    return failures


def pin_image(argv: Sequence[str]) -> int:
    """`pin`: protect an image BEFORE a job or service is pointed at it. Exits non-zero if it cannot."""
    p = argparse.ArgumentParser(prog="deploy-cleanup.py pin",
                                description="pin an image so the registry cleanup never deletes it")
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
                   help="comma-separated tag prefixes of the tagged versions the plan may delete")
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
        # Never delete a version past a revision step that did not finish: what still lists as a
        # rollback target is exactly what the plan must not outrun.
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
