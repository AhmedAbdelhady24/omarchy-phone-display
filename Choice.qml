import QtQuick
import QtQuick.Controls as Controls
import qs.Commons as Commons

Controls.ComboBox {
    id: root
    property var labelFor: function(value) { return String(value) }
    implicitHeight: Commons.Style.space(38)
    leftPadding: Commons.Style.space(12)
    rightPadding: Commons.Style.space(30)
    opacity: enabled ? 1 : 0.45
    displayText: labelFor(currentText)
    background: Rectangle {
        color: PhonePalette.field
        radius: Commons.Style.space(8)
        border.color: root.activeFocus || root.hovered ? PhonePalette.accent : PhonePalette.line
    }
    contentItem: Text {
        textFormat: Text.PlainText
        text: root.displayText
        color: PhonePalette.foreground
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: root.width-width-Commons.Style.space(12)
        y: (root.height-height)/2
        textFormat: Text.PlainText
        text: "⌄"
        color: PhonePalette.accent
    }
    delegate: Controls.ItemDelegate {
        required property var modelData
        required property int index
        width: root.width-Commons.Style.space(8)
        implicitHeight: Commons.Style.space(36)
        highlighted: root.highlightedIndex === index
        contentItem: Text {
            textFormat: Text.PlainText
            text: root.labelFor(modelData)
            color: highlighted ? PhonePalette.ink : PhonePalette.foreground
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: Commons.Style.space(6)
            color: highlighted ? PhonePalette.accent : PhonePalette.surface
        }
    }
    popup: Controls.Popup {
        y: root.height+Commons.Style.space(4)
        width: root.width
        padding: Commons.Style.space(4)
        implicitHeight: contentItem.implicitHeight+padding*2
        contentItem: ListView {
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            clip: true
        }
        background: Rectangle {
            color: PhonePalette.surface
            radius: Commons.Style.space(9)
            border.color: PhonePalette.border
        }
    }
}
