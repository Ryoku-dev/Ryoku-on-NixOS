import QtQuick
import Quickshell
import "../"

// The style's popout layer: its OSD pills, the tray hover menu host and the
// side music pill. Serpantinum's desktop right-click menu is not ported: the
// Ryoku wallpaper menu owns that edge.
Item {
    id: root

    Osd {}
    TrayBase {}
    SideMusicPopout {}
    DockAppMenu {}
}
