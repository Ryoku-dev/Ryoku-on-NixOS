package main

import "testing"

func TestBuildTags(t *testing.T) {
	cases := []struct {
		name   string
		file   string
		bucket int
		want   string
	}{
		{"folders+colour", "Nature/Ocean/sky.png", 7, "Nature,Ocean,blue"},
		{"provider from filename", "wallhaven-abc123.jpg", 99, "wallhaven,gray"},
		{"colour dedupes against folder", "blue/x.png", 7, "blue"},
		{"non-provider prefix stays a filename", "nature-blue.png", 4, "green"},
		{"root file is just its colour", "sky.png", 0, "red"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := buildTags(scanned{name: c.file, src: "/w/" + c.file}, c.bucket)
			if got != c.want {
				t.Fatalf("buildTags(%q, %d) = %q, want %q", c.file, c.bucket, got, c.want)
			}
		})
	}
}

func TestProviderFromName(t *testing.T) {
	cases := map[string]string{
		"wallhaven-abc.png":     "wallhaven",
		"nested/youtube-xy.mp4": "youtube",
		"nature-blue.png":       "",
		"noseparator.png":       "",
		"-leadingdash.png":      "",
		"moewalls-1234.webm":    "moewalls",
	}
	for in, want := range cases {
		if got := providerFromName(in); got != want {
			t.Errorf("providerFromName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestHueBucketName(t *testing.T) {
	if hueBucketName(7) != "blue" || hueBucketName(99) != "gray" {
		t.Fatal("hue bucket names drifted from the wheel")
	}
	if hueBucketName(42) != "" {
		t.Fatal("an out-of-range bucket must not invent a colour")
	}
}
