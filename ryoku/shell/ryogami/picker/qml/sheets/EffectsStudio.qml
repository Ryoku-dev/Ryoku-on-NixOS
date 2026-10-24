import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: root

    required property PickerState state
    property var args
    property bool shown: false
    signal closeRequested()

    anchors.fill: parent
    focus: true

    property real _reveal: shown ? 1 : 0
    Behavior on _reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }
    visible: _reveal > 0.001

    readonly property string _mode: (root.args && root.args.mode) ? String(root.args.mode) : "studio"

    function _focused() {
        if (!root.state || !root.state.view || !root.state.field)
            return null
        var i = root.state.field.currentIndex
        if (i < 0)
            return null
        var e = root.state.view.get(i)
        return (e && e.key) ? e : null
    }
    function _close() {
        root._discardPreview()
        root.closeRequested()
    }

    property var _effects: []
    property string _selectedId: ""
    property string _expandedCategory: ""
    property var _params: ({})
    property string _previewOut: ""
    property bool _previewPending: false
    property bool _committing: false
    property int _navStop: 1
    property string _studioInput: ""
    property string _studioBase: ""

    readonly property var _extras: [
        { id: "grade", label: I18n.tr("Colour grade") },
        { id: "upscale", label: I18n.tr("Upscale") },
        { id: "optimise", label: I18n.tr("Optimise") }
    ]
    function _isExtra(id) { return id === "grade" || id === "upscale" || id === "optimise" }

    readonly property var _selectedEffect: {
        for (var i = 0; i < root._effects.length; ++i)
            if (root._effects[i].id === root._selectedId)
                return root._effects[i]
        return null
    }
    readonly property string _selKind: root._isExtra(root._selectedId)
        ? root._selectedId
        : (root._selectedEffect ? "effect" : "none")

    readonly property var _categories: {
        var out = [], idx = ({})
        for (var i = 0; i < root._effects.length; ++i) {
            var e = root._effects[i]
            var c = (e.category !== undefined) ? String(e.category) : "Other"
            if (idx[c] === undefined) { idx[c] = out.length; out.push({ name: c, effects: [] }) }
            out[idx[c]].effects.push({ id: e.id, label: e.label })
        }
        return out
    }

    readonly property bool _canApply: {
        if (root._selKind === "grade")
            return root._studioInput.length > 0
        if (root._selKind === "effect")
            return root._studioInput.length > 0 && root._previewOut.length > 0
        return false
    }

    readonly property string _title: {
        if (root._selKind === "grade") return I18n.tr("Colour grade")
        if (root._selKind === "upscale") return I18n.tr("Upscale")
        if (root._selKind === "optimise") return I18n.tr("Optimise")
        return root._selectedEffect ? String(root._selectedEffect.label || "") : ""
    }
    readonly property string _desc: {
        if (root._selKind === "grade") return I18n.tr("Adjust brightness, contrast, colour and warmth, then apply.")
        if (root._selKind === "upscale") return I18n.tr("Enlarge this image with a neural upscaler.")
        if (root._selKind === "optimise") return I18n.tr("Re-encode the library to reclaim disk space.")
        return root._selectedEffect ? String(root._selectedEffect.description || "") : ""
    }

    function _categoryOf(id) {
        for (var i = 0; i < root._effects.length; ++i)
            if (root._effects[i].id === id)
                return String(root._effects[i].category || "")
        return ""
    }

    function _loadEffects() {
        Daemon.call("effects.list", ({}), function(res, err) {
            if (err) { root.state.toast((err && err.message) || I18n.tr("The effect list could not be loaded."), "error"); return }
            root._effects = (res && res.effects) ? res.effects : []
            if (root._selectedId === "" || (!root._selectedEffect && !root._isExtra(root._selectedId))) {
                if (root._effects.length > 0)
                    root._selectEffect(root._effects[0].id)
            }
        })
    }

    function _seedParams(effect) {
        var m = ({})
        if (effect && effect.params)
            for (var i = 0; i < effect.params.length; ++i) {
                var p = effect.params[i]
                m[p.id] = (p.default !== undefined) ? p.default : (p.value !== undefined ? p.value : null)
            }
        root._params = m
    }

    function _selectEffect(id) {
        root._discardPreview()
        root._selectedId = id
        root._expandedCategory = root._categoryOf(id)
        root._navStop = 1
        root._seedParams(root._selectedEffect)
        root._requestPreview()
    }

    function _selectExtra(id) {
        root._discardPreview()
        root._selectedId = id
        if (id === "grade") { gradePanel.reset(); root._requestGradePreview() }
        else if (id === "upscale") root._upPoll()
        else if (id === "optimise") root._optPoll()
    }

    function _setParam(id, val) {
        var m = ({})
        for (var k in root._params) m[k] = root._params[k]
        m[id] = val
        root._params = m
    }

    function _requestPreview() {
        if (root._selKind !== "effect" || root._studioInput.length === 0)
            return
        var effId = root._selectedId
        root._previewPending = true
        Daemon.call("effects.preview", { input: root._studioInput, effect: effId, params: root._params }, function(res, err) {
            root._previewPending = false
            if (err) { root.state.toast((err && err.message) || I18n.tr("The preview failed."), "error"); return }
            if (root._selectedId !== effId) return
            root._previewOut = (res && res.output) ? String(res.output) : ""
        })
    }

    function _discardPreview() {
        var out = root._previewOut
        root._previewOut = ""
        if (out && out.length > 0)
            Daemon.call("effects.discard", { preview: out }, function(res, err) {})
    }

    function _onDiscard() {
        if (root._selKind === "grade") { gradePanel.reset(); root._discardPreview() }
        else if (root._selKind === "effect") { root._discardPreview(); root._seedParams(root._selectedEffect) }
    }

    function _apply() {
        if (root._selKind === "effect") root._commitEffect()
        else if (root._selKind === "grade") root._commitGrade()
    }

    function _commitEffect() {
        if (!root._canApply) return
        root._committing = true
        var effId = root._selectedId
        Daemon.call("effects.commit", { preview: root._previewOut, input: root._studioInput, effect: effId, params: root._params }, function(res, err) {
            if (err) { root._committing = false; root.state.toast((err && err.message) || I18n.tr("The effect could not be saved."), "error"); return }
            root._previewOut = ""
            root.state.toast(I18n.tr("Effect saved."), "success")
            root.closeRequested()
        })
    }

    function _gradeArgs() {
        return {
            input: root._studioInput,
            brightness: Math.round(gradePanel.brightness),
            contrast: Math.round(gradePanel.contrast),
            saturation: Math.round(gradePanel.saturation),
            warmth: Math.round(gradePanel.warmth),
            vignette: gradePanel.vignette,
            negate: gradePanel.negate
        }
    }
    function _requestGradePreview() {
        if (root._studioInput.length === 0) return
        root._previewPending = true
        Daemon.call("grade.preview", root._gradeArgs(), function(res, err) {
            root._previewPending = false
            if (err) { root.state.toast((err && err.message) || I18n.tr("The preview failed."), "error"); return }
            root._previewOut = (res && res.output) ? String(res.output) : ""
        })
    }
    function _commitGrade() {
        if (root._studioInput.length === 0) return
        root._committing = true
        Daemon.call("grade.commit", root._gradeArgs(), function(res, err) {
            if (err) { root._committing = false; root.state.toast((err && err.message) || I18n.tr("The edit could not be saved."), "error"); return }
            root._previewOut = ""
            root.state.toast(I18n.tr("Colour grade saved."), "success")
            root.closeRequested()
        })
    }

    property bool _upRunning: false
    property var _upStatus: ({})
    function _upStart() {
        if (root._studioInput.length === 0) return
        Daemon.call("upscale.start", { input: root._studioInput }, function(res, err) {
            if (err) { root.state.toast((err && err.message) || I18n.tr("Upscale could not start."), "error"); return }
            root._upRunning = true
            upTimer.restart()
        })
    }
    function _upPoll() {
        Daemon.call("upscale.status", ({}), function(res, err) {
            if (err) return
            root._upStatus = res || ({})
            root._upRunning = !!(res && res.running)
            if (!root._upRunning) upTimer.stop()
        })
    }
    function _upCancel() {
        Daemon.call("upscale.cancel", ({}), function(res, err) {})
        root._upRunning = false
        upTimer.stop()
    }
    Timer { id: upTimer; interval: 800; repeat: true; running: false; onTriggered: root._upPoll() }

    property bool _optRunning: false
    property var _optStatus: ({})
    property string _optPreset: String(Settings.value("performance.imageOptimizePreset") || "quality")
    property string _optResolution: "4k"
    function _optStart() {
        Daemon.call("optimize.start", { preset: root._optPreset, resolution: root._optResolution }, function(res, err) {
            if (err) { root.state.toast((err && err.message) || I18n.tr("Optimise could not start."), "error"); return }
            root._optRunning = true
            optTimer.restart()
        })
    }
    function _optPoll() {
        Daemon.call("optimize.status", ({}), function(res, err) {
            if (err) return
            root._optStatus = res || ({})
            root._optRunning = !!(res && res.running)
            if (!root._optRunning) optTimer.stop()
        })
    }
    function _optCancel() {
        Daemon.call("optimize.cancel", ({}), function(res, err) {})
        root._optRunning = false
        optTimer.stop()
    }
    Timer { id: optTimer; interval: 800; repeat: true; running: false; onTriggered: root._optPoll() }

    function _progressFrac(s) {
        var t = Number(s && s.total), p = Number(s && s.progress)
        return (t > 0 && !isNaN(p)) ? Math.max(0, Math.min(1, p / t)) : 0
    }
    function _progressSuffix(s) {
        var t = Number(s && s.total), p = Number(s && s.progress)
        return (t > 0) ? ("  " + (isNaN(p) ? 0 : p) + " / " + t) : ""
    }
    function _verdictText(v) {
        if (!v) return ""
        var r = String(v.result || "")
        if (r === "done") return I18n.tr("Upscaled successfully.")
        if (r === "sharp") return I18n.tr("Already sharp; nothing to do.")
        if (r === "unsupported") return I18n.tr("This image cannot be upscaled.")
        if (r === "error") return I18n.tr("Upscale failed: ") + String(v.why || "")
        return ""
    }

    function _navMax() {
        var n = (root._selectedEffect && root._selectedEffect.params) ? root._selectedEffect.params.length : 0
        return 1 + n
    }
    function _nav(dy) { root._navStop = Math.max(0, Math.min(root._navMax(), root._navStop + dy)) }
    function _stepCategory(dx) {
        var cats = root._categories
        if (cats.length === 0) return
        var ci = 0
        for (var i = 0; i < cats.length; ++i) if (cats[i].name === root._expandedCategory) { ci = i; break }
        ci = (ci + dx + cats.length) % cats.length
        if (cats[ci].effects.length > 0) root._selectEffect(cats[ci].effects[0].id)
    }
    function _stepEffect(dx) {
        var eff = null
        for (var i = 0; i < root._categories.length; ++i)
            if (root._categories[i].name === root._expandedCategory) { eff = root._categories[i].effects; break }
        if (!eff) return
        var ei = 0
        for (var j = 0; j < eff.length; ++j) if (eff[j].id === root._selectedId) { ei = j; break }
        ei = Math.max(0, Math.min(eff.length - 1, ei + dx))
        root._selectEffect(eff[ei].id)
    }
    function _nudgeParam(i, dx) {
        if (!root._selectedEffect || !root._selectedEffect.params) return
        var p = root._selectedEffect.params[i]
        if (!p) return
        var type = (p.type !== undefined) ? String(p.type) : "number"
        if (type === "dropdown") {
            var opts = p.options || []
            if (opts.length === 0) return
            var cur = root._params[p.id], idx = 0
            for (var k = 0; k < opts.length; ++k) {
                var v = (opts[k].mode !== undefined) ? opts[k].mode : opts[k].value
                if (v === cur) { idx = k; break }
            }
            idx = (idx + dx + opts.length) % opts.length
            var nv = (opts[idx].mode !== undefined) ? opts[idx].mode : opts[idx].value
            root._setParam(p.id, nv); root._requestPreview()
        } else if (type === "color") {
            // Colour has no ordered nudge.
        } else {
            var step = Number(p.step) || 1
            var mn = Number(p.min), mx = Number(p.max)
            var c = Number(root._params[p.id])
            if (isNaN(c)) c = Number(p.default) || 0
            c += dx * step
            if (!isNaN(mn)) c = Math.max(mn, c)
            if (!isNaN(mx)) c = Math.min(mx, c)
            if (type === "integer") c = Math.round(c)
            root._setParam(p.id, c); root._requestPreview()
        }
    }
    function _navH(dx) {
        if (root._navStop === 0) root._stepCategory(dx)
        else if (root._navStop === 1) root._stepEffect(dx)
        else root._nudgeParam(root._navStop - 2, dx)
    }

    property var _outputs: []
    property var _selected: ({})
    property var _fillModes: ({})
    property var _locks: ({})
    property string _themeOutput: ""
    property var _audioMute: ({})
    property var _audioVolume: ({})
    property var _manual: ({})

    readonly property var _incoming: root._focused()
    readonly property string _incType: root._incoming ? String(root._incoming.type || "static") : "static"
    readonly property string _incPath: root._incoming ? String(root._incoming.path || "") : ""
    readonly property string _incThumb: root._incoming ? Library.fileUrl(root._incoming.fullImage || root._incoming.thumb || "") : ""
    readonly property string _incName: root._incoming ? String(root._incoming.name || root._incoming.key || "") : ""

    function _settingStr(key, def) {
        if (typeof Settings === "undefined" || !Settings.ready) return def
        var v = Settings.value(key)
        return (v === undefined || v === null || v === "") ? def : String(v)
    }
    function _settingBool(key, def) {
        if (typeof Settings === "undefined" || !Settings.ready) return def
        var v = Settings.value(key)
        if (v === undefined || v === null) return def
        return v === true || v === "true"
    }
    function _kindLabel(t) { return t === "video" ? I18n.tr("Video") : I18n.tr("Image") }

    function _isSel(name) { return root._selected[name] === true }
    function _selCount() {
        var c = 0
        for (var i = 0; i < root._outputs.length; ++i)
            if (root._selected[root._outputs[i].name]) c++
        return c
    }
    function _allSelected() { return root._outputs.length > 0 && root._selCount() === root._outputs.length }
    function _toggleSel(name) { var m = Object.assign({}, root._selected); m[name] = !m[name]; root._selected = m }
    function _toggleAll() {
        var all = root._allSelected(), m = ({})
        for (var i = 0; i < root._outputs.length; ++i) m[root._outputs[i].name] = !all
        root._selected = m
    }

    function _outThumb(out) {
        if (!out || !out.current) return ""
        var c = out.current
        if (c.key && typeof Library !== "undefined") {
            var e = Library.entry("wallpapers", c.key)
            if (e && e.thumb) return Library.fileUrl(e.thumb)
        }
        if (c.path) return Library.fileUrl(c.path)
        return ""
    }
    function _outFit(out) {
        return root._settingStr("display.fillModes." + out.name, (out.current && out.current.fit) ? String(out.current.fit) : "fill")
    }

    function _initSelection() {
        var outs = (typeof Library !== "undefined" && Library.outputs) ? Library.outputs : []
        root._outputs = outs
        var sel = ({}), fills = ({}), locks = ({})
        for (var i = 0; i < outs.length; ++i) {
            var n = outs[i].name
            sel[n] = true
            fills[n] = root._outFit(outs[i])
            locks[n] = root._settingBool("display.outputLocks." + n, false)
        }
        root._selected = sel; root._fillModes = fills; root._locks = locks
        root._themeOutput = root._settingStr("display.themeOutput", "")
        root._audioMute = ({}); root._audioVolume = ({}); root._manual = ({})
    }
    function _refreshOutputs() {
        var outs = (typeof Library !== "undefined" && Library.outputs) ? Library.outputs : []
        root._outputs = outs
        var sel = Object.assign({}, root._selected)
        var fills = Object.assign({}, root._fillModes)
        var locks = Object.assign({}, root._locks)
        for (var i = 0; i < outs.length; ++i) {
            var n = outs[i].name
            if (sel[n] === undefined) sel[n] = true
            if (fills[n] === undefined) fills[n] = root._outFit(outs[i])
            if (locks[n] === undefined) locks[n] = root._settingBool("display.outputLocks." + n, false)
        }
        root._selected = sel; root._fillModes = fills; root._locks = locks
    }

    function _setFill(name, mode) {
        Settings.set("display.fillModes." + name, mode)
        var m = Object.assign({}, root._fillModes); m[name] = mode; root._fillModes = m
        var out = null
        for (var i = 0; i < root._outputs.length; ++i) if (root._outputs[i].name === name) { out = root._outputs[i]; break }
        var cur = (out && out.current) ? out.current : null
        if (cur && cur.path)
            Daemon.call("wall.apply", { type: cur.type || "static", path: cur.path, outputs: [name] }, function(res, err) {
                if (err) root.state.toast((err && err.message) || I18n.tr("The placement could not be changed."), "error")
            })
    }
    function _setLock(name, locked) {
        Settings.set("display.outputLocks." + name, locked)
        var m = Object.assign({}, root._locks); m[name] = locked; root._locks = m
    }
    function _toggleColours(name) {
        if (root._themeOutput === name) {
            Settings.set("display.themeOutput", "")
            root._themeOutput = ""
            root.state.toast(I18n.tr("This display no longer sets the colours."), "info")
        } else {
            Settings.set("display.themeOutput", name)
            root._themeOutput = name
        }
    }
    function _setPause(name, manual) {
        Daemon.call("wall.pause", { outputs: [name], paused: manual }, function(res, err) {
            if (err) root.state.toast((err && err.message) || I18n.tr("Playback could not be changed."), "error")
        })
        var m = Object.assign({}, root._manual); m[name] = manual; root._manual = m
    }
    function _setMute(name, muted) { var m = Object.assign({}, root._audioMute); m[name] = muted; root._audioMute = m }
    function _setVolume(name, v) { var m = Object.assign({}, root._audioVolume); m[name] = v; root._audioVolume = m }

    function _applyToSelected() {
        if (!root._incoming) { root.closeRequested(); return }
        var count = root._selCount()
        if (count === 0) return
        var names = []
        for (var i = 0; i < root._outputs.length; ++i) {
            var n = root._outputs[i].name
            if (root._selected[n]) names.push(n)
        }
        var wildcard = (root._incType !== "video" && root._allSelected())
        var params = { type: root._incType, path: root._incPath, outputs: wildcard ? ["*"] : names }
        if (root._incType === "video") {
            var am = ({}), vm = ({})
            for (var j = 0; j < names.length; ++j) {
                var nm = names[j]
                am[nm] = (root._audioMute[nm] === true)
                vm[nm] = (root._audioVolume[nm] !== undefined ? root._audioVolume[nm] : 100)
            }
            if (Object.keys(am).length > 0) params.outputs_audio = am
            if (Object.keys(vm).length > 0) params.outputs_volume = vm
        }
        Daemon.call("wall.apply", params, function(res, err) {
            if (err) { root.state.toast((err && err.message) || I18n.tr("This wallpaper could not be applied."), "error"); return }
            root.closeRequested()
        })
    }

    onShownChanged: {
        if (!root.shown) return
        if (root._mode === "studio") {
            var e = root._focused()
            if (!e || String(e.type || "") !== "static") {
                root.state.toast(I18n.tr("Effects only work on images."), "error")
                root.closeRequested()
                return
            }
            root._studioInput = String(e.path || "")
            root._studioBase = Library.fileUrl(e.fullImage || e.path || "")
            root._loadEffects()
        } else {
            if (typeof Library !== "undefined") Library.refreshOutputs()
            root._initSelection()
        }
    }

    Connections {
        target: (typeof Library !== "undefined") ? Library : null
        function onOutputsChanged() { if (root.shown && root._mode !== "studio") root._refreshOutputs() }
    }

    Keys.onEscapePressed: root._close()
    Keys.onPressed: (event) => {
        if (root._mode !== "studio" || root._selKind !== "effect") return
        if (event.key === Qt.Key_Up) { root._nav(-1); event.accepted = true }
        else if (event.key === Qt.Key_Down) { root._nav(1); event.accepted = true }
        else if (event.key === Qt.Key_Left) { root._navH(-1); event.accepted = true }
        else if (event.key === Qt.Key_Right) { root._navH(1); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root._apply(); event.accepted = true }
    }

    Item {
        id: studio
        anchors.fill: parent
        visible: root._mode === "studio"

        Scrim { anchors.fill: parent; alpha: 0.68; reveal: root._reveal; dismissable: true; onDismissed: root._close() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.max(Theme.folioSheetMinWidth, Math.min(Theme.folioSheetWidth * Theme.scale, root.width - Theme.folioSheetMargin * Theme.scale))
            height: Math.max(Theme.folioSheetMinHeight, Math.min(Theme.folioSheetHeight * Theme.scale, root.height - Theme.folioSheetMargin * Theme.scale))
            color: Theme.withAlpha(Theme.surface, 0.99)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.66)
            opacity: root._reveal
            clip: true

            readonly property real _indexW: 292 * Math.max(0.9, Theme.scale)

            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                source: (root._selKind === "effect" || root._selKind === "grade")
                    ? (root._previewOut.length > 0 ? Library.fileUrl(root._previewOut) : root._studioBase)
                    : root._studioBase
            }
            Text {
                anchors.centerIn: parent
                visible: root._previewPending && root._previewOut.length === 0 && (root._selKind === "effect" || root._selKind === "grade")
                text: I18n.tr("Updating preview\u2026")
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontBody
                color: Theme.withAlpha(Theme.surfaceText, 0.52)
                renderType: Text.NativeRendering
            }

            Rectangle { anchors.fill: parent; color: Theme.withAlpha(Theme.background, 0.16) }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.38) }
                    GradientStop { position: 0.34; color: Qt.rgba(0, 0, 0, 0.08) }
                    GradientStop { position: 0.66; color: Qt.rgba(0, 0, 0, 0.12) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
                }
            }

            Row {
                anchors.fill: parent
                spacing: 0

                Item {
                    width: card._indexW
                    height: parent.height
                    EffectsIndexRail {
                        anchors.fill: parent
                        categories: root._categories
                        extras: root._extras
                        selectedId: root._selectedId
                        expandedCategory: root._expandedCategory
                        focusCategory: root._navStop === 0
                        focusEffect: root._navStop === 1
                        imagesOnly: true
                        onCategoryPicked: (name) => {
                            root._expandedCategory = name
                            var cats = root._categories
                            for (var i = 0; i < cats.length; ++i)
                                if (cats[i].name === name && cats[i].effects.length > 0) { root._selectEffect(cats[i].effects[0].id); break }
                        }
                        onEffectPicked: (id) => root._selectEffect(id)
                        onExtraPicked: (id) => root._selectExtra(id)
                    }
                }

                Item {
                    id: editorHost
                    width: parent.width - card._indexW
                    height: parent.height

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 28 * Theme.scale
                        anchors.bottomMargin: 24 * Theme.scale
                        anchors.leftMargin: 28 * Theme.scale
                        anchors.rightMargin: 26 * Theme.scale
                        spacing: 14 * Theme.scale

                        Text {
                            Layout.fillWidth: true
                            text: root._title
                            font.family: Theme.display
                            font.pixelSize: Theme.fs(52)
                            lineHeight: 0.96
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 620 * Theme.scale
                            visible: root._desc.length > 0
                            text: root._desc
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontBase
                            color: Theme.withAlpha(Theme.surfaceText, 0.72)
                            lineHeight: 1.35
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7 * Theme.scale
                            Item { Layout.fillWidth: true }
                            FolioAction {
                                visible: root._selKind === "effect" || root._selKind === "grade"
                                fixedWidth: 96 * Theme.scale
                                label: I18n.tr("Apply")
                                active: root._canApply
                                enabled: root._canApply
                                onTriggered: root._apply()
                            }
                            FolioAction {
                                visible: root._selKind === "effect" || root._selKind === "grade"
                                label: I18n.tr("Discard")
                                onTriggered: root._onDiscard()
                            }
                            FolioAction { label: "\u00d7"; minWidth: 30; onTriggered: root._close() }
                        }

                        Item { Layout.fillWidth: true; Layout.fillHeight: true }

                        FolioRule { Layout.fillWidth: true; alpha: 0.5 }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root._selKind === "effect"
                            color: Theme.withAlpha(Theme.surface, 0.84)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.outline, 0.68)
                            implicitHeight: paramCol.implicitHeight + 40 * Theme.scale

                            Column {
                                id: paramCol
                                x: 24 * Theme.scale
                                y: 18 * Theme.scale
                                width: parent.width - 48 * Theme.scale
                                spacing: 12 * Theme.scale

                                Text {
                                    text: I18n.tr("Settings")
                                    font.family: Theme.sans
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Theme.fontField
                                    color: Theme.surfaceText
                                    renderType: Text.NativeRendering
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 26 * Theme.scale
                                    visible: root._selectedEffect && root._selectedEffect.params && root._selectedEffect.params.length > 0

                                    Repeater {
                                        model: (root._selectedEffect && root._selectedEffect.params) ? root._selectedEffect.params : []
                                        delegate: EffectsParamControl {
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            Layout.alignment: Qt.AlignTop
                                            param: modelData
                                            value: (root._params[modelData.id] !== undefined) ? root._params[modelData.id] : modelData.default
                                            focused: root._navStop === index + 2
                                            onMoved: (v) => { root._params[modelData.id] = v }
                                            onCommitted: (v) => { root._setParam(modelData.id, v); root._requestPreview() }
                                        }
                                    }
                                }

                                Text {
                                    visible: !(root._selectedEffect && root._selectedEffect.params && root._selectedEffect.params.length > 0)
                                    width: parent.width
                                    text: I18n.tr("This effect has no settings. Apply it as it is.")
                                    font.family: Theme.sans
                                    font.weight: Font.Normal
                                    font.pixelSize: Theme.fontBase
                                    color: Theme.withAlpha(Theme.surfaceText, 0.52)
                                    wrapMode: Text.WordWrap
                                    renderType: Text.NativeRendering
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root._selKind === "grade"
                            color: Theme.withAlpha(Theme.surface, 0.84)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.outline, 0.68)
                            implicitHeight: gradeCol.implicitHeight + 40 * Theme.scale

                            Column {
                                id: gradeCol
                                x: 24 * Theme.scale
                                y: 18 * Theme.scale
                                width: parent.width - 48 * Theme.scale
                                spacing: 12 * Theme.scale

                                Text {
                                    text: I18n.tr("Adjustments")
                                    font.family: Theme.sans
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Theme.fontField
                                    color: Theme.surfaceText
                                    renderType: Text.NativeRendering
                                }
                                EffectsGradePanel {
                                    id: gradePanel
                                    width: parent.width
                                    onChanged: root._requestGradePreview()
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root._selKind === "upscale"
                            color: Theme.withAlpha(Theme.surface, 0.84)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.outline, 0.68)
                            implicitHeight: upCol.implicitHeight + 40 * Theme.scale

                            Column {
                                id: upCol
                                x: 24 * Theme.scale
                                y: 18 * Theme.scale
                                width: parent.width - 48 * Theme.scale
                                spacing: 12 * Theme.scale

                                Text {
                                    text: I18n.tr("Upscale this image")
                                    font.family: Theme.sans
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Theme.fontField
                                    color: Theme.surfaceText
                                    renderType: Text.NativeRendering
                                }

                                Column {
                                    width: parent.width
                                    spacing: 7 * Theme.scale
                                    visible: root._upRunning
                                    Text {
                                        text: (root._upStatus.phase ? String(root._upStatus.phase) : I18n.tr("Working")) + root._progressSuffix(root._upStatus)
                                        font.family: Theme.sans
                                        font.weight: Font.Medium
                                        font.pixelSize: Theme.fontBase
                                        color: Theme.withAlpha(Theme.surfaceText, 0.7)
                                        renderType: Text.NativeRendering
                                    }
                                    Rectangle {
                                        width: parent.width
                                        height: 4 * Theme.scale
                                        color: Theme.withAlpha(Theme.outline, 0.3)
                                        Rectangle {
                                            height: parent.height
                                            width: parent.width * root._progressFrac(root._upStatus)
                                            color: Theme.withAlpha(Theme.surfaceText, 0.9)
                                        }
                                    }
                                    Text {
                                        visible: root._upStatus.file !== undefined && String(root._upStatus.file).length > 0
                                        width: parent.width
                                        text: String(root._upStatus.file || "")
                                        font.family: Theme.sans
                                        font.weight: Font.Medium
                                        font.pixelSize: Theme.fontMini
                                        color: Theme.withAlpha(Theme.surfaceText, 0.5)
                                        elide: Text.ElideMiddle
                                        renderType: Text.NativeRendering
                                    }
                                }

                                Text {
                                    visible: !root._upRunning && root._upStatus.verdict !== undefined && root._verdictText(root._upStatus.verdict).length > 0
                                    width: parent.width
                                    text: root._verdictText(root._upStatus.verdict)
                                    font.family: Theme.sans
                                    font.weight: Font.Normal
                                    font.pixelSize: Theme.fontMini
                                    color: Theme.withAlpha(Theme.surfaceText, 0.6)
                                    wrapMode: Text.WordWrap
                                    renderType: Text.NativeRendering
                                }

                                Row {
                                    spacing: 7 * Theme.scale
                                    FolioAction {
                                        visible: !root._upRunning
                                        label: I18n.tr("Start")
                                        active: root._studioInput.length > 0
                                        enabled: root._studioInput.length > 0
                                        onTriggered: root._upStart()
                                    }
                                    FolioDestructiveAction {
                                        visible: root._upRunning
                                        label: I18n.tr("Cancel")
                                        confirm: true
                                        onTriggered: root._upCancel()
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root._selKind === "optimise"
                            color: Theme.withAlpha(Theme.surface, 0.84)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.outline, 0.68)
                            implicitHeight: optCol.implicitHeight + 40 * Theme.scale

                            Column {
                                id: optCol
                                x: 24 * Theme.scale
                                y: 18 * Theme.scale
                                width: parent.width - 48 * Theme.scale
                                spacing: 12 * Theme.scale

                                Text {
                                    text: I18n.tr("Optimise the library")
                                    font.family: Theme.sans
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Theme.fontField
                                    color: Theme.surfaceText
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    text: I18n.tr("Quality")
                                    font.family: Theme.sans
                                    font.weight: Font.Medium
                                    font.pixelSize: Theme.fontFine
                                    color: Theme.withAlpha(Theme.surfaceText, 0.46)
                                    renderType: Text.NativeRendering
                                }
                                ChoiceButtons {
                                    width: parent.width
                                    value: root._optPreset
                                    options: [
                                        { value: "light", label: I18n.tr("Light") },
                                        { value: "balanced", label: I18n.tr("Balanced") },
                                        { value: "quality", label: I18n.tr("Quality") }
                                    ]
                                    onSelected: (v) => root._optPreset = v
                                }

                                Text {
                                    text: I18n.tr("Maximum resolution")
                                    font.family: Theme.sans
                                    font.weight: Font.Medium
                                    font.pixelSize: Theme.fontFine
                                    color: Theme.withAlpha(Theme.surfaceText, 0.46)
                                    renderType: Text.NativeRendering
                                }
                                ChoiceButtons {
                                    width: parent.width
                                    value: root._optResolution
                                    options: [
                                        { value: "1080p", label: I18n.tr("1080p") },
                                        { value: "2k", label: I18n.tr("2K") },
                                        { value: "4k", label: I18n.tr("4K") }
                                    ]
                                    onSelected: (v) => root._optResolution = v
                                }

                                Column {
                                    width: parent.width
                                    spacing: 7 * Theme.scale
                                    visible: root._optRunning
                                    Text {
                                        text: I18n.tr("Optimising") + root._progressSuffix(root._optStatus)
                                        font.family: Theme.sans
                                        font.weight: Font.Medium
                                        font.pixelSize: Theme.fontBase
                                        color: Theme.withAlpha(Theme.surfaceText, 0.7)
                                        renderType: Text.NativeRendering
                                    }
                                    Rectangle {
                                        width: parent.width
                                        height: 4 * Theme.scale
                                        color: Theme.withAlpha(Theme.outline, 0.3)
                                        Rectangle {
                                            height: parent.height
                                            width: parent.width * root._progressFrac(root._optStatus)
                                            color: Theme.withAlpha(Theme.surfaceText, 0.9)
                                        }
                                    }
                                    Text {
                                        visible: root._optStatus.currentFile !== undefined && String(root._optStatus.currentFile).length > 0
                                        width: parent.width
                                        text: String(root._optStatus.currentFile || "")
                                        font.family: Theme.sans
                                        font.weight: Font.Medium
                                        font.pixelSize: Theme.fontMini
                                        color: Theme.withAlpha(Theme.surfaceText, 0.5)
                                        elide: Text.ElideMiddle
                                        renderType: Text.NativeRendering
                                    }
                                }

                                Text {
                                    visible: !root._optRunning && (Number(root._optStatus.optimized || 0) + Number(root._optStatus.skipped || 0) + Number(root._optStatus.failed || 0)) > 0
                                    width: parent.width
                                    text: I18n.tr("Optimised %1 \u00b7 skipped %2 \u00b7 failed %3")
                                        .arg(Number(root._optStatus.optimized || 0))
                                        .arg(Number(root._optStatus.skipped || 0))
                                        .arg(Number(root._optStatus.failed || 0))
                                    font.family: Theme.sans
                                    font.weight: Font.Normal
                                    font.pixelSize: Theme.fontMini
                                    color: Theme.withAlpha(Theme.surfaceText, 0.6)
                                    renderType: Text.NativeRendering
                                }

                                Row {
                                    spacing: 7 * Theme.scale
                                    FolioAction {
                                        visible: !root._optRunning
                                        label: I18n.tr("Start")
                                        active: true
                                        onTriggered: root._optStart()
                                    }
                                    FolioDestructiveAction {
                                        visible: root._optRunning
                                        label: I18n.tr("Cancel")
                                        confirm: true
                                        onTriggered: root._optCancel()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.withAlpha(Theme.surface, 0.9)
                visible: root._committing
            }
        }
    }

    Item {
        id: displays
        anchors.fill: parent
        visible: root._mode !== "studio"

        FolioSheet {
            id: sheet
            reveal: root._reveal
            showMasthead: false
            onDismissed: root._close()
        }

        FolioIndexShell {
            parent: sheet.indexArea
            anchors.fill: parent
            title: I18n.tr("Displays")
            note: I18n.tr("Pick where the wallpaper should go. Displays you do not select keep their current wallpaper.")

            Column {
                parent: parent.body
                anchors.fill: parent
                spacing: 13 * Theme.scale

                Column {
                    width: parent.width
                    spacing: 5 * Theme.scale
                    Rectangle {
                        width: parent.width
                        height: 152 * Theme.scale
                        color: Theme.withAlpha(Theme.surfaceVariant, 0.4)
                        clip: true
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            visible: root._incThumb.length > 0
                            source: root._incThumb
                        }
                    }
                    Text {
                        text: I18n.tr("New wallpaper")
                        font.family: Theme.sans
                        font.weight: Font.DemiBold
                        font.pixelSize: Theme.fontFine
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: root._incName
                        font.family: Theme.sans
                        font.weight: Font.DemiBold
                        font.pixelSize: Theme.fontField
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: root._kindLabel(root._incType)
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontMini
                        color: Theme.withAlpha(Theme.surfaceText, 0.48)
                        renderType: Text.NativeRendering
                    }
                }

                FolioRule { width: parent.width; alpha: 0.48 }

                Column {
                    width: parent.width
                    spacing: 7 * Theme.scale
                    Text {
                        text: I18n.tr("Displays")
                        font.family: Theme.sans
                        font.weight: Font.DemiBold
                        font.pixelSize: Theme.fontFine
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: String(root._selCount())
                        font.family: Theme.display
                        font.pixelSize: Theme.fontStudio
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("of %1 selected").arg(root._outputs.length)
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontBase
                        color: Theme.withAlpha(Theme.surfaceText, 0.7)
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("Each display keeps its own placement and audio settings.")
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontFine
                        color: Theme.withAlpha(Theme.surfaceText, 0.46)
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                    FolioAction {
                        width: parent.width
                        label: root._allSelected() ? I18n.tr("Clear selection") : I18n.tr("Select all")
                        active: root._allSelected()
                        enabled: root._outputs.length > 0
                        onTriggered: root._toggleAll()
                    }
                }
            }
        }

        Item {
            parent: sheet.readingArea
            anchors.fill: parent

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 23 * Theme.scale
                anchors.bottomMargin: 23 * Theme.scale
                anchors.leftMargin: 27 * Theme.scale
                anchors.rightMargin: 27 * Theme.scale
                spacing: 12 * Theme.scale

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7 * Theme.scale
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Choose displays")
                        font.family: Theme.display
                        font.pixelSize: Theme.fs(34)
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                    FolioAction { label: "\u00d7"; minWidth: 30; onTriggered: root._close() }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Only the displays you pick will change.")
                    font.family: Theme.sans
                    font.weight: Font.Normal
                    font.pixelSize: Theme.fontSmall
                    color: Theme.withAlpha(Theme.surfaceText, 0.56)
                    renderType: Text.NativeRendering
                }
                FolioRule { Layout.fillWidth: true; alpha: 0.58 }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Displays")
                    font.family: Theme.sans
                    font.weight: Font.DemiBold
                    font.pixelSize: Theme.fontField
                    color: Theme.surfaceText
                    renderType: Text.NativeRendering
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Pick a display, then choose how the wallpaper should fit.")
                    font.family: Theme.sans
                    font.weight: Font.Normal
                    font.pixelSize: Theme.fontSmall
                    color: Theme.withAlpha(Theme.surfaceText, 0.52)
                    renderType: Text.NativeRendering
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: tiles.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: tiles
                        width: parent.width
                        spacing: 9 * Theme.scale

                        Rectangle {
                            width: parent.width
                            visible: root._outputs.length === 0
                            color: Theme.withAlpha(Theme.surfaceContainer, 0.54)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.outline, 0.52)
                            implicitHeight: emptyCol.implicitHeight + 36 * Theme.scale
                            Column {
                                id: emptyCol
                                x: 18 * Theme.scale
                                y: 18 * Theme.scale
                                width: parent.width - 36 * Theme.scale
                                spacing: 5 * Theme.scale
                                Text {
                                    text: I18n.tr("Looking for displays")
                                    font.family: Theme.sans
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Theme.fontField
                                    color: Theme.surfaceText
                                    renderType: Text.NativeRendering
                                }
                                Text {
                                    width: parent.width
                                    text: I18n.tr("Displays will show up here when the compositor reports them.")
                                    font.family: Theme.sans
                                    font.weight: Font.Normal
                                    font.pixelSize: Theme.fontSmall
                                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                                    wrapMode: Text.WordWrap
                                    renderType: Text.NativeRendering
                                }
                            }
                        }

                        Repeater {
                            model: root._outputs
                            delegate: EffectsApplyTile {
                                required property var modelData
                                width: tiles.width
                                output: modelData
                                selected: root._isSel(modelData.name)
                                incomingThumb: root._incThumb
                                currentThumb: root._outThumb(modelData)
                                fillMode: (root._fillModes[modelData.name] !== undefined) ? root._fillModes[modelData.name] : "fill"
                                locked: root._locks[modelData.name] === true
                                colourSource: root._themeOutput === modelData.name
                                incomingVideo: root._incType === "video"
                                muted: root._audioMute[modelData.name] === true
                                volume: (root._audioVolume[modelData.name] !== undefined) ? root._audioVolume[modelData.name] : 100
                                currentVideo: modelData.current && (String(modelData.current.type || "") === "video")
                                manual: root._manual[modelData.name] === true
                                onToggled: root._toggleSel(modelData.name)
                                onPlacementPicked: (mode) => root._setFill(modelData.name, mode)
                                onLockToggled: (want) => root._setLock(modelData.name, want)
                                onColoursToggled: root._toggleColours(modelData.name)
                                onMuteToggled: (want) => root._setMute(modelData.name, want)
                                onVolumeMoved: (v) => root._setVolume(modelData.name, v)
                                onVolumeReleased: (v) => root._setVolume(modelData.name, v)
                                onPauseToggled: (want) => root._setPause(modelData.name, want)
                            }
                        }
                    }
                }

                FolioRule { Layout.fillWidth: true; alpha: 0.58 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 13 * Theme.scale
                    Column {
                        Layout.fillWidth: true
                        Text {
                            text: I18n.tr("Apply wallpaper")
                            font.family: Theme.sans
                            font.weight: Font.DemiBold
                            font.pixelSize: Theme.fontLabel
                            color: Theme.surfaceText
                            renderType: Text.NativeRendering
                        }
                        Text {
                            text: root._selCount() === 0 ? I18n.tr("Pick at least one display.") : I18n.tr("Only the displays you picked will change.")
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontFine
                            color: Theme.withAlpha(Theme.surfaceText, 0.5)
                            renderType: Text.NativeRendering
                        }
                    }
                    FolioAction {
                        fixedWidth: 210 * Theme.scale
                        label: root._selCount() === 0 ? I18n.tr("Choose displays") : I18n.tr("Apply to %1 displays").arg(root._selCount())
                        active: root._selCount() > 0
                        enabled: root._selCount() > 0
                        onTriggered: root._applyToSelected()
                    }
                }
            }
        }

        Keys.onEscapePressed: root._close()
    }
}
