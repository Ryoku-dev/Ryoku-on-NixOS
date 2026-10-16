pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import shell.services as RWeather

// Reference-shaped weather data backed only by Ryoku's weather topic. The
// daemon owns fetching, location, retries, formatting and persistence; Stage
// and adopted ii surfaces share this adapter instead of starting another
// network client.
Singleton {
    id: root

    readonly property var current: RWeather.Weather.current
    readonly property var hourly: RWeather.Weather.hourly
    readonly property var daily: RWeather.Weather.daily
    readonly property var moon: RWeather.Weather.moon
    readonly property var air: RWeather.Weather.air
    readonly property string status: RWeather.Weather.status
    readonly property string errorText: RWeather.Weather.errorText
    readonly property string locationName: RWeather.Weather.location
    readonly property string updatedAt: RWeather.Weather.updatedAt
    readonly property bool available: RWeather.Weather.available
    readonly property int fetchInterval: 15 * 60 * 1000
    readonly property string city: String(RWeather.Config.weatherLocation ?? "")
    readonly property bool gpsActive: root.city.trim() === ""
    readonly property string resolvedCity: RWeather.Weather.city
    readonly property string activeUnit: {
        const configured = String(RWeather.Config.weatherUnit ?? "auto");
        if (configured === "celsius" || configured === "fahrenheit")
            return configured;
        return String(root.current?.temperature ?? "").includes("F")
            ? "fahrenheit" : "celsius";
    }
    readonly property bool useUSCS: root.activeUnit === "fahrenheit"
    readonly property bool forecastLoading: root.status === "loading"
    readonly property var location: ({
        "valid": root.available,
        "lat": 0,
        "lon": 0,
        "long": 0,
        "city": root.resolvedCity
    })

    signal dataRefreshed
    signal refreshFailed(string reason)

    function wmoToWwo(wmo) {
        const code = Number(wmo);
        if (code === 0 || code === 1) return 113;
        if (code === 2) return 116;
        if (code === 3) return 122;
        if (code === 45 || code === 48) return 248;
        if (code === 51 || code === 53 || code === 55) return 266;
        if (code === 56 || code === 57) return 284;
        if (code === 61 || code === 63 || code === 65) return 296;
        if (code === 66 || code === 67) return 311;
        if (code === 71 || code === 73 || code === 75 || code === 77) return 332;
        if (code === 80 || code === 81 || code === 82) return 353;
        if (code === 85 || code === 86) return 368;
        if (code === 95) return 386;
        if (code === 96 || code === 99) return 389;
        return 113;
    }

    function getWeatherDescription(code) {
        const descriptions = ({
            "113": Translation.tr("Clear"),
            "116": Translation.tr("Partly Cloudy"),
            "119": Translation.tr("Cloudy"),
            "122": Translation.tr("Overcast"),
            "143": Translation.tr("Mist"),
            "176": Translation.tr("Patchy Rain"),
            "200": Translation.tr("Thundery Outbreaks"),
            "248": Translation.tr("Fog"),
            "266": Translation.tr("Light Drizzle"),
            "284": Translation.tr("Freezing Drizzle"),
            "296": Translation.tr("Light Rain"),
            "311": Translation.tr("Freezing Rain"),
            "326": Translation.tr("Light Snow"),
            "332": Translation.tr("Moderate Snow"),
            "353": Translation.tr("Light Rain Shower"),
            "368": Translation.tr("Snow Shower"),
            "386": Translation.tr("Thunderstorm"),
            "389": Translation.tr("Heavy Rain with Thunder")
        });
        const key = String(Number(code));
        return descriptions[key] ?? Translation.tr("Unknown");
    }

    function degreesToCompass(degrees) {
        const value = Math.floor((Number(degrees) / 22.5) + 0.5);
        const points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
        return points[(value % 16 + 16) % 16];
    }

    function formatTime(value) {
        return value ? String(value) : "00:00";
    }

    readonly property var data: {
        const value = root.current;
        if (!value) {
            return {
                "uv": 0,
                "humidity": "0%",
                "sunrise": "00:00",
                "sunset": "00:00",
                "windDir": "N",
                "wCode": 113,
                "wDesc": "",
                "city": root.resolvedCity || root.city || Translation.tr("City"),
                "wind": "0 km/h",
                "precip": "0 mm",
                "visib": "0 km",
                "press": "0 hPa",
                "temp": "",
                "tempFeelsLike": "",
                "lastRefresh": root.updatedAt,
                "isDay": true
            };
        }
        const referenceCode = root.wmoToWwo(value.code);
        return {
            "uv": value.uvIndex ?? 0,
            "humidity": (value.humidity ?? 0) + "%",
            "sunrise": value.sunrise || "00:00",
            "sunset": value.sunset || "00:00",
            "windDir": value.windDir || "N",
            "wCode": referenceCode,
            "wDesc": root.getWeatherDescription(referenceCode),
            "city": root.resolvedCity || root.city || Translation.tr("City"),
            "wind": (value.wind ?? 0) + " " + (value.windUnits ?? ""),
            "precip": value.precip || (root.useUSCS ? "0 in" : "0 mm"),
            "visib": value.visibility || (root.useUSCS ? "0 mi" : "0 km"),
            "press": value.pressure || "0 hPa",
            "temp": value.temperature || "",
            "tempFeelsLike": value.feelsLike || "",
            "lastRefresh": root.updatedAt,
            "isDay": value.isDay ?? true
        };
    }

    function _toCelsius(value) {
        return root.useUSCS ? (Number(value) - 32) * 5 / 9 : Number(value);
    }

    function _toFahrenheit(value) {
        return root.useUSCS ? Number(value) : Number(value) * 9 / 5 + 32;
    }

    function _dateForOffset(offset) {
        const date = new Date(DateTime.clock.date.getTime());
        date.setDate(date.getDate() + offset);
        const month = String(date.getMonth() + 1).padStart(2, "0");
        const day = String(date.getDate()).padStart(2, "0");
        return date.getFullYear() + "-" + month + "-" + day;
    }

    readonly property var forecastData: {
        const result = [];
        const values = root.daily ?? [];
        for (let index = 0; index < values.length; index++) {
            const day = values[index];
            const maxC = root._toCelsius(day.hi);
            const minC = root._toCelsius(day.lo);
            const maxF = root._toFahrenheit(day.hi);
            const minF = root._toFahrenheit(day.lo);
            result.push({
                "date": root._dateForOffset(index),
                "maxC": Math.round(maxC),
                "minC": Math.round(minC),
                "maxF": Math.round(maxF),
                "minF": Math.round(minF),
                "code": root.wmoToWwo(day.code)
            });
        }
        return result;
    }

    readonly property var hourlyData: {
        const result = [];
        const values = root.hourly ?? [];
        for (let index = 0; index < values.length; index++) {
            const hour = Number(values[index].hour);
            if (!Number.isFinite(hour) || hour % 3 !== 0)
                continue;
            const tempC = root._toCelsius(values[index].temp);
            const tempF = root._toFahrenheit(values[index].temp);
            result.push({
                "time": String(hour * 100),
                "tempC": String(Math.round(tempC)),
                "tempF": String(Math.round(tempF)),
                "code": String(root.wmoToWwo(values[index].code))
            });
        }
        return result;
    }

    property bool manualRefreshPending: false

    function getData(force = false) {
        if (force || (!root.available && root.status !== "loading"))
            RWeather.Weather.retry();
    }

    function refresh() {
        RWeather.Weather.retry();
    }

    function retry() {
        RWeather.Weather.retry();
    }

    function refreshManually() {
        if (root.manualRefreshPending)
            return;
        root.manualRefreshPending = true;
        manualRefreshTimeout.restart();
        RWeather.Weather.retry();
    }

    function requestRefetch() {
        RWeather.Weather.retry();
    }

    function setUnit(unit) {
        RWeather.Weather.setUnit(unit);
    }

    Timer {
        id: manualRefreshTimeout
        interval: 20000
        repeat: false
        onTriggered: root.manualRefreshPending = false
    }

    Connections {
        target: RWeather.Weather

        function onFrameChanged() {
            if (root.status === "loaded") {
                root.manualRefreshPending = false;
                manualRefreshTimeout.stop();
                root.dataRefreshed();
            } else if (root.status === "error") {
                root.manualRefreshPending = false;
                manualRefreshTimeout.stop();
                root.refreshFailed(root.errorText);
            }
        }
    }
}
