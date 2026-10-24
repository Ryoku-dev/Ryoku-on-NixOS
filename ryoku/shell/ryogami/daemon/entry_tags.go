package main

import (
	"path"
	"strings"
)

func buildTags(it scanned, hueBucket int) string {
	var tags []string
	seen := map[string]bool{}
	add := func(t string) {
		t = strings.TrimSpace(t)
		if t == "" {
			return
		}
		key := strings.ToLower(t)
		if seen[key] {
			return
		}
		seen[key] = true
		tags = append(tags, t)
	}

	if dir := path.Dir(it.name); dir != "." && dir != "/" && dir != "" {
		for _, seg := range strings.Split(dir, "/") {
			add(seg)
		}
	}
	add(providerFromName(it.name))
	add(hueBucketName(hueBucket))
	return strings.Join(tags, ",")
}

// Only these prefixes count, so a hand-named file never gains a bogus provider tag.
var downloadProviders = map[string]bool{
	"wallhaven": true, "unsplash": true, "pexels": true, "bing": true,
	"youtube": true, "moewalls": true, "motionbgs": true,
	"ryostore": true, "repos": true,
}

func providerFromName(name string) string {
	base := name
	if i := strings.LastIndex(base, "/"); i >= 0 {
		base = base[i+1:]
	}
	i := strings.Index(base, "-")
	if i <= 0 {
		return ""
	}
	if prov := strings.ToLower(base[:i]); downloadProviders[prov] {
		return prov
	}
	return ""
}

// Indexed like scan.go's hueToBucketIdx wheel; 99 is desaturated.
var hueBucketNames = map[int]string{
	0: "red", 1: "orange", 2: "yellow", 3: "lime", 4: "green", 5: "teal",
	6: "cyan", 7: "blue", 8: "indigo", 9: "purple", 10: "magenta", 11: "pink",
	99: "gray",
}

func hueBucketName(bucket int) string { return hueBucketNames[bucket] }
