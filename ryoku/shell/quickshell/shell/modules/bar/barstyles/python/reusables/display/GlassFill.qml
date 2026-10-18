import QtQuick
import "../../"
import "../"
import "glassNesting.js" as Nesting

Item {
    id: root

    property real radius: 0
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomLeftRadius: radius
    property real bottomRightRadius: radius
    property color tintColor: ThemeBackend.base
    property real tintAmount: 0.35
    property real frost: 2.2
    property real rim: 0.45
    property real saturation: 1.0
    property real thickness: -1
    property real tintStrength: 0.5
    property real shadow: 0
    property real press: 0
    property real pulse: 0
    readonly property real pad: shadow > 0 ? 12 : 0

    readonly property bool isGlassFill: true
    property bool allowed: true
    property bool forceClear: false
    property bool forceOpaque: false
    property bool followBackdropHover: true
    property int nestLevel: 0
    readonly property real nest: Math.min(1, nestLevel * 0.5)
    property Item backdrop: null
    property Item registeredBackdrop: null
    property Item backdropOverride: null

    readonly property bool active: allowed && tintColor.a > 0.02 && root.visible && ThemeBackend.liquidGlass && backdrop !== null && backdrop.active && width > 0 && height > 0

    function findBackdrop() {
        if (root.backdropOverride) {
            root.explicitOwner = null;
            return root.backdropOverride;
        }
        let e = root.parent;
        let d = 0;
        while (e && d < 48) {
            if (e.glassBackdropItem !== undefined) {
                root.explicitOwner = e;
                return e.glassBackdropItem;
            }
            e = e.parent;
            d++;
        }
        root.explicitOwner = null;
        let a = root.parent;
        let depth = 0;
        while (a && depth < 32) {
            const kids = a.children;
            if (kids) {
                for (let i = 0; i < kids.length; i++) {
                    if (kids[i] && kids[i].isGlassBackdrop === true && kids[i].surfaceEnabled !== false && kids[i].earsOnly !== true) return kids[i];
                }
            }
            a = a.parent;
            depth++;
        }
        a = root.parent;
        depth = 0;
        while (a && depth < 32) {
            const kids = a.children;
            if (kids) {
                for (let i = 0; i < kids.length; i++) {
                    const sub = kids[i] ? kids[i].children : null;
                    if (!sub) continue;
                    for (let j = 0; j < sub.length; j++) {
                        if (sub[j] && sub[j].isGlassBackdrop === true && sub[j].surfaceEnabled !== false && sub[j].earsOnly !== true) return sub[j];
                    }
                }
            }
            a = a.parent;
            depth++;
        }
        return null;
    }

    function resolve() {
        root.backdrop = root.findBackdrop();
        root.updateNest();
    }

    function updateNest() {
        root.nestLevel = Nesting.nestLevel(root, root.backdrop ? root.backdrop.parent : null, false);
    }

    function register() {
        unregister();
        if (root.active && root.backdrop) {
            root.backdrop.consumers++;
            root.registeredBackdrop = root.backdrop;
        }
    }

    function unregister() {
        if (root.registeredBackdrop) {
            root.registeredBackdrop.consumers--;
            root.registeredBackdrop = null;
        }
    }

    property int resolveAttempts: 0
    property Item explicitOwner: null

    Connections {
        target: root.explicitOwner
        ignoreUnknownSignals: true
        function onGlassBackdropItemChanged() { root.resolve(); }
    }

    Timer {
        interval: 450
        repeat: true
        running: (root.backdrop === null || !root.backdrop.active) && root.allowed && ThemeBackend.liquidGlass && root.visible && root.resolveAttempts < 24
        onTriggered: {
            root.resolveAttempts++;
            root.resolve();
        }
    }

    onBackdropOverrideChanged: resolve()
    onVisibleChanged: {
        if (visible && ThemeBackend.liquidGlass) {
            resolveAttempts = 0;
            resolve();
        }
    }
    onActiveChanged: {
        cursorPrimed = false;
        rectPrimed = false;
        armed = false;
        armFrames = 0;
        if (active) updateNest();
        register();
    }
    onBackdropChanged: register()
    onParentChanged: resolve()
    Component.onCompleted: resolve()
    Component.onDestruction: unregister()

    Connections {
        target: ThemeBackend
        function onLiquidGlassChanged() { root.resolve(); }
    }

    function track() {
        let e = root;
        let d = 0;
        while (e && d < 64) {
            void e.x;
            void e.y;
            void e.width;
            void e.height;
            e = e.parent;
            d++;
        }
    }

    property rect sampleRect: {
        if (!root.active) return Qt.rect(0, 0, 1, 1);
        void root.backdrop.frame;
        root.track();
        const a = root.backdrop.mapFromItem(root, -root.pad, -root.pad);
        const b = root.backdrop.mapFromItem(root, root.width + root.pad, root.height + root.pad);
        const bw = Math.max(1, root.backdrop.width);
        const bh = Math.max(1, root.backdrop.height);
        return Qt.rect(a.x / bw, a.y / bh, (b.x - a.x) / bw, (b.y - a.y) / bh);
    }

    property point localCursor: {
        if (!root.active) return Qt.point(0, 0);
        root.track();
        const c = root.mapFromItem(root.backdrop, root.backdrop.cursorX, root.backdrop.cursorY);
        return Qt.point(c.x + root.pad, c.y + root.pad);
    }

    property int turns: {
        if (!root.active) return 0;
        void root.backdrop.frame;
        root.track();
        const p0 = root.backdrop.mapFromItem(root, 0, 0);
        const p1 = root.backdrop.mapFromItem(root, 1, 0);
        const angle = Math.atan2(p1.y - p0.y, p1.x - p0.x) * 180 / Math.PI;
        return (((-Math.round(angle / 90)) % 4) + 4) % 4;
    }

    property rect frameRect: {
        if (!root.active) return Qt.rect(0, 0, 1, 1);
        void root.backdrop.frame;
        root.track();
        const a = root.backdrop.mapFromItem(glassFrame, 0, 0);
        const b = root.backdrop.mapFromItem(glassFrame, glassFrame.width, glassFrame.height);
        const bw = Math.max(1, root.backdrop.width);
        const bh = Math.max(1, root.backdrop.height);
        return Qt.rect(Math.min(a.x, b.x) / bw, Math.min(a.y, b.y) / bh, Math.abs(b.x - a.x) / bw, Math.abs(b.y - a.y) / bh);
    }

    property point frameCursor: {
        if (!root.active) return Qt.point(0, 0);
        root.track();
        const c = glassFrame.mapFromItem(root.backdrop, root.backdrop.cursorX, root.backdrop.cursorY);
        return Qt.point(c.x, c.y);
    }

    function cornerRadius(i) {
        const r = [root.topLeftRadius, root.topRightRadius, root.bottomRightRadius, root.bottomLeftRadius];
        return r[(i + root.turns) % 4];
    }

    property real motion: 0
    property point lastCursor: Qt.point(0, 0)
    property point lastCenter: Qt.point(0, 0)
    property size lastSize: Qt.size(0, 0)
    property bool cursorPrimed: false
    property bool rectPrimed: false
    property bool armed: false
    property int armFrames: 0

    FrameAnimation {
        running: root.active && !root.armed
        onTriggered: {
            if (++root.armFrames >= 3) root.armed = true;
        }
    }

    function bump(distance) {
        if (!root.active || !root.armed || distance < 0.05) return;
        root.motion = Math.min(1, root.motion + distance / 36);
        if (!motionDecay.running) motionDecay.start();
    }

    onLocalCursorChanged: {
        if (!root.active) return;
        lastCursor = localCursor;
        if (!cursorPrimed) {
            cursorPrimed = true;
            return;
        }
    }

    onSampleRectChanged: {
        if (!root.active) return;
        const bw = root.backdrop.width;
        const bh = root.backdrop.height;
        const cx = (sampleRect.x + sampleRect.width * 0.5) * bw;
        const cy = (sampleRect.y + sampleRect.height * 0.5) * bh;
        const sw = sampleRect.width * bw;
        const sh = sampleRect.height * bh;
        const d = Math.abs(cx - lastCenter.x) + Math.abs(cy - lastCenter.y) + Math.abs(sw - lastSize.width) * 0.5 + Math.abs(sh - lastSize.height) * 0.5;
        lastCenter = Qt.point(cx, cy);
        lastSize = Qt.size(sw, sh);
        if (!rectPrimed) {
            rectPrimed = true;
            return;
        }
        bump(Math.min(60, d));
    }

    Timer {
        id: motionDecay
        interval: 16
        repeat: true
        onTriggered: {
            root.motion *= 0.91;
            if (root.motion < 0.004) {
                root.motion = 0;
                stop();
            }
        }
    }

    Item {
        id: glassFrame
        anchors.centerIn: parent
        width: (root.turns % 2 === 0 ? root.width : root.height) + root.pad * 2
        height: (root.turns % 2 === 0 ? root.height : root.width) + root.pad * 2
        rotation: root.turns * 90
        visible: root.active

        LiquidGlass {
            anchors.fill: parent
            glassPad: root.pad
            shadowAmt: root.shadow * (1 - 0.6 * root.nest)
            nest: root.nest
            morph: 0
            dispersion: 0.02
            clear: root.forceOpaque ? 0 : ((root.forceClear || root.nestLevel >= 1) ? 1 : 0)
            energy: Math.min(1, root.press + root.pulse)
            motion: root.motion
            src: root.backdrop ? root.backdrop.texture : null
            topLeftRadius: root.cornerRadius(0)
            topRightRadius: root.cornerRadius(1)
            bottomRightRadius: root.cornerRadius(2)
            bottomLeftRadius: root.cornerRadius(3)
            tintColor: root.tintColor
            tintAmount: root.tintAmount * root.tintStrength * (1 - 0.5 * root.nest)
            frost: root.nestLevel >= 1 ? Math.min(root.frost, 1.0) : root.frost
            rim: root.rim * (1 - 0.35 * root.nest)
            saturation: 1 + (root.saturation - 1) * (1 - root.nest)
            bezel: Math.max(3, Math.min(14, Math.min(root.width, root.height) * 0.28))
            thickness: root.thickness >= 0 ? root.thickness : bezel * 0.8
            sourceRect: root.frameRect
            cursorPos: root.frameCursor
            hover: (root.backdrop && root.followBackdropHover) ? root.backdrop.hoverAmount : 0
        }
    }
}
