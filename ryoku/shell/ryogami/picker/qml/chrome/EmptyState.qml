import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    required property PickerState state

    readonly property bool rices: root.state.collection === "rices"
    // Wallpaper facets never narrow rices or themes (LibraryView skips them there).
    readonly property bool filtered: {
        var v = root.state.view
        if (!v) return false
        if (v.query !== "" || v.tags.length > 0) return true
        if (v.collection !== "wallpapers" && v.collection !== "workshop") return false
        return v.typeFilter !== "" || v.hueFilter !== -1 || v.favouritesOnly
            || v.orientation !== "" || (v.folder !== "" && v.folder !== "*")
    }
    readonly property string message: {
        if (root.filtered)
            return I18n.tr("Nothing matches these filters.")
        switch (root.state.collection) {
        case "rices": return I18n.tr("No rices yet. Save this desktop as one, or import a rice someone shared.")
        case "workshop": return I18n.tr("No Wallpaper Engine scenes yet. Find some with Download, Steam Workshop.")
        case "themes": return I18n.tr("No themes installed.")
        }
        return I18n.tr("No wallpapers yet. Add some to your wallpaper folder or use Download.")
    }
    readonly property bool offerRices: root.rices && !root.filtered

    visible: !!root.state.view && root.state.view.count === 0

    // The picker has no backdrop of its own, so the message carries one to read on any wallpaper.
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(label.width, root.offerRices ? actions.width : 0) + 44 * Theme.scale
        height: label.implicitHeight + 26 * Theme.scale
            + (root.offerRices ? actions.height + 16 * Theme.scale : 0)
        radius: Theme.radius
        color: Theme.withAlpha(Theme.surfaceContainer, 0.92)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.4)

        Text {
            id: label
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 13 * Theme.scale
            width: Math.min(implicitWidth, Math.min(root.width - 124 * Theme.scale, 596 * Theme.scale))
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.message
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fs(16)
            color: Theme.surfaceText
            renderType: Text.NativeRendering
        }

        Row {
            id: actions
            visible: root.offerRices
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: label.bottom
            anchors.topMargin: 16 * Theme.scale
            spacing: 8 * Theme.scale
            FixedButton {
                mode: "action"
                glyph: "\u{f0193}"
                label: I18n.tr("Save look")
                active: true
                onTriggered: root.state.openRiceShare("save", null)
            }
            FixedButton {
                mode: "action"
                glyph: "\u{f02fa}"
                label: I18n.tr("Import a rice")
                onTriggered: root.state.openRiceShare("import", null)
            }
        }
    }
}
