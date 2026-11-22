import QtQuick
import Lithic
import ".."

Item {
    id: seal

    property string badgeId: ""
    property string title: "RYOKU"
    property string sigil: "力"
    property string rarity: "common"
    property string category: "Ryoku"
    property bool locked: false
    property bool animateFoil: false

    readonly property bool animatedRarity: rarity === "mythic" || rarity === "holographic"
    readonly property bool moving: animatedRarity && visible && !locked && !Lithic.reduceMotion
    readonly property string assetBase: "../../assets/badges/" + badgeId
    readonly property string alternateSuffix: rarity === "holographic" ? ".foil.svg" : ".pulse.svg"

    implicitWidth: 150
    implicitHeight: 150
    clip: false
    Accessible.role: Accessible.Graphic
    Accessible.name: title + ", " + rarity + " achievement"

    Image {
        id: emblem
        anchors.fill: parent
        source: seal.visible && seal.badgeId !== "" ?
            Qt.resolvedUrl(seal.assetBase + ".svg") : ""
        sourceSize.width: Math.max(150, Math.round(width * 2))
        sourceSize.height: Math.max(150, Math.round(height * 2))
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        opacity: seal.locked ? 0.29 : 1
    }

    Image {
        id: foil
        anchors.fill: parent
        visible: seal.animatedRarity && !seal.locked && seal.badgeId !== ""
        source: visible ? Qt.resolvedUrl(seal.assetBase + seal.alternateSuffix) : ""
        sourceSize.width: Math.max(150, Math.round(width * 2))
        sourceSize.height: Math.max(150, Math.round(height * 2))
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        opacity: 0

        SequentialAnimation on opacity {
            running: seal.moving && foil.status === Image.Ready
            loops: Animation.Infinite
            NumberAnimation {
                from: 0
                to: 1
                duration: seal.rarity === "mythic" ? 1400 : 2600
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                from: 1
                to: 0
                duration: seal.rarity === "mythic" ? 1400 : 2600
                easing.type: Easing.InOutSine
            }
        }
    }

    Rectangle {
        visible: emblem.status === Image.Error
        anchors.centerIn: parent
        width: parent.width * 0.7
        height: width
        rotation: 45
        color: "transparent"
        border.color: Lithic.fg3
        border.width: 1
        Label {
            anchors.centerIn: parent
            text: "力"
            typeRole: "section"
        }
    }
}
