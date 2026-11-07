import QtQuick
import qs.Ui as Ui
import qs.Commons as Commons

Ui.BarWidget {
    id: root
    moduleName: "user.phone-display"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    readonly property bool opened: popup.opened
    property bool popoutSwitchClosing: false
    Component.onCompleted: PhoneState.inspect()

    function open() { popup.open() }
    function close() { popup.close() }
    function toggle() { popup.toggle() }
    function closeForPopoutSwitch() {
        popoutSwitchClosing = true
        close()
        Qt.callLater(function() { root.popoutSwitchClosing = false })
    }
    function runAction(action) { PhoneState.run(action, root.settings, root) }
    function saveChoice(key, value) {
        var next = Object.assign({}, root.settings)
        next[key] = value
        if (key === "resolution") {
            var size = (value === "native" ? PhoneState.setup.nativeSize || "1080x2400" : value).split("x")
            var scale = Number(next.scale || "1.5")
            if (Number(size[0]) / scale % 1 || Number(size[1]) / scale % 1) next.scale = "1"
        }
        if (root.bar && root.bar.shell && root.bar.shell.updateEntryInline(root.moduleName, next)) {
            root.settings = next
        } else {
            PhoneState.error = strings.t("saveFailed")
        }
    }

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
    Panel {
        id: popup
        bar: root.bar
        hostWidget: root
        anchorItem: button
        backend: PhoneState
    }
    Ui.BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: PhoneState.busy ? "󰦖" : PhoneState.active ? "󰄜" : PhoneState.adbConnected ? "󰄛" : "󰄞"
        active: PhoneState.active
        opacity: PhoneState.adbConnected || PhoneState.active ? 1 : 0.45
        // Only static translated strings enter the shell-owned tooltip.
        tooltipText: PhoneState.busy ? strings.t("working") : PhoneState.active ? strings.t("activeTooltip")
            : PhoneState.adbConnected ? strings.t("readyTooltip") : strings.t("disconnectedTooltip")
        onPressed: function(mouseButton) {
            if (mouseButton === Qt.RightButton) root.toggle()
            else if (mouseButton === Qt.LeftButton) root.runAction("toggle")
        }
    }
}
