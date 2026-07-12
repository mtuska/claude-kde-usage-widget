import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_notify5h: notify5hCheck.checked
    property bool cfg_notify5hDefault: true

    property alias cfg_notify5hThreshold: notify5hSpin.value
    property int cfg_notify5hThresholdDefault: 90

    property alias cfg_notify7d: notify7dCheck.checked
    property bool cfg_notify7dDefault: true

    property alias cfg_notify7dThreshold: notify7dSpin.value
    property int cfg_notify7dThresholdDefault: 90

    property alias cfg_notifyLimitReached: notifyLimitCheck.checked
    property bool cfg_notifyLimitReachedDefault: true

    property alias cfg_notifyIncident: notifyIncidentCheck.checked
    property bool cfg_notifyIncidentDefault: true

    property alias cfg_notifyMaintenance: notifyMaintenanceCheck.checked
    property bool cfg_notifyMaintenanceDefault: false

    // ── Rate-limit thresholds ─────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Rate limits"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: notify5hCheck
        Kirigami.FormData.label: "5-hour window:"
        text: "Notify when utilization crosses the threshold"
    }

    QQC2.SpinBox {
        id: notify5hSpin
        Kirigami.FormData.label: "5-hour threshold (%):"
        from: 1
        to: 100
        value: 90
        enabled: notify5hCheck.checked
        textFromValue: function(v) { return v + " %" }
        valueFromText: function(t) { return parseInt(t) || 90 }
    }

    QQC2.CheckBox {
        id: notify7dCheck
        Kirigami.FormData.label: "7-day window:"
        text: "Notify when utilization crosses the threshold"
    }

    QQC2.SpinBox {
        id: notify7dSpin
        Kirigami.FormData.label: "7-day threshold (%):"
        from: 1
        to: 100
        value: 90
        enabled: notify7dCheck.checked
        textFromValue: function(v) { return v + " %" }
        valueFromText: function(t) { return parseInt(t) || 90 }
    }

    QQC2.CheckBox {
        id: notifyLimitCheck
        Kirigami.FormData.label: "Limit reached:"
        text: "Notify when a window is fully used (100% / LIMITED)"
    }

    // ── Service ───────────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Service status"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: notifyIncidentCheck
        Kirigami.FormData.label: "Incidents:"
        text: "Notify when a new Claude incident is reported"
    }

    QQC2.CheckBox {
        id: notifyMaintenanceCheck
        Kirigami.FormData.label: "Maintenance:"
        text: "Notify when scheduled maintenance is announced"
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        text: "Notifications use notify-send (libnotify) and fire once per crossing."
        opacity: 0.7
        font: Kirigami.Theme.smallFont
    }
}
