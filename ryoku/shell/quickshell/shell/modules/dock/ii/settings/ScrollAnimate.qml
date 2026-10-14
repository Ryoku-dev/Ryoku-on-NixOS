import QtQuick
import "."
import ".."

Item {
    id: root
    visible: false

    // Existing consumers rely on the parent target; callers with a different
    // target can opt in explicitly without paying for the animation engine in
    // Settings Performance Mode.
    property Item targetItem: parent
    readonly property bool scrollAnimationsEnabled: Config.options?.appearance?.scrollAnimations ?? true
    readonly property bool performanceMode: Config.options?.appearance?.settingsPerformanceMode ?? true
    // Settings pages are only created after Config.ready. Keeping this gate
    // here as well prevents any other consumer from attaching transforms while
    // the adapter is still being populated from disk.
    property bool active: Config.ready && root.scrollAnimationsEnabled && !root.performanceMode

    Loader {
        active: root.active && root.targetItem !== null
        sourceComponent: scrollAnimationComponent
    }

    Component {
        id: scrollAnimationComponent

        Item {
            id: animation
            property Item targetItem: root.targetItem
            property Item attachedTarget: null
            property Flickable flickable: null
            // mapToItem() does not expose the target item's layout geometry as
            // a binding dependency. Bump this after layout changes so the
            // initial visibility pass runs again once the parent layout has
            // assigned the final delegate positions.
            property int layoutTick: 0

            function scheduleLayoutRefresh() {
                layoutRefreshTimer.restart();
            }

            Scale {
                id: scrollScaleTransform
                origin.x: animation.targetItem ? animation.targetItem.width / 2 : 0
                origin.y: animation.targetItem ? animation.targetItem.height / 2 : 0
                xScale: animation.animatedScale
                yScale: animation.animatedScale
            }

            Translate {
                id: scrollTranslateTransform
                y: animation.animatedTranslateY
            }

            Timer {
                id: retryTimer
                interval: 50
                repeat: false
                onTriggered: animation.findFlickable()
            }

            Timer {
                id: layoutRefreshTimer
                interval: 0
                repeat: false
                onTriggered: animation.layoutTick++
            }

            function attachTransform() {
                if (!targetItem)
                    return;

                const transforms = targetItem.transform;
                if (transforms.indexOf(scrollScaleTransform) === -1) {
                    transforms.push(scrollScaleTransform);
                }
                if (transforms.indexOf(scrollTranslateTransform) === -1) {
                    transforms.push(scrollTranslateTransform);
                }
                targetItem.transform = transforms;
                attachedTarget = targetItem;
            }

            function detachTransform() {
                if (!attachedTarget)
                    return;

                const transforms = attachedTarget.transform;
                const scaleIdx = transforms.indexOf(scrollScaleTransform);
                if (scaleIdx !== -1) {
                    transforms.splice(scaleIdx, 1);
                }
                const transIdx = transforms.indexOf(scrollTranslateTransform);
                if (transIdx !== -1) {
                    transforms.splice(transIdx, 1);
                }
                attachedTarget.transform = transforms;
                attachedTarget = null;
            }

            function findFlickable() {
                let nextParent = targetItem ? targetItem.parent : null;
                while (nextParent) {
                    if (nextParent.flickableDirection !== undefined && nextParent.contentY !== undefined) {
                        flickable = nextParent;
                        scheduleLayoutRefresh();
                        return;
                    }
                    nextParent = nextParent.parent;
                }
                flickable = null;
            }

            // Calculate relative Y coordinate inside the Flickable viewport.
            readonly property real relativeY: {
                if (!flickable || !targetItem)
                    return 0;
                // Reading contentY keeps this binding reactive to scrolling.
                const scrollY = flickable.contentY;
                // mapToItem() itself is not reactive to layout-only position
                // changes; this explicit tick invalidates the binding after a
                // deferred layout pass.
                const layoutPass = animation.layoutTick;
                try {
                    return targetItem.mapToItem(flickable, 0, 0).y;
                } catch (error) {
                    return 0;
                }
            }

            // Check visibility with a generous buffer to begin the animation
            // before a delegate enters the viewport.
            readonly property bool isVisible: {
                if (!flickable || !targetItem || flickable.height <= 0
                        || flickable.contentHeight <= 0
                        || targetItem.width <= 0 || targetItem.height <= 0)
                    return true;

                const isBelowTop = (relativeY + targetItem.height) >= -60;
                const isAboveBottom = relativeY <= (flickable.height + 100);
                return isBelowTop && isAboveBottom;
            }

            // Keep opacity out of this controller. Several settings controls
            // use `visible: opacity > 0`; hiding them here removes them from
            // their Layout, changes contentHeight, and can leave them stuck
            // until a scroll event invalidates mapToItem().
            readonly property real targetScale: isVisible ? 1.0 : 0.92
            readonly property real targetTranslateY: isVisible ? 0 : 20
            property real animatedScale: 0.92
            property real animatedTranslateY: 20

            Binding {
                target: animation
                property: "animatedScale"
                value: animation.targetScale
            }

            Binding {
                target: animation
                property: "animatedTranslateY"
                value: animation.targetTranslateY
            }

            Behavior on animatedScale {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Behavior on animatedTranslateY {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Component.onCompleted: {
                findFlickable();
                if (!flickable)
                    retryTimer.start();
                attachTransform();
                scheduleLayoutRefresh();
            }

            onTargetItemChanged: {
                retryTimer.stop();
                detachTransform();
                findFlickable();
                if (!flickable)
                    retryTimer.start();
                attachTransform();
                scheduleLayoutRefresh();
            }

            Connections {
                target: animation.targetItem
                ignoreUnknownSignals: true

                function onYChanged() {
                    animation.scheduleLayoutRefresh();
                }

                function onHeightChanged() {
                    animation.scheduleLayoutRefresh();
                }

                function onParentChanged() {
                    animation.findFlickable();
                    animation.scheduleLayoutRefresh();
                }
            }

            Connections {
                target: animation.flickable
                ignoreUnknownSignals: true

                function onHeightChanged() {
                    animation.scheduleLayoutRefresh();
                }

                function onContentHeightChanged() {
                    animation.scheduleLayoutRefresh();
                }
            }

            Component.onDestruction: {
                retryTimer.stop();
                detachTransform();
            }
        }
    }
}
