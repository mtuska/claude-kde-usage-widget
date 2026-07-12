#!/bin/bash
# Count Claude Code agents actively working on this machine, and emit JSON:
#   {"agents": N, "subagents": M}
#
#   agents    – top-level sessions currently generating (their main transcript
#               was written within WINDOW seconds)
#   subagents – Task-spawned sub-agents currently generating (a fresh transcript
#               under a .../subagents/ directory)
#
# "Actively working" is inferred from transcript write recency: Claude Code
# streams output to the transcript continuously while generating and stops when
# idle. This only counts work happening now — not merely-open editor windows —
# and is a purely local filesystem read (no network, no API tokens).

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
WINDOW="${SESSION_WINDOW:-30}"
export CLAUDE_DIR WINDOW

python3 - <<'PYEOF'
import glob, json, os, time

home = os.environ["CLAUDE_DIR"]
window = float(os.environ["WINDOW"])
proj = os.path.join(home, "projects")
now = time.time()
sep = os.sep

def fresh(path):
    try:
        return (now - os.path.getmtime(path)) <= window
    except OSError:
        return False

agents = 0
subagents = 0
for path in glob.glob(os.path.join(proj, "**", "*.jsonl"), recursive=True):
    if not fresh(path):
        continue
    if (sep + "subagents" + sep) in path:
        subagents += 1
    else:
        agents += 1

print(json.dumps({"agents": agents, "subagents": subagents}))
PYEOF
