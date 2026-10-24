pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons
import "."

Item {
    id: root

    property var kit: null
    property string query: ""
    property bool current: false
    readonly property int matches: client.ready && !client.shellDown ? root.totalMatches() : -1
    readonly property var rail: root.makeRail()
    property string railCurrent: "overview"
    readonly property bool railReady: client.stateLoaded || client.shellDown
    signal requestClose()

    property bool loadedOnce: false
    property bool restoringRail: false
    readonly property var view: content.item

    function matchesNotification(item) {
        if (!root.query)
            return true;
        return [item.app, item.title, item.body].join(" ").toLowerCase().indexOf(root.query) >= 0;
    }

    function matchesContact(item) {
        if (!root.query)
            return true;
        const numbers = Array.isArray(item.numbers)
            ? item.numbers.map(number => String(number.number || "")).join(" ") : "";
        return (String(item.name || "") + " " + numbers).toLowerCase().indexOf(root.query) >= 0;
    }

    function matchesApp(item) {
        if (!root.query)
            return true;
        return (String(item.label || "") + " " + String(item.package || "")).toLowerCase().indexOf(root.query) >= 0;
    }

    function matchingCount(items, matcher) {
        let count = 0;
        for (let i = 0; i < items.length; i++) {
            if (matcher(items[i]))
                count++;
        }
        return count;
    }

    function notificationCount() {
        return root.matchingCount(client.notifications, root.matchesNotification);
    }

    function contactCount() {
        if (!root.query)
            return Number((client.state.contacts || {}).count || 0);
        return client.contactsOpened ? root.matchingCount(client.contacts, root.matchesContact) : 0;
    }

    function appCount() {
        if (!root.query)
            return Number((client.state.apps || {}).count || 0);
        return client.appsOpened ? root.matchingCount(client.apps, root.matchesApp) : 0;
    }

    function totalMatches() {
        if (!root.query)
            return client.notifications.length
                + Number((client.state.contacts || {}).count || 0)
                + Number((client.state.apps || {}).count || 0);
        return root.notificationCount() + root.contactCount() + root.appCount();
    }

    function makeRail() {
        const observed = client.revision;
        if (!client.ready || client.shellDown)
            return [];
        return [
            { id: "overview", label: I18n.tr("Overview"), count: -1 },
            { id: "notifications", label: I18n.tr("Notifications"), count: root.notificationCount() },
            { id: "screen", label: I18n.tr("Screen"), count: -1 },
            { id: "contacts", label: I18n.tr("Contacts"), count: root.contactCount() },
            { id: "apps", label: I18n.tr("Apps"), count: root.appCount() }
        ];
    }

    function restoreRail() {
        if (!root.kit || typeof root.kit.get !== "function")
            return;
        const saved = String(root.kit.get("phone.rail", "overview"));
        root.restoringRail = true;
        root.railCurrent = ["overview", "notifications", "screen", "contacts", "apps"].indexOf(saved) >= 0
            ? saved : "overview";
        root.restoringRail = false;
    }

    function openCurrentData() {
        if (!root.loadedOnce)
            return;
        if (root.railCurrent === "contacts")
            client.openContacts();
        else if (root.railCurrent === "apps")
            client.openApps();
    }

    function activate() {
        root.loadedOnce = true;
        root.openCurrentData();
        client.activate();
        if (root.view)
            Qt.callLater(root.view.activate);
    }

    function handleEscape() {
        return root.view ? root.view.handleEscape() : false;
    }

    function openSection(section) {
        root.railCurrent = section;
    }

    onCurrentChanged: {
        if (root.current) {
            root.loadedOnce = true;
            if (root.view)
                Qt.callLater(root.view.activate);
        }
    }
    onKitChanged: root.restoreRail()
    onRailCurrentChanged: {
        root.openCurrentData();
        if (!root.restoringRail && root.kit && typeof root.kit.set === "function")
            root.kit.set("phone.rail", root.railCurrent);
        if (root.view)
            Qt.callLater(root.view.activate);
    }
    onRailChanged: {
        if (client.ready && !root.rail.some(item => item.id === root.railCurrent))
            root.railCurrent = "overview";
    }

    PhoneClient { id: client }

    Loader {
        id: content
        anchors.fill: parent
        active: root.loadedOnce
        sourceComponent: PhoneContent {
            client: client
            query: root.query
            section: root.railCurrent
            onNavigate: section => root.openSection(section)
            onRequestClose: root.requestClose()
        }
        onLoaded: if (root.current) Qt.callLater(root.view.activate)
    }
}
