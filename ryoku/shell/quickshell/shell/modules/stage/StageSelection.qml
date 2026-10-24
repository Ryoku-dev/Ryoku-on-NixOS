pragma ComponentBehavior: Bound

import QtQuick
import stage
import stage.modules.common.functions as StageFunctions
import "Singletons" as StageCfg
import "../desktop/Singletons" as WidgetStore

// Selection stays on the live Ryoku canvas: this controller borrows the
// island's geometry arithmetic while the desktop supplies the real slots.
Item {
    id: root

    property bool active: false
    property bool keyboardEnabled: false
    readonly property bool selectionEnabled: root.active
    property real framingDim: 0
    property bool inputBlocked: false
    property bool snapEnabled: true
    property real snapThreshold: 8
    property real guideVertical: -1
    property real guideHorizontal: -1
    readonly property var guideVerticals: root.guideVertical >= 0
        ? [root.guideVertical] : []
    readonly property var guideHorizontals: root.guideHorizontal >= 0
        ? [root.guideHorizontal] : []
    property bool marqueeActive: false
    property bool widgetPressActive: false
    property real marqueeAnchorX: 0
    property real marqueeAnchorY: 0
    property real marqueeX: 0
    property real marqueeY: 0
    property int marqueeModifiers: Qt.NoModifier
    readonly property bool marqueeExtending: Boolean(root.marqueeModifiers
        & (Qt.ShiftModifier | Qt.ControlModifier))
    property string monitor: ""
    property real gridSize: 12
    property var widgetIds: []
    property var itemFor: null
    property var provider: null
    property int heldModifiers: Qt.NoModifier
    property var _drag: null
    property var _nudge: null
    property var _pluginPreview: ({})

    signal removeRequested(string id)
    signal dropped(rect box)
    signal marqueeFinished(rect band)
    signal settingsRequested(string id)

    visible: root.active
    focus: root.active && root.keyboardEnabled

    readonly property rect selectionRect: {
        let minX = Infinity;
        let minY = Infinity;
        let maxX = -Infinity;
        let maxY = -Infinity;
        for (const id of StageCfg.StageSession.selection) {
            const item = root._item(id);
            if (!root._movable(id, item) || item.visible === false)
                continue;
            minX = Math.min(minX, item.x);
            minY = Math.min(minY, item.y);
            maxX = Math.max(maxX, item.x + item.width);
            maxY = Math.max(maxY, item.y + item.height);
        }
        if (!isFinite(minX))
            return Qt.rect(0, 0, 0, 0);
        return Qt.rect(minX, minY, maxX - minX, maxY - minY);
    }
    readonly property bool dragging: root._drag !== null

    onKeyboardEnabledChanged: {
        root.heldModifiers = Qt.NoModifier;
        if (root.keyboardEnabled)
            root.forceActiveFocus();
    }
    onActiveChanged: {
        if (!root.active) {
            root.flushNudge();
            root.widgetDragCancelled("");
            root.cancelMarquee();
            root._pluginPreview = ({});
            root.heldModifiers = Qt.NoModifier;
        } else if (root.keyboardEnabled) {
            root.forceActiveFocus();
        }
    }
    onWidgetIdsChanged: {
        if (!root.active)
            return;
        const kept = StageCfg.StageSession.selection.filter(
            id => root.widgetIds.indexOf(id) >= 0);
        if (kept.length !== StageCfg.StageSession.selection.length)
            StageCfg.StageSession.selectMany(kept, StageCfg.StageSession.selected);
    }

    function _item(id) {
        return root.itemFor ? root.itemFor(id) : null;
    }

    function _isPlugin(id) {
        return String(id).indexOf("plugin:") === 0;
    }
    function _isVisualizer(id) {
        return String(id).indexOf("visualizer:") === 0;
    }

    function _movable(id, item) {
        return item !== null && item !== undefined
            && item.locked !== true
            && (!root._isVisualizer(id)
                || typeof item.stagePreviewPosition === "function");
    }

    function _bounds(item) {
        if (!item)
            return { minX: 0, maxX: 0, minY: 0, maxY: 0 };
        if (typeof item.clampX === "function" && typeof item.clampY === "function") {
            return {
                minX: item.clampX(-1000000000),
                maxX: item.clampX(1000000000),
                minY: item.clampY(-1000000000),
                maxY: item.clampY(1000000000)
            };
        }
        const parentWidth = item.parent ? item.parent.width : item.x + item.width;
        const parentHeight = item.parent ? item.parent.height : item.y + item.height;
        return {
            minX: 0,
            maxX: Math.max(0, parentWidth - item.width),
            minY: 0,
            maxY: Math.max(0, parentHeight - item.height)
        };
    }

    function _snapshot(id) {
        return root.provider ? root.provider.snapshot(id) : null;
    }

    function _snapshotAt(id, before, x, y) {
        if (!before)
            return null;
        const after = JSON.parse(JSON.stringify(before));
        if (root._isPlugin(id)) {
            after.entry = after.entry || {};
            after.entry.desktopWidget = Object.assign({}, after.entry.desktopWidget || {}, {
                x: Math.round(x),
                y: Math.round(y)
            });
        } else {
            after.anchor = "free";
            after.x = Math.round(x);
            after.y = Math.round(y);
        }
        return after;
    }

    function _setPreview(id, item, x, y) {
        if (!item)
            return;
        if (typeof item.stagePreviewPosition === "function") {
            item.stagePreviewPosition(x, y);
            return;
        }
        if (root._isPlugin(id)) {
            const next = Object.assign({}, root._pluginPreview);
            next[id] = Qt.point(x, y);
            root._pluginPreview = next;
        }
    }

    function _endPreview(id, item) {
        if (item && typeof item.stageEndPreview === "function")
            item.stageEndPreview();
    }
    function _dropPluginPreview(id) {
        if (!root._isPlugin(id) || root._pluginPreview[id] === undefined)
            return;
        const next = Object.assign({}, root._pluginPreview);
        delete next[id];
        root._pluginPreview = next;
    }

    function hasPluginPreview(id) {
        return root._pluginPreview[id] !== undefined;
    }

    function pluginPreview(id) {
        return root._pluginPreview[id] || Qt.point(0, 0);
    }

    Timer {
        id: pluginPreviewRelease
        interval: 1500
        onTriggered: root._pluginPreview = ({})
    }
    Connections {
        target: GlobalStates
        function onEditHistoryWillReplay() {
            root.flushNudge();
            root._pluginPreview = ({});
        }
    }


    function _commitPositions(positions, beforeById) {
        if (!positions || positions.length === 0)
            return;
        const changed = [];
        const patch = {};
        for (const position of positions) {
            const id = position.id;
            const visualizer = root._isVisualizer(id);
            const before = beforeById && beforeById[id] !== undefined
                ? beforeById[id] : root._snapshot(id);
            const oldX = before && before.x !== undefined ? before.x
                : before && before.entry && before.entry.desktopWidget
                    ? before.entry.desktopWidget.x : undefined;
            const oldY = before && before.y !== undefined ? before.y
                : before && before.entry && before.entry.desktopWidget
                    ? before.entry.desktopWidget.y : undefined;
            const x = Math.round(position.x);
            const y = Math.round(position.y);
            const same = visualizer
                ? position.startX !== undefined && position.startY !== undefined
                    && Math.round(position.startX) === x
                    && Math.round(position.startY) === y
                : oldX !== undefined && oldY !== undefined
                    && Math.round(oldX) === x && Math.round(oldY) === y;
            if (same) {
                root._endPreview(id, root._item(id));
                root._dropPluginPreview(id);
                continue;
            }
            changed.push({
                id: id,
                x: x,
                y: y,
                before: before,
                visualizer: visualizer
            });
            if (!root._isPlugin(id) && !visualizer) {
                patch[id + "Anchor"] = "free";
                patch[id + "X"] = x;
                patch[id + "Y"] = y;
            }
        }
        if (changed.length === 0)
            return;
        const provider = root.provider;

        GlobalStates.editHistoryBeginBatch();
        if (Object.keys(patch).length > 0)
            WidgetStore.Config.setManyFor(root.monitor, patch);
        for (const move of changed) {
            const item = root._item(move.id);
            if (move.visualizer
                    && item && typeof item.stageCommitPosition === "function") {
                item.stageCommitPosition(move.x, move.y);
            } else if (root._isPlugin(move.id)) {
                root._setPreview(move.id, item, move.x, move.y);
                if (provider) {
                    const pluginId = move.id.slice(7);
                    provider.enqueue([provider.placeTool, pluginId, "desktopWidget",
                        "" + move.x, "" + move.y]);
                }
            }
            const after = move.visualizer
                ? root._snapshot(move.id)
                : root._snapshotAt(move.id, move.before, move.x, move.y);
            if (provider && move.before && after) {
                const id = move.id;
                const before = move.before;
                GlobalStates.editHistoryPush({
                    undo: () => provider.restore(id, before),
                    redo: () => provider.restore(id, after)
                });
            }
            root._endPreview(move.id, item);
        }
        GlobalStates.editHistoryEndBatch();
        if (Object.keys(root._pluginPreview).length > 0)
            pluginPreviewRelease.restart();
    }

    function beginMarquee(x, y, modifiers) {
        if (!root.selectionEnabled)
            return;
        root.marqueeModifiers = modifiers === undefined
            ? root.heldModifiers : modifiers;
        root.marqueeAnchorX = x;
        root.marqueeAnchorY = y;
        root.marqueeX = x;
        root.marqueeY = y;
        root.marqueeActive = true;
    }

    function updateMarquee(x, y) {
        if (!root.marqueeActive)
            return;
        root.marqueeX = x;
        root.marqueeY = y;
    }

    function finishMarquee(modifiers) {
        if (!root.marqueeActive)
            return;
        if (modifiers !== undefined)
            root.marqueeModifiers = modifiers;
        root.marqueeActive = false;
        const band = Qt.rect(
            Math.min(root.marqueeAnchorX, root.marqueeX),
            Math.min(root.marqueeAnchorY, root.marqueeY),
            Math.abs(root.marqueeX - root.marqueeAnchorX),
            Math.abs(root.marqueeY - root.marqueeAnchorY));
        root.selectRect(band, root.marqueeExtending);
        root.marqueeFinished(band);
        root.marqueeModifiers = Qt.NoModifier;
    }

    function cancelMarquee() {
        root.marqueeActive = false;
        root.marqueeModifiers = Qt.NoModifier;
    }

    function pick(id, modifiers) {
        root.widgetPressActive = true;
        Qt.callLater(() => root.widgetPressActive = false);
        root.flushNudge();
        const mods = modifiers === undefined ? root.heldModifiers : modifiers;
        if ((mods & Qt.ShiftModifier) || (mods & Qt.ControlModifier)) {
            StageCfg.StageSession.toggleSelect(id);
        } else if (StageCfg.StageSession.contains(id)) {
            StageCfg.StageSession.selectMany(
                StageCfg.StageSession.selection, id);
        } else {
            StageCfg.StageSession.select(id);
        }
        StageCfg.StageSession.closePanel();
        if (root.keyboardEnabled)
            root.forceActiveFocus();
    }

    function selectRect(rect, extend) {
        root.flushNudge();
        const picked = extend ? StageCfg.StageSession.selection.slice() : [];
        for (const id of root.widgetIds || []) {
            const item = root._item(id);
            if (!item || item.visible === false)
                continue;
            if (item.x < rect.x + rect.width && item.x + item.width > rect.x
                    && item.y < rect.y + rect.height && item.y + item.height > rect.y
                    && picked.indexOf(id) < 0)
                picked.push(id);
        }
        StageCfg.StageSession.selectMany(picked);
    }

    function selectAll() {
        root.flushNudge();
        const ids = [];
        for (const id of root.widgetIds || [])
            if (root._item(id))
                ids.push(id);
        StageCfg.StageSession.selectMany(ids);
    }

    function removeSelection() {
        root.flushNudge();
        const ids = StageCfg.StageSession.selection.slice();
        if (ids.length === 0)
            return;
        StageCfg.StageSession.deselect();
        GlobalStates.editHistoryBeginBatch();
        for (const id of ids)
            root.removeRequested(id);
        GlobalStates.editHistoryEndBatch();
    }
    function _snapTargets() {
        const xs = [root.width / 2];
        const ys = [root.height / 2];
        const selected = StageCfg.StageSession.selection;
        for (const otherId of root.widgetIds || []) {
            if (selected.indexOf(otherId) >= 0)
                continue;
            const other = root._item(otherId);
            if (!other || other.visible === false)
                continue;
            xs.push(other.x, other.x + other.width / 2,
                other.x + other.width);
            ys.push(other.y, other.y + other.height / 2,
                other.y + other.height);
        }
        return { x: xs, y: ys };
    }

    function _snapAxis(position, size, targets, grid) {
        let best = position;
        let guide = -1;
        let distance = root.snapThreshold + 1;
        const points = [
            { at: position, offset: 0 },
            { at: position + size / 2, offset: size / 2 },
            { at: position + size, offset: size }
        ];
        for (const point of points) {
            for (const target of targets) {
                const d = Math.abs(point.at - target);
                if (d < distance) {
                    distance = d;
                    best = target - point.offset;
                    guide = target;
                }
            }
        }
        if (grid > 0) {
            const target = Math.round(position / grid) * grid;
            const d = Math.abs(position - target);
            if (d < distance) {
                best = target;
                guide = target;
            }
        }
        return { position: best, guide: guide };
    }

    function _snapPoint(id, x, y, modifiers) {
        const drag = root._drag;
        const item = drag ? drag.leaderItem : null;
        if (!drag || !item || !root.snapEnabled
                || Boolean(modifiers & Qt.AltModifier)) {
            root.guideVertical = -1;
            root.guideHorizontal = -1;
            return Qt.point(x, y);
        }
        const sx = root._snapAxis(x, item.width, drag.snapTargets.x,
            Math.max(1, root.gridSize));
        const sy = root._snapAxis(y, item.height, drag.snapTargets.y,
            Math.max(1, root.gridSize));
        root.guideVertical = sx.guide;
        root.guideHorizontal = sy.guide;
        return Qt.point(sx.position, sy.position);
    }

    function widgetDragStarted(id) {
        root.flushNudge();
        if (!StageCfg.StageSession.contains(id)) {
            root._drag = null;
            return { active: false, minX: -Infinity, maxX: Infinity,
                minY: -Infinity, maxY: Infinity };
        }
        const members = [];
        const before = {};
        let deltaMinX = -Infinity;
        let deltaMaxX = Infinity;
        let deltaMinY = -Infinity;
        let deltaMaxY = Infinity;
        for (const memberId of StageCfg.StageSession.selection) {
            const item = root._item(memberId);
            if (!root._movable(memberId, item))
                continue;
            const bounds = root._bounds(item);
            const member = { id: memberId, item: item, x: item.x, y: item.y };
            members.push(member);
            before[memberId] = root._snapshot(memberId);
            deltaMinX = Math.max(deltaMinX, bounds.minX - member.x);
            deltaMaxX = Math.min(deltaMaxX, bounds.maxX - member.x);
            deltaMinY = Math.max(deltaMinY, bounds.minY - member.y);
            deltaMaxY = Math.min(deltaMaxY, bounds.maxY - member.y);
            if (memberId !== id)
                root._setPreview(memberId, item, member.x, member.y);
        }
        const leader = members.find(member => member.id === id);
        if (!leader) {
            root._drag = null;
            return { active: false, minX: -Infinity, maxX: Infinity,
                minY: -Infinity, maxY: Infinity };
        }
        root._drag = {
            leader: id,
            leaderItem: leader.item,
            startX: leader.x,
            startY: leader.y,
            members: members,
            before: before,
            deltaMinX: deltaMinX,
            deltaMaxX: deltaMaxX,
            deltaMinY: deltaMinY,
            deltaMaxY: deltaMaxY,
            snapTargets: root._snapTargets()
        };
        return {
            active: true,
            minX: leader.x + deltaMinX,
            maxX: leader.x + deltaMaxX,
            minY: leader.y + deltaMinY,
            maxY: leader.y + deltaMaxY
        };
    }

    function widgetDragMoved(id, x, y, modifiers) {
        const drag = root._drag;
        if (!drag || drag.leader !== id)
            return Qt.point(x, y);
        const snapped = root._snapPoint(id, x, y,
            modifiers === undefined ? root.heldModifiers : modifiers);
        const dx = Math.max(drag.deltaMinX,
            Math.min(drag.deltaMaxX, snapped.x - drag.startX));
        const dy = Math.max(drag.deltaMinY,
            Math.min(drag.deltaMaxY, snapped.y - drag.startY));
        for (const member of drag.members) {
            if (member.id !== id)
                root._setPreview(member.id, member.item,
                    member.x + dx, member.y + dy);
        }
        return Qt.point(drag.startX + dx, drag.startY + dy);
    }

    function widgetDragEnded(id, x, y, modifiers) {
        const drag = root._drag;
        if (!drag || drag.leader !== id)
            return false;
        const point = root.widgetDragMoved(id, x, y, modifiers);
        const dx = point.x - drag.startX;
        const dy = point.y - drag.startY;
        const positions = drag.members.map(member => ({
            id: member.id,
            x: member.x + dx,
            y: member.y + dy,
            startX: member.x,
            startY: member.y
        }));
        for (const position of positions)
            if (root._isPlugin(position.id))
                root._setPreview(position.id, root._item(position.id),
                    position.x, position.y);
        root._drag = null;
        root.guideVertical = -1;
        root.guideHorizontal = -1;
        root._commitPositions(positions, drag.before);
        const leader = root._item(id);
        if (leader)
            root.dropped(Qt.rect(point.x, point.y, leader.width, leader.height));
        return true;
    }

    function widgetDragCancelled(id) {
        const drag = root._drag;
        if (!drag || (id !== "" && drag.leader !== id))
            return;
        root._drag = null;
        root.guideVertical = -1;
        root.guideHorizontal = -1;
        for (const member of drag.members)
            root._endPreview(member.id, member.item);
        root._pluginPreview = ({});
    }

    function _nudgeMembers() {
        const members = [];
        const before = {};
        for (const id of StageCfg.StageSession.selection) {
            const item = root._item(id);
            if (!root._movable(id, item))
                continue;
            const bounds = root._bounds(item);
            members.push({
                id: id,
                item: item,
                x: item.x,
                y: item.y,
                startX: item.x,
                startY: item.y,
                minX: bounds.minX,
                maxX: bounds.maxX,
                minY: bounds.minY,
                maxY: bounds.maxY
            });
            before[id] = root._snapshot(id);
        }
        return { members: members, before: before };
    }

    function nudgeSelection(dirX, dirY, large) {
        if (root._nudge === null) {
            const run = root._nudgeMembers();
            if (run.members.length === 0)
                return;
            root._nudge = run;
        }
        const members = root._nudge.members;
        const leader = members[0];
        const lattice = Math.max(1, root.gridSize);
        const distance = lattice * (large ? 10 : 1);
        const wantX = dirX === 0 ? leader.x
            : StageFunctions.WidgetNudge.step(leader.x, dirX * distance, lattice, 0);
        const wantY = dirY === 0 ? leader.y
            : StageFunctions.WidgetNudge.step(leader.y, dirY * distance, lattice, 0);
        const bounded = StageFunctions.WidgetNudge.groupDelta(members,
            wantX - leader.x, wantY - leader.y);
        if (bounded.dx === 0 && bounded.dy === 0)
            return;
        for (const member of members) {
            member.x += bounded.dx;
            member.y += bounded.dy;
            root._setPreview(member.id, member.item, member.x, member.y);
        }
        nudgeCommit.restart();
    }

    Timer {
        id: nudgeCommit
        interval: 400
        onTriggered: root.flushNudge()
    }

    function flushNudge() {
        nudgeCommit.stop();
        const run = root._nudge;
        root._nudge = null;
        if (!run)
            return;
        root._commitPositions(run.members.map(member => ({
            id: member.id,
            x: member.x,
            y: member.y,
            startX: member.startX,
            startY: member.startY
        })), run.before);
    }

    function alignSelection(mode) {
        root.flushNudge();
        const members = [];
        const before = {};
        for (const id of StageCfg.StageSession.selection) {
            const item = root._item(id);
            if (!root._movable(id, item))
                continue;
            const bounds = root._bounds(item);
            members.push({
                id: id,
                x: item.x,
                y: item.y,
                box: Qt.rect(item.x, item.y, item.width, item.height),
                minX: bounds.minX,
                maxX: bounds.maxX,
                minY: bounds.minY,
                maxY: bounds.maxY
            });
            before[id] = root._snapshot(id);
        }
        const moves = StageFunctions.WidgetAlign.deltas(members, mode);
        const positions = [];
        for (const member of members) {
            const move = moves[member.id];
            if (move)
                positions.push({
                    id: member.id,
                    x: member.x + move.dx,
                    y: member.y + move.dy,
                    startX: member.x,
                    startY: member.y
                });
        }
        root._commitPositions(positions, before);
    }
    function scaleSelection(delta, reset) {
        root.flushNudge();
        const ids = StageCfg.StageSession.selection.slice();
        if (ids.length === 0)
            return;
        GlobalStates.editHistoryBeginBatch();
        for (const id of ids) {
            if (String(id).indexOf("visualizer") === 0)
                continue;
            const item = root._item(id);
            if (!item || typeof item.stageSetScale !== "function")
                continue;
            const current = item.effectiveScale !== undefined
                ? item.effectiveScale : 1;
            item.stageSetScale(reset ? 1 : current + delta);
        }
        GlobalStates.editHistoryEndBatch();
    }

    function toggleLockSelection() {
        root.flushNudge();
        const ids = StageCfg.StageSession.selection.slice();
        if (ids.length === 0)
            return;
        GlobalStates.editHistoryBeginBatch();
        for (const id of ids) {
            if (String(id).indexOf("visualizer") === 0)
                continue;
            const item = root._item(id);
            if (item && typeof item.stageToggleLock === "function")
                item.stageToggleLock();
        }
        GlobalStates.editHistoryEndBatch();
    }

    readonly property var arrowKeys: ({
        left: Qt.Key_Left,
        right: Qt.Key_Right,
        up: Qt.Key_Up,
        down: Qt.Key_Down
    })

    Keys.onPressed: event => {
        root.heldModifiers = event.modifiers;
        if (!root.active)
            return;
        const control = Boolean(event.modifiers & Qt.ControlModifier);
        const shift = Boolean(event.modifiers & Qt.ShiftModifier);
        if (control && event.key === Qt.Key_F) {
            event.accepted = true;
            if (event.isAutoRepeat)
                return;
            GlobalStates.editDrawerSection = "widgets";
            GlobalStates.editDrawerPage = "";
            GlobalStates.editDrawerOpen = true;
            GlobalStates.editSearchFocusRequested();
            return;
        }
        if (control && event.key === Qt.Key_A) {
            event.accepted = true;
            if (!event.isAutoRepeat)
                root.selectAll();
            return;
        }
        if (control && (event.key === Qt.Key_Z || event.key === Qt.Key_Y)) {
            event.accepted = true;
            if (event.isAutoRepeat)
                return;
            root.flushNudge();
            if (event.key === Qt.Key_Y || shift)
                GlobalStates.editRedo();
            else
                GlobalStates.editUndo();
            return;
        }
        if (StageCfg.StageSession.selection.length > 0 && !control
                && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal
                    || event.key === Qt.Key_Minus || event.key === Qt.Key_0
                    || event.key === Qt.Key_L || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter)) {
            event.accepted = true;
            if (event.isAutoRepeat)
                return;
            if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)
                root.scaleSelection(0.1, false);
            else if (event.key === Qt.Key_Minus)
                root.scaleSelection(-0.1, false);
            else if (event.key === Qt.Key_0)
                root.scaleSelection(0, true);
            else if (event.key === Qt.Key_L)
                root.toggleLockSelection();
            else
                root.settingsRequested(StageCfg.StageSession.selected);
            return;
        }
        if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
                && StageCfg.StageSession.selection.length > 0) {
            event.accepted = true;
            if (!event.isAutoRepeat)
                root.removeSelection();
            return;
        }
        const direction = StageFunctions.WidgetNudge.direction(event.key, root.arrowKeys);
        if (!direction || control || StageCfg.StageSession.selection.length === 0)
            return;
        root.nudgeSelection(direction.dx, direction.dy, shift);
        event.accepted = true;
    }
    Keys.onReleased: event => root.heldModifiers = event.modifiers
    Keys.onEscapePressed: event => {
        if (!root.active)
            return;
        root.flushNudge();
        StageCfg.StageSession.escapeStep();
        event.accepted = true;
    }
}
