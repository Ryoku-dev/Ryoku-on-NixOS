import QtQuick
import Qt5Compat.GraphicalEffects
import stage.modules.common

DropShadow {
    required property var target
    source: target
    x: source?.x ?? 0
    y: source?.y ?? 0
    width: source?.width ?? 0
    height: source?.height ?? 0
    radius: 8
    samples: radius * 2 + 1
    color: Appearance.colors.colShadow
    transparentBorder: true
    visible: opacity > 0 && !Config.options.appearance.transparency.popups && !Config.options.appearance.transparency.enable
}
