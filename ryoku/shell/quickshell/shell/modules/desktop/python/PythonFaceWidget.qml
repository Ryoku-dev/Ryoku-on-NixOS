pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"
import "PythonRoster.js" as PythonRoster

Item {
    id: adapter

    property string faceId: "time"
    property string prefix: "pythonTime"
    property var screen: null
    property string inkColorA: ""
    property real scaleCfg: 1

    readonly property var rosterFace: PythonRoster.byPrefix(adapter.prefix)
    readonly property var options: {
        const raw = Config[adapter.prefix + "Opts"];
        if (raw && typeof raw === "object")
            return raw;
        if (!raw || String(raw).length === 0)
            return ({});
        try {
            const parsed = JSON.parse(String(raw));
            return parsed && typeof parsed === "object" ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }
    readonly property string selectedVariant: {
        const variants = adapter.rosterFace ? adapter.rosterFace.variants : ["default"];
        const saved = Config[adapter.prefix + "Variant"] || "";
        return variants.indexOf(saved) >= 0 ? saved : variants[0];
    }
    readonly property string selectedImage: adapter.faceId === "image" && typeof adapter.options.imagePath === "string"
        ? adapter.options.imagePath : ""
    readonly property bool ryokuStyle: Config[adapter.prefix + "Style"] === "ryoku"
    readonly property color hostOverride: adapter.inkColorA.length > 0 ? adapter.inkColorA : "transparent"
    readonly property int screenW: adapter.screen ? adapter.screen.width : 1920
    readonly property int screenH: adapter.screen ? adapter.screen.height : 1080

    implicitWidth: faceProvider.implicitWidth
    implicitHeight: faceProvider.implicitHeight
    width: implicitWidth
    height: implicitHeight

    PythonFaceProvider {
        id: faceProvider
        faceId: adapter.faceId
        variant: adapter.selectedVariant
        screenW: adapter.screenW
        screenH: adapter.screenH
        imagePath: adapter.selectedImage
        ryokuStyle: adapter.ryokuStyle
        inkOverride: adapter.hostOverride
        accentOverride: adapter.hostOverride
        sizeOverride: adapter.selectedVariant
        scaleOverride: adapter.scaleCfg
        radiusOverride: Config[adapter.prefix + "Radius"]
        optionOverrides: adapter.options
    }

    Binding {
        target: faceProvider.item
        property: "parent"
        value: adapter
        when: faceProvider.item !== null
    }
    Binding {
        target: faceProvider.item
        property: "visible"
        value: true
        when: faceProvider.item !== null
    }
}
