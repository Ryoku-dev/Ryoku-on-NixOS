import QtQuick
import Quickshell
import Quickshell.Widgets
import inir.services

// An app icon from a theme name or an absolute path, falling back to a generic
// icon when neither resolves. Drawn with Quickshell's own icon provider: the
// Kirigami icon the reference used is a KDE library Ryoku does not ship, and a
// box without it could not load any surface that shows an app icon.
Item {
    id: root

    property string icon: ""
    property string fallback: "application-x-executable"
    property int iconSize: 24
    property alias implicitSize: root.iconSize

    implicitWidth: iconSize
    implicitHeight: iconSize

    readonly property string resolvedSource: AppSearch.resolveIcon(root.icon, root.fallback)
    property bool _failed: false
    onResolvedSourceChanged: root._failed = false

    IconImage {
        anchors.fill: parent
        implicitSize: root.iconSize
        mipmap: true
        source: root._failed ? Quickshell.iconPath(root.fallback, "") : root.resolvedSource
        onStatusChanged: if (status === Image.Error && !root._failed) root._failed = true
    }
}
