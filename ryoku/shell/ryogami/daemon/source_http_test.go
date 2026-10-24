package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestHostAllowlist(t *testing.T) {
	allow := []struct{ source, url string }{
		{"wallhaven", "https://wallhaven.cc/api/v1/search"},
		{"wallhaven", "https://w.wallhaven.cc/full/x/wallhaven-1.jpg"},
		{"wallhaven", "https://whvn.cc/abc"},
		{"unsplash", "https://images.unsplash.com/photo-1"},
		{"unsplash", "https://api.unsplash.com/photos/x/download"},
		{"pexels", "https://images.pexels.com/photos/1/x.jpg"},
		{"youtube", "https://i.ytimg.com/vi/abc/maxresdefault.jpg"},
		{"youtube", "https://yt3.ggpht.com/x"},
		{"bing", "https://www.bing.com/th?id=x"},
		{"steam", "https://cdn.steamstatic.com/x.jpg"},
		{"steam", "https://images.steamusercontent.com/x"},
		{"steam", "https://steamcdn-a.akamaihd.net/x"},
		{"moewalls", "https://moewalls.com/x"},
		{"moewalls", "https://go.moewalls.com/download.php?video=t"},
		{"moewalls", "https://wsrv.nl/?url=x"},
		{"motionbgs", "https://motionbgs.com/dl/4k/1/"},
		{"ryostore", "https://raw.githubusercontent.com/ryoku-dev/ryostore/main/x.mp4"},
		{"repos", "https://api.github.com/repos/o/r"},
		{"repos", "https://media.githubusercontent.com/media/o/r/main/x.mp4"},
	}
	for _, c := range allow {
		if err := requireSource(c.source, c.url); err != nil {
			t.Errorf("expected %s to allow %s, got %v", c.source, c.url, err)
		}
	}

	deny := []struct{ source, url string }{
		{"wallhaven", "https://evil.com/x.jpg"},
		{"wallhaven", "https://wallhaven.cc.evil.com/x"},
		{"unsplash", "https://pexels.com/x"},
		{"pexels", "https://unsplash.com/x"},
		{"youtube", "https://youtube.com/watch"},
		{"bing", "https://bong.com/x"},
		{"steam", "https://steam.com/x"},
		{"moewalls", "https://motionbgs.com/x"},
		{"motionbgs", "https://moewalls.com/x"},
		{"ryostore", "https://example.com/x"},
	}
	for _, c := range deny {
		if err := requireSource(c.source, c.url); err == nil {
			t.Errorf("expected %s to block %s", c.source, c.url)
		}
	}
}

func TestRequirePublicBlocksPrivate(t *testing.T) {
	blocked := []string{
		"http://127.0.0.1/x",
		"http://10.0.0.5/x",
		"http://192.168.1.2/x",
		"http://169.254.1.1/x",
		"http://[::1]/x",
		"ftp://wallhaven.cc/x",
	}
	for _, u := range blocked {
		if err := requirePublic(u); err == nil {
			t.Errorf("expected %s to be blocked", u)
		}
	}
	if err := requirePublic("https://wallhaven.cc/api"); err != nil {
		t.Errorf("public host wrongly blocked: %v", err)
	}
}

func TestExtFromURL(t *testing.T) {
	cases := map[string]string{
		"https://x/a.jpg":                "jpg",
		"https://x/a.PNG?q=1":            "PNG",
		"https://x/a.webm#frag":          "webm",
		"https://x/noext":                "jpg",
		"https://x/weird.superlongext":   "jpg",
		"https://x/dir/name.mp4?a=b&c=d": "mp4",
	}
	for in, want := range cases {
		if got := extFromURL(in); got != want {
			t.Errorf("extFromURL(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSafeSeg(t *testing.T) {
	if got := safeSeg("a/b\\c"); got != "a_b_c" {
		t.Errorf("safeSeg = %q", got)
	}
}

func TestSniffDetect(t *testing.T) {
	cases := []struct {
		head []byte
		want sniffKind
	}{
		{[]byte{0xFF, 0xD8, 0xFF, 0xE0}, sniffImage},
		{[]byte{0x89, 'P', 'N', 'G', 0, 0, 0, 0}, sniffImage},
		{[]byte("GIF89a....."), sniffImage},
		{append([]byte("RIFF0000"), []byte("WEBP")...), sniffImage},
		{append([]byte("0000"), []byte("ftypavif")...), sniffImage},
		{append([]byte("0000"), []byte("ftypmp42")...), sniffVideo},
		{[]byte{0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0}, sniffVideo},
		{[]byte("<html><body>"), sniffUnknown},
		{[]byte("{\"error\":1}"), sniffUnknown},
	}
	for _, c := range cases {
		if got := detectKind(c.head); got != c.want {
			t.Errorf("detectKind(%q) = %v, want %v", c.head, got, c.want)
		}
	}
}

func TestCheckFileRejectsMismatch(t *testing.T) {
	dir := t.TempDir()
	html := filepath.Join(dir, "page.jpg")
	if err := os.WriteFile(html, []byte("<html>not an image</html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := checkFile(html, sniffImage); err == nil {
		t.Error("expected checkFile to reject an HTML page saved as .jpg")
	}
	png := filepath.Join(dir, "real.png")
	if err := os.WriteFile(png, []byte{0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0, 0, 0, 0, 0}, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := checkFile(png, sniffImage); err != nil {
		t.Errorf("expected checkFile to accept a real PNG: %v", err)
	}
}

func TestPartialFileAndCopyBounded(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "wallhaven-1.jpg")
	f, part, err := partialFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(part, ".part") || filepath.Dir(part) != dir {
		t.Errorf("partial file %q not a .part beside dest", part)
	}
	if _, err := copyBounded(strings.NewReader("hello"), f, 1024); err != nil {
		t.Fatal(err)
	}
	f.Close()
	if _, err := os.Stat(dest); err == nil {
		t.Error("dest should not exist before rename")
	}
	os.Rename(part, dest)
	if b, _ := os.ReadFile(dest); string(b) != "hello" {
		t.Errorf("dest content = %q", b)
	}
}

func TestCopyBoundedRejectsOverflow(t *testing.T) {
	var sink strings.Builder
	if _, err := copyBounded(strings.NewReader("0123456789"), &sink, 4); err == nil {
		t.Error("expected copyBounded to reject a body over the cap")
	}
}
