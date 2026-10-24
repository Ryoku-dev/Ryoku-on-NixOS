import QtQuick
import QtQuick.Layouts
import stage
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import Ryoku.Ui as Ui
import Ryoku.Ui.Singletons

ColumnLayout {
    id: root

    signal fieldFocusRequested(Item field)
    signal fieldFocusReleased()

    spacing: Tokens.s3

    property bool saving: false
    property string renamingPreset: ""
    property string applyingPreset: ""
    property var pendingBefore: null
    property var pendingAfter: null
    property string applyError: ""

    readonly property string monitorName: String(Config.widgetProvider?.monitor ?? "")
    readonly property string activePreset: root.matchingPreset()

    function cleanName(value) {
        return PresetStore.cleanName(value);
    }

    function currentWallpaper() {
        const selected = Wallpapers.currentWallpaperPath(root.monitorName);
        return String(selected || Wallpapers.effectiveWallpaperPath || "");
    }

    function captureSnapshot() {
        const palette = MaterialThemeLoader.snapshot();
        return {
            wallpaper: root.currentWallpaper(),
            theme: palette.themeName,
            mode: palette.mode,
            schemeType: palette.schemeType,
            sourceColorIndex: palette.sourceColorIndex
        };
    }

    function paletteState(snapshot) {
        return {
            themeName: String(snapshot.theme ?? "Wallpaper"),
            mode: String(snapshot.mode ?? "smart"),
            schemeType: String(snapshot.schemeType ?? "scheme-tonal-spot"),
            sourceColorIndex: Number(snapshot.sourceColorIndex ?? 0)
        };
    }

    function sameSnapshot(left, right) {
        return String(left.wallpaper ?? "") === String(right.wallpaper ?? "")
            && String(left.theme ?? "Wallpaper") === String(right.theme ?? "Wallpaper")
            && String(left.mode ?? "smart") === String(right.mode ?? "smart")
            && String(left.schemeType ?? "scheme-tonal-spot")
                === String(right.schemeType ?? "scheme-tonal-spot")
            && Number(left.sourceColorIndex ?? 0) === Number(right.sourceColorIndex ?? 0);
    }

    function matchingPreset() {
        const current = root.captureSnapshot();
        for (const preset of PresetStore.presets) {
            if (root.sameSnapshot(current, preset))
                return String(preset.name ?? "");
        }
        return "";
    }

    function commitPresetList(before, after) {
        PresetStore.replace(after);
        GlobalStates.editHistoryPush({
            "undo": () => PresetStore.replace(before),
            "redo": () => PresetStore.replace(after)
        });
    }

    function savePreset() {
        const name = root.cleanName(nameField.text);
        if (name === "")
            return;
        root.applyError = "";
        const before = PresetStore.clone(PresetStore.presets);
        const after = PresetStore.clone(before);
        const snapshot = Object.assign(root.captureSnapshot(), {
            name: name,
            updatedAt: Date.now()
        });
        const index = after.findIndex(candidate => candidate.name === name);
        if (index >= 0)
            after[index] = snapshot;
        else
            after.push(snapshot);
        root.commitPresetList(before, after);
        nameField.clear();
        root.saving = false;
        root.fieldFocusReleased();
    }

    function beginRename(name) {
        root.applyError = "";
        root.saving = false;
        nameField.clear();
        root.renamingPreset = name;
        renameField.text = name;
        root.fieldFocusRequested(renameField);
        Qt.callLater(renameField.grabFocus);
    }

    function cancelRename() {
        root.renamingPreset = "";
        renameField.clear();
        root.fieldFocusReleased();
    }

    function commitRename() {
        const beforeName = root.renamingPreset;
        const afterName = root.cleanName(renameField.text);
        if (beforeName === "" || afterName === "")
            return;
        if (beforeName !== afterName
                && PresetStore.presets.some(candidate => candidate.name === afterName)) {
            root.applyError = Translation.tr("That preset name is already in use.");
            return;
        }
        const before = PresetStore.clone(PresetStore.presets);
        const after = PresetStore.clone(before);
        const index = after.findIndex(candidate => candidate.name === beforeName);
        if (index < 0)
            return;
        after[index].name = afterName;
        after[index].updatedAt = Date.now();
        root.commitPresetList(before, after);
        root.cancelRename();
    }

    function deletePreset(name) {
        root.applyError = "";
        const before = PresetStore.clone(PresetStore.presets);
        const after = before.filter(candidate => candidate.name !== name);
        if (after.length === before.length)
            return;
        root.commitPresetList(before, after);
        if (root.renamingPreset === name)
            root.cancelRename();
    }

    function restoreSnapshot(snapshot) {
        MaterialThemeLoader.applyState(root.paletteState(snapshot), false);
        const wallpaper = String(snapshot.wallpaper ?? "");
        if (wallpaper !== "")
            Wallpapers.applyForScreen(wallpaper, root.monitorName,
                String(snapshot.mode ?? "") === "dark");
    }

    function applyPreset(name) {
        if (name === root.activePreset || root.applyingPreset !== ""
                || MaterialThemeLoader.busy)
            return;
        const preset = PresetStore.presets.find(candidate => candidate.name === name);
        if (!preset)
            return;
        root.applyError = "";
        root.applyingPreset = name;
        root.pendingBefore = root.captureSnapshot();
        root.pendingAfter = PresetStore.clone(preset);
        MaterialThemeLoader.applyState(root.paletteState(preset), false,
            "stage-preset:" + name);
    }

    function presetSummary(preset) {
        const theme = String(preset.theme ?? "Wallpaper");
        if (theme !== "Wallpaper")
            return theme;
        const scheme = String(preset.schemeType ?? "scheme-tonal-spot")
            .replace(/^scheme-/, "").replace(/-/g, " ");
        return scheme + " · " + String(preset.mode ?? "smart");
    }

    Connections {
        target: MaterialThemeLoader
        function onApplyFinished(tag, ok, error) {
            if (!String(tag).startsWith("stage-preset:"))
                return;
            const before = root.pendingBefore;
            const after = root.pendingAfter;
            root.applyingPreset = "";
            root.pendingBefore = null;
            root.pendingAfter = null;
            if (!ok || !before || !after) {
                root.applyError = error || Translation.tr("The preset could not be applied.");
                return;
            }

            const wallpaper = String(after.wallpaper ?? "");
            if (wallpaper !== "")
                Wallpapers.applyForScreen(wallpaper, root.monitorName,
                    String(after.mode ?? "") === "dark");
            GlobalStates.editHistoryPush({
                "undo": () => root.restoreSnapshot(before),
                "redo": () => root.restoreSnapshot(after)
            });
        }
    }

    Ui.SettingCard {
        Layout.fillWidth: true
        title: Translation.tr("SAVED LOOKS")
        collapsible: false

        Ui.SettingRow {
            width: parent.width
            label: Translation.tr("Save current look")
            desc: Translation.tr("Wallpaper, theme and colour controls")
            enabled: PresetStore.ready
            controlWidth: saveToggle.implicitWidth

            Ui.Btn {
                id: saveToggle
                anchors.fill: parent
                text: root.saving ? Translation.tr("Cancel") : Translation.tr("Save")
                compact: true
                onAct: {
                    root.saving = !root.saving;
                    root.renamingPreset = "";
                    renameField.clear();
                    if (root.saving) {
                        root.fieldFocusRequested(nameField);
                        Qt.callLater(nameField.grabFocus);
                    } else {
                        nameField.clear();
                        root.fieldFocusReleased();
                    }
                }
            }
        }

        Ui.SettingRow {
            width: parent.width
            visible: root.saving
            label: Translation.tr("Preset name")
            footH: Tokens.ctlH + Tokens.s1

            RowLayout {
                anchors.fill: parent
                spacing: Tokens.s2

                Ui.Field {
                    id: nameField
                    Layout.fillWidth: true
                    placeholder: Translation.tr("e.g. Reading")
                    onAccepted: root.savePreset()
                }
                Ui.Btn {
                    Layout.preferredWidth: implicitWidth
                    Layout.fillHeight: true
                    text: Translation.tr("Add")
                    compact: true
                    primary: true
                    armed: root.cleanName(nameField.text) !== ""
                    onAct: root.savePreset()
                }
            }
        }

        Item {
            width: parent.width
            height: emptyLabel.visible ? Tokens.rowH + Tokens.s2 : 0

            Text {
                id: emptyLabel
                anchors.fill: parent
                anchors.margins: Tokens.s4
                visible: PresetStore.ready && PresetStore.presets.length === 0
                text: Translation.tr("Nothing saved yet.")
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        Repeater {
            model: PresetStore.presets

            delegate: Column {
                id: presetItem
                required property var modelData
                width: parent.width

                readonly property string presetName: String(modelData.name ?? "")
                readonly property bool selected: root.activePreset === presetName
                readonly property bool applying: root.applyingPreset === presetName

                Ui.SettingRow {
                    width: parent.width
                    divider: true
                    label: presetItem.presetName
                    desc: root.presetSummary(presetItem.modelData)
                    value: presetItem.selected ? Translation.tr("ACTIVE")
                        : presetItem.applying ? Translation.tr("APPLYING") : ""
                    changed: presetItem.selected
                    enabled: root.applyingPreset === ""
                        && !MaterialThemeLoader.busy
                    controlWidth: Tokens.s6 * 3 + Tokens.s1 * 2

                    Row {
                        anchors.fill: parent
                        spacing: Tokens.s1

                        Ui.IconBtn {
                            width: Tokens.s6
                            height: Tokens.s6
                            glyph: "✓"
                            armed: !presetItem.selected
                            onAct: root.applyPreset(presetItem.presetName)
                            HoverHandler { id: applyHover }
                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: applyHover.hovered
                                text: Translation.tr("Apply preset")
                            }
                        }
                        Ui.IconBtn {
                            width: Tokens.s6
                            height: Tokens.s6
                            glyph: "✎"
                            onAct: root.beginRename(presetItem.presetName)
                            HoverHandler { id: renameHover }
                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: renameHover.hovered
                                text: Translation.tr("Rename preset")
                            }
                        }
                        Ui.IconBtn {
                            width: Tokens.s6
                            height: Tokens.s6
                            glyph: "×"
                            onAct: root.deletePreset(presetItem.presetName)
                            HoverHandler { id: deleteHover }
                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: deleteHover.hovered
                                text: Translation.tr("Delete preset")
                            }
                        }
                    }
                }

            }
        }

        Ui.SettingRow {
            width: parent.width
            visible: root.renamingPreset !== ""
            label: Translation.tr("Rename %1").arg(root.renamingPreset)
            footH: Tokens.s6

            RowLayout {
                anchors.fill: parent
                spacing: Tokens.s2

                Ui.Field {
                    id: renameField
                    Layout.fillWidth: true
                    placeholder: Translation.tr("Preset name")
                    onAccepted: root.commitRename()
                }
                Ui.IconBtn {
                    Layout.preferredWidth: Tokens.s6
                    Layout.fillHeight: true
                    glyph: "×"
                    onAct: root.cancelRename()
                    HoverHandler { id: cancelRenameHover }
                    StyledToolTip {
                        extraVisibleCondition: false
                        alternativeVisibleCondition: cancelRenameHover.hovered
                        text: Translation.tr("Cancel rename")
                    }
                }
                Ui.IconBtn {
                    Layout.preferredWidth: Tokens.s6
                    Layout.fillHeight: true
                    glyph: "✓"
                    armed: root.cleanName(renameField.text) !== ""
                    onAct: root.commitRename()
                    HoverHandler { id: saveRenameHover }
                    StyledToolTip {
                        extraVisibleCondition: false
                        alternativeVisibleCondition: saveRenameHover.hovered
                        text: Translation.tr("Save name")
                    }
                }
            }
        }
    }

    EditPanelNotice {
        Layout.fillWidth: true
        visible: root.applyError !== "" || PresetStore.lastError !== ""
        symbol: "error"
        text: root.applyError !== "" ? root.applyError : PresetStore.lastError
    }
}
