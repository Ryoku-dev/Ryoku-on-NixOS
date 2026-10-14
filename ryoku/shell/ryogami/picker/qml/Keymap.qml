import QtQuick
import "KeyChord.js" as KeyChord

Item {
    id: keymap

    required property PickerState state

    // Scopes owned by another surface (a field, search, the browser) are parsed but not fired here.
    readonly property var _actions: [
        { id: "select",          key: "keys.select",          def: "click",             scope: "everywhere" },
        { id: "apply",           key: "keys.apply",           def: "enter",             scope: "everywhere" },
        { id: "flip",            key: "keys.flip",            def: "right-click",       scope: "everywhere" },
        { id: "reveal",          key: "keys.reveal",          def: "v",                 scope: "everywhere" },
        { id: "favourite",       key: "keys.favourite",       def: "f",                 scope: "everywhere" },
        { id: "effects",         key: "keys.effects",         def: "ctrl+click",        scope: "everywhere" },
        { id: "studio",          key: "keys.studio",          def: "shift+right-click", scope: "everywhere" },
        { id: "sceneProperties", key: "keys.sceneProperties", def: "shift+w",           scope: "everywhere" },
        { id: "playlists",       key: "keys.playlists",       def: "p",                 scope: "everywhere" },
        { id: "settings",        key: "keys.settings",        def: "shift+s",           scope: "everywhere" },
        { id: "help",            key: "keys.help",            def: "?",                 scope: "everywhere" },
        { id: "themePanel",      key: "keys.themePanel",      def: "c",                 scope: "everywhere" },
        { id: "downloads",       key: "keys.downloads",       def: "ctrl+d",            scope: "everywhere" },
        { id: "tagCloud",        key: "keys.tagCloud",        def: "shift+down",        scope: "everywhere" },
        { id: "tagMode",         key: "keys.tagMode",         def: "t",                 scope: "everywhere" },
        { id: "filterBar",       key: "keys.filterBar",       def: "shift+up",          scope: "everywhere" },
        { id: "colorPrev",       key: "keys.colorPrev",       def: "shift+left",        scope: "everywhere" },
        { id: "colorNext",       key: "keys.colorNext",       def: "shift+right",       scope: "everywhere" },
        { id: "typePrev",        key: "keys.typePrev",        def: "shift+tab",         scope: "picker" },
        { id: "typeNext",        key: "keys.typeNext",        def: "tab",               scope: "picker" },
        { id: "sortPrev",        key: "keys.sortPrev",        def: "alt+left",          scope: "everywhere" },
        { id: "sortNext",        key: "keys.sortNext",        def: "alt+right",         scope: "everywhere" },
        { id: "randomRotate",    key: "keys.randomRotate",    def: "ctrl+r",            scope: "everywhere" },
        { id: "searchMode",      key: "keys.searchMode",      def: "ctrl+tab",          scope: "search" },
        { id: "folderPrev",      key: "keys.folderPrev",      def: "ctrl+left",         scope: "everywhere" },
        { id: "folderNext",      key: "keys.folderNext",      def: "ctrl+right",        scope: "everywhere" },
        { id: "folderToggle",    key: "keys.folderToggle",    def: "ctrl+m",            scope: "everywhere" },
        { id: "hiddenFolders",   key: "keys.hiddenFolders",   def: "ctrl+h",            scope: "everywhere" },
        { id: "navLeft",         key: "keys.navLeft",         def: "left",              scope: "everywhere" },
        { id: "navRight",        key: "keys.navRight",        def: "right",             scope: "everywhere" },
        { id: "navUp",           key: "keys.navUp",           def: "up",                scope: "everywhere" },
        { id: "navDown",         key: "keys.navDown",         def: "down",              scope: "everywhere" },
        { id: "autocomplete",    key: "keys.autocomplete",    def: "tab",               scope: "fields" },
        { id: "sourceWallhaven", key: "keys.sourceWallhaven", def: "1",                 scope: "downloads" },
        { id: "sourceSteam",     key: "keys.sourceSteam",     def: "2",                 scope: "downloads" },
        { id: "sourceUnsplash",  key: "keys.sourceUnsplash",  def: "3",                 scope: "downloads" },
        { id: "sourcePexels",    key: "keys.sourcePexels",    def: "4",                 scope: "downloads" },
        { id: "sourceYoutube",   key: "keys.sourceYoutube",   def: "5",                 scope: "downloads" },
        { id: "sourceBing",      key: "keys.sourceBing",      def: "6",                 scope: "downloads" }
    ]

    property var _keyMap: ({})     // canonical key signature -> action id
    property var _mouseMap: ({})   // canonical mouse signature -> action id
    property var _scopes: ({})     // action id -> scope

    property Connections _settingsConn: Connections {
        target: Settings
        function onReadyChanged() { keymap._rebuild() }
        function onChanged(key, value) { if (String(key).indexOf("keys.") === 0) keymap._rebuild() }
    }
    Component.onCompleted: keymap._rebuild()

    function _rebuild() {
        var km = ({})
        var mm = ({})
        var sc = ({})
        for (var i = 0; i < keymap._actions.length; ++i) {
            var a = keymap._actions[i]
            sc[a.id] = a.scope
            var trig = Settings.ready ? Settings.value(a.key) : undefined
            if (trig === undefined || trig === null || trig === "")
                trig = a.def
            var canon = KeyChord.canon(trig)
            if (canon) {
                // Signatures can repeat across scopes; keep the action this router can fire.
                var prev = km[canon]
                if (prev === undefined) {
                    km[canon] = a.id
                } else {
                    var prevPref = (sc[prev] === "everywhere" || sc[prev] === "picker")
                    var newPref = (a.scope === "everywhere" || a.scope === "picker")
                    if (newPref && !prevPref)
                        km[canon] = a.id
                }
            } else {
                var mg = keymap._mouseCanon(trig)
                if (mg)
                    mm[mg] = a.id
            }
        }
        keymap._keyMap = km
        keymap._mouseMap = mm
        keymap._scopes = sc
    }


    function _mouseCanon(trigger) {
        var s = String(trigger).toLowerCase()
        if (s.indexOf("click") < 0)
            return null
        var ctrl = s.indexOf("ctrl") >= 0 || s.indexOf("control") >= 0
        var alt = s.indexOf("alt") >= 0
        var shift = s.indexOf("shift") >= 0
        var btn = (s.indexOf("right-click") >= 0) ? "right" : "left"
        return (ctrl ? "ctrl+" : "") + (alt ? "alt+" : "") + (shift ? "shift+" : "") + btn
    }


    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            keymap.state.goBack()
            event.accepted = true
            return true
        }
        var sig = KeyChord.signature(event)
        if (!sig)
            return false
        var id = keymap._keyMap[sig]
        if (id === undefined)
            return false
        var scope = keymap._scopes[id] || "everywhere"
        if (scope !== "everywhere" && scope !== "picker")
            return false
        keymap._run(id, undefined)
        event.accepted = true
        return true
    }

    function mouseGesture(rightButton, modifiers, row) {
        var ctrl = (modifiers & Qt.ControlModifier) !== 0
        var alt = (modifiers & Qt.AltModifier) !== 0
        var shift = (modifiers & Qt.ShiftModifier) !== 0
        var btn = rightButton ? "right" : "left"
        var mg = (ctrl ? "ctrl+" : "") + (alt ? "alt+" : "") + (shift ? "shift+" : "") + btn
        var id = keymap._mouseMap[mg]
        if (id === undefined)
            return false
        keymap._run(id, row)
        return true
    }

    function _fire(id) { Daemon.call("settings.action", { id: id }) }

    function _run(id, row) {
        var f = keymap.state.field
        if (row === undefined)
            row = f ? f.currentIndex : -1
        switch (id) {
        case "select":
        case "apply": if (row >= 0) keymap.state.applyRow(row, false); break
        case "flip": if (f && row >= 0) f.flip(row); break
        case "reveal": if (f) f.action("reveal"); break
        case "favourite": if (row >= 0) keymap.state.toggleFavourite(row); break
        case "effects": if (row >= 0) keymap.state.applyRow(row, true); break
        case "studio": if (row >= 0) keymap.state.openSheet("effects", { mode: "studio", row: row }); break
        case "sceneProperties": if (row >= 0) keymap.state.openSheet("sceneProperties", { row: row }); break
        case "playlists": keymap.state.openSheet("playlists"); break
        case "settings": keymap.state.openSheet("settings"); break
        case "help": keymap.state.helpOpen = !keymap.state.helpOpen; break
        case "themePanel": keymap.state.themeBarOpen = !keymap.state.themeBarOpen; break
        case "downloads": keymap.state.openBrowser(""); break
        case "tagCloud": keymap.state.searchOpen = !keymap.state.searchOpen; break
        case "tagMode": keymap.state.searchOpen = true; break
        case "filterBar": keymap.state.filterBarToggled = !keymap.state.filterBarToggled; break
        case "searchMode": keymap.state.searchMode = (keymap.state.searchMode === "tags") ? "describe" : "tags"; break
        case "colorPrev": keymap._cycleHue(-1); break
        case "colorNext": keymap._cycleHue(1); break
        case "typePrev": keymap._cycleType(-1); break
        case "typeNext": keymap._cycleType(1); break
        case "sortPrev": keymap._cycleSort(-1); break
        case "sortNext": keymap._cycleSort(1); break
        case "randomRotate": keymap._fire("randomRotate"); break
        case "folderPrev": keymap._fire("folderPrev"); break
        case "folderNext": keymap._fire("folderNext"); break
        case "folderToggle": keymap._folderToggle(); break
        case "hiddenFolders": keymap._fire("hiddenFolders"); break
        case "navLeft": if (f) f.step(-1, 0); break
        case "navRight": if (f) f.step(1, 0); break
        case "navUp": if (f) f.step(0, -1); break
        case "navDown": if (f) f.step(0, 1); break
        case "sourceWallhaven": keymap.state.openBrowser("wallhaven"); break
        case "sourceSteam": keymap.state.openBrowser("steam"); break
        case "sourceUnsplash": keymap.state.openBrowser("unsplash"); break
        case "sourcePexels": keymap.state.openBrowser("pexels"); break
        case "sourceYoutube": keymap.state.openBrowser("youtube"); break
        case "sourceBing": keymap.state.openBrowser("bing"); break
        }
    }

    function _cycleType(dir) {
        if (!keymap.state.view) return
        var order = ["", "static", "video", "we"]
        var idx = order.indexOf(keymap.state.view.typeFilter)
        if (idx < 0) idx = 0
        keymap.state.view.typeFilter = order[(idx + dir + order.length) % order.length]
    }
    function _cycleHue(dir) {
        if (!keymap.state.view) return
        var order = [-1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 99]
        var idx = order.indexOf(keymap.state.view.hueFilter)
        if (idx < 0) idx = 0
        keymap.state.view.hueFilter = order[(idx + dir + order.length) % order.length]
    }
    function _cycleSort(dir) {
        if (!keymap.state.view) return
        var order = ["color", "date", "recent", "applied", "pop", "richness", "minimalist", "res", "name"]
        var idx = order.indexOf(keymap.state.view.sort)
        if (idx < 0) idx = 0
        keymap.state.view.sort = order[(idx + dir + order.length) % order.length]
    }
    function _folderToggle() {
        if (!keymap.state.view) return
        keymap.state.view.folder = (keymap.state.view.folder === "*") ? "" : "*"
    }
}
