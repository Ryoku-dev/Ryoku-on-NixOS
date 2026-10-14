pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import shell.services as RyokuWeather

/**
 * The ii dock's weather view.
 *
 * Ryoku owns the weather engine (the daemon's `weather` topic, polled and
 * unit-converted in Go); the dock's widgets read the reference's field names,
 * so this re-exposes the daemon's current reading in that shape. The tiles
 * fall back on their own defaults while the daemon has no data yet.
 */
Singleton {
    id: root

    readonly property var data: ({
        "wCode": RyokuWeather.Weather.current ? RyokuWeather.Weather.current.code : 113,
        "temp": RyokuWeather.Weather.temp,
        "city": RyokuWeather.Weather.city,
        "wDesc": RyokuWeather.Weather.condition,
        "humidity": RyokuWeather.Weather.humidity,
        "feelsLike": RyokuWeather.Weather.feels,
        "windSpeed": RyokuWeather.Weather.wind,
        "isDay": RyokuWeather.Weather.isDay,
        "sunset": ""
    })
}
