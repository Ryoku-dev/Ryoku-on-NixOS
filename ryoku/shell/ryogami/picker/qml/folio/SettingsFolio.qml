import QtQuick
import Ryoku.Ui.Singletons
import "FolioConditions.js" as Cond
import "FolioActions.js" as Actions

FocusScope {
    id: folio

    required property PickerState state
    property var args
    property bool shown: false
    signal closeRequested()

    anchors.fill: parent
    focus: folio.shown
    onShownChanged: if (folio.shown) { folio._applyArgs(); folio.forceActiveFocus(); }
    // A request for another tab can arrive while the folio is already open.
    onArgsChanged: if (folio.shown) folio._applyArgs()

    // Escape leaves an open search before it closes the sheet.
    Keys.onEscapePressed: (e) => {
        if (folio.searchOpen) {
            folio.searchOpen = false
            folio.query = ""
            folio.forceActiveFocus()
        } else {
            folio.closeRequested()
        }
        e.accepted = true
    }
    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier)) {
            folio.searchOpen = true
            e.accepted = true
        }
    }

    // Pure data, so every tab can live at once.
    PickerTab { id: tPicker }
    FilterTab { id: tFilter }
    PositionTab { id: tPosition }
    DisplaysTab { id: tDisplays }
    MotionTab { id: tMotion }
    PlaybackTab { id: tPlayback }
    PerformanceTab { id: tPerformance }
    LibraryTab { id: tLibrary }
    SourcesTab { id: tSources }
    AutomationTab { id: tAutomation }
    ThemeTab { id: tTheme }
    LightingTab { id: tLighting }
    IntegrationsTab { id: tIntegrations }
    LanguageTab { id: tLanguage }
    readonly property var tabs: [tPicker, tFilter, tPosition, tDisplays, tMotion, tPlayback,
        tPerformance, tLibrary, tSources, tAutomation, tTheme, tLighting, tIntegrations, tLanguage]
    readonly property var lightingController: lighting
    LightingController {
        id: lighting
        active: folio.shown && folio.activeTab && folio.activeTab.tabKey === "lighting"
    }

    property int activeTabIndex: 0
    property int activeSectionIndex: 0
    property bool searchOpen: false
    property string query: ""
    property string jumpControlId: ""

    readonly property var activeTab: folio.tabs[folio.activeTabIndex]
    readonly property var activeSection: (folio.activeTab && folio.activeTab.sections
        && folio.activeSectionIndex < folio.activeTab.sections.length)
        ? folio.activeTab.sections[folio.activeSectionIndex] : null
    readonly property bool isDesign: folio._sectionIsDesign(folio.activeSection)
    // The picker keeps the scene rendered behind the folio for design sections.
    readonly property bool sceneVisible: folio.isDesign
    Binding {
        target: folio.state
        property: "sceneThrough"
        value: folio.shown && folio.sceneVisible
    }

    function _sectionIsDesign(section) {
        if (!section) return false;
        var cs = section.controls || [];
        for (var i = 0; i < cs.length; i++)
            if (cs[i].perMode === true) return true;
        return false;
    }

    property int rev: 0
    readonly property var condCtx: Cond.makeCtx(Settings)
    Connections {
        target: Settings
        function onChanged(key, value) { folio.rev++; }
        function onSchemaChanged() { folio.rev++; }
    }

    FolioOptions { id: folioOptions }

    function _applyArgs() {
        var a = folio.args;
        if (!a) return;
        if (a.tab !== undefined) {
            var ti = folio._tabIndex(a.tab);
            if (ti >= 0) folio.activeTabIndex = ti;
        }
        if (a.section !== undefined) folio.activeSectionIndex = Number(a.section) || 0;
        if (a.control !== undefined) folio.jumpControlId = String(a.control);
    }
    function _tabIndex(id) {
        if (typeof id === "number") return id;
        for (var i = 0; i < folio.tabs.length; i++)
            if (folio.tabs[i].tabKey === id) return i;
        return -1;
    }

    function _selectTab(i) { folio.activeTabIndex = i; folio.activeSectionIndex = 0; folio.jumpControlId = ""; }
    function _selectSection(t, s) { folio.activeTabIndex = t; folio.activeSectionIndex = s; folio.jumpControlId = ""; }
    function _openResult(t, s, cid) {
        folio.activeTabIndex = t; folio.activeSectionIndex = s;
        folio.searchOpen = false; folio.query = "";
        // Reopening the same search result must expand its group again.
        folio.jumpControlId = "";
        Qt.callLater(function () { folio.jumpControlId = cid; });
    }

    property string capturingKey: ""
    property var _captureControl: null
    function captureKeybind(control) {
        folio._captureControl = control;
        folio.capturingKey = control.key ? control.key : "";
    }
    function _conflictFor(chord) {
        var tab = folio.activeTab;
        if (!tab || chord.length === 0) return "";
        var mineKey = folio._captureControl ? folio._captureControl.key : "";
        var secs = tab.sections || [];
        for (var s = 0; s < secs.length; s++) {
            var cs = secs[s].controls || [];
            for (var c = 0; c < cs.length; c++) {
                if (cs[c].kind !== "keybind" || cs[c].key === mineKey) continue;
                if (String(Settings.value(cs[c].key) || "") === chord)
                    return (folio._captureControl ? folio._captureControl.label : "")
                        + " " + I18n.tr("and") + " " + cs[c].label + " " + I18n.tr("both use") + " " + chord + ".";
            }
        }
        return "";
    }

    property bool processPickerOpen: false
    function chooseProcess() { folio.processPickerOpen = true; }
    function _addProcess(name) {
        if (!name || name.length === 0) return;
        var v = Settings.value("playback.processes");
        var arr = Array.isArray(v) ? v.slice() : [];
        if (arr.indexOf(name) < 0) { arr.push(name); Settings.set("playback.processes", arr); }
    }

    property real reveal: folio.shown ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }
    visible: folio.reveal > 0.001

    FolioSheet {
        id: sheet
        reveal: folio.reveal
        showMasthead: false
        pageOpacity: folio.isDesign ? 0.14 : 0.965
        scrimAlpha: folio.isDesign ? 0.2 : 0.68
        onDismissed: folio.closeRequested()

        FolioIndex {
            parent: sheet.indexArea
            anchors.fill: parent
            reveal: folio.reveal
            tabs: folio.tabs
            activeTabIndex: folio.activeTabIndex
            activeSectionIndex: folio.activeSectionIndex
            searchOpen: folio.searchOpen
            query: folio.query
            onSelectTab: (i) => folio._selectTab(i)
            onSelectSection: (t, s) => folio._selectSection(t, s)
            onOpenResult: (t, s, cid) => folio._openResult(t, s, cid)
            onSearchToggled: (open) => folio.searchOpen = open
            onQueryEdited: (t) => folio.query = t
        }

        Loader {
            parent: sheet.readingArea
            anchors.fill: parent
            sourceComponent: folio.isDesign ? studioComp : pageComp
        }
    }

    Component {
        id: pageComp
        FolioPage {
            tab: folio.activeTab
            sectionIndex: folio.activeSectionIndex
            state: folio.state
            options: folioOptions
            host: folio
            condCtx: folio.condCtx
            rev: folio.rev
            jumpControlId: folio.jumpControlId
            onCloseRequested: folio.closeRequested()
        }
    }
    Component {
        id: studioComp
        ShapeStudio {
            tab: folio.activeTab
            sectionIndex: folio.activeSectionIndex
            state: folio.state
            options: folioOptions
            host: folio
            condCtx: folio.condCtx
            rev: folio.rev
            jumpControlId: folio.jumpControlId
            onCloseRequested: folio.closeRequested()
        }
    }

    Loader {
        anchors.fill: parent
        active: folio.capturingKey.length > 0
        sourceComponent: KeybindCapture {
            actionLabel: folio._captureControl ? folio._captureControl.label : ""
            currentBinding: folio.capturingKey.length > 0 ? String(Settings.value(folio.capturingKey) || "") : ""
            conflictFor: folio._conflictFor
            Component.onCompleted: open()
            onSaved: (chord) => { Settings.set(folio.capturingKey, chord); folio.capturingKey = ""; }
            onCleared: { Settings.set(folio.capturingKey, ""); folio.capturingKey = ""; }
            onCancelled: folio.capturingKey = ""
        }
    }

    Loader {
        anchors.fill: parent
        active: folio.processPickerOpen
        sourceComponent: FocusScope {
            anchors.fill: parent
            focus: true
            Component.onCompleted: manual.forceActiveFocus()
            Keys.onEscapePressed: (e) => { folio.processPickerOpen = false; e.accepted = true; }

            Scrim { anchors.fill: parent; alpha: 0.5; onDismissed: folio.processPickerOpen = false }

            ChamferPanel {
                anchors.centerIn: parent
                width: Math.min(parent.width - 80 * Theme.scale, 420 * Theme.scale)
                height: pcol.implicitHeight + 40 * Theme.scale

                Column {
                    id: pcol
                    anchors.centerIn: parent
                    width: parent.width - 44 * Theme.scale
                    spacing: 12 * Theme.scale

                    Text {
                        width: parent.width
                        text: I18n.tr("Add a program to pause for")
                        font.family: Theme.display
                        font.pixelSize: Theme.fontTitle
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("Enter the process name, for example mpv or steam.")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontBase
                        color: Theme.withAlpha(Theme.surfaceText, 0.56)
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                    TextField {
                        id: manual
                        width: parent.width
                        variant: "field"
                        placeholder: I18n.tr("Process name")
                        onCommitted: (t) => { folio._addProcess(t.trim()); folio.processPickerOpen = false; }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 9 * Theme.scale
                        FolioAction {
                            label: I18n.tr("Add")
                            enabled: manual.text.trim().length > 0
                            onTriggered: { folio._addProcess(manual.text.trim()); folio.processPickerOpen = false; }
                        }
                        FolioAction {
                            label: I18n.tr("Cancel")
                            onTriggered: folio.processPickerOpen = false
                        }
                    }
                }
            }
        }
    }
}
