package main

import (
	"image/color"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

// recorder captures the events emitted by an Optimizer run and closes done when
// the terminal finished event arrives.
type recorder struct {
	mu        sync.Mutex
	events    []recorded
	done      chan struct{}
	firstFile chan struct{}
	once      sync.Once
}

type recorded struct {
	event string
	data  map[string]interface{}
}

func newRecorder() *recorder {
	return &recorder{done: make(chan struct{}), firstFile: make(chan struct{}, 1)}
}

func (r *recorder) emit(event string, data map[string]interface{}) {
	r.mu.Lock()
	r.events = append(r.events, recorded{event: event, data: data})
	r.mu.Unlock()
	if p, ok := data["progress"].(int); ok && p >= 1 {
		select {
		case r.firstFile <- struct{}{}:
		default:
		}
	}
	if event == "ryogami.wall.optimize.finished" || event == "ryogami.wall.convert.finished" {
		r.once.Do(func() { close(r.done) })
	}
}

func (r *recorder) snapshot() []recorded {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]recorded, len(r.events))
	copy(out, r.events)
	return out
}

func TestOptimizeEligibilityFilter(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"a.png", "b.JPG", "c.jpeg", "d.gif", "e.webp", "f.txt", "g.mp4", "h.MOV"} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// Nested directories are not descended into (mirrors scan_dir_by_ext).
	if err := os.MkdirAll(filepath.Join(dir, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sub", "nested.png"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	imgs := scanDirByExt(dir, imageOptimizeExts)
	wantImgs := []string{"a.png", "b.JPG", "c.jpeg", "d.gif"}
	if !sameBaseSet(imgs, wantImgs) {
		t.Fatalf("image eligibility: want %v, got %v", wantImgs, baseNames(imgs))
	}

	vids := scanDirByExt(dir, videoConvertExts)
	wantVids := []string{"g.mp4", "h.MOV"}
	if !sameBaseSet(vids, wantVids) {
		t.Fatalf("video eligibility: want %v, got %v", wantVids, baseNames(vids))
	}
}

func TestOptimizeRunConvertsPNGs(t *testing.T) {
	if !haveMagick() {
		t.Skip("magick not installed")
	}
	wall := t.TempDir()
	writePNG(t, filepath.Join(wall, "a.png"), color.RGBA{200, 20, 20, 255})
	writePNG(t, filepath.Join(wall, "b.png"), color.RGBA{20, 200, 20, 255})

	rec := newRecorder()
	o := NewOptimizer(wall, t.TempDir(), rec.emit)

	if err := o.Start(kindOptimize, "balanced", "1080p", nil); err != nil {
		t.Fatalf("start: %v", err)
	}

	select {
	case <-rec.done:
	case <-time.After(60 * time.Second):
		t.Fatal("run did not finish in time")
	}

	webps, _ := filepath.Glob(filepath.Join(wall, "*.webp"))
	if len(webps) != 2 {
		t.Fatalf("want 2 webp outputs, got %v", webps)
	}
	pngs, _ := filepath.Glob(filepath.Join(wall, "*.png"))
	if len(pngs) != 0 {
		t.Fatalf("originals should be removed, still present: %v", pngs)
	}

	events := rec.snapshot()
	if len(events) < 2 {
		t.Fatalf("want progress + finished events, got %d", len(events))
	}
	if events[0].event != "ryogami.wall.optimize.progress" {
		t.Fatalf("first event should be progress, got %q", events[0].event)
	}
	last := events[len(events)-1]
	if last.event != "ryogami.wall.optimize.finished" {
		t.Fatalf("last event should be finished, got %q", last.event)
	}
	if last.data["optimized"] != 2 {
		t.Fatalf("finished optimized: want 2, got %v", last.data["optimized"])
	}
	// finished must arrive after every progress event.
	for _, e := range events[:len(events)-1] {
		if e.event == "ryogami.wall.optimize.finished" {
			t.Fatal("finished emitted before the last event")
		}
	}
}

func TestOptimizeCancelStopsEarly(t *testing.T) {
	if !haveMagick() {
		t.Skip("magick not installed")
	}
	wall := t.TempDir()
	const n = 8
	for i := range n {
		writePNG(t, filepath.Join(wall, string(rune('a'+i))+".png"), color.RGBA{uint8(i * 20), 30, 40, 255})
	}

	rec := newRecorder()
	o := NewOptimizer(wall, t.TempDir(), rec.emit)

	if err := o.Start(kindOptimize, "balanced", "1080p", nil); err != nil {
		t.Fatalf("start: %v", err)
	}

	// Cancel once the first file has been processed, then let the run wind down.
	select {
	case <-rec.firstFile:
	case <-time.After(30 * time.Second):
		t.Fatal("no file processed before timeout")
	}
	o.Cancel(kindOptimize)

	select {
	case <-rec.done:
	case <-time.After(30 * time.Second):
		t.Fatal("cancelled run did not emit finished")
	}

	st := o.Status(kindOptimize)
	if st["running"] != false {
		t.Fatalf("job should not be running after finish")
	}
	if st["total"] != n {
		t.Fatalf("total: want %d, got %v", n, st["total"])
	}
	if st["progress"].(int) >= n {
		t.Fatalf("cancel should have stopped before all %d files, progress=%v", n, st["progress"])
	}
}

func TestOptimizeStartRejectsSecondRun(t *testing.T) {
	o := NewOptimizer(t.TempDir(), t.TempDir(), nil)
	o.mu.Lock()
	o.jobs[kindOptimize].running = true
	o.mu.Unlock()
	if err := o.Start(kindOptimize, "balanced", "1080p", nil); err == nil {
		t.Fatal("second concurrent run should be rejected")
	}
	if err := o.Start(kindOptimize, "nope", "1080p", nil); err == nil {
		t.Fatal("unknown preset should error")
	}
	if err := o.Start(kindOptimize, "balanced", "nope", nil); err == nil {
		t.Fatal("unknown resolution should error")
	}
}

func baseNames(paths []string) []string {
	out := make([]string, len(paths))
	for i, p := range paths {
		out[i] = filepath.Base(p)
	}
	return out
}

func sameBaseSet(paths, want []string) bool {
	got := baseNames(paths)
	if len(got) != len(want) {
		return false
	}
	seen := map[string]bool{}
	for _, g := range got {
		seen[g] = true
	}
	for _, w := range want {
		if !seen[w] {
			return false
		}
	}
	return true
}

// Auto-optimise hands the optimizer only the new arrivals; the rest of the
// library keeps its originals.
func TestAutoOptimizeTouchesOnlyNewImages(t *testing.T) {
	if !haveMagick() {
		t.Skip("magick not installed")
	}
	wall := t.TempDir()
	existing := filepath.Join(wall, "existing.png")
	arrival := filepath.Join(wall, "arrival.png")
	writePNG(t, existing, color.RGBA{200, 20, 20, 255})
	writePNG(t, arrival, color.RGBA{20, 200, 20, 255})

	rec := newRecorder()
	o := NewOptimizer(wall, t.TempDir(), rec.emit)
	files := optimizableImages([]Entry{{Type: "static", Path: arrival}, {Type: "video", Path: filepath.Join(wall, "clip.mp4")}})
	if err := o.Start(kindOptimize, "balanced", "1080p", files); err != nil {
		t.Fatalf("start: %v", err)
	}
	select {
	case <-rec.done:
	case <-time.After(60 * time.Second):
		t.Fatal("run did not finish in time")
	}

	if !fileExists(existing) {
		t.Fatal("an image already in the library was re-encoded")
	}
	if fileExists(arrival) || !fileExists(filepath.Join(wall, "arrival.webp")) {
		t.Fatal("the new image was not optimised")
	}
}
