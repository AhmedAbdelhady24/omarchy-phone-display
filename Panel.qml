import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Ui as Ui
import qs.Commons as Commons

Ui.Panel {
    id: root
    moduleName: "user.phone-display"
    manageIpc: false
    required property var backend
    required property var anchorItem
    required property var hostWidget
    property bool showSetup: hostWidget.settings.setupComplete !== true
    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
    onOpenedChanged: {
        backend.openViews += opened ? 1 : -1
        if (opened) backend.inspect()
    }
    Component.onDestruction: { if (opened) backend.openViews = Math.max(0, backend.openViews-1) }

    Ui.KeyboardPanel {
        id: panel
        bar: root.bar
        anchorItem: root.anchorItem
        owner: root.hostWidget
        open: root.opened
        borderSpec: Commons.Border.flat(PhonePalette.border, 1)
        contentWidth: fittedContentWidth(Commons.Style.space(460))
        contentHeight: fittedContentHeight(loadedContentHeight, Commons.Style.space(780))
        focusTarget: loadedContent
        content: FocusScope {
            implicitHeight: body.implicitHeight
            anchors.fill: parent
            Keys.onEscapePressed: root.close()
            Rectangle {
                anchors.fill: parent
                anchors.margins: -panel.padding
                color: PhonePalette.background
                radius: Commons.Style.cornerRadius
                z: -1
            }
            Controls.ScrollView {
                id: scroll
                anchors.fill: parent
                clip: true
                contentWidth: availableWidth
                Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                Column {
                    id: body
                    width: scroll.availableWidth
                    spacing: Commons.Style.space(12)
                    RowLayout {
                        width: parent.width
                        spacing: Commons.Style.space(10)
                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: strings.t("title")
                            color: PhonePalette.foreground
                            font.family: Commons.Style.font.family
                            font.pixelSize: Commons.Style.font.body
                            font.bold: true
                        }
                        Rectangle {
                            implicitWidth: badge.implicitWidth+Commons.Style.space(18)
                            implicitHeight: Commons.Style.space(26)
                            radius: height/2
                            color: PhonePalette.elevated
                            border.color: root.backend.adbConnected?PhonePalette.border:PhonePalette.line
                            Text {
                                id: badge
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: root.backend.adbConnected?strings.t("connectedBadge"):strings.t("disconnectedBadge")
                                color: root.backend.adbConnected?PhonePalette.accent:PhonePalette.muted
                                font.pixelSize: Commons.Style.font.bodySmall
                            }
                        }
                    }
                    Row {
                        spacing: Commons.Style.space(8)
                        ActionButton { text: strings.t("displayTab"); emphasized: !root.showSetup; focusable: true; onClicked: root.showSetup=false }
                        ActionButton { text: strings.t("setupTab"); emphasized: root.showSetup; focusable: true; onClicked: root.showSetup=true }
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        text: root.backend.busy ? strings.t("working") : root.backend.active ? strings.t("streaming").arg(root.backend.resolution)
                            : root.backend.setup.usb && !root.backend.setup.avnc ? strings.t("avncMissing")
                            : root.backend.adbConnected ? strings.t("ready") : strings.t("disconnected")
                        color: PhonePalette.foreground
                        font.pixelSize: Commons.Style.font.body
                    }
                    Text {
                        width: parent.width
                        visible: root.showSetup
                        textFormat: Text.PlainText
                        text: strings.t("setupSubtitle")
                        wrapMode: Text.WordWrap
                        color: PhonePalette.muted
                        font.pixelSize: Commons.Style.font.bodySmall
                    }
                    SetupGuide { width: body.width; visible: root.showSetup; backend: root.backend; hostWidget: root.hostWidget }
                    Column {
                        visible: !root.showSetup
                        width: parent.width
                        spacing: Commons.Style.space(10)
                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: strings.t("dragHint")
                            wrapMode: Text.WordWrap
                            color: PhonePalette.foreground
                            font.pixelSize: Commons.Style.font.bodySmall
                        }
                        DisplayLayout {
                            id: layoutEditor
                            width: parent.width
                            settings: root.hostWidget.settings
                            backend: root.backend
                            enabled: !root.backend.busy
                            onPlaced: function(position) {
                                root.hostWidget.saveChoice("placement",position)
                                if (root.backend.active) root.hostWidget.runAction("configure")
                            }
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: strings.t("currentPosition").arg(layoutEditor.shownPlacement)
                            color: PhonePalette.foreground
                            font.pixelSize: Commons.Style.font.bodySmall
                        }
                        Repeater {
                            model: [
                                {key:"orientation",label:"orientation",values:["auto","portrait","landscape"],fallback:"auto"},
                                {key:"resolution",label:"resolution",values:["native","1080x2340","1080x2400","1080x1920","720x1600","720x1280"],fallback:"native"},
                                {key:"refreshRate",label:"refresh",values:["60","90","120"],fallback:"60"},
                                {key:"scale",label:"scale",values:["1","1.25","1.5","2"],fallback:"1.5"}
                            ]
                            delegate: Column {
                                required property var modelData
                                width: body.width
                                spacing: Commons.Style.space(4)
                                Text {
                                    textFormat: Text.PlainText
                                    text: strings.t(modelData.label)
                                    color: PhonePalette.foreground
                                    font.pixelSize: Commons.Style.font.bodySmall
                                }
                                Choice {
                                    id: choice
                                    width: parent.width
                                    enabled: !root.backend.busy && (modelData.key === "orientation" || !root.backend.active)
                                    model: {
                                        if (modelData.key !== "scale") return modelData.values
                                        var resolution=root.hostWidget.settings.resolution || "native"
                                        var size=(resolution === "native" ? root.backend.setup.nativeSize || "1080x2400" : resolution).split("x")
                                        return modelData.values.filter(function(s) { return Number(size[0])/Number(s)%1 === 0 && Number(size[1])/Number(s)%1 === 0 })
                                    }
                                    currentIndex: Math.max(0,model.indexOf(String(root.hostWidget.settings[modelData.key] || modelData.fallback)))
                                    onActivated: {
                                        root.hostWidget.saveChoice(modelData.key,model[currentIndex])
                                        if (modelData.key === "orientation" && root.backend.active) root.hostWidget.runAction("configure")
                                    }
                                    labelFor: function(value) {
                                        if (modelData.key === "orientation") return strings.t(String(value))
                                        if (value === "native") return strings.t("nativeResolution").arg(root.backend.setup.nativeSize || "…")
                                        return modelData.key === "refreshRate"?value+" Hz":String(value)
                                    }
                                }
                            }
                        }
                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: strings.t("rotationHint")
                            wrapMode: Text.WordWrap
                            color: PhonePalette.foreground
                            font.pixelSize: Commons.Style.font.bodySmall
                        }
                    }
                    Text {
                        width: parent.width
                        visible: root.backend.error !== ""
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        text: root.backend.error
                        color: PhonePalette.danger
                        font.pixelSize: Commons.Style.font.bodySmall
                    }
                    Row {
                        spacing: Commons.Style.space(10)
                        ActionButton {
                            text: root.backend.active ? strings.t("stop") : strings.t("start")
                            primary: !root.backend.active
                            focusable: true
                            enabled: !root.backend.busy && (root.backend.active || root.backend.setup.usb && root.backend.setup.avnc && !root.backend.setup.missing.length)
                            onClicked: root.hostWidget.runAction("toggle")
                        }
                        ActionButton { text: strings.t("cleanup"); focusable: true; enabled: !root.backend.busy; onClicked: root.hostWidget.runAction("stop") }
                    }
                }
            }
        }
    }
}
