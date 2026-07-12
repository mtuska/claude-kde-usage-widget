#!/bin/bash
# Compute local Claude Code token usage and estimated cost from transcripts,
# plus per-window token sums used to estimate the (hidden) rate-limit ceilings
# and the recent burn rate. Purely local filesystem reads — no network, no
# API tokens.
#
# Usage: fetch_usage.sh [h5_reset_ts] [d7_reset_ts]
#   The reset timestamps (unix seconds) bound the 5h / 7d windows so the token
#   sums line up with the server's utilization for those same windows. If
#   omitted, trailing 5h / 7d from now are used.

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
H5_RESET="${1:-0}"
D7_RESET="${2:-0}"
export CLAUDE_DIR H5_RESET D7_RESET

python3 - <<'PYEOF'
import glob, json, os, time
from datetime import datetime, timezone

home = os.environ["CLAUDE_DIR"]
proj = os.path.join(home, "projects")
now = time.time()
h5_reset = float(os.environ["H5_RESET"])
d7_reset = float(os.environ["D7_RESET"])

# Window start = reset - duration (the window is partly elapsed when the reset
# is in the future). Fall back to a trailing window when no reset is given, and
# clamp the lookback to at most one full duration.
h5_start = max(h5_reset - 5 * 3600, now - 5 * 3600) if h5_reset > 0 else now - 5 * 3600
d7_start = max(d7_reset - 7 * 86400, now - 7 * 86400) if d7_reset > 0 else now - 7 * 86400
hour_start = now - 3600

# Local midnight (today) in epoch seconds, and the start of the 7-day window.
lt = time.localtime(now)
midnight = time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, 0, 0, 0, 0, 0, -1))
week_start = midnight - 6 * 86400  # start of the oldest day shown in the sparkline

# Per-model pricing, $ per token (input, output, cache-write 5m, cache-read).
PRICES = {
    "opus":   (5e-6,  25e-6,  6.25e-6, 0.5e-6),
    "sonnet": (3e-6,  15e-6,  3.75e-6, 0.3e-6),
    "haiku":  (1e-6,  5e-6,   1.25e-6, 0.1e-6),
    "fable":  (10e-6, 50e-6,  12.5e-6, 1.0e-6),
    "mythos": (10e-6, 50e-6,  12.5e-6, 1.0e-6),
}
def price(model):
    m = (model or "").lower()
    for k, v in PRICES.items():
        if k in m:
            return v
    return PRICES["opus"]  # sensible default for unknown Claude models

def parse_ts(rec):
    ts = rec.get("timestamp")
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None

today = {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0, "cost": 0.0}
w5 = 0      # total tokens in the 5h window
w7 = 0      # total tokens in the 7d window
rate = 0    # total tokens in the last hour
by_model = {}   # today's total tokens per (friendly) model name
daily = [0] * 7  # total tokens per day for the last 7 days (index 0 = oldest)

def model_family(model):
    m = (model or "").lower()
    for k in ("opus", "sonnet", "haiku", "fable", "mythos"):
        if k in m:
            return k.capitalize()
    return "Other"

# Only files touched in the last 7 days can contain in-window records.
cutoff = now - 7 * 86400 - 60
for path in glob.glob(os.path.join(proj, "**", "*.jsonl"), recursive=True):
    try:
        if os.path.getmtime(path) < cutoff:
            continue
    except OSError:
        continue
    try:
        f = open(path, "r", errors="ignore")
    except OSError:
        continue
    with f:
        for line in f:
            if '"usage"' not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            msg = rec.get("message") or {}
            usage = msg.get("usage") if isinstance(msg, dict) else None
            if not usage:
                continue
            t = parse_ts(rec)
            if t is None or t < cutoff:
                continue
            i = usage.get("input_tokens", 0) or 0
            o = usage.get("output_tokens", 0) or 0
            cw = usage.get("cache_creation_input_tokens", 0) or 0
            cr = usage.get("cache_read_input_tokens", 0) or 0
            total = i + o + cw + cr

            if t >= d7_start:
                w7 += total
            if t >= h5_start:
                w5 += total
            if t >= hour_start:
                rate += total

            # Daily buckets for the sparkline (index 0 = 6 days ago, 6 = today).
            if t >= week_start:
                di = int((t - week_start) // 86400)
                if di > 6:
                    di = 6
                daily[di] += total

            if t >= midnight:
                today["input"] += i
                today["output"] += o
                today["cache_write"] += cw
                today["cache_read"] += cr
                pi, po, pcw, pcr = price(msg.get("model"))
                today["cost"] += i * pi + o * po + cw * pcw + cr * pcr
                fam = model_family(msg.get("model"))
                by_model[fam] = by_model.get(fam, 0) + total

print(json.dumps({
    "today": {
        "input": today["input"],
        "output": today["output"],
        "cache_write": today["cache_write"],
        "cache_read": today["cache_read"],
        "total": today["input"] + today["output"] + today["cache_write"] + today["cache_read"],
        "cost": round(today["cost"], 2),
    },
    "window_5h_tokens": w5,
    "window_7d_tokens": w7,
    "rate_per_hour": rate,
    "by_model": by_model,
    "daily": daily,
}))
PYEOF
