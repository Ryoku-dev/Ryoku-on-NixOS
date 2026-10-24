import QtQuick

Rectangle {
    id: rule

    property real alpha: 0.58
    property real reveal: 1

    implicitHeight: 1
    color: Theme.withAlpha(Theme.outline, rule.alpha * rule.reveal)
}
