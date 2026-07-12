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
