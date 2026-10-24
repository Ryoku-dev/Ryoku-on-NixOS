import stage.services
import stage.modules.common
import stage.modules.common.widgets
import QtQuick

Item {
    id: root

    property color color: WidgetColorScheme.textColorOnBg
    property string style: Config.options.background.widgets.clock_cookie.dialNumberStyle // "dots", "numbers", "full", "hide"
    property string dateStyle : Config.options.background.widgets.clock_cookie.dateStyle

    // 12 Dots
    FadeLoader {
        id: dotsLoader
        anchors {
            fill: parent
            margins: 10
        }
        shown: root.style === "dots"
        sourceComponent: Dots {
            color: root.color
            margins: 46 - dotsLoader.opacity * 34
        }
    }

    // 3-6-9-12 hour numbers (pls don't realize you can have more than 4 numbers)
    FadeLoader {
        id: bigHourNumbersLoader
        anchors.fill: parent
        shown: root.style === "numbers"
        sourceComponent: BigHourNumbers {
            numberSize: 80
            color: root.color
            margins: 20 - 10 * bigHourNumbersLoader.opacity
        }
    }

    // Lines
    FadeLoader {
        id: linesLoader
        anchors {
            fill: parent
            margins: 10
        }
        shown: root.style === "full"
        sourceComponent: Lines {
            color: root.color
            margins: 46 - linesLoader.opacity * 34
        }
    }

    // Material Shapes
    FadeLoader {
        id: shapesLoader
        anchors {
            fill: parent
            margins: 10
        }
        shown: root.style === "shapes"
        sourceComponent: Shapes {
            color: root.color
            margins: 46 - shapesLoader.opacity * 34
        }
    }

}
