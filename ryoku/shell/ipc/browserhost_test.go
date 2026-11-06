package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

type lockedBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *lockedBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

// frames decodes the native-messaging frames written so far.
func (l *lockedBuffer) frames(t *testing.T) []map[string]any {
	t.Helper()
	l.mu.Lock()
	data := append([]byte(nil), l.b.Bytes()...)
	l.mu.Unlock()
	var out []map[string]any
	for len(data) >= 4 {
		n := int(binary.LittleEndian.Uint32(data[:4]))
		if len(data) < 4+n {
			break
		}
		var m map[string]any
		if err := json.Unmarshal(data[4:4+n], &m); err != nil {
			t.Fatalf("bad frame: %v", err)
		}
		out = append(out, m)
		data = data[4+n:]
	}
	return out
}

func waitFrames(t *testing.T, buf *lockedBuffer, want int, within time.Duration) {
	t.Helper()
	deadline := time.Now().Add(within)
	for time.Now().Before(deadline) {
		if len(buf.frames(t)) >= want {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("got %d frames, want %d within %v", len(buf.frames(t)), want, within)
}

func writeColors(t *testing.T, path, bg string) {
	t.Helper()
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(`{"background":"`+bg+`","foreground":"#eeeeee","color0":"#000000"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	// Matugen and the shell replace the file by rename.
	if err := os.Rename(tmp, path); err != nil {
		t.Fatal(err)
	}
}

func startHost(t *testing.T, colors string) (*lockedBuffer, *io.PipeWriter, <-chan int) {
	t.Helper()
	in, inW := io.Pipe()
	out := &lockedBuffer{}
	exited := make(chan int, 1)
	go func() { exited <- serveBrowserHost(in, out, colors) }()
	return out, inW, exited
}

func TestBrowserHostPushesChangesWithoutPolling(t *testing.T) {
	dir := t.TempDir()
	colors := filepath.Join(dir, "colors.json")
	writeColors(t, colors, "#101010")
	before := browserHostFallbackPolls.Load()

	out, inW, exited := startHost(t, colors)
	waitFrames(t, out, 1, 2*time.Second)

	// Let the old polling interval pass several times: an idle host must not
	// emit anything nor fall back to stat polling.
	time.Sleep(3 * browserHostFallbackInterval)
	if n := len(out.frames(t)); n != 1 {
		t.Fatalf("idle host sent %d frames, want 1", n)
	}

	time.Sleep(20 * time.Millisecond) // ensure a newer mtime
	writeColors(t, colors, "#202020")
	waitFrames(t, out, 2, 2*time.Second)
	frames := out.frames(t)
	if got := frames[1]["colors"].(map[string]any)["background"]; got != "#202020" {
		t.Fatalf("update carried %v, want #202020", got)
	}
	if browserHostFallbackPolls.Load() != before {
		t.Fatal("event-driven path fell back to polling")
	}

	inW.Close()
	select {
	case rc := <-exited:
		if rc != 0 {
			t.Fatalf("exit code %d", rc)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("host did not exit when the browser disconnected")
	}
}

func TestBrowserHostExitsOnDisconnectWhileIdle(t *testing.T) {
	colors := filepath.Join(t.TempDir(), "colors.json")
	writeColors(t, colors, "#101010")
	_, inW, exited := startHost(t, colors)
	time.Sleep(100 * time.Millisecond)
	inW.Close()
	select {
	case <-exited:
	case <-time.After(2 * time.Second):
		t.Fatal("blocked watcher was not woken by disconnect")
	}
}

func TestBrowserHostFallsBackWhenDirectoryMissing(t *testing.T) {
	root := t.TempDir()
	colors := filepath.Join(root, "late", "colors.json") // directory not created yet
	before := browserHostFallbackPolls.Load()
	out, inW, exited := startHost(t, colors)
	defer func() { inW.Close(); <-exited }()

	time.Sleep(2 * browserHostFallbackInterval)
	if err := os.MkdirAll(filepath.Dir(colors), 0o755); err != nil {
		t.Fatal(err)
	}
	writeColors(t, colors, "#303030")
	// The initial send found nothing, so the first palette arrives via polling.
	waitFrames(t, out, 1, 3*time.Second)
	if browserHostFallbackPolls.Load() == before {
		t.Fatal("fallback path did not poll")
	}
}
