import QtQuick
import QtQuick.Layouts
import stage.modules.common.widgets
import ".."

RippleButton {
    id: root

    property real buttonSize: Appearance.sizes.dockButtonSize
    // Owned by DockContent's delegate wrapper. Specialized buttons only
    // consume this already-animated value.
    property real dockMagnificationScale: {
        let item = parent;
        for (let depth = 0; item && depth < 6; depth++) {
            if (typeof item._magnificationScale !== "undefined")
                return item._magnificationScale;
            item = item.parent;
        }
        return 1.0;
    }

    width: buttonSize
    height: buttonSize
    buttonRadius: Appearance.rounding.normal
    background.implicitWidth: buttonSize
    background.implicitHeight: buttonSize
    padding: 0

    rippleEnabled: false
    colBackground: "transparent"
    colBackgroundHover: "transparent"
    colBackgroundToggled: "transparent"
    colBackgroundToggledHover: "transparent"
}
