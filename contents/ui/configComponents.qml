import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_showStatus: showStatusCheck.checked
    property bool cfg_showStatusDefault: true

    property alias cfg_showMaintenance: showMaintenanceCheck.checked
    property bool cfg_showMaintenanceDefault: true

    property alias cfg_showComponents: showComponentsCheck.checked
    property bool cfg_showComponentsDefault: false

    property alias cfg_showSessions: showSessionsCheck.checked
    property bool cfg_showSessionsDefault: true

    property alias cfg_showUsage: showUsageCheck.checked
    property bool cfg_showUsageDefault: true

    property alias cfg_showEstimates: showEstimatesCheck.checked
    property bool cfg_showEstimatesDefault: true

    property alias cfg_statusInterval: statusSpin.value
    property int cfg_statusIntervalDefault: 2

    property alias cfg_sessionInterval: sessionSpin.value
    property int cfg_sessionIntervalDefault: 10

    property alias cfg_usageInterval: usageSpin.value
    property int cfg_usageIntervalDefault: 60

    // ── Service status ────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Service status"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showStatusCheck
        Kirigami.FormData.label: "Status line:"
        text: "Show Claude service status & incidents (status.claude.com)"
    }

    QQC2.CheckBox {
        id: showMaintenanceCheck
        text: "Show scheduled maintenance windows"
        enabled: showStatusCheck.checked
    }

    QQC2.CheckBox {
        id: showComponentsCheck
        text: "Show per-component status (API, Console, Code, …)"
        enabled: showStatusCheck.checked
    }

    QQC2.SpinBox {
        id: statusSpin
        Kirigami.FormData.label: "Poll interval (minutes):"
        from: 1
        to: 60
        value: 2
        enabled: showStatusCheck.checked
        textFromValue: function(v) { return v + " min" }
        valueFromText: function(t) { return parseInt(t) || 2 }
    }

    // ── Local activity ────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Local Claude Code activity"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showSessionsCheck
        Kirigami.FormData.label: "Agents:"
        text: "Show active agents / sub-agents working now (this machine)"
    }

    QQC2.SpinBox {
        id: sessionSpin
        Kirigami.FormData.label: "Poll interval (seconds):"
        from: 3
        to: 300
        value: 10
        enabled: showSessionsCheck.checked
        textFromValue: function(v) { return v + " s" }
        valueFromText: function(t) { return parseInt(t) || 10 }
    }

    // ── Token usage ───────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Token usage & estimates"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showUsageCheck
        Kirigami.FormData.label: "Usage:"
        text: "Show today's tokens, cost, per-model split & 7-day sparkline"
    }

    QQC2.CheckBox {
        id: showEstimatesCheck
        text: "Show estimated ceiling & burn-rate ETA on each limit"
        enabled: showUsageCheck.checked
    }

    QQC2.SpinBox {
        id: usageSpin
        Kirigami.FormData.label: "Scan interval (seconds):"
        from: 15
        to: 600
        value: 60
        enabled: showUsageCheck.checked
        textFromValue: function(v) { return v + " s" }
        valueFromText: function(t) { return parseInt(t) || 60 }
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        text: "Status & activity scans are local/free — they never cost API tokens."
        opacity: 0.7
        font: Kirigami.Theme.smallFont
    }
}
