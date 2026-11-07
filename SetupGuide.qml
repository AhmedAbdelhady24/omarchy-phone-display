import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons as Commons

Column {
    id: root
    required property var backend
    required property var hostWidget
    property int expandedStep: -1
    property bool userSelectedStep: false
    width: parent.width
    spacing: Commons.Style.space(8)
    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    function suggestStep() {
        if (userSelectedStep) return
        expandedStep = backend.setup.missing.length ? 0 : !backend.setup.usb ? 1
            : !backend.setup.avnc ? 2 : hostWidget.settings.setupComplete !== true ? 3 : -1
    }
    Component.onCompleted: suggestStep()
    Connections { target: root.backend; function onSetupChanged() { root.suggestStep() } }

    Repeater {
        model: [
            {title:"toolsShort",body:"setupPackagesBody",ready:!root.backend.setup.missing.length,status:root.backend.setup.missing.length?"missingShort":"installedShort"},
            {title:"usbShort",body:"setupUsbBody",ready:root.backend.setup.usb,status:root.backend.setup.usb?"authorizedShort":"connectShort"},
            {title:"avncShort",body:"setupAvncBody",ready:root.backend.setup.usb&&root.backend.setup.avnc,status:!root.backend.setup.usb?"connectShort":root.backend.setup.avnc?"installedShort":"avncMissingShort"},
            {title:"profileShort",body:"setupProfileBody",ready:null,status:"reviewShort"},
            {title:"rotationShort",body:"setupRotateBody",ready:root.backend.setup.autoRotate,status:root.backend.setup.autoRotate?"rotationOnShort":"rotationOffShort"}
        ]
        delegate: Rectangle {
            id: step
            required property var modelData
            required property int index
            readonly property bool expanded: root.expandedStep === index
            width: root.width
            height: cardContent.implicitHeight+Commons.Style.space(20)
            radius: Commons.Style.space(10)
            color: PhonePalette.surface
            border.color: expanded ? PhonePalette.border : PhonePalette.line
            Column {
                id: cardContent
                x: Commons.Style.space(12)
                y: Commons.Style.space(10)
                width: parent.width-Commons.Style.space(24)
                spacing: Commons.Style.space(10)
                Controls.AbstractButton {
                    width: parent.width
                    height: Commons.Style.space(38)
                    Accessible.name: strings.t(step.modelData.title)
                    onClicked: { root.userSelectedStep=true; root.expandedStep=step.expanded?-1:step.index }
                    background: Rectangle { color: "transparent" }
                    contentItem: RowLayout {
                        spacing: Commons.Style.space(10)
                        Rectangle {
                            Layout.preferredWidth: Commons.Style.space(24)
                            Layout.preferredHeight: width
                            radius: width/2
                            color: step.modelData.ready === true ? PhonePalette.accent : PhonePalette.elevated
                            Text {
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: step.modelData.ready === true ? "✓" : step.modelData.ready === false ? "!" : "i"
                                color: step.modelData.ready === true ? PhonePalette.ink : PhonePalette.muted
                                font.pixelSize: Commons.Style.font.body
                            }
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: Commons.Style.space(2)
                            Text {
                                width: parent.width
                                textFormat: Text.PlainText
                                text: strings.t(step.modelData.title)
                                color: PhonePalette.foreground
                                font.pixelSize: Commons.Style.font.body
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                textFormat: Text.PlainText
                                text: strings.t(step.modelData.status)
                                color: step.modelData.ready === true ? PhonePalette.accent : step.modelData.ready === false ? PhonePalette.danger : PhonePalette.muted
                                font.pixelSize: Commons.Style.font.bodySmall
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: step.expanded ? "⌄" : "›"
                            color: PhonePalette.muted
                            font.pixelSize: Commons.Style.font.body
                        }
                    }
                }
                Column {
                    width: parent.width
                    spacing: Commons.Style.space(10)
                    visible: step.expanded
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: strings.t(step.modelData.body)
                        wrapMode: Text.WordWrap
                        color: PhonePalette.muted
                        font.pixelSize: Commons.Style.font.bodySmall
                    }
                    TextEdit {
                        visible: step.index===0
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.WrapAnywhere
                        text: "omarchy pkg add wayvnc android-tools jq iproute2 util-linux"
                        color: PhonePalette.accent
                        font.family: "monospace"
                        font.pixelSize: Commons.Style.font.bodySmall
                    }
                    Text {
                        width: parent.width
                        visible: step.index===2 && root.backend.setup.usb && !root.backend.setup.avnc
                        textFormat: Text.PlainText
                        text: strings.t("avncMissing")
                        wrapMode: Text.WordWrap
                        color: PhonePalette.danger
                        font.pixelSize: Commons.Style.font.bodySmall
                    }
                    ActionButton {
                        visible: step.index===2
                        text: strings.t("getAvnc")
                        onClicked: Qt.openUrlExternally("https://f-droid.org/packages/com.gaurav.avnc/")
                    }
                }
            }
        }
    }
    Rectangle {
        width: root.width
        height: chargingContent.implicitHeight+Commons.Style.space(24)
        radius: Commons.Style.space(10)
        color: PhonePalette.surface
        border.color: PhonePalette.line
        Column {
            id: chargingContent
            x: Commons.Style.space(12)
            y: Commons.Style.space(12)
            width: parent.width-Commons.Style.space(24)
            spacing: Commons.Style.space(8)
            Controls.Switch {
                id: charging
                width: parent.width
                text: strings.t("keepAwake")
                checked: root.hostWidget.settings.keepAwake !== false
                enabled: root.backend.setup.usb && !root.backend.busy
                opacity: enabled ? 1 : 0.45
                onClicked: {
                    root.hostWidget.saveChoice("keepAwake",checked)
                    root.hostWidget.runAction(checked?"awake-on":"awake-off")
                }
                contentItem: Text {
                    textFormat: Text.PlainText
                    text: charging.text
                    color: PhonePalette.foreground
                    font.pixelSize: Commons.Style.font.body
                    verticalAlignment: Text.AlignVCenter
                    rightPadding: charging.indicator.width+Commons.Style.space(12)
                    elide: Text.ElideRight
                }
                indicator: Rectangle {
                    implicitWidth: Commons.Style.space(42)
                    implicitHeight: Commons.Style.space(24)
                    x: charging.width-width
                    y: (charging.height-height)/2
                    radius: height/2
                    color: charging.checked?PhonePalette.accent:PhonePalette.line
                    Rectangle {
                        x: charging.checked?parent.width-width-Commons.Style.space(3):Commons.Style.space(3)
                        y: Commons.Style.space(3)
                        width: Commons.Style.space(18)
                        height: width
                        radius: width/2
                        color: PhonePalette.ink
                        Behavior on x { NumberAnimation { duration: Commons.Style.duration(120); easing.type:Easing.OutCubic } }
                    }
                }
            }
            Text {
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: strings.t("chargingShortHint")
                color: PhonePalette.muted
                font.pixelSize: Commons.Style.font.bodySmall
            }
        }
    }
    Row {
        spacing: Commons.Style.space(8)
        ActionButton { text:strings.t("recheck"); enabled:!root.backend.checking; onClicked:root.backend.inspect() }
        ActionButton {
            text: strings.t("setupDone")
            primary: true
            enabled: root.backend.setup.usb && root.backend.setup.avnc && !root.backend.setup.missing.length
            onClicked: { root.hostWidget.saveChoice("setupComplete",true); root.userSelectedStep=true; root.expandedStep=-1 }
        }
    }
}
