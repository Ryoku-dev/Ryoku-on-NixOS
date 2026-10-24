package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func mustRule(t *testing.T, s string) scheduleRule {
	t.Helper()
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(s), &m); err != nil {
		t.Fatalf("bad rule json: %v", err)
	}
	r, ok := parseScheduleRule(m)
	if !ok {
		t.Fatalf("rule rejected: %s", s)
	}
	return r
}

func at(minute, sunrise, sunset int) *scheduleNow {
	return &scheduleNow{year: 2026, month: 3, day: 1, wday: 0, minute: minute, sunrise: sunrise, sunset: sunset}
}

func TestScheduleDayNightWindows(t *testing.T) {
	day := mustRule(t, `{"name":"Day","priority":100,"target":{"type":"folder","value":"/d"},
		"condition":{"op":"all","children":[{"block":"timewindow","from":"sunrise","to":"sunset"}]}}`)
	night := mustRule(t, `{"name":"Night","priority":100,"target":{"type":"folder","value":"/n"},
		"condition":{"op":"all","children":[{"block":"timewindow","from":"sunset","to":"sunrise"}]}}`)
	if day.set != "folder:/d" || night.set != "folder:/n" {
		t.Fatalf("folder targets flattened wrong: %q %q", day.set, night.set)
	}
	rules := []scheduleRule{day, night}
	if scheduleWinner(rules, at(12*60, 360, 1080)) != 0 {
		t.Error("midday should pick the day rule")
	}
	if scheduleWinner(rules, at(23*60, 360, 1080)) != 1 {
		t.Error("late night should pick the night rule")
	}
}

func TestSchedulePriorityAndSpecificity(t *testing.T) {
	def := mustRule(t, `{"name":"default","priority":100,"target":{"type":"random"},"condition":{"op":"all","children":[]}}`)
	cozy := mustRule(t, `{"name":"cozy","priority":20,"target":{"type":"random"},"condition":{"op":"all","children":[
		{"block":"weekday","days":["sun"]},{"block":"weather","tags":["cloudy"]},
		{"block":"timecmp","op":">=","at":"20:00"}]}}`)
	rules := []scheduleRule{def, cozy}
	now := &scheduleNow{year: 2026, month: 3, day: 1, wday: 0, minute: 21 * 60, sunrise: 360, sunset: 1080, weather: []string{"cloudy"}}
	if scheduleWinner(rules, now) != 1 {
		t.Error("lower-priority-number cozy rule should win a full match")
	}
	now.wday = 1
	if scheduleWinner(rules, now) != 0 {
		t.Error("default should win when cozy no longer matches")
	}

	broad := mustRule(t, `{"name":"feb","priority":20,"target":{"type":"random"},
		"condition":{"op":"all","children":[{"block":"date","value":"02-01..02-28"}]}}`)
	narrow := mustRule(t, `{"name":"feb-eve","priority":20,"target":{"type":"random"},
		"condition":{"op":"all","children":[{"block":"date","value":"02-01..02-28"},{"block":"timecmp","op":">=","at":"18:00"}]}}`)
	rs := []scheduleRule{broad, narrow}
	if scheduleWinner(rs, &scheduleNow{year: 2026, month: 2, day: 14, minute: 20 * 60, sunrise: 360, sunset: 1080}) != 1 {
		t.Error("equal priority: the more specific rule should win in its window")
	}
	if scheduleWinner(rs, &scheduleNow{year: 2026, month: 2, day: 14, minute: 12 * 60, sunrise: 360, sunset: 1080}) != 0 {
		t.Error("equal priority: the broad rule should win outside the specific window")
	}
}

func TestScheduleNestedGroupsAndNegation(t *testing.T) {
	r := mustRule(t, `{"name":"weekend","priority":10,"target":{"type":"random"},"condition":{"op":"all","children":[
		{"block":"weekday","days":["sat","sun"]},
		{"op":"any","children":[
			{"block":"weather","tags":["rainy"]},
			{"block":"timecmp","op":">=","at":"sunset"},
			{"block":"weather","negated":true,"tags":["stormy"]}]}]}}`)
	rules := []scheduleRule{r}
	sat := func(min int, w ...string) *scheduleNow {
		return &scheduleNow{year: 2026, month: 8, day: 15, wday: 6, minute: min, sunrise: 360, sunset: 1080, weather: w}
	}
	if scheduleWinner(rules, sat(720, "rainy")) != 0 {
		t.Error("rainy saturday should match the any-group")
	}
	if scheduleWinner(rules, sat(1200, "stormy")) != 0 {
		t.Error("post-sunset saturday should match via the time clause")
	}
	if scheduleWinner(rules, sat(720, "stormy")) != -1 {
		t.Error("stormy midday saturday should fail every any-branch")
	}
	if scheduleWinner(rules, &scheduleNow{year: 2026, month: 8, day: 17, wday: 1, minute: 1200, sunrise: 360, sunset: 1080}) != -1 {
		t.Error("a weekday should not match a weekend rule")
	}
}

func TestScheduleSolarOffsetAndBoundaryWait(t *testing.T) {
	r := mustRule(t, `{"name":"golden","priority":10,"target":{"type":"random"},
		"condition":{"op":"all","children":[{"block":"timewindow","from":"sunset-30","to":"sunset+30"}]}}`)
	rules := []scheduleRule{r}
	if scheduleWinner(rules, at(1060, 360, 1080)) != 0 {
		t.Error("inside the golden window (1050..1110) should match")
	}
	if scheduleWinner(rules, at(1120, 360, 1080)) != -1 {
		t.Error("past the golden window should not match")
	}
	if w := scheduleNextBoundaryWait(rules, 900, 360, 1080); w != 150 {
		t.Errorf("next boundary from 900 should be 150 (to 1050), got %d", w)
	}
}

func TestScheduleWeatherCapsBoundary(t *testing.T) {
	r := mustRule(t, `{"name":"w","priority":10,"target":{"type":"random"},
		"condition":{"op":"all","children":[{"block":"weather","tags":["rainy"]}]}}`)
	if w := scheduleNextBoundaryWait([]scheduleRule{r}, 100, 360, 1080); w != 60 {
		t.Errorf("a weather rule should cap the recheck at 60 min, got %d", w)
	}
}

func TestSchedulePowerBatteryFailClosed(t *testing.T) {
	r := mustRule(t, `{"name":"docked","priority":10,"target":{"type":"random"},"condition":{"op":"all","children":[
		{"block":"power","source":"external"},{"block":"battery","op":">=","value":80},
		{"block":"outputcount","op":">=","value":2},{"block":"output","value":"DP-1"}]}}`)
	rules := []scheduleRule{r}
	external, pct := false, 90
	docked := &scheduleNow{minute: 600, sunrise: 360, sunset: 1080, onBattery: &external, batteryPercent: &pct, outputs: []string{"DP-1", "HDMI-A-1"}}
	if scheduleWinner(rules, docked) != 0 {
		t.Error("external power, 90%, 2 outputs incl DP-1 should match")
	}
	unknownBattery := &scheduleNow{minute: 600, sunrise: 360, sunset: 1080, onBattery: &external, outputs: []string{"DP-1", "HDMI-A-1"}}
	if scheduleWinner(rules, unknownBattery) != -1 {
		t.Error("an unknown battery level must fail the battery clause closed")
	}
}

func TestScheduleDateWrapNewYear(t *testing.T) {
	winter := dateRange{start: dateSpec{month: 12, day: 15}, end: dateSpec{month: 1, day: 5}}
	if !dateInRange(winter, 2026, 12, 20) {
		t.Error("Dec 20 falls in a 12-15..01-05 recurring range")
	}
	if !dateInRange(winter, 2027, 1, 3) {
		t.Error("Jan 3 falls in a 12-15..01-05 recurring range")
	}
	if dateInRange(winter, 2026, 6, 1) {
		t.Error("Jun 1 is outside the winter range")
	}
}

func TestScheduleTargetAndFilters(t *testing.T) {
	r := mustRule(t, `{"name":"r","priority":5,"theme":"dark",
		"target":{"type":"random","filters":{"types":["video"],"favouritesOnly":true}},
		"condition":{"op":"all","children":[]}}`)
	if r.mode != "dark" {
		t.Errorf("theme dark should map to mode dark, got %q", r.mode)
	}
	if len(r.randomTypes) != 1 || r.randomTypes[0] != "video" || r.randomFav == nil || !*r.randomFav {
		t.Errorf("random filters not parsed: types=%v fav=%v", r.randomTypes, r.randomFav)
	}
	pl := mustRule(t, `{"name":"p","priority":5,"target":{"type":"playlist","value":"7"},"condition":{"op":"all","children":[]}}`)
	if pl.set != "playlist:7" {
		t.Errorf("playlist target flattened wrong: %q", pl.set)
	}
	we := mustRule(t, `{"name":"w","priority":5,"target":{"type":"wallpaper","value":"we:123"},"condition":{"op":"all","children":[]}}`)
	if we.set != "we:123" {
		t.Errorf("wallpaper target passes value verbatim, got %q", we.set)
	}
}

func TestScheduleRejectsBadRules(t *testing.T) {
	var m map[string]interface{}
	_ = json.Unmarshal([]byte(`{"name":"x","enabled":false,"target":{"type":"random"},"condition":{"op":"all","children":[]}}`), &m)
	if _, ok := parseScheduleRule(m); ok {
		t.Error("a disabled rule must be dropped")
	}
	_ = json.Unmarshal([]byte(`{"name":"y","target":{"type":"folder","value":""},"condition":{"op":"all","children":[]}}`), &m)
	if _, ok := parseScheduleRule(m); ok {
		t.Error("an empty folder target must be dropped")
	}
}

func TestListFolderMediaTypeFilter(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"a.png", "b.mp4", "c.txt", "d.jpg"} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	all := listFolderMedia(dir, nil)
	if len(all) != 3 {
		t.Fatalf("expected 3 media files (png,mp4,jpg), got %v", all)
	}
	vids := listFolderMedia(dir, []string{"video"})
	if len(vids) != 1 || filepath.Base(vids[0]) != "b.mp4" {
		t.Fatalf("video-only filter should keep just b.mp4, got %v", vids)
	}
	imgs := listFolderMedia(dir, []string{"static"})
	if len(imgs) != 2 {
		t.Fatalf("static-only filter should keep 2 images, got %v", imgs)
	}
}
