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

    # ---------------------------------------------------------- offset cache
    print("offset cache")
    import shutil
    def run_persistent(root, events, session="cache1", truncate=False):
        """Same transcript file across calls, so the cache is exercised."""
        tp = os.path.join(root, "persist.jsonl")
        mode = "w" if truncate else ("a" if os.path.exists(tp) else "w")
        with open(tp, mode) as f:
            for e in events: f.write(json.dumps(e)+"\n")
        payload = {"hook_event_name":"Stop","cwd":root,"session_id":session,
                   "transcript_path":tp,"stop_hook_active":False}
        p = subprocess.run([sys.executable,GUARD],input=json.dumps(payload),
              capture_output=True,text=True,env=dict(os.environ,CLAUDE_PROJECT_DIR=root))
        return p.returncode, p.stderr

    os.makedirs(os.path.join(root,".git"), exist_ok=True)
    rc,_ = run_persistent(root, [edit(J("src","A.java"))], truncate=True)
    check("cache: first turn blocks", rc==2)
    cache_dir = os.path.join(root,".git","claude-verify-guard")
    check("cache: file written", os.path.isdir(cache_dir) and os.listdir(cache_dir))
    rc,_ = run_persistent(root, [bash("./mvnw test")])
    check("cache: appended test clears it", rc==0)
    rc,_ = run_persistent(root, [edit(J("src","B.java"))])
    check("cache: appended edit blocks again", rc==2)
    rc,_ = run_persistent(root, [bash("task test")])
    check("cache: cleared again", rc==0)

    # incremental must agree with a cold full parse of the same file
    cold = os.path.join(root,"persist.jsonl")
    shutil.copy(cold, os.path.join(root,"cold.jsonl"))
    payload = {"hook_event_name":"Stop","cwd":root,"session_id":"never-seen",
               "transcript_path":os.path.join(root,"cold.jsonl"),"stop_hook_active":False}
    p = subprocess.run([sys.executable,GUARD],input=json.dumps(payload),
          capture_output=True,text=True,env=dict(os.environ,CLAUDE_PROJECT_DIR=root))
    check("cache: incremental result == cold full parse", p.returncode==0, p.returncode)

    # a truncated/replaced transcript must invalidate the cache, not mis-resume
    rc,_ = run_persistent(root, [edit(J("src","C.java"))], truncate=True)
    check("cache: truncated transcript falls back to full parse", rc==2)

    # a same-size replacement must invalidate too, not just a truncation
    tp = os.path.join(root,"persist.jsonl")
    with open(tp,"w") as f:
        f.write(json.dumps(bash("./mvnw test"))+"\n")
        f.write(json.dumps(edit(J("src","Z.java")))+"\n")
    payload = {"hook_event_name":"Stop","cwd":root,"session_id":"cache1",
               "transcript_path":tp,"stop_hook_active":False}
    p = subprocess.run([sys.executable,GUARD],input=json.dumps(payload),
          capture_output=True,text=True,env=dict(os.environ,CLAUDE_PROJECT_DIR=root))
    check("cache: rewritten transcript is not resumed from a stale offset",
          p.returncode==2, p.returncode)

    # a corrupt cache must not break the hook
    cf = os.path.join(cache_dir, os.listdir(cache_dir)[0])
    open(cf,"w").write("{not json")
    rc,_ = run_persistent(root, [bash("./mvnw test")])
    check("cache: corrupt cache falls back cleanly", rc==0)

    # a half-written final line must not be consumed
    tp = os.path.join(root,"partial.jsonl")
    with open(tp,"w") as f:
        f.write(json.dumps(edit(J("src","D.java")))+"\n")
        f.write('{"type":"assistant","mess')          # torn write, no newline
    payload = {"hook_event_name":"Stop","cwd":root,"session_id":"partial",
               "transcript_path":tp,"stop_hook_active":False}
    p = subprocess.run([sys.executable,GUARD],input=json.dumps(payload),
          capture_output=True,text=True,env=dict(os.environ,CLAUDE_PROJECT_DIR=root))
    check("cache: torn final line ignored, edit still seen", p.returncode==2)
    with open(tp,"a") as f:
        f.write('age":{"content":[]}}\n')
        f.write(json.dumps(bash("./mvnw test"))+"\n")
    p = subprocess.run([sys.executable,GUARD],input=json.dumps(payload),
          capture_output=True,text=True,env=dict(os.environ,CLAUDE_PROJECT_DIR=root))
    check("cache: completed line then test clears it", p.returncode==0, p.stderr[:120])

print()
if FAILURES:
    print(f"{len(FAILURES)} FAILED: {FAILURES}"); sys.exit(1)
print("all tests passed")
