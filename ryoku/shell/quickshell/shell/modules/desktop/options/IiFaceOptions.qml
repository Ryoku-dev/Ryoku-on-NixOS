pragma ComponentBehavior: Bound
import QtQuick
import stage.modules.ii.background.widgets
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
}
