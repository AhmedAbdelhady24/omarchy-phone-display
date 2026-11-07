import QtQuick
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
        contentWidth: fittedContentWidth(Commons.Style.space(460))
        contentHeight: fittedContentHeight(loadedContentHeight, Commons.Style.space(780))
        focusTarget: loadedContent
        content: FocusScope {
            implicitHeight: body.implicitHeight
            anchors.fill: parent
            Keys.onEscapePressed: root.close()
            Controls.ScrollView {
                anchors.fill: parent
                clip: true
                contentWidth: availableWidth
                Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                Column {
                    id: body
                    width: parent.width
                    spacing: Commons.Style.space(12)
                    Text {
                        textFormat: Text.PlainText
                        text: strings.t("title")
                        color: Commons.Color.foreground
                        font.family: Commons.Style.font.family
                        font.pixelSize: Commons.Style.font.title
                    }
                    Row {
                        spacing: Commons.Style.space(8)
                        Ui.Button { text: strings.t("displayTab"); selected: !root.showSetup; focusable: true; onClicked: root.showSetup=false }
                        Ui.Button { text: strings.t("setupTab"); selected: root.showSetup; focusable: true; onClicked: root.showSetup=true }
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        text: root.backend.busy ? strings.t("working") : root.backend.active ? strings.t("streaming").arg(root.backend.resolution)
                            : root.backend.setup.usb && !root.backend.setup.avnc ? strings.t("avncMissing")
                            : root.backend.adbConnected ? strings.t("ready") : strings.t("disconnected")
                        color: Commons.Color.foreground
                        font.pixelSize: Commons.Style.font.body
                    }
                    SetupGuide { visible: root.showSetup; backend: root.backend; hostWidget: root.hostWidget }
                    Column {
                        visible: !root.showSetup
                        width: parent.width
                        spacing: Commons.Style.space(10)
                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: strings.t("dragHint")
                            wrapMode: Text.WordWrap
                            color: Commons.Color.foreground
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
                            color: Commons.Color.foreground
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
                                    color: Commons.Color.foreground
                                    font.pixelSize: Commons.Style.font.bodySmall
                                }
                                Controls.ComboBox {
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
                                    displayText: modelData.key === "orientation" ? strings.t(currentText)
                                        : currentText === "native" ? strings.t("nativeResolution").arg(root.backend.setup.nativeSize || "…")
                                        : modelData.key === "refreshRate" ? currentText+" Hz" : currentText
                                    palette.text: Commons.Color.foreground
                                    palette.buttonText: Commons.Color.foreground
                                    palette.button: Commons.Color.background
                                    palette.base: Commons.Color.background
                                    palette.highlight: Commons.Color.accent
                                }
                            }
                        }
                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: strings.t("rotationHint")
                            wrapMode: Text.WordWrap
                            color: Commons.Color.foreground
                            font.pixelSize: Commons.Style.font.bodySmall
                        }
                    }
                    Text {
                        width: parent.width
                        visible: root.backend.error !== ""
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        text: root.backend.error
                        color: Commons.Color.foreground
                        font.pixelSize: Commons.Style.font.bodySmall
                    }
                    Row {
                        spacing: Commons.Style.space(10)
                        Ui.Button {
                            text: root.backend.active ? strings.t("stop") : strings.t("start")
                            focusable: true
                            enabled: !root.backend.busy && (root.backend.active || root.backend.setup.usb && root.backend.setup.avnc && !root.backend.setup.missing.length)
                            onClicked: root.hostWidget.runAction("toggle")
                        }
                        Ui.Button { text: strings.t("cleanup"); focusable: true; enabled: !root.backend.busy; onClicked: root.hostWidget.runAction("stop") }
                    }
                }
            }
        }
    }
}
