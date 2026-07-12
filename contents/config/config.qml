import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "General"
        icon: "configure"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: "Components"
        icon: "view-list-details"
        source: "configComponents.qml"
    }
    ConfigCategory {
        name: "Notifications"
        icon: "preferences-desktop-notification"
        source: "configNotifications.qml"
    }
}
