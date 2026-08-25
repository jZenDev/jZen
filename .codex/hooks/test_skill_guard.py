#!/usr/bin/env python3
import json, os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "skill_guard.py")
FAILURES = []

def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else " " + str(detail)))
    if not cond: FAILURES.append(name)

def run(root, path, session="s1", tool="Edit"):
    payload = {"hook_event_name": "PreToolUse", "tool_name": tool, "cwd": root,
               "session_id": session, "tool_input": {"file_path": path}}
    return _go(root, payload)

def run_cmd(root, command, session="c1"):
    payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": root,
               "session_id": session, "tool_input": {"command": command}}
    return _go(root, payload)

def _go(root, payload):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=root)
    p = subprocess.run([sys.executable, GUARD], input=json.dumps(payload),
                       capture_output=True, text=True, env=env)
    return p.returncode, p.stderr

with tempfile.TemporaryDirectory() as root:
    os.makedirs(os.path.join(root, ".claude", "hooks"))
    os.makedirs(os.path.join(root, ".claude", "skills", "design-system"))
    os.makedirs(os.path.join(root, ".claude", "skills", "big"))
    os.makedirs(os.path.join(root, "templates", "course"))
    os.makedirs(os.path.join(root, "src"))
    os.makedirs(os.path.join(root, ".git"))
    open(os.path.join(root, ".claude", "skills", "design-system", "SKILL.md"), "w").write(
        "---\nname: design-system\n---\nReuse tags/ before inventing. Tokens only.\n")
    open(os.path.join(root, ".claude", "skills", "big", "SKILL.md"), "w").write(
        "\n".join(f"line {i}" for i in range(400)))
    open(os.path.join(root, ".claude", "hooks", "skill-map.json"), "w").write(json.dumps({
        "rules": [
            {"skill": "design-system", "paths": ["*.qute.html", "*.module.css"],
             "why": "This is UI markup."},
            {"skill": "big", "paths": ["src/big/*"]},
        ]}))

    print("skill guard")
    rc, err = run(root, os.path.join(root, "templates/course/courses.qute.html"))
    check("blocks first governed edit", rc == 2 and "Reuse tags/" in err, err[:150])
    check("explains why", "This is UI markup." in err)

    rc, err = run(root, os.path.join(root, "templates/course/other.qute.html"))
    check("second edit of same skill passes", rc == 0, err[:150])

    rc, err = run(root, os.path.join(root, "templates/course/x.qute.html"), session="s2")
    check("new session blocks again", rc == 2)

    rc, err = run(root, os.path.join(root, "src/App.java"))
    check("ungoverned path passes", rc == 0)

    rc, err = run(root, os.path.join(root, "styles/app.module.css"), session="s3")
    check("basename pattern matches anywhere", rc == 2)

    os.makedirs(os.path.join(root, "src", "big"))
    rc, err = run(root, os.path.join(root, "src/big/thing.ts"), session="s4")
    check("long skill is truncated with a pointer",
          rc == 2 and "more lines" in err and "SKILL.md" in err, err[-200:])

    rc, err = run(root, "/etc/passwd", session="s5")
    check("path outside project passes", rc == 0)

    rc, err = run(root, os.path.join(root, "templates/a.qute.html"), session="s6", tool="Write")
    check("Write tool also guarded", rc == 2)

    # two skills governing one path are delivered together, in one block
    open(os.path.join(root, ".claude", "hooks", "skill-map.json"), "w").write(json.dumps({
        "rules": [
            {"skill": "design-system", "paths": ["*.qute.html"], "why": "it is UI markup"},
            {"skill": "big", "paths": ["*.qute.html"], "why": "it carries Alpine directives"},
        ]}))
    rc, err = run(root, os.path.join(root, "templates/both.qute.html"), session="s8")
    check("both governing skills delivered at once",
          rc == 2 and "Reuse tags/" in err and "line 0" in err
          and "design-system" in err and "big" in err, err[:200])
    rc, err = run(root, os.path.join(root, "templates/both2.qute.html"), session="s8")
    check("both marked delivered, second edit passes", rc == 0, err[:150])

    # exclude keeps build output from triggering a block
    open(os.path.join(root, ".claude", "hooks", "skill-map.json"), "w").write(json.dumps({
        "rules": [{"skill": "design-system", "paths": ["*.module.css"],
                   "exclude": ["target/*", "*/node_modules/*"]}]}))
    os.makedirs(os.path.join(root, "target", "classes"), exist_ok=True)
    rc, err = run(root, os.path.join(root, "target/classes/app.module.css"), session="s9")
    check("excluded build output passes", rc == 0, err[:150])
    rc, err = run(root, os.path.join(root, "src/app.module.css"), session="s9")
    check("source path still blocks", rc == 2, err[:150])

    # ---- command triggers (item 14) ----
    print("command triggers")
    open(os.path.join(root, ".claude", "skills", "long-job", "SKILL.md"), "w") if False else None
    os.makedirs(os.path.join(root, ".claude", "skills", "long-job"), exist_ok=True)
    open(os.path.join(root, ".claude", "skills", "long-job", "SKILL.md"), "w").write(
        "---\nname: long-job\n---\nNever poll with a foreground sleep.\n")
    open(os.path.join(root, ".claude", "hooks", "skill-map.json"), "w").write(json.dumps({
        "rules": [
            {"skill": "long-job", "why": "it is a long command",
             "commands": [r"\bmvnw\b[^|;&]*\btest\b", r"\btask\s+test\b"]},
            {"skill": "design-system", "paths": ["*.qute.html"]},
        ]}))
    rc, err = run_cmd(root, "./mvnw test", session="c1")
    check("first long test command blocks with the skill",
          rc == 2 and "Never poll" in err and "mvnw test" in err, err[:200])
    rc, err = run_cmd(root, "./mvnw -q -o test 2>&1 | tail -50", session="c1")
    check("second such command passes", rc == 0, err[:150])
    rc, err = run_cmd(root, "task test", session="c2")
    check("different session blocks again", rc == 2)
    rc, err = run_cmd(root, "ls -la", session="c3")
    check("unrelated command passes", rc == 0)
    rc, err = run_cmd(root, "git status", session="c3")
    check("git status passes", rc == 0)
    rc, err = run(root, os.path.join(root, "templates/x.qute.html"), session="c3")
    check("path rules still work alongside command rules", rc == 2)
    # a MENTION is not an invocation -- this exact shape produced a false block
    rc, err = run_cmd(root, """probe() { echo "task test"; }\nprobe""", session="c5")
    check("quoted mention inside a function does not block", rc == 0, err[:200])
    rc, err = run_cmd(root, "grep -rn 'task test' docs/", session="c5")
    check("grep for a trigger string does not block", rc == 0, err[:150])
    rc, err = run_cmd(root, "cat <<'EOF'\n./mvnw test\nEOF", session="c5")
    check("heredoc body mentioning a trigger does not block", rc == 0, err[:150])
    rc, err = run_cmd(root, 'echo "run ./mvnw test later"', session="c5")
    check("echoing a trigger does not block", rc == 0, err[:150])
    rc, err = run_cmd(root, "./mvnw test", session="c5")
    check("the real invocation still blocks", rc == 2, err[:150])
    rc, err = run_cmd(root, "cd server && task test 2>&1 | tail -5", session="c6")
    check("real invocation in a pipeline still blocks", rc == 2, err[:150])

    open(os.path.join(root, ".claude", "hooks", "skill-map.json"), "w").write(json.dumps({
        "rules": [{"skill": "long-job", "commands": ["[unclosed"]}]}))
    rc, err = run_cmd(root, "./mvnw test", session="c4")
    check("a broken regex in the map never blocks", rc == 0, err[:150])

    p = subprocess.run([sys.executable, GUARD], input="not json",
                       capture_output=True, text=True)
    check("malformed payload never blocks", p.returncode == 0)

    os.remove(os.path.join(root, ".claude", "hooks", "skill-map.json"))
    rc, err = run(root, os.path.join(root, "templates/z.qute.html"), session="s7")
    check("missing map is a no-op", rc == 0)

print()
if FAILURES:
    print(f"{len(FAILURES)} FAILED: {FAILURES}"); sys.exit(1)
print("all tests passed")
