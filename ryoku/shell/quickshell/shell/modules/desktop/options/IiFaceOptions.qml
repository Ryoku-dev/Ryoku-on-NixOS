pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons
import stage.modules.ii.background.widgets
import stage.modules.common as StageCommon
import "../Singletons" as WidgetStore
import "../ii/IiRoster.js" as IiRoster

// Options for a hosted ii desktop widget: the widget's own Settings page from
// the vendored ii library, resolved through the stage's widget registry. The
// page renders headerless at its full content height, so the inspector's band
// scroller reveals it; every control writes the stage config the face reads,
// the same store the Stage Editor edits.
Item {
    id: opts

    property string widget: ""
    readonly property var face: IiRoster.byPrefix(opts.widget)
    readonly property url pageUrl: opts.face ? WidgetsRegistry.getConfigPagePath(opts.face.id) : ""
    readonly property string widgetId: opts.face ? opts.face.id : ""
    property var previousWidgetCountProvider: null

    QtObject {
        id: hostedWidgetCountProvider

        function count(widgetId) {
            const entry = IiRoster.byId(widgetId);
            if (!entry)
                return -1;
            if (!WidgetStore.Config.ready)
                return 0;
            const key = entry.prefix + "Enabled";
            const outputs = Wm.outputs || [];
            if (outputs.length === 0) {
                const monitor = WidgetStore.Config.writeMonitor || "";
                return WidgetStore.Config.get(key, monitor) === true ? 1 : 0;
            }
            let count = 0;
            const seen = {};
            for (let i = 0; i < outputs.length; i++) {
                const name = String(outputs[i]?.name ?? "");
                if (name === "" || seen[name])
                    continue;
                seen[name] = true;
                if (WidgetStore.Config.get(key, name) === true)
                    count++;
            }
            return count;
        }
    }

    Component.onCompleted: {
        opts.previousWidgetCountProvider = StageCommon.Config.widgetCountProvider;
        StageCommon.Config.widgetCountProvider = hostedWidgetCountProvider;
    }
    Component.onDestruction: {
        if (StageCommon.Config.widgetCountProvider === hostedWidgetCountProvider)
            StageCommon.Config.widgetCountProvider = opts.previousWidgetCountProvider;
    }

    width: parent ? parent.width : 0
    implicitHeight: pageLoader.height

    Loader {
        id: pageLoader
        width: parent.width
        active: opts.pageUrl.toString().length > 0
        source: opts.pageUrl
        // The page is a full-height flickable by design; hosted, it opens to
        // its whole content so the inspector's own scroller owns the motion.
        height: item && item.flickable ? Math.max(64, item.flickable.contentHeight) : 0
        onLoaded: {
            if (item.hasOwnProperty("headerVisible"))
                item.headerVisible = false;
            if (item.hasOwnProperty("bottomContentPadding"))
                item.bottomContentPadding = 8;
        }
    }

    Binding {
        target: pageLoader.item
        property: "widget"
        value: opts.widget
        when: pageLoader.item !== null && pageLoader.item.hasOwnProperty("widget")
    }
    Binding {
        target: pageLoader.item
        property: "widgetId"
        value: opts.widgetId
        when: pageLoader.item !== null && pageLoader.item.hasOwnProperty("widgetId")
    }
    Binding {
        target: pageLoader.item
        property: "faceId"
        value: opts.widgetId
        when: pageLoader.item !== null && pageLoader.item.hasOwnProperty("faceId")
    }
}
