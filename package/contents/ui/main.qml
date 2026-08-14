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
    property string defaultZone: ""

    // Services and ports are NOT polled: listing them goes through firewalld's
    // config.info polkit action, which is auth_admin_keep, so every poll would
    // raise a password dialog. They are fetched only when the user asks.
    property var services: []
    property var ports: []
    property bool detailsRequested: false
    property bool detailsLoading: false
    property bool detailsFailed: false
    property string detailsAt: ""

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

        // Every periodic query goes through here, which refuses anything that
        // would raise a polkit dialog. Kept as a hard guard rather than a
        // convention: one careless firewall-cmd added to the polling loop is
        // enough to make the widget ask for a password every ten seconds.
        function poll(cmd) {
            if (!ZoneLogic.isFreeQuery(cmd)) {
                console.warn("firewallzone: refusing to poll a privileged query:", cmd)
                return
            }
            run(cmd)
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
                    root.clearDetails()
                } else {
                    poll("firewall-cmd --get-zone-of-interface=" + root.iface)
                }
            } else if (source.indexOf("get-zone-of-interface") !== -1) {
                var previous = root.zoneState.zone
                root.zoneState = ZoneLogic.parseZone(stdout, stderr, code)
                if (!root.zoneState.ok || root.zoneState.zone !== previous)
                    root.clearDetails()
            } else if (source.indexOf("get-default-zone") !== -1) {
                root.defaultZone = stdout.trim()
            } else if (source.indexOf("--list-all") !== -1) {
                var details = ZoneLogic.parseListAll(stdout)
                root.detailsLoading = false
                if (details.ok) {
                    root.services = details.services
                    root.ports = details.ports
                    // A snapshot, not a live view: firewalld is only asked when
                    // the user asks, so say when the answer was taken.
                    root.detailsAt = Qt.formatTime(new Date(), "HH:mm")
                } else {
                    // Declined or failed authentication. Offer the button again
                    // rather than claim the zone has nothing open.
                    root.detailsRequested = false
                    root.detailsFailed = true
                }
            }
        }
    }

    function clearDetails() {
        services = []
        ports = []
        detailsRequested = false
        detailsLoading = false
        detailsFailed = false
        detailsAt = ""
    }

    // Explicit user action only. firewalld asks for a password here, which is
    // exactly why it is not part of the polling loop. A single --list-all is
    // deliberate: one query, one password prompt.
    function loadDetails() {
        if (!zoneState.ok || detailsLoading)
            return
        detailsRequested = true
        detailsLoading = true
        detailsFailed = false
        executable.run("firewall-cmd --zone=" + zoneState.zone + " --list-all")
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.run("ip -o route show default | awk '{print $5; exit}'")
    }

    Component.onCompleted: executable.poll("firewall-cmd --get-default-zone")

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

        // Plasma remembers a popup size per applet (popupHeight in
        // plasma-org.kde.plasma.desktop-appletsrc) and reuses it even after the
        // content has grown — the last button then falls outside the dialog and
        // is simply not there any more. A minimum tied to the content forbids
        // that: revealing the service list makes the popup grow instead.
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: content.implicitHeight

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
            // Width is imposed, height is left to the layout. Anchoring both
            // while fullRep.implicitHeight reads back content.implicitHeight
            // makes the two disagree: children get laid out past the bottom of
            // a popup that believes it is shorter, and the last one disappears.
            width: fullRep.width
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

            QQC2.Label {
                visible: root.defaultZone !== ""
                text: i18n("Default zone: %1", root.defaultZone)
                color: Kirigami.Theme.disabledTextColor
                Layout.fillWidth: true
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // Asking firewalld for services and ports triggers a polkit prompt,
            // so it stays behind an explicit click and says so.
            ThemedButton {
                visible: root.zoneState.ok && !root.detailsRequested
                text: i18n("Show open services…")
                icon.name: "view-list-details"
                Layout.fillWidth: true
                onClicked: root.loadDetails()
                PlasmaComponents.ToolTip {
                    text: i18n("firewalld requires authentication to list services, so this asks for your password")
                }
            }

            QQC2.Label {
                visible: root.detailsFailed
                text: i18n("Not authenticated — services stay hidden")
                color: Kirigami.Theme.neutralTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight
            }

            QQC2.Label {
                visible: root.detailsLoading
                text: i18n("Waiting for authentication…")
                color: Kirigami.Theme.disabledTextColor
                Layout.fillWidth: true
            }

            QQC2.Label {
                visible: root.detailsRequested && !root.detailsLoading
                text: root.services.length > 0
                    ? i18n("Open services: %1", root.services.join(", "))
                    : i18n("Open services: none")
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                // Without this the layout sizes the label as a single line and
                // the popup ends up shorter than its own content.
                Layout.preferredHeight: contentHeight
            }

            QQC2.Label {
                visible: root.detailsRequested && !root.detailsLoading
                text: root.ports.length > 0
                    ? i18n("Open ports: %1", root.ports.join(", "))
                    : i18n("Open ports: none")
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                // Without this the layout sizes the label as a single line and
                // the popup ends up shorter than its own content.
                Layout.preferredHeight: contentHeight
            }

            RowLayout {
                visible: root.detailsRequested && !root.detailsLoading
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: i18n("Read at %1", root.detailsAt)
                    color: Kirigami.Theme.disabledTextColor
                    font: Kirigami.Theme.smallFont
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                ThemedButton {
                    text: i18n("Refresh")
                    icon.name: "view-refresh"
                    onClicked: root.loadDetails()
                    PlasmaComponents.ToolTip {
                        text: i18n("Ask firewalld again. Adding a service or a port elsewhere is not seen until you do.")
                    }
                }
            }

            ThemedButton {
                text: i18n("Open firewall settings")
                icon.name: "configure"
                Layout.fillWidth: true
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
