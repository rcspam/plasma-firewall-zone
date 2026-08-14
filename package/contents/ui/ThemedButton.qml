// A button that actually paints its icon and label inside a plasmoid popup.
//
// Plasma's QQC2 style leaves Button.contentItem null in this context, so a
// plain QQC2.Button renders as an empty frame: the text is set, nothing shows.
// PlasmaComponents.Button is not the answer either — it is styled for the panel
// and stays dark on a light popup. Hence an explicit contentItem and background.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.Button {
    id: control

    // Never take keyboard focus: a stray space or return reaching a freshly
    // opened popup must not trigger anything.
    focusPolicy: Qt.NoFocus

    leftPadding: Kirigami.Units.smallSpacing * 2
    rightPadding: Kirigami.Units.smallSpacing * 2
    topPadding: Kirigami.Units.smallSpacing
    bottomPadding: Kirigami.Units.smallSpacing

    background: Rectangle {
        radius: 3
        readonly property color hl: Kirigami.Theme.highlightColor
        color: control.pressed ? Qt.rgba(hl.r, hl.g, hl.b, 0.55)
             : control.hovered ? Qt.rgba(hl.r, hl.g, hl.b, 0.22)
             : Kirigami.Theme.alternateBackgroundColor
        border.width: 1
        border.color: control.hovered ? Kirigami.Theme.highlightColor
                                      : Kirigami.Theme.disabledTextColor
        opacity: control.enabled ? 1.0 : 0.55
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: control.icon.name
            visible: source !== ""
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            color: Kirigami.Theme.textColor
        }
        QQC2.Label {
            text: control.text
            color: Kirigami.Theme.textColor
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
