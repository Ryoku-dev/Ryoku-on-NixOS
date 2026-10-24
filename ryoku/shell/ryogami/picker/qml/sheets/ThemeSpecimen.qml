import QtQuick

Item {
    id: specimen

    property var palette: ({})

    implicitHeight: 83 * Theme.scale
    implicitWidth: 158 * Theme.scale

    function _c(k, fb) {
        var v = specimen.palette ? specimen.palette[k] : undefined
        return (typeof v === "string" && v.length > 0) ? v : fb
    }
    readonly property color cPrimary: specimen._c("primary", Theme.primary)
    readonly property color cPrimaryText: specimen._c("primaryText", Theme.primaryText)
    readonly property color cSurface: specimen._c("surface", Theme.surface)
    readonly property color cSurfaceText: specimen._c("surfaceText", Theme.surfaceText)
    readonly property color cSurfaceVariant: specimen._c("surfaceVariant", Theme.surfaceVariant)
    readonly property color cSurfaceContainer: specimen._c("surfaceContainer", Theme.surfaceContainer)
    readonly property color cBackground: specimen._c("background", Theme.background)
    readonly property color cOutline: specimen._c("outline", Theme.outline)
    readonly property color cTertiary: specimen._c("tertiary", Theme.tertiary)

    Rectangle {
        id: frame
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Theme.withAlpha(specimen.cOutline, 0.72)
        radius: Theme.radius
        clip: true

        Row {
            anchors.fill: parent

            Rectangle {
                id: rail
                width: Math.min(65 * Theme.scale, parent.width * 0.42)
                height: parent.height
                color: specimen.cSurface

                Column {
                    anchors.fill: parent
                    anchors.margins: 6 * Theme.scale
                    spacing: 5 * Theme.scale

                    Rectangle {
                        width: parent.width
                        height: 10 * Theme.scale
                        color: specimen.cTertiary
                    }

                    Rectangle {
                        width: parent.width
                        height: 12 * Theme.scale
                        color: specimen.cPrimary

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 4 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3 * Theme.scale

                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    width: 7 * Theme.scale
                                    height: 2 * Theme.scale
                                    color: specimen.cPrimaryText
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 8 * Theme.scale
                        color: Theme.withAlpha(specimen.cSurfaceText, 0.5)
                    }
                    Rectangle {
                        width: parent.width * 0.7
                        height: 8 * Theme.scale
                        color: Theme.withAlpha(specimen.cSurfaceText, 0.32)
                    }
                }
            }

            Rectangle {
                width: parent.width - rail.width
                height: parent.height
                color: specimen.cBackground

                Column {
                    anchors.fill: parent
                    anchors.margins: 6 * Theme.scale
                    spacing: 6 * Theme.scale

                    Rectangle {
                        width: parent.width
                        height: 16 * Theme.scale
                        color: specimen.cSurfaceContainer

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 5 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5 * Theme.scale

                            Rectangle {
                                width: 38 * Theme.scale
                                height: 8 * Theme.scale
                                color: specimen.cPrimary
                            }
                            Rectangle {
                                width: 23 * Theme.scale
                                height: 8 * Theme.scale
                                color: specimen.cTertiary
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: parent.height - (16 * Theme.scale) - (6 * Theme.scale)
                        color: specimen.cSurfaceVariant
                        border.width: 1
                        border.color: Theme.withAlpha(specimen.cOutline, 0.58)

                        Column {
                            anchors.fill: parent
                            anchors.margins: 6 * Theme.scale
                            spacing: 5 * Theme.scale

                            Rectangle {
                                width: parent.width
                                height: 6 * Theme.scale
                                color: Theme.withAlpha(specimen.cSurfaceText, 0.9)
                            }
                            Rectangle {
                                width: parent.width * 0.7
                                height: 6 * Theme.scale
                                color: Theme.withAlpha(specimen.cSurfaceText, 0.54)
                            }
                            Rectangle {
                                width: parent.width * 0.5
                                height: 6 * Theme.scale
                                color: Theme.withAlpha(specimen.cSurfaceText, 0.38)
                            }
                        }
                    }
                }
            }
        }
    }
}
