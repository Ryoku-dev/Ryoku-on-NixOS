import QtQuick

QtObject {
    required property real width
    required property real height
    required property bool configReady

    // Optional plugin discovery is independent from native and hosted widgets.
    // A missing plugin scanner must not blank Python, iRiS or ii widgets.
    readonly property bool ready: width > 0 && height > 0 && configReady
}
