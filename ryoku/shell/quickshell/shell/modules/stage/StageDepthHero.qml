pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons

Preview {
    id: hero

    property string wallpaperUrl: ""
    property string subjectUrl: ""
    property string mode: ""
    property string state: ""
    property bool busy: false

    label: I18n.tr("WALLPAPER SCENE")
    tag: hero.mode.toUpperCase()
    live: hero.wallpaperUrl !== ""
    offText: I18n.tr("NO WALLPAPER")
    implicitHeight: Tokens.s7 * 5

    Item {
        anchors.fill: parent

        Image {
            id: wall
            anchors.fill: parent
            source: hero.wallpaperUrl
            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectCrop
            opacity: status === Image.Ready ? (hero.busy ? 0.48 : 0.72) : 0
            Behavior on opacity {
                NumberAnimation { duration: Tokens.swap; easing.type: Tokens.ease }
            }
        }

        Image {
            anchors.fill: parent
            visible: hero.subjectUrl !== ""
            source: hero.subjectUrl
            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectCrop
            opacity: status === Image.Ready ? (hero.busy ? 0.56 : 0.9) : 0
            Behavior on opacity {
                NumberAnimation { duration: Tokens.swap; easing.type: Tokens.ease }
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0
                    color: Qt.rgba(Tokens.paper.r, Tokens.paper.g, Tokens.paper.b, 0.02)
                }
                GradientStop {
                    position: 1
                    color: Qt.rgba(Tokens.paper.r, Tokens.paper.g, Tokens.paper.b, 0.92)
                }
            }
        }

        Column {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: Tokens.s4
            }
            spacing: Tokens.s1

            Text {
                width: parent.width
                text: hero.mode
                color: Tokens.ink
                font.family: Tokens.display
                font.pixelSize: Tokens.fHero
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: hero.state
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
