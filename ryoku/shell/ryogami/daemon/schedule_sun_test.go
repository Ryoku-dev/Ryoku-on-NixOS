package main

import (
	"math"
	"testing"
)

func TestSunTimesAlmanac(t *testing.T) {
	cases := []struct {
		doy               int
		lat, lon          float64
		wantRise, wantSet float64
		label             string
	}{
		{172, 51.5, -0.13, 223.14, 1221.40, "london midsummer"},
		{355, 40.7, -74.0, 736.68, 1291.85, "nyc winter"},
		{1, 0.0, 0.0, 356.16, 1083.47, "equator new year"},
	}
	for _, c := range cases {
		rise, set, ok := sunTimesUTCMin(c.doy, c.lat, c.lon)
		if !ok {
			t.Fatalf("%s: expected a sun crossing", c.label)
		}
		if math.Abs(rise-c.wantRise) > 3 {
			t.Errorf("%s sunrise: got %.2f want %.2f", c.label, rise, c.wantRise)
		}
		if math.Abs(set-c.wantSet) > 3 {
			t.Errorf("%s sunset: got %.2f want %.2f", c.label, set, c.wantSet)
		}
	}
}

func TestSunTimesPolarNight(t *testing.T) {
	if _, _, ok := sunTimesUTCMin(355, 80.0, 20.0); ok {
		t.Fatal("high arctic in deep winter should report no sun crossing")
	}
}

func TestUTCToLocalMinWrap(t *testing.T) {
	// 23:40 UTC at +02:00 wraps to 01:40 local.
	if got := utcToLocalMin(23*60+40, 2*3600); got != 100 {
		t.Fatalf("wrap forward: got %d want 100", got)
	}
	// 00:30 UTC at -02:00 wraps back to 22:30 local.
	if got := utcToLocalMin(30, -2*3600); got != 22*60+30 {
		t.Fatalf("wrap back: got %d want %d", got, 22*60+30)
	}
}
