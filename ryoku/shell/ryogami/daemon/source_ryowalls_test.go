package main

import (
	"strconv"
	"strings"
	"testing"
)

func TestParseMotionbgs(t *testing.T) {
	html := `<a title="Celestial Veil live wallpaper" href=/celestial-veil>` +
		`<img src=/i/c/48x48/media/8626/celestial-veil.3840x2160.jpg ` +
		`srcset="/i/c/72x72/media/8626/celestial-veil.3840x2160.jpg, /i/c/546x308/media/8626/celestial-veil.3840x2160.jpg">` +
		`<span class=ttl>Celestial Veil</span><span class=frm> 4K </span></a>` +
		`<a title="Dupe live wallpaper" href=/celestial-veil><img src=/i/c/546x308/media/8626/celestial-veil.3840x2160.jpg></a>` +
		`<a title="Spider&#039;s Web live wallpaper" href=/spider-web>` +
		`<img src=/i/c/546x308/media/543/spider-web.jpg><span class=frm> HD </span></a>`
	out := parseMotionbgs(html)
	if len(out) != 2 {
		t.Fatalf("expected 2 results (dedup by id), got %d", len(out))
	}
	// 4K card: largest thumb kept, motion-preview clip is the fullURL, 4K resolution, title from ttl.
	r := out[0]
	if r.id != "8626" {
		t.Errorf("id = %q", r.id)
	}
	if r.thumbURL != "https://motionbgs.com/i/c/546x308/media/8626/celestial-veil.3840x2160.jpg" {
		t.Errorf("thumb = %q", r.thumbURL)
	}
	if r.fullURL != "https://motionbgs.com/media/8626/celestial-veil.960x540.mp4" {
		t.Errorf("fullURL = %q", r.fullURL)
	}
	if r.resolution != "3840x2160" || r.title != "Celestial Veil" {
		t.Errorf("res/title wrong: %+v", r)
	}
	// HD-only card: 1080p resolution, title falls back to the anchor with the suffix and entity resolved.
	h := out[1]
	if h.id != "543" || h.resolution != "1920x1080" {
		t.Errorf("hd res wrong: %+v", h)
	}
	if h.fullURL != "https://motionbgs.com/media/543/spider-web.960x540.mp4" {
		t.Errorf("hd fullURL = %q", h.fullURL)
	}
	if h.title != "Spider's Web" {
		t.Errorf("hd title = %q", h.title)
	}
}

func TestMotionbgsPath(t *testing.T) {
	cases := []struct {
		query string
		page  int
		want  string
	}{
		{"", 1, "/"},
		{"", 2, "/2/"},
		{"Demon Slayer", 1, "/tag:demon-slayer/"},
		{"demon   slayer", 3, "/tag:demon-slayer/3/"},
	}
	for _, c := range cases {
		if got := motionbgsPath(c.query, c.page); got != c.want {
			t.Errorf("motionbgsPath(%q,%d) = %q, want %q", c.query, c.page, got, c.want)
		}
	}
}

func TestParseMoewalls(t *testing.T) {
	html := `<article class="post"><a title="Cool Live Wallpaper" class="g1-frame" href="https://moewalls.com/cool-post/"><img class="resolutions-1920x1080" src="https://moewalls.com/wp-content/uploads/2026/01/cool-thumb-400x225.jpg"></a></article>`
	out := parseMoewalls(html)
	if len(out) != 1 {
		t.Fatalf("expected 1 result, got %d", len(out))
	}
	r := out[0]
	if r.id != "cool" || r.title != "Cool" {
		t.Errorf("id/title wrong: %+v", r)
	}
	if r.fullURL != "https://moewalls.com/wp-content/uploads/preview/2026/cool-preview.webm" {
		t.Errorf("full = %q", r.fullURL)
	}
	if r.resolution != "1920x1080" || r.trackURL != "https://moewalls.com/cool-post/" {
		t.Errorf("res/track wrong: %+v", r)
	}
	if r.thumbURL == "" || !strings.HasPrefix(r.thumbURL, "https://wsrv.nl/?url=") {
		t.Errorf("thumb not proxied: %q", r.thumbURL)
	}
}

func TestRyowallsRegistryRows(t *testing.T) {
	reg := ryowallsRegistry{Wallpapers: []ryowallsWall{
		{ID: "w1", Name: "Sakura", Poster: "posters/w1.jpg", Video: "videos/w1.mp4", Author: "Aki", Tags: []string{"anime"}},
		{ID: "w2", Name: "Ocean", Poster: "https://cdn.example/x.jpg", Video: "https://cdn.example/x.mp4"},
	}}
	rows := ryowallsRegistryRows(reg, ryostoreBase, "", false)
	if len(rows) != 2 {
		t.Fatalf("rows = %d", len(rows))
	}
	if rows[0].thumbURL != ryostoreBase+"/posters/w1.jpg" || rows[0].fullURL != ryostoreBase+"/videos/w1.mp4" {
		t.Errorf("relative paths not absolutized: %+v", rows[0])
	}
	if rows[0].attribution != "Aki" {
		t.Errorf("author lost: %+v", rows[0])
	}
	if rows[1].fullURL != "https://cdn.example/x.mp4" {
		t.Errorf("absolute url mangled: %+v", rows[1])
	}
	filtered := ryowallsRegistryRows(reg, ryostoreBase, "ocean", false)
	if len(filtered) != 1 || filtered[0].id != "w2" {
		t.Errorf("query filter kept %d rows", len(filtered))
	}
	proxied := ryowallsRegistryRows(reg, ryostoreBase, "sakura", true)
	if len(proxied) != 1 || !strings.HasPrefix(proxied[0].thumbURL, "https://wsrv.nl/?url=") {
		t.Errorf("proxy thumb not applied: %+v", proxied)
	}
}

func makeResults(n int) []sourceResult {
	out := make([]sourceResult, n)
	for i := range out {
		out[i] = sourceResult{id: strconv.Itoa(i)}
	}
	return out
}

func TestClientPage(t *testing.T) {
	p := clientPage(makeResults(30), 1)
	if len(p.results) != 24 || p.lastPage != 2 || p.currentPage != 1 {
		t.Errorf("page1: %d results, %d/%d", len(p.results), p.currentPage, p.lastPage)
	}
	p = clientPage(makeResults(30), 2)
	if len(p.results) != 6 || p.currentPage != 2 {
		t.Errorf("page2: %d results, current %d", len(p.results), p.currentPage)
	}
	p = clientPage(nil, 1)
	if len(p.results) != 0 || p.lastPage != 1 {
		t.Errorf("empty: %d results, lastPage %d", len(p.results), p.lastPage)
	}
}

func TestServerPage(t *testing.T) {
	p := serverPage(makeResults(24), 1)
	if p.lastPage != 2 {
		t.Errorf("full page should advance lastPage, got %d", p.lastPage)
	}
	p = serverPage(nil, 3)
	if p.lastPage != 3 || len(p.results) != 0 {
		t.Errorf("empty page should stay put, got lastPage %d", p.lastPage)
	}
}

func TestRyowallsHelpers(t *testing.T) {
	if ryostoreAbs("https://b", "a/c.jpg") != "https://b/a/c.jpg" {
		t.Error("relative not joined")
	}
	if ryostoreAbs("https://b", "https://x/y") != "https://x/y" {
		t.Error("absolute mangled")
	}
	if ryostoreAbs("https://b", "/a") != "https://b/a" {
		t.Error("leading slash not handled")
	}
	if got := reposThumbProxy("https://raw.example/dir/x.jpg"); got != "https://wsrv.nl/?url=raw.example/dir/x.jpg&w=480&output=webp&q=80" {
		t.Errorf("proxy = %q", got)
	}
	if got := encPath("dir/a b.jpg"); got != "dir/a%20b.jpg" {
		t.Errorf("encPath = %q", got)
	}
}
