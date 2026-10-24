pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: page

    property string tab: "Scene"

    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + Tokens.s4
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        QQC.ScrollBar.vertical: ScrollRail {
            policy: QQC.ScrollBar.AsNeeded
        }
        WheelScroll {}

        Column {
            id: content
            width: scroll.width
            spacing: Tokens.s2

            Chips {
                width: parent.width
                options: ["Scene", "Layers", "Look", "Motion", "Front"]
                current: page.tab === "In front" ? "Front" : page.tab
                onChose: label => page.tab = label === "Front" ? "In front" : label
            }

            StageDepthOptions {
                width: parent.width
                section: page.tab
            }
        }
    }
}
