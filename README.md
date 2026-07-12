# Claude Limits Widget

KDE Plasma 6 panel widget that shows your Claude API rate limit usage in real time.

Displays two windows: 5-hour and 7-day, each with a usage bar, utilization percentage, and time until reset. The popup
also shows Claude's service status and any active incidents pulled from
[status.claude.com](https://status.claude.com/), so you stay aware of outages; the panel view flags a degraded status
with a colored dot. It also counts the Claude Code sessions running **on this machine** — how many are open, how many
are actively working right now, and how many sub-agents are running. From the local transcripts it derives today's
token usage and an estimated (pay-as-you-go equivalent) cost, a per-model split, cache-hit ratio, a 7-day usage
sparkline, and — by dividing tokens used in a window by the server's reported utilization — an **estimated ceiling**
for each limit plus a burn-rate ETA to when you'd hit it. It also surfaces whether **usage credits** (overage) are
available when you hit a limit, plus scheduled-maintenance windows and per-component status from the status page.
Everything is individually toggleable, and optional desktop notifications fire on configurable thresholds, on a limit
being fully reached, or on a new incident/maintenance. Compact view lives in the panel; click to open the full popup.

**KDE Store:** https://www.opendesktop.org/p/2359310

## How it works

On each refresh the widget runs a shell script that:

1. Reads your OAuth token from `~/.claude/.credentials.json` (written by Claude Code)
2. Makes a minimal `POST /v1/messages` call to `api.anthropic.com` using the cheapest model (
   `claude-haiku-4-5-20251001`) with `max_tokens: 1`
3. Extracts the `anthropic-ratelimit-unified-*` response headers
4. Returns the parsed values as JSON to the widget

> **Note:** Every refresh burns real tokens. The call is as small as possible (1 output token), but it is a real API
> request that counts against your usage. Set the refresh interval accordingly.

Separately, the widget polls `status.claude.com/api/v2/summary.json` every 2 minutes for service status and active
incidents. That request is unauthenticated and **does not cost any tokens**.

It also scans `~/.claude` every 10 seconds to count local Claude Code activity: running sessions
(`~/.claude/sessions/*.json` with a live PID), how many have written transcript output in the last ~45 seconds
("working"), and how many sub-agent transcripts are currently active. Once a minute it parses the transcript `usage`
fields to total today's tokens and estimate cost, and sums per-window tokens for the ceiling/ETA estimates. Both are
purely local filesystem reads — no network, no tokens — and only see activity on this machine, not chats on claude.ai
or other devices.

> **Estimates are rough.** The "estimated ceiling" divides your local token sum by the server's utilization; Anthropic
> weights tokens (especially cache reads) differently, so treat it as a ballpark. The "$" cost is the equivalent
> pay-as-you-go price of those tokens — on a Max/Pro subscription you are **not** billed it.

Desktop notifications use `notify-send` and fire on a rising edge (once per crossing, re-armed on recovery).

## Requirements

- KDE Plasma 6
- `curl`, `python3`, `bash`
- `libnotify` (`notify-send`) for desktop notifications — optional
- An active Claude account with Claude Code installed (provides `~/.claude/.credentials.json`)

## Installation

```bash
kpackagetool6 --install . --type Plasma/Applet
```

To upgrade after changes:

```bash
kpackagetool6 --upgrade . --type Plasma/Applet
```

Then restart Plasma:

```bash
plasmashell --replace &
```

## Settings

Right-click the widget → Configure. Settings are split across three pages.

**General** — show/hide the title, the rate-limit refresh interval (minutes; each refresh is one 1-token API
call), and proxy mode (see below).

**Components** — toggle each feature independently and set its own poll interval:

| Setting | Description |
|---|---|
| Status line | Claude service status & incidents (`status.claude.com`) |
| Scheduled maintenance | Upcoming/in-progress maintenance windows |
| Per-component status | Operational state of each component (API, Console, Code, …) |
| Sessions | Local running/working/sub-agent counts (this machine) |
| Usage | Today's tokens, cost, per-model split, cache-hit %, and 7-day sparkline |
| Estimated ceiling & ETA | The `used ÷ utilization` ceiling estimate and burn-rate ETA on each limit |
| Poll intervals | Status (min), sessions (s), usage-scan (s) — status/session/usage scans are local & token-free |

**Notifications** — desktop notifications via `notify-send`, each individually toggleable:

| Setting | Description |
|---|---|
| 5-hour / 7-day high | Notify when utilization crosses a configurable threshold (default 90%) |
| Limit reached | Notify when a window is fully used (100% / LIMITED) |
| Incidents | Notify when a new Claude incident is reported |
| Maintenance | Notify when scheduled maintenance is announced (off by default) |

### Proxy settings

| Mode       | Behavior                                                               |
|------------|------------------------------------------------------------------------|
| No proxy   | Passes `--noproxy '*'` to curl, bypassing any system proxy             |
| System env | curl reads `HTTP_PROXY` / `HTTPS_PROXY` from the environment (default) |
| Custom URL | Uses the URL you provide, e.g. `http://proxy.example.com:8080`         |

## License

MIT
