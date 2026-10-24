import QtQuick
import QtQuick.Layouts
import Quickshell
import Ryoku.Ui as RyokuUi
import stage
import stage.modules.common
import stage.modules.common.widgets
import stage.services
import shell.services as ShellServices

/**
 * The ii dock design's widgets & buttons: everything on the dock that is not
 * an app. Native widgets, utility tiles, buttons, the widget stack and the
 * folders, as the panel's own rows. An item's deeper options (a timer's
 * durations, a folder feed's path) stay on the item's own menu on the dock.
 */
StyledFlickable {
    id: root

    contentHeight: column.implicitHeight
    clip: true

    function cfg(key, fallback) { return ShellServices.Dock.designCfg("ii", key, fallback) }
    function setCfg(key, value) { ShellServices.Dock.setDesignCfg("ii", key, value) }
    function toggle(key, fallback) { root.setCfg(key, !root.cfg(key, fallback)) }

    // The utility catalogue and the folders live in the design's own
    // services, published by its host while the dock is up.
    readonly property var actions: ShellServices.Dock.designActions
    readonly property var stackItems: root.cfg("widgetStackItems", ["media", "weather", "tasks"])
    readonly property var folders: root.cfg("pinnedFiles", [])
    property var utilityRows: ({})
    property string highlightedKind: ""
    readonly property string targetKind: GlobalStates.iiDockWidgetSettingsTarget

    function registerUtilityRow(kind, row) {
        root.utilityRows[kind] = row;
        if (root.targetKind === kind)
            root.scrollToUtility(kind);
    }

    function unregisterUtilityRow(kind, row) {
        if (root.utilityRows[kind] === row)
            delete root.utilityRows[kind];
    }

    function scrollToUtility(kind) {
        if (kind === "")
            return;
        const row = root.utilityRows[kind];
        if (!row)
            return;
        Qt.callLater(() => {
            if (!row || !root.contentItem)
                return;
            const point = root.contentItem.mapFromItem(row, 0, 0);
            const target = Math.max(0, Math.min(point.y - 96, root.contentHeight - root.height));
            targetScroll.stop();
            if (Appearance.reducedMotion) {
                root.contentY = target;
            } else {
                targetScroll.from = root.contentY;
                targetScroll.to = target;
                targetScroll.start();
            }
            root.highlightedKind = kind;
            clearHighlight.restart();
        });
    }

    onTargetKindChanged: root.scrollToUtility(root.targetKind)

    NumberAnimation {
        id: targetScroll
        target: root
        property: "contentY"
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    Timer {
        id: clearHighlight
        interval: 1200
        onTriggered: {
            const kind = root.highlightedKind;
            root.highlightedKind = "";
            if (GlobalStates.iiDockWidgetSettingsTarget === kind)
                GlobalStates.iiDockWidgetSettingsTarget = "";
        }
    }

    function setStackMember(member, on) {
        const items = Array.from(root.stackItems ?? []);
        const index = items.indexOf(member);
        if (on && index < 0)
            items.push(member);
        else if (!on && index >= 0)
            items.splice(index, 1);
        else
            return;
        root.setCfg("widgetStackItems", items);
    }

    function folderName(path) {
        const parts = String(path).split("/").filter(part => part.length > 0);
        return parts[parts.length - 1] ?? path;
    }

    readonly property var nativeWidgets: [
        { key: "enableMediaWidget", member: "media", title: Translation.tr("Media"), subtitle: Translation.tr("What is playing, with its controls"), symbol: "play_circle" },
        { key: "enableWeatherWidget", member: "weather", title: Translation.tr("Weather"), subtitle: Translation.tr("The sky and the temperature outside"), symbol: "cloud" },
        { key: "enableTasksWidget", member: "tasks", title: Translation.tr("Tasks"), subtitle: Translation.tr("Your to-do list, a click from done"), symbol: "checklist" },
        { key: "enableSportsWidget", member: "sports", title: Translation.tr("Sports"), subtitle: Translation.tr("Live scores of the teams you follow"), symbol: "sports_soccer" },
        { key: "enableLivePreviewWidget", member: "livePreview", title: Translation.tr("Live preview"), subtitle: Translation.tr("A running window, mirrored on the dock"), symbol: "live_tv" }
    ]

    RyokuUi.FileDialogHost {
        id: folderDialog
        folders: true
        title: Translation.tr("Choose a folder for the dock")
        onAccepted: root.actions?.addFolder(String(folderDialog.selectedFolder))
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: 4

        EditPanelSectionLabel { text: Translation.tr("Widgets") }

        Repeater {
            model: root.nativeWidgets
            delegate: EditPanelRow {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: false
                symbol: modelData.symbol
                title: modelData.title
                subtitle: modelData.subtitle
                trailingKind: "switch"
                switchChecked: root.cfg(modelData.key, false)
                onActivated: root.toggle(modelData.key, false)
            }
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "smartphone"
            title: Translation.tr("Phone mirror")
            subtitle: Translation.tr("Your paired phone's screen, a click away")
            trailingKind: "switch"
            switchChecked: root.cfg("showPhoneButton", false)
            onActivated: root.toggle("showPhoneButton", false)
        }

        EditPanelSectionLabel {
            visible: root.cfg("enableLivePreviewWidget", false)
            text: Translation.tr("Live preview")
        }

        EditPanelRow {
            visible: root.cfg("enableLivePreviewWidget", false)
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "width"
            title: Translation.tr("Width")
            trailingKind: "stepper"
            readonly property int slots: Number(root.cfg("livePreviewSlots", 2))
            valueText: Translation.tr("%1 slots").arg(slots)
            stepDownEnabled: slots > 2
            stepUpEnabled: slots < 6
            onStepDown: root.setCfg("livePreviewSlots", Math.max(2, slots - 1))
            onStepUp: root.setCfg("livePreviewSlots", Math.min(6, slots + 1))
        }

        EditPanelRow {
            visible: root.cfg("enableLivePreviewWidget", false)
            Layout.fillWidth: true
            first: false
            last: false
            symbol: "ads_click"
            title: Translation.tr("Follow the active window")
            trailingKind: "switch"
            switchChecked: root.cfg("livePreviewFollowActiveWindow", true)
            onActivated: root.toggle("livePreviewFollowActiveWindow", true)
        }

        EditPanelRow {
            visible: root.cfg("enableLivePreviewWidget", false)
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "arrow_selector_tool"
            title: Translation.tr("Show the cursor")
            trailingKind: "switch"
            switchChecked: root.cfg("livePreviewPaintCursor", false)
            onActivated: root.toggle("livePreviewPaintCursor", false)
        }

        EditOptionChips {
            visible: root.cfg("enableLivePreviewWidget", false)
            Layout.fillWidth: true
            label: Translation.tr("Capture")
            compact: false
            currentValue: root.cfg("livePreviewCaptureMode", "visible")
            options: [
                { displayName: Translation.tr("While visible"), icon: "visibility", value: "visible" },
                { displayName: Translation.tr("While hovered"), icon: "mouse", value: "hover" }
            ]
            onSelected: value => root.setCfg("livePreviewCaptureMode", value)
        }

        EditPanelSectionLabel {
            visible: root.cfg("enableWidgetStack", false)
            text: Translation.tr("In the widget stack")
        }

        Repeater {
            model: root.cfg("enableWidgetStack", false) ? root.nativeWidgets : []
            delegate: EditPanelRow {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === root.nativeWidgets.length - 1
                symbol: modelData.symbol
                title: modelData.title
                trailingKind: "switch"
                switchChecked: (root.stackItems ?? []).indexOf(modelData.member) >= 0
                onActivated: root.setStackMember(modelData.member, !switchChecked)
            }
        }

        EditPanelNotice {
            visible: root.actions === null
            Layout.fillWidth: true
            Layout.topMargin: Appearance.sizes.space2
            symbol: "info"
            text: Translation.tr("Turn the dock on to choose its utility tiles and folders.")
        }

        Repeater {
            model: root.actions?.utilityGroups ?? []
            delegate: ColumnLayout {
                id: utilityGroup
                required property var modelData
                readonly property var kinds: (root.actions?.utilityKinds ?? []).filter(info => info.group === modelData.id)
                Layout.fillWidth: true
                spacing: 4

                EditPanelSectionLabel { text: Translation.tr(utilityGroup.modelData.title) }

                Repeater {
                    model: utilityGroup.kinds
                    delegate: EditPanelRow {
                        required property var modelData
                        required property int index
                        id: utilityRow
                        selected: root.highlightedKind === modelData.kind
                        Component.onCompleted: root.registerUtilityRow(modelData.kind, utilityRow)
                        Component.onDestruction: root.unregisterUtilityRow(modelData.kind, utilityRow)
                        readonly property bool onDock: (root.actions?.utilities ?? []).some(entry => entry.kind === modelData.kind)
                        Layout.fillWidth: true
                        first: index === 0
                        last: index === utilityGroup.kinds.length - 1
                        symbol: modelData.symbol
                        title: Translation.tr(modelData.title)
                        subtitle: Translation.tr(modelData.description)
                        trailingKind: "switch"
                        switchChecked: onDock
                        onActivated: root.actions?.setUtility(modelData.kind, !onDock)
                    }
                }
            }
        }

        EditPanelSectionLabel { text: Translation.tr("Buttons") }

        Repeater {
            model: [
                { key: "showOverviewButton", title: Translation.tr("Overview"), subtitle: Translation.tr("Opens the overview"), symbol: "apps", fallback: true },
                { key: "showPinButton", title: Translation.tr("Pin"), subtitle: Translation.tr("Keeps the dock on screen"), symbol: "keep", fallback: true },
                { key: "showTrashButton", title: Translation.tr("Trash"), subtitle: Translation.tr("Drop files on it to throw them away"), symbol: "delete", fallback: false },
                { key: "showNotificationBadges", title: Translation.tr("Notification badges"), subtitle: Translation.tr("A count on an app with unread notifications"), symbol: "notifications", fallback: true },
                { key: "showDividers", title: Translation.tr("Dividers"), subtitle: Translation.tr("Lines between apps, widgets and buttons"), symbol: "more_vert", fallback: true }
            ]
            delegate: EditPanelRow {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === 4
                symbol: modelData.symbol
                title: modelData.title
                subtitle: modelData.subtitle
                trailingKind: "switch"
                switchChecked: root.cfg(modelData.key, modelData.fallback)
                onActivated: root.toggle(modelData.key, modelData.fallback)
            }
        }

        EditPanelSectionLabel {
            visible: root.actions !== null
            text: Translation.tr("Folders")
        }

        Repeater {
            model: root.actions !== null ? root.folders : []
            delegate: EditPanelRow {
                required property string modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: false
                symbol: "folder"
                title: root.folderName(modelData)
                subtitle: Translation.tr("Tap to take it off the dock")
                trailingKind: "stepper"
                valueText: String(index + 1)
                stepDownEnabled: index > 0
                stepUpEnabled: index < root.folders.length - 1
                onStepDown: root.actions?.moveFolder(index, index - 1)
                onStepUp: root.actions?.moveFolder(index, index + 1)
                onActivated: root.actions?.removeFolder(modelData)
            }
        }

        EditPanelRow {
            visible: root.actions !== null
            Layout.fillWidth: true
            first: root.folders.length === 0
            last: true
            symbol: "create_new_folder"
            title: Translation.tr("Add a folder")
            trailingKind: "add"
            onActivated: folderDialog.open()
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
