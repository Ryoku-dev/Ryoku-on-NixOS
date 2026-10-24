pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import "Singletons"
import Ryoku.Ui.Singletons

// A small grid of quick-action tiles for the desktop menu -- the iRiS menu's
// quick row in Ryoku's paper-and-ink language, laid out calm. Each item is a
// plain object { icon, label, image?, accent?, action }: a Material glyph over
// its name, a bone plate when it is the primary action (inversion, never a
// tint), or a wallpaper thumbnail under a scrim. Every tile is sized to the
// widest label at the tile type, so a name never clips at any font scale or
// language, and the grid wraps to `columns` so the card stays a calm width.
// Clicking runs the action and dismisses the enclosing menu.
Item {
    id: quick

    property var items: []
    property int columns: 2
    // Roomy: the glyph sits over its name with air above and below.
    property real tileHeight: Theme.s7 + Theme.s2

    width: parent ? parent.width : 0
    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    readonly property int count: quick.items ? quick.items.length : 0

    // Uniform tile width: the widest label measured at the tile's own type, plus
    // padding, so every tile fits its name whole -- no elide, no clip.
    FontMetrics { id: fm; font.family: Theme.font; font.pixelSize: Theme.fSmall }
    readonly property real labelMax: {
        var m = 0;
        for (var i = 0; i < quick.count; i++)
            m = Math.max(m, fm.advanceWidth(I18n.tr(quick.items[i].label || "")));
        return m;
    }
    readonly property real tileW: Math.max(Theme.s7 + Theme.s3, Math.ceil(quick.labelMax) + Theme.s3 * 2)

    // find the enclosing DesktopMenu so a fired tile can dismiss it.
    function closeMenu() {
        var p = quick.parent;
        while (p) {
            if (p.ryoMenu === true) {
                p.close();
                return;
            }
            p = p.parent;
        }
    }

    Grid {
        id: grid
        anchors.horizontalCenter: parent.horizontalCenter
        columns: quick.columns
        rowSpacing: Theme.s1
        columnSpacing: Theme.s1

        Repeater {
            model: quick.items

            delegate: Item {
                id: tile
                required property var modelData
                required property int index

                readonly property bool accent: tile.modelData.accent === true
                readonly property string image: String(tile.modelData.image ?? "")
                readonly property bool hasImage: tile.image.length > 0 && img.status === Image.Ready
                readonly property color face: tile.accent ? Theme.inkOnBone
                    : tile.hasImage ? Theme.bone
                    : (ma.containsMouse ? Theme.ink : Theme.inkDim)

                width: quick.tileW
                height: quick.tileHeight

                scale: ma.pressed ? 0.97 : 1
                Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

                ClippingRectangle {
                    id: plate
                    anchors.fill: parent
                    radius: Theme.menuTileRadius
                    color: tile.accent ? Theme.bone
                        : ma.pressed ? Theme.tilePress
                        : ma.containsMouse ? Theme.tileHover : Theme.tile
                    Behavior on color { ColorAnimation { duration: Theme.quick } }

                    Image {
                        id: img
                        anchors.fill: parent
                        visible: tile.image.length > 0
                        source: tile.image.length > 0 ? "file://" + tile.image.replace(/^file:\/\//, "") : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: Math.round(quick.tileW * 2)
                        asynchronous: true
                        cache: false
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: tile.hasImage
                        color: Qt.rgba(0, 0, 0, 0.42)
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.menuTileRadius
                    color: "transparent"
                    border.width: 1
                    border.color: tile.accent ? Theme.bone : Theme.line
                }

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.s1
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.modelData.icon ?? ""
                        color: tile.face
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fBody + 4
                        Behavior on color { ColorAnimation { duration: Theme.quick } }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr(tile.modelData.label ?? "")
                        color: tile.face
                        font.family: Theme.font
                        font.pixelSize: Theme.fSmall
                        font.weight: Font.Medium
                        Behavior on color { ColorAnimation { duration: Theme.quick } }
                    }
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (tile.modelData.action)
                            tile.modelData.action();
                        quick.closeMenu();
                    }
                }
            }
        }
    }
}
