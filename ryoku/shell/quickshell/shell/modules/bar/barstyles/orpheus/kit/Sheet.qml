import QtQuick

Item {
    id: root

    property real pageWidth: 360
    property string title: ""
    property bool backVisible: false
    property list<Item> trailing
    default property alias content: contentColumn.data

    signal back()

    // Trailing items report their own visibility only while the row holding them
    // is shown, so the header never hides on their account.
    readonly property bool headerVisible: backVisible || title.length > 0 || trailing.length > 0
    readonly property real padding: Style.s4

    implicitWidth: pageWidth
    implicitHeight: padding * 2 + contentColumn.implicitHeight
        + (headerVisible ? Math.max(32, headerRow.implicitHeight) + Style.s3 : 0)
    width: implicitWidth
    height: implicitHeight

    function adoptTrailing() {
        for (let index = 0; index < trailing.length; ++index) {
            const item = trailing[index];
            if (item)
                item.parent = trailingRow;
        }
    }

    onTrailingChanged: adoptTrailing()
    Component.onCompleted: adoptTrailing()

    Item {
        id: headerRow
        visible: root.headerVisible
        x: root.padding
        y: root.padding
        width: Math.max(0, root.width - root.padding * 2)
        implicitHeight: Math.max(backButton.implicitHeight, titleLabel.implicitHeight,
            trailingRow.implicitHeight)
        height: Math.max(32, implicitHeight)

        IconButton {
            id: backButton
            visible: root.backVisible
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            icon: "arrow_back"
            size: 32
            variant: "plain"
            onClicked: root.back()
        }

        Label {
            id: titleLabel
            visible: root.title.length > 0
            anchors.left: backButton.visible ? backButton.right : parent.left
            anchors.leftMargin: backButton.visible ? Style.s2 : 0
            anchors.right: trailingRow.left
            anchors.rightMargin: trailingRow.width > 0 ? Style.s3 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            role: "title"
        }

        Row {
            id: trailingRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.s2
        }
    }

    Column {
        id: contentColumn
        x: root.padding
        y: root.padding + (root.headerVisible ? headerRow.height + Style.s3 : 0)
        width: Math.max(0, root.width - root.padding * 2)
        spacing: Style.s4
    }
}
