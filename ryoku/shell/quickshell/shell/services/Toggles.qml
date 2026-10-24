pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

// one source for the quick-toggles the System deck's control tiles and the bar's
// placeable toggle modules both read. every tile is reactive off a live source:
// wifi and night light ride the daemon topics, microphone rides the Pipewire
// graph (Audio), bluetooth the BT service, and dnd / keep-awake / game mode
// Flags. nothing here polls, forks, or shells out for state; the actions mirror
// the deck's originals exactly, kept here so there is one copy, not two.
Singleton {
    id: root

    // ---- wifi (reactive off the daemon network topic) ------------------------
    // The daemon owns NetworkManager and pushes radio state on every change, so
    // the tile reads that instead of forking nmcli on a timer. The toggle sends
    // the intent through the same daemon call the network panel uses, so there
    // is one writer and the tile reflects the real radio, not an optimistic flip.
    readonly property bool wifiOn: Network.wifiRadio
    function toggleWifi() { Network.setWifiEnabled(!root.wifiOn); }

    // ---- microphone (reactive off the Pipewire graph) ------------------------
    // Audio tracks the default source, so its mute flag is live; the tile reads
    // the same object the volume panel and the record HUD drive.
    readonly property bool micMuted: !!(Audio.source && Audio.source.audio && Audio.source.audio.muted)
    function toggleMic() {
        if (Audio.source && Audio.source.audio)
            Audio.source.audio.muted = !Audio.source.audio.muted;
    }

    // ---- night light (reactive off the daemon nightlight topic) --------------
    // The daemon watches the provider's backend and the state files, so the
    // tile reflects a toggle from the keybind, the Hub, or the script itself.
    // The intent rides the same daemon call, which runs the shipped script once.
    readonly property bool nightOn: Nightlight.on
    function toggleNight() { Nightlight.toggle(); }

    // ---- bluetooth (reactive off BlueZ; writes persist through the helper) ----
    readonly property bool btOn: BluetoothPower.enabled
    function toggleBt() { BluetoothPower.toggle(); }

    // ---- dnd / keep-awake / game mode (reactive off Flags) -------------------
    readonly property bool dnd: Flags.dnd
    readonly property bool keepAwake: Flags.keepAwake
    readonly property bool gameMode: Flags.gameMode
    function toggleDnd() { Flags.dnd = !Flags.dnd; }
    function toggleCaffeine() { Flags.keepAwake = !Flags.keepAwake; }
    function toggleGame() { Flags.gameMode = !Flags.gameMode; }
}
