.pragma library

// The ii desktop-widget roster: every widget the stage's vendored ii registry
// declares, one row each. id is the registry widgetId (the face file resolves
// through WidgetsRegistry.getQmlPath); prefix is the widgets.json key stem;
// gloss is the kanji seal the widget menu wears. The faces read their own
// options from the stage config, so the slot contract here is placement,
// scale, opacity and backing only.
var faces = [
    { id: "clock_cookie", prefix: "iiClockCookie", label: "Cookie Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_digital", prefix: "iiClockDigital", label: "Digital Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_nagasaki", prefix: "iiClockNagasaki", label: "Nagasaki Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_flex", prefix: "iiClockFlex", label: "Flex Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_hori", prefix: "iiClockHori", label: "Hori Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_ios", prefix: "iiClockIos", label: "iOS Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_nothing", prefix: "iiClockNothing", label: "Nothing Digital Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "nothing_wheel_clock", prefix: "iiNothingWheelClock", label: "Nothing Wheel Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "nagasaki_text", prefix: "iiNagasakiText", label: "Nagasaki Text Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_word", prefix: "iiClockWord", label: "Word Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_dial", prefix: "iiClockDial", label: "Dial Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_wearos", prefix: "iiClockWearos", label: "WearOS Clock (Watch)", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "wearos_arc_clock", prefix: "iiWearosArcClock", label: "WearOS Arc Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "concentric_clock", prefix: "iiConcentricClock", label: "Concentric Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "month_clock", prefix: "iiMonthClock", label: "Month Clock", icon: "calendar_month", gloss: "時計", category: "Clock" },
    { id: "scallop_dot_clock", prefix: "iiScallopDotClock", label: "Scallop Dot Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "scallop_number_clock", prefix: "iiScallopNumberClock", label: "Scallop Number Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "circle_pointer_clock", prefix: "iiCirclePointerClock", label: "Circle Pointer Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "triple_ring_clock", prefix: "iiTripleRingClock", label: "Triple Ring Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "grid_card_clock", prefix: "iiGridCardClock", label: "Grid Card Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "clock_expressive_card", prefix: "iiClockExpressiveCard", label: "Expressive Card Clock", icon: "schedule", gloss: "時計", category: "Clock" },
    { id: "circular_media", prefix: "iiCircularMedia", label: "Circular Media (Watch)", icon: "play_circle", gloss: "音楽", category: "Media" },
    { id: "media_circular", prefix: "iiMediaCircular", label: "Circular Media", icon: "play_circle", gloss: "音楽", category: "Media" },
    { id: "media_expressive", prefix: "iiMediaExpressive", label: "Expressive Media", icon: "music_note", gloss: "音楽", category: "Media" },
    { id: "media_android", prefix: "iiMediaAndroid", label: "Android Media", icon: "play_circle", gloss: "音楽", category: "Media" },
    { id: "media_cd", prefix: "iiMediaCd", label: "CD Media 1x1", icon: "album", gloss: "音楽", category: "Media" },
    { id: "nothing_ring_media", prefix: "iiNothingRingMedia", label: "Nothing Ring Media 1x1", icon: "graphic_eq", gloss: "音楽", category: "Media" },
    { id: "weather_default", prefix: "iiWeatherDefault", label: "Default Weather", icon: "cloud", gloss: "天気", category: "Weather" },
    { id: "weather_expressive", prefix: "iiWeatherExpressive", label: "Expressive Weather", icon: "sunny", gloss: "天気", category: "Weather" },
    { id: "weather_forecast", prefix: "iiWeatherForecast", label: "Forecast Weather 2x1", icon: "partly_cloudy_day", gloss: "天気", category: "Weather" },
    { id: "weather_card", prefix: "iiWeatherCard", label: "Weather Card 1x1", icon: "cloud", gloss: "天気", category: "Weather" },
    { id: "weather_icon", prefix: "iiWeatherIcon", label: "Weather Icon Shape", icon: "sunny", gloss: "天気", category: "Weather" },
    { id: "weather_pill", prefix: "iiWeatherPill", label: "Weather Pill 1x0.5", icon: "cloud", gloss: "天気", category: "Weather" },
    { id: "weather_circle", prefix: "iiWeatherCircle", label: "Weather Circle Cookie", icon: "sunny", gloss: "天気", category: "Weather" },
    { id: "nothing_weather_circle", prefix: "iiNothingWeatherCircle", label: "Nothing Weather Circle", icon: "cloud", gloss: "天気", category: "Weather" },
    { id: "volume_mute_pill", prefix: "iiVolumeMutePill", label: "Volume Mute Pill 1x0.5", icon: "volume_off", gloss: "状態", category: "System" },
    { id: "wifi_pill", prefix: "iiWifiPill", label: "Wi-Fi Pill 1x0.5", icon: "wifi", gloss: "状態", category: "System" },
    { id: "bluetooth_pill", prefix: "iiBluetoothPill", label: "Bluetooth Pill 1x0.5", icon: "bluetooth", gloss: "状態", category: "System" },
    { id: "mic_pill", prefix: "iiMicPill", label: "Microphone Pill 1x0.5", icon: "mic", gloss: "状態", category: "System" },
    { id: "dark_mode_pill", prefix: "iiDarkModePill", label: "Dark Mode Pill 1x0.5", icon: "dark_mode", gloss: "状態", category: "System" },
    { id: "screen_record_pill", prefix: "iiScreenRecordPill", label: "Screen Record Pill 1x0.5", icon: "videocam", gloss: "状態", category: "System" },
    { id: "easy_effects_pill", prefix: "iiEasyEffectsPill", label: "EasyEffects Pill 1x0.5", icon: "graphic_eq", gloss: "状態", category: "System" },
    { id: "easyeffects_preset_portrait", prefix: "iiEasyeffectsPresetPortrait", label: "EasyEffects Preset (portrait)", icon: "graphic_eq", gloss: "状態", category: "System" },
    { id: "easyeffects_preset_landscape", prefix: "iiEasyeffectsPresetLandscape", label: "EasyEffects Preset (landscape)", icon: "graphic_eq", gloss: "状態", category: "System" },
    { id: "weather_typography", prefix: "iiWeatherTypography", label: "Weather Typography", icon: "cloud", gloss: "天気", category: "Weather" },
    { id: "weather_hourly", prefix: "iiWeatherHourly", label: "Weather Hourly 2x1", icon: "sunny", gloss: "天気", category: "Weather" },
    { id: "date_default", prefix: "iiDateDefault", label: "Date Card", icon: "calendar_today", gloss: "日付", category: "Date" },
    { id: "calendar_minimal", prefix: "iiCalendarMinimal", label: "Calendar Minimal 1x1", icon: "calendar_month", gloss: "日付", category: "Date" },
    { id: "calendar_grid", prefix: "iiCalendarGrid", label: "Calendar Month Grid 2x1", icon: "calendar_month", gloss: "日付", category: "Date" },
    { id: "calendar_agenda", prefix: "iiCalendarAgenda", label: "Calendar Agenda 1x1", icon: "event", gloss: "日付", category: "Date" },
    { id: "calendar_next_event", prefix: "iiCalendarNextEvent", label: "Calendar Next Event 2x1", icon: "event", gloss: "日付", category: "Date" },
    { id: "calendar_pill", prefix: "iiCalendarPill", label: "Calendar Pill 1x0.5", icon: "calendar_today", gloss: "日付", category: "Date" },
    { id: "calendar_upcoming_3days", prefix: "iiCalendarUpcoming3days", label: "Calendar Upcoming 3 Days 1x1", icon: "calendar_view_day", gloss: "日付", category: "Date" },
    { id: "photo", prefix: "iiPhoto", label: "Photo", icon: "image", gloss: "写真", category: "Photo" },
    { id: "photo_1x1", prefix: "iiPhoto1x1", label: "Photo 1x1", icon: "image", gloss: "写真", category: "Photo" },
    { id: "photo_weather_2x1", prefix: "iiPhotoWeather2x1", label: "Photo Weather (2x1)", icon: "image", gloss: "写真", category: "Photo" },
    { id: "photo_pill_2x1", prefix: "iiPhotoPill2x1", label: "Photo Pill Badge (2x1)", icon: "image", gloss: "写真", category: "Photo" },
    { id: "photo_minimal_temp_2x1", prefix: "iiPhotoMinimalTemp2x1", label: "Photo Minimal Temp (2x1)", icon: "image", gloss: "写真", category: "Photo" },
    { id: "bluetooth_battery", prefix: "iiBluetoothBattery", label: "Bluetooth Device Battery", icon: "earbuds", gloss: "電池", category: "Devices" },
    { id: "bluetooth_headphone", prefix: "iiBluetoothHeadphone", label: "Bluetooth Headphone 1x2", icon: "headphones", gloss: "電池", category: "Devices" },
    { id: "mobile_battery", prefix: "iiMobileBattery", label: "Mobile Phone Battery", icon: "smartphone", gloss: "電池", category: "Devices" },
    { id: "bluetooth_headphone_cookie", prefix: "iiBluetoothHeadphoneCookie", label: "Bluetooth Headphone Cookie", icon: "headphones", gloss: "電池", category: "Devices" },
    { id: "bluetooth_fill_cards", prefix: "iiBluetoothFillCards", label: "Bluetooth Fill Cards", icon: "bluetooth", gloss: "電池", category: "Devices" },
    { id: "pc_battery_bars", prefix: "iiPcBatteryBars", label: "PC Battery Bars", icon: "battery_charging_full", gloss: "電池", category: "Devices" },
    { id: "pc_battery_cable", prefix: "iiPcBatteryCable", label: "PC Battery Cable", icon: "power", gloss: "電池", category: "Devices" },
    { id: "devices_battery_list", prefix: "iiDevicesBatteryList", label: "Connected Devices Battery List (2x1)", icon: "battery_full", gloss: "電池", category: "Devices" },
    { id: "devices_battery_list_1x1", prefix: "iiDevicesBatteryList1x1", label: "Connected Devices Battery List (1x1)", icon: "battery_full", gloss: "電池", category: "Devices" },
    { id: "bluetooth_earbuds_stem", prefix: "iiBluetoothEarbudsStem", label: "Bluetooth Earbuds Stem", icon: "earbuds", gloss: "電池", category: "Devices" },
    { id: "email_inbox", prefix: "iiEmailInbox", label: "Email Inbox (1x1)", icon: "mail", gloss: "道具", category: "Utility" },
    { id: "email_inbox_2x1", prefix: "iiEmailInbox2x1", label: "Email Inbox (2x1)", icon: "mail", gloss: "道具", category: "Utility" },
    { id: "ai_chat", prefix: "iiAiChat", label: "AI Chat", icon: "auto_awesome", gloss: "道具", category: "Utility" },
    { id: "notes_widget", prefix: "iiNotesWidget", label: "Notes (1x1)", icon: "note_stack", gloss: "道具", category: "Utility" },
    { id: "notes_widget_2x1", prefix: "iiNotesWidget2x1", label: "Notes (2x1)", icon: "note_stack", gloss: "道具", category: "Utility" },
    { id: "compact_media", prefix: "iiCompactMedia", label: "Compact Media (2x1)", icon: "graphic_eq", gloss: "音楽", category: "Media" },
    { id: "quick_actions", prefix: "iiQuickActions", label: "Quick Actions", icon: "widgets", gloss: "道具", category: "Utility" },
    { id: "android_search_bar", prefix: "iiAndroidSearchBar", label: "Android Search Bar", icon: "search", gloss: "道具", category: "Utility" },
    { id: "search_pill", prefix: "iiSearchPill", label: "Search Pill", icon: "auto_awesome", gloss: "道具", category: "Utility" },
    { id: "quote", prefix: "iiQuote", label: "Quote", icon: "format_quote", gloss: "道具", category: "Utility" },
    { id: "water_reminder", prefix: "iiWaterReminder", label: "Water Reminder", icon: "water_drop", gloss: "道具", category: "Utility" },
    { id: "at_a_glance", prefix: "iiAtAGlance", label: "At a Glance", icon: "dashboard", gloss: "道具", category: "Utility" },
    { id: "resource_cpu_pill", prefix: "iiResourceCpuPill", label: "CPU Resource Pill", icon: "memory", gloss: "計測", category: "Resources" },
    { id: "resource_ram_pill", prefix: "iiResourceRamPill", label: "RAM Resource Pill", icon: "memory_alt", gloss: "計測", category: "Resources" },
    { id: "resource_disk_pill", prefix: "iiResourceDiskPill", label: "Disk Resource Pill", icon: "hard_drive", gloss: "計測", category: "Resources" },
    { id: "resource_fill_cards", prefix: "iiResourceFillCards", label: "Resource Fill Cards", icon: "donut_large", gloss: "計測", category: "Resources" },
    { id: "resource_nothing_disk", prefix: "iiResourceNothingDisk", label: "Nothing Storage Widget", icon: "hard_drive", gloss: "計測", category: "Resources" },
    { id: "resource_nothing_cpu", prefix: "iiResourceNothingCpu", label: "Nothing CPU Widget", icon: "memory", gloss: "計測", category: "Resources" },
    { id: "resource_nothing_ram", prefix: "iiResourceNothingRam", label: "Nothing RAM Widget", icon: "memory_alt", gloss: "計測", category: "Resources" },
];

function byPrefix(prefix) {
    for (var i = 0; i < faces.length; i++)
        if (faces[i].prefix === prefix)
            return faces[i];
    return null;
}

function byId(id) {
    for (var i = 0; i < faces.length; i++)
        if (faces[i].id === id)
            return faces[i];
    return null;
}

function isIi(prefix) {
    return byPrefix(prefix) !== null;
}
