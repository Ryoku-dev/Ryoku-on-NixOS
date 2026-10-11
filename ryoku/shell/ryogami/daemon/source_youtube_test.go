package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestYoutubeMissingToolUsesHostAdvice(t *testing.T) {
	bin := t.TempDir()
	host := filepath.Join(bin, "ryoku-host")
	if err := os.WriteFile(host, []byte("#!/bin/sh\n[ \"$1 $2 $3\" = 'pkg advice yt-dlp' ] || exit 2\nprintf 'sudo xbps-install -S yt-dlp\\n'\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)
	got := youtubeMissingTool("browse")
	if !strings.Contains(got, "sudo xbps-install -S yt-dlp") || strings.Contains(got, "pacman") {
		t.Fatalf("missing-tool advice = %q", got)
	}
}

const ytFixture = `{"id":"vid00000001","title":"Nice 4k","duration":120,"channel":"Chan","thumbnails":[{"url":"https://i.ytimg.com/vi/vid00000001/hq.jpg","width":480,"height":360},{"url":"https://i.ytimg.com/vi/vid00000001/max.jpg","width":1280,"height":720}]}
{"id":"livestream1","title":"Live","live_status":"is_live"}
{"id":"bad id!!","title":"Bad"}
{"id":"vid00000002","title":"Long","duration":100000}`

func TestParseYoutubeSearch(t *testing.T) {
	page := parseYoutubeSearch(ytFixture, 1, 24, 0)
	if len(page.results) != 2 {
		t.Fatalf("results = %d, want 2 (live + bad id dropped)", len(page.results))
	}
	r := page.results[0]
	if r.id != "vid00000001" || r.fullURL != "https://www.youtube.com/watch?v=vid00000001" {
		t.Errorf("id/full wrong: %+v", r)
	}
	if r.thumbURL != "https://i.ytimg.com/vi/vid00000001/max.jpg" {
		t.Errorf("best thumbnail not chosen: %q", r.thumbURL)
	}
	if r.resolution != "2:00" || r.durationSecs != 120 || r.attribution != "Chan" {
		t.Errorf("fields wrong: %+v", r)
	}
}

func TestParseYoutubeDurationFilter(t *testing.T) {
	page := parseYoutubeSearch(ytFixture, 1, 24, 200)
	if len(page.results) != 1 || page.results[0].id != "vid00000001" {
		t.Errorf("duration filter kept %d results: %+v", len(page.results), page.results)
	}
}

func TestParseYoutubePagination(t *testing.T) {
	page := parseYoutubeSearch(ytFixture, 1, 1, 0)
	if len(page.results) != 1 || page.lastPage != 2 || page.currentPage != 1 {
		t.Errorf("page1: %d results, page %d/%d", len(page.results), page.currentPage, page.lastPage)
	}
	page = parseYoutubeSearch(ytFixture, 2, 1, 0)
	if len(page.results) != 1 || page.lastPage != 2 {
		t.Errorf("page2: %d results, lastPage %d", len(page.results), page.lastPage)
	}
}

func TestYoutubeSafeID(t *testing.T) {
	good := []string{"abcABC-_123", "dQw4w9WgXcQ"}
	for _, id := range good {
		if !youtubeSafeID(id) {
			t.Errorf("%q should be safe", id)
		}
	}
	bad := []string{"", "a b", "abc!!", strings.Repeat("x", 25)}
	for _, id := range bad {
		if youtubeSafeID(id) {
			t.Errorf("%q should be unsafe", id)
		}
	}
}

func TestFmtDuration(t *testing.T) {
	if fmtDuration(90) != "1:30" {
		t.Errorf("90s = %q", fmtDuration(90))
	}
	if fmtDuration(3661) != "1:01:01" {
		t.Errorf("3661s = %q", fmtDuration(3661))
	}
}

func TestYtExtractPercentAndPhases(t *testing.T) {
	if p, ok := ytExtractPercent("[download]  45.0% of 10.00MiB"); !ok || p < 0.44 || p > 0.46 {
		t.Errorf("extractPercent = %v %v", p, ok)
	}
	if _, ok := ytExtractPercent("[info] not a percent"); ok {
		t.Error("non-download line should not yield a percent")
	}
	ph := &ytPhases{}
	if _, ok := noteLine(ph, "[download] Destination: video.f137.mp4"); ok || ph.seen != 1 {
		t.Errorf("destination should bump phase, seen=%d", ph.seen)
	}
	if v, ok := noteLine(ph, "[download]  50.0% of 1MiB"); !ok || v < 0.44 || v > 0.46 {
		t.Errorf("video phase overall = %v", v)
	}
	noteLine(ph, "[download] Destination: video.f140.m4a")
	if v, ok := noteLine(ph, "[download] 100.0% of 1MiB"); !ok || v < 0.97 || v > 0.99 {
		t.Errorf("audio phase overall = %v", v)
	}
	if v, ok := noteLine(ph, "[Merger] Merging formats into \"out.mp4\""); !ok || v != 0.98 || !ph.merging {
		t.Errorf("merger should report 0.98, got %v", v)
	}
}

func TestClipProgress(t *testing.T) {
	if _, ok := clipProgress("frame=1 time=00:00:30.00 bitrate=1", 0); ok {
		t.Error("no clip duration should yield no progress")
	}
	v, ok := clipProgress("frame=1 fps=1 q=1 size=1kB time=00:00:30.00 bitrate=1", 60)
	if !ok || v < 0.49 || v > 0.51 {
		t.Errorf("clip progress = %v %v", v, ok)
	}
}

func TestYoutubeDownloadArgs(t *testing.T) {
	full := youtubeDownloadArgs("vid1", "/vids", 2160, 0, 0)
	joined := strings.Join(full, " ")
	if !strings.Contains(joined, "/vids/youtube-vid1.%(ext)s") {
		t.Errorf("output template missing: %v", full)
	}
	if strings.Contains(joined, "--download-sections") {
		t.Error("no clip should not request sections")
	}
	clip := youtubeDownloadArgs("vid1", "/vids", 1080, 30, 60)
	cj := strings.Join(clip, " ")
	if !strings.Contains(cj, "--download-sections *0:00:30-0:01:30") {
		t.Errorf("clip sections wrong: %v", clip)
	}
	if !strings.Contains(cj, "height<=?1080") {
		t.Errorf("max height missing: %v", clip)
	}
}
