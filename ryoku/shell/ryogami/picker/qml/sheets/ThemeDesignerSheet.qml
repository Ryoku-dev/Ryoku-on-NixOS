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

    property bool candDark: true
    property var candDarkRoles: ({})
    property var candLightRoles: ({})

    property string selRole: "primary"
    property real editH: 0
    property real editS: 0
    property real editV: 1
    property string loadedHex: "#000000"
    property string activePreset: ""
    property var recents: []
    property string roleQuery: ""

    property string nameText: ""
    property var savedPalettes: []
    property bool loadingLib: false
    property string libError: ""
    property var _wpEntry: null
    property string _baseline: ""

    readonly property var groupOrder: ["wall", "accents", "tertiary", "surfaces", "error", "effects"]

    readonly property var roleDefs: [
        { key: "primary", name: I18n.tr("Accent"), desc: I18n.tr("Selection, focus, and the main action colour."), group: "wall", chrome: true },
        { key: "primaryText", name: I18n.tr("Accent text"), desc: I18n.tr("Text and icons drawn on the accent."), group: "wall", chrome: true },
        { key: "tertiary", name: I18n.tr("Second accent"), desc: I18n.tr("The secondary accent for destructive and highlight cues."), group: "wall", chrome: true },
        { key: "surface", name: I18n.tr("Panel"), desc: I18n.tr("The panel and sheet background."), group: "wall", chrome: true },
        { key: "surfaceText", name: I18n.tr("Panel text"), desc: I18n.tr("Body text on panels."), group: "wall", chrome: true },
        { key: "surfaceVariant", name: I18n.tr("Panel alt"), desc: I18n.tr("Hover fills and quiet panel areas."), group: "wall", chrome: true },
        { key: "surfaceContainer", name: I18n.tr("Panel raised"), desc: I18n.tr("Cards, rows, and idle controls."), group: "wall", chrome: true },
        { key: "background", name: I18n.tr("Backdrop"), desc: I18n.tr("The backdrop behind panels."), group: "wall", chrome: true },
        { key: "outline", name: I18n.tr("Outline"), desc: I18n.tr("Borders, dividers, and rules."), group: "wall", chrome: true },

        { key: "primaryContainer", name: I18n.tr("Primary container"), desc: I18n.tr("A tinted fill behind primary content."), group: "accents" },
        { key: "onPrimaryContainer", name: I18n.tr("Primary container text"), desc: I18n.tr("Text on the primary container."), group: "accents" },
        { key: "inversePrimary", name: I18n.tr("Inverse primary"), desc: I18n.tr("The accent shown on inverted surfaces."), group: "accents" },
        { key: "secondary", name: I18n.tr("Secondary"), desc: I18n.tr("A muted companion to the accent."), group: "accents" },
        { key: "onSecondary", name: I18n.tr("Secondary text"), desc: I18n.tr("Text on the secondary colour."), group: "accents" },
        { key: "secondaryContainer", name: I18n.tr("Secondary container"), desc: I18n.tr("A tinted fill behind secondary content."), group: "accents" },
        { key: "onSecondaryContainer", name: I18n.tr("Secondary container text"), desc: I18n.tr("Text on the secondary container."), group: "accents" },
        { key: "surfaceTint", name: I18n.tr("Surface tint"), desc: I18n.tr("The accent tint elevated surfaces carry."), group: "accents" },

        { key: "onTertiary", name: I18n.tr("Tertiary text"), desc: I18n.tr("Text on the second accent."), group: "tertiary" },
        { key: "tertiaryContainer", name: I18n.tr("Tertiary container"), desc: I18n.tr("A tinted fill behind tertiary content."), group: "tertiary" },
        { key: "onTertiaryContainer", name: I18n.tr("Tertiary container text"), desc: I18n.tr("Text on the tertiary container."), group: "tertiary" },

        { key: "onSurfaceVariant", name: I18n.tr("Panel alt text"), desc: I18n.tr("Secondary text on quiet panels."), group: "surfaces" },
        { key: "outlineVariant", name: I18n.tr("Outline variant"), desc: I18n.tr("A fainter divider colour."), group: "surfaces" },
        { key: "inverseSurface", name: I18n.tr("Inverse surface"), desc: I18n.tr("A surface inverted for contrast."), group: "surfaces" },
        { key: "onInverseSurface", name: I18n.tr("Inverse surface text"), desc: I18n.tr("Text on the inverse surface."), group: "surfaces" },
        { key: "surfaceBright", name: I18n.tr("Bright surface"), desc: I18n.tr("The brightest surface step."), group: "surfaces" },
        { key: "surfaceDim", name: I18n.tr("Dim surface"), desc: I18n.tr("The dimmest surface step."), group: "surfaces" },
        { key: "surfaceContainerLowest", name: I18n.tr("Lowest container"), desc: I18n.tr("The lowest container step."), group: "surfaces" },
        { key: "surfaceContainerLow", name: I18n.tr("Low container"), desc: I18n.tr("A low container step."), group: "surfaces" },
        { key: "surfaceContainerHigh", name: I18n.tr("High container"), desc: I18n.tr("A high container step."), group: "surfaces" },
        { key: "surfaceContainerHighest", name: I18n.tr("Highest container"), desc: I18n.tr("The highest container step."), group: "surfaces" },
        { key: "onBackground", name: I18n.tr("Backdrop text"), desc: I18n.tr("Text on the backdrop."), group: "surfaces" },

        { key: "error", name: I18n.tr("Error"), desc: I18n.tr("The error accent."), group: "error" },
        { key: "onError", name: I18n.tr("Error text"), desc: I18n.tr("Text on the error accent."), group: "error" },
        { key: "errorContainer", name: I18n.tr("Error container"), desc: I18n.tr("A tinted fill behind error content."), group: "error" },
        { key: "onErrorContainer", name: I18n.tr("Error container text"), desc: I18n.tr("Text on the error container."), group: "error" },

        { key: "scrim", name: I18n.tr("Scrim"), desc: I18n.tr("The dimming behind modal surfaces."), group: "effects" },
        { key: "shadow", name: I18n.tr("Shadow"), desc: I18n.tr("The drop-shadow colour."), group: "effects" },
        { key: "sourceColor", name: I18n.tr("Source colour"), desc: I18n.tr("The seed colour the scheme derives from."), group: "effects" }
    ]

    readonly property var _presetOptions: {
        var keys = Object.keys(Theme.presets), out = []
        for (var i = 0; i < keys.length; i++) {
            var k = keys[i]
            out.push({ value: k, label: root._presetLabel(k), strip: Theme.presets[k].primary })
        }
        return out
    }

    readonly property var _previewMap: {
        var c = root.candDark ? root.candDarkRoles : root.candLightRoles
        if (!c)
            return null
        return {
            primary: c.primary, primaryText: c.primaryText, surface: c.surface,
            surfaceText: c.surfaceText, surfaceVariant: c.surfaceVariant,
            surfaceContainer: c.surfaceContainer, background: c.background,
            outline: c.outline, tertiary: c.tertiary
        }
    }

    readonly property bool _compact: flick.width < 780 * Theme.scale
    readonly property real _pageW: Math.max(0, flick.width - 76 * Theme.scale)

    readonly property bool _colourChanged: {
        root.candDarkRoles; root.candLightRoles; root.candDark; root.selRole; root.loadedHex
        return root._current(root.selRole) !== root.loadedHex
    }
    readonly property bool _dirty: {
        root.candDarkRoles; root.candLightRoles
        return root._baseline !== "" && root._baseline !== root._snapshot()
    }

    function _hex(c) {
        var q = Qt.color(c)
        function h2(x) { var s = Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
        return "#" + h2(q.r) + h2(q.g) + h2(q.b)
    }
    function _validHex(s) { return /^#?[0-9a-fA-F]{6}$/.test((s || "").trim()) }
    function _clean(s) { s = (s || "").trim(); if (s.charAt(0) !== "#") s = "#" + s; return s.toLowerCase() }
    function _norm(s) { return root._validHex(s) ? root._clean(s) : root._hex(Qt.color(s)) }
    function _rgbToHsv(hex) {
        var q = Qt.color(hex)
        var r = q.r, g = q.g, b = q.b
        var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, h = 0
        if (d > 0) {
            if (mx === r) h = ((g - b) / d) % 6
            else if (mx === g) h = (b - r) / d + 2
            else h = (r - g) / d + 4
            h *= 60; if (h < 0) h += 360
        }
        return { h: h, s: mx === 0 ? 0 : d / mx, v: mx }
    }
    function _hsvToHex(h, s, v) { return root._hex(Qt.hsva(Math.max(0, Math.min(0.99999, h / 360)), s, v, 1)) }

    function _clone(m) { var o = {}; for (var k in m) o[k] = m[k]; return o }
    function _current(mat) {
        var src = root.candDark ? root.candDarkRoles : root.candLightRoles
        return (src && src[mat]) ? src[mat] : "#000000"
    }
    function _setRoleColour(mat, hex) {
        var src = root.candDark ? root.candDarkRoles : root.candLightRoles
        var next = root._clone(src)
        next[mat] = hex
        if (root.candDark) root.candDarkRoles = next
        else root.candLightRoles = next
    }
    function _roleDef(key) { for (var i = 0; i < root.roleDefs.length; i++) if (root.roleDefs[i].key === key) return root.roleDefs[i]; return null }
    function _selName() { var r = root._roleDef(root.selRole); return r ? r.name : root.selRole }
    function _selDesc() { var r = root._roleDef(root.selRole); return r ? r.desc : "" }
    function _rolesIn(group, q) {
        var out = [], query = (q || "").toLowerCase().trim()
        for (var i = 0; i < root.roleDefs.length; i++) {
            var r = root.roleDefs[i]
            if (r.group !== group) continue
            if (query !== "" && r.name.toLowerCase().indexOf(query) < 0 && r.key.toLowerCase().indexOf(query) < 0) continue
            out.push(r)
        }
        return out
    }
    function _groupLabel(g) {
        switch (g) {
        case "wall": return I18n.tr("Wall interface")
        case "accents": return I18n.tr("Primary and secondary")
        case "tertiary": return I18n.tr("Tertiary")
        case "surfaces": return I18n.tr("Surfaces and outlines")
        case "error": return I18n.tr("Errors")
        case "effects": return I18n.tr("Source and effects")
        }
        return g
    }
    function _presetLabel(k) {
        var s = k.replace(/-/g, " ")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    function _seedValue(r) {
        var wall = Theme.wall || ({}), wp = Theme.wallPalette
        if (r.chrome) return root._norm(wp[r.key])
        if (typeof wall[r.key] === "string" && wall[r.key].length) return root._norm(wall[r.key])
        var m = r.key.toLowerCase()
        if (m.indexOf("container") >= 0) return root._norm(wp.surfaceContainer)
        if (m.indexOf("outline") >= 0) return root._norm(wp.outline)
        if (m.indexOf("inverse") >= 0) return root._norm(wp.surfaceText)
        if (m.indexOf("error") >= 0) return "#ffb4ab"
        if (m === "scrim" || m === "shadow") return "#000000"
        if (m.charAt(0) === "o" && m.charAt(1) === "n") return root._norm(wp.surfaceText)
        return root._norm(wp.surfaceVariant)
    }
    function _seedRoles() {
        var o = {}
        for (var i = 0; i < root.roleDefs.length; i++) { var r = root.roleDefs[i]; o[r.key] = root._seedValue(r) }
        return o
    }
    function _seedCandidate() {
        root.candDarkRoles = root._seedRoles()
        root.candLightRoles = root._seedRoles()
        root.activePreset = ""
        root._markSaved()
    }

    readonly property var _chrome9: ["primary", "primaryText", "surface", "surfaceText", "surfaceVariant", "surfaceContainer", "background", "outline", "tertiary"]
    function _payload9(roles) {
        var o = {}
        for (var i = 0; i < root._chrome9.length; i++) { var k = root._chrome9[i]; if (roles && roles[k]) o[k] = roles[k] }
        return o
    }
    function _adopt9(target, src) {
        if (!src) return target
        var out = root._clone(target)
        for (var i = 0; i < root._chrome9.length; i++) {
            var k = root._chrome9[i]
            if (typeof src[k] === "string" && src[k].length) out[k] = root._norm(src[k])
        }
        return out
    }
    function _adoptCurrent(cur) {
        root.candDarkRoles = root._adopt9(root.candDarkRoles, cur)
        root.candLightRoles = root._adopt9(root.candLightRoles, cur)
        root._markSaved()
        root._loadRole()
    }
    function _adoptVariants(res) {
        if (res.dark) root.candDarkRoles = root._adopt9(root.candDarkRoles, res.dark)
        if (res.light) root.candLightRoles = root._adopt9(root.candLightRoles, res.light)
        root._markSaved()
    }

    function _syncHex() { if (!hexField.editing) hexField.text = root._current(root.selRole) }
    function _adoptEdit() {
        var hsv = root._rgbToHsv(root._current(root.selRole))
        root.editH = hsv.h; root.editS = hsv.s; root.editV = hsv.v
        root._syncHex()
    }
    function _loadRole() { root.loadedHex = root._current(root.selRole); root._adoptEdit() }
    function _selectRole(mat) { root.selRole = mat; root._loadRole() }
    function _setVariant(dark) { if (root.candDark === dark) return; root.candDark = dark; root._loadRole() }
    function _commitHsv() {
        root._setRoleColour(root.selRole, root._hsvToHex(root.editH, root.editS, root.editV))
        root.activePreset = ""
        root._syncHex()
    }
    function _applyHex(t) {
        if (!root._validHex(t)) { root.state.toast(I18n.tr("Enter a colour as #rrggbb."), "error"); return }
        root._setRoleColour(root.selRole, root._clean(t))
        root.activePreset = ""
        root._adoptEdit()
    }
    function _resetColour() { root._setRoleColour(root.selRole, root.loadedHex); root.activePreset = ""; root._adoptEdit() }
    function _pushRecent(hex) {
        if (!hex) return
        var out = [hex]
        for (var i = 0; i < root.recents.length && out.length < 8; i++) if (root.recents[i] !== hex) out.push(root.recents[i])
        root.recents = out
    }
    function _applyRecent(hex) { root._setRoleColour(root.selRole, hex); root.activePreset = ""; root._adoptEdit() }

    function _applyPreset(key) {
        var p = Theme.presets[key]
        if (!p) return
        root.activePreset = key
        var d = root._clone(root.candDarkRoles), l = root._clone(root.candLightRoles)
        for (var i = 0; i < root._chrome9.length; i++) {
            var k = root._chrome9[i]
            d[k] = root._norm(p[k]); l[k] = root._norm(p[k])
        }
        root.candDarkRoles = d; root.candLightRoles = l
        root._loadRole()
    }
    function _derive() { root._setRoleColour("primary", root._current(root.selRole)); root.activePreset = ""; root._adoptEdit() }

    function _snapshot() { return JSON.stringify({ d: root.candDarkRoles, l: root.candLightRoles }) }
    function _markSaved() { root._baseline = root._snapshot() }
    function _resetChanges() {
        if (!root._baseline) return
        var b = JSON.parse(root._baseline)
        root.candDarkRoles = b.d; root.candLightRoles = b.l
        root._loadRole()
    }

    function _pushPreview() { if (root.shown) { try { Theme.previewPalette = root._previewMap } catch (e) {} } }
    function _clearPreview() { try { Theme.previewPalette = null } catch (e) {} }
    onCandDarkRolesChanged: root._pushPreview()
    onCandLightRolesChanged: root._pushPreview()
    onCandDarkChanged: root._pushPreview()

    function _loadLibrary() {
        root.loadingLib = true
        root.libError = ""
        Daemon.call("theme.designer.load", ({}), function(res, err) {
            root.loadingLib = false
            if (err) { root.libError = (err.message || I18n.tr("Saved palettes could not be loaded.")); return }
            root.savedPalettes = (res && res.saved) ? res.saved : []
            if (res && res.current) root._adoptCurrent(res.current)
        })
    }
    function _loadSaved(name) {
        Daemon.call("theme.designer.load", { name: name }, function(res, err) {
            if (err) { root.state.toast(err.message || I18n.tr("That palette could not be loaded."), "error"); return }
            if (res) { root._adoptVariants(res); root.nameText = res.name || name; root.activePreset = ""; root._loadRole() }
        })
    }
    function _save(apply) {
        var nm = root.nameText.trim()
        if (!nm) return
        Daemon.call("theme.designer.save", { name: nm, dark: root._payload9(root.candDarkRoles), light: root._payload9(root.candLightRoles) }, function(res, err) {
            if (err) { root.state.toast(err.message || I18n.tr("This palette could not be saved."), "error"); return }
            root._markSaved()
            root._loadLibrary()
            if (apply) {
                Settings.set("theme.policy", "fixed")
                Settings.set("theme.staticTheme", nm)
            }
            root.state.toast(apply ? I18n.tr("Palette saved and applied.") : I18n.tr("Palette saved."), "success")
        })
    }
    function _delete(name) {
        Daemon.call("theme.designer.delete", { name: name }, function(res, err) {
            if (err) { root.state.toast(err.message || I18n.tr("That palette could not be deleted."), "error"); return }
            root._loadLibrary()
        })
    }

    function _refreshWallpaper() {
        Library.refreshOutputs()
        var outs = Library.outputs || []
        var cur = null
        for (var i = 0; i < outs.length; i++) { if (outs[i].focused) { cur = outs[i].current; break } }
        if (!cur && outs.length) cur = outs[0].current
        root._wpEntry = (cur && cur.key) ? Library.entry("wallpapers", cur.key) : null
    }
    function _loadCurrent() { root._seedCandidate(); root._loadRole() }
    function _saveWallpaper() { if (!root._wpEntry) return; root.nameText = (root._wpEntry.name || root._wpEntry.key); root._save(false) }

    function _stripColours(entry) {
        var src = (entry && entry.dark) ? entry.dark : ((entry && entry.light) ? entry.light : null)
        var out = []
        for (var i = 0; i < root._chrome9.length; i++) { var k = root._chrome9[i]; out.push((src && src[k]) ? src[k] : Theme[k]) }
        return out
    }

    function _open() {
        root._seedCandidate()
        root.selRole = "primary"
        root._loadRole()
        root._pushPreview()
        root._loadLibrary()
        root._refreshWallpaper()
    }
    onShownChanged: { if (root.shown) root._open(); else root._clearPreview() }

    Connections {
        target: Library
        function onOutputsChanged() { root._refreshWallpaper() }
    }

    Keys.onEscapePressed: root.closeRequested()

    FolioSheet {
        id: sheet
        reveal: root._reveal
        showMasthead: false
        onDismissed: root.closeRequested()

        FolioIndexShell {
            id: indexShell
            parent: sheet.indexArea
            anchors.fill: parent
            title: I18n.tr("Palette index")
            note: root.roleDefs.length + " " + I18n.tr("colour roles for the Wall interface and app integrations.")

            Item {
                parent: indexShell.body
                anchors.fill: parent

                TextField {
                    id: searchField
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    variant: "workbench"
                    glyph: "\uf002"
                    placeholder: I18n.tr("Search colours")
                    onEdited: (t) => root.roleQuery = t
                    onCommitted: (t) => root.roleQuery = t
                }

                Flickable {
                    id: roleFlick
                    anchors.top: searchField.bottom
                    anchors.topMargin: 13 * Theme.scale
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: footer.top
                    anchors.bottomMargin: 13 * Theme.scale
                    contentWidth: width
                    contentHeight: groupsCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: groupsCol
                        width: roleFlick.width
                        spacing: 4 * Theme.scale

                        Repeater {
                            model: root.groupOrder
                            delegate: Column {
                                id: groupCol
                                required property string modelData
                                readonly property var rolesInGroup: root._rolesIn(modelData, root.roleQuery)
                                width: groupsCol.width
                                spacing: 2 * Theme.scale
                                visible: rolesInGroup.length > 0

                                Text {
                                    leftPadding: 12 * Theme.scale
                                    topPadding: 7 * Theme.scale
                                    bottomPadding: 3 * Theme.scale
                                    text: root._groupLabel(groupCol.modelData)
                                    font.family: Theme.sans
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Theme.fontSmall
                                    color: Theme.surfaceText
                                    renderType: Text.NativeRendering
                                }

                                Repeater {
                                    model: groupCol.rolesInGroup
                                    delegate: ThemeRoleRow {
                                        required property var modelData
                                        width: groupsCol.width
                                        roleName: modelData.name
                                        roleKey: modelData.key
                                        swatch: root._current(modelData.key)
                                        hex: root._current(modelData.key)
                                        active: root.selRole === modelData.key
                                        onClicked: root._selectRole(modelData.key)
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    id: footer
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 4 * Theme.scale

                    FolioRule { width: parent.width; alpha: 0.5 }
                    Text {
                        width: parent.width
                        text: root._selName()
                        font.family: Theme.sans; font.weight: Font.DemiBold
                        font.pixelSize: Theme.fontSmall
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.selRole
                        font.family: Theme.sans; font.weight: Font.Medium
                        font.pixelSize: Theme.fontMini
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root._selDesc()
                        font.family: Theme.sans; font.weight: Font.Normal
                        font.pixelSize: Theme.fontBase
                        color: Theme.withAlpha(Theme.surfaceText, 0.5)
                        lineHeight: 1.4
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        Flickable {
            id: flick
            parent: sheet.readingArea
            anchors.fill: parent
            contentWidth: width
            contentHeight: readCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: readCol
                width: flick.width
                topPadding: 34 * Theme.scale
                leftPadding: 38 * Theme.scale
                rightPadding: 38 * Theme.scale
                bottomPadding: 48 * Theme.scale
                spacing: 28 * Theme.scale

                Column {
                    width: root._pageW
                    spacing: 7 * Theme.scale

                    Item {
                        width: parent.width
                        height: titleText.implicitHeight

                        Text {
                            id: titleText
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Theme designer")
                            font.family: Theme.display
                            font.pixelSize: Theme.fontSection
                            lineHeight: 1.0
                            color: Theme.surfaceText
                            renderType: Text.NativeRendering
                        }
                        FolioAction {
                            anchors.right: parent.right
                            anchors.verticalCenter: titleText.verticalCenter
                            label: "\u00d7"
                            minWidth: 34
                            onTriggered: root.closeRequested()
                        }
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("Edit the full colour scheme, preview the Wall interface, and save both variants.")
                        font.family: Theme.sans; font.weight: Font.Normal
                        font.pixelSize: Theme.fontXSmall
                        color: Theme.withAlpha(Theme.surfaceText, 0.56)
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                    FolioRule { width: parent.width; alpha: 0.58 }
                }

                GridLayout {
                    width: root._pageW
                    columns: root._compact ? 1 : 2
                    columnSpacing: 34 * Theme.scale
                    rowSpacing: 28 * Theme.scale

                    Column {
                        id: wheelEditor
                        Layout.fillWidth: false
                        Layout.preferredWidth: root._compact ? root._pageW : (root._pageW - 34 * Theme.scale) * 5 / 12
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: root._compact ? root._pageW : (root._pageW - 34 * Theme.scale) * 5 / 12
                        Layout.alignment: Qt.AlignTop
                        spacing: 11 * Theme.scale

                        RowLayout {
                            width: wheelEditor.width
                            spacing: 8 * Theme.scale
                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Colour field")
                                font.family: Theme.sans; font.weight: Font.DemiBold
                                font.pixelSize: Theme.fontField
                                color: Theme.surfaceText
                                renderType: Text.NativeRendering
                            }
                            ChoiceButtons {
                                options: [
                                    { value: true, label: I18n.tr("Dark") },
                                    { value: false, label: I18n.tr("Light") }
                                ]
                                value: root.candDark
                                onSelected: (v) => root._setVariant(v)
                            }
                        }

                        Text {
                            width: wheelEditor.width
                            text: I18n.tr("Choose hue on the ring, then saturation and light inside the field.")
                            font.family: Theme.sans; font.weight: Font.Normal
                            font.pixelSize: Theme.fontXSmall
                            color: Theme.withAlpha(Theme.surfaceText, 0.56)
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }

                        Item {
                            width: wheelEditor.width
                            height: 184 * Theme.scale
                            ColorWheel {
                                id: colorWheel
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 184 * Theme.scale
                                height: 184 * Theme.scale
                                hsv: ({ h: root.editH, s: root.editS, v: root.editV })
                                onHue: (deg) => {
                                    root.editH = deg
                                    if (root.editS <= 0.001) root.editS = 0.5
                                    if (root.editV <= 0.001) root.editV = 0.5
                                    root._commitHsv()
                                }
                                onSv: (s, v) => { root.editS = s; root.editV = v; root._commitHsv() }
                                onDragEnd: root._pushRecent(root._current(root.selRole))
                            }
                        }

                        RowLayout {
                            width: wheelEditor.width
                            spacing: 8 * Theme.scale
                            Rectangle {
                                Layout.preferredWidth: 42 * Theme.scale
                                Layout.preferredHeight: 30 * Theme.scale
                                color: root._current(root.selRole)
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.outline, 0.5)
                            }
                            TextField {
                                id: hexField
                                Layout.preferredWidth: 138 * Theme.scale
                                variant: "workbench"
                                placeholder: I18n.tr("#rrggbb")
                                onCommitted: (t) => root._applyHex(t)
                            }
                            FolioAction {
                                label: I18n.tr("Set colour")
                                active: true
                                onTriggered: root._applyHex(hexField.text)
                            }
                        }

                        RowLayout {
                            width: wheelEditor.width
                            spacing: 8 * Theme.scale
                            FolioAction {
                                label: I18n.tr("Reset colour")
                                enabled: root._colourChanged
                                onTriggered: root._resetColour()
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: I18n.tr("Last loaded")
                                font.family: Theme.sans; font.weight: Font.Medium
                                font.pixelSize: Theme.fontMini
                                color: Theme.withAlpha(Theme.surfaceText, 0.56)
                                renderType: Text.NativeRendering
                            }
                            Rectangle {
                                Layout.preferredWidth: 18 * Theme.scale
                                Layout.preferredHeight: 14 * Theme.scale
                                color: root.loadedHex
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.outline, 0.5)
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: root.loadedHex
                                font.family: Theme.display
                                font.pixelSize: Theme.fontFine
                                color: Theme.withAlpha(Theme.surfaceText, 0.46)
                                renderType: Text.NativeRendering
                            }
                        }

                        FolioRule { width: wheelEditor.width; alpha: 0.36 }

                        Text {
                            text: I18n.tr("Recent")
                            font.family: Theme.sans; font.weight: Font.DemiBold
                            font.pixelSize: Theme.fontFine
                            color: Theme.surfaceText
                            renderType: Text.NativeRendering
                        }

                        Flow {
                            width: wheelEditor.width
                            spacing: 7 * Theme.scale
                            visible: root.recents.length > 0
                            Repeater {
                                model: root.recents
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 28 * Theme.scale
                                    height: 20 * Theme.scale
                                    color: modelData
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.outline, 0.5)
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root._applyRecent(modelData)
                                    }
                                }
                            }
                        }
                        Text {
                            visible: root.recents.length === 0
                            width: wheelEditor.width
                            text: I18n.tr("Colours used during this edit appear here.")
                            font.family: Theme.sans; font.weight: Font.Normal
                            font.pixelSize: Theme.fontFine
                            color: Theme.withAlpha(Theme.surfaceText, 0.42)
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }
                    }

                    Column {
                        id: previewCol
                        Layout.fillWidth: false
                        Layout.preferredWidth: root._compact ? root._pageW : (root._pageW - 34 * Theme.scale) * 7 / 12
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: root._compact ? root._pageW : (root._pageW - 34 * Theme.scale) * 7 / 12
                        Layout.alignment: Qt.AlignTop
                        spacing: 9 * Theme.scale

                        Text {
                            text: I18n.tr("Settings preview")
                            font.family: Theme.sans; font.weight: Font.DemiBold
                            font.pixelSize: Theme.fontField
                            color: Theme.surfaceText
                            renderType: Text.NativeRendering
                        }
                        Text {
                            width: previewCol.width
                            text: I18n.tr("This preview uses all nine colours across navigation, controls, fields, cards, and status messages.")
                            font.family: Theme.sans; font.weight: Font.Normal
                            font.pixelSize: Theme.fontXSmall
                            color: Theme.withAlpha(Theme.surfaceText, 0.56)
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }
                        ThemePreviewPane {
                            width: previewCol.width
                            palette: root._previewMap
                            editingRole: root._selName()
                        }
                    }
                }

                GridLayout {
                    width: root._pageW
                    columns: root._compact ? 1 : 2
                    columnSpacing: 34 * Theme.scale
                    rowSpacing: 28 * Theme.scale

                    Column {
                        id: mgmtLeft
                        Layout.fillWidth: false
                        Layout.preferredWidth: root._compact ? root._pageW : (root._pageW - 34 * Theme.scale) / 2
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: root._compact ? root._pageW : (root._pageW - 34 * Theme.scale) / 2
                        Layout.alignment: Qt.AlignTop
                        spacing: 28 * Theme.scale

                        Column {
                            width: mgmtLeft.width
                            spacing: 9 * Theme.scale
                            FolioRule { width: parent.width; alpha: 0.58 }
                            Text {
                                text: I18n.tr("Starting palette")
                                font.family: Theme.sans; font.weight: Font.DemiBold
                                font.pixelSize: Theme.fontField
                                color: Theme.surfaceText
                                renderType: Text.NativeRendering
                            }
                            Text {
                                width: parent.width
                                text: I18n.tr("Open a preset, or build a palette from the colour selected above.")
                                font.family: Theme.sans; font.weight: Font.Normal
                                font.pixelSize: Theme.fontXSmall
                                color: Theme.withAlpha(Theme.surfaceText, 0.56)
                                wrapMode: Text.WordWrap
                                renderType: Text.NativeRendering
                            }
                            ChoiceButtons {
                                width: mgmtLeft.width
                                options: root._presetOptions
                                value: root.activePreset
                                showStrip: true
                                onSelected: (v) => root._applyPreset(v)
                            }
                            FolioAction {
                                label: I18n.tr("Derive from colour")
                                onTriggered: root._derive()
                            }
                        }

                        Column {
                            width: mgmtLeft.width
                            spacing: 9 * Theme.scale
                            FolioRule { width: parent.width; alpha: 0.58 }
                            Text {
                                text: I18n.tr("Save palette")
                                font.family: Theme.sans; font.weight: Font.DemiBold
                                font.pixelSize: Theme.fontField
                                color: Theme.surfaceText
                                renderType: Text.NativeRendering
                            }
                            Text {
                                width: parent.width
                                text: I18n.tr("Name this palette to save both variants. Save + apply uses the variant selected above.")
                                font.family: Theme.sans; font.weight: Font.Normal
                                font.pixelSize: Theme.fontXSmall
                                color: Theme.withAlpha(Theme.surfaceText, 0.56)
                                wrapMode: Text.WordWrap
                                renderType: Text.NativeRendering
                            }
                            TextField {
                                id: nameField
                                width: mgmtLeft.width
                                variant: "workbench"
                                placeholder: I18n.tr("Palette name")
                                onEdited: (t) => root.nameText = t
                                onCommitted: (t) => { root.nameText = t; root._save(false) }
                            }
                            RowLayout {
                                width: mgmtLeft.width
                                spacing: 8 * Theme.scale
                                FolioAction {
                                    label: I18n.tr("Save")
                                    enabled: root.nameText.trim().length > 0
                                    onTriggered: root._save(false)
                                }
                                FolioAction {
                                    label: I18n.tr("Save + apply")
                                    active: root.nameText.trim().length > 0
                                    enabled: root.nameText.trim().length > 0
                                    onTriggered: root._save(true)
                                }
                                Item { Layout.fillWidth: true }
                                FolioDestructiveAction {
                                    visible: root._dirty
                                    confirm: true
                                    label: I18n.tr("Reset changes")
                                    onTriggered: root._resetChanges()
                                }
                            }
                        }
                    }

                    Column {
                        id: mgmtRight
                        Layout.fillWidth: false
                        Layout.preferredWidth: root._compact ? root._pageW : (root._pageW - 34 * Theme.scale) / 2
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: root._compact ? root._pageW : (root._pageW - 34 * Theme.scale) / 2
                        Layout.alignment: Qt.AlignTop
                        spacing: 28 * Theme.scale

                        Column {
                            width: mgmtRight.width
                            spacing: 9 * Theme.scale
                            FolioRule { width: parent.width; alpha: 0.58 }
                            Text {
                                text: I18n.tr("Current wallpaper")
                                font.family: Theme.sans; font.weight: Font.DemiBold
                                font.pixelSize: Theme.fontField
                                color: Theme.surfaceText
                                renderType: Text.NativeRendering
                            }
                            Text {
                                width: parent.width
                                text: I18n.tr("Save both dark and light variants for the wallpaper supplying your desktop theme.")
                                font.family: Theme.sans; font.weight: Font.Normal
                                font.pixelSize: Theme.fontXSmall
                                color: Theme.withAlpha(Theme.surfaceText, 0.56)
                                wrapMode: Text.WordWrap
                                renderType: Text.NativeRendering
                            }

                            RowLayout {
                                width: mgmtRight.width
                                spacing: 9 * Theme.scale
                                visible: root._wpEntry !== null
                                Image {
                                    Layout.preferredWidth: 104 * Theme.scale
                                    Layout.preferredHeight: 68 * Theme.scale
                                    fillMode: Image.PreserveAspectCrop
                                    clip: true
                                    asynchronous: true
                                    cache: true
                                    source: Library.fileUrl(root._wpEntry ? root._wpEntry.thumb : "")
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8 * Theme.scale
                                    Text {
                                        Layout.fillWidth: true
                                        text: root._wpEntry ? (root._wpEntry.name || root._wpEntry.key) : ""
                                        elide: Text.ElideRight
                                        font.family: Theme.sans; font.weight: Font.DemiBold
                                        font.pixelSize: Theme.fontLabel
                                        color: Theme.surfaceText
                                        renderType: Text.NativeRendering
                                    }
                                    RowLayout {
                                        spacing: 8 * Theme.scale
                                        FolioAction {
                                            label: I18n.tr("Load current")
                                            onTriggered: root._loadCurrent()
                                        }
                                        FolioAction {
                                            label: I18n.tr("Save for this wallpaper")
                                            active: true
                                            onTriggered: root._saveWallpaper()
                                        }
                                    }
                                }
                            }

                            Column {
                                width: mgmtRight.width
                                spacing: 9 * Theme.scale
                                visible: root._wpEntry === null
                                Text {
                                    width: parent.width
                                    text: I18n.tr("No wallpaper palette is available yet.")
                                    font.family: Theme.sans; font.weight: Font.Normal
                                    font.pixelSize: Theme.fontBase
                                    color: Theme.withAlpha(Theme.surfaceText, 0.56)
                                    wrapMode: Text.WordWrap
                                    renderType: Text.NativeRendering
                                }
                                FolioAction {
                                    label: I18n.tr("Load current")
                                    onTriggered: root._loadCurrent()
                                }
                            }

                            Text {
                                visible: root.libError.length > 0
                                width: parent.width
                                text: root.libError
                                font.family: Theme.sans; font.weight: Font.Normal
                                font.pixelSize: Theme.fontBase
                                color: Theme.tertiary
                                wrapMode: Text.WordWrap
                                renderType: Text.NativeRendering
                            }
                        }

                        Column {
                            width: mgmtRight.width
                            spacing: 9 * Theme.scale
                            FolioRule { width: parent.width; alpha: 0.58 }
                            RowLayout {
                                width: mgmtRight.width
                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Saved palettes")
                                    font.family: Theme.sans; font.weight: Font.DemiBold
                                    font.pixelSize: Theme.fontField
                                    color: Theme.surfaceText
                                    renderType: Text.NativeRendering
                                }
                                Text {
                                    text: root.savedPalettes.length + " " + I18n.tr("custom")
                                    font.family: Theme.sans; font.weight: Font.Medium
                                    font.pixelSize: Theme.fontFine
                                    color: Theme.withAlpha(Theme.surfaceText, 0.44)
                                    renderType: Text.NativeRendering
                                }
                            }
                            Text {
                                width: parent.width
                                text: I18n.tr("Open a saved palette to edit its full dark and light schemes.")
                                font.family: Theme.sans; font.weight: Font.Normal
                                font.pixelSize: Theme.fontMini
                                color: Theme.withAlpha(Theme.surfaceText, 0.56)
                                wrapMode: Text.WordWrap
                                renderType: Text.NativeRendering
                            }

                            Text {
                                visible: root.loadingLib
                                text: I18n.tr("Loading saved palettes\u2026")
                                font.family: Theme.sans; font.weight: Font.Medium
                                font.pixelSize: Theme.fontBase
                                color: Theme.withAlpha(Theme.surfaceText, 0.6)
                                renderType: Text.NativeRendering
                            }
                            Text {
                                visible: !root.loadingLib && root.savedPalettes.length === 0 && root.libError.length === 0
                                width: parent.width
                                text: I18n.tr("No custom palettes yet. Name the current palette and save it to add the first one.")
                                font.family: Theme.sans; font.weight: Font.Normal
                                font.pixelSize: Theme.fontBase
                                color: Theme.withAlpha(Theme.surfaceText, 0.48)
                                wrapMode: Text.WordWrap
                                renderType: Text.NativeRendering
                            }

                            Column {
                                width: mgmtRight.width
                                spacing: 7 * Theme.scale
                                visible: !root.loadingLib && root.savedPalettes.length > 0

                                Repeater {
                                    model: root.savedPalettes
                                    delegate: RowLayout {
                                        id: savedRow
                                        required property var modelData
                                        readonly property var entry: modelData
                                        width: mgmtRight.width
                                        spacing: 8 * Theme.scale

                                        Item {
                                            Layout.fillWidth: true
                                            implicitHeight: 30 * Theme.scale

                                            Rectangle {
                                                anchors.fill: parent
                                                color: (savedRow.entry.name === root.nameText) ? Theme.withAlpha(Theme.surfaceText, 0.09)
                                                     : loadHover.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.05)
                                                     : "transparent"
                                            }
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 7 * Theme.scale
                                                anchors.rightMargin: 7 * Theme.scale
                                                spacing: 8 * Theme.scale
                                                Rectangle {
                                                    Layout.preferredWidth: 6 * Theme.scale
                                                    Layout.preferredHeight: 6 * Theme.scale
                                                    radius: 3 * Theme.scale
                                                    color: (savedRow.entry.name === root.nameText) ? Theme.withAlpha(Theme.surfaceText, 0.9) : "transparent"
                                                    border.width: (savedRow.entry.name === root.nameText) ? 0 : 1
                                                    border.color: Theme.withAlpha(Theme.surfaceText, 0.4)
                                                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: savedRow.entry.name
                                                    elide: Text.ElideRight
                                                    font.family: Theme.sans; font.weight: (savedRow.entry.name === root.nameText) ? Font.DemiBold : Font.Medium
                                                    font.pixelSize: Theme.fontWide
                                                    color: Theme.surfaceText
                                                    renderType: Text.NativeRendering
                                                }
                                                Row {
                                                    spacing: 0
                                                    Repeater {
                                                        model: root._stripColours(savedRow.entry)
                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            width: 10 * Theme.scale
                                                            height: 15 * Theme.scale
                                                            color: modelData
                                                        }
                                                    }
                                                }
                                            }
                                            MouseArea {
                                                id: loadHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root._loadSaved(savedRow.entry.name)
                                            }
                                        }

                                        FolioDestructiveAction {
                                            confirm: true
                                            label: "\u00d7"
                                            minWidth: 34
                                            onTriggered: root._delete(savedRow.entry.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
