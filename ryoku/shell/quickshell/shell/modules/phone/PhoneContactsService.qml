pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import shell.services

Singleton {
    id: root

    property bool available: false
    property bool ready: false
    property string sourcePath: ""
    property string lastError: ""
    property var contacts: []
    property string searchQuery: ""
    property var filteredContacts: []
    property int hiddenCount: 0
    readonly property int count: contacts.length
    readonly property bool hideUnnamed: Config.phone?.contacts?.hideUnnamed ?? true
    readonly property bool enabled: PhoneState.runtimeReady
        && (Config.phone?.contacts?.enabled ?? true)

    function refresh(): void {
        monitor.running = false
        if (!root.enabled || !KdeConnectService.activeDeviceId) {
            root.ready = root.enabled
            root.contacts = []
            root._updateFilteredContacts()
            return
        }
        root.ready = false
        monitor.command = PhoneState.pdeath(["python3",
            Quickshell.shellPath("modules/phone/scripts/kdeconnect/contacts_monitor.py"),
            "--device", KdeConnectService.activeDeviceId])
        monitor.running = true
    }

    function setSearchQuery(query): void {
        root.searchQuery = String(query || "")
        root._updateFilteredContacts()
    }

    function contactById(contactId): var {
        return root.contacts.find(contact => contact.id === contactId) ?? null
    }

    function contactByNumber(number): var {
        const digits = String(number || "").replace(/\D/g, "")
        if (digits.length < 6) return null
        return root.contacts.find(contact => Array.from(contact.phones || []).some(phone => {
            const candidate = String(phone.normalized || phone.value || "").replace(/\D/g, "")
            return candidate.endsWith(digits) || digits.endsWith(candidate)
        })) ?? null
    }

    function copyPhone(number): void {
        if (number) Quickshell.clipboardText = String(number)
    }

    function openDialer(number): void {
        root._startIntent("android.intent.action.DIAL", "tel:" + String(number || ""))
    }

    function composeSms(number): void {
        root._startIntent("android.intent.action.SENDTO", "smsto:" + String(number || ""))
    }

    function _startIntent(action, uri): void {
        if (!uri || !KdeConnectService.adbReachable) return
        Spawn.run(["adb"].concat(KdeConnectService.adbTargetArgs())
            .concat(["shell", "am", "start", "-a", action, "-d", uri]))
    }

    function toggleFavorite(contactId): void {
        PhoneState.setFavoriteContact(contactId, !root.isFavorite(contactId))
        root._updateFilteredContacts()
    }

    function isFavorite(contactId): bool {
        return (PhoneState.favoriteContactIds || []).indexOf(contactId) >= 0
    }

    function _updateFilteredContacts(): void {
        const query = root.searchQuery.trim().toLowerCase()
        const visible = []
        let hidden = 0
        for (const contact of Array.from(root.contacts || [])) {
            if (root.hideUnnamed && contact.nameless === true) {
                hidden++
                continue
            }
            const haystack = [contact.displayName, contact.organization]
                .concat(Array.from(contact.phones || []).map(phone => phone.value))
                .join(" ").toLowerCase()
            if (query === "" || haystack.indexOf(query) >= 0)
                visible.push(contact)
        }
        visible.sort((left, right) => {
            const favoriteDelta = Number(root.isFavorite(right.id)) - Number(root.isFavorite(left.id))
            return favoriteDelta || String(left.displayName).localeCompare(String(right.displayName))
        })
        root.hiddenCount = hidden
        root.filteredContacts = visible
    }

    Process {
        id: monitor
        running: false
        stdout: SplitParser {
            onRead: line => {
                if (!line) return
                try {
                    const message = JSON.parse(line)
                    if (message.event === "ready") {
                        root.available = true
                        root.ready = true
                        root.sourcePath = String(message.sourcePath || "")
                        root.lastError = ""
                    } else if (message.event === "snapshot") {
                        root.contacts = Array.from(message.contacts || []).map(contact =>
                            Object.assign({}, contact, {
                                phoneNumbers: Array.from(contact.phones || []).map(phone => ({
                                    number: String(phone.value || ""),
                                    type: String(phone.type || "mobile")
                                }))
                            }))
                        root._updateFilteredContacts()
                    } else if (message.event === "error") {
                        root.available = false
                        root.ready = true
                        root.lastError = String(message.message || I18n.tr("Contacts are unavailable"))
                    }
                } catch (error) {
                    root.lastError = I18n.tr("Contacts data could not be read")
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.enabled)
                root.lastError = I18n.tr("Contacts monitor stopped")
        }
    }

    Connections {
        target: KdeConnectService
        function onActiveDeviceIdChanged() { root.refresh() }
        function onActiveReachableChanged() { root.refresh() }
    }

    onEnabledChanged: refresh()
    onHideUnnamedChanged: _updateFilteredContacts()
    Component.onCompleted: refresh()
}
