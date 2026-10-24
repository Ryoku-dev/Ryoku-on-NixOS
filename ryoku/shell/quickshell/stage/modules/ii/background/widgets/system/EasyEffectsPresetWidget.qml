import QtQuick
import Ryoku.Ui.Singletons
import stage
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.ii.background.widgets
import stage.modules.ii.easyEffects
import stage.modules.ii.easyEffects.tabs

/**
 * The EasyEffects app's preset hero on the desktop: the same card (texture, shape, name,
 * chain, buttons), standing (portrait) or lying (landscape). The buttons work: "Edit
 * effects" opens EasyEffects, while "Bypass" switches the effects off or on.
 *
 * Both shapes use the shared EasyEffects widget options, matching the app's preset hero.
 */
AbstractBackgroundWidget {
    id: root

    /// Lying on its side: art left, the rest beside it.
    property bool landscape: false
    property bool wallpaperSafetyTriggered: false

    readonly property var options: Config.options.easyEffects.widget

    configEntryName: root.landscape ? "easyeffects_preset_landscape" : "easyeffects_preset_portrait"
    implicitWidth: root.landscape ? 720 : 360
    implicitHeight: root.landscape ? 320 : 640

    // Pause the shader while an application covers this widget's active workspace.
    readonly property var shownWorkspaces: {
        const output = root.monitorName || Wm.focusedOutput || "";
        return (Wm.workspaces ?? [])
            .filter(workspace => workspace.active === true
                && (output === "" || workspace.output === output))
            .map(workspace => String(workspace.id));
    }
    readonly property bool covered: !root.isPreview && (root.options.pauseOnWindows ?? true)
        && (Wm.windows ?? []).some(window => root.shownWorkspaces.includes(String(window.workspace))
            && (!window.toplevel || window.toplevel.minimized !== true))

    readonly property string holdKey: `presetWidget:${root.widgetInstance?.id ?? (root.landscape ? "landscape" : "portrait")}:${root.isPreview ? "preview" : "desktop"}`

    Component.onCompleted: EasyEffects.hold(root.holdKey, true)
    Component.onDestruction: EasyEffects.hold(root.holdKey, false)

    EasyEffectsEditor {
        id: editor
        pipeline: root.options.pipeline === "input" ? "input" : "output"
    }

    StyledDropShadow {
        target: hero
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    PresetHero {
        id: hero
        anchors.fill: parent
        editor: editor
        landscape: root.landscape

        showTopography: root.options.topography ?? true
        topographyReactive: root.options.topographyReactive ?? true
        topographyPaused: root.covered
        topographyStrength: (root.options.topographyStrength ?? 100) / 100
        art: root.options.art ?? "shape"
        showDevice: root.options.showDevice ?? true
        showState: root.options.showState ?? true
        showDefault: root.options.showDefault ?? true
        showWave: root.options.showWave ?? true
        showCaption: root.options.showCaption ?? true
        showName: root.options.showName ?? true
        showEffects: root.options.showEffects ?? true
        showButtons: root.options.showButtons ?? true

        onEditRequested: EasyEffects.openNativeWindow()
    }
}
