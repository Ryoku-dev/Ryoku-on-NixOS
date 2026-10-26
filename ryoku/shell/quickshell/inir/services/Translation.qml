pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Ryoku.Ui.Singletons as RyokuUi

QtObject {
    readonly property var locale: {
        const language = RyokuUi.I18n.langs.find(entry => entry.code === RyokuUi.I18n.lang)
        const localeName = String(language?.locale ?? RyokuUi.I18n.lang).split(".")[0]
        return Qt.locale(localeName)
    }

    function tr(text) {
        return RyokuUi.I18n.tr(text)
    }
}
