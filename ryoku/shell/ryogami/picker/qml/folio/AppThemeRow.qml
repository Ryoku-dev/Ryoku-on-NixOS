import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: row

    property var control: ({})
    property var state
    property var options
    property real reveal: 1

    property var _apps: []

    implicitHeight: col.implicitHeight

    Component.onCompleted: row._fetch()
    Connections {
        target: Daemon
        function onReconnected() { row._fetch() }
        function onEvent(name, data) {
            if (name === "ryogami.theme.apps.changed")
                row._fetch();
        }
    }

    function _fetch() {
        Daemon.call("theme.apps", ({}), function (result, error) {
            if (error && Object.keys(error).length > 0)
                return;
            var list = result && result.apps ? result.apps : (Array.isArray(result) ? result : []);
            row._apps = list;
        });
    }

    function _toggle(app, enabled) {
        row.state.runAction("SetAppTheme", { id: app.id, enabled: enabled });
        // Optimistic: reflect the new state until the daemon echoes it.
        var next = [];
        for (var i = 0; i < row._apps.length; i++) {
            var a = row._apps[i];
            if (a.id === app.id) {
                var copy = ({});
                for (var k in a) if (a.hasOwnProperty(k)) copy[k] = a[k];
                copy.enabled = enabled;
                next.push(copy);
            } else {
                next.push(a);
            }
        }
        row._apps = next;
    }

    Column {
        id: col
        width: row.width
        spacing: 8 * Theme.scale

        Text {
            width: parent.width
            visible: !!row.control.help && row.control.help.length > 0
            text: row.control.help ? row.control.help : ""
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontBase
            color: Theme.withAlpha(Theme.surfaceText, 0.56 * row.reveal)
            lineHeight: 1.38
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }

        Text {
            width: parent.width
            visible: row._apps.length === 0
            text: I18n.tr("No supported apps detected. Use Find apps after installing one.")
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontBase
            color: Theme.withAlpha(Theme.surfaceText, 0.5 * row.reveal)
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }

        Repeater {
            model: row._apps

            delegate: Item {
                id: appRow
                required property var modelData
                width: col.width
                height: Math.max(nameText.implicitHeight, appToggle.height) + 8 * Theme.scale

                readonly property bool _available: appRow.modelData.available === undefined || appRow.modelData.available === true

                Text {
                    id: nameText
                    anchors.left: parent.left
                    anchors.right: appToggle.left
                    anchors.rightMargin: 10 * Theme.scale
                    anchors.verticalCenter: parent.verticalCenter
                    text: appRow.modelData.name !== undefined ? appRow.modelData.name
                        : (appRow.modelData.label !== undefined ? appRow.modelData.label : String(appRow.modelData.id))
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontLabel
                    color: Theme.withAlpha(Theme.surfaceText, appRow._available ? row.reveal : 0.4 * row.reveal)
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }
                FixedButton {
                    id: appToggle
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: row.enabled && appRow._available
                    active: appRow.modelData.enabled === true
                    minWidth: 92
                    label: appRow.modelData.enabled === true ? I18n.tr("Enabled") : I18n.tr("Disabled")
                    onTriggered: row._toggle(appRow.modelData, !(appRow.modelData.enabled === true))
                }
            }
        }
    }
}
