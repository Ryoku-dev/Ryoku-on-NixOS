import QtQuick
import QtMultimedia

Item {
    id: soundtrack
    property url audioFile: ""

    MediaPlayer {
        id: player
        source: soundtrack.audioFile
        autoPlay: true
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            id: audio
            volume: 0
        }
        onPlaybackStateChanged: {
            console.info("Ryoku soundtrack state:", playbackState,
                         "audio volume:", audio.volume)
            if (playbackState === MediaPlayer.PlayingState)
                fadeIn.restart()
        }
        onMediaStatusChanged: {
            console.info("Ryoku soundtrack media status:", mediaStatus)
        }
        onErrorOccurred: (error, errorString) => {
            console.warn("Ryoku soundtrack error:", errorString)
        }
    }

    NumberAnimation {
        id: fadeIn
        target: audio
        property: "volume"
        from: 0
        to: 0.13
        duration: 3000
        easing.type: Easing.InOutSine
        onFinished: console.info("Ryoku soundtrack volume:", audio.volume)
    }
}
