package main

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	weatherTTL       = 30 * time.Minute
	weatherReachTTL  = 60 * time.Second
	openMeteoGeoHost = "https://geocoding-api.open-meteo.com/v1/search"
	openMeteoForHost = "https://api.open-meteo.com/v1/forecast"
	weatherUA        = "ryogami-wallpaper"
)

func init() {
	registerAvailability("weather", func(*daemon) bool { return weatherReachable() })
}

var weatherClient = &http.Client{Timeout: 8 * time.Second}

var (
	weatherMu   sync.Mutex
	weatherTags []string
	weatherAt   time.Time
	weatherKey  string
)

// Never touches the network, so schedule.get cannot block on a forecast fetch.
func currentWeatherCached() []string {
	weatherMu.Lock()
	defer weatherMu.Unlock()
	return append([]string(nil), weatherTags...)
}

func (d *daemon) currentWeather() []string {
	lat := parseCoord(d.settingString("schedule.latitude"))
	lon := parseCoord(d.settingString("schedule.longitude"))
	locale := strings.TrimSpace(d.settingString("general.locale"))
	key := locale + "|" + d.settingString("schedule.latitude") + "|" + d.settingString("schedule.longitude")

	weatherMu.Lock()
	if weatherTags != nil && weatherKey == key && time.Since(weatherAt) < weatherTTL {
		tags := append([]string(nil), weatherTags...)
		weatherMu.Unlock()
		return tags
	}
	weatherMu.Unlock()

	// A city name wins when set; otherwise the schedule coordinates.
	if locale != "" {
		gl, glo, ok := geocodeCity(locale)
		if !ok {
			return nil
		}
		lat, lon = gl, glo
	} else if lat == 0 && lon == 0 {
		return nil
	}

	code, wind, ok := fetchForecast(lat, lon)
	if !ok {
		return nil
	}
	tags := mapWeatherCode(code, wind)

	weatherMu.Lock()
	weatherTags = tags
	weatherAt = time.Now()
	weatherKey = key
	weatherMu.Unlock()
	return append([]string(nil), tags...)
}

func geocodeCity(name string) (float64, float64, bool) {
	q := url.Values{}
	q.Set("name", name)
	q.Set("count", "1")
	body, ok := weatherGet(openMeteoGeoHost + "?" + q.Encode())
	if !ok {
		return 0, 0, false
	}
	var parsed struct {
		Results []struct {
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
		} `json:"results"`
	}
	if json.Unmarshal(body, &parsed) != nil || len(parsed.Results) == 0 {
		return 0, 0, false
	}
	return parsed.Results[0].Latitude, parsed.Results[0].Longitude, true
}

func fetchForecast(lat, lon float64) (int, float64, bool) {
	q := url.Values{}
	q.Set("latitude", strconv.FormatFloat(lat, 'f', 4, 64))
	q.Set("longitude", strconv.FormatFloat(lon, 'f', 4, 64))
	q.Set("current", "weather_code,wind_speed_10m")
	body, ok := weatherGet(openMeteoForHost + "?" + q.Encode())
	if !ok {
		return 0, 0, false
	}
	var parsed struct {
		Current struct {
			WeatherCode int     `json:"weather_code"`
			WindSpeed   float64 `json:"wind_speed_10m"`
		} `json:"current"`
	}
	if json.Unmarshal(body, &parsed) != nil {
		return 0, 0, false
	}
	return parsed.Current.WeatherCode, parsed.Current.WindSpeed, true
}

func weatherGet(rawURL string) ([]byte, bool) {
	req, err := http.NewRequest(http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, false
	}
	req.Header.Set("User-Agent", weatherUA)
	resp, err := weatherClient.Do(req)
	if err != nil {
		return nil, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, false
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, false
	}
	return body, true
}

func mapWeatherCode(code int, windKmh float64) []string {
	var tags []string
	switch {
	case code == 0:
		tags = []string{"clear", "sunny"}
	case code == 1:
		tags = []string{"clear"}
	case code == 2 || code == 3:
		tags = []string{"cloudy"}
	case code == 45 || code == 48:
		tags = []string{"foggy"}
	case (code >= 51 && code <= 67) || (code >= 80 && code <= 82):
		tags = []string{"rainy"}
	case (code >= 71 && code <= 77) || code == 85 || code == 86:
		tags = []string{"snowy"}
	case code >= 95 && code <= 99:
		tags = []string{"stormy"}
	default:
		tags = []string{"clear"}
	}
	if windKmh >= 30.0 {
		tags = append(tags, "windy")
	}
	return tags
}

var (
	reachMu   sync.Mutex
	reachOK   bool
	reachAt   time.Time
	reachDone bool
)

// The availability cache calls this off the schema path. The extra minute cache
// avoids opening a new probe socket on every background refresh.
func weatherReachable() bool {
	reachMu.Lock()
	if reachDone && time.Since(reachAt) < weatherReachTTL {
		ok := reachOK
		reachMu.Unlock()
		return ok
	}
	reachMu.Unlock()

	conn, err := net.DialTimeout("tcp", "api.open-meteo.com:443", 2*time.Second)
	ok := err == nil
	if conn != nil {
		conn.Close()
	}

	reachMu.Lock()
	reachOK = ok
	reachAt = time.Now()
	reachDone = true
	reachMu.Unlock()
	return ok
}
