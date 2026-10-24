pragma Singleton
import QtQuick
import Quickshell

// Shared desktop wall clocks. Minute-only widgets bind `date`; faces that
// actually draw seconds register through setSecondPrecision() and bind
// `secondDate`, so a normal desktop has no one-second wakeup.
Singleton {
    id: root

    property var secondConsumers: []
    readonly property bool secondsEnabled: root.secondConsumers.length > 0
    readonly property var date: minuteClock.date
    readonly property var secondDate: root.secondsEnabled ? secondsClock.date : minuteClock.date

    // YYYY-MM-DD of today. Date-only faces derive their grids from this key
    // instead of reevaluating them whenever another face requests seconds.
    readonly property string dayKey: Qt.formatDate(root.date, "yyyy-MM-dd")

    function setSecondPrecision(owner, wanted) {
        const index = root.secondConsumers.indexOf(owner);
        if (wanted && index < 0)
            root.secondConsumers = root.secondConsumers.concat([owner]);
        else if (!wanted && index >= 0) {
            const next = root.secondConsumers.slice();
            next.splice(index, 1);
            root.secondConsumers = next;
        }
    }

    SystemClock {
        id: minuteClock
        precision: SystemClock.Minutes
    }

    SystemClock {
        id: secondsClock
        precision: SystemClock.Seconds
        enabled: root.secondsEnabled
    }
}
