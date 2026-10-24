pragma ComponentBehavior: Bound

import QtQuick
import stage.modules.common
import stage.modules.common.widgets
import stage.services

Item {
    id: root

    property int hour: DateTime.clock.hours
    property bool use24h: false
    property bool boldFont: false
    property color color: WidgetColorScheme.textColorOnBg
    property real baseWidth: 240

    property real hourWidthScale: 1.0
    property real hourHeightScale: 1.0
    property real customPixelSize: 36
    property int customWeight: 700
    property int customWidth: 100
    property int customRound: 0

    readonly property string hourString: {
        var h = hour;
        if (!use24h) {
            h = h % 12;
            if (h === 0) h = 12;
        }
        return h < 10 && use24h ? "0" + h : "" + h;
    }

    width: hourText.implicitWidth
    height: hourText.implicitHeight

    StyledText {
        id: hourText
        anchors.centerIn: parent
        text: root.hourString
        color: root.color
        font {
            family: root.boldFont ? Appearance.font.family.display : Appearance.font.family.numbers
            pixelSize: Math.round(root.baseWidth * (root.customPixelSize / 100.0))
            weight: root.customWeight
            variableAxes: ({
                "wght": root.customWeight,
                "wdth": root.customWidth,
                "ROND": root.customRound
            })
        }
    }
}
