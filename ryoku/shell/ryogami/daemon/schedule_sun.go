package main

import "math"

// Computed locally so sun events work offline, using the NOAA sunrise-equation approximation.

// ok is false when the sun never crosses the horizon that day (polar day or night).
func sunTimesUTCMin(dayOfYear int, latitude, longitude float64) (sunrise, sunset float64, ok bool) {
	rise, okRise := solarEventUTCMin(dayOfYear, latitude, longitude, true)
	if !okRise {
		return 0, 0, false
	}
	set, okSet := solarEventUTCMin(dayOfYear, latitude, longitude, false)
	if !okSet {
		return 0, 0, false
	}
	return rise, set, true
}

func solarEventUTCMin(dayOfYear int, latitude, longitude float64, rising bool) (float64, bool) {
	// 90.833 deg: the geometric zenith plus refraction and the solar disc.
	const zenith = 90.833
	longitudeHour := longitude / 15.0
	base := 18.0
	if rising {
		base = 6.0
	}
	days := float64(dayOfYear) + (base-longitudeHour)/24.0
	anomaly := 0.9856*days - 3.289
	sunLongitude := normalizeDegrees(anomaly +
		1.916*math.Sin(radians(anomaly)) +
		0.020*math.Sin(radians(2*anomaly)) +
		282.634)
	rightAscension := normalizeDegrees(degrees(math.Atan(math.Tan(radians(sunLongitude)))))
	// Put the right ascension in the same quadrant as the ecliptic longitude.
	longitudeQuadrant := math.Floor(sunLongitude/90.0) * 90.0
	ascensionQuadrant := math.Floor(rightAscension/90.0) * 90.0
	rightAscension = (rightAscension + (longitudeQuadrant - ascensionQuadrant)) / 15.0
	sinDeclination := 0.39782 * math.Sin(radians(sunLongitude))
	cosDeclination := math.Cos(math.Asin(sinDeclination))
	cosHourAngle := (math.Cos(radians(zenith)) - sinDeclination*math.Sin(radians(latitude))) /
		(cosDeclination * math.Cos(radians(latitude)))
	if cosHourAngle < -1.0 || cosHourAngle > 1.0 {
		return 0, false
	}
	var hourAngle float64
	if rising {
		hourAngle = (360.0 - degrees(math.Acos(cosHourAngle))) / 15.0
	} else {
		hourAngle = degrees(math.Acos(cosHourAngle)) / 15.0
	}
	localMeanTime := hourAngle + rightAscension - 0.06571*days - 6.622
	utcHours := euclidMod(localMeanTime-longitudeHour, 24.0)
	return utcHours * 60.0, true
}

func normalizeDegrees(d float64) float64 { return euclidMod(d, 360.0) }

// Go's math.Mod keeps the dividend's sign, which would put a pre-dawn event on the wrong day.
func euclidMod(value, modulus float64) float64 {
	r := math.Mod(value, modulus)
	if r < 0 {
		r += modulus
	}
	return r
}

func radians(d float64) float64 { return d * math.Pi / 180.0 }
func degrees(r float64) float64 { return r * 180.0 / math.Pi }
