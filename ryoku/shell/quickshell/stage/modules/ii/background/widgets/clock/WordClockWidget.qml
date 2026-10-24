pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.ii.background.widgets
AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_word"
    readonly property var cfg: Config.options.background.widgets.clock_word
    implicitWidth: cfg.size ?? 240
    implicitHeight: cfg.size ?? 240

    readonly property int hourNumber: {
        const h = DateTime.clock.hours % 12;
        return h === 0 ? 12 : h;
    }
    readonly property string hourWord: numberWord(hourNumber)
    readonly property int minuteNumber: DateTime.clock.minutes
    readonly property string minuteTensWord: minuteNumber >= 10 && minuteNumber <= 19
                                             ? numberWord(minuteNumber)
                                             : numberWord(Math.floor(minuteNumber / 10) * 10)
    readonly property string minuteOnesWord: (minuteNumber >= 10 && minuteNumber <= 19) || minuteNumber % 10 === 0
                                             ? ""
                                             : numberWord(minuteNumber % 10)

    function numberWord(value) {
        const words = [Translation.tr("Zero"), Translation.tr("One"), Translation.tr("Two"), Translation.tr("Three"), Translation.tr("Four"), Translation.tr("Five"), Translation.tr("Six"), Translation.tr("Seven"), Translation.tr("Eight"), Translation.tr("Nine"), Translation.tr("Ten"), Translation.tr("Eleven"), Translation.tr("Twelve"), Translation.tr("Thirteen"), Translation.tr("Fourteen"), Translation.tr("Fifteen"), Translation.tr("Sixteen"), Translation.tr("Seventeen"), Translation.tr("Eighteen"), Translation.tr("Nineteen"), Translation.tr("Twenty"), Translation.tr("Thirty"), Translation.tr("Forty"), Translation.tr("Fifty")];
        if (value <= 19) return words[value];
        return words[18 + Math.floor(value / 10)];
    }

    StyledDropShadow {
        target: backgroundShape
        visible: backgroundShape.visible && (Config.options.background.widgets.enableShadows ?? false)
    }

    MaterialShape {
        id: backgroundShape
        anchors.fill: parent
        visible: (root.cfg.backgroundStyle ?? "shape") === "shape"
        color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
        shapeString: root.cfg.backgroundShape ?? "Circle"
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.60
        spacing: -root.height * 0.025

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: font.pixelSize * 1.08
            text: root.hourWord
            color: WidgetColorScheme.accentColor
            font.pixelSize: Math.min(root.height * 0.16, root.width * 1.05 / Math.max(1, text.length))
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: font.pixelSize * 1.08
            text: root.minuteTensWord
            color: WidgetColorScheme.textColorOnBg
            font.pixelSize: Math.min(root.height * 0.16, root.width * 1.05 / Math.max(1, text.length))
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? font.pixelSize * 1.08 : 0
            text: root.minuteOnesWord
            color: WidgetColorScheme.textColorOnBg
            font.pixelSize: Math.min(root.height * 0.16, root.width * 1.05 / Math.max(1, text.length))
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            visible: text !== ""
        }
    }
}
