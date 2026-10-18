package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

const paletteOne = `{"primary":"#111111","surface":"#112233","onSurface":"#ffffff"}`
const paletteTwo = `{"primary":"#222222","surface":"#112233","onSurface":"#ffffff"}`
const paletteThree = `{"primary":"#333333","surface":"#112233","onSurface":"#ffffff"}`

func waitPalette(t *testing.T, hub *paletteHub, want string) {
	t.Helper()
	deadline := time.Now().Add(4 * time.Second)
	for string(hub.snapshot().data) != want {
		if time.Now().After(deadline) {
			t.Fatalf("palette = %q, want %q", hub.snapshot().data, want)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func writePalette(t *testing.T, path, data string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
}

func startWatcher(t *testing.T, path string, hub *paletteHub) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	attached := make(chan struct{}, 1)
	done := make(chan error, 1)
	go func() {
		done <- watchPaletteContext(ctx, path, func() error {
			err := hub.readFile(path)
			select {
			case attached <- struct{}{}:
			default:
			}
			return err
		})
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case err := <-done:
			if !errors.Is(err, context.Canceled) {
				t.Errorf("watcher stopped: %v", err)
			}
		case <-time.After(3 * time.Second):
			t.Error("watcher did not stop")
		}
	})
	select {
	case <-attached:
	case <-time.After(3 * time.Second):
		t.Fatal("watcher did not attach")
	}
}

func TestBridgeWaitsForAPaletteWrittenAfterStart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cache", "ryoku", "colors.json")
	hub := newPaletteHub()
	startWatcher(t, path, hub)
	rec := httptest.NewRecorder()
	hub.paletteHandler(rec, httptest.NewRequest(http.MethodGet, "/colors.json", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status before a palette = %d, want 503", rec.Code)
	}
	writePalette(t, path, paletteOne)
	waitPalette(t, hub, paletteOne)
}

func TestPaletteWatcherReadsPaletteAlreadyPresentWhenAttaching(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cache", "ryoku", "colors.json")
	// Simulate the first write landing after main's initial read and before attach.
	hub := newPaletteHub()
	if err := hub.readFile(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("initial read = %v", err)
	}
	writePalette(t, path, paletteOne)
	startWatcher(t, path, hub)
	waitPalette(t, hub, paletteOne)
}

func TestPaletteWatcherRecoversReplacedDirectories(t *testing.T) {
	for _, mode := range []string{"rename", "delete", "ancestor"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			dir := filepath.Join(root, "cache", "ryoku")
			path := filepath.Join(dir, "colors.json")
			hub := newPaletteHub()
			startWatcher(t, path, hub)
			writePalette(t, path, paletteOne)
			waitPalette(t, hub, paletteOne)
			switch mode {
			case "rename":
				if err := os.Rename(dir, dir+"-old"); err != nil {
					t.Fatal(err)
				}
			case "delete":
				if err := os.RemoveAll(dir); err != nil {
					t.Fatal(err)
				}
				// Recreation happens after a recovery check has seen the path absent.
				time.Sleep(1200 * time.Millisecond)
			case "ancestor":
				if err := os.Rename(filepath.Dir(dir), filepath.Dir(dir)+"-old"); err != nil {
					t.Fatal(err)
				}
			}
			// A single write before reattachment must suffice.
			writePalette(t, path, paletteTwo)
			waitPalette(t, hub, paletteTwo)
			writePalette(t, path, paletteThree)
			waitPalette(t, hub, paletteThree)
		})
	}
}

func TestPaletteWatcherKeepsValidPaletteAndAcceptsAtomicReplacement(t *testing.T) {
	path := filepath.Join(t.TempDir(), "colors.json")
	hub := newPaletteHub()
	startWatcher(t, path, hub)
	writePalette(t, path, paletteOne)
	waitPalette(t, hub, paletteOne)
	writePalette(t, path, "{")
	// Wait for the invalid write to be consumed before asserting retention.
	time.Sleep(50 * time.Millisecond)
	if got := string(hub.snapshot().data); got != paletteOne {
		t.Fatalf("invalid write replaced palette: %q", got)
	}
	tmp := path + ".new"
	writePalette(t, tmp, paletteTwo)
	if err := os.Rename(tmp, path); err != nil {
		t.Fatal(err)
	}
	waitPalette(t, hub, paletteTwo)
}
