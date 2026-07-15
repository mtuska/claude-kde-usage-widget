import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

import "../code/utils.js" as Utils

PlasmoidItem {
    id: root

    // Let Plasma pick automatically:
    //   - compact on a panel
    //   - full on the desktop
    // Setting preferredRepresentation: fullRepresentation here forces the
    // popup to render inline in the panel — don't do it.

    property var limitData: null
    property string errorMsg: ""
    property bool loading: false
    property string lastUpdated: ""

    // Service status from status.claude.com (free, no token cost).
    property var statusData: null
    property string statusError: ""

    readonly property var incidents: statusData && statusData.incidents ? statusData.incidents : []
    readonly property string statusIndicator: statusData ? (statusData.indicator || "") : ""
    // Anything other than "none" (or a missing/unknown status) is degraded.
    readonly property bool statusDegraded: statusData !== null
        && statusIndicator !== "" && statusIndicator !== "none"

    // Local Claude Code activity on this machine (free, no token cost).
    property var sessionData: null

    // Actively-working agents / sub-agents on this machine (right now).
    readonly property int agentCount: sessionData ? (sessionData.agents || 0) : 0
    readonly property int subagentCount: sessionData ? (sessionData.subagents || 0) : 0
    readonly property bool hasActivity: agentCount > 0 || subagentCount > 0
    readonly property string activityText: {
        var parts = []
        if (agentCount > 0) parts.push(agentCount + (agentCount === 1 ? " agent" : " agents"))
        if (subagentCount > 0) parts.push(subagentCount + (subagentCount === 1 ? " sub-agent" : " sub-agents"))
        return parts.join(" · ")
    }
    // Terse compact form: "1", "1 +2", "+2".
    readonly property string activityCompact: {
        var parts = []
        if (agentCount > 0) parts.push("" + agentCount)
        if (subagentCount > 0) parts.push("+" + subagentCount)
        return parts.join(" ")
    }

    // Service status extras
    readonly property var maintenances: statusData && statusData.maintenances ? statusData.maintenances : []
    readonly property var statusComponents: statusData && statusData.components ? statusData.components : []
    readonly property bool componentsDegraded: {
        for (var i = 0; i < statusComponents.length; i++)
            if ((statusComponents[i].status || "operational") !== "operational") return true
        return false
    }

    // Usage credits (overage): whether spend past the limit is allowed.
    readonly property string overageStatus: limitData ? (limitData.overage_status || "") : ""

    // Local token usage / estimated cost from transcripts (free, no token cost).
    property var usageData: null
    readonly property real ratePerHour: usageData ? (usageData.rate_per_hour || 0) : 0
    readonly property var byModel: usageData && usageData.by_model ? usageData.by_model : ({})
    readonly property var daily: usageData && usageData.daily ? usageData.daily : []
    readonly property real cacheRatio: {
        if (!usageData || !usageData.today) return 0
        var t = usageData.today.total
        return t > 0 ? usageData.today.cache_read / t : 0
    }
    readonly property real maxDaily: {
        var m = 0
        for (var i = 0; i < daily.length; i++) if (daily[i] > m) m = daily[i]
        return m
    }
    readonly property string modelBreakdown: {
        var total = (usageData && usageData.today) ? usageData.today.total : 0
        if (!total) return ""
        var keys = Object.keys(byModel)
        keys.sort(function(a, b) { return byModel[b] - byModel[a] })
        var parts = []
        for (var i = 0; i < keys.length && i < 4; i++)
            parts.push(keys[i] + " " + Math.round(byModel[keys[i]] / total * 100) + "%")
        return parts.join(" · ")
    }
    readonly property bool overageAvailable: overageStatus === "allowed"
    readonly property string overageLabel: overageStatus ? (overageAvailable ? "available" : "disabled") : ""

    // ── Configuration (with sensible fallbacks) ───────────────────────────────
    readonly property bool cfgShowStatus:      Plasmoid.configuration.showStatus !== false
    readonly property bool cfgShowMaintenance: Plasmoid.configuration.showMaintenance !== false
    readonly property bool cfgShowComponents:  Plasmoid.configuration.showComponents === true
    readonly property bool cfgShowSessions:    Plasmoid.configuration.showSessions !== false
    readonly property bool cfgShowUsage:       Plasmoid.configuration.showUsage !== false
    readonly property bool cfgShowEstimates:   Plasmoid.configuration.showEstimates !== false
    readonly property int  cfgStatusInterval:  Math.max(1, Plasmoid.configuration.statusInterval || 2)
    readonly property int  cfgSessionInterval: Math.max(3, Plasmoid.configuration.sessionInterval || 10)
    readonly property int  cfgUsageInterval:   Math.max(15, Plasmoid.configuration.usageInterval || 60)

    readonly property bool cfgNotify5h:          Plasmoid.configuration.notify5h !== false
    readonly property bool cfgNotify7d:          Plasmoid.configuration.notify7d !== false
    readonly property bool cfgNotifyLimit:       Plasmoid.configuration.notifyLimitReached !== false
    readonly property bool cfgNotifyIncident:    Plasmoid.configuration.notifyIncident !== false
    readonly property bool cfgNotifyMaintenance: Plasmoid.configuration.notifyMaintenance === true
    readonly property real cfgThreshold5h:       (Plasmoid.configuration.notify5hThreshold || 90) / 100
    readonly property real cfgThreshold7d:       (Plasmoid.configuration.notify7dThreshold || 90) / 100

    // Rising-edge notification state.
    property bool notified5h: false
    property bool notified7d: false
    property bool notifiedLimit5h: false
    property bool notifiedLimit7d: false
    property string notifiedIncidentKey: ""
    property string notifiedMaintKey: ""

    readonly property var h5: limitData ? limitData.h5 : null
    readonly property var d7: limitData ? limitData.d7 : null
    readonly property bool hasData: limitData !== null
    readonly property bool firstLoad: loading && !hasData

    readonly property int effectiveInterval: Math.max(1, Plasmoid.configuration.refreshInterval || 1)
    readonly property bool showTitle: Plasmoid.configuration.showTitle !== false

    readonly property string scriptPath: Qt.resolvedUrl("../code/fetch_limits.sh").toString().replace("file://", "")
    readonly property string statusScriptPath: Qt.resolvedUrl("../code/fetch_status.sh").toString().replace("file://", "")
    readonly property string sessionScriptPath: Qt.resolvedUrl("../code/fetch_sessions.sh").toString().replace("file://", "")
    readonly property string usageScriptPath: Qt.resolvedUrl("../code/fetch_usage.sh").toString().replace("file://", "")

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            root.loading = false
            disconnectSource(source)

            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""

            if (!stdout.trim()) {
                root.errorMsg = stderr || "No output from script"
                return
            }
            try {
                var parsed = JSON.parse(stdout.trim())
                if (parsed.error) {
                    root.errorMsg = parsed.error
                    root.limitData = null
                } else {
                    root.limitData = parsed
                    root.errorMsg = ""
                    var now = new Date()
                    root.lastUpdated = now.getHours() + ":" + String(now.getMinutes()).padStart(2, "0")
                    root.checkLimitNotifications()
                }
            } catch(e) {
                root.errorMsg = "Parse error: " + stdout.substring(0, 80)
            }
        }
    }

    function fetchLimits() {
        if (root.loading) return
        root.loading = true
        var safePath  = root.scriptPath.replace(/'/g, "'\\''")
        var safeProxy = (Plasmoid.configuration.proxyUrl || "").replace(/'/g, "'\\''")
        var proxyMode = Plasmoid.configuration.proxyMode || "env"
        executable.connectSource("bash '" + safePath + "' '" + proxyMode + "' '" + safeProxy + "'")
    }

    P5Support.DataSource {
        id: statusExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)

            var stdout = (data["stdout"] || "").trim()
            var stderr = data["stderr"] || ""

            if (!stdout) {
                root.statusError = stderr || "No status output"
                return
            }
            try {
                var parsed = JSON.parse(stdout)
                if (parsed.error) {
                    root.statusError = parsed.error
                } else {
                    root.statusData = parsed
                    root.statusError = ""
                    root.checkIncidentNotifications()
                    root.checkMaintenanceNotifications()
                }
            } catch(e) {
                root.statusError = "Status parse error"
            }
        }
    }

    function fetchStatus() {
        var safePath  = root.statusScriptPath.replace(/'/g, "'\\''")
        var safeProxy = (Plasmoid.configuration.proxyUrl || "").replace(/'/g, "'\\''")
        var proxyMode = Plasmoid.configuration.proxyMode || "env"
        statusExecutable.connectSource("bash '" + safePath + "' '" + proxyMode + "' '" + safeProxy + "'")
    }

    P5Support.DataSource {
        id: sessionExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            var stdout = (data["stdout"] || "").trim()
            if (!stdout) return
            try {
                var parsed = JSON.parse(stdout)
                if (!parsed.error) root.sessionData = parsed
            } catch(e) {
                // Local activity is best-effort; ignore transient parse errors.
            }
        }
    }

    function fetchSessions() {
        var safePath = root.sessionScriptPath.replace(/'/g, "'\\''")
        sessionExecutable.connectSource("bash '" + safePath + "'")
    }

    P5Support.DataSource {
        id: usageExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            var stdout = (data["stdout"] || "").trim()
            if (!stdout) return
            try {
                var parsed = JSON.parse(stdout)
                if (!parsed.error) root.usageData = parsed
            } catch(e) {
                // Best-effort; ignore transient parse errors.
            }
        }
    }

    function fetchUsage() {
        var safePath = root.usageScriptPath.replace(/'/g, "'\\''")
        var h5Reset = (root.h5 && root.h5.reset_ts) ? root.h5.reset_ts : "0"
        var d7Reset = (root.d7 && root.d7.reset_ts) ? root.d7.reset_ts : "0"
        usageExecutable.connectSource("bash '" + safePath + "' '" + h5Reset + "' '" + d7Reset + "'")
    }

    // Fire-and-forget desktop notifications via notify-send.
    P5Support.DataSource {
        id: notifier
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) { disconnectSource(source) }
    }

    function notify(title, body) {
        var t = String(title).replace(/'/g, "'\\''")
        var b = String(body).replace(/'/g, "'\\''")
        notifier.connectSource("notify-send -a 'Claude Limits' -i dialog-information '" + t + "' '" + b + "'")
    }

    // Rising-edge notification checks: fire once per crossing, re-arm on recovery.
    function checkWindow(win, enabled, threshold, notifiedProp, notifiedLimitProp, label) {
        if (!win) return
        var util = win.utilization
        var reached = util >= 1.0 || Utils.isLimited(win.status || "")
        // Threshold-crossing notification.
        if (enabled) {
            if (util >= threshold && !root[notifiedProp]) {
                root[notifiedProp] = true
                root.notify("Claude " + label + " limit high", Math.round(util * 100) + "% used")
            } else if (util < threshold) {
                root[notifiedProp] = false
            }
        }
        // "Full usage" / limit-reached notification.
        if (root.cfgNotifyLimit) {
            if (reached && !root[notifiedLimitProp]) {
                root[notifiedLimitProp] = true
                root.notify("Claude " + label + " limit reached", "Window is fully used (100%)")
            } else if (!reached) {
                root[notifiedLimitProp] = false
            }
        }
    }

    function checkLimitNotifications() {
        checkWindow(root.h5, root.cfgNotify5h, root.cfgThreshold5h, "notified5h", "notifiedLimit5h", "5-hour")
        checkWindow(root.d7, root.cfgNotify7d, root.cfgThreshold7d, "notified7d", "notifiedLimit7d", "7-day")
    }

    function checkIncidentNotifications() {
        if (root.cfgNotifyIncident && root.incidents.length > 0) {
            var key = root.incidents.map(function(i) { return i.name }).join("|")
            if (key !== root.notifiedIncidentKey) {
                root.notifiedIncidentKey = key
                root.notify("Claude service incident", root.incidents[0].name)
            }
        } else if (root.incidents.length === 0) {
            root.notifiedIncidentKey = ""
        }
    }

    function checkMaintenanceNotifications() {
        if (root.cfgNotifyMaintenance && root.maintenances.length > 0) {
            var key = root.maintenances.map(function(m) { return m.name }).join("|")
            if (key !== root.notifiedMaintKey) {
                root.notifiedMaintKey = key
                root.notify("Claude scheduled maintenance", root.maintenances[0].name)
            }
        } else if (root.maintenances.length === 0) {
            root.notifiedMaintKey = ""
        }
    }

    Timer {
        interval: root.effectiveInterval * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.fetchLimits()
    }

    // Delayed first fetch: give the network / session a moment after login
    Timer {
        interval: 6000
        running: true
        repeat: false
        onTriggered: root.fetchLimits()
    }

    // Service status is free to poll, so refresh it on a fixed short cadence
    // regardless of the (token-burning) limits refresh interval.
    Timer {
        interval: root.cfgStatusInterval * 60 * 1000
        running: root.cfgShowStatus
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchStatus()
    }

    // Local session activity is a cheap filesystem scan; poll it often so the
    // "working" count feels live.
    Timer {
        interval: root.cfgSessionInterval * 1000
        running: root.cfgShowSessions
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchSessions()
    }

    // Token usage / cost parses the transcripts (~0.5s).
    Timer {
        interval: root.cfgUsageInterval * 1000
        running: root.cfgShowUsage
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchUsage()
    }

    // ── Compact (panel bar) ──────────────────────────────────────────────────
    compactRepresentation: MouseArea {
        id: compactRoot

        // Tell the panel how wide/tall we want to be. Plasma's panel layout
        // reads the Layout.* attached properties; implicitWidth alone is
        // ignored, which is why the applet gets squeezed to icon width.
        readonly property int desiredWidth: 150

        implicitWidth: desiredWidth
        implicitHeight: compactCol.implicitHeight + 4

        Layout.minimumWidth: desiredWidth
        Layout.preferredWidth: desiredWidth
        Layout.maximumWidth: desiredWidth * 2

        onClicked: root.expanded = !root.expanded

        Column {
            id: compactCol
            anchors.centerIn: parent
            spacing: 2

            CompactBar {
                label: "5h"
                windowData: root.h5
                visible: root.hasData
            }
            CompactBar {
                label: "7d"
                windowData: root.d7
                visible: root.hasData
            }

            // Service-status warning: only shown when Claude is degraded.
            Row {
                spacing: 3
                visible: root.cfgShowStatus && (root.statusDegraded || root.componentsDegraded)

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: Utils.severityColor(
                        root.statusIndicator,
                        Kirigami.Theme.positiveTextColor,
                        Kirigami.Theme.neutralTextColor,
                        Kirigami.Theme.negativeTextColor,
                        Kirigami.Theme.disabledTextColor)
                }

                PlasmaComponents.Label {
                    text: root.incidents.length > 0 ? "issue" : "degraded"
                    font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Active agents / sub-agents: a green dot + count, shown only while
            // something is actively working.
            Row {
                spacing: 3
                visible: root.cfgShowSessions && root.hasActivity

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: Kirigami.Theme.positiveTextColor
                }

                PlasmaComponents.Label {
                    text: root.activityCompact
                    font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            PlasmaComponents.Label {
                text: root.firstLoad ? "…" : (root.errorMsg ? "!" : "")
                font.pixelSize: 9
                visible: root.firstLoad || root.errorMsg !== ""
            }
        }
    }

    // ── Full popup ───────────────────────────────────────────────────────────
    fullRepresentation: Item {
        readonly property int popupWidth: 280

        // Content-sized: height follows the visible sections so toggling
        // components in config resizes the popup instead of clipping.
        implicitWidth: popupWidth
        implicitHeight: popupCol.implicitHeight + 2 * Kirigami.Units.largeSpacing

        Layout.minimumWidth: popupWidth
        Layout.preferredWidth: popupWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            id: popupCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            // Title — first item in layout, always at top
            RowLayout {
                Layout.fillWidth: true
                visible: root.showTitle

                PlasmaComponents.Label {
                    text: "Claude Limits"
                    font.bold: true
                    font.pixelSize: 14
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    QQC2.ToolTip.text: "Refresh now"
                    QQC2.ToolTip.visible: hovered
                    enabled: !root.loading
                    onClicked: root.fetchLimits()
                }
            }

            // Service status (status.claude.com)
            StatusRow {
                Layout.fillWidth: true
                indicator: root.statusIndicator
                description: root.statusData ? (root.statusData.description || "") : ""
                incidents: root.incidents
                errorText: root.statusError
                visible: root.cfgShowStatus && hasStatus
            }

            // Scheduled maintenance windows
            Repeater {
                model: (root.cfgShowStatus && root.cfgShowMaintenance) ? root.maintenances : []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6
                    Kirigami.Icon {
                        source: "tools"
                        Layout.preferredWidth: 12
                        Layout.preferredHeight: 12
                        Layout.alignment: Qt.AlignVCenter
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: modelData.name || "Scheduled maintenance"
                        font.pixelSize: 10
                        color: Kirigami.Theme.neutralTextColor
                        elide: Text.ElideRight
                    }
                }
            }

            // Per-component status list
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                visible: root.cfgShowStatus && root.cfgShowComponents && root.statusComponents.length > 0

                Repeater {
                    model: root.statusComponents
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 6
                            Layout.preferredHeight: 6
                            radius: 3
                            Layout.alignment: Qt.AlignVCenter
                            color: (modelData.status === "operational")
                                   ? Kirigami.Theme.positiveTextColor
                                   : Kirigami.Theme.neutralTextColor
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            font.pixelSize: 10
                            opacity: 0.8
                            elide: Text.ElideRight
                        }
                        PlasmaComponents.Label {
                            text: modelData.status
                            font.pixelSize: 9
                            opacity: 0.7
                            color: (modelData.status === "operational")
                                   ? Kirigami.Theme.textColor
                                   : Kirigami.Theme.neutralTextColor
                        }
                    }
                }
            }

            // Active Claude Code agents / sub-agents on this machine
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.cfgShowSessions && root.hasActivity

                Kirigami.Icon {
                    source: "utilities-terminal"
                    Layout.preferredWidth: 12
                    Layout.preferredHeight: 12
                    Layout.alignment: Qt.AlignVCenter
                }

                PlasmaComponents.Label {
                    text: root.activityText + " working"
                    font.pixelSize: 11
                    opacity: 0.9
                }

                Item { Layout.fillWidth: true }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.errorMsg
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                visible: root.errorMsg !== "" && !root.loading
            }

            // Placeholder before first data arrives
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                visible: !root.hasData

                PlasmaComponents.BusyIndicator {
                    anchors.centerIn: parent
                    visible: root.firstLoad
                    running: visible
                }

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: "Waiting for first update…"
                    opacity: 0.6
                    visible: !root.firstLoad && root.errorMsg === ""
                }
            }

            LimitRow {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                label: "5-hour window"
                windowData: root.h5
                windowTokens: root.usageData ? (root.usageData.window_5h_tokens || 0) : 0
                ratePerHour: root.ratePerHour
                showEstimate: root.cfgShowEstimates
                visible: root.hasData
            }

            LimitRow {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                label: "7-day window"
                windowData: root.d7
                windowTokens: root.usageData ? (root.usageData.window_7d_tokens || 0) : 0
                ratePerHour: root.ratePerHour
                showEstimate: root.cfgShowEstimates
                visible: root.hasData
            }

            // Usage credits (overage) + fallback capacity
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.hasData
                         && (root.overageLabel !== "" || (root.limitData && root.limitData.fallback))

                PlasmaComponents.Label {
                    text: "Usage credits:"
                    opacity: 0.7
                    font.pixelSize: 11
                    visible: root.overageLabel !== ""
                }
                PlasmaComponents.Label {
                    text: root.overageLabel
                    font.pixelSize: 11
                    visible: root.overageLabel !== ""
                    color: root.overageAvailable ? Kirigami.Theme.positiveTextColor
                                                  : Kirigami.Theme.neutralTextColor
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: (root.limitData && root.limitData.fallback) ? "Fallback: " + root.limitData.fallback : ""
                    font.pixelSize: 11
                    opacity: 0.7
                    visible: root.limitData && root.limitData.fallback
                    color: (root.limitData && root.limitData.fallback === "available")
                           ? Kirigami.Theme.positiveTextColor
                           : Kirigami.Theme.neutralTextColor
                }
            }

            // Token usage: Today total/cost/cache, per-model split, 7-day sparkline
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: 1
                visible: root.cfgShowUsage && root.usageData
                         && root.usageData.today && root.usageData.today.total > 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    PlasmaComponents.Label { text: "Today"; font.pixelSize: 11; font.bold: true; opacity: 0.8 }
                    PlasmaComponents.Label {
                        text: root.usageData ? Utils.fmtTokens(root.usageData.today.total) + " tok" : ""
                        font.pixelSize: 11
                    }
                    PlasmaComponents.Label {
                        text: (root.usageData && root.usageData.today.cost) ? "· ~$" + root.usageData.today.cost.toFixed(2) : ""
                        font.pixelSize: 11
                        opacity: 0.7
                        QQC2.ToolTip.text: "Estimated pay-as-you-go equivalent — not billed on a subscription"
                        QQC2.ToolTip.visible: costMouse.containsMouse
                        MouseArea { id: costMouse; anchors.fill: parent; hoverEnabled: true }
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: root.cacheRatio > 0 ? Math.round(root.cacheRatio * 100) + "% cached" : ""
                        font.pixelSize: 10
                        opacity: 0.6
                    }
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.modelBreakdown
                    font.pixelSize: 10
                    opacity: 0.7
                    visible: root.modelBreakdown !== ""
                    elide: Text.ElideRight
                }

                // 7-day usage sparkline (today highlighted)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 4
                    visible: root.daily.length === 7 && root.maxDaily > 0

                    PlasmaComponents.Label { text: "7d"; font.pixelSize: 9; opacity: 0.6; Layout.alignment: Qt.AlignBottom }

                    Row {
                        Layout.fillWidth: true
                        height: 20
                        spacing: 3
                        Repeater {
                            model: root.daily
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: 12
                                height: Math.max((modelData / root.maxDaily) * 18, 2)
                                anchors.bottom: parent.bottom
                                radius: 2
                                color: Kirigami.Theme.highlightColor
                                opacity: index === 6 ? 1.0 : 0.45
                            }
                        }
                    }

                    PlasmaComponents.Label { text: "today"; font.pixelSize: 9; opacity: 0.5; Layout.alignment: Qt.AlignBottom }
                }
            }

            // Footer: plan · interval · last update
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 4
                opacity: 0.6
                visible: !root.loading

                PlasmaComponents.Label {
                    text: root.limitData && root.limitData.plan ? (root.limitData.plan.charAt(0).toUpperCase() + root.limitData.plan.slice(1)) + " ·" : ""
                    font.pixelSize: 10
                    visible: root.limitData && root.limitData.plan
                }

                Kirigami.Icon {
                    source: "view-refresh"
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    Layout.alignment: Qt.AlignVCenter
                }

                PlasmaComponents.Label {
                    text: root.effectiveInterval + " min ·"
                    font.pixelSize: 10
                }

                PlasmaComponents.Label {
                    text: root.lastUpdated ? "Updated " + root.lastUpdated : ""
                    font.pixelSize: 10
                    visible: root.lastUpdated !== ""
                }
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignRight
                text: "Refreshing…"
                font.pixelSize: 10
                opacity: 0.6
                visible: root.loading
            }
        }
    }
}
