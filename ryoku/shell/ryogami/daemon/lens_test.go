package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

func writeTestIndex(t *testing.T, path, model string, fp uint64, dims int, entries [][2]interface{}) {
	t.Helper()
	var b bytes.Buffer
	b.WriteString(indexMagic)
	le32 := func(v uint32) {
		var x [4]byte
		binary.LittleEndian.PutUint32(x[:], v)
		b.Write(x[:])
	}
	le64 := func(v uint64) {
		var x [8]byte
		binary.LittleEndian.PutUint64(x[:], v)
		b.Write(x[:])
	}
	le32(uint32(dims))
	le32(uint32(len(model)))
	b.WriteString(model)
	le64(fp)
	le64(uint64(len(entries)))
	for _, e := range entries {
		key := e[0].(string)
		le32(uint32(len(key)))
		b.WriteString(key)
		le64(e[1].(uint64))
		for range dims {
			le32(0)
		}
	}
	if err := os.WriteFile(path, b.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path+".fingerprint", []byte("12345"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestCacheIndexName(t *testing.T) {
	// Exact values cross-checked against skwd-lens-proto's cache_index_name.
	if got := cacheIndexName("a", "b"); got != "index-e57da31903de37b1.sidx" {
		t.Fatalf("a|b: got %s", got)
	}
	if got := cacheIndexName("siglip2@1.0.0-beta.23", "full"); got != "index-4b5928b2aaf784c6.sidx" {
		t.Fatalf("siglip full: got %s", got)
	}
	shape := regexp.MustCompile(`^index-[0-9a-f]{16}\.sidx$`)
	if !shape.MatchString(cacheIndexName("m@1", "multiview")) {
		t.Fatal("name shape")
	}
	if cacheIndexName("m@1", "full") == cacheIndexName("m@1", "multiview") {
		t.Fatal("profile must change the name")
	}
	if cacheIndexName("m@1", "full") == cacheIndexName("m@2", "full") {
		t.Fatal("model must change the name")
	}
}

func TestEntryFingerprint(t *testing.T) {
	a := entryFingerprint("/no/such/thumb.webp", 10, "full")
	if a != entryFingerprint("/no/such/thumb.webp", 10, "full") {
		t.Fatal("fingerprint must be stable for identical inputs")
	}
	if a == entryFingerprint("/no/such/thumb.webp", 10, "center") {
		t.Fatal("view must change the fingerprint")
	}
	if a == entryFingerprint("/no/such/thumb.webp", 11, "full") {
		t.Fatal("mtime must change the fingerprint")
	}
	if a == entryFingerprint("/other/thumb.webp", 10, "full") {
		t.Fatal("path must change the fingerprint")
	}
}

func TestLensEligible(t *testing.T) {
	if !lensEligible(Entry{Name: "a", Thumb: "/t.webp"}) {
		t.Fatal("named + thumbed row is eligible")
	}
	if lensEligible(Entry{Name: "a", Thumb: ""}) {
		t.Fatal("no thumbnail is ineligible")
	}
	if lensEligible(Entry{Name: "/", Thumb: "/t.webp"}) {
		t.Fatal("empty name is ineligible")
	}
}

func catalogDaemon(t *testing.T) *daemon {
	t.Helper()
	return &daemon{store: openStore(t.TempDir())}
}

func TestCatalogRequestFull(t *testing.T) {
	d := catalogDaemon(t)
	d.store.replaceAll(map[string]Entry{
		"wide":    {Key: "wide", Name: "wide", Type: "static", Thumb: "/t/wide.webp", Mtime: 1, Width: 3840, Height: 1080},
		"normal":  {Key: "normal", Name: "normal", Type: "static", Thumb: "/t/n.webp", Mtime: 2, Width: 1920, Height: 1080},
		"clip":    {Key: "clip", Name: "clip", Type: "video", Thumb: "/t/c.webp", Mtime: 3, Width: 3840, Height: 1080},
		"nothumb": {Key: "nothumb", Name: "nothumb", Type: "static", Thumb: "", Mtime: 4},
	})
	req := d.catalogRequest(false)
	if len(req.Entries) != 3 {
		t.Fatalf("full: want 3 eligible entries, got %d", len(req.Entries))
	}
	for _, e := range req.Entries {
		if e.View != "full" {
			t.Fatalf("full profile emits only full views, got %q", e.View)
		}
	}
}

func TestCatalogRequestMultiview(t *testing.T) {
	d := catalogDaemon(t)
	d.store.replaceAll(map[string]Entry{
		"wide":   {Key: "wide", Name: "wide", Type: "static", Thumb: "/t/wide.webp", Mtime: 1, Width: 3840, Height: 1080},
		"normal": {Key: "normal", Name: "normal", Type: "static", Thumb: "/t/n.webp", Mtime: 2, Width: 1920, Height: 1080},
		"clip":   {Key: "clip", Name: "clip", Type: "video", Thumb: "/t/c.webp", Mtime: 3, Width: 3840, Height: 1080},
	})
	req := d.catalogRequest(true)
	views := map[string][]string{}
	for _, e := range req.Entries {
		views[e.Key] = append(views[e.Key], e.View)
	}
	if got := len(views["wide"]); got != 4 {
		t.Fatalf("ultrawide static: want 4 views, got %d (%v)", got, views["wide"])
	}
	if got := len(views["normal"]); got != 2 {
		t.Fatalf("normal static: want 2 views, got %d (%v)", got, views["normal"])
	}
	if got := len(views["clip"]); got != 2 {
		t.Fatalf("video: want 2 views, got %d (%v)", got, views["clip"])
	}
}

func TestCatalogFingerprintTracksChanges(t *testing.T) {
	d := catalogDaemon(t)
	base := map[string]Entry{
		"a": {Key: "a", Name: "a", Type: "static", Thumb: "/t/a.webp", Mtime: 1, Width: 1920, Height: 1080},
	}
	d.store.replaceAll(base)
	first := d.catalogRequest(false).Fingerprint
	if first != d.catalogRequest(false).Fingerprint {
		t.Fatal("fingerprint must be stable for an unchanged catalog")
	}
	if first == d.catalogRequest(true).Fingerprint {
		t.Fatal("profile must change the catalog fingerprint")
	}
	d.store.replaceAll(map[string]Entry{
		"a": {Key: "a", Name: "a", Type: "static", Thumb: "/t/a.webp", Mtime: 99, Width: 1920, Height: 1080},
	})
	if first == d.catalogRequest(false).Fingerprint {
		t.Fatal("a changed catalog must change the fingerprint")
	}
}

func TestIndexReaderAndCurrency(t *testing.T) {
	dir := t.TempDir()
	idx := filepath.Join(dir, "index.sidx")
	writeTestIndex(t, idx, "m@1", 12345, 4, [][2]interface{}{
		{"a", uint64(11)}, {"a", uint64(12)}, {"b", uint64(13)},
	})

	f, err := os.Open(idx)
	if err != nil {
		t.Fatal(err)
	}
	r := bufio.NewReader(f)
	h, err := readIndexHeader(r)
	f.Close()
	if err != nil || h.model != "m@1" || h.count != 3 || h.dimensions != 4 {
		t.Fatalf("header: %+v err=%v", h, err)
	}
	if got := indexUniqueKeys(idx); got != 2 {
		t.Fatalf("unique keys: want 2, got %d", got)
	}

	manifest := filepath.Join(dir, "semantic-pack.json")
	if err := os.WriteFile(manifest, []byte(`{"id":"m","version":"1"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	paths := semanticPaths{manifest: manifest, index: idx}
	if !indexModelMatches(paths) {
		t.Fatal("index built for m@1 must match manifest m@1")
	}
	if !indexCurrent(paths, 12345) {
		t.Fatal("matching fingerprint + model is current")
	}
	if indexCurrent(paths, 999) {
		t.Fatal("a different fingerprint is not current")
	}

	if err := os.WriteFile(manifest, []byte(`{"id":"m","version":"2"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if indexModelMatches(paths) {
		t.Fatal("index for m@1 must not match manifest m@2")
	}
}

func TestReadIndexHeaderRejectsGarbage(t *testing.T) {
	dir := t.TempDir()
	bad := filepath.Join(dir, "bad.sidx")
	if err := os.WriteFile(bad, []byte("NOTMAGIC and more"), 0o644); err != nil {
		t.Fatal(err)
	}
	f, _ := os.Open(bad)
	defer f.Close()
	if _, err := readIndexHeader(bufio.NewReader(f)); err != errNotIndex {
		t.Fatalf("want errNotIndex, got %v", err)
	}
	if indexUniqueKeys(bad) != 0 {
		t.Fatal("garbage yields zero indexed keys")
	}
}

func TestManagedPackComponentContainment(t *testing.T) {
	base := t.TempDir()
	models := filepath.Join(base, "models")
	comp := filepath.Join(models, "mypack")
	if err := os.MkdirAll(comp, 0o755); err != nil {
		t.Fatal(err)
	}
	inside := filepath.Join(comp, "semantic-pack.json")
	if err := os.WriteFile(inside, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := managedPackComponent(models, inside)
	if err != nil || got != "mypack" {
		t.Fatalf("inside model library: got %q err=%v", got, err)
	}

	rogue := filepath.Join(base, "rogue")
	if err := os.MkdirAll(rogue, 0o755); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(rogue, "semantic-pack.json")
	if err := os.WriteFile(outside, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := managedPackComponent(models, outside); err == nil {
		t.Fatal("a manifest outside the model library must be refused")
	}
	if _, err := managedPackComponent(models, filepath.Join(comp, "other.json")); err == nil {
		t.Fatal("only semantic-pack.json may be removed")
	}
}

func TestActionIndex(t *testing.T) {
	if i, ok := actionIndex(map[string]interface{}{"index": float64(3)}); !ok || i != 3 {
		t.Fatalf("float index: %d %v", i, ok)
	}
	if _, ok := actionIndex(map[string]interface{}{}); ok {
		t.Fatal("missing index reports not-ok")
	}
}
