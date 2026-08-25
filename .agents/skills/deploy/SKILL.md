---
name: deploy
description: Deploy jZen to Cloud Run, or prepare the commands for a deploy. Use whenever asked to deploy, ship, release, roll back, cut over a region, or check what is running in production, and before touching gcloud for anything that changes a live service. Encodes who runs a deploy, the create-or-update rule for one-time resources, and the post-deploy checks that were repeatedly asked for by hand.
---

# Deploying jZen

## The authority is the Taskfile, not this file

`task deploy:cloudrun`'s `summary:` in `Taskfile.yml` is the source of truth: the dirty-tree
refusal, the unpushed-commit refusal, the migrate-before-deploy ordering, the schema-rollback
gate, and the eight capacity knobs with what each one breaks. **Read it before deploying**
(`task --summary deploy:cloudrun`). Do not restate its rules here or in a plan document — they
change, and a second copy drifts into being wrong.

This skill covers only what the Taskfile cannot: who runs the command, and the failure modes
that came from outside it.

## You prepare deploy commands; the user runs them

Do not run a deploy autonomously. Print the exact command, ready to paste, and say what it will
change. The user runs it and brings back the output.

This is not caution for its own sake — it is what the transcripts show working. The recurring
failure is the opposite: a deploy attempted, failing on a missing prerequisite, and the user
having to ask twice for the command that would have fixed it (*"I see no commands, give me them
here again"*). Hand over the command first and that round trip disappears.

When you do hand over a command, hand over the *whole* sequence including any one-time setup
below, not just the happy path.

## One-time resources: describe-or-create, never bare update

A deploy updates resources that a first deploy has to create. `gcloud run jobs update` on a job
that does not exist fails with `Job [...] could not be found` — which is exactly how a region
cutover broke: the migration job existed in the old region and not the new one.

Any command that touches a Cloud Run job, a Cloud Scheduler entry, or a service in a region
that may be new goes out in this form:

```sh
gcloud run jobs describe "$JOB" --region "$REGION" --project "$PROJECT" >/dev/null 2>&1 \
  || gcloud run jobs create "$JOB" --region "$REGION" --project "$PROJECT" …
gcloud run jobs update "$JOB" --region "$REGION" --project "$PROJECT" --image "$IMAGE"
```

**Changing `REGION` means every regional resource is new.** Before proposing a region change,
list what has to exist in the target region first, and hand that list over as commands.

## After a deploy, answer these without being asked

The user asked for each of these by hand more than once. Volunteer them:

- **Did the revision actually take traffic?** `gcloud run services describe … --format='value(status.traffic)'`
- **What is the cold start now?** Time a request against a scaled-to-zero service, and compare
  it to the figure in the ADR that set the expectation.
- **Is the live site healthy?** Hit the real URL, not just `/q/health`.
- **Did the measured win match the predicted one?** If a plan document predicted a number,
  score it against the observed one and say so plainly when it did not land.

## Rolling back

The image tag is the short commit SHA, which is only a usable identity while that commit is
reachable on origin. `ALLOW_UNPUSHED=1` exists but production was once served for two days from
a commit `main` never received (ADR-048). Roll back to a SHA that is on `main`, and remember the
schema-rollback gate will refuse an older image against a forward-migrated schema unless
`ALLOW_SCHEMA_ROLLBACK=1` is set deliberately.
