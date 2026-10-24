package main

import (
	"strings"
	"testing"
)

func TestParseWallhavenSearch(t *testing.T) {
	body := `{"data":[{"id":"abc123","path":"https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg","resolution":"3840x2160","file_size":1234567,"purity":"sfw","category":"general","thumbs":{"small":"https://th.wallhaven.cc/small/ab/abc123.jpg","large":"https://th.wallhaven.cc/lg/ab/abc123.jpg"}}],"meta":{"current_page":2,"last_page":14,"per_page":24,"total":319}}`
	page, err := parseWallhavenSearch(body)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.results) != 1 {
		t.Fatalf("results = %d", len(page.results))
	}
	r := page.results[0]
	if r.id != "abc123" || r.fullURL != "https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg" {
		t.Errorf("id/full wrong: %+v", r)
	}
	if r.thumbURL != "https://th.wallhaven.cc/lg/ab/abc123.jpg" {
		t.Errorf("thumb = %q", r.thumbURL)
	}
	if r.resolution != "3840x2160" || r.fileSize != 1234567 || r.purity != "sfw" || r.category != "general" {
		t.Errorf("fields wrong: %+v", r)
	}
	if page.lastPage != 14 || page.currentPage != 2 {
		t.Errorf("pagination = %d/%d", page.currentPage, page.lastPage)
	}
}

func TestParseWallhavenError(t *testing.T) {
	if _, err := parseWallhavenSearch(`{"error":"Not Found"}`); err == nil {
		t.Error("expected wallhaven error to surface")
	}
}

func TestWithinMax(t *testing.T) {
	if !withinMax("1920x1080", "3840x2160") {
		t.Error("1080p should be within 4k")
	}
	if withinMax("3840x2160", "1920x1080") {
		t.Error("4k should exceed 1080p")
	}
	if !withinMax("garbage", "1920x1080") {
		t.Error("unparsable resolution should be kept")
	}
	if !withinMax("1920x1080", "") {
		t.Error("empty bound should keep everything")
	}
}

func TestParseWallhavenCollections(t *testing.T) {
	cols, err := parseWallhavenCollections(`{"data":[{"id":42,"label":"Favs","count":7}]}`)
	if err != nil {
		t.Fatal(err)
	}
	if len(cols) != 1 || cols[0]["id"].(uint64) != 42 || cols[0]["label"] != "Favs" {
		t.Errorf("collections = %+v", cols)
	}
}

func TestParseUnsplashSearch(t *testing.T) {
	body := `{"total_pages":5,"results":[{"id":"u1","width":3840,"height":2160,"urls":{"full":"https://images.unsplash.com/full1","small":"https://images.unsplash.com/small1"},"links":{"download_location":"https://api.unsplash.com/photos/u1/download"},"user":{"name":"Jane Doe","links":{"html":"https://unsplash.com/@jane"}}}]}`
	page, err := parseUnsplashSearch(body, 3)
	if err != nil {
		t.Fatal(err)
	}
	r := page.results[0]
	if r.id != "u1" || r.fullURL != "https://images.unsplash.com/full1" || r.thumbURL != "https://images.unsplash.com/small1" {
		t.Errorf("urls wrong: %+v", r)
	}
	if r.trackURL != "https://api.unsplash.com/photos/u1/download" {
		t.Errorf("trackURL = %q", r.trackURL)
	}
	if r.attribution != "Photo by Jane Doe on Unsplash" || !strings.Contains(r.attributionURL, "utm_source=ryogami") {
		t.Errorf("attribution wrong: %q / %q", r.attribution, r.attributionURL)
	}
	if page.lastPage != 5 || page.currentPage != 3 {
		t.Errorf("pagination = %d/%d", page.currentPage, page.lastPage)
	}
}

func TestParseUnsplashError(t *testing.T) {
	if _, err := parseUnsplashSearch(`{"errors":["OAuth error"]}`, 1); err == nil {
		t.Error("expected unsplash error to surface")
	}
}

func TestParsePexelsSearchPagination(t *testing.T) {
	body := `{"total_results":100,"photos":[{"id":42,"width":1920,"height":1080,"url":"https://www.pexels.com/photo/42/","photographer":"Sam","photographer_url":"https://www.pexels.com/@sam","src":{"original":"https://images.pexels.com/photos/42/orig.jpg","large":"https://images.pexels.com/photos/42/large.jpg"},"alt":"A view"}]}`
	page, err := parsePexelsSearch(body, 1, 30)
	if err != nil {
		t.Fatal(err)
	}
	r := page.results[0]
	if r.id != "42" || r.fullURL != "https://images.pexels.com/photos/42/orig.jpg" || r.thumbURL != "https://images.pexels.com/photos/42/large.jpg" {
		t.Errorf("urls wrong: %+v", r)
	}
	if r.resolution != "1920x1080" || r.title != "A view" || r.attribution != "Photo by Sam on Pexels" {
		t.Errorf("fields wrong: %+v", r)
	}
	if page.lastPage != 4 { // ceil(100/30)
		t.Errorf("lastPage = %d, want 4", page.lastPage)
	}
}

func TestParsePexelsNextPageFallback(t *testing.T) {
	withNext := `{"photos":[],"next_page":"https://api.pexels.com/v1/search?page=3"}`
	page, _ := parsePexelsSearch(withNext, 2, 30)
	if page.lastPage != 3 {
		t.Errorf("with next_page lastPage = %d, want 3", page.lastPage)
	}
	noNext := `{"photos":[]}`
	page, _ = parsePexelsSearch(noNext, 2, 30)
	if page.lastPage != 2 {
		t.Errorf("without next_page lastPage = %d, want 2", page.lastPage)
	}
}

func TestPexelsColor(t *testing.T) {
	if pexelsColor("red") != "red" {
		t.Error("named color dropped")
	}
	if pexelsColor("#a1b2c3") != "#a1b2c3" {
		t.Error("hex color dropped")
	}
	if pexelsColor("chartreuse") != "" {
		t.Error("unknown color kept")
	}
	if pexelsColor("#xyzxyz") != "" {
		t.Error("bad hex kept")
	}
}

func TestParseBingSearch(t *testing.T) {
	body := `{"images":[{"urlbase":"/th?id=OHR.Example_EN-US1234","startdate":"20260927","copyright":"A place (Someone)","copyrightlink":"https://www.bing.com/search?q=place","title":"A place"}]}`
	page, err := parseBingSearch(body)
	if err != nil {
		t.Fatal(err)
	}
	r := page.results[0]
	if r.id != "OHR.Example_EN-US1234" {
		t.Errorf("id = %q", r.id)
	}
	if r.fullURL != "https://www.bing.com/th?id=OHR.Example_EN-US1234_UHD.jpg" {
		t.Errorf("full = %q", r.fullURL)
	}
	if r.thumbURL != "https://www.bing.com/th?id=OHR.Example_EN-US1234_400x240.jpg" {
		t.Errorf("thumb = %q", r.thumbURL)
	}
	if r.resolution != "3840x2160" || r.title != "A place" || r.attribution != "A place (Someone)" {
		t.Errorf("fields wrong: %+v", r)
	}
	if page.lastPage != 1 {
		t.Errorf("bing is a single page, got lastPage %d", page.lastPage)
	}
}
