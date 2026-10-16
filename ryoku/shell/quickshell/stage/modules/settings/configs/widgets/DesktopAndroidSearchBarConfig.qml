import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    function actionIcon(key) {
        if (key === "music_rec") return "music_note";
        if (key === "ai_chat") return "neurology";
        if (key === "translator") return "translate";
        if (key === "wallpapers") return "wallpaper";
        if (key === "phone") return "smartphone";
        if (key === "cheatsheet") return "apps";
        if (key === "clipboard") return "content_paste";
        if (key === "color_picker") return "colorize";
        if (key === "screenshot") return "crop";
        return "search";
    }

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius:    Appearance.rounding.full
            topRightRadius:   Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius:Appearance.rounding.full
            colBackground:      Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple:          Appearance.colors.colSecondaryContainerActive
            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Android Search Bar Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family:    Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Search Bar Settings")
        icon: "search"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("android_search_bar")

            PagePlaceholder {
                anchors.fill: parent
                icon:    "search"
                shape:   MaterialShape.Shape.Circle
                title:       Translation.tr("Android Search Bar disabled")
                description: Translation.tr("Enable Android Search Bar in Desktop Widgets settings to configure options.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("android_search_bar")

            // ── Widget Grid Size / Aspect Ratio Preset ──────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Widget Aspect Ratio & Size") }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.android_search_bar.aspectRatio ?? "0.5x2"
                onSelected: value => Config.options.background.widgets.android_search_bar.aspectRatio = value
                options: [
                    { displayName: "0.5x2 (Compact)", icon: "crop_landscape", value: "0.5x2" },
                    { displayName: "2x1 (Medium)", icon: "crop_16_9", value: "2x1" },
                    { displayName: "3x1 (Wide)", icon: "crop_free", value: "3x1" },
                    { displayName: "4x1 (Full Width)", icon: "fit_screen", value: "4x1" }
                ]
            }

            // ── Button 1 Action ──────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Button 1 Action (Inner Bar Left)") }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.android_search_bar.action1 ?? "music_rec"
                onSelected: value => Config.options.background.widgets.android_search_bar.action1 = value
                options: [
                    { displayName: Translation.tr("Music Recognition"), icon: "music_note", value: "music_rec" },
                    { displayName: Translation.tr("AI Chat"), icon: "neurology", value: "ai_chat" },
                    { displayName: Translation.tr("Translator"), icon: "translate", value: "translator" },
                    { displayName: Translation.tr("Search Overlay"), icon: "search", value: "search" },
                    { displayName: Translation.tr("Wallpapers"), icon: "wallpaper", value: "wallpapers" },
                    { displayName: Translation.tr("Phone / KDE Connect"), icon: "smartphone", value: "phone" },
                    { displayName: Translation.tr("Kit"), icon: "apps", value: "cheatsheet" },
                    { displayName: Translation.tr("Clipboard"), icon: "content_paste", value: "clipboard" },
                    { displayName: Translation.tr("Color Picker"), icon: "colorize", value: "color_picker" },
                    { displayName: Translation.tr("Screenshot"), icon: "crop", value: "screenshot" }
                ]
            }

            // ── Button 2 Action ──────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Button 2 Action (Inner Bar Right)") }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.android_search_bar.action2 ?? "ai_chat"
                onSelected: value => Config.options.background.widgets.android_search_bar.action2 = value
                options: [
                    { displayName: Translation.tr("AI Chat"), icon: "neurology", value: "ai_chat" },
                    { displayName: Translation.tr("Music Recognition"), icon: "music_note", value: "music_rec" },
                    { displayName: Translation.tr("Translator"), icon: "translate", value: "translator" },
                    { displayName: Translation.tr("Search Overlay"), icon: "search", value: "search" },
                    { displayName: Translation.tr("Wallpapers"), icon: "wallpaper", value: "wallpapers" },
                    { displayName: Translation.tr("Phone / KDE Connect"), icon: "smartphone", value: "phone" },
                    { displayName: Translation.tr("Kit"), icon: "apps", value: "cheatsheet" },
                    { displayName: Translation.tr("Clipboard"), icon: "content_paste", value: "clipboard" },
                    { displayName: Translation.tr("Color Picker"), icon: "colorize", value: "color_picker" },
                    { displayName: Translation.tr("Screenshot"), icon: "crop", value: "screenshot" }
                ]
            }

            // ── Button 3 Action ──────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Button 3 Action (Outer Circle)") }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.android_search_bar.action3 ?? "search"
                onSelected: value => Config.options.background.widgets.android_search_bar.action3 = value
                options: [
                    { displayName: Translation.tr("Search Overlay"), icon: "search", value: "search" },
                    { displayName: Translation.tr("AI Chat"), icon: "neurology", value: "ai_chat" },
                    { displayName: Translation.tr("Music Recognition"), icon: "music_note", value: "music_rec" },
                    { displayName: Translation.tr("Translator"), icon: "translate", value: "translator" },
                    { displayName: Translation.tr("Wallpapers"), icon: "wallpaper", value: "wallpapers" },
                    { displayName: Translation.tr("Phone / KDE Connect"), icon: "smartphone", value: "phone" },
                    { displayName: Translation.tr("Kit"), icon: "apps", value: "cheatsheet" },
                    { displayName: Translation.tr("Clipboard"), icon: "content_paste", value: "clipboard" },
                    { displayName: Translation.tr("Color Picker"), icon: "colorize", value: "color_picker" },
                    { displayName: Translation.tr("Screenshot"), icon: "crop", value: "screenshot" }
                ]
            }

            ContentSubsectionLabel { text: Translation.tr("Button Icons") }

            ConfigTextField {
                id: icon1Field
                text: Translation.tr("Button 1 icon")
                icon: "filter_1"
                tooltip: Translation.tr("Optional Material Symbol name. Leave empty to use the selected action's icon.")
                placeholderText: root.actionIcon(Config.options.background.widgets.android_search_bar.action1 ?? "music_rec")
                Component.onCompleted: inputText = Config.options.background.widgets.android_search_bar.icon1 ?? ""
                textField.onTextChanged: {
                    if (textField.activeFocus)
                        Config.options.background.widgets.android_search_bar.icon1 = textField.text.trim();
                }
            }

            ConfigTextField {
                id: icon2Field
                text: Translation.tr("Button 2 icon")
                icon: "filter_2"
                tooltip: Translation.tr("Optional Material Symbol name. Leave empty to use the selected action's icon.")
                placeholderText: root.actionIcon(Config.options.background.widgets.android_search_bar.action2 ?? "ai_chat")
                Component.onCompleted: inputText = Config.options.background.widgets.android_search_bar.icon2 ?? ""
                textField.onTextChanged: {
                    if (textField.activeFocus)
                        Config.options.background.widgets.android_search_bar.icon2 = textField.text.trim();
                }
            }

            ConfigTextField {
                id: icon3Field
                text: Translation.tr("Button 3 icon")
                icon: "filter_3"
                tooltip: Translation.tr("Optional Material Symbol name. Leave empty to use the selected action's icon.")
                placeholderText: root.actionIcon(Config.options.background.widgets.android_search_bar.action3 ?? "search")
                Component.onCompleted: inputText = Config.options.background.widgets.android_search_bar.icon3 ?? ""
                textField.onTextChanged: {
                    if (textField.activeFocus)
                        Config.options.background.widgets.android_search_bar.icon3 = textField.text.trim();
                }
            }

            // ── Scale & Appearance ───────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Scale & Appearance") }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text:  Translation.tr("Widget Scale")
                value: Config.options.background.widgets.android_search_bar.widgetSize ?? 100
                from: 50; to: 200; stepSize: 10
                onValueChanged: Config.options.background.widgets.android_search_bar.widgetSize = value
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.enableShadows ?? true
                onCheckedChanged: Config.options.background.widgets.enableShadows = checked
            }
        }
    }
}
