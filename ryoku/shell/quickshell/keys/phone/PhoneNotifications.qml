pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var client
    property string query: ""
    property string replyId: ""
    property string expandedId: ""

    readonly property var filtered: client.notifications.filter(function(item) {
        if (!root.query)
            return true;
        const text = [item.app, item.title, item.body].join(" ").toLowerCase();
        return text.indexOf(root.query) >= 0;
    })
    readonly property var groups: {
        const byApp = {};
        const order = [];
        for (let i = 0; i < root.filtered.length; i++) {
            const item = root.filtered[i];
            const app = String(item.app || I18n.tr("Phone"));
            if (!byApp[app]) {
                byApp[app] = [];
                order.push(app);
            }
            byApp[app].push(item);
        }
        return order.map(function(app) {
            return { app: app, items: byApp[app] };
        });
    }

    function relativeTime(value) {
        const delta = Math.max(0, Date.now() - Number(value || 0));
        const minute = 60000;
        if (delta < minute)
            return I18n.tr("now");
        if (delta < minute * 60)
            return I18n.tr("%1 min ago").arg(Math.floor(delta / minute));
        if (delta < minute * 60 * 24)
            return I18n.tr("%1 hr ago").arg(Math.floor(delta / (minute * 60)));
        return I18n.tr("%1 d ago").arg(Math.floor(delta / (minute * 60 * 24)));
    }

    function iconSource(path) {
        const value = String(path || "");
        return value.startsWith("/") ? "file://" + value : value;
    }

    function activate() {
        if (root.filtered.length > 0)
            clearAll.forceActiveFocus();
        else
            root.forceActiveFocus();
    }

    function handleEscape() {
        if (root.replyId) {
            root.replyId = "";
            root.forceActiveFocus();
            return true;
        }
        return false;
    }

    Column {
        anchors.fill: parent
        spacing: Tokens.s3

        Row {
            width: parent.width
            height: Tokens.s6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - clearAll.width
                text: root.filtered.length === 0 ? I18n.tr("Notifications")
                    : root.filtered.length === 1 ? I18n.tr("1 notification")
                    : I18n.tr("%1 notifications").arg(root.filtered.length)
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
            }
            Btn {
                id: clearAll
                visible: root.client.notifications.length > 0
                compact: true
                text: I18n.tr("CLEAR ALL")
                onAct: root.client.call("dismissAll", [])
            }
        }

        Flickable {
            id: scroll
            width: parent.width
            height: parent.height - Tokens.s6 - parent.spacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentHeight: groupsColumn.implicitHeight
            ScrollBar.vertical: ScrollRail {
                policy: ScrollBar.AsNeeded
                visible: scroll.contentHeight > scroll.height + 1
            }
            WheelScroll { }

            Column {
                id: groupsColumn
                width: scroll.width - Tokens.s3
                spacing: Tokens.s3

                Repeater {
                    model: root.groups
                    delegate: Rectangle {
                        id: groupCard
                        required property var modelData
                        required property int index
                        property bool entered: Tokens.reduceMotion
                        width: groupsColumn.width
                        implicitHeight: groupBody.implicitHeight + Tokens.s3 * 2
                        radius: Tokens.radius
                        color: Tokens.paperLift
                        border.width: Tokens.border
                        border.color: Tokens.lineSoft
                        opacity: entered ? 1 : 0
                        transform: Translate { y: groupCard.entered ? 0 : Tokens.s2 }
                        Component.onCompleted: enterDelay.start()
                        Timer {
                            id: enterDelay
                            interval: Tokens.reduceMotion ? 0 : Math.min(groupCard.index, 8) * 24
                            onTriggered: groupCard.entered = true
                        }
                        Behavior on opacity {
                            enabled: !Tokens.reduceMotion
                            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                        }

                        Column {
                            id: groupBody
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.s3
                            spacing: Tokens.s2

                            Row {
                                width: parent.width
                                height: Tokens.s6
                                spacing: Tokens.s3
                                Rectangle {
                                    width: Tokens.s6
                                    height: width
                                    radius: width / 2
                                    color: Tokens.tint10
                                    Image {
                                        id: appIcon
                                        anchors.fill: parent
                                        anchors.margins: Tokens.s1
                                        source: groupCard.modelData.items.length > 0
                                            ? root.iconSource(groupCard.modelData.items[0].icon) : ""
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Text {
                                        visible: appIcon.status !== Image.Ready
                                        anchors.centerIn: parent
                                        text: String(groupCard.modelData.app || "?").slice(0, 1).toUpperCase()
                                        color: Tokens.ink
                                        font.family: Tokens.ui
                                        font.pixelSize: Tokens.fBody
                                        font.weight: Font.DemiBold
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width - count.width - Tokens.s7 - parent.spacing * 2)
                                    text: String(groupCard.modelData.app || I18n.tr("Phone"))
                                    color: Tokens.ink
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fRow
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    id: count
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(Tokens.s5, countText.implicitWidth + Tokens.s2)
                                    height: Tokens.s5
                                    radius: height / 2
                                    color: Tokens.tint10
                                    Text {
                                        id: countText
                                        anchors.centerIn: parent
                                        text: String(groupCard.modelData.items.length)
                                        color: Tokens.inkDim
                                        font.family: Tokens.mono
                                        font.pixelSize: Tokens.fTiny
                                    }
                                    Behavior on width {
                                        enabled: !Tokens.reduceMotion
                                        NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
                                    }
                                }
                            }

                            Repeater {
                                model: groupCard.modelData.items
                                delegate: Rectangle {
                                    id: notification
                                    required property var modelData
                                    readonly property string itemId: String(modelData.id || "")
                                    width: groupBody.width
                                    implicitHeight: notificationBody.implicitHeight + Tokens.s3 * 2
                                    radius: Tokens.radius
                                    color: bodyHover.hovered ? Tokens.tint5 : "transparent"
                                    border.width: Tokens.border
                                    border.color: root.replyId === itemId ? Tokens.lineStrong : Tokens.lineSoft
                                    scale: bodyTap.pressed ? 0.992 : 1
                                    Behavior on color {
                                        enabled: !Tokens.reduceMotion
                                        ColorAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on scale {
                                        enabled: !Tokens.reduceMotion
                                        NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
                                    }

                                    Column {
                                        id: notificationBody
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: Tokens.s3
                                        spacing: Tokens.s2

                                        Row {
                                            width: parent.width
                                            spacing: Tokens.s2
                                            Text {
                                                width: Math.max(0, parent.width - timeText.width - parent.spacing)
                                                text: String(notification.modelData.title || I18n.tr("Notification"))
                                                color: Tokens.ink
                                                font.family: Tokens.ui
                                                font.pixelSize: Tokens.fSmall
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                id: timeText
                                                text: root.relativeTime(notification.modelData.time)
                                                color: Tokens.inkFaint
                                                font.family: Tokens.ui
                                                font.pixelSize: Tokens.fTiny
                                            }
                                        }
                                        Text {
                                            visible: text.length > 0
                                            width: parent.width
                                            text: String(notification.modelData.body || "")
                                            color: Tokens.inkMuted
                                            font.family: Tokens.ui
                                            font.pixelSize: Tokens.fSmall
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: root.expandedId === notification.itemId ? 100 : 2
                                            elide: root.expandedId === notification.itemId ? Text.ElideNone : Text.ElideRight
                                        }

                                        Row {
                                            width: parent.width
                                            spacing: Tokens.s2
                                            Btn {
                                                visible: notification.modelData.canReply === true
                                                compact: true
                                                text: I18n.tr("REPLY")
                                                onAct: {
                                                    root.replyId = notification.itemId;
                                                    Qt.callLater(replyField.grabFocus);
                                                }
                                            }
                                            Btn {
                                                visible: notification.modelData.dismissable === true
                                                compact: true
                                                text: I18n.tr("DISMISS")
                                                onAct: root.client.call("dismiss", [notification.itemId])
                                            }
                                            Repeater {
                                                model: Array.isArray(notification.modelData.actions)
                                                    ? notification.modelData.actions : []
                                                delegate: Btn {
                                                    required property var modelData
                                                    compact: true
                                                    text: String(modelData.label || I18n.tr("Action")).toUpperCase()
                                                    onAct: root.client.call("action", [notification.itemId, String(modelData.key || "")])
                                                }
                                            }
                                        }

                                        Row {
                                            visible: root.replyId === notification.itemId
                                            width: parent.width
                                            spacing: Tokens.s2
                                            Field {
                                                id: replyField
                                                width: parent.width - sendReply.width - parent.spacing
                                                placeholder: String(notification.modelData.replyHint || I18n.tr("Reply"))
                                                onAccepted: sendReply.act()
                                            }
                                            Btn {
                                                id: sendReply
                                                primary: true
                                                text: I18n.tr("SEND")
                                                armed: replyField.text.trim().length > 0
                                                onAct: {
                                                    root.client.call("reply", [notification.itemId, replyField.text.trim()]);
                                                    replyField.clear();
                                                    root.replyId = "";
                                                }
                                            }
                                        }
                                    }

                                    HoverHandler { id: bodyHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        id: bodyTap
                                        acceptedButtons: Qt.LeftButton
                                        gesturePolicy: TapHandler.ReleaseWithinBounds
                                        onTapped: {
                                            if (root.replyId !== notification.itemId)
                                                root.expandedId = root.expandedId === notification.itemId ? "" : notification.itemId;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    visible: root.groups.length === 0
                    width: groupsColumn.width
                    spacing: Tokens.s3
                    Text {
                        width: parent.width
                        text: root.query
                            ? I18n.tr("No phone notifications match this search.")
                            : I18n.tr("No notifications from your phone. On the phone open KDE Connect, choose this computer, and allow Notification sync.")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fBody
                        wrapMode: Text.WordWrap
                    }
                    Btn {
                        text: I18n.tr("REFRESH")
                        onAct: root.client.call("refresh", [])
                    }
                }
            }
        }
    }
}
