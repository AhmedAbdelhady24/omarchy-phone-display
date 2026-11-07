import QtQuick
import qs.Commons as Commons
import "Layout.js" as Layout

Rectangle {
    id: root
    required property var settings
    required property var backend
    property var monitors: Layout.validMonitors(backend.setup.monitors)
    property var phone: Layout.phoneSize(settings, backend.setup.nativeSize, backend.active ? backend.resolution : "", backend.setup.phoneOrientation)
    readonly property string shownPlacement: {
        var current=(backend.setup.monitors || []).filter(function(m) { return m.name === "PHONE-DISPLAY" })[0]
        return backend.active && current ? current.x+"x"+current.y : settings.placement || "right-of"
    }
    property var scene: Layout.scene(monitors, phone, shownPlacement)
    property var frozenScene: scene
    property bool dragging: false
    readonly property var view: dragging ? frozenScene : scene
    readonly property real factor: Math.min((width-36)/Math.max(view.width,1), (height-36)/Math.max(view.height,1))
    readonly property real originX: (width-view.width*factor)/2
    readonly property real originY: (height-view.height*factor)/2
    signal placed(string position)
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true
    height: Commons.Style.space(200)
    color: Commons.Color.background
    radius: Commons.Style.cornerRadius
    border.color: Commons.Color.foreground
    border.width: 1
    clip: true
    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
    Repeater {
        model: root.monitors
        delegate: Rectangle {
            required property var modelData
            x: root.originX+(modelData.x-root.view.x)*root.factor
            y: root.originY+(modelData.y-root.view.y)*root.factor
            width: modelData.width*root.factor
            height: modelData.height*root.factor
            color: Qt.rgba(0.5,0.5,0.5,0.15)
            border.color: Commons.Color.foreground
            radius: 3
            Text {
                anchors.centerIn: parent
                width: parent.width-8
                textFormat: Text.PlainText
                text: modelData.name
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                color: Commons.Color.foreground
                font.pixelSize: Commons.Style.font.bodySmall
            }
        }
    }
    Rectangle {
        id: phoneCard
        objectName: "phoneCard"
        x: root.originX+(root.view.phone.x-root.view.x)*root.factor
        y: root.originY+(root.view.phone.y-root.view.y)*root.factor
        width: root.phone.width*root.factor
        height: root.phone.height*root.factor
        color: Commons.Color.accent
        radius: 3
        border.color: Commons.Color.foreground
        focus: true
        activeFocusOnTab: true
        Accessible.name: strings.t("phoneDrag")
        Keys.onPressed: function(event) {
            var m = root.monitors[0]
            if (!m || !root.enabled) return
            var p = root.view.phone
            if (event.key === Qt.Key_Left) p={x:m.x-root.phone.width,y:m.y}
            else if (event.key === Qt.Key_Right) p={x:m.x+m.width,y:m.y}
            else if (event.key === Qt.Key_Up) p={x:m.x,y:m.y-root.phone.height}
            else if (event.key === Qt.Key_Down) p={x:m.x,y:m.y+m.height}
            else return
            var target=Layout.snap(root.monitors,root.phone,p.x,p.y)
            root.placed(target.x+"x"+target.y)
            event.accepted=true
        }
        Text {
            anchors.centerIn: parent
            width: parent.width-6
            textFormat: Text.PlainText
            text: strings.t("phone")
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: Commons.Color.background
            font.pixelSize: Commons.Style.font.bodySmall
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            enabled: root.monitors.length > 0 && !root.backend.busy
            property point pressPoint
            property point cardPoint
            onPressed: function(mouse) {
                pressPoint=mapToItem(root,mouse.x,mouse.y)
                cardPoint=Qt.point(phoneCard.x,phoneCard.y)
                root.frozenScene=root.scene
                root.dragging=true
                phoneCard.forceActiveFocus()
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                var p=mapToItem(root,mouse.x,mouse.y)
                phoneCard.x=cardPoint.x+p.x-pressPoint.x
                phoneCard.y=cardPoint.y+p.y-pressPoint.y
            }
            function restoreBindings() {
                root.dragging=false
                phoneCard.x=Qt.binding(function() { return root.originX+(root.view.phone.x-root.view.x)*root.factor })
                phoneCard.y=Qt.binding(function() { return root.originY+(root.view.phone.y-root.view.y)*root.factor })
            }
            onReleased: {
                var p=Layout.snap(root.monitors,root.phone,root.view.x+(phoneCard.x-root.originX)/root.factor,root.view.y+(phoneCard.y-root.originY)/root.factor)
                root.placed(p.x+"x"+p.y)
                restoreBindings()
            }
            onCanceled: restoreBindings()
        }
    }
}
