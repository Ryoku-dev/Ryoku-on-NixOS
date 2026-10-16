.pragma library

// The ii desktop widgets' quick knobs: per registry widget id, up to three of
// the widget's own settings worth a right-click, in the order the menu lists
// them. Every key is a property of the face's options store, storeFor(id): a
// dotted path under the stage Config.options naming the object the widget's
// Settings page writes and the face reads. A key may itself be a dotted path
// into a nested object of the store ("visualizer.enable"); the whole set stays
// on that page under Customize.
//
//   { key, label, type: "toggle", def }
//   { key, label, type: "cycle", def, choices: [{ value, label }] }
//
// `def` is the face's own fallback for an unset key, so the menu shows what
// the face draws. Labels are translation keys (I18n.tr at the menu).
var controls = {
    // ── Clocks ──
    "clock_cookie": [
        { key: "hourMarks", label: "Hour marks", type: "toggle", def: false },
        { key: "timeIndicators", label: "Middle digits", type: "toggle", def: true },
        { key: "secondHandStyle", label: "Second hand", type: "cycle", def: "dot", choices: [
            { value: "hide", label: "Hidden" },
            { value: "line", label: "Line" },
            { value: "dot", label: "Dot" },
            { value: "classic", label: "Classic" }
        ] }
    ],
    "clock_digital": [
        { key: "showSeconds", label: "Seconds", type: "toggle", def: false },
        { key: "showDate", label: "Date", type: "toggle", def: true },
        { key: "colorful", label: "Colorful digits", type: "toggle", def: false }
    ],
    "clock_nagasaki": [
        { key: "monochrome", label: "Monochrome", type: "toggle", def: false }
    ],
    "clock_flex": [
        { key: "useAltColors", label: "Card colors", type: "toggle", def: false }
    ],
    "clock_hori": [
        { key: "showColon", label: "Colon", type: "toggle", def: true },
        { key: "useAltColors", label: "Card colors", type: "toggle", def: false }
    ],
    "clock_ios": [
        { key: "showDate", label: "Date", type: "toggle", def: true },
        { key: "timeFormat", label: "Time format", type: "cycle", def: "system", choices: [
            { value: "system", label: "System" },
            { value: "12h", label: "12-hour" },
            { value: "24h", label: "24-hour" }
        ] }
    ],
    "clock_nothing": [
        { key: "use24h", label: "24-hour time", type: "toggle", def: true },
        { key: "showDate", label: "Date", type: "toggle", def: true },
        { key: "useAccentColor", label: "Accent hours", type: "toggle", def: false }
    ],
    "nothing_wheel_clock": [
        { key: "timeFormat", label: "Time format", type: "cycle", def: "system", choices: [
            { value: "system", label: "System" },
            { value: "12h", label: "12-hour" },
            { value: "24h", label: "24-hour" }
        ] },
        { key: "showDateHeader", label: "Date header", type: "toggle", def: true },
        { key: "showMinuteNeighbors", label: "Nearby minutes", type: "toggle", def: true }
    ],
    "nagasaki_text": [
        { key: "colorStyle", label: "Text color", type: "cycle", def: "surface", choices: [
            { value: "surface", label: "Surface" },
            { value: "text", label: "Text" },
            { value: "accent", label: "Accent" }
        ] }
    ],
    "clock_word": [
        { key: "backgroundStyle", label: "Background", type: "cycle", def: "shape", choices: [
            { value: "shape", label: "Shape" },
            { value: "transparent", label: "Transparent" }
        ] },
        { key: "backgroundShape", label: "Shape", type: "cycle", def: "Circle", choices: [
            { value: "Circle", label: "Circle" },
            { value: "Square", label: "Square" },
            { value: "Cookie12Sided", label: "Cookie" }
        ] }
    ],
    "clock_dial": [
        { key: "showSecondHand", label: "Second hand", type: "toggle", def: false },
        { key: "showNumberRing", label: "Number ring", type: "toggle", def: false },
        { key: "showTicks", label: "Dial ticks", type: "toggle", def: true }
    ],
    "clock_wearos": [
        { key: "showMinuteHand", label: "Minute hand", type: "toggle", def: true },
        { key: "showOuterNumbers", label: "Outer numbers", type: "toggle", def: true },
        { key: "showDigitalTimePill", label: "Digital time", type: "toggle", def: true }
    ],
    "wearos_arc_clock": [
        { key: "blackBackground", label: "Black background", type: "toggle", def: false },
        { key: "enableBackgroundPattern", label: "Dot pattern", type: "toggle", def: true },
        { key: "enableGlassReflection", label: "Glass reflection", type: "toggle", def: true }
    ],
    "concentric_clock": [
        { key: "use24h", label: "24-hour time", type: "toggle", def: true },
        { key: "showArc24h", label: "24h progress", type: "toggle", def: false },
        {
            key: "dialStyle",
            label: "Dial style",
            type: "cycle",
            def: "concentric",
            choices: [
                { value: "concentric", label: "Concentric" },
                { value: "outer_only", label: "Outer only" },
                { value: "inner_only", label: "Inner only" },
                { value: "full_pixel3", label: "Pixel Watch 3" },
                { value: "full_dense", label: "Full dense" },
                { value: "minimal_arc", label: "Minimal arc" },
                { value: "dots", label: "Dots" },
                { value: "numbers", label: "Numbers" },
                { value: "full", label: "Full ticks" },
                { value: "shapes", label: "Material shapes" },
                { value: "none", label: "None" }
            ]
        }
    ],
    "month_clock": [
        {
            key: "secondHandStyle",
            label: "Second hand",
            type: "cycle",
            def: "line",
            choices: [
                { value: "line", label: "Line" },
                { value: "dot", label: "Dot" },
                { value: "classic", label: "Classic" },
                { value: "hide", label: "Hidden" }
            ]
        },
        { key: "showTickMarks", label: "Tick marks", type: "toggle", def: true },
        { key: "showMonthRing", label: "Month ring", type: "toggle", def: true }
    ],
    "scallop_dot_clock": [
        { key: "showHourHand", label: "Hour bubble", type: "toggle", def: true },
        { key: "showMinuteBubble", label: "Minute bubble", type: "toggle", def: true },
        { key: "showDots", label: "Background dots", type: "toggle", def: true }
    ],
    "scallop_number_clock": [
        { key: "showHourHand", label: "Hour bubble", type: "toggle", def: true },
        { key: "showMinuteBubble", label: "Minute bubble", type: "toggle", def: true },
        { key: "showDots", label: "Background numbers", type: "toggle", def: true }
    ],
    "circle_pointer_clock": [
        { key: "showDots", label: "Minute numbers", type: "toggle", def: true },
        { key: "boldFont", label: "Bold type", type: "toggle", def: true },
        { key: "useBlackBg", label: "Black background", type: "toggle", def: true }
    ],
    "triple_ring_clock": [
        { key: "boldFont", label: "Bold type", type: "toggle", def: true },
        { key: "useBlackBg", label: "Black background", type: "toggle", def: true },
        { key: "enableGlassReflection", label: "Glass reflection", type: "toggle", def: false }
    ],
    "grid_card_clock": [
        {
            key: "widgetSize",
            label: "Size",
            type: "cycle",
            def: 100,
            choices: [
                { value: 75, label: "Small" },
                { value: 100, label: "Default" },
                { value: 125, label: "Large" },
                { value: 150, label: "Extra large" }
            ]
        }
    ],
    "clock_expressive_card": [
        {
            key: "widgetSize",
            label: "Size",
            type: "cycle",
            def: 100,
            choices: [
                { value: 75, label: "Small" },
                { value: 100, label: "Default" },
                { value: 125, label: "Large" },
                { value: 150, label: "Extra large" }
            ]
        }
    ],

    // ── Media ──
    "circular_media": [
        { key: "useAlbumColors", label: "Album colors", type: "toggle", def: true },
        { key: "showDevicePill", label: "Audio device", type: "toggle", def: true },
        { key: "enableGlassReflection", label: "Glass reflection", type: "toggle", def: true }
    ],
    "media_circular": [
        { key: "visualizer.enable", label: "Visualizer", type: "toggle", def: false },
        { key: "useAlbumColors", label: "Album colors", type: "toggle", def: true },
        { key: "hideAllButtons", label: "Hide controls", type: "toggle", def: false }
    ],
    "media_expressive": [
        { key: "dynamicAlbumColors", label: "Album colors", type: "toggle", def: false },
        { key: "rotateAlbumArt", label: "Rotate album art", type: "toggle", def: true },
        { key: "showProgressSlider", label: "Progress slider", type: "toggle", def: true }
    ],
    "media_android": [
        { key: "dynamicAlbumColors", label: "Album colors", type: "toggle", def: false },
        { key: "showLyrics", label: "Synced lyrics", type: "toggle", def: true },
        { key: "showControls", label: "Playback controls", type: "toggle", def: true }
    ],
    "media_cd": [
        { key: "dynamicAlbumColors", label: "Album colors", type: "toggle", def: false },
        { key: "enableShadows", label: "Shadow", type: "toggle", def: true },
        { key: "enableInnerShadow", label: "Inner shadow", type: "toggle", def: true }
    ],
    "nothing_ring_media": [
        { key: "enableShadows", label: "Shadow", type: "toggle", def: true }
    ],
    "compact_media": [
        { key: "dynamicAlbumColors", label: "Album colors", type: "toggle", def: false },
        { key: "enableShadows", label: "Shadow", type: "toggle", def: true }
    ],

    // ── Weather ──
    "weather_default": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: false },
        { key: "showTemperature", label: "Temperature", type: "toggle", def: true },
        { key: "showIcon", label: "Weather icon", type: "toggle", def: true }
    ],
    "weather_expressive": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: false },
        { key: "showTemperature", label: "Temperature", type: "toggle", def: true },
        { key: "backgroundShape", label: "Card shape", type: "cycle", def: "Cookie9Sided", choices: [
            { value: "Circle", label: "Circle" },
            { value: "Cookie9Sided", label: "Cookie" },
            { value: "Puffy", label: "Puffy" },
            { value: "Sunny", label: "Sunny" }
        ] }
    ],
    "weather_forecast": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: true },
        { key: "showForecast", label: "Forecast", type: "toggle", def: true },
        { key: "showLocation", label: "Location", type: "toggle", def: true }
    ],
    "weather_card": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: true },
        { key: "showForecast", label: "Forecast", type: "toggle", def: true },
        { key: "showLocation", label: "Location", type: "toggle", def: true }
    ],
    "weather_icon": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: true },
        { key: "showBackground", label: "Background", type: "toggle", def: true },
        { key: "backgroundShape", label: "Icon shape", type: "cycle", def: "Cookie12Sided", choices: [
            { value: "Circle", label: "Circle" },
            { value: "Cookie12Sided", label: "Cookie" },
            { value: "Puffy", label: "Puffy" },
            { value: "Sunny", label: "Sunny" }
        ] }
    ],
    "weather_pill": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: true },
        { key: "showTemperature", label: "Temperature", type: "toggle", def: true },
        { key: "showIcon", label: "Weather icon", type: "toggle", def: true }
    ],
    "weather_circle": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: true },
        { key: "showTemperature", label: "Temperature", type: "toggle", def: true },
        { key: "showLocation", label: "Location", type: "toggle", def: true }
    ],
    "nothing_weather_circle": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: false },
        { key: "showTemperature", label: "Temperature", type: "toggle", def: false }
    ],
    "weather_typography": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: true },
        { key: "showFeelsLike", label: "Feels-like", type: "toggle", def: true },
        { key: "showCondition", label: "Condition", type: "toggle", def: true }
    ],
    "weather_hourly": [
        { key: "expressiveColors", label: "Expressive colors", type: "toggle", def: true },
        { key: "showHourly", label: "Hourly forecast", type: "toggle", def: true },
        { key: "showForecast", label: "Daily forecast", type: "toggle", def: true }
    ],

    // ── Date and Photo ──
    "date_default": [
        { key: "uppercaseMonth", label: "Uppercase month", type: "toggle", def: true }
    ],
    "calendar_minimal": [
        { key: "weekdayFormat", label: "Weekday label", type: "cycle", def: "dddd", choices: [
            { value: "dddd", label: "Full" },
            { value: "ddd", label: "Short" }
        ] },
        { key: "monthFormat", label: "Month label", type: "cycle", def: "MMMM", choices: [
            { value: "MMMM", label: "Full" },
            { value: "MMM", label: "Short" }
        ] }
    ],
    "calendar_grid": [
        { key: "weekStart", label: "Week start", type: "cycle", def: "monday", choices: [
            { value: "monday", label: "Monday" },
            { value: "sunday", label: "Sunday" }
        ] }
    ],
    "calendar_agenda": [
        { key: "weekStart", label: "Week start", type: "cycle", def: "monday", choices: [
            { value: "monday", label: "Monday" },
            { value: "sunday", label: "Sunday" }
        ] },
        { key: "maxEvents", label: "Events shown", type: "cycle", def: 0, choices: [
            { value: 0, label: "All" },
            { value: 1, label: "1" },
            { value: 3, label: "3" },
            { value: 5, label: "5" }
        ] },
        { key: "showEventDots", label: "Event dots", type: "toggle", def: true }
    ],
    "calendar_next_event": [
        { key: "maxEvents", label: "Events shown", type: "cycle", def: 0, choices: [
            { value: 0, label: "All" },
            { value: 1, label: "1" },
            { value: 3, label: "3" },
            { value: 5, label: "5" }
        ] },
        { key: "showAddButton", label: "Add event button", type: "toggle", def: true }
    ],
    "calendar_pill": [
        { key: "weekdayFormat", label: "Weekday label", type: "cycle", def: "dddd", choices: [
            { value: "dddd", label: "Full" },
            { value: "ddd", label: "Short" }
        ] }
    ],
    "calendar_upcoming_3days": [
        { key: "daysShown", label: "Days shown", type: "cycle", def: 3, choices: [
            { value: 1, label: "1" },
            { value: 2, label: "2" },
            { value: 3, label: "3" }
        ] },
        { key: "maxEventsPerDay", label: "Events per day", type: "cycle", def: 0, choices: [
            { value: 0, label: "All" },
            { value: 1, label: "1" },
            { value: 2, label: "2" },
            { value: 3, label: "3" }
        ] },
        { key: "showAddButton", label: "Add event button", type: "toggle", def: true }
    ],
    "photo": [
        { key: "fitMode", label: "Photo fit", type: "cycle", def: "crop", choices: [
            { value: "crop", label: "Crop" },
            { value: "fit", label: "Fit" }
        ] }
    ],
    "photo_1x1": [
        { key: "fitMode", label: "Photo fit", type: "cycle", def: "crop", choices: [
            { value: "crop", label: "Crop" },
            { value: "fit", label: "Fit" }
        ] }
    ],
    "photo_weather_2x1": [
        { key: "fitMode", label: "Photo fit", type: "cycle", def: "crop", choices: [
            { value: "crop", label: "Crop" },
            { value: "fit", label: "Fit" }
        ] },
        { key: "showOverlay", label: "Caption", type: "toggle", def: true }
    ],
    "photo_pill_2x1": [
        { key: "fitMode", label: "Photo fit", type: "cycle", def: "crop", choices: [
            { value: "crop", label: "Crop" },
            { value: "fit", label: "Fit" }
        ] },
        { key: "showOverlay", label: "Caption", type: "toggle", def: true }
    ],
    "photo_minimal_temp_2x1": [
        { key: "fitMode", label: "Photo fit", type: "cycle", def: "crop", choices: [
            { value: "crop", label: "Crop" },
            { value: "fit", label: "Fit" }
        ] },
        { key: "showOverlay", label: "Caption", type: "toggle", def: true }
    ],


    // ── Devices ──
    "bluetooth_battery": [
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true }
    ],
    "bluetooth_headphone": [
        { key: "halfSize", label: "Compact size", type: "toggle", def: true },
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true }
    ],
    "mobile_battery": [
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true }
    ],
    "bluetooth_headphone_cookie": [
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true },
        { key: "materialShape", label: "Card shape", type: "cycle", def: "Cookie12Sided", choices: [
            { value: "Circle", label: "Circle" },
            { value: "Cookie12Sided", label: "Cookie" },
            { value: "Puffy", label: "Puffy" },
            { value: "Sunny", label: "Sunny" }
        ] }
    ],
    "bluetooth_fill_cards": [
        { key: "maxDevices", label: "Devices shown", type: "cycle", def: 4, choices: [
            { value: 1, label: "One" }, { value: 2, label: "Two" },
            { value: 3, label: "Three" }, { value: 4, label: "Four" }
        ] },
        { key: "showDeviceName", label: "Device names", type: "toggle", def: true },
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true }
    ],
    "pc_battery_bars": [
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true },
        { key: "showStatus", label: "Battery status", type: "toggle", def: true }
    ],
    "pc_battery_cable": [
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true },
        { key: "showChargingIcon", label: "Charging icon", type: "toggle", def: true }
    ],
    "devices_battery_list": [
        { key: "maxDevices", label: "Devices shown", type: "cycle", def: 4, choices: [
            { value: 1, label: "One" }, { value: 2, label: "Two" },
            { value: 3, label: "Three" }, { value: 4, label: "Four" }
        ] },
        { key: "showDeviceName", label: "Device names", type: "toggle", def: true },
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true }
    ],
    "devices_battery_list_1x1": [
        { key: "maxDevices", label: "Devices shown", type: "cycle", def: 4, choices: [
            { value: 1, label: "One" }, { value: 2, label: "Two" },
            { value: 3, label: "Three" }, { value: 4, label: "Four" }
        ] },
        { key: "showDeviceName", label: "Device names", type: "toggle", def: true },
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true }
    ],
    "bluetooth_earbuds_stem": [
        { key: "showDeviceName", label: "Device name", type: "toggle", def: true },
        { key: "showPercentage", label: "Show percentage", type: "toggle", def: true }
    ],


    // ── Utility ──
    "ai_chat": [
        { key: "useMaterialSymbol", label: "Symbol icon", type: "toggle", def: false }
    ],
    "quick_actions": [
        { key: "bottomButton1", label: "Left shortcut", type: "cycle", def: "translator", choices: [
            { value: "translator", label: "Translator" },
            { value: "phone", label: "Phone" },
            { value: "wallpapers", label: "Wallpapers" },
            { value: "media", label: "Media" },
            { value: "sidebar_dashboard", label: "Dashboard" },
            { value: "cheatsheet", label: "Kit" }
        ] },
        { key: "bottomButton2", label: "Right shortcut", type: "cycle", def: "phone", choices: [
            { value: "translator", label: "Translator" },
            { value: "phone", label: "Phone" },
            { value: "wallpapers", label: "Wallpapers" },
            { value: "media", label: "Media" },
            { value: "sidebar_dashboard", label: "Dashboard" },
            { value: "cheatsheet", label: "Kit" }
        ] }
    ],
    "android_search_bar": [
        { key: "action1", label: "Left action", type: "cycle", def: "music_rec", choices: [
            { value: "music_rec", label: "Music recognition" },
            { value: "ai_chat", label: "AI chat" },
            { value: "translator", label: "Translator" },
            { value: "search", label: "Search" },
            { value: "wallpapers", label: "Wallpapers" },
            { value: "phone", label: "Phone" },
            { value: "cheatsheet", label: "Kit" },
            { value: "clipboard", label: "Clipboard" },
            { value: "color_picker", label: "Color picker" },
            { value: "screenshot", label: "Screenshot" }
        ] },
        { key: "action2", label: "Center action", type: "cycle", def: "ai_chat", choices: [
            { value: "ai_chat", label: "AI chat" },
            { value: "music_rec", label: "Music recognition" },
            { value: "translator", label: "Translator" },
            { value: "search", label: "Search" },
            { value: "wallpapers", label: "Wallpapers" },
            { value: "phone", label: "Phone" },
            { value: "cheatsheet", label: "Kit" },
            { value: "clipboard", label: "Clipboard" },
            { value: "color_picker", label: "Color picker" },
            { value: "screenshot", label: "Screenshot" }
        ] },
        { key: "action3", label: "Right action", type: "cycle", def: "search", choices: [
            { value: "search", label: "Search" },
            { value: "ai_chat", label: "AI chat" },
            { value: "music_rec", label: "Music recognition" },
            { value: "translator", label: "Translator" },
            { value: "wallpapers", label: "Wallpapers" },
            { value: "phone", label: "Phone" },
            { value: "cheatsheet", label: "Kit" },
            { value: "clipboard", label: "Clipboard" },
            { value: "color_picker", label: "Color picker" },
            { value: "screenshot", label: "Screenshot" }
        ] }
    ],
    "search_pill": [
        { key: "action1", label: "Left action", type: "cycle", def: "ai_chat", choices: [
            { value: "ai_chat", label: "AI chat" },
            { value: "music_rec", label: "Music recognition" },
            { value: "translator", label: "Translator" },
            { value: "search", label: "Search" },
            { value: "wallpapers", label: "Wallpapers" },
            { value: "phone", label: "Phone" },
            { value: "cheatsheet", label: "Kit" },
            { value: "clipboard", label: "Clipboard" },
            { value: "color_picker", label: "Color picker" },
            { value: "screenshot", label: "Screenshot" }
        ] },
        { key: "action2", label: "Center action", type: "cycle", def: "music_rec", choices: [
            { value: "music_rec", label: "Music recognition" },
            { value: "ai_chat", label: "AI chat" },
            { value: "translator", label: "Translator" },
            { value: "search", label: "Search" },
            { value: "wallpapers", label: "Wallpapers" },
            { value: "phone", label: "Phone" },
            { value: "cheatsheet", label: "Kit" },
            { value: "clipboard", label: "Clipboard" },
            { value: "color_picker", label: "Color picker" },
            { value: "screenshot", label: "Screenshot" }
        ] },
        { key: "action3", label: "Right action", type: "cycle", def: "search", choices: [
            { value: "search", label: "Search" },
            { value: "ai_chat", label: "AI chat" },
            { value: "music_rec", label: "Music recognition" },
            { value: "translator", label: "Translator" },
            { value: "wallpapers", label: "Wallpapers" },
            { value: "phone", label: "Phone" },
            { value: "cheatsheet", label: "Kit" },
            { value: "clipboard", label: "Clipboard" },
            { value: "color_picker", label: "Color picker" },
            { value: "screenshot", label: "Screenshot" }
        ] }
    ],
    "quote": [
        { key: "fontSize", label: "Text size", type: "cycle", def: 16, choices: [
            { value: 12, label: "Small" },
            { value: 16, label: "Medium" },
            { value: 20, label: "Large" },
            { value: 24, label: "Extra large" }
        ] }
    ],
    "water_reminder": [
        { key: "enable", label: "Drink reminders", type: "toggle", def: false },
        { key: "dailyGoal", label: "Daily goal", type: "cycle", def: 8, choices: [
            { value: 6, label: "6 glasses" },
            { value: 8, label: "8 glasses" },
            { value: 10, label: "10 glasses" },
            { value: 12, label: "12 glasses" }
        ] },
        { key: "intervalHours", label: "Reminder interval", type: "cycle", def: 2, choices: [
            { value: 1, label: "Every hour" },
            { value: 2, label: "Every 2 hours" },
            { value: 4, label: "Every 4 hours" },
            { value: 6, label: "Every 6 hours" }
        ] }
    ],
    "at_a_glance": [
        { key: "widthCells", label: "Width", type: "cycle", def: 3, choices: [
            { value: 2, label: "Compact" },
            { value: 3, label: "Full" },
            { value: 4, label: "Expanded" }
        ] },
        { key: "dualColumnMode", label: "Two contexts", type: "toggle", def: false },
        { key: "enableWeather", label: "Weather", type: "toggle", def: true }
    ],

    // ── System and Resources ──
    "easyeffects_preset_portrait": [
        { key: "pipeline", label: "Audio path", type: "cycle", def: "output", choices: [
            { value: "output", label: "Output" }, { value: "input", label: "Input" }
        ] },
        { key: "topography", label: "Contour lines", type: "toggle", def: true },
        { key: "showButtons", label: "Buttons", type: "toggle", def: true }
    ],
    "easyeffects_preset_landscape": [
        { key: "pipeline", label: "Audio path", type: "cycle", def: "output", choices: [
            { value: "output", label: "Output" }, { value: "input", label: "Input" }
        ] },
        { key: "topography", label: "Contour lines", type: "toggle", def: true },
        { key: "showButtons", label: "Buttons", type: "toggle", def: true }
    ],
    "resource_cpu_pill": [
        { key: "aspectRatio", label: "Layout", type: "cycle", def: "2x0.5", choices: [
            { value: "1x0.5", label: "Compact" }, { value: "2x0.5", label: "Standard" }
        ] },
        { key: "showDetails", label: "Temperature", type: "toggle", def: true },
        { key: "widgetSize", label: "Size", type: "cycle", def: 100, choices: [
            { value: 75, label: "75%" }, { value: 100, label: "100%" },
            { value: 125, label: "125%" }, { value: 150, label: "150%" }
        ] }
    ],
    "resource_ram_pill": [
        { key: "aspectRatio", label: "Layout", type: "cycle", def: "2x0.5", choices: [
            { value: "1x0.5", label: "Compact" }, { value: "2x0.5", label: "Standard" }
        ] },
        { key: "showDetails", label: "Usage details", type: "toggle", def: true },
        { key: "widgetSize", label: "Size", type: "cycle", def: 100, choices: [
            { value: 75, label: "75%" }, { value: 100, label: "100%" },
            { value: 125, label: "125%" }, { value: 150, label: "150%" }
        ] }
    ],
    "resource_disk_pill": [
        { key: "aspectRatio", label: "Layout", type: "cycle", def: "2x0.5", choices: [
            { value: "1x0.5", label: "Compact" }, { value: "2x0.5", label: "Standard" }
        ] },
        { key: "showDetails", label: "Usage details", type: "toggle", def: true },
        { key: "widgetSize", label: "Size", type: "cycle", def: 100, choices: [
            { value: 75, label: "75%" }, { value: 100, label: "100%" },
            { value: 125, label: "125%" }, { value: 150, label: "150%" }
        ] }
    ],
    "resource_fill_cards": [
        { key: "enableCpu", label: "CPU card", type: "toggle", def: true },
        { key: "enableRam", label: "RAM card", type: "toggle", def: true },
        { key: "enableDisk", label: "Disk card", type: "toggle", def: true }
    ],
    "resource_nothing_disk": [
        { key: "useAccentColor", label: "Accent colour", type: "toggle", def: false },
        { key: "widgetSize", label: "Size", type: "cycle", def: 100, choices: [
            { value: 75, label: "75%" }, { value: 100, label: "100%" },
            { value: 125, label: "125%" }, { value: 150, label: "150%" }
        ] }
    ],
    "resource_nothing_cpu": [
        { key: "useAccentColor", label: "Accent colour", type: "toggle", def: false },
        { key: "widgetSize", label: "Size", type: "cycle", def: 100, choices: [
            { value: 75, label: "75%" }, { value: 100, label: "100%" },
            { value: 125, label: "125%" }, { value: 150, label: "150%" }
        ] }
    ],
    "resource_nothing_ram": [
        { key: "useAccentColor", label: "Accent colour", type: "toggle", def: false },
        { key: "widgetSize", label: "Size", type: "cycle", def: 100, choices: [
            { value: 75, label: "75%" }, { value: 100, label: "100%" },
            { value: 125, label: "125%" }, { value: 150, label: "150%" }
        ] }
    ],
};

// Most faces keep their options in background.widgets.<id>. These keep them
// where the face reads them under another name, several shared with a sibling
// entry so one Settings page and one knob drive both.
var faceStores = {
    "clock_wearos": "background.widgets.wearos_clock",
    "date_default": "background.widgets.date",
    "media_circular": "background.widgets.media",
    "media_expressive": "background.widgets.media",
    "media_android": "background.widgets.media",
    "weather_default": "background.widgets.weather",
    "weather_expressive": "background.widgets.weather",
    "easyeffects_preset_portrait": "easyEffects.widget",
    "easyeffects_preset_landscape": "easyEffects.widget"
};

function forWidget(id) {
    return controls[id] || [];
}

function storeFor(id) {
    return faceStores[id] || ("background.widgets." + id);
}
