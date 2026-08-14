// A titled list that stays folded until asked for.
//
// The popup is meant to be read at a glance, so the counts live in the header
// and the entries themselves only appear on demand. An empty section is not
// clickable: there is nothing to unfold, and its header says so.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: section

    property string title: ""
    property var items: []
    property bool expanded: false

    readonly property bool empty: !items || items.length === 0

    spacing: 0

    MouseArea {
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight
        cursorShape: section.empty ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !section.empty
        onClicked: section.expanded = !section.expanded

        RowLayout {
            id: header
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: section.expanded ? "arrow-down" : "arrow-right"
                visible: !section.empty
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            QQC2.Label {
                text: section.empty ? i18n("%1: none", section.title)
                                    : i18n("%1 (%2)", section.title, section.items.length)
                font.bold: !section.empty
                color: section.empty ? Kirigami.Theme.disabledTextColor
                                     : Kirigami.Theme.textColor
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    // Hidden children are ignored by the layout, so folding shrinks the popup.
    ColumnLayout {
        visible: section.expanded && !section.empty
        Layout.fillWidth: true
        spacing: 0

        Repeater {
            model: section.items
            QQC2.Label {
                text: modelData
                color: Kirigami.Theme.textColor
                elide: Text.ElideRight
                Layout.leftMargin: Kirigami.Units.gridUnit
                Layout.fillWidth: true
            }
        }
    }
}
