pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui.Singletons

QQC.ScrollView {
    id: root
    required property real s
    required property var plugins
    required property bool active
    signal requestClose()
    implicitHeight: 380 * s
    contentWidth: availableWidth
    clip: true
    QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff
    Column {
        width: root.availableWidth
        spacing: 16 * root.s
        Repeater {
            model: root.plugins
            delegate: SidebarCardHost {
                required property var modelData
                required property int index
                width: root.availableWidth
                s: root.s
                cardId: modelData.id
                pluginEntry: modelData.entry
                cardIndex: index
                open: root.active
                reveal: root.active ? 1 : 0
                tabActive: root.active
                viewportHeight: root.height
                onRequestClose: root.requestClose()
            }
        }
    }
}
