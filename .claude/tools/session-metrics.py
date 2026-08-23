#!/usr/bin/env python3
"""Measure agent-session behaviour from Claude Code transcripts.

Every number in the session audit that produced `.claude/hooks/` came from a
one-off script that lived in a scratchpad. A one-off measurement cannot answer
the only question that matters afterwards -- did any of it help? -- so the
measurement lives here instead, and re-running it is a command.

    python3 .claude/tools/session-metrics.py                    # since the baseline
    python3 .claude/tools/session-metrics.py --compare          # vs the stored baseline
    python3 .claude/tools/session-metrics.py --since 2026-09-01
    python3 .claude/tools/session-metrics.py --json             # machine-readable
    python3 .claude/tools/session-metrics.py --write-baseline   # re-stamp the baseline

Reads only: it parses `~/.claude/projects/*/*.jsonl` and writes nothing outside
this directory (and nothing at all without --write-baseline).
"""

from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
BASELINE = os.path.join(HERE, "session-metrics-baseline.json")
PROJECTS = os.path.expanduser("~/.claude/projects")

# The repos the audit covered. Add more as they get the same treatment.
REPOS = {
    "jZen": "-Users-amerezhanyi-Developer-jZenDev-jZen",
    "prudent": "-Users-amerezhanyi-Developer-jZenDev-prudent",
    "bugeater": "-Users-amerezhanyi-Developer-BugEater-bugeater-quarkus",
}

# A user turn matching this is a proxy for "the user had to say it again".
CORRECTION = re.compile(
    r"\b(don't|do not|never|stop|why did you|you (broke|forgot|missed|didn't|should|must)"
    r"|again|no,|nope|wrong|incorrect|revert|undo|i told you|as i said|not what i)\b", re.I)

# Text the guards put on stderr when they block. Counting these is how we tell
# a rule that fires from a rule that is merely written down.
GUARDS = {
    "git_guard": "Blocked by the git guard",
    "skill_guard": "Blocked once by the skill guard",
    "verify_guard": "Blocked by the verify guard",
}

TEST_CMD = re.compile(r"\bmvnw\b[^|;&]*\b(test|verify)\b|\btask\s+test\b|\bdart\s+test\b"
                      r"|\bflutter\s+test\b|\bpnpm\s+test\b")


def ts_of(entry: dict):
    raw = entry.get("timestamp")
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def blocks(msg: dict):
    c = msg.get("content")
    if isinstance(c, str):
        return [{"type": "text", "text": c}]
    return c if isinstance(c, list) else []


def commit_subject(cmd: str) -> str | None:
    """Best-effort recovery of a commit subject from a shell command."""
    if "git commit" not in cmd:
        return None
    m = re.search(r"-m\s+\"([^\"]*)\"", cmd) or re.search(r"-m\s+'([^']*)'", cmd)
    if m:
        return m.group(1).split("\n")[0].strip()
    m = re.search(r"<<-?\s*'?([A-Za-z_]\w*)'?\s*\n(.*?)\n", cmd, re.S)
    if m:
        return m.group(2).strip()
    return None


def measure(since: datetime | None, until: datetime | None) -> dict:
    out = {
        "sessions": 0, "assistant_turns": 0,
        "commits": 0, "commit_subject_over_50": 0, "longest_subject": 0,
        "commit_on_protected_branch": 0,
        "sleep_calls": 0, "sleep_seconds": 0,
        "idle_echo_calls": 0,
        "skill_invocations": 0, "subagent_invocations": 0,
        "bash_calls": 0, "test_runs": 0,
        "guard_blocks": {k: 0 for k in GUARDS},
        "correction_turns": 0, "user_turns": 0,
        "per_repo": {},
        "first_session": None, "last_session": None,
    }
    for repo, folder in REPOS.items():
        r = {k: 0 for k in ("sessions", "commits", "commit_subject_over_50",
                            "commit_on_protected_branch", "sleep_calls", "sleep_seconds",
                            "skill_invocations", "correction_turns", "test_runs")}
        r["guard_blocks"] = {k: 0 for k in GUARDS}
        for path in sorted(glob.glob(os.path.join(PROJECTS, folder, "*.jsonl"))):
            counted = False
            try:
                fh = open(path, encoding="utf-8", errors="replace")
            except OSError:
                continue
            with fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        e = json.loads(line)
                    except ValueError:
                        continue
                    when = ts_of(e)
                    # Bookkeeping lines (mode, ai-title, snapshots) carry no
                    # timestamp. They must not decide whether a session falls in
                    # the window, or every file lands in every window.
                    if when is None:
                        continue
                    if since and when < since:
                        continue
                    if until and when > until:
                        continue
                    iso = when.isoformat()
                    if not out["first_session"] or iso < out["first_session"]:
                        out["first_session"] = iso
                    if not out["last_session"] or iso > out["last_session"]:
                        out["last_session"] = iso
                    if not counted:
                        counted = True
                        out["sessions"] += 1
                        r["sessions"] += 1

                    kind = e.get("type")
                    if kind == "assistant":
                        out["assistant_turns"] += 1
                        for b in blocks(e.get("message") or {}):
                            if b.get("type") != "tool_use":
                                continue
                            name, inp = b.get("name"), b.get("input") or {}
                            if name == "Skill":
                                out["skill_invocations"] += 1
                                r["skill_invocations"] += 1
                            elif name == "Agent":
                                out["subagent_invocations"] += 1
                            elif name == "Bash":
                                cmd = inp.get("command") or ""
                                out["bash_calls"] += 1
                                if TEST_CMD.search(cmd):
                                    out["test_runs"] += 1
                                    r["test_runs"] += 1
                                for n in re.findall(r"^\s*sleep\s+(\d+)", cmd, re.M):
                                    out["sleep_calls"] += 1
                                    r["sleep_calls"] += 1
                                    out["sleep_seconds"] += int(n)
                                    r["sleep_seconds"] += int(n)
                                if re.match(r"^\s*echo\s+(waiting|standby|ack)", cmd):
                                    out["idle_echo_calls"] += 1
                                sub = commit_subject(cmd)
                                if sub is not None:
                                    out["commits"] += 1
                                    r["commits"] += 1
                                    out["longest_subject"] = max(out["longest_subject"], len(sub))
                                    if len(sub) > 50:
                                        out["commit_subject_over_50"] += 1
                                        r["commit_subject_over_50"] += 1
                                if "git commit" in cmd and e.get("gitBranch") in ("main", "master") \
                                        and not re.search(r"(checkout\s+-[bB]|switch\s+(-c|-C|--create))", cmd):
                                    out["commit_on_protected_branch"] += 1
                                    r["commit_on_protected_branch"] += 1
                    elif kind == "user":
                        msg = e.get("message") or {}
                        for b in blocks(msg):
                            if b.get("type") == "tool_result":
                                cont = b.get("content")
                                txt = cont if isinstance(cont, str) else " ".join(
                                    x.get("text", "") for x in cont if isinstance(x, dict))
                                for key, needle in GUARDS.items():
                                    if needle in txt:
                                        out["guard_blocks"][key] += 1
                                        r["guard_blocks"][key] += 1
                            elif b.get("type") == "text" and not e.get("isSidechain"):
                                txt = b.get("text", "")
                                if not txt or "<system-reminder>" in txt[:60] or txt.startswith("Caveat"):
                                    continue
                                out["user_turns"] += 1
                                if len(txt) < 1500 and CORRECTION.search(txt):
                                    out["correction_turns"] += 1
                                    r["correction_turns"] += 1
        out["per_repo"][repo] = r
    return out


def pct(n: int, d: int) -> str:
    return f"{100.0 * n / d:.0f}%" if d else "n/a"


def report(m: dict, base: dict | None) -> None:
    def line(label, cur, prior=None, lower_better=True, suffix="", prior_suffix=None):
        s = f"  {label:<34} {cur:>9}{suffix}"
        if prior is not None:
            delta = cur - prior
            arrow = "=" if delta == 0 else ("v" if (delta < 0) == lower_better else "^")
            s += f"   was {prior}{prior_suffix if prior_suffix is not None else suffix}"
            s += f"  {arrow}{abs(delta)}"
        return s

    b = base.get("metrics") if base else None
    print(f"\nSessions {m['sessions']}   "
          f"{(m['first_session'] or '?')[:10]} .. {(m['last_session'] or '?')[:10]}")
    if base:
        print(f"Baseline {base['metrics']['sessions']} sessions, "
              f"{base.get('window','?')} ({base.get('note','')})")
    print("\nRULES THAT USED TO BE BROKEN")
    print(line("commit subjects over 50 chars", m["commit_subject_over_50"],
               b["commit_subject_over_50"] if b else None,
               suffix=f" / {m['commits']}",
               prior_suffix=f" / {b['commits']}" if b else None))
    print(f"  {'  (as a rate)':<34} {pct(m['commit_subject_over_50'], m['commits']):>9}"
          + (f"   was {pct(b['commit_subject_over_50'], b['commits'])}" if b else ""))
    print(line("longest subject", m["longest_subject"], b["longest_subject"] if b else None))
    print(line("commits on a protected branch", m["commit_on_protected_branch"],
               b["commit_on_protected_branch"] if b else None))
    print("\nTIME BURNED WAITING")
    print(line("foreground sleep calls", m["sleep_calls"], b["sleep_calls"] if b else None))
    print(line("seconds slept", m["sleep_seconds"], b["sleep_seconds"] if b else None, suffix="s"))
    print(line("idle 'echo waiting' calls", m["idle_echo_calls"],
               b["idle_echo_calls"] if b else None))
    print("\nWHETHER THE RULES REACH THE MODEL")
    print(line("skill invocations", m["skill_invocations"],
               b["skill_invocations"] if b else None, lower_better=False))
    print(line("test runs", m["test_runs"], b["test_runs"] if b else None, lower_better=False))
    print(line("subagent invocations", m["subagent_invocations"],
               b["subagent_invocations"] if b else None, lower_better=False))
    total_blocks = sum(m["guard_blocks"].values())
    print(f"  {'guard blocks (mechanism firing)':<34} {total_blocks:>9}")
    for k, v in m["guard_blocks"].items():
        print(f"      {k:<30} {v:>9}")
    print("\nWHETHER THE USER HAD TO REPEAT THEMSELVES")
    print(line("correction-shaped user turns", m["correction_turns"],
               b["correction_turns"] if b else None, suffix=f" / {m['user_turns']}",
               prior_suffix=f" / {b['user_turns']}" if b else None))
    print(f"  {'  (as a rate)':<34} {pct(m['correction_turns'], m['user_turns']):>9}"
          + (f"   was {pct(b['correction_turns'], b['user_turns'])}" if b else ""))
    print("\nPER REPO (corrections / commits over 50 / sleeps)")
    for repo, r in m["per_repo"].items():
        print(f"  {repo:<12} {r['sessions']:>3} sessions   "
              f"{r['correction_turns']:>3} corr   "
              f"{r['commit_subject_over_50']:>3}/{r['commits']:<3} long   "
              f"{r['sleep_calls']:>3} sleeps   "
              f"{sum(r['guard_blocks'].values()):>3} blocks")
    print()
    if b and m["sessions"] < 10:
        print("NOTE: fewer than 10 sessions since the baseline. Rates are noise at this size;\n"
              "      re-run once there is a few weeks of real work to compare.\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since", help="ISO date, e.g. 2026-09-01")
    ap.add_argument("--until", help="ISO date")
    ap.add_argument("--compare", action="store_true",
                    help="measure since the baseline cutoff and diff against it")
    ap.add_argument("--json", action="store_true", help="emit raw JSON")
    ap.add_argument("--write-baseline", action="store_true",
                    help="overwrite the stored baseline with the measured window")
    ap.add_argument("--note", default="", help="note to store with --write-baseline")
    a = ap.parse_args()

    base = None
    if os.path.exists(BASELINE):
        try:
            base = json.load(open(BASELINE, encoding="utf-8"))
        except (OSError, ValueError) as exc:
            print(f"baseline unreadable ({exc})", file=sys.stderr)

    def parse(d):
        return datetime.fromisoformat(d).replace(tzinfo=timezone.utc) if d else None

    since, until = parse(a.since), parse(a.until)
    if a.compare and base and not since:
        since = parse(base["cutoff"])

    m = measure(since, until)
    if a.json:
        print(json.dumps(m, indent=2))
        return 0
    report(m, base if a.compare else None)

    if a.write_baseline:
        payload = {
            "cutoff": (until or datetime.now(timezone.utc)).date().isoformat(),
            "window": f"{(m['first_session'] or '?')[:10]}..{(m['last_session'] or '?')[:10]}",
            "note": a.note,
            "generated": datetime.now(timezone.utc).isoformat(),
            "metrics": m,
        }
        with open(BASELINE, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2)
            fh.write("\n")
        print(f"baseline written to {BASELINE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
