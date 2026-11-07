import QtQuick
import qs.Ui as Ui
import qs.Commons as Commons

Ui.Button {
    id: root
    property bool primary: false
    property bool emphasized: false
    foreground: emphasized || primary ? PhonePalette.ink : PhonePalette.foreground
    accent: PhonePalette.accent
    background: PhonePalette.surface
    color: emphasized || primary ? (hot ? Qt.lighter(PhonePalette.accent, 1.06) : PhonePalette.accent)
        : hot ? PhonePalette.elevated : PhonePalette.surface
    borderSpec: Commons.Border.flat(activeFocus ? PhonePalette.accent : emphasized || primary ? PhonePalette.accent : PhonePalette.line, activeFocus ? 2 : 1)
    radius: Commons.Style.space(8)
    horizontalPadding: Commons.Style.space(14)
    verticalPadding: Commons.Style.space(9)
    opacity: enabled ? 1 : 0.45
    focusable: true
}
