pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import "../utils/menupoll.js" as MenuPoll

// Tailscale runs beside NetworkManager rather than inside it, so the daemon's
// network topic never sees it. This reads `tailscale status --json` only while
// a surface claims it through setActive(): every 10 s while tailscaled answers,
// once a minute while the CLI is missing. A clean status read is the only thing
// that marks it available, so a machine without Tailscale shows nothing.
//
// The same read also runs `tailscale get --json` for the exit-node prefs (LAN
// access, advertising this machine); an older CLI without `get` just leaves
// prefsKnown false and those switches hidden.
//
// Mutations run the CLI on an explicit tap: up, down, picking or clearing the
// exit node, and the two exit-node prefs. When tailscaled refuses one because
// this user is not its operator, needsOperator rises; authorise() then runs
// `pkexec tailscale set --operator=$USER` once and retries the refused action.
Singleton {
    id: root

    // "" until the first read; Running | Stopped | NeedsLogin | NoState once
    // tailscaled answers; Unavailable while the CLI is there but tailscaled is
    // not; Missing without the CLI.
    property string state: ""
    readonly property bool installed: root.state !== "" && root.state !== "Missing"
    readonly property bool available: root.installed && root.state !== "Unavailable"
    readonly property bool up: root.state === "Running"
    readonly property bool signedOut: root.state === "NeedsLogin"

    property string hostName: ""
    property string dnsName: ""
    property string ip4: ""
    property string ip6: ""
    property string tailnet: ""
    property bool exitNodeActive: false
    property string exitNodeName: ""
    // Peers that offer to carry traffic, online first:
    // { id, name, ip, online, active, os }.
    property var exitNodes: []
    property bool prefsKnown: false
    property bool allowLan: false
    property bool advertisingExit: false
    property int peersOnline: 0
    property int peersTotal: 0
    // Health warnings minus "Tailscale is stopped.", which the switch already says.
    property var health: []

    property bool needsOperator: false
    property string lastError: ""
    readonly property bool busy: action.running || authoriser.running

    property var owners: []
    readonly property bool watching: root.owners.length > 0
    function setActive(owner, enabled) {
        root.owners = MenuPoll.setOwnership(root.owners, owner, enabled);
    }

    onWatchingChanged: if (root.watching) root.refresh()

    function refresh() {
        if (status.running)
            return;
        status.running = true;
    }

    function turnOn() { root.run(["tailscale", "up"], "up"); }
    function turnOff() { root.run(["tailscale", "down"], "down"); }
    function stopExitNode() { root.run(["tailscale", "set", "--exit-node="], "exitoff"); }
    function useExitNode(node) {
        if (node && node.ip)
            root.run(["tailscale", "set", "--exit-node=" + node.ip], "exit");
    }
    function setAllowLan(on) {
        root.run(["tailscale", "set", "--exit-node-allow-lan-access=" + (on ? "true" : "false")], "lan");
    }
    function setAdvertiseExit(on) {
        root.run(["tailscale", "set", "--advertise-exit-node=" + (on ? "true" : "false")], "advertise");
    }

    // The one privileged call, reached only from the card's Authorise button.
    function authorise() {
        const user = Quickshell.env("USER") || "";
        if (user.length === 0 || authoriser.running)
            return;
        authoriser.command = ["pkexec", "tailscale", "set", "--operator=" + user];
        authoriser.running = true;
    }

    function copyIp() {
        if (root.ip4.length > 0)
            Quickshell.execDetached(["wl-copy", root.ip4]);
    }

    function openAdmin() {
        Spawn.runApp(["xdg-open", "https://login.tailscale.com/admin/machines"], { label: "browser" });
    }

    function run(command, tag) {
        if (action.running)
            return;
        root.lastError = "";
        action.tag = tag;
        action.command = command;
        action.running = true;
    }

    function apply(text) {
        const parts = String(text).split("\x1e");
        let status;
        try {
            status = JSON.parse(parts[0]);
        } catch (e) {
            return;
        }
        let prefs = null;
        try {
            prefs = parts.length > 1 && parts[1].trim().length > 0 ? JSON.parse(parts[1]) : null;
        } catch (e) {
            prefs = null;
        }
        root.prefsKnown = !!prefs;
        root.allowLan = !!prefs && prefs["exit-node-allow-lan-access"] === true;
        root.advertisingExit = !!prefs && prefs["advertise-exit-node"] === true;
        if (!status)
            return;
        const backend = status.BackendState || "";
        root.state = ["Running", "Stopped", "NeedsLogin"].includes(backend) ? backend : "NoState";

        const self = status.Self || {};
        root.hostName = self.HostName || "";
        const dns = self.DNSName || "";
        root.dnsName = dns.endsWith(".") ? dns.slice(0, -1) : dns;
        const addresses = self.TailscaleIPs || status.TailscaleIPs || [];
        root.ip4 = addresses.find(address => String(address).indexOf(":") < 0) || "";
        root.ip6 = addresses.find(address => String(address).indexOf(":") >= 0) || "";
        root.tailnet = (status.CurrentTailnet || {}).Name || "";

        const exitNode = status.ExitNodeStatus || null;
        const peers = Object.values(status.Peer || {});
        const exitPeer = exitNode ? peers.find(peer => peer && peer.ID === exitNode.ID) : null;
        root.exitNodeActive = !!exitNode;
        root.exitNodeName = exitPeer ? (exitPeer.HostName || "") : "";
        root.exitNodes = peers
            .filter(peer => peer && (peer.ExitNodeOption === true || peer.ExitNode === true))
            .map(peer => ({
                id: peer.ID || "",
                name: peer.HostName || String(peer.DNSName || "").split(".")[0],
                ip: (peer.TailscaleIPs || []).find(address => String(address).indexOf(":") < 0) || "",
                online: peer.Online === true,
                active: peer.ExitNode === true || (!!exitNode && peer.ID === exitNode.ID),
                os: peer.OS || ""
            }))
            .sort((a, b) => (b.online - a.online) || a.name.localeCompare(b.name));
        root.peersTotal = peers.length;
        root.peersOnline = peers.filter(peer => peer && peer.Online === true).length;
        root.health = (status.Health || []).filter(line => String(line).trim() !== "Tailscale is stopped.");
    }

    // Exit 127 is the CLI missing; any other failure is tailscaled not answering.
    Process {
        id: status
        command: ["sh", "-c", "command -v tailscale >/dev/null 2>&1 || exit 127; tailscale status --json || exit $?; printf '\\036'; tailscale get --json 2>/dev/null || true"]
        stdout: StdioCollector { id: statusOutput }
        onExited: code => {
            if (code === 0)
                root.apply(statusOutput.text);
            else
                root.state = code === 127 ? "Missing" : "Unavailable";
        }
    }

    Timer {
        interval: root.state === "Missing" ? 60000 : 10000
        running: root.watching
        repeat: true
        onTriggered: root.refresh()
    }

    // One refresh a second after any action, so the switch settles without
    // waiting for the next poll.
    Timer {
        id: settle
        interval: 1000
        onTriggered: root.refresh()
    }

    Process {
        id: action
        property string tag: ""
        stderr: StdioCollector { id: actionError }
        onExited: code => {
            const error = actionError.text.trim();
            if (code !== 0 && /access denied|--operator|\boperator\b/i.test(error)) {
                root.needsOperator = true;
                root.lastError = "";
            } else if (code !== 0) {
                root.lastError = error.length > 0 ? error.split("\n")[0] : "tailscale " + action.tag + " failed";
            }
            settle.restart();
        }
    }

    Process {
        id: authoriser
        onExited: code => {
            if (code !== 0) {
                root.lastError = "Authorisation cancelled";
                return;
            }
            root.needsOperator = false;
            // Retry exactly the refused command (up, down, exit node, a pref).
            if (action.command && action.command.length > 0)
                root.run(action.command.slice(), action.tag);
            settle.restart();
        }
    }
}
