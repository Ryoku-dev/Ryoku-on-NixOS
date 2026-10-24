pragma ComponentBehavior: Bound

import QtQuick
import "."
import Ryoku.Ui.Singletons

Item {
    id: content

    required property var kit
    property bool current: false
    property string section: "test"
    property int focusPulse: 0


    function activate() {
        if (section === "test")
            testView.focusInput();
        else
            content.forceActiveFocus();
    }

    TypingStore { id: typingStore; kit: content.kit }
    TypingLanguages { id: typingLanguages; store: typingStore }
    TypingSoundPacks { id: typingPacks }

    TypingTestView {
        id: testView
        property bool tabCurrent: content.current
        anchors.fill: parent
        opacity: content.section === "test" ? 1 : 0
        visible: opacity > 0
        enabled: content.section === "test"
        z: enabled ? 1 : 0
        store: typingStore
        languages: typingLanguages
        soundPacks: typingPacks
        transform: Translate {
            x: content.section === "test" ? 0 : -Tokens.s2
            Behavior on x {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
            }
        }
        Behavior on opacity {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
        }
        onRequestSection: section => content.section = section
    }

    TypingHistoryPage {
        anchors.fill: parent
        opacity: content.section === "history" ? 1 : 0
        visible: opacity > 0
        enabled: content.section === "history"
        z: enabled ? 1 : 0
        store: typingStore
        transform: Translate {
            x: content.section === "history" ? 0 : Tokens.s2
            Behavior on x {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
            }
        }
        Behavior on opacity {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
        }
    }

    TypingStatsPage {
        anchors.fill: parent
        opacity: content.section === "stats" ? 1 : 0
        visible: opacity > 0
        enabled: content.section === "stats"
        z: enabled ? 1 : 0
        store: typingStore
        transform: Translate {
            x: content.section === "stats" ? 0 : Tokens.s2
            Behavior on x {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
            }
        }
        Behavior on opacity {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
        }
    }

    TypingSettingsPage {
        anchors.fill: parent
        opacity: content.section === "settings" ? 1 : 0
        visible: opacity > 0
        enabled: content.section === "settings"
        z: enabled ? 1 : 0
        store: typingStore
        languages: typingLanguages
        soundPacks: typingPacks
        transform: Translate {
            x: content.section === "settings" ? 0 : Tokens.s2
            Behavior on x {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
            }
        }
        Behavior on opacity {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
        }
        onRequestInputFocus: {
            content.section = "test";
            Qt.callLater(testView.focusInput);
        }
    }

    onSectionChanged: Qt.callLater(activate)
    onFocusPulseChanged: Qt.callLater(activate)
}
