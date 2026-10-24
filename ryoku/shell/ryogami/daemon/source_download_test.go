package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func newTestSources(t *testing.T) (*daemon, *sources) {
	t.Helper()
	tmp := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(tmp, "config"))
	t.Setenv("RYOGAMI_WALL_CONFIG", "")
	resetSettingsState()
	t.Cleanup(resetSettingsState)
	d := &daemon{events: newEventHub()}
	d.cfg.Paths.Wallpaper = filepath.Join(tmp, "wall")
	d.cfg.Paths.VideoWallpaper = filepath.Join(tmp, "vid")
	d.cfg.Paths.Cache = filepath.Join(tmp, "cache")
	for _, dir := range []string{d.cfg.Paths.Wallpaper, d.cfg.Paths.VideoWallpaper, d.cfg.Paths.Cache} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	s := newSources(d)
	d.sources = s
	return d, s
}

type capturedEvent struct {
	Event string          `json:"event"`
	Data  json.RawMessage `json:"data"`
}

type thumbRoundTripFunc func(*http.Request) (*http.Response, error)

func (f thumbRoundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}

func drainEvents(ch chan string) []capturedEvent {
	var out []capturedEvent
	for {
		select {
		case line := <-ch:
			var ce capturedEvent
			_ = json.Unmarshal([]byte(line), &ce)
			out = append(out, ce)
		default:
			return out
		}
	}
}

func TestGateAdmission(t *testing.T) {
	g := newGate(1, 1) // one slot, one queue seat -> two outstanding max
	r1, ok1 := g.tryReserve()
	r2, ok2 := g.tryReserve()
	if !ok1 || !ok2 {
		t.Fatal("first two reservations should succeed")
	}
	if _, ok3 := g.tryReserve(); ok3 {
		t.Error("a reservation past the queue depth must be refused")
	}
	slot1 := r1.acquire(nil)
	admitted := make(chan struct{})
	go func() {
		s2 := r2.acquire(nil)
		close(admitted)
		s2.release()
	}()
	select {
	case <-admitted:
		t.Error("second reservation admitted while the slot was busy")
	case <-time.After(50 * time.Millisecond):
	}
	slot1.release()
	select {
	case <-admitted:
	case <-time.After(time.Second):
		t.Error("second reservation never admitted after the slot freed")
	}
}

func TestGateQueuedAheadCount(t *testing.T) {
	g := newGate(1, 4)
	r1, _ := g.tryReserve()
	r2, _ := g.tryReserve()
	slot1 := r1.acquire(nil)
	var ahead uint64 = 999
	waiting := make(chan struct{})
	go func() {
		close(waiting)
		s2 := r2.acquire(func(a uint64) { ahead = a })
		s2.release()
	}()
	<-waiting
	time.Sleep(30 * time.Millisecond)
	slot1.release()
	time.Sleep(30 * time.Millisecond)
	if ahead != 0 {
		t.Errorf("head-of-line ahead = %d, want 0", ahead)
	}
}

func TestDownloadDest(t *testing.T) {
	if got := downloadDest("/w", "wallhaven", "abc", "jpg"); got != "/w/wallhaven-abc.jpg" {
		t.Errorf("dest = %q", got)
	}
	if got := downloadDest("/v", "repos", "sub/dir/clip", "mp4"); got != "/v/repos-sub_dir_clip.mp4" {
		t.Errorf("path-like id not sanitised: %q", got)
	}
}

func TestLibraryRoundTrip(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "wallhaven-abc.jpg"), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(dir, "unsplash-xy.png"), []byte("x"), 0o644)
	ids := libraryIDs(dir, "wallhaven")
	if len(ids) != 1 || !ids["abc"] {
		t.Errorf("ids = %v", ids)
	}
	if p, ok := sourceLibraryPath(dir, "wallhaven", "abc"); !ok || filepath.Base(p) != "wallhaven-abc.jpg" {
		t.Errorf("path = %q ok=%v", p, ok)
	}
	if _, ok := sourceLibraryPath(dir, "wallhaven", "missing"); ok {
		t.Error("missing id should not resolve")
	}
}

func TestShouldEmitAndContentProgress(t *testing.T) {
	if !shouldEmit(0.02, 0.0, 200*time.Millisecond) {
		t.Error("Δ2% after 200ms should emit")
	}
	if shouldEmit(0.005, 0.0, 200*time.Millisecond) {
		t.Error("Δ0.5% should not emit")
	}
	if shouldEmit(0.5, 0.0, 100*time.Millisecond) {
		t.Error("under 125ms should not emit")
	}
	if p, ok := contentProgress(50, 100); !ok || p != 0.5 {
		t.Errorf("progress = %v %v", p, ok)
	}
	if p, _ := contentProgress(100, 100); p != 0.99 {
		t.Errorf("progress should clamp to 0.99, got %v", p)
	}
	if _, ok := contentProgress(1, 0); ok {
		t.Error("unknown total should yield no progress")
	}
}

func TestDownloadProgressThrottleKeepsFirstStatusAndFinalEvents(t *testing.T) {
	_, sources := newTestSources(t)
	start := time.Unix(100, 0)
	p := 0.1
	if !sources.allowDownloadEvent(downloadEvent{ID: "a", Status: dlQueued}, start) {
		t.Fatal("first event was suppressed")
	}
	if sources.allowDownloadEvent(downloadEvent{ID: "a", Status: dlQueued, Progress: &p}, start.Add(124*time.Millisecond)) {
		t.Fatal("progress event inside throttle window was emitted")
	}
	if !sources.allowDownloadEvent(downloadEvent{ID: "a", Status: dlDownloading, Progress: &p}, start.Add(20*time.Millisecond)) {
		t.Fatal("status change was suppressed")
	}
	if sources.allowDownloadEvent(downloadEvent{ID: "a", Status: dlDownloading, Progress: &p}, start.Add(144*time.Millisecond)) {
		t.Fatal("eighth-of-a-second boundary was emitted early")
	}
	if !sources.allowDownloadEvent(downloadEvent{ID: "a", Status: dlDownloading, Progress: &p}, start.Add(145*time.Millisecond)) {
		t.Fatal("progress event at throttle boundary was suppressed")
	}
	if !sources.allowDownloadEvent(downloadEvent{ID: "a", Status: dlDone}, start.Add(146*time.Millisecond)) {
		t.Fatal("final event was suppressed")
	}
	if !sources.allowDownloadEvent(downloadEvent{ID: "a", Status: dlDownloading}, start.Add(147*time.Millisecond)) {
		t.Fatal("new transfer's first event was suppressed")
	}
}

func TestWorkshopProgressThrottleKeepsStatusAndFinalEvents(t *testing.T) {
	d := &daemon{}
	start := time.Unix(200, 0)
	if !d.allowWorkshopDownloadEvent("42", "downloading", start) {
		t.Fatal("first event was suppressed")
	}
	if d.allowWorkshopDownloadEvent("42", "downloading", start.Add(50*time.Millisecond)) {
		t.Fatal("progress event inside throttle window was emitted")
	}
	if !d.allowWorkshopDownloadEvent("42", "auth_error", start.Add(51*time.Millisecond)) {
		t.Fatal("status change/final event was suppressed")
	}
	if !d.allowWorkshopDownloadEvent("42", "done", start.Add(52*time.Millisecond)) {
		t.Fatal("done event was suppressed")
	}
}

func TestDownloadEventShapes(t *testing.T) {
	p := "/x/wallhaven-1.jpg"
	done, _ := json.Marshal(downloadEvent{ID: "1", Status: dlDone, Path: &p})
	if strings.Contains(string(done), "progress") || strings.Contains(string(done), "error") {
		t.Errorf("done event carries extra fields: %s", done)
	}
	if !strings.Contains(string(done), `"path":"/x/wallhaven-1.jpg"`) {
		t.Errorf("done missing path: %s", done)
	}
	e := "boom"
	fail, _ := json.Marshal(downloadEvent{ID: "1", Status: dlError, Error: &e})
	if !strings.Contains(string(fail), `"error":"boom"`) || strings.Contains(string(fail), "path") {
		t.Errorf("error event shape: %s", fail)
	}
}

func TestRespondExistsEmitsDone(t *testing.T) {
	d, s := newTestSources(t)
	ch := d.events.subscribe()
	resp := s.respondExists(7, "id1", "/w/wallhaven-id1.jpg")
	res := resp.Result.(map[string]interface{})
	if res["status"] != "exists" || res["path"] != "/w/wallhaven-id1.jpg" {
		t.Errorf("resp = %+v", res)
	}
	evs := drainEvents(ch)
	if len(evs) != 1 || evs[0].Event != evDownload {
		t.Fatalf("events = %+v", evs)
	}
	var de downloadEvent
	json.Unmarshal(evs[0].Data, &de)
	if de.Status != dlDone || de.Path == nil || *de.Path != "/w/wallhaven-id1.jpg" {
		t.Errorf("done event = %+v", de)
	}
}

func TestFinishDownloadError(t *testing.T) {
	d, s := newTestSources(t)
	ch := d.events.subscribe()
	s.finishDownload("id2", "", errors.New("network down"))
	evs := drainEvents(ch)
	if len(evs) != 1 {
		t.Fatalf("events = %+v", evs)
	}
	var de downloadEvent
	json.Unmarshal(evs[0].Data, &de)
	if de.Status != dlError || de.Error == nil || *de.Error != "network down" {
		t.Errorf("error event = %+v", de)
	}
}

func TestStartDownloadInProgress(t *testing.T) {
	_, s := newTestSources(t)
	s.beginInflight("wallhaven:x")
	resp := s.startDownload(1, "x", s.images, "wallhaven:x", func(context.Context, *gateSlot) {})
	if resp.Result.(map[string]interface{})["status"] != "in_progress" {
		t.Errorf("resp = %+v", resp.Result)
	}
}

func TestStartDownloadQueueFull(t *testing.T) {
	_, s := newTestSources(t)
	s.images = newGate(0, 0)
	resp := s.startDownload(1, "x", s.images, "wallhaven:x", func(context.Context, *gateSlot) {})
	if resp.Error == nil || resp.Error.Code != -32000 {
		t.Errorf("expected queue-full, got %+v", resp)
	}
	s.inflightMu.Lock()
	held := s.inflight["wallhaven:x"]
	s.inflightMu.Unlock()
	if held {
		t.Error("inflight key should be released when the queue is full")
	}
}

func TestStartDownloadStartedRunsWork(t *testing.T) {
	_, s := newTestSources(t)
	done := make(chan struct{})
	resp := s.startDownload(1, "x", s.images, "wallhaven:x", func(context.Context, *gateSlot) { close(done) })
	if resp.Result.(map[string]interface{})["status"] != "started" {
		t.Errorf("resp = %+v", resp.Result)
	}
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Error("work never ran")
	}
}

var pngBytes = []byte{0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0, 0, 0, 0, 0}

func TestFetchToFileSuccess(t *testing.T) {
	d, s := newTestSources(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write(pngBytes)
	}))
	defer srv.Close()
	dest := filepath.Join(d.config().wallpaperDir(), "wallhaven-1.jpg")
	permit := func(string) error { return nil }
	if err := s.fetchToFile(context.Background(), srv.URL, dest, sniffImage, maxDownloadBytes, permit, nil); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(dest); len(b) != len(pngBytes) {
		t.Errorf("file len = %d", len(b))
	}
	entries, _ := os.ReadDir(filepath.Dir(dest))
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".part") {
			t.Errorf("leftover partial file: %s", e.Name())
		}
	}
}

func TestFetchToFileRejectsWrongType(t *testing.T) {
	d, s := newTestSources(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("<html>error page served with an image extension</html>"))
	}))
	defer srv.Close()
	dest := filepath.Join(d.config().wallpaperDir(), "wallhaven-2.jpg")
	if err := s.fetchToFile(context.Background(), srv.URL, dest, sniffImage, maxDownloadBytes, func(string) error { return nil }, nil); err == nil {
		t.Error("expected a magic-byte rejection")
	}
	if _, err := os.Stat(dest); err == nil {
		t.Error("a rejected download must leave no file")
	}
}

func TestFetchToFileSizeCap(t *testing.T) {
	d, s := newTestSources(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("0123456789ABCDEF"))
	}))
	defer srv.Close()
	dest := filepath.Join(d.config().wallpaperDir(), "wallhaven-3.jpg")
	if err := s.fetchToFile(context.Background(), srv.URL, dest, sniffImage, 4, func(string) error { return nil }, nil); err == nil {
		t.Error("expected a size-cap rejection")
	}
}

func TestSupersededOverlappingThumbnailEmitsOnce(t *testing.T) {
	d, s := newTestSources(t)
	const (
		connectionID = 91
		source       = "wallhaven"
		id           = "shared"
		thumbURL     = "https://wallhaven.cc/shared.png"
	)
	started := make(chan struct{})
	release := make(chan struct{})
	var startedOnce, releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	defer unblock()
	s.http.noRedirect = &http.Client{Transport: thumbRoundTripFunc(func(req *http.Request) (*http.Response, error) {
		startedOnce.Do(func() { close(started) })
		<-release
		return &http.Response{
			StatusCode: http.StatusOK,
			Header:     make(http.Header),
			Body:       io.NopCloser(strings.NewReader(string(pngBytes))),
			Request:    req,
		}, nil
	})}
	events := d.events.subscribe()
	defer d.events.unsubscribe(events)
	s.openSearchConnection(connectionID)
	defer s.dropSearchConnection(connectionID)

	_, finishFirst, stale := s.beginSearch(connectionID, source, 1, time.Minute)
	if stale {
		t.Fatal("first search was unexpectedly stale")
	}
	defer finishFirst()
	jobs := [][2]string{{id, thumbURL}}
	s.queueRemoteThumbs(connectionID, source, source, 1, jobs)
	select {
	case <-started:
	case <-time.After(3 * time.Second):
		t.Fatal("first thumbnail fetch did not start")
	}

	_, finishSecond, stale := s.beginSearch(connectionID, source, 2, time.Minute)
	if stale {
		t.Fatal("second search was unexpectedly stale")
	}
	defer finishSecond()
	s.queueRemoteThumbs(connectionID, source, source, 2, jobs)
	time.Sleep(50 * time.Millisecond)
	unblock()

	count := 0
	deadline := time.After(3 * time.Second)
	for count == 0 {
		select {
		case line := <-events:
			var ev capturedEvent
			if json.Unmarshal([]byte(line), &ev) == nil && ev.Event == evRemoteThumb {
				var data map[string]interface{}
				if json.Unmarshal(ev.Data, &data) == nil && data["source"] == source && data["id"] == id {
					count++
				}
			}
		case <-deadline:
			t.Fatal("overlapping result never received its thumbnail event")
		}
	}
	select {
	case line := <-events:
		var ev capturedEvent
		if json.Unmarshal([]byte(line), &ev) == nil && ev.Event == evRemoteThumb {
			var data map[string]interface{}
			if json.Unmarshal(ev.Data, &data) == nil && data["source"] == source && data["id"] == id {
				count++
			}
		}
	case <-time.After(200 * time.Millisecond):
	}
	if count != 1 {
		t.Fatalf("thumbnail event count = %d, want 1", count)
	}
}
