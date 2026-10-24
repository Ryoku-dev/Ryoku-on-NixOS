import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    required property PickerState state
    property var args: root.state ? root.state.sheetArgs : ({})
    property bool shown: false

    signal closeRequested()

    anchors.fill: parent
    focus: root.shown

    property real _reveal: shown ? 1 : 0
    Behavior on _reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }
    visible: _reveal > 0.001

    property string inspectedBackend: ""
    property string defaultBackend: ""
    property var backends: []
    property var previews: []
    property bool loading: false
    property string error: ""

    // Settings is read by method, not a notifying property, so this stamp re-runs those bindings.
    property int _settingsRev: 0
    Connections {
        target: Settings
        function onChanged(key, value) { root._settingsRev++ }
    }

    readonly property var _applyKeys: ["theme.staticTheme"]

    readonly property var _backendLabels: ({ "ryoku": I18n.tr("Ryoku") })
    function backendLabel(b) {
        var l = root._backendLabels[b]
        return (l !== undefined) ? l : String(b)
    }

    readonly property string appliedBackend: root.defaultBackend

    function isPreviewActive(p) {
        root._settingsRev
        if (!p || p.backend !== root.appliedBackend || !Settings.ready)
            return false
        if (String(Settings.value("theme.policy")) !== "fixed")
            return false
        var cur = Settings.value(p.key)
        return cur !== undefined && cur !== null && String(cur) === String(p.value)
    }

    readonly property real _scale: Theme.scale
    readonly property bool compact: root.width < 760 * root._scale
    readonly property int columns: root.compact ? 2 : 3
    readonly property real cardW: (root.compact ? 174 : 202) * root._scale
    readonly property real gridGap: 12 * root._scale
    readonly property real innerWidth: root.columns * root.cardW + (root.columns - 1) * root.gridGap
    readonly property real pad: 18 * root._scale

    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
    readonly property int _rows: root.previews.length > 0 ? Math.ceil(root.previews.length / root.columns) : 0
    readonly property real _contentHeight: root._rows > 0 ? root._rows * 123 * root._scale + (root._rows - 1) * root.gridGap : 0
    readonly property real _gridCap: root._clamp(root.height - 280 * root._scale, 220 * root._scale, 520 * root._scale)
    readonly property real gridHeight: Math.min(root._contentHeight, root._gridCap)

    function loadPreviews() {
        root.loading = true
        root.error = ""
        root.previews = []
        var reqBackend = root.inspectedBackend
        Daemon.call("theme.previews", { backend: reqBackend }, function(res, err) {
            if (!root.shown)
                return
            root.loading = false
            if (err) {
                root.error = err.message || I18n.tr("No colour previews were returned. Check that the selected colour source is installed and working.")
                return
            }
            if (res && res.backends)
                root.backends = res.backends
            if (res && res.backend) {
                root.inspectedBackend = res.backend
                if (root.defaultBackend === "")
                    root.defaultBackend = res.backend
            }
            if (!res || !res.previews || res.previews.length === 0) {
                root.error = I18n.tr("No colour previews were returned. Check that the selected colour source is installed and working.")
                return
            }
            root.previews = res.previews
        })
    }

    function inspectBackend(b) {
        if (root.inspectedBackend === b)
            return
        root.inspectedBackend = b
        root.previews = []
        root.loadPreviews()
    }

    function applyPreview(p) {
        if (!p)
            return
        if (root._applyKeys.indexOf(p.key) < 0) {
            root.state.toast(I18n.tr("That colour profile cannot be applied."), "error")
            return
        }
        // The daemon retints on the static-theme write, so there is no separate retheme call.
        Settings.set("theme.policy", "fixed")
        Settings.set(p.key, p.value)
    }

    onShownChanged: {
        if (root.shown) {
            root.error = ""
            root.defaultBackend = ""
            root.inspectedBackend = ""
            root.loadPreviews()
        } else {
            root.previews = []
            root.error = ""
            root.loading = false
        }
    }

    Scrim {
        anchors.fill: parent
        alpha: 0.58
        reveal: root._reveal
        onDismissed: root.closeRequested()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: root.innerWidth + 2 * root.pad
        height: layout.implicitHeight + 2 * root.pad
        color: Theme.withAlpha(Theme.surface, 0.98)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.55)
        radius: Theme.radius
        opacity: root._reveal
        scale: 0.985 + 0.015 * root._reveal

        // Swallows presses so they never reach the scrim.
        MouseArea { anchors.fill: parent }

        Column {
            id: layout
            x: root.pad
            y: root.pad
            width: root.innerWidth
            spacing: 14 * root._scale

            Item {
                width: parent.width
                height: Math.max(headingText.implicitHeight, closeAction.height)

                Column {
                    id: headingText
                    anchors.left: parent.left
                    anchors.right: closeAction.left
                    anchors.rightMargin: 13 * root._scale
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * root._scale

                    Text {
                        width: parent.width
                        text: I18n.tr("Colour preview")
                        font.family: Theme.display
                        font.pixelSize: Theme.fontLead
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("Choose a colour source, then compare its profiles using the same wallpaper.")
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontSmall
                        color: Theme.withAlpha(Theme.surfaceText, 0.62)
                        renderType: Text.NativeRendering
                        wrapMode: Text.WordWrap
                    }
                }

                FolioAction {
                    id: closeAction
                    anchors.right: parent.right
                    anchors.top: parent.top
                    label: "\u00d7"
                    minWidth: 30
                    onTriggered: root.closeRequested()
                }
            }

            Column {
                width: parent.width
                spacing: 7 * root._scale

                Text {
                    text: I18n.tr("Colour source")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontFine
                    color: Theme.withAlpha(Theme.surfaceText, 0.58)
                    renderType: Text.NativeRendering
                }

                Flow {
                    width: parent.width
                    spacing: 7 * root._scale

                    Repeater {
                        model: root.backends
                        delegate: Rectangle {
                            id: srcButton
                            required property var modelData
                            readonly property bool inspected: modelData === root.inspectedBackend
                            readonly property bool appliedOn: modelData === root.appliedBackend
                            readonly property bool hovered: srcArea.containsMouse

                            implicitHeight: 26 * root._scale
                            implicitWidth: srcLabel.implicitWidth + 24 * root._scale
                            radius: Theme.radius
                            color: srcButton.inspected ? Theme.surfaceText
                                : srcButton.hovered ? Theme.withAlpha(Theme.surfaceText, 0.09)
                                : Theme.withAlpha(Theme.surfaceText, 0.05)
                            border.width: srcButton.inspected ? 2 : 1
                            border.color: srcButton.inspected ? "transparent"
                                : srcButton.hovered ? Theme.withAlpha(Theme.surfaceText, 0.24)
                                : Theme.withAlpha(Theme.outline, 0.4)
                            Behavior on color { ColorAnimation { duration: Theme.fast } }
                            Behavior on border.color { ColorAnimation { duration: Theme.fast } }

                            Text {
                                id: srcLabel
                                anchors.centerIn: parent
                                text: srcButton.appliedOn
                                    ? I18n.tr("%1 · on").arg(root.backendLabel(srcButton.modelData))
                                    : root.backendLabel(srcButton.modelData)
                                font.family: Theme.sans
                                font.weight: srcButton.inspected ? Font.DemiBold : Font.Medium
                                font.pixelSize: Theme.fontSmall
                                color: srcButton.inspected ? Theme.surface : Theme.surfaceText
                                renderType: Text.NativeRendering
                            }

                            MouseArea {
                                id: srcArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.inspectBackend(srcButton.modelData)
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.loading
                text: I18n.tr("Generating previews from the current wallpaper…")
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBody
                color: Theme.withAlpha(Theme.surfaceText, 0.66)
                renderType: Text.NativeRendering
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                visible: !root.loading && root.error !== ""
                text: root.error
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBody
                color: Theme.tertiary
                renderType: Text.NativeRendering
                wrapMode: Text.WordWrap
            }

            Flickable {
                width: parent.width
                height: root.gridHeight
                visible: !root.loading && root.error === "" && root.previews.length > 0
                contentHeight: grid.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Grid {
                    id: grid
                    columns: root.columns
                    columnSpacing: root.gridGap
                    rowSpacing: root.gridGap

                    Repeater {
                        model: root.previews
                        delegate: ThemeAuditionCard {
                            required property var modelData
                            cardWidth: root.cardW
                            preview: modelData
                            active: root.isPreviewActive(modelData)
                            onPicked: root.applyPreview(modelData)
                        }
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: root.closeRequested()
}
