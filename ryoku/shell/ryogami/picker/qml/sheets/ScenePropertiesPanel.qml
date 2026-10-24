import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    required property PickerState state
    property var args
    property bool shown: false

    signal closeRequested()

    anchors.fill: parent
    focus: root.shown

    // Resolved through the library entry: weId is not a view role.
    readonly property int _row: (args && args.row !== undefined && args.row !== null) ? Number(args.row) : -1
    readonly property var _entry: {
        if (root._row < 0 || !root.state || !root.state.view || !root.state.view.get)
            return null
        var v = root.state.view.get(root._row)
        if (!v || !v.key)
            return null
        return Library.entry(root.state.view.collection, v.key)
    }
    readonly property string weId: (args && args.weId) ? String(args.weId)
        : (root._entry && root._entry.weId) ? String(root._entry.weId) : ""
    readonly property string sceneTitle: (args && args.title) ? String(args.title)
        : (root._entry && (root._entry.title || root._entry.name)) ? String(root._entry.title || root._entry.name)
        : I18n.tr("Scene")

    property bool loading: true
    property string errorText: ""
    property var rows: []
    property var fpsValue: null            // null == follow the global default
    property int globalFps: 0
    property bool globalFpsKnown: false
    property var pending: ({})              // name -> optimistic encoded value
    property var inflight: ({})             // name -> unacknowledged write count
    property var fpsPending: undefined
    property int fpsInflight: 0
    property string _loadedId: ""
    property int seedRevision: 0

    property real _reveal: shown ? 1 : 0
    Behavior on _reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }
    visible: _reveal > 0.001

    Component.onCompleted: root._maybeFetch()
    onWeIdChanged: root._maybeFetch()
    onShownChanged: if (root.shown) root._maybeFetch()

    function _maybeFetch() {
        if (root.weId !== "" && root.weId !== root._loadedId)
            root._fetch()
    }

    function _fetch() {
        root._loadedId = root.weId
        root.loading = true
        root.errorText = ""
        var forId = root.weId
        Daemon.call("workshop.properties", { weId: forId }, function(result, error) {
            if (root.weId !== forId)
                return
            if (error) {
                root.loading = false
                root.errorText = (error && error.message) ? error.message
                    : I18n.tr("The scene's properties could not be read.")
                return
            }
            root._accept(result)
        })
    }

    function _accept(result) {
        root.loading = false
        root.errorText = ""

        var g = result ? result.globalFps : undefined
        root.globalFpsKnown = (typeof g === "number")
        root.globalFps = root.globalFpsKnown ? g : 0

        if (root.fpsInflight > 0 && root.fpsPending !== undefined) {
            root.fpsValue = root.fpsPending
        } else {
            root.fpsPending = undefined
            root.fpsValue = (result && typeof result.fps === "number") ? result.fps : null
        }

        var incoming = (result && result.properties) ? result.properties.slice() : []
        incoming.sort(function(a, b) { return (a.order || 0) - (b.order || 0) })
        var keep = ({})
        for (var i = 0; i < incoming.length; i++) {
            var nm = incoming[i].name
            if (root.inflight[nm] > 0 && root.pending[nm] !== undefined) {
                incoming[i].value = root.pending[nm]
                keep[nm] = root.pending[nm]
            }
        }
        root.pending = keep
        root.rows = incoming
        // The Repeater keeps delegates for value-equal rows, so a row whose local
        // edit was reset on the daemon side must be told to re-read its value.
        root.seedRevision++
    }

    function _writeProperty(name, value) {
        var p = {}
        for (var k in root.pending) p[k] = root.pending[k]
        p[name] = value
        root.pending = p

        var f = {}
        for (var k2 in root.inflight) f[k2] = root.inflight[k2]
        f[name] = (f[name] || 0) + 1
        root.inflight = f

        Daemon.call("workshop.setProperty", { weId: root.weId, name: name, value: value }, function(res, err) {
            var g = {}
            for (var k3 in root.inflight) g[k3] = root.inflight[k3]
            g[name] = Math.max(0, (g[name] || 1) - 1)
            root.inflight = g
            if (err && root.state)
                root.state.toast((err && err.message) ? err.message : I18n.tr("That change could not be applied."), "error")
        })
    }

    function _setFps(v) {           // v: null or a whole number
        root.fpsValue = v
        root.fpsPending = v
        root.fpsInflight = root.fpsInflight + 1
        Daemon.call("workshop.setProperty", { weId: root.weId, fps: v }, function(res, err) {
            root.fpsInflight = Math.max(0, root.fpsInflight - 1)
            if (err && root.state)
                root.state.toast((err && err.message) ? err.message : I18n.tr("The frame rate could not be changed."), "error")
        })
    }

    function _restoreDefaults() {
        root.pending = ({})
        root.inflight = ({})
        root.fpsPending = undefined
        root.fpsInflight = 0
        Daemon.call("workshop.setProperty", { weId: root.weId, reset: true }, function(res, err) {
            if (err) {
                if (root.state)
                    root.state.toast((err && err.message) ? err.message : I18n.tr("Defaults could not be restored."), "error")
                return
            }
            root._fetch()
        })
    }

    function _shownRows() {
        var out = []
        var rs = root.rows
        for (var i = 0; i < rs.length; i++)
            if (rs[i].condition !== false)
                out.push(rs[i])
        return out
    }
    function _isEditable(r) {
        return r.kind === "bool" || r.kind === "slider" || r.kind === "combo" || r.kind === "color"
    }
    function _effective(r) {
        return (root.pending[r.name] !== undefined) ? root.pending[r.name] : r.value
    }
    function _colNorm(s) {
        var parts = String(s === undefined || s === null ? "" : s).trim().split(/\s+/)
        function f(x) { var n = parseFloat(x); return isFinite(n) ? Math.max(0, Math.min(1, n)).toFixed(3) : "0.000" }
        return f(parts[0]) + " " + f(parts[1]) + " " + f(parts[2])
    }
    function _rowDiffers(r) {
        var v = root._effective(r)
        if (r.kind === "slider")
            return Math.abs(Number(v) - Number(r.default)) > 1e-9
        if (r.kind === "color")
            return root._colNorm(v) !== root._colNorm(r.default)
        return v !== r.default
    }
    function _editableCount() {
        var c = 0
        var s = root._shownRows()
        for (var i = 0; i < s.length; i++)
            if (root._isEditable(s[i])) c++
        return c + (root.globalFpsKnown ? 1 : 0)
    }
    function _changedCount() {
        var c = 0
        var s = root._shownRows()
        for (var i = 0; i < s.length; i++)
            if (root._isEditable(s[i]) && root._rowDiffers(s[i])) c++
        return c + ((root.fpsValue !== null) ? 1 : 0)
    }
    function _anyChanged() {
        var s = root._shownRows()
        for (var i = 0; i < s.length; i++)
            if (root._isEditable(s[i]) && root._rowDiffers(s[i])) return true
        return false
    }
    function _noteText() {
        return I18n.tr("%1 adjustable, %2 changed").arg(root._editableCount()).arg(root._changedCount())
    }
    readonly property bool _resetEnabled: (root.fpsValue !== null) || root._anyChanged()

    FolioSheet {
        id: sheet
        reveal: root._reveal
        onDismissed: root.closeRequested()

        FolioMasthead {
            parent: sheet.mastheadArea
            anchors.fill: parent
            reveal: root._reveal
            breadcrumb: I18n.tr("Wallpaper  /  Scene  /  Properties")
            onCloseRequested: root.closeRequested()
        }

        FolioIndexShell {
            id: indexShell
            parent: sheet.indexArea
            anchors.fill: parent
            title: root.sceneTitle
            note: root._noteText()
            bodySpacing: 12
            reveal: root._reveal

            Column {
                parent: indexShell.body
                width: parent.width
                spacing: 12 * Theme.scale

                FolioAction {
                    fixedWidth: parent.width
                    label: I18n.tr("Restore defaults")
                    enabled: root._resetEnabled
                    onTriggered: root._restoreDefaults()
                }
            }
        }

        Item {
            parent: sheet.readingArea
            anchors.fill: parent

            Text {
                visible: root.loading
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.leftMargin: 27 * Theme.scale
                anchors.rightMargin: 27 * Theme.scale
                anchors.topMargin: 24 * Theme.scale
                text: I18n.tr("Reading the scene's properties\u2026")
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBody
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }

            Flickable {
                id: flick
                visible: !root.loading
                anchors.fill: parent
                anchors.topMargin: 23 * Theme.scale
                anchors.leftMargin: 27 * Theme.scale
                anchors.rightMargin: 27 * Theme.scale
                anchors.bottomMargin: 20 * Theme.scale
                clip: true
                contentWidth: width
                contentHeight: readingCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: readingCol
                    width: flick.width
                    spacing: 14 * Theme.scale

                    Column {
                        visible: root.globalFpsKnown
                        width: parent.width
                        spacing: 8 * Theme.scale

                        Text {
                            text: I18n.tr("FPS")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontLabel
                            color: Theme.surfaceText
                            renderType: Text.NativeRendering
                        }
                        Text {
                            width: parent.width
                            text: I18n.tr("Limits this wallpaper's frame rate. Default follows the global Wallpaper Engine setting (%1 FPS).").arg(root.globalFps)
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontBase
                            color: Theme.withAlpha(Theme.surfaceText, 0.58)
                            lineHeight: 1.35
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }
                        ChoiceButtons {
                            width: parent.width
                            value: root.fpsValue
                            options: [
                                { value: null, label: I18n.tr("Default") },
                                { value: 15, label: "15" },
                                { value: 24, label: "24" },
                                { value: 30, label: "30" },
                                { value: 60, label: "60" },
                                { value: 90, label: "90" },
                                { value: 120, label: "120" },
                                { value: 144, label: "144" },
                                { value: 240, label: "240" }
                            ]
                            onSelected: (v) => root._setFps(v)
                        }
                        Row {
                            width: parent.width
                            spacing: 9 * Theme.scale
                            FolioSlider {
                                id: fpsSlider
                                width: parent.width - fpsNum.width - 9 * Theme.scale
                                from: 1
                                to: 240
                                step: 1
                                onReleased: (v) => root._setFps(Math.round(v))
                                Component.onCompleted: value = (root.fpsValue !== null ? root.fpsValue : root.globalFps)
                                Connections {
                                    target: root
                                    function onFpsValueChanged() {
                                        if (!fpsSlider.dragging)
                                            fpsSlider.value = (root.fpsValue !== null ? root.fpsValue : root.globalFps)
                                    }
                                    function onGlobalFpsChanged() {
                                        if (!fpsSlider.dragging && root.fpsValue === null)
                                            fpsSlider.value = root.globalFps
                                    }
                                }
                            }
                            Text {
                                id: fpsNum
                                width: 48 * Theme.scale
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(fpsSlider.value)
                                horizontalAlignment: Text.AlignRight
                                font.family: Theme.display
                                font.pixelSize: Theme.fontBase
                                color: Theme.surfaceText
                                renderType: Text.NativeRendering
                            }
                        }
                    }

                    FolioRule {
                        visible: root.globalFpsKnown && rows.count > 0
                        width: parent.width
                        alpha: 0.5
                    }

                    Repeater {
                        id: rows
                        model: root._shownRows()
                        delegate: ScenePropertyRow {
                            required property var modelData
                            width: readingCol.width
                            row: modelData
                            seedRevision: root.seedRevision
                            available: readingCol.width
                            onCommitted: (name, value) => root._writeProperty(name, value)
                        }
                    }

                    Text {
                        visible: !root.loading && root.errorText === "" && root._shownRows().length === 0
                        width: parent.width
                        text: I18n.tr("This scene does not publish any adjustable properties.")
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontBody
                        color: Theme.withAlpha(Theme.surfaceText, 0.56)
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }

                    Text {
                        visible: root.errorText !== ""
                        width: parent.width
                        text: root.errorText
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontBody
                        color: Theme.destructive
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: root.closeRequested()
}
