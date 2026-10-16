pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import stage.modules.ii.background.widgets
import "../Singletons"

// One desktop widget kind for the whole vendored ii roster. The slot content
// Ryoku's WidgetSlot measures and frames: the face file resolves through the
// stage's widget registry by id and is created in preview mode, so the widget
// never places, drags, persists or menus itself -- Ryoku's WidgetSlot owns
// placement, lock, scale, backing and the right-click menu. The face keeps its
// own look: it reads its per-widget options (colours, formats, the Material
// shape knobs) straight from the stage config, the same store the Stage
// Editor's widget config pages edit.
Item {
    id: adapter

    property string faceId: "clock_cookie"
    property string prefix: "iiClockCookie"
    property var screen: null

    readonly property url faceUrl: WidgetsRegistry.getQmlPath(faceId)
    readonly property Component faceComp: Qt.createComponent(faceUrl)
    property Item faceItem: null

    implicitWidth: faceItem ? faceItem.implicitWidth : 240
    implicitHeight: faceItem ? faceItem.implicitHeight : 240

    readonly property int _screenW: adapter.screen ? adapter.screen.width : 1920
    readonly property int _screenH: adapter.screen ? adapter.screen.height : 1080

    // The component compiles synchronously; creating the object passes
    // isPreview as an initial value, so the widget never runs a frame in the
    // stage's placement mode.
    function create() {
        const comp = adapter.faceComp;
        if (comp === null || comp.status !== Component.Ready)
            return;
        if (adapter.faceItem !== null)
            adapter.faceItem.destroy();
        adapter.faceItem = comp.createObject(adapter, {
            "isPreview": true,
            "visible": true,
            "screenWidth": adapter._screenW,
            "screenHeight": adapter._screenH,
            "scaledScreenWidth": adapter._screenW,
            "scaledScreenHeight": adapter._screenH
        });
    }

    Component.onCompleted: create()

    Connections {
        target: adapter.faceComp
        enabled: adapter.faceComp !== null
        function onStatusChanged() { adapter.create(); }
    }
}
