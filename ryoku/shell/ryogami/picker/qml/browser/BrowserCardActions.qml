import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: actions

    property var item: null
    property var sources: null
    property bool applying: false
    property real reveal: 1
    // A running download can be stopped from its own button, except Workshop transfers.
    property bool cancellable: false

    signal save()
    signal apply()
    signal cancel()

    readonly property bool hovering: saveHover.containsMouse || applyHover.containsMouse
    readonly property bool _downloaded: !!item && item.downloaded === true
    readonly property bool _downloading: !!sources && sources.isDownloading(item)
    readonly property bool _queued: !!sources && sources.isQueued(item)

    Rectangle {
        visible: actions._downloaded || actions._queued
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 6 * Theme.scale
        anchors.topMargin: 6 * Theme.scale
        width: 70 * Theme.scale
        height: 22 * Theme.scale
        radius: Theme.radius
        color: actions._downloaded
            ? Theme.withAlpha(Theme.surfaceText, 0.96 * actions.reveal)
            : Theme.withAlpha(Theme.surface, 0.9 * actions.reveal)
        border.width: actions._queued ? 1 : 0
        border.color: Theme.withAlpha(Theme.outline, 0.55 * actions.reveal)
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast; easing.type: Theme.revealEasing } }

        Text {
            anchors.centerIn: parent
            text: actions._downloaded ? I18n.tr("\u2713 Saved") : I18n.tr("Queued")
            font.family: Theme.sans
            font.weight: Font.DemiBold
            font.pixelSize: Theme.fontSmall
            color: actions._downloaded
                ? Theme.withAlpha(Theme.surface, actions.reveal)
                : Theme.withAlpha(Theme.surfaceText, actions.reveal)
            renderType: Text.NativeRendering
        }
    }

    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6 * Theme.scale
        height: Math.min(34 * Theme.scale, parent.height)
        radius: Theme.radius
        color: Theme.withAlpha(Theme.surface, 0.9 * actions.reveal)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.5 * actions.reveal)

        Row {
            id: buttons
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 4 * Theme.scale
            anchors.rightMargin: 4 * Theme.scale
            spacing: 4 * Theme.scale

            readonly property bool compact: width < 138 * Theme.scale

            Rectangle {
                id: saveBtn
                width: buttons.compact
                    ? Math.max(0, Math.min(26 * Theme.scale, buttons.width * 0.34))
                    : Math.max(46 * Theme.scale, buttons.width - buttons.spacing - 64 * Theme.scale)
                height: 24 * Theme.scale
                radius: Theme.radius
                color: saveHover.containsMouse
                    ? Theme.withAlpha(Theme.surfaceText, 0.14 * actions.reveal)
                    : Theme.withAlpha(Theme.surfaceText, 0.06 * actions.reveal)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.34 * actions.reveal)

                Behavior on color { ColorAnimation { duration: Theme.fast } }

                Text {
                    anchors.centerIn: parent
                    width: Math.max(0, parent.width - 6 * Theme.scale)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: buttons.compact
                        ? (actions._downloading && actions.cancellable ? "\u{f0156}"
                           : (actions._downloaded ? "\u2713" : "\uf019"))
                        : (actions._downloaded
                            ? I18n.tr("\u2713 Saved")
                            : actions._downloading
                                ? (actions.cancellable && saveHover.containsMouse
                                    ? I18n.tr("Cancel")
                                    : (actions.sources ? actions.sources.progressLabel(I18n.tr("Saving"), actions.item) : I18n.tr("Saving")))
                                : I18n.tr("Save"))
                    font.family: buttons.compact ? Theme.icon : Theme.sans
                    font.weight: Font.DemiBold
                    font.pixelSize: Theme.fontSmall
                    color: Theme.withAlpha(Theme.surfaceText,
                        (actions._downloaded || actions._downloading ? 0.6 : 0.94) * actions.reveal)
                    renderType: Text.NativeRendering
                }
                MouseArea {
                    id: saveHover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !actions._downloaded && (!actions._downloading || actions.cancellable)
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: actions._downloading ? actions.cancel() : actions.save()
                }
            }

            Rectangle {
                id: applyBtn
                width: Math.max(0, buttons.width - saveBtn.width - buttons.spacing)
                height: 24 * Theme.scale
                radius: Theme.radius
                color: applyHover.containsMouse
                    ? Theme.withAlpha(Theme.surfaceText, 0.84 * actions.reveal)
                    : Theme.withAlpha(Theme.surfaceText, 0.97 * actions.reveal)

                Behavior on color { ColorAnimation { duration: Theme.fast } }

                Text {
                    anchors.centerIn: parent
                    width: Math.max(0, parent.width - 6 * Theme.scale)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: actions.applying
                        ? (actions._downloading && actions.sources
                            ? actions.sources.progressLabel(I18n.tr("Applying"), actions.item)
                            : I18n.tr("Applying"))
                        : I18n.tr("Apply")
                    font.family: Theme.sans
                    font.weight: Font.DemiBold
                    font.pixelSize: buttons.compact ? Theme.fontTiny : Theme.fontSmall
                    color: Theme.withAlpha(Theme.surface, (actions.applying ? 0.62 : 1.0) * actions.reveal)
                    renderType: Text.NativeRendering
                }
                MouseArea {
                    id: applyHover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !actions.applying
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: actions.apply()
                }
            }
        }
    }
}
