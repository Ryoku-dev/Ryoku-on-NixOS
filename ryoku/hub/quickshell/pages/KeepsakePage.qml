pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import Ryoku.Ui.Singletons

Item {
    id: pg

    property var hub
    readonly property bool fullBleed: true

    // Replace these paragraphs with the real memories when the story is ready.
    property string beginning: [
        "Ryoku on NixOS started out as me wanting Ryoku on my desktop but it didn't support NixOS so I made it a",
        "reality and what I thought would be a simple QML port to the correct folders and a few commands turned",
        "into an entire repository with over 30,000 lines of translation code, removing arch assumptions, wrappers,",
        "scripts, compiling the whole 9 yards and throughout all of it, I never actually thought many people would",
        "actually use it but not even in the first 2 months of it being public theres been over 2,000 unique git",
        "clones and that to me is still insane to this day, so to each and every one of you, thank you, not only",
        "for installing and using this project of mine but also all the feedback, PR's and even all the issue",
        "reporting <3",
    ].join(" ")
    property string people: "The contributors behind Ryoku on NixOS, the ones who make this entire project a reality."
    property string letter: "Thank you from all of us for using Ryoku on NixOS, it means alot to us and I hope Ryoku is just as good as you expected it to be. Thank you for believing in us."

    readonly property var contributorMessages: [
        { name: "aethctl", role: "Lead Developer", quote: "Does tel aviv finally approve of my larp?", text: "", avatar: "../art/maintainers/aethctl.png", github: "https://github.com/aethctl" },
        { name: "feelyourwarmth", role: "Maintainer", quote: "I didnt do shit to Ryoku, why am I here", text: "", avatar: "../art/maintainers/feelyourwarmth.png", github: "https://github.com/feelyourwarmth" },
        { name: "Mo", role: "Tester", quote: "I just clicked things until something broke.", text: "", avatar: "../art/maintainers/mo.png", github: "" }
    ]

    readonly property url bundledSoundtrack: Qt.resolvedUrl("../art/maintainers/key-c418.mp3")

    Loader {
        id: soundtrackLoader
        active: true
        source: "KeepsakeSoundtrack.qml"
        visible: false
        onLoaded: { if (item) item.audioFile = pg.bundledSoundtrack; }
    }

    readonly property var earlyAdopters: [
        { name: "@Carlos Villanueva", avatar: "https://cdn.discordapp.com/avatars/339856219005124608/45be83891b4337f3dabd2b496cb32814.webp?size=20" },
        { name: "@Daman Weylin", avatar: "https://cdn.discordapp.com/avatars/371131660022054912/3b599df084e5f3d491a30881f7257222.webp?size=20" },
        { name: "@Gamegyf", avatar: "https://cdn.discordapp.com/avatars/937008103390597140/b3ed1f3c44380bc1e71cb07d86baa384.webp?size=20" },
        { name: "@Mo", avatar: "https://cdn.discordapp.com/avatars/279182706599002114/27080b3a67ff44965a66ae4e2b13a6d6.webp?size=20" },
        { name: "@Philia", avatar: "https://cdn.discordapp.com/avatars/1136169063912063017/1064c956223a5e5b4c6714f745df7ac2.webp?size=20" },
        { name: "@Prime_79", avatar: "https://cdn.discordapp.com/avatars/1276915638497054793/088a45e42e99e291b3950b5224a5aa58.webp?size=20" },
        { name: "@ZTZ-V1D", avatar: "https://cdn.discordapp.com/avatars/1117047178733572176/12d0ae408975f07952759337557b5ebb.webp?size=20" },
        { name: "@the random", avatar: "https://cdn.discordapp.com/avatars/1208809552301269032/460d0a802864f07fbed38642b8d400cb.webp?size=20" },
        { name: "@vxxn", avatar: "https://cdn.discordapp.com/avatars/1465711556607213588/3238ffe6aa00f34e36601af0810f87ae.webp?size=20" }
    ]

    property bool firstReveal: true
    property real darkness: 0
    property real titleReveal: 0
    property real storyReveal: 0
    property real letterReveal: 0
    property real glowPulse: 0.75

    function appear(value, offset) {
        return Math.max(0, Math.min(1, (value - offset) / (1 - offset)));
    }

    Component.onCompleted: revealAnimation.restart()

    Keys.onEscapePressed: {
        if (pg.hub) pg.hub.keepsakeOpen = false;
    }

    SequentialAnimation {
        id: revealAnimation
        NumberAnimation {
            target: pg; property: "darkness"; from: 0; to: 1
            duration: Tokens.dur(pg.firstReveal ? 1600 : 350)
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: pg; property: "titleReveal"; from: 0; to: 1
            duration: Tokens.dur(pg.firstReveal ? 1250 : 380)
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: pg; property: "storyReveal"; from: 0; to: 1
            duration: Tokens.dur(pg.firstReveal ? 1900 : 440)
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: pg; property: "letterReveal"; from: 0; to: 1
            duration: Tokens.dur(pg.firstReveal ? 950 : 340)
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        running: !Tokens.reduceMotion && pg.visible
        loops: Animation.Infinite
        NumberAnimation {
            target: pg; property: "glowPulse"; from: 0.65; to: 1.0
            duration: Math.max(1, Tokens.dur(5200)); easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: pg; property: "glowPulse"; from: 1.0; to: 0.65
            duration: Math.max(1, Tokens.dur(5200)); easing.type: Easing.InOutSine
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Tokens.paper
    }

    // A soft, theme-coloured halo contained within the Hub's page viewport.
    // No external window, compositor blur, shaders or extra dependencies.
    Repeater {
        model: 4
        Rectangle {
            required property int index
            anchors.fill: parent
            anchors.margins: Tokens.s2 + index * Tokens.s2
            radius: Tokens.radius + Tokens.s3
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(Tokens.sun.r, Tokens.sun.g, Tokens.sun.b,
                pg.darkness * pg.glowPulse * (0.10 - index * 0.019))
            opacity: 1
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Tokens.s5
        radius: Tokens.radius
        color: Tokens.paperLift
        border.width: Tokens.border
        border.color: Qt.rgba(Tokens.ink.r, Tokens.ink.g, Tokens.ink.b,
            0.20 * pg.darkness)
        opacity: pg.darkness
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        anchors.margins: Tokens.s5
        clip: true
        contentWidth: width
        contentHeight: stage.height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Item {
            id: stage
            width: scroll.width
            height: Math.max(scroll.height, content.y + content.implicitHeight + Tokens.s7)

            Column {
                id: content
                x: Math.round((stage.width - width) / 2)
                y: Tokens.s7
                width: Math.max(1, Math.min(840, stage.width - Tokens.s6 * 2))
                spacing: Tokens.s6

                Text {
                    width: parent.width
                    text: "The people behind Ryoku on NixOS"
                    color: Tokens.ink
                    font.family: Tokens.display
                    font.italic: true
                    font.pixelSize: Math.min(64, Math.max(Tokens.fTitle, content.width / 13))
                    lineHeight: 1.13
                    wrapMode: Text.WordWrap
                    opacity: pg.titleReveal
                    transform: Translate { y: (1 - pg.titleReveal) * Tokens.s4 }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Tokens.lineStrong
                    opacity: pg.storyReveal
                }

                Column {
                    width: parent.width
                    spacing: Tokens.s6
                    opacity: pg.storyReveal
                    transform: Translate { y: (1 - pg.storyReveal) * Tokens.s5 }

                    Column {
                        width: parent.width
                        spacing: Tokens.s3

                        Text {
                            width: parent.width
                            text: "How Ryoku on NixOS was made"
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fRow + 2
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: pg.beginning
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fBody + 1
                            lineHeight: 1.5
                            wrapMode: Text.WordWrap
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Tokens.s3

                        Text {
                            width: parent.width
                            text: "The people behind Ryoku on NixOS"
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fRow + 2
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: pg.people
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fBody + 1
                            lineHeight: 1.5
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: pg.contributorMessages
                            delegate: Item {
                                id: messageRow
                                required property int index
                                required property var modelData
                                width: parent.width
                                readonly property bool portraitFirst: index % 2 === 0
                                readonly property int portraitSize: width < 550 ? 72 : 100
                                height: Math.max(portraitSize, messageCopy.implicitHeight) + Tokens.s4
                                opacity: pg.appear(pg.storyReveal, Math.min(index * 0.12, 0.48))

                                Rectangle {
                                    id: portrait
                                    x: messageRow.portraitFirst ? 0 : messageRow.width - width
                                    y: (messageRow.height - height) / 2
                                    width: messageRow.portraitSize
                                    height: width
                                    radius: width / 2
                                    clip: true
                                    color: Tokens.paperLift
                                    border.width: 1
                                    border.color: Tokens.lineStrong

                                    Text {
                                        anchors.centerIn: parent
                                        text: String(messageRow.modelData.name || "?").slice(0, 1).toUpperCase()
                                        color: Tokens.inkMuted
                                        font.family: Tokens.display
                                        font.pixelSize: Tokens.fTitle
                                    }
                                    Image {
                                        anchors.fill: parent
                                        source: messageRow.modelData.avatar || ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        visible: status === Image.Ready
                                    }
                                }

                                Column {
                                    id: messageCopy
                                    x: messageRow.portraitFirst ? portrait.width + Tokens.s5 : 0
                                    y: (messageRow.height - height) / 2
                                    width: messageRow.width - portrait.width - Tokens.s5
                                    spacing: Tokens.s2

                                    Text {
                                        width: parent.width
                                        visible: !!messageRow.modelData.quote
                                        text: "“" + messageRow.modelData.quote + "”"
                                        color: Tokens.ink
                                        font.family: Tokens.display
                                        font.italic: true
                                        font.pixelSize: Tokens.fRow + 2
                                        lineHeight: 1.35
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: messageRow.portraitFirst ? Text.AlignLeft : Text.AlignRight
                                    }
                                    Text {
                                        visible: !!messageRow.modelData.text
                                        width: parent.width
                                        text: messageRow.modelData.text || ""
                                        color: Tokens.inkDim
                                        font.family: Tokens.ui
                                        font.pixelSize: Tokens.fBody
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: messageRow.portraitFirst ? Text.AlignLeft : Text.AlignRight
                                    }
                                    Row {
                                        id: contributorIdentity
                                        width: implicitWidth
                                        x: messageRow.portraitFirst ? 0 : parent.width - width
                                        spacing: Tokens.s2

                                        Text {
                                            id: contributorName
                                            text: messageRow.modelData.name
                                            color: "#FFFFFF"
                                            font.family: Tokens.mono
                                            font.pixelSize: Tokens.fSmall + 1
                                            font.weight: Font.Medium
                                            font.underline: contributorHover.containsMouse

                                            MouseArea {
                                                id: contributorHover
                                                anchors.fill: parent
                                                enabled: !!messageRow.modelData.github
                                                hoverEnabled: true
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: Qt.openUrlExternally(messageRow.modelData.github)
                                            }
                                        }
                                        Text {
                                            text: "- " + (messageRow.modelData.role || "")
                                            color: Tokens.inkDim
                                            font.family: Tokens.mono
                                            font.pixelSize: Tokens.fSmall + 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    opacity: pg.letterReveal
                    transform: Translate { y: (1 - pg.letterReveal) * Tokens.s4 }

                    Text {
                        width: parent.width
                        text: "a note to you, the user"
                        color: Tokens.ink
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fRow + 2
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: pg.letter
                        color: Tokens.ink
                        font.family: Tokens.display
                        font.italic: true
                        font.pixelSize: Tokens.fRow + 4
                        lineHeight: 1.45
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Tokens.lineStrong
                    }

                    Rectangle {
                        width: parent.width
                        height: adoptersContent.implicitHeight + Tokens.s4 * 2
                        color: Tokens.paperLift
                        radius: Tokens.radius
                        border.width: 1
                        border.color: Tokens.lineStrong

                        Column {
                            id: adoptersContent
                            x: Tokens.s4
                            y: Tokens.s4
                            width: Math.max(1, parent.width - Tokens.s4 * 2)
                            spacing: Tokens.s3

                            Text {
                                width: parent.width
                                text: "Early Adopters"
                                color: Tokens.ink
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fRow + 2
                                font.weight: Font.DemiBold
                            }

                            Flow {
                                width: parent.width
                                spacing: Tokens.s2

                                Repeater {
                                    model: pg.earlyAdopters
                                    delegate: Rectangle {
                                        id: adopterTag
                                        required property var modelData
                                        width: adopterRow.implicitWidth + Tokens.s3 * 2
                                        height: 30
                                        radius: height / 2
                                        color: Tokens.paper
                                        border.width: 1
                                        border.color: Tokens.line

                                        Row {
                                            id: adopterRow
                                            anchors.centerIn: parent
                                            spacing: Tokens.s2

                                            Rectangle {
                                                width: 20
                                                height: 20
                                                radius: 10
                                                color: Tokens.paperLift
                                                border.width: 1
                                                border.color: Tokens.lineStrong

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (String(adopterTag.modelData.name || "?").replace(/^@/, "").charAt(0) || "?").toUpperCase()
                                                    color: Tokens.inkDim
                                                    font.family: Tokens.ui
                                                    font.pixelSize: Tokens.fSmall
                                                }
                                                Image {
                                                    anchors.centerIn: parent
                                                    width: 14
                                                    height: 14
                                                    source: adopterTag.modelData.avatar || ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    visible: status === Image.Ready
                                                }
                                            }
                                            Text {
                                                text: adopterTag.modelData.name
                                                color: Tokens.ink
                                                font.family: Tokens.ui
                                                font.pixelSize: Tokens.fSmall
                                                font.weight: Font.Medium
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        id: c418Credit
                        width: parent.width
                        text: "Music: \"Key\" by C418"
                        color: Tokens.inkMuted
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fSmall
                        horizontalAlignment: Text.AlignHCenter
                        font.underline: creditHover.containsMouse

                        MouseArea {
                            id: creditHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally("https://c418.org/")
                        }
                    }

                }
            }
        }
    }
}
