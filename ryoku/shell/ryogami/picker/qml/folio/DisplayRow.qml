import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: row

    property var state
    property var options
    property real reveal: 1
    property var controls: []

    implicitHeight: col.implicitHeight

    function _control(match) {
        for (var i = 0; i < row.controls.length; i++) {
            var c = row.controls[i];
            if (c.id && c.id.indexOf(match) >= 0)
                return c;
        }
        return ({});
    }
    readonly property var _fillControl: row._control("fillModes")
    readonly property var _lockControl: row._control("outputLocks")

    Column {
        id: col
        width: row.width
        spacing: 10 * Theme.scale

        Text {
            width: parent.width
            visible: Library.outputs.length === 0
            text: I18n.tr("No displays detected.")
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontBody
            color: Theme.withAlpha(Theme.surfaceText, 0.5 * row.reveal)
            renderType: Text.NativeRendering
        }

        Repeater {
            model: Library.outputs

            delegate: StackBar {
                id: outCard
                required property var modelData
                required property int index
                width: col.width
                expanded: outCard.index === 0
                title: {
                    var o = outCard.modelData;
                    var size = (o.width && o.height) ? ("  " + o.width + "\u00d7" + o.height) : "";
                    return (o.name ? o.name : I18n.tr("Display")) + size + (o.focused ? "  \u25cf" : "");
                }

                readonly property string _name: outCard.modelData.name ? String(outCard.modelData.name) : ""
                readonly property var _current: outCard.modelData.current ? outCard.modelData.current : ({})
                readonly property bool _hasAudio: outCard._current && (outCard._current.type === "video" || outCard._current.type === "we")
                // The catalogue thumbnail stands in for videos and scenes, which an Image cannot show.
                readonly property string _preview: {
                    var c = outCard._current
                    if (!c || !c.path)
                        return ""
                    var e = c.key ? Library.entry(c.type === "we" ? "workshop" : "wallpapers", c.key) : null
                    var p = (e && (e.thumb || e.thumbSm)) ? (e.thumb || e.thumbSm) : (c.type === "static" ? String(c.path) : "")
                    return Library.fileUrl(p)
                }

                Column {
                    parent: outCard.body
                    width: outCard.body.width
                    spacing: 12 * Theme.scale
                    topPadding: 6 * Theme.scale
                    bottomPadding: 8 * Theme.scale

                    Rectangle {
                        width: 220 * Theme.scale
                        height: width * 9 / 16
                        color: Theme.withAlpha(Theme.background, 0.9)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.4)
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: outCard._preview
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            visible: source != ""
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !outCard._current || !outCard._current.path
                            text: I18n.tr("Nothing applied")
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontBase
                            color: Theme.withAlpha(Theme.surfaceText, 0.5)
                            renderType: Text.NativeRendering
                        }
                    }

                    // An unset display shows the global placement it inherits; a pick writes its own.
                    ChoiceRow {
                        width: parent.width
                        state: row.state
                        options: row.options
                        control: row._fillControl
                        keyOverride: "display.fillModes." + outCard._name
                        bound: false
                        property SettingValue ownFill: SettingValue { key: "display.fillModes." + outCard._name }
                        property SettingValue globalFill: SettingValue { key: "display.fillMode" }
                        boundValue: ["fill", "fit", "stretch", "center", "tile", "span"].indexOf(ownFill.value) >= 0
                            ? ownFill.value : globalFill.value
                        onEdited: (v) => ownFill.set(v)
                    }

                    ToggleRow {
                        width: parent.width
                        state: row.state
                        control: row._lockControl
                        keyOverride: "display.outputLocks." + outCard._name
                    }

                    Item {
                        width: parent.width
                        height: Math.max(colourLabel.implicitHeight, colourBtn.height)
                        Text {
                            id: colourLabel
                            anchors.left: parent.left
                            anchors.right: colourBtn.left
                            anchors.rightMargin: 10 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Use this display's colours")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontField
                            color: Theme.withAlpha(Theme.surfaceText, row.reveal)
                            elide: Text.ElideRight
                        }
                        FixedButton {
                            id: colourBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            minWidth: 92
                            active: String(Settings.value("display.themeOutput")) === outCard._name
                            label: active ? I18n.tr("Source") : I18n.tr("Off")
                            onTriggered: Settings.set("display.themeOutput", active ? "" : outCard._name)
                        }
                    }

                    Column {
                        width: parent.width
                        visible: outCard._hasAudio
                        spacing: 6 * Theme.scale

                        Row {
                            spacing: 10 * Theme.scale
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Audio")
                                font.family: Theme.sans
                                font.weight: Font.Medium
                                font.pixelSize: Theme.fontField
                                color: Theme.withAlpha(Theme.surfaceText, row.reveal)
                                renderType: Text.NativeRendering
                            }
                            FixedButton {
                                anchors.verticalCenter: parent.verticalCenter
                                minWidth: 84
                                active: !(outCard._current && outCard._current.mute === true)
                                label: active ? I18n.tr("Sound") : I18n.tr("Muted")
                                onTriggered: Daemon.call("wall.set_audio",
                                    { outputs: [outCard._name], mute: active }, null)
                            }
                        }
                        FolioSlider {
                            width: Math.min(parent.width, 260 * Theme.scale)
                            from: 0
                            to: 100
                            step: 1
                            value: outCard._current && outCard._current.volume !== undefined ? Number(outCard._current.volume) : 100
                            onReleased: (v) => Daemon.call("wall.set_audio",
                                { outputs: [outCard._name], volume: Math.round(v) }, null)
                        }
                    }

                    Item {
                        width: parent.width
                        height: Math.max(playLabel.implicitHeight, playBtn.height)
                        property bool _paused: outCard.modelData.manual_paused === true
                            || (outCard._current && outCard._current.manual_paused === true)
                        Text {
                            id: playLabel
                            anchors.left: parent.left
                            anchors.right: playBtn.left
                            anchors.rightMargin: 10 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Playback")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontField
                            color: Theme.withAlpha(Theme.surfaceText, row.reveal)
                            elide: Text.ElideRight
                        }
                        FixedButton {
                            id: playBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            minWidth: 92
                            active: !parent._paused
                            label: parent._paused ? I18n.tr("Paused") : I18n.tr("Playing")
                            onTriggered: {
                                parent._paused = !parent._paused;
                                Daemon.call("wall.pause",
                                    { outputs: [outCard._name], paused: parent._paused }, null);
                            }
                        }
                    }
                }
            }
        }
    }
}
