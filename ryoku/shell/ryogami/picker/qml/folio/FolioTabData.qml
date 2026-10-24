import QtQuick

// Presentation only: defaults, ranges and live values come from the daemon schema through SettingValue.
QtObject {
    property string tabKey: ""
    property string title: ""
    property string note: ""
    property var sections: []
}
