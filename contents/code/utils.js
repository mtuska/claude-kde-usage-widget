.pragma library

// Shared status/color logic for the compact bars and the popup rows.

var CLAUDE_COLOR = "#DA7756"
var WARN_COLOR = "#E8A87C"
var WARN_THRESHOLD = 0.85

function isLimited(status) {
    return status === "limited" || status === "blocked"
}

function barColor(status, utilization, negativeColor) {
    if (isLimited(status))
        return negativeColor
    return utilization > WARN_THRESHOLD ? WARN_COLOR : CLAUDE_COLOR
}

// Compact token count: 12300000 -> "12.3M", 4500 -> "4.5K".
function fmtTokens(n) {
    if (!n || n < 0) return "0"
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(Math.round(n))
}

// Humanize a duration given in hours: 1.8 -> "1h 48m", 0.3 -> "18m".
function fmtHours(hours) {
    if (!(hours > 0)) return ""
    var totalMin = Math.round(hours * 60)
    var d = Math.floor(totalMin / 1440)
    var h = Math.floor((totalMin % 1440) / 60)
    var m = totalMin % 60
    var parts = []
    if (d > 0) parts.push(d + "d")
    if (h > 0) parts.push(h + "h")
    if (m > 0 && d === 0) parts.push(m + "m")
    return parts.length ? parts.join(" ") : "<1m"
}

// Map a Statuspage severity (indicator or incident impact) to a theme color.
// Severities: none | minor | major | critical.
function severityColor(severity, positiveColor, neutralColor, negativeColor, disabledColor) {
    switch (severity) {
        case "none":     return positiveColor
        case "minor":    return neutralColor
        case "major":    return WARN_COLOR
        case "critical": return negativeColor
        default:         return disabledColor
    }
}
