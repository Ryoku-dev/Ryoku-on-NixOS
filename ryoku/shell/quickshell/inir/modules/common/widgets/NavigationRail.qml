import QtQuick
import QtQuick.Layouts
import inir.modules.common
import inir.modules.common.widgets

ColumnLayout { // Window content with navigation rail and content pane
    id: root
    property bool expanded: true
    property int currentIndex: 0
    spacing: 5
}
