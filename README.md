# Claude Limits Widget

KDE Plasma 6 panel widget that shows your Claude API rate limit usage in real time.

Displays two windows: 5-hour and 7-day, each with a usage bar, utilization percentage, and time until reset. The popup
also shows Claude's service status and any active incidents pulled from
[status.claude.com](https://status.claude.com/), so you stay aware of outages; the panel view flags a degraded status
with a colored dot. It also counts the Claude Code sessions running **on this machine** — how many are open, how many
are actively working right now, plus a count of running sub-agents. From the local transcripts it derives today's
token usage and an estimated (pay-as-you-go equivalent) cost, a per-model split, cache-hit ratio, a 7-day usage
sparkline, and — by dividing tokens used in a window by the server's reported utilization — an **estimated ceiling**
for each limit plus a burn-rate ETA to when you'd hit it. It also surfaces whether **usage credits** (overage) are
available when you hit a limit, plus scheduled-maintenance windows and per-component status from the status page.
Everything is individually toggleable, and optional desktop notifications fire on configurable thresholds, on a limit
being fully reached, or on a new incident/maintenance. Compact view lives in the panel; click to open the full popup.

**KDE Store:** https://www.opendesktop.org/p/2359310

## Nothing here costs you tokens

Every source the widget reads is free. The rate-limit windows come from **`GET
https://api.anthropic.com/api/oauth/usage`** — the same endpoint Claude Code's own `/usage` screen reads —
authenticated with the OAuth token Claude Code already keeps in `~/.claude/.credentials.json`. It's a plain read: no
inference, no tokens, and nothing charged against the very limits it reports.

| Data | Source | Cost |
|---|---|---|
| 5h / 7d rate-limit windows, usage credits | `GET /api/oauth/usage` (OAuth) | free |
| Today's tokens/cost, cache %, model split, 7-day sparkline | local `~/.claude` scan | free |
| Running / working agents & sub-agents | local transcript mtimes | free |
| Service status, incidents, maintenance | `status.claude.com` (unauthenticated) | free |

> **Note:** versions before this read the `anthropic-ratelimit-unified-*` **response headers** instead, which meant
> burning a real (1-token) Haiku call on every refresh just to see the headers come back. The usage endpoint replaces
> that entirely — so the refresh interval is now only about how live you want the bars, not what they cost. It
> defaults to 1 minute.

## How it works

On each rate-limit refresh the widget runs a shell script that:

1. Reads your OAuth token from `~/.claude/.credentials.json` (written by Claude Code)
2. `GET`s `https://api.anthropic.com/api/oauth/usage` with that token
3. Maps the response — `five_hour` and `seven_day`, each a `utilization` percentage plus an ISO-8601 `resets_at`,
   along with the usage-credits (`extra_usage`) state — into the widget's shape
4. Returns it as JSON to the widget

The reset countdown is then derived locally from that timestamp (see `LimitRow.qml`) and ticks down every second
between refreshes. The endpoint is itself rate-limited server-side, so the widget stays polite rather than hammering
it; a failed refresh keeps the last-known values.

Separately, the widget polls `status.claude.com/api/v2/summary.json` every 2 minutes for service status and active
incidents. That request is unauthenticated and **does not cost any tokens**.

It also scans `~/.claude` every 10 seconds to count Claude Code work happening **right now**: a transcript that was
written in the last ~30 seconds means that agent is actively generating. It reports how many top-level **agents** and
how many **sub-agents** are working — merely-open (idle) editor windows are not counted. Once a minute it parses the
transcript `usage`
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

**General** — show/hide the title, the rate-limit refresh interval (minutes; each refresh is a free GET), and proxy
mode (see below).

**Components** — toggle each feature independently and set its own poll interval:

| Setting | Description |
|---|---|
| Status line | Claude service status & incidents (`status.claude.com`) |
| Scheduled maintenance | Upcoming/in-progress maintenance windows |
| Per-component status | Operational state of each component (API, Console, Code, …) |
| Sessions | Local running/working/sub-agent counts (this machine) |
| Usage | Today's tokens, cost, per-model split, cache-hit %, and 7-day sparkline |
| Estimated ceiling & ETA | The `used ÷ utilization` ceiling estimate and burn-rate ETA on each limit |
| Poll intervals | Status (min), sessions (s), usage-scan (s) — all local scans |

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
