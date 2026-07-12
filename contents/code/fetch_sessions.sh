#!/bin/bash
# Count local Claude Code activity on this machine and emit JSON:
#   {"sessions": N, "working": N, "agents": N}
#
#   sessions – running Claude Code chats (live ~/.claude/sessions/<pid>.json)
#   working  – of those, how many streamed transcript output in the last WINDOW s
#   agents   – sub-agent transcripts freshly written in the last WINDOW s
#
# Purely local filesystem reads — no network, no API tokens. There is no
# way to see chats on claude.ai or other machines, only local sessions.

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
WINDOW="${SESSION_WINDOW:-45}"
export CLAUDE_DIR WINDOW

python3 - <<'PYEOF'
import glob, json, os, time

home = os.environ["CLAUDE_DIR"]
window = float(os.environ["WINDOW"])
proj = os.path.join(home, "projects")
now = time.time()

def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # exists, owned by someone else (shouldn't happen for us)
    except (TypeError, ValueError):
        return False
    return True

def fresh(path):
    try:
        return (now - os.path.getmtime(path)) <= window
    except OSError:
        return False

# Live interactive sessions, keyed by sessionId.
session_ids = []
for f in glob.glob(os.path.join(home, "sessions", "*.json")):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    pid = d.get("pid")
    if pid is None:
        base = os.path.splitext(os.path.basename(f))[0]
        pid = int(base) if base.isdigit() else None
    if alive(pid):
        sid = d.get("sessionId")
        if sid:
            session_ids.append(sid)

# A session counts as "working" if its own transcript or any of its
# sub-agent transcripts was written within the window.
working = 0
for sid in session_ids:
    mains = glob.glob(os.path.join(proj, "*", sid + ".jsonl"))
    subs  = glob.glob(os.path.join(proj, "*", sid, "subagents", "*.jsonl"))
    if any(fresh(p) for p in mains + subs):
        working += 1

# Sub-agents actively working anywhere (fresh subagent transcripts).
agents = sum(1 for p in glob.glob(os.path.join(proj, "*", "*", "subagents", "*.jsonl"))
             if fresh(p))

print(json.dumps({
    "sessions": len(session_ids),
    "working": working,
    "agents": agents,
}))
PYEOF
