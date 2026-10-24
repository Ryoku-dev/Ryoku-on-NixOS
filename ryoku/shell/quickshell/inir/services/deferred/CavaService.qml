pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import shell.services as ShellServices
import inir.modules.common
import inir.services

Singleton {
    id: root

    property int _legacySubscribers: 0
    property var _sampleRequests: []
    property int _nextSampleRequestId: 1
    readonly property int _subscribers: root._legacySubscribers + root._sampleRequests.length
    readonly property bool active: root._subscribers > 0

    readonly property int cfgFramerate: Config.options?.appearance?.cava?.framerate ?? 60
    readonly property int cfgSensitivity: Config.options?.appearance?.cava?.sensitivity ?? 100
    readonly property int cfgBars: Config.options?.appearance?.cava?.bars ?? 0
    readonly property bool cfgStereo: Config.options?.appearance?.cava?.stereo ?? true
    readonly property var cfgBlockedApps: Config.options?.appearance?.cava?.blockedApps ?? []
    readonly property string cfgBlockedAppsJson: JSON.stringify(root.cfgBlockedApps)

    readonly property int requestedBars: {
        var requested = 0;
        for (var i = 0; i < root._sampleRequests.length; i++)
            requested = Math.max(requested, root._sampleRequests[i].bars ?? 0);
        return requested;
    }
    readonly property int effectiveBars: {
        var count = root.cfgBars > 0
            ? Math.max(2, Math.round(root.cfgBars))
            : Math.min(320, Math.max(50, root.requestedBars));
        if (root.cfgStereo && count % 2 !== 0)
            count++;
        return count;
    }

    readonly property list<real> points: root.active
        ? root.resample(ShellServices.AudioBars.levels, root.effectiveBars) : []
    readonly property real framePeak: root.peakOf(root.points)
    readonly property real frameAverage: root.averageOf(root.points)
    readonly property real normalizationCeiling: 1000
    readonly property real normalizationFloor: 20
    readonly property bool audioSignalActive: root.active
        && ShellServices.AudioBars.energy > 0

    readonly property string playerDesktopEntry: {
        if (YtMusic.isPlaying)
            return "mpv ytmusic youtube-music";
        var player = MprisController.activePlayer;
        return player?.desktopEntry || player?.identity || "__inir_music_player__";
    }

    function resample(source, count) {
        var out = new Array(count);
        if (!source || source.length === 0) {
            out.fill(0);
            return out;
        }
        if (count === 1) {
            out[0] = 1000 * Number(source[0] || 0);
            return out;
        }
        for (var i = 0; i < count; i++) {
            var at = i * (source.length - 1) / (count - 1);
            var lo = Math.floor(at);
            var hi = Math.min(source.length - 1, lo + 1);
            var mix = at - lo;
            var value = Number(source[lo] || 0) * (1 - mix)
                + Number(source[hi] || 0) * mix;
            out[i] = 1000 * Math.max(0, Math.min(1, value));
        }
        return out;
    }

    function peakOf(values) {
        var peak = 0;
        for (var i = 0; i < values.length; i++)
            peak = Math.max(peak, Number(values[i] || 0));
        return peak;
    }

    function averageOf(values) {
        if (!values || values.length === 0)
            return 0;
        var sum = 0;
        for (var i = 0; i < values.length; i++)
            sum += Number(values[i] || 0);
        return sum / values.length;
    }

    function subscribe(requestedBars): int {
        if (requestedBars === undefined) {
            root._legacySubscribers++;
            return 0;
        }
        var requestId = root._nextSampleRequestId++;
        var next = root._sampleRequests.slice();
        next.push({
            id: requestId,
            bars: Math.max(0, Math.round(Number(requestedBars) || 0))
        });
        root._sampleRequests = next;
        return requestId;
    }

    function updateSubscription(requestId: int, requestedBars): void {
        if (requestId <= 0)
            return;
        var bars = Math.max(0, Math.round(Number(requestedBars) || 0));
        root._sampleRequests = root._sampleRequests.map(request =>
            request.id === requestId ? { id: request.id, bars: bars } : request);
    }

    function unsubscribe(requestId): void {
        if (requestId === undefined || requestId === 0) {
            root._legacySubscribers = Math.max(0, root._legacySubscribers - 1);
            return;
        }
        root._sampleRequests = root._sampleRequests.filter(
            request => request.id !== requestId);
    }

    function updateOwnership(): void {
        ShellServices.AudioBars.setActive(root, root.active);
    }

    onActiveChanged: root.updateOwnership()
    Component.onCompleted: root.updateOwnership()
    Component.onDestruction: ShellServices.AudioBars.setActive(root, false)
}
