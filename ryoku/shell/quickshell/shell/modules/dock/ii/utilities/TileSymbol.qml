import QtQuick
import stage.modules.common.widgets
import ".."

/**
 * A Material Symbol on a dock tile. MaterialSymbol rasterises natively at its
 * base size and the lens would stretch that bitmap; curve rendering stays
 * sharp at any scale and keeps the FILL axis (see the dock icons).
 */
MaterialSymbol {
    renderType: Text.CurveRendering
}
