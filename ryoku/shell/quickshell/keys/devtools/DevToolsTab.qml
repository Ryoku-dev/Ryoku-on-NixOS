pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons
import "."

Item {
    id: root

    property var kit
    readonly property bool kitReady: Boolean(kit && kit.ready)
    property string query: ""
    property bool current: false
    property string railCurrent: "password"
    property bool loadedOnce: false
    property bool restoredState: false
    property bool adjustingRail: false
    signal requestClose()

    readonly property var toolIndex: [
        { id: "password", name: I18n.tr("Password generator"), description: I18n.tr("Create a secure password with the character sets you choose.") },
        { id: "uuid", name: I18n.tr("UUID generator"), description: I18n.tr("Create a random UUID v4 or time-ordered UUID v7.") },
        { id: "json_formatter", name: I18n.tr("JSON formatter & validator"), description: I18n.tr("Format, minify, sort, and validate JSON data.") },
        { id: "base64", name: I18n.tr("Base64 encode/decode"), description: I18n.tr("Encode UTF-8 text or decode Base64 data.") },
        { id: "url_encode", name: I18n.tr("URL encode/decode"), description: I18n.tr("Encode or decode URL paths and query values.") },
        { id: "jwt_decoder", name: I18n.tr("JWT decoder"), description: I18n.tr("Read a token's header and payload without verifying its signature.") },
        { id: "unix_timestamp", name: I18n.tr("Unix timestamp"), description: I18n.tr("Convert epoch timestamps and dates into common time formats.") },
        { id: "color_converter", name: I18n.tr("Color converter"), description: I18n.tr("Convert colours between hex, RGB, and HSL.") },
        { id: "regex_tester", name: I18n.tr("Regex tester"), description: I18n.tr("Test a regular expression and inspect every match group.") },
        { id: "text_diff", name: I18n.tr("Text diff"), description: I18n.tr("Compare original and modified text line by line.") },
        { id: "chmod_calculator", name: I18n.tr("chmod calculator"), description: I18n.tr("Translate Unix permissions between octal and symbolic forms.") }
    ]
    readonly property var filteredTools: {
        const needle = query.trim().toLocaleLowerCase();
        if (needle.length === 0)
            return toolIndex;
        const terms = needle.split(/\s+/).filter(term => term.length > 0);
        return toolIndex.filter(tool => {
            const text = (tool.name + " " + tool.description).toLocaleLowerCase();
            return terms.every(term => text.includes(term));
        });
    }
    readonly property int matches: filteredTools.length
    readonly property var rail: filteredTools.map(tool => ({
        id: tool.id,
        label: tool.name,
        count: -1
    }))

    function validTool(id) {
        return toolIndex.some(tool => tool.id === id);
    }

    function visibleTool(id) {
        return filteredTools.some(tool => tool.id === id);
    }

    function setRail(value) {
        if (railCurrent === value)
            return;
        adjustingRail = true;
        railCurrent = value;
        adjustingRail = false;
    }

    function ensureRailCurrent() {
        if (filteredTools.length === 0) {
            setRail("");
            return;
        }
        let value = validTool(railCurrent) ? railCurrent : "password";
        if (!visibleTool(value))
            value = filteredTools[0].id;
        setRail(value);
    }

    function restoreTool() {
        if (restoredState || !kit || (kit.ready !== undefined && !kit.ready))
            return;
        let value = "password";
        try {
            value = String(kit.get("devtools.tool", "password"));
        } catch (error) {
            value = "password";
        }
        if (!validTool(value))
            value = "password";
        restoredState = true;
        setRail(value);
        ensureRailCurrent();
    }

    function activate() {
        loadedOnce = true;
        Qt.callLater(() => {
            if (body.item)
                body.item.activate();
        });
    }

    function handleEscape() {
        return body.item ? body.item.handleEscape() : false;
    }

    onCurrentChanged: if (current) activate()
    onKitChanged: {
        restoredState = false;
        restoreTool();
    }
    onKitReadyChanged: restoreTool()
    onQueryChanged: ensureRailCurrent()
    onRailCurrentChanged: {
        if (adjustingRail || !restoredState)
            return;
        if (!validTool(railCurrent) || !visibleTool(railCurrent)) {
            ensureRailCurrent();
            return;
        }
        try {
            if (kit)
                kit.set("devtools.tool", railCurrent);
        } catch (error) {
        }
    }
    Component.onCompleted: {
        restoreTool();
        if (current)
            activate();
    }


    Loader {
        id: body
        anchors.fill: parent
        active: root.loadedOnce
        sourceComponent: Component {
            DevToolsBody {
                kit: root.kit
                current: root.current
                railCurrent: root.railCurrent
                onRequestClose: root.requestClose()
            }
        }
    }
}
