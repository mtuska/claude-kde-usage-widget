#!/bin/bash
# Fetch Claude rate-limit windows from the OAuth usage endpoint.
# Outputs JSON for the QML widget to consume.
#
# This is a plain authenticated GET: no inference, no tokens, and nothing
# charged against the very limits it reports. It reads the same endpoint that
# Claude Code's own /usage screen uses.
#
# Usage: fetch_limits.sh [proxy_mode] [proxy_url]
#   proxy_mode: none | env (default) | custom

PROXY_MODE="${1:-env}"
PROXY_URL="${2:-}"
CREDS_FILE="${CREDS_FILE:-$HOME/.claude/.credentials.json}"
export CREDS_FILE

USAGE_URL="https://api.anthropic.com/api/oauth/usage"

err() {
    printf '{"error": "%s"}\n' "$1"
    exit 1
}

# Prints two lines: access token, subscription type.
read_creds() {
    python3 - <<'PYEOF'
import json, os, sys
try:
    with open(os.environ['CREDS_FILE']) as f:
        oauth = json.load(f)['claudeAiOauth']
    print(oauth['accessToken'])
    print(oauth.get('subscriptionType', ''))
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
}

load_creds() {
    local creds
    creds=$(read_creds) || return 1
    ACCESS_TOKEN=$(sed -n 1p <<<"$creds")
    SUBSCRIPTION_TYPE=$(sed -n 2p <<<"$creds")
    [ -n "$ACCESS_TOKEN" ]
}

# Prints the usage JSON body; empty on any non-2xx (--fail) or transport error.
fetch_usage() {
    local args=(-s --fail
        -H "Authorization: Bearer $ACCESS_TOKEN"
        -H "Content-Type: application/json"
        --max-time 10)
    case "$PROXY_MODE" in
        none)   args+=(--noproxy '*') ;;
        custom) [ -n "$PROXY_URL" ] && args+=(--proxy "$PROXY_URL") ;;
        *)      ;;  # env: curl reads HTTP_PROXY/HTTPS_PROXY automatically
    esac
    curl "${args[@]}" "$USAGE_URL" 2>/dev/null
}

[ -f "$CREDS_FILE" ] || err "No credentials file at ~/.claude/.credentials.json"
load_creds || err "Failed to read access token"

BODY=$(fetch_usage)

# Token may be stale (e.g. right after boot). Spawn claude briefly to
# trigger OAuth refresh, re-read the token, then retry once.
if [ -z "$BODY" ] && command -v claude >/dev/null 2>&1; then
    timeout 5 claude -p "x" >/dev/null 2>&1 || true
    load_creds && BODY=$(fetch_usage)
fi

[ -n "$BODY" ] || err "Usage endpoint request failed"

export BODY SUBSCRIPTION_TYPE
python3 - <<'PYEOF'
import json, os, sys, time
from datetime import datetime, timezone

try:
    payload = json.loads(os.environ['BODY'])
except Exception:
    print(json.dumps({"error": "Malformed response from usage endpoint"}))
    sys.exit(0)


def iso_to_unix(value):
    """The endpoint sends ISO-8601; the widget counts down from unix seconds."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        dt = datetime.fromisoformat(str(value))
    except (TypeError, ValueError):
        return None
    if dt.tzinfo is None:   # defensive: the API sends an offset, but assume UTC
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def fmt_reset(ts):
    if not ts:
        return None
    mins = round((ts - time.time()) / 60)
    if mins < 0:
        return "now"
    if mins < 60:
        return f"{mins}m"
    hours = round(mins / 60)
    if hours < 24:
        return f"{hours}h"
    return f"{round(hours / 24)}d"


def window(raw):
    if not isinstance(raw, dict):
        return {"status": None, "utilization": 0.0, "reset_ts": None,
                "reset_in": None}
    pct = raw.get("utilization")
    # The endpoint reports 0-100; the QML works in 0-1.
    util = float(pct) / 100.0 if isinstance(pct, (int, float)) else 0.0
    ts = iso_to_unix(raw.get("resets_at"))
    return {
        # This endpoint has no allowed/rejected field (the old header API did),
        # so treat a window as limited exactly when it is used up.
        "status": "limited" if util >= 1.0 else "allowed",
        "utilization": util,
        "reset_ts": str(int(ts)) if ts else None,
        "reset_in": fmt_reset(ts),
    }


extra = payload.get("extra_usage") or {}
result = {
    # "Usage credits" in the Claude UI: whether spend past the limit is allowed.
    "overage_status": {True: "allowed", False: "rejected"}.get(
        extra.get("is_enabled")),
    "overage_reason": extra.get("disabled_reason"),
    "h5": window(payload.get("five_hour")),
    "d7": window(payload.get("seven_day")),
    "plan": os.environ.get("SUBSCRIPTION_TYPE", ""),
    "updated_at": int(time.time()),
}
print(json.dumps(result))
PYEOF
