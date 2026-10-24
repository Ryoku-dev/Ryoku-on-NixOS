import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: tile

    property var output: ({})
    property bool selected: false
    property string incomingThumb: ""
    property string currentThumb: ""
    property string fillMode: ""
    property bool locked: false
    property bool colourSource: false
    property bool incomingVideo: false
    property bool muted: false
    property int volume: 100
    property bool currentVideo: false
    property bool paused: false
    property bool manual: false

    signal toggled()
    signal placementPicked(string mode)
    signal lockToggled(bool wantLocked)
    signal coloursToggled()
    signal muteToggled(bool wantMuted)
    signal volumeMoved(int v)
    signal volumeReleased(int v)
    signal pauseToggled(bool wantManual)

    readonly property string _name: (tile.output && tile.output.name !== undefined) ? String(tile.output.name) : ""
    readonly property int _w: (tile.output && tile.output.width !== undefined) ? tile.output.width : 0
    readonly property int _h: (tile.output && tile.output.height !== undefined) ? tile.output.height : 0
    readonly property string _orientation: tile._w <= 0 ? ""
        : tile._w > tile._h ? I18n.tr("Landscape")
        : tile._w < tile._h ? I18n.tr("Portrait")
        : I18n.tr("Square")
    readonly property string _resolution: tile._w <= 0
        ? I18n.tr("Finding resolution")
        : (tile._w + " \u00d7 " + tile._h + "  \u00b7  " + tile._orientation)

    implicitHeight: frame.implicitHeight

    Rectangle {
        id: frame
        width: tile.width
        implicitHeight: body.implicitHeight + 18 * Theme.scale
        color: Theme.withAlpha(Theme.surfaceContainer, tile.selected ? 0.7 : 0.48)
        border.width: 1
        border.color: tile.selected
            ? Theme.withAlpha(Theme.surfaceText, 0.7)
            : Theme.withAlpha(Theme.outline, 0.5)

        Column {
            id: body
            x: 10 * Theme.scale
            y: 9 * Theme.scale
            width: parent.width - 20 * Theme.scale
            spacing: 9 * Theme.scale

            Rectangle {
                width: parent.width
                height: 88 * Theme.scale
                color: selHover.containsMouse
                    ? Theme.withAlpha(Theme.surfaceVariant, 0.5)
                    : Theme.withAlpha(Theme.surfaceContainer, 0.4)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.42)

                Row {
                    anchors.fill: parent
                    anchors.margins: 8 * Theme.scale
                    spacing: 13 * Theme.scale

                    Rectangle {
                        width: 132 * Theme.scale
                        height: parent.height
                        color: Theme.withAlpha(Theme.surfaceVariant, 0.4)
                        clip: true
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            source: tile.selected
                                ? (tile.incomingThumb.length > 0 ? tile.incomingThumb : tile.currentThumb)
                                : (tile.currentThumb.length > 0 ? tile.currentThumb : tile.incomingThumb)
                        }
                    }

                    Column {
                        width: parent.width - 132 * Theme.scale - markerText.width - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3 * Theme.scale

                        Text {
                            width: parent.width
                            text: tile._name
                            font.family: Theme.sans
                            font.weight: Font.DemiBold
                            font.pixelSize: Theme.fontHead
                            color: Theme.surfaceText
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: tile._resolution
                            font.family: Theme.display
                            font.pixelSize: Theme.fontSmall
                            color: Theme.withAlpha(Theme.surfaceText, 0.5)
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: tile.selected ? I18n.tr("New wallpaper") : I18n.tr("Current wallpaper")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontFine
                            color: Theme.withAlpha(Theme.surfaceText, 0.4)
                            renderType: Text.NativeRendering
                        }
                    }

                    Row {
                        id: markerText
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6 * Theme.scale
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6 * Theme.scale
                            height: 6 * Theme.scale
                            radius: width / 2
                            color: tile.selected ? Theme.withAlpha(Theme.surfaceText, 0.9) : "transparent"
                            border.width: tile.selected ? 0 : 1
                            border.color: Theme.withAlpha(Theme.surfaceText, 0.4)
                            Behavior on color { ColorAnimation { duration: Theme.fast } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tile.selected ? I18n.tr("Selected") : I18n.tr("Add")
                            font.family: Theme.sans
                            font.weight: tile.selected ? Font.DemiBold : Font.Medium
                            font.pixelSize: Theme.fontSmall
                            color: tile.selected ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.58)
                            renderType: Text.NativeRendering
                        }
                    }
                }
                MouseArea {
                    id: selHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.toggled()
                }
            }

            Row {
                width: parent.width
                spacing: 7 * Theme.scale
                Text {
                    width: 72 * Theme.scale
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Placement")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontFine
                    color: Theme.withAlpha(Theme.surfaceText, 0.46)
                    renderType: Text.NativeRendering
                }
                DisplayPlacementControl {
                    width: parent.width - 72 * Theme.scale - parent.spacing
                    current: tile.fillMode
                    onPicked: (mode) => tile.placementPicked(mode)
                }
            }

            Row {
                width: parent.width
                spacing: 7 * Theme.scale
                Text {
                    width: 72 * Theme.scale
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Lock")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontFine
                    color: Theme.withAlpha(Theme.surfaceText, 0.46)
                    renderType: Text.NativeRendering
                }
                FolioAction {
                    anchors.verticalCenter: parent.verticalCenter
                    fixedWidth: 92 * Theme.scale
                    label: tile.locked ? I18n.tr("Locked") : I18n.tr("Unlocked")
                    active: tile.locked
                    onTriggered: tile.lockToggled(!tile.locked)
                }
            }

            Row {
                width: parent.width
                spacing: 7 * Theme.scale
                Text {
                    width: 72 * Theme.scale
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Colours")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontFine
                    color: Theme.withAlpha(Theme.surfaceText, 0.46)
                    renderType: Text.NativeRendering
                }
                FolioAction {
                    anchors.verticalCenter: parent.verticalCenter
                    label: tile.colourSource ? I18n.tr("Colour source") : I18n.tr("Use for colours")
                    active: tile.colourSource
                    onTriggered: tile.coloursToggled()
                }
            }

            Row {
                width: parent.width
                spacing: 7 * Theme.scale
                visible: tile.incomingVideo
                Text {
                    width: 72 * Theme.scale
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Audio")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontFine
                    color: Theme.withAlpha(Theme.surfaceText, 0.46)
                    renderType: Text.NativeRendering
                }
                DisplayAudioControl {
                    width: parent.width - 72 * Theme.scale - parent.spacing
                    muted: tile.muted
                    volume: tile.volume
                    playing: !tile.muted
                    onMuteToggled: (wantMuted) => tile.muteToggled(wantMuted)
                    onVolumeMoved: (v) => tile.volumeMoved(v)
                    onVolumeReleased: (v) => tile.volumeReleased(v)
                }
            }

            Row {
                width: parent.width
                spacing: 7 * Theme.scale
                visible: tile.currentVideo
                Text {
                    width: 72 * Theme.scale
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Wallpaper")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontFine
                    color: Theme.withAlpha(Theme.surfaceText, 0.46)
                    renderType: Text.NativeRendering
                }
                DisplayPlaybackControl {
                    anchors.verticalCenter: parent.verticalCenter
                    manual: tile.manual
                    paused: tile.paused
                    onPauseToggled: (wantManual) => tile.pauseToggled(wantManual)
                }
            }
        }
    }
}
