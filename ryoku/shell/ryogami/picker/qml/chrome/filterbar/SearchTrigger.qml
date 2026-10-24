import QtQuick
import Ryoku.Ui.Singletons

// The search line in the masthead: it reads like a field and opens the search panel,
// which owns tag and describe search. A running query shows here with a way to clear it.
Item {
    id: st

    required property PickerState state
    readonly property LibraryView view: st.state ? st.state.view : null
    readonly property string query: st.view && st.view.query ? String(st.view.query) : ""
    readonly property int tagCount: st.view && st.view.tags ? st.view.tags.length : 0
    // A finished describe search has no query text; it lives on as an explicit key ordering.
    readonly property bool described: !!(st.view && st.view.keyOrder && st.view.keyOrder.length > 0)
    readonly property bool active: st.query !== "" || st.tagCount > 0 || st.described
    readonly property bool engaged: (st.state && st.state.searchOpen) || st.active
    readonly property bool hovered: mouse.containsMouse

    implicitHeight: 34 * Theme.scale

    Text {
        id: lens
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{f0349}"
        font.family: Theme.icon
        font.pixelSize: Theme.fs(15)
        color: Theme.withAlpha(Theme.surfaceText, st.engaged || st.hovered ? 1 : 0.55)
        rotation: st.hovered ? -12 : 0
        renderType: Text.NativeRendering
        Behavior on rotation { NumberAnimation { duration: Theme.standard; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    Text {
        anchors.left: lens.right
        anchors.leftMargin: 10 * Theme.scale
        anchors.right: clear.visible ? clear.left : parent.right
        anchors.rightMargin: 8 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: st.query !== "" ? st.query
            : st.tagCount > 0 ? I18n.tr("%1 tags chosen").arg(st.tagCount)
            : st.described ? I18n.tr("Described")
            : I18n.tr("Search by tag, or describe it")
        font.family: Theme.sans
        font.pixelSize: Theme.fs(13)
        color: st.active ? Theme.surfaceText
             : Theme.withAlpha(Theme.surfaceText, st.hovered ? 0.7 : 0.45)
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    // The rule under the line brightens and fills from the left while search is in play.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.withAlpha(Theme.surfaceText, 0.22)
    }
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: 1.5 * Theme.scale
        width: st.engaged ? parent.width : st.hovered ? parent.width * 0.35 : 0
        color: Theme.surfaceText
        Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onClicked: if (st.state) st.state.searchOpen = !st.state.searchOpen
    }

    BarButton {
        id: clear
        visible: st.active
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: "\u{f0156}"
        tooltip: I18n.tr("Clear search")
        hpad: 6
        onTriggered: {
            if (!st.view) return
            st.view.query = ""
            st.view.tags = []
            st.view.keyOrder = []
        }
    }
}
