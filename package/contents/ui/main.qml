// Firewall Zone — panel indicator for the active firewalld zone.
// Read-only by design: every command it runs works as an unprivileged user.
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import "ZoneLogic.js" as ZoneLogic

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

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

    toolTipMainText: root.zoneState.ok
        ? i18n("Firewall zone: %1", root.zoneState.zone)
        : i18n("Firewall Zone")
    toolTipSubText: root.zoneState.ok
        ? i18n("Interface: %1", root.iface)
        : ZoneLogic.errorText(root.zoneState.error)
}
