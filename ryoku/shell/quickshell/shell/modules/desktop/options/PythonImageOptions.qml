pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import "PythonOpts.js" as PythonOpts

// Options for the Python image widget: the picture to show and how it fits.
// The path is typed here (the same affordance the iRiS custom-image panel
// uses) rather than embedding Serpantinum's file chooser, whose relative
// imports would drag the style's own singletons into the desktop tree. Values
// persist in the widget's <prefix>Opts JSON, which PythonFaceWidget pushes into
// the live face.
Column {
    id: opts

    property string widget: ""
    width: parent ? parent.width : 0
    spacing: Theme.s1

    readonly property var store: PythonOpts.read(Config, opts.widget)
    readonly property string imagePath: String(opts.store.imagePath || "")
    readonly property bool fitCrop: opts.store.fitCrop === true

    MenuSection { label: I18n.tr("Image"); gloss: "画像" }
    MenuTextField {
        label: I18n.tr("Picture")
        placeholder: I18n.tr("Image path")
        text: opts.imagePath
        onCommitted: (v) => PythonOpts.put(Config, opts.widget, "imagePath", v.trim())
    }
    MenuRow {
        visible: opts.imagePath !== ""
        label: I18n.tr("Fit")
        value: opts.fitCrop ? I18n.tr("Crop to fill") : I18n.tr("Show whole")
        closeOnTrigger: false
        onTriggered: PythonOpts.put(Config, opts.widget, "fitCrop", !opts.fitCrop)
    }
    MenuRow {
        visible: opts.imagePath !== ""
        label: I18n.tr("Clear")
        onTriggered: PythonOpts.put(Config, opts.widget, "imagePath", "")
    }
}
