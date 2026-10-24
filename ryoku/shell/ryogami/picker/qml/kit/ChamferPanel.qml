import QtQuick

// A floating dialog plate: flat paper, a hairline, a hair of rounding. It floats, so it
// keeps a soft shadow; there is no colour on it, only the words it holds.
Rectangle {
    id: panel

    property real reveal: 1

    radius: Theme.radius
    color: Theme.withAlpha(Theme.surface, 0.99 * panel.reveal)
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.55 * panel.reveal)
}
