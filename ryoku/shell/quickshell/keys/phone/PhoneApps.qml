pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var client
    property string query: ""
    signal navigate(string section)
    signal requestClose()

    readonly property var adb: client.state.adb || ({ state: "none" })
    readonly property var scrcpy: client.state.scrcpy || ({ appMode: false })
    readonly property var appState: client.state.apps || ({ count: 0, loading: false, error: "" })
    readonly property bool available: String(adb.state || "none") === "device" && scrcpy.appMode === true
    readonly property var filtered: {
        const source = client.apps.filter(function(app) {
            if (!root.query)
                return true;
            return (String(app.label || "") + " " + String(app.package || "")).toLowerCase().indexOf(root.query) >= 0;
        });
        return source.slice().sort(function(a, b) {
            if ((a.favorite === true) !== (b.favorite === true))
                return a.favorite === true ? -1 : 1;
            return String(a.label || a.package || "").localeCompare(String(b.label || b.package || ""));
        });
    }

    function iconSource(path) {
        const value = String(path || "");
        return value.startsWith("/") ? "file://" + value : value;
    }

    function activate() {
        if (root.available)
            refresh.forceActiveFocus();
        else
            screenLink.forceActiveFocus();
    }

    function handleEscape() {
        return false;
    }

    Column {
        anchors.fill: parent
        spacing: Tokens.s3

        Row {
            width: parent.width
            height: Tokens.s6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - refresh.width
                text: root.appState.loading === true ? I18n.tr("Reading installed apps...")
                    : root.filtered.length === 0 ? I18n.tr("Android apps")
                    : root.filtered.length === 1 ? I18n.tr("1 app - favourites first")
                    : I18n.tr("%1 apps - favourites first").arg(root.filtered.length)
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                elide: Text.ElideRight
            }
            Btn {
                id: refresh
                visible: root.available
                compact: true
                text: I18n.tr("REFRESH")
                armed: root.appState.loading !== true
                onAct: root.client.call("appsRefresh", [])
            }
        }

        Rectangle {
            visible: !root.available
            width: parent.width
            implicitHeight: blocked.implicitHeight + Tokens.s5 * 2
            radius: Tokens.radius
            color: Tokens.paperLift
            border.width: Tokens.border
            border.color: Tokens.lineSoft
            Column {
                id: blocked
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.s5
                spacing: Tokens.s3
                Text {
                    width: parent.width
                    text: String(root.adb.state || "none") !== "device"
                        ? I18n.tr("Android apps need USB debugging before they can open on this computer.")
                        : I18n.tr("This scrcpy version cannot open one Android app at a time.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody
                    wrapMode: Text.WordWrap
                }
                Btn {
                    id: screenLink
                    text: I18n.tr("OPEN SCREEN SETUP")
                    primary: true
                    onAct: root.navigate("screen")
                }
            }
        }

        GridView {
            id: grid
            visible: root.available
            width: parent.width
            height: parent.height - Tokens.s6 - parent.spacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            readonly property int columns: Math.max(3, Math.floor(width / 128))
            cellWidth: width / columns
            cellHeight: 130
            model: root.filtered
            QQC.ScrollBar.vertical: ScrollRail {
                policy: QQC.ScrollBar.AsNeeded
                visible: grid.contentHeight > grid.height + 1
            }
            WheelScroll { }

            delegate: Item {
                id: appCell
                required property var modelData
                required property int index
                property bool entered: Tokens.reduceMotion
                width: grid.cellWidth
                height: grid.cellHeight
                opacity: entered ? 1 : 0
                transform: Translate { y: appCell.entered ? 0 : Tokens.s2 }
                Component.onCompleted: delay.start()
                Timer {
                    id: delay
                    interval: Tokens.reduceMotion ? 0 : Math.min(appCell.index, 10) * 20
                    onTriggered: appCell.entered = true
                }
                Behavior on opacity {
                    enabled: !Tokens.reduceMotion
                    NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Tokens.s1
                    radius: Tokens.radius
                    color: launch.down ? Tokens.tint16 : launch.hovered ? Tokens.tint10 : Tokens.paperLift
                    border.width: Tokens.border
                    border.color: appCell.modelData.running === true || appCell.modelData.favorite === true
                        ? Tokens.lineStrong : Tokens.lineSoft
                    scale: launch.down ? 0.985 : launch.hovered ? 1.008 : 1
                    Behavior on color {
                        enabled: !Tokens.reduceMotion
                        ColorAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: !Tokens.reduceMotion
                        NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
                    }

                    QQC.AbstractButton {
                        id: launch
                        anchors.fill: parent
                        anchors.rightMargin: Tokens.s6
                        hoverEnabled: true
                        background: Item { }
                        contentItem: Column {
                            anchors.centerIn: parent
                            width: parent.width - Tokens.s3 * 2
                            spacing: Tokens.s2
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 60
                                height: 60
                                radius: Tokens.radius
                                color: Tokens.tint10
                                clip: true
                                Image {
                                    id: icon
                                    anchors.fill: parent
                                    anchors.margins: Tokens.s1
                                    source: root.iconSource(appCell.modelData.icon)
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }
                                Text {
                                    visible: icon.status !== Image.Ready
                                    anchors.centerIn: parent
                                    text: "android"
                                    color: Tokens.inkDim
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: Tokens.fValue
                                }
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: String(appCell.modelData.label || appCell.modelData.package || I18n.tr("App"))
                                color: Tokens.ink
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                        onClicked: {
                            root.client.call("appLaunch", [String(appCell.modelData.package || "")]);
                            root.requestClose();
                        }
                    }

                    IconBtn {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Tokens.s1
                        glyph: appCell.modelData.favorite === true ? "★" : "☆"
                        Accessible.name: I18n.tr("Favourite app")
                        onAct: root.client.call("favoriteApp", [String(appCell.modelData.package || ""), appCell.modelData.favorite === true ? "false" : "true"])
                    }

                    Rectangle {
                        visible: appCell.modelData.running === true
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: Tokens.s2
                        width: runningText.implicitWidth + Tokens.s2
                        height: Tokens.s5
                        radius: height / 2
                        color: Tokens.bone
                        Text {
                            id: runningText
                            anchors.centerIn: parent
                            text: I18n.tr("RUNNING")
                            color: Tokens.inkOnBone
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fTiny
                            font.letterSpacing: Tokens.trackLabel
                        }
                        Behavior on opacity {
                            enabled: !Tokens.reduceMotion
                            NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            Column {
                visible: grid.count === 0 && root.appState.loading !== true
                anchors.top: parent.top
                anchors.topMargin: Tokens.s5
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: Tokens.s3
                spacing: Tokens.s3
                Text {
                    width: parent.width
                    text: root.query ? I18n.tr("No apps match this search.")
                        : String(root.appState.error || "").length > 0 ? String(root.appState.error)
                        : I18n.tr("No Android apps are available yet. Refresh after your phone is connected.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody
                    wrapMode: Text.WordWrap
                }
                Btn {
                    text: I18n.tr("REFRESH")
                    onAct: root.client.call("appsRefresh", [])
                }
            }
        }
    }
}
