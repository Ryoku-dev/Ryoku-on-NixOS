pragma Singleton

import Quickshell
import QtQuick
import stage.modules.common

// Google Weather Icons - Set 4 (Filled, 48x48 SVGs)
// Source: https://github.com/mrdarrengriffin/google-weather-icons
// Maps WWO weather codes to SVG icon file paths with day/night and light/dark theme support.

Singleton {
    id: root

    // ─── Base paths ──────────────────────────────────────────────────────
    readonly property string _lightBase: Qt.resolvedUrl("../../assets/icons/google-weather/light")
    readonly property string _darkBase: Qt.resolvedUrl("../../assets/icons/google-weather/dark")

    // ─── WWO code → condition mapping ────────────────────────────────────
    // Maps WWO weather code (string) to a condition key from the _conditionFiles map.
    // Used as the primary lookup for getWeatherIcon().
    readonly property var _wwoToCondition: ({
        "113": "clear",
        "116": "partly_cloudy",
        "119": "mostly_cloudy",
        "122": "cloudy",
        "143": "haze_fog_dust_smoke",
        "176": "scattered_showers",
        "179": "flurries",
        "182": "mixed_rain_hail_sleet",
        "185": "haze_fog_dust_smoke",
        "200": "isolated_thunderstorms",
        "227": "blowing_snow",
        "230": "blizzard",
        "248": "haze_fog_dust_smoke",
        "260": "haze_fog_dust_smoke",
        "263": "drizzle",
        "266": "drizzle",
        "281": "showers_rain",
        "284": "icy",
        "293": "showers_rain",
        "296": "showers_rain",
        "299": "heavy_rain",
        "302": "heavy_rain",
        "305": "heavy_rain",
        "308": "heavy_rain",
        "311": "icy",
        "314": "icy",
        "317": "sleet_hail",
        "320": "sleet_hail",
        "323": "flurries",
        "326": "flurries",
        "329": "showers_snow",
        "332": "showers_snow",
        "335": "heavy_snow",
        "338": "heavy_snow",
        "350": "sleet_hail",
        "353": "scattered_showers",
        "356": "heavy_rain",
        "359": "heavy_rain",
        "362": "sleet_hail",
        "365": "sleet_hail",
        "368": "showers_snow",
        "371": "heavy_snow",
        "374": "sleet_hail",
        "377": "sleet_hail",
        "386": "isolated_scattered_thunderstorms",
        "389": "strong_thunderstorms",
        "392": "flurries",
        "395": "heavy_snow"
    })

    // ─── Condition → filename mapping ────────────────────────────────────
    // Maps condition keys to filenames. Conditions with day/night variants
    // use { day: ..., night: ... } structure; others use { default: ... }.
    readonly property var _conditionFiles: ({
        "clear":                                { day: "clear_day.svg", night: "clear_night.svg" },
        "partly_cloudy":                        { day: "partly_cloudy_day.svg", night: "partly_cloudy_night.svg" },
        "mostly_cloudy":                        { day: "mostly_cloudy_day.svg", night: "mostly_cloudy_night.svg" },
        "cloudy":                               { default: "cloudy.svg" },
        "haze_fog_dust_smoke":                  { default: "haze_fog_dust_smoke.svg" },
        "scattered_showers":                    { day: "scattered_showers_day.svg", night: "scattered_showers_night.svg" },
        "drizzle":                              { default: "drizzle.svg" },
        "showers_rain":                         { default: "showers_rain.svg" },
        "heavy_rain":                           { default: "heavy_rain.svg" },
        "flurries":                             { default: "flurries.svg" },
        "showers_snow":                         { default: "showers_snow.svg" },
        "heavy_snow":                           { default: "heavy_snow.svg" },
        "mixed_rain_snow":                      { default: "mixed_rain_snow.svg" },
        "mixed_rain_hail_sleet":                { default: "mixed_rain_hail_sleet.svg" },
        "sleet_hail":                           { default: "sleet_hail.svg" },
        "isolated_thunderstorms":               { default: "isolated_thunderstorms.svg" },
        "isolated_scattered_thunderstorms":     { day: "isolated_scattered_thunderstorms_day.svg", night: "isolated_scattered_thunderstorms_night.svg" },
        "strong_thunderstorms":                 { default: "strong_thunderstorms.svg" },
        "icy":                                  { default: "icy.svg" },
        "blowing_snow":                         { default: "blowing_snow.svg" },
        "blizzard":                             { default: "blizzard.svg" },
        "tornado":                              { default: "tornado.svg" },
        "tropical_storm_hurricane":             { default: "tropical_storm_hurricane.svg" },
        "windy":                                { default: "windy.svg" },
        "very_hot":                             { default: "very_hot.svg" },
        "very_cold":                            { default: "very_cold.svg" },
        "umbrella":                             { default: "umbrella.svg" }
    })

    // ─── Conditions that have day/night variants ─────────────────────────
    readonly property var _hasDayNight: [
        "clear", "partly_cloudy", "mostly_cloudy",
        "scattered_showers", "isolated_scattered_thunderstorms"
    ]

    // ─── Public API ──────────────────────────────────────────────────────

    // Returns the filename (e.g. "clear_day.svg") for a given WWO code.
    function getFilename(code, isNight: bool): string {
        var key = String(code)
        if (!_wwoToCondition.hasOwnProperty(key)) {
            return "cloudy.svg"
        }
        var condition = _wwoToCondition[key]
        var fileMap = _conditionFiles[condition]
        if (!fileMap) return "cloudy.svg"

        if (_hasDayNight.indexOf(condition) >= 0) {
            return isNight ? (fileMap.night || fileMap.day) : fileMap.day
        }
        return fileMap.default
    }

    // Returns the full resolved URL to the SVG file for a given WWO code.
    // Automatically selects light/dark theme icons based on Appearance.m3colors.darkmode.
    function getWeatherIcon(code, isNight: bool): url {
        var filename = getFilename(code, isNight)
        var base = Appearance.m3colors.darkmode ? _darkBase : _lightBase
        // If the icon doesn't exist in the current theme, fall back to the other theme
        if (Appearance.m3colors.darkmode && !_darkHasFile(filename)) {
            base = _lightBase
        }
        return Qt.resolvedUrl(base + "/" + filename)
    }

    // Check if a dark-theme icon file exists (dark set has fewer files).
    // Dark set covers: clear_night, cloudy, drizzle, heavy_rain, heavy_snow, flurries,
    //                   icy, hurricane, blizzard, blowing_snow, sleet_hail, thunderstorms,
    //                   strong_thunderstorms, tornado, windy, partly_cloudy, mostly_sunny,
    //                   and the Japanese regional variants.
    readonly property var _darkFiles: [
        "clear_night.svg", "cloudy.svg", "cloudy_with_rain.svg", "cloudy_with_snow.svg",
        "cloudy_with_sunny.svg", "drizzle.svg", "flurries.svg", "heavy_rain.svg",
        "heavy_snow.svg", "hurricane.svg", "icy.svg", "blizzard.svg", "blowing_snow.svg",
        "mostly_sunny.svg", "partly_cloudy.svg", "rain_with_cloudy.svg", "rain_with_snow.svg",
        "rain_with_sunny.svg", "sleet_hail.svg", "snow_with_cloudy.svg", "snow_with_rain.svg",
        "snow_with_sunny.svg", "strong_thunderstorms.svg", "sunny.svg", "sunny_with_cloudy.svg",
        "sunny_with_rain.svg", "sunny_with_snow.svg", "thunderstorms.svg", "tornado.svg", "windy.svg"
    ]

    function _darkHasFile(filename: string): bool {
        return _darkFiles.indexOf(filename) >= 0
    }

    // ─── Convenience: backward-compatible Material Symbol fallback ───────
    // Returns the Material Symbol name for a given WWO code (same as old Icons.getWeatherIcon).
    // Kept for backward compatibility during transition.
    readonly property var _materialFallback: ({
        "113": "clear_day",
        "116": "partly_cloudy_day",
        "119": "cloud",
        "122": "cloud",
        "143": "foggy",
        "176": "rainy",
        "179": "rainy",
        "182": "rainy",
        "185": "rainy",
        "200": "thunderstorm",
        "227": "cloudy_snowing",
        "230": "snowing_heavy",
        "248": "foggy",
        "260": "foggy",
        "263": "rainy",
        "266": "rainy",
        "281": "rainy",
        "284": "rainy",
        "293": "rainy",
        "296": "rainy",
        "299": "rainy",
        "302": "weather_hail",
        "305": "rainy",
        "308": "weather_hail",
        "311": "rainy",
        "314": "rainy",
        "317": "rainy",
        "320": "cloudy_snowing",
        "323": "cloudy_snowing",
        "326": "cloudy_snowing",
        "329": "snowing_heavy",
        "332": "snowing_heavy",
        "335": "snowing",
        "338": "snowing_heavy",
        "350": "rainy",
        "353": "rainy",
        "356": "rainy",
        "359": "weather_hail",
        "362": "rainy",
        "365": "rainy",
        "368": "cloudy_snowing",
        "371": "snowing",
        "374": "rainy",
        "377": "rainy",
        "386": "thunderstorm",
        "389": "thunderstorm",
        "392": "thunderstorm",
        "395": "snowing"
    })

    function getMaterialSymbol(code): string {
        var key = String(code)
        if (_materialFallback.hasOwnProperty(key)) {
            return _materialFallback[key]
        }
        return "cloud"
    }
}
