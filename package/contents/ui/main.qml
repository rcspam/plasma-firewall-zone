// Firewall Zone — panel indicator for the active firewalld zone.
// Read-only by design: every command it runs works as an unprivileged user.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import "ZoneLogic.js" as ZoneLogic

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    // Popups inherit the panel colour set (usually dark). On a light global
    // theme that makes the popup unreadable. Force the View set instead.
    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false

    property var zoneState: ({ ok: false, zone: "", error: "unknown" })
    property string iface: ""
    property var services: []
    property var ports: []

    // The executable engine caches sources by their exact string, so re-running
    // the same command silently does nothing. A unique prefix forces a fresh run.
    property int tick: 0

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        function run(cmd) {
            connectSource("env _=" + (root.tick++) + " " + cmd)
        }

        onNewData: function(source, data) {
            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""
            var code = data["exit code"]
            disconnectSource(source)

            if (source.indexOf("route show default") !== -1) {
                root.iface = stdout.trim()
                if (root.iface.length === 0) {
                    root.zoneState = { ok: false, zone: "", error: "offline" }
                    root.services = []
                    root.ports = []
                } else {
                    run("firewall-cmd --get-zone-of-interface=" + root.iface)
                }
            } else if (source.indexOf("get-zone-of-interface") !== -1) {
                root.zoneState = ZoneLogic.parseZone(stdout, stderr, code)
                if (root.zoneState.ok) {
                    run("firewall-cmd --zone=" + root.zoneState.zone + " --list-services")
                    run("firewall-cmd --zone=" + root.zoneState.zone + " --list-ports")
                } else {
                    root.services = []
                    root.ports = []
                }
            } else if (source.indexOf("--list-services") !== -1) {
                root.services = ZoneLogic.parseList(stdout)
            } else if (source.indexOf("--list-ports") !== -1) {
                root.ports = ZoneLogic.parseList(stdout)
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.run("ip -o route show default | awk '{print $5; exit}'")
    }

    compactRepresentation: MouseArea {
        property bool wasExpanded: false
        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        Kirigami.Icon {
            anchors.fill: parent
            source: ZoneLogic.iconFor(root.zoneState)
        }
    }

    fullRepresentation: Item {
        id: fullRep
        // Both forms are needed: Plasma sizes the popup from the Layout
        // attached properties, the dialog itself from the implicit size.
        implicitWidth: Kirigami.Units.gridUnit * 18
        implicitHeight: content.implicitHeight
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

        // Repeated here, not only on the root item: the popup is built in its
        // own window, so the attached property set on PlasmoidItem does not
        // reach it. Background and text then come from the same colour set,
        // which is what keeps the popup readable under any global theme.
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        // The popup's real background is painted by Plasma's SVG theme and is
        // always panel-coloured. Cover it with a theme-aware rectangle. It sits
        // outside the layout on purpose: an anchored child of a ColumnLayout is
        // undefined behaviour, so the layout lives in a sibling item instead.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -Kirigami.Units.largeSpacing
            z: -1
            color: Kirigami.Theme.backgroundColor
            radius: Kirigami.Units.largeSpacing * 1.5
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: ZoneLogic.iconFor(root.zoneState)
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                QQC2.Label {
                    text: root.zoneState.ok
                        ? i18n("Zone: %1", root.zoneState.zone)
                        : ZoneLogic.errorText(root.zoneState.error)
                    font.bold: true
                    color: Kirigami.Theme.textColor
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            QQC2.Label {
                visible: root.zoneState.ok
                text: i18n("Interface: %1", root.iface)
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
            }

            Kirigami.Separator { Layout.fillWidth: true }

            QQC2.Label {
                visible: root.zoneState.ok
                text: root.services.length > 0
                    ? i18n("Open services: %1", root.services.join(", "))
                    : i18n("Open services: none")
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
            }

            QQC2.Label {
                visible: root.zoneState.ok
                text: root.ports.length > 0
                    ? i18n("Open ports: %1", root.ports.join(", "))
                    : i18n("Open ports: none")
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
            }

            Item { Layout.fillHeight: true }

            QQC2.Button {
                text: i18n("Open firewall settings")
                icon.name: "configure"
                Layout.fillWidth: true
                // Never take keyboard focus: a stray space or return reaching
                // the freshly opened popup would otherwise launch a privileged
                // configuration tool behind the user's back.
                focusPolicy: Qt.NoFocus
                onClicked: {
                    // Detach: the executable engine only reports back when the
                    // process exits, so a foreground GUI would keep the source
                    // connected for as long as its window stays open.
                    executable.run("firewall-config >/dev/null 2>&1 &")
                    root.expanded = false
                }
                PlasmaComponents.ToolTip {
                    text: i18n("Launches firewall-config, which will ask for your password")
                }
            }
        }
    }

    toolTipMainText: root.zoneState.ok
        ? i18n("Firewall zone: %1", root.zoneState.zone)
        : i18n("Firewall Zone")
    toolTipSubText: root.zoneState.ok
        ? i18n("Interface: %1", root.iface)
        : ZoneLogic.errorText(root.zoneState.error)
}
