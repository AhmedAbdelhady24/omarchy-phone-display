pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property bool active: false
    property bool adbConnected: false
    property string resolution: ""
    property string error: ""
    property int openViews: 0
    property var setup: ({missing: [], usb: false, avnc: false, nativeSize: "", autoRotate: false, monitors: []})
    property var requester: null
    readonly property bool busy: operation.running
    readonly property bool checking: inspection.running
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("phone-display.sh").toString().replace(/^file:\/\//, ""))
    readonly property string runtime: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/" + Quickshell.env("UID"))
        + "/omarchy-phone-display-" + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "no-session").replace(/[^a-zA-Z0-9_.-]/g, "_")

    function refresh() { if (!status.running) status.running = true }
    function inspect() { if (!usbEvents.running) usbEvents.running = true; if (!inspection.running) inspection.running = true; refresh() }
    function run(action, settings, owner) {
        if (busy) return
        requester = owner || null
        error = ""
        var size = String(settings.resolution || "native").split("x")
        if (size[0] === "native") size = ["native", "native"]
        if (action === "awake-on" || action === "awake-off") {
            operation.command = ["bash", script, "awake", action === "awake-on" ? "on" : "off"]
        } else {
            operation.command = ["bash", script, action, size[0], size[1],
                String(settings.placement || "right-of"), String(settings.scale || "1.5"),
                String(settings.refreshRate || "60"), String(settings.orientation || "auto"),
                settings.keepAwake === false ? "false" : "true"]
        }
        operation.running = true
    }

    Component.onCompleted: inspect()
    FileView {
        path: root.runtime + "/state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); root.refresh(); if (root.openViews > 0) root.inspect() }
        onLoadFailed: root.refresh()
    }
    Process {
        id: usbEvents
        // One event subscription for the entire shell, shared by every bar.
        command: ["adb", "track-devices"]
        running: true
        stdout: SplitParser { onRead: deviceDebounce.restart() }
        stderr: StdioCollector { }
        onExited: root.refresh()
    }
    Timer { id: deviceDebounce; interval: 250; onTriggered: root.inspect() }
    Timer {
        interval: 5000
        repeat: true
        running: root.openViews > 0
        onTriggered: root.inspect()
    }
    Process {
        id: status
        command: ["bash", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    root.active = data.active === true
                    root.adbConnected = data.adb_connected === true
                    root.resolution = String(data.resolution || "").slice(0, 40)
                } catch (e) { root.active = false; root.adbConnected = false }
            }
        }
        onExited: function(code) { if (code !== 0) { root.active = false; root.adbConnected = false } }
    }
    Process {
        id: inspection
        command: ["bash", root.script, "inspect"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (text.length > 65536) return
                    var data = JSON.parse(text)
                    if (Array.isArray(data.monitors) && data.monitors.length <= 32 && Array.isArray(data.missing)) root.setup = data
                } catch (e) { }
            }
        }
        stderr: StdioCollector { }
    }
    Process {
        id: operation
        stdout: StdioCollector { }
        stderr: StdioCollector { id: diagnostic }
        onExited: function(code) {
            if (code !== 0) {
                root.error = String(diagnostic.text || "Phone display operation failed.").slice(0, 1800)
                if (root.requester) root.requester.open()
            }
            root.requester = null
            root.inspect()
        }
    }
}
