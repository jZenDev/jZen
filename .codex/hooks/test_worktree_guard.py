#!/usr/bin/env python3
"""Tests for worktree_guard.py, including replays of two real mistakes."""
import json, os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "worktree_guard.py")
FAILURES = []

def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else "  " + str(detail)))
    if not cond: FAILURES.append(name)

def edit(p):  return {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":p}}]}}
def bash(c):  return {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":c}}]}}

def run(root, cmd, events):
    tp = os.path.join(root, "t.jsonl")
    with open(tp,"w") as f:
        for e in events: f.write(json.dumps(e)+"\n")
    payload = {"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":root,
               "session_id":"s","transcript_path":tp,"tool_input":{"command":cmd}}
    p = subprocess.run([sys.executable,GUARD],input=json.dumps(payload),
          capture_output=True,text=True,env=dict(os.environ,CLAUDE_PROJECT_DIR=root))
    return p.returncode, p.stderr

with tempfile.TemporaryDirectory() as root:
    q = dict(capture_output=True, cwd=root, text=True)
    subprocess.run(["git","init","-q","-b","main",root],capture_output=True)
    subprocess.run(["git","config","user.email","t@t"],**q)
    subprocess.run(["git","config","user.name","t"],**q)
    for f in ("mine.txt","theirs.txt","other.txt"):
        open(os.path.join(root,f),"w").write("v1\n")
    subprocess.run(["git","add","-A"],**q); subprocess.run(["git","commit","-qm","init"],**q)

    print("commit: foreign staged files")
    # MISTAKE 1 REPLAY: the user's file was already staged when I committed.
    open(os.path.join(root,"mine.txt"),"w").write("v2\n")
    open(os.path.join(root,"theirs.txt"),"w").write("theirs\n")
    subprocess.run(["git","add","mine.txt","theirs.txt"],**q)
    rc,err = run(root, 'git commit -m "x"', [edit(os.path.join(root,"mine.txt"))])
    check("blocks when the index holds a file the session never wrote",
          rc==2 and "theirs.txt" in err, err[:200])
    check("does not accuse the session's own file", "mine.txt" not in err.split("never wrote")[-1][:200])

    rc,err = run(root, 'ALLOW_FOREIGN=1 git commit -m "x"', [edit(os.path.join(root,"mine.txt"))])
    check("ALLOW_FOREIGN=1 overrides", rc==0, err[:150])

    subprocess.run(["git","restore","--staged","theirs.txt"],**q)
    rc,err = run(root, 'git commit -m "x"', [edit(os.path.join(root,"mine.txt"))])
    check("passes once only the session's files are staged", rc==0, err[:200])

    print("commit: files the session wrote via bash")
    subprocess.run(["git","restore","--staged","."],**q)
    open(os.path.join(root,"gen.txt"),"w").write("g\n")
    subprocess.run(["git","add","gen.txt","mine.txt"],**q)
    rc,err = run(root, 'git commit -m "x"',
                 [edit(os.path.join(root,"mine.txt")), bash("cat > gen.txt <<'EOF'\ng\nEOF")])
    check("a file written by a bash redirect counts as the session's", rc==0, err[:200])
    rc,err = run(root, 'git commit -m "x"',
                 [edit(os.path.join(root,"mine.txt")), bash("printf x | tee gen.txt")])
    check("tee counts too", rc==0, err[:150])
    rc,err = run(root, 'git commit -m "x"', [edit(os.path.join(root,"mine.txt"))])
    check("but an unexplained new file still blocks", rc==2 and "gen.txt" in err, err[:200])

    print("branch switch under foreign changes")
    subprocess.run(["git","restore","--staged","."],**q)
    subprocess.run(["git","branch","-q","feature/x"],**q)
    # MISTAKE 2 REPLAY: switching while the user's files are modified.
    rc,err = run(root, 'git checkout feature/x', [edit(os.path.join(root,"mine.txt"))])
    check("blocks a switch while foreign files are modified",
          rc==2 and "theirs.txt" in err, err[:200])
    check("suggests a worktree", "git worktree add" in err)
    rc,err = run(root, 'git switch feature/x', [edit(os.path.join(root,"mine.txt"))])
    check("git switch is covered too", rc==2)
    rc,err = run(root, 'git checkout -b feature/y', [edit(os.path.join(root,"mine.txt"))])
    check("creating a branch is allowed (it carries nothing away)", rc==0, err[:150])
    # MISTAKE 2, exact form: -b with a START POINT is the one git aborts.
    open(os.path.join(root,"theirs.txt"),"w").write("theirs again\n")
    rc,err = run(root, 'git checkout -b fix/z origin/main', [edit(os.path.join(root,"mine.txt"))])
    check("blocks -b with a start point under foreign changes",
          rc==2 and "worktree add -b fix/z" in err, err[:220])
    rc,err = run(root, 'git checkout -b fix/z', [edit(os.path.join(root,"mine.txt"))])
    check("-b from HEAD is still allowed (carries the tree safely)", rc==0, err[:150])

    rc,err = run(root, 'git checkout -- theirs.txt', [edit(os.path.join(root,"mine.txt"))])
    check("path checkout is not a branch switch", rc==0, err[:150])

    subprocess.run(["git","checkout","-q","--","theirs.txt"],**q)
    rc,err = run(root, 'git checkout feature/x', [edit(os.path.join(root,"mine.txt"))])
    check("switch passes when only the session's files are dirty", rc==0, err[:200])

    print("robustness")
    rc,err = run(root, 'ls -la', [])
    check("non-git command ignored", rc==0)
    rc,err = run(root, 'git status', [])
    check("git status ignored", rc==0)
    rc,err = run(root, 'echo "git commit -m x"', [])
    check("a mention is not an invocation", rc==0)
    p = subprocess.run([sys.executable,GUARD],input="not json",capture_output=True,text=True)
    check("malformed payload never blocks", p.returncode==0)
    payload={"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":root,
             "transcript_path":"/nope.jsonl","tool_input":{"command":"git commit -m x"}}
    p=subprocess.run([sys.executable,GUARD],input=json.dumps(payload),capture_output=True,text=True)
    check("missing transcript does not crash", p.returncode in (0,2))

print()
if FAILURES:
    print(f"{len(FAILURES)} FAILED: {FAILURES}"); sys.exit(1)
print("all tests passed")
