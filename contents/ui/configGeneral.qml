import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_showTitle: showTitleCheck.checked
    property bool cfg_showTitleDefault: true

    property alias cfg_refreshInterval: refreshSpinBox.value
    property int cfg_refreshIntervalDefault: 1

    property string cfg_proxyMode: "env"
    property string cfg_proxyModeDefault: "env"

    property alias cfg_proxyUrl: proxyUrlField.text
    property string cfg_proxyUrlDefault: ""

    // ── Appearance ────────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Appearance"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showTitleCheck
        Kirigami.FormData.label: "Show title:"
        text: "Show the \"Claude Limits\" heading in the popup"
    }

    // ── Limits refresh ────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Rate-limit refresh"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: refreshSpinBox
        Kirigami.FormData.label: "Interval (minutes):"
        from: 1
        to: 120
        value: 1
        textFromValue: function(v) { return v + " min" }
        valueFromText: function(t) { return parseInt(t) || 1 }
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        text: "Free: each refresh is a plain read of Claude Code's usage "
              + "endpoint — no tokens.\nThe reset countdown ticks locally "
              + "every second between refreshes."
        opacity: 0.7
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
    }

    // ── Proxy ─────────────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Proxy"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.ComboBox {
        id: proxyCombo
        Kirigami.FormData.label: "Mode:"
        model: ["No proxy", "System env (HTTP_PROXY)", "Custom URL"]
        currentIndex: {
            var idx = ["none", "env", "custom"].indexOf(cfg_proxyMode)
            return idx >= 0 ? idx : 1
        }
        onActivated: cfg_proxyMode = ["none", "env", "custom"][currentIndex]
    }

    QQC2.TextField {
        id: proxyUrlField
        Kirigami.FormData.label: "Proxy URL:"
        placeholderText: "http://proxy.example.com:8080"
        visible: cfg_proxyMode === "custom"
    }
}
