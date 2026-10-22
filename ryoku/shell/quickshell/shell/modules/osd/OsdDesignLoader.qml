pragma ComponentBehavior: Bound

import QtQuick
import shell.services

Loader {
    id: root

    required property string kind
    required property var screen
    property real us: 1
    property bool shown: false
    property real value: 0
    property real maxValue: 1
    property bool muted: false
    property string icon: ""
    property url iconSource: ""
    property string label: ""

    // A broken receipt stays on the shipped visual until its resolved URL changes.
    property string failedUrl: ""
    property string loadedUrl: ""
    readonly property string requestedUrl: Designs.osdUrl
    readonly property bool storeRuns: Designs.osdReady
        && Designs.osd !== Designs.shipped
        && root.requestedUrl !== ""
        && root.requestedUrl !== root.failedUrl
    readonly property string placement: {
        if (!root.item || typeof root.item.placement !== "string")
            return "bottom";
        const place = root.item.placement;
        return place === "top" || place === "left" || place === "right"
            || place === "center" ? place : "bottom";
    }
    readonly property real reveal: root.item
        && typeof root.item.reveal === "number" ? root.item.reveal : 0

    active: root.storeRuns
    asynchronous: true
    visible: root.storeRuns

    function load() {
        if (!root.storeRuns || root.loadedUrl === root.requestedUrl)
            return;
        root.loadedUrl = root.requestedUrl;
        root.setSource(root.requestedUrl, {
            kind: root.kind,
            screen: root.screen,
            us: root.us,
            shown: root.shown,
            value: root.value,
            maxValue: root.maxValue,
            muted: root.muted,
            icon: root.icon,
            iconSource: root.iconSource,
            label: root.label
        });
    }

    onRequestedUrlChanged: {
        root.loadedUrl = "";
        if (root.storeRuns)
            Qt.callLater(root.load);
    }
    onStoreRunsChanged: {
        if (!root.storeRuns) {
            // Clear the URL as well as the guard so reactivation cannot create
            // an item before setSource restores its required properties.
            root.loadedUrl = "";
            root.setSource("");
            return;
        }
        Qt.callLater(root.load);
    }
    Component.onCompleted: root.load()

    onStatusChanged: {
        if (root.status !== Loader.Error)
            return;
        const errorUrl = root.source.toString();
        // An old asynchronous error must not reject the design now being requested.
        if (errorUrl === "" || errorUrl !== root.requestedUrl || errorUrl === root.failedUrl)
            return;
        root.failedUrl = errorUrl;
        console.warn("osd: the store OSD " + Designs.osd
            + " did not load; drawing the Ryoku OSD");
    }

    Binding {
        when: root.item !== null
        target: root.item
        property: "kind"
        value: root.kind
    }
    Binding {
        when: root.item !== null
        target: root.item
        property: "screen"
        value: root.screen
    }
    Binding {
        when: root.item !== null
        target: root.item
        property: "us"
        value: root.us
    }
    Binding {
        when: root.item !== null
        target: root.item
        property: "shown"
        value: root.shown
    }
    Binding {
        when: root.item !== null
        target: root.item
        property: "value"
        value: root.value
    }
    Binding {
        when: root.item !== null
        target: root.item
        property: "maxValue"
        value: root.maxValue
    }
    Binding {
        when: root.item !== null
        target: root.item
        property: "muted"
        value: root.muted
    }
    Binding {
        when: root.item !== null
        target: root.item
        property: "icon"
        value: root.icon
    }
    Binding {
        when: root.item !== null
        target: root.item
        property: "iconSource"
        value: root.iconSource
    }
    Binding {
        when: root.item !== null
        target: root.item
        property: "label"
        value: root.label
    }
}
