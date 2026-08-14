// Firewall Zone — panel indicator for the active firewalld zone.
// Read-only by design: every command it runs works as an unprivileged user.
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Panel widget: without this, plasmoidviewer renders both representations at once.
    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        property bool wasExpanded: false
        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        Kirigami.Icon {
            anchors.fill: parent
            source: "security-high"
        }
    }

    toolTipMainText: i18n("Firewall Zone")
    toolTipSubText: i18n("Not wired up yet")
}
