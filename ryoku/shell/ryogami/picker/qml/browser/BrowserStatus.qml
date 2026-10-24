import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: strip

    property string error: ""
    property bool loading: false
    property string sourceLabel: ""
    property int count: 0
    property bool pendingApply: false
    property var applyItem: null
    property int active: 0
    property int queued: 0
    property var activeItem: null
    property var queuedItem: null
    property var sources: null

    readonly property var _state: strip._compute()
    readonly property string message: _state.text
    readonly property bool isError: _state.err

    implicitHeight: message.length > 0 ? (row.implicitHeight + 12 * Theme.scale) : 0
    visible: message.length > 0

    function _compute() {
        if (strip.error.length > 0 && strip.count > 0)
            return { text: strip.error, err: true }
        if (strip.pendingApply) {
            var at = strip.applyItem
            var lbl = (strip.sources && at) ? strip.sources.progressLabel(I18n.tr("Applying"), at) : I18n.tr("Applying\u2026")
            return { text: lbl, err: false }
        }
        var a = strip.active, q = strip.queued
        if (a + q > 1) {
            if (q === 0) return { text: I18n.tr("Downloading %1\u2026").arg(a), err: false }
            if (a === 0) return { text: I18n.tr("%1 queued\u2026").arg(q), err: false }
            return { text: I18n.tr("Downloading %1 \u00b7 %2 queued\u2026").arg(a).arg(q), err: false }
        }
        if (a === 1) {
            var it = strip.activeItem
            var t = (strip.sources && it) ? strip.sources.progressLabel(I18n.tr("Downloading"), it) : I18n.tr("Downloading\u2026")
            return { text: t, err: false }
        }
        if (q === 1) {
            var qt = strip.queuedItem
            var phase = (strip.sources && qt) ? strip.sources.downloadPhase(qt.downloadStatus) : ""
            return { text: phase.length > 0 ? (phase + "\u2026") : I18n.tr("Queued\u2026"), err: false }
        }
        if (strip.loading && strip.count > 0)
            return { text: I18n.tr("Searching %1\u2026").arg(strip.sourceLabel), err: false }
        return { text: "", err: false }
    }

    Rectangle {
        anchors.fill: parent
        visible: strip.message.length > 0
        color: strip.isError
            ? Theme.withAlpha(Theme.tertiary, 0.12)
            : Theme.withAlpha(Theme.surface, 0.85)

        Row {
            id: row
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10 * Theme.scale
            anchors.rightMargin: 10 * Theme.scale
            spacing: 8 * Theme.scale

            BrowserSpinner {
                anchors.verticalCenter: parent.verticalCenter
                visible: !strip.isError
                size: 12
                color: Theme.surfaceText
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, strip.width - 30 * Theme.scale)
                text: strip.message
                elide: Text.ElideRight
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontBody
                color: strip.isError ? Theme.tertiary : Theme.surfaceText
                renderType: Text.NativeRendering
            }
        }
    }
}
