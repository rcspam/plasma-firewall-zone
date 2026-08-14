// Colour settings for the panel icon.
//
// Root is a plain Item, not KCM.SimpleKCM: Plasma injects the cfg_* properties
// into the root element, and SimpleKCM does not always receive them.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

Item {
    id: page

    property alias cfg_colorTrusted: trustedButton.color
    property alias cfg_colorClosed: closedButton.color
    property alias cfg_colorDown: downButton.color
    property alias cfg_colorOffline: offlineButton.color

    // Plasma injects a cfg_<name>Default property per config entry. Without
    // these stubs it complains that the page has no such property.
    property color cfg_colorTrustedDefault
    property color cfg_colorClosedDefault
    property color cfg_colorDownDefault
    property color cfg_colorOfflineDefault

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        Kirigami.FormLayout {
            Layout.fillWidth: true

            KQuickControls.ColorButton {
                id: trustedButton
                Kirigami.FormData.label: i18n("Trusted zone:")
                dialogTitle: i18n("Colour for a trusted zone")
            }
            QQC2.Label {
                text: i18n("home, internal, work, trusted")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }

            KQuickControls.ColorButton {
                id: closedButton
                Kirigami.FormData.label: i18n("Closed zone:")
                dialogTitle: i18n("Colour for a closed zone")
            }
            QQC2.Label {
                text: i18n("public, external, dmz, block, drop, and any unknown zone")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }

            KQuickControls.ColorButton {
                id: downButton
                Kirigami.FormData.label: i18n("Firewall stopped:")
                dialogTitle: i18n("Colour when firewalld is not running")
            }

            KQuickControls.ColorButton {
                id: offlineButton
                Kirigami.FormData.label: i18n("Offline:")
                dialogTitle: i18n("Colour when there is no network connection")
            }
        }

        QQC2.Button {
            text: i18n("Restore defaults")
            icon.name: "edit-undo"
            Layout.alignment: Qt.AlignLeft
            onClicked: {
                trustedButton.color = "#27ae60"
                closedButton.color = "#f39c12"
                downButton.color = "#c0392b"
                offlineButton.color = "#7f8c8d"
            }
        }

        Item { Layout.fillHeight: true }
    }
}
