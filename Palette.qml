pragma Singleton
import QtQuick
import qs.Commons as Commons
import "Colors.js" as Colors

QtObject {
    id: root
    readonly property color accent: Commons.Color.accent
    readonly property color background: Qt.rgba(Commons.Color.popups.background.r,Commons.Color.popups.background.g,Commons.Color.popups.background.b,1)
    readonly property color foreground: Commons.Color.popups.text
    readonly property color surface: tint(accent,0.035)
    readonly property color elevated: tint(accent,0.12)
    readonly property color field: tint(foreground,0.025)
    readonly property color muted: tint(foreground,0.74)
    readonly property color ink: Colors.inkFor(accent)
    readonly property color border: tint(accent,0.65)
    readonly property color line: tint(foreground,0.18)
    readonly property color danger: Colors.contrast(Commons.Color.urgent,background)>=4.5?Commons.Color.urgent:foreground
    function tint(color,amount) { return Qt.tint(background,Qt.rgba(color.r,color.g,color.b,amount)) }
}
