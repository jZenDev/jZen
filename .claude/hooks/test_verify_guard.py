#!/usr/bin/env python3
import json, os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "verify_guard.py")
FAILURES = []

def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else " " + str(detail)))
    if not cond: FAILURES.append(name)

def edit(path):
    return {"type":"assistant","message":{"content":[
        {"type":"tool_use","name":"Edit","input":{"file_path":path}}]}}
def bash(cmd):
    return {"type":"assistant","message":{"content":[
        {"type":"tool_use","name":"Bash","input":{"command":cmd}}]}}

def run(root, events, stop_active=False):
    tp = os.path.join(root, "transcript.jsonl")
    with open(tp,"w") as f:
        for e in events: f.write(json.dumps(e)+"\n")
    payload = {"hook_event_name":"Stop","cwd":root,"session_id":"s",
               "transcript_path":tp,"stop_hook_active":stop_active}
    env = dict(os.environ, CLAUDE_PROJECT_DIR=root)
    p = subprocess.run([sys.executable,GUARD],input=json.dumps(payload),
                       capture_output=True,text=True,env=env)
    return p.returncode, p.stderr

with tempfile.TemporaryDirectory() as root:
    os.makedirs(os.path.join(root,".claude","hooks"))
    J = lambda *p: os.path.join(root,*p)

    print("verify guard")
    rc,err = run(root, [edit(J("src","App.java"))])
    check("source edit with no test blocks", rc==2 and "App.java" in err, err[:160])
    check("says no test ran", "no test command has run" in err)

    rc,err = run(root, [edit(J("src","App.java")), bash("./mvnw test")])
    check("test after edit passes", rc==0, err[:160])

    rc,err = run(root, [bash("./mvnw test"), edit(J("src","App.java"))])
    check("test BEFORE edit still blocks", rc==2 and "before that edit" in err, err[:160])

    rc,err = run(root, [edit(J("docs","NOTES.md"))])
    check("docs-only edit passes", rc==0)
    rc,err = run(root, [edit(J("README.md"))])
    check("markdown passes", rc==0)
    rc,err = run(root, [edit(J(".claude","settings.json"))])
    check("tooling edit passes", rc==0)
    rc,err = run(root, [edit(J("target","classes","X.java"))])
    check("build output passes", rc==0)
    rc,err = run(root, [edit(J("client","lib","generated","x.pb.dart"))])
    check("generated output passes", rc==0)

    rc,err = run(root, [])
    check("no edits at all passes", rc==0)

    rc,err = run(root, [edit(J("src","App.java"))], stop_active=True)
    check("stop_hook_active short-circuits (no loop)", rc==0, err[:160])

    for cmd,label in [("task test","task test"),("./mvnw -B verify","mvnw verify"),
                      ("cd client && dart test","dart test"),("flutter test","flutter test"),
                      ("pnpm test","pnpm test")]:
        rc,err = run(root, [edit(J("src","App.java")), bash(cmd)])
        check(f"'{label}' counts as verification", rc==0, err[:120])

    rc,err = run(root, [edit(J("src","App.java")), bash("echo done")])
    check("a non-test command does not count", rc==2)

    # config override
    open(J(".claude","hooks","verify-rules.json"),"w").write(json.dumps(
        {"source":["*.java"],"exempt":[],"tests":[r"\bmake check\b"],"message":"Run make check."}))
    rc,err = run(root, [edit(J("src","App.java")), bash("./mvnw test")])
    check("config replaces the test list", rc==2 and "Run make check." in err, err[:160])
    rc,err = run(root, [edit(J("src","App.java")), bash("make check")])
    check("configured test command passes", rc==0)
    os.remove(J(".claude","hooks","verify-rules.json"))

    # robustness
    p = subprocess.run([sys.executable,GUARD],input="not json",capture_output=True,text=True)
    check("malformed payload never blocks", p.returncode==0)
    payload = {"hook_event_name":"Stop","cwd":root,"transcript_path":"/nope.jsonl"}
    p = subprocess.run([sys.executable,GUARD],input=json.dumps(payload),
                       capture_output=True,text=True,env=dict(os.environ,CLAUDE_PROJECT_DIR=root))
    check("missing transcript never blocks", p.returncode==0)

print()
if FAILURES:
    print(f"{len(FAILURES)} FAILED: {FAILURES}"); sys.exit(1)
print("all tests passed")
