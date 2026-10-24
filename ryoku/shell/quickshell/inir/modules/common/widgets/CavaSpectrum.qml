pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Blobs
import inir.modules.common
import inir.services

CavaSpectrumPainter {
    id: root

    property bool active: false

    spectrumColor: Appearance.colors.colPrimary
    spectrumColors: CavaTheme.visualizerColors
    mirroredStereo: Config.options?.appearance?.cava?.stereo ?? true

    visible: (root.points?.length ?? 0) > 0 && (root.active || root.opacity > 0.001)
    opacity: root.active ? Math.max(0, Math.min(1, root.spectrumOpacity)) : 0

    Behavior on opacity {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: Appearance.calcEffectiveDuration(root.active ? 180 : 480)
            easing.type: root.active ? Easing.OutCubic : Easing.InOutCubic
        }
    }
}
