package main

import (
	"reflect"
	"testing"
)

func TestMapWeatherCode(t *testing.T) {
	cases := []struct {
		code int
		wind float64
		want []string
	}{
		{0, 0, []string{"clear", "sunny"}},
		{1, 0, []string{"clear"}},
		{3, 0, []string{"cloudy"}},
		{48, 0, []string{"foggy"}},
		{61, 0, []string{"rainy"}},
		{82, 0, []string{"rainy"}},
		{73, 0, []string{"snowy"}},
		{96, 0, []string{"stormy"}},
		{999, 0, []string{"clear"}},
	}
	for _, c := range cases {
		if got := mapWeatherCode(c.code, c.wind); !reflect.DeepEqual(got, c.want) {
			t.Errorf("code %d: got %v want %v", c.code, got, c.want)
		}
	}
}

func TestMapWeatherCodeWind(t *testing.T) {
	got := mapWeatherCode(0, 35.0)
	if !reflect.DeepEqual(got, []string{"clear", "sunny", "windy"}) {
		t.Fatalf("high wind should add windy: %v", got)
	}
	if got := mapWeatherCode(0, 29.9); reflect.DeepEqual(got, []string{"clear", "sunny", "windy"}) {
		t.Fatalf("sub-threshold wind must not add windy: %v", got)
	}
}
