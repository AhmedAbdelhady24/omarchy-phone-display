import QtQuick
import QtQuick.Controls as Controls
import qs.Ui as Ui
import qs.Commons as Commons

Column {
    id: root
    required property var backend
    required property var hostWidget
    width: parent.width
    spacing: Commons.Style.space(12)
    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
    Repeater {
        model: [
            {title: "setupPackages", body: "setupPackagesBody"},
            {title: "setupAvnc", body: "setupAvncBody"},
            {title: "setupUsb", body: "setupUsbBody"},
            {title: "setupProfile", body: "setupProfileBody"},
            {title: "setupRotate", body: "setupRotateBody"},
            {title: "setupStart", body: "setupStartBody"}
        ]
        delegate: Column {
            required property var modelData
            required property int index
            width: root.width
            spacing: Commons.Style.space(4)
            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: strings.t(modelData.title)
                wrapMode: Text.WordWrap
                color: Commons.Color.foreground
                font.bold: true
                font.pixelSize: Commons.Style.font.body
            }
            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: strings.t(modelData.body)
                wrapMode: Text.WordWrap
                color: Commons.Color.foreground
                font.pixelSize: Commons.Style.font.bodySmall
            }
            TextEdit {
                visible: index === 0
                width: parent.width
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAnywhere
                text: "omarchy pkg add wayvnc android-tools jq iproute2 util-linux"
                color: Commons.Color.foreground
                font.family: "monospace"
                font.pixelSize: Commons.Style.font.bodySmall
            }
            Text {
                width: parent.width
                visible: index < 3 || index === 4
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: index === 0 ? (root.backend.setup.missing.length ? strings.t("packagesMissing").arg(root.backend.setup.missing.join(", ")) : strings.t("packagesReady"))
                    : index === 1 ? (!root.backend.setup.usb ? strings.t("avncUnknown") : root.backend.setup.avnc ? strings.t("avncReady") : strings.t("avncMissing"))
                    : index === 2 ? (root.backend.setup.usb ? strings.t("ready") : strings.t("disconnected"))
                    : root.backend.setup.autoRotate ? strings.t("rotationReady") : strings.t("rotationLocked")
                color: Commons.Color.foreground
                font.bold: true
                font.pixelSize: Commons.Style.font.bodySmall
            }
            Ui.Button {
                visible: index === 1
                text: strings.t("getAvnc")
                focusable: true
                onClicked: Qt.openUrlExternally("https://f-droid.org/packages/com.gaurav.avnc/")
            }
        }
    }
    Controls.CheckBox {
        width: parent.width
        text: strings.t("keepAwake")
        checked: root.hostWidget.settings.keepAwake !== false
        enabled: root.backend.setup.usb && !root.backend.busy
        palette.windowText: Commons.Color.foreground
        onClicked: {
            root.hostWidget.saveChoice("keepAwake", checked)
            root.hostWidget.runAction(checked ? "awake-on" : "awake-off")
        }
    }
    Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: strings.t("keepAwakeHint")
        color: Commons.Color.foreground
        font.pixelSize: Commons.Style.font.bodySmall
    }
    Row {
        spacing: Commons.Style.space(8)
        Ui.Button {
            text: strings.t("recheck")
            focusable: true
            enabled: !root.backend.checking
            onClicked: root.backend.inspect()
        }
        Ui.Button {
            text: strings.t("setupDone")
            focusable: true
            enabled: root.backend.setup.usb && root.backend.setup.avnc && !root.backend.setup.missing.length
            onClicked: root.hostWidget.saveChoice("setupComplete", true)
        }
    }
}
