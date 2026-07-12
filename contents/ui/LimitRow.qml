import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "../code/utils.js" as Utils

ColumnLayout {
    id: root

    property string label: ""
    // One window object from fetch_limits.sh output (h5 or d7)
    property var windowData: null

    // Local token usage in this window and the recent burn rate (tokens/hour),
    // from fetch_usage.sh — used to estimate the hidden ceiling and ETA.
    property real windowTokens: 0
    property real ratePerHour: 0

    readonly property real utilization: windowData ? windowData.utilization : 0
    readonly property string status: windowData ? (windowData.status || "") : ""
    readonly property string resetIn: windowData ? (windowData.reset_in || "") : ""
    readonly property string resetTs: windowData ? (windowData.reset_ts || "") : ""

    // Reactive clock: bindings that need the current time depend on `now`
    // instead of Date.now() (which QML can't track), so a Timer ticking this
    // property forces the countdown below to re-evaluate live.
    property double now: new Date().getTime()

    // Milliseconds until reset (-1 when unknown), re-evaluated as `now` ticks.
    readonly property double diffMs: {
        if (!resetTs) return -1
        var ts = parseInt(resetTs)
        if (isNaN(ts) || ts <= 0) return -1
        return ts * 1000 - now
    }

    Timer {
        // Tick every second in the final minute so the countdown reads
        // 55s, 54s, … ; a slower 30s tick is plenty the rest of the time.
        interval: (root.diffMs > 0 && root.diffMs < 60000) ? 1000 : 30000
        running: true
        repeat: true
        onTriggered: root.now = new Date().getTime()
    }

    readonly property string resetLabel: {
        if (diffMs < 0) return resetIn
        if (diffMs <= 0) return "now"
        if (diffMs < 60000) return Math.ceil(diffMs / 1000) + "s"
        var totalMins = Math.round(diffMs / 60000)
        var days = Math.floor(totalMins / 1440)
        var hrs  = Math.floor((totalMins % 1440) / 60)
        var mins = totalMins % 60
        var parts = []
        if (days > 0) parts.push(days + "d")
        if (hrs  > 0) parts.push(hrs + " hr")
        if (mins > 0) parts.push(mins + " min")
        return parts.length ? parts.join(" ") : "< 1 min"
    }

    readonly property bool limited: Utils.isLimited(status)
    readonly property color barColor: Utils.barColor(status, utilization, Kirigami.Theme.negativeTextColor)

    // Estimated total ceiling for this window: used ÷ utilization (rough — the
    // server's utilization weighting differs from a raw token sum).
    readonly property bool hasEstimate: windowTokens > 0 && utilization > 0.01
    readonly property real estimatedCeiling: hasEstimate ? windowTokens / utilization : 0

    // ETA to the limit at the current burn rate, capped at the window reset.
    readonly property real etaHours: (hasEstimate && ratePerHour > 0)
        ? Math.max(estimatedCeiling - windowTokens, 0) / ratePerHour : 0
    readonly property real hoursToReset: diffMs > 0 ? diffMs / 3600000 : 0
    // Only meaningful if the limit would be hit before the window resets.
    readonly property bool etaBeforeReset: etaHours > 0 && hoursToReset > 0 && etaHours < hoursToReset

    readonly property string estimateLabel: {
        if (!hasEstimate) return ""
        var t = "~" + Utils.fmtTokens(windowTokens) + " / ~" + Utils.fmtTokens(estimatedCeiling) + " tok"
        if (etaBeforeReset)
            t += " · full in ~" + Utils.fmtHours(etaHours)
        return t
    }

    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        PlasmaComponents.Label {
            text: root.label
            font.bold: true
            font.pixelSize: 12
        }

        PlasmaComponents.Label {
            text: Math.round(root.utilization * 100) + "%"
            font.pixelSize: 12
            opacity: 0.7
        }

        Item { Layout.fillWidth: true }

        PlasmaComponents.Label {
            text: root.limited ? "LIMITED" : ""
            font.pixelSize: 10
            color: Kirigami.Theme.negativeTextColor
            visible: root.limited
        }
    }

    // Progress bar background
    Rectangle {
        Layout.fillWidth: true
        height: 7
        radius: 3
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1

        Rectangle {
            width: Math.max(Math.min(root.utilization, 1.0) * parent.width, root.utilization > 0 ? 4 : 0)
            height: parent.height
            radius: parent.radius
            color: root.barColor
            Behavior on width { NumberAnimation { duration: 300 } }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        PlasmaComponents.Label {
            text: root.resetLabel ? "Resets " + root.resetLabel : ""
            font.pixelSize: 10
            opacity: 0.7
            visible: root.resetIn !== ""
        }

        Item { Layout.fillWidth: true }

        // Estimated used / ceiling (+ ETA to limit at current burn).
        PlasmaComponents.Label {
            text: root.estimateLabel
            font.pixelSize: 10
            opacity: 0.7
            color: root.etaBeforeReset ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            visible: root.hasEstimate
        }
    }
}
