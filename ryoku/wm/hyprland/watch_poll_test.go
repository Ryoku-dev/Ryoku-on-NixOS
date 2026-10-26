package main

import (
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"

	wm "ryoku-wm"
)

func TestGeometryPollFollowsVisibleFloatingWindow(t *testing.T) {
	var clients atomic.Value
	clients.Store([]byte(`[{"address":"0xa","class":"kitty","monitor":0,"floating":false,"at":[0,0],"size":[800,600],"workspace":{"id":1,"name":"1"},"focusHistoryID":0}]`))
	queries := make(chan struct{}, 64)

	restore := stubCtl(t, func(args ...string) ([]byte, error) {
		switch args[0] {
		case "monitors":
			return []byte(`[{"id":0,"name":"DP-1","width":1920,"height":1080,"activeWorkspace":{"id":1,"name":"1"},"specialWorkspace":{"id":0,"name":""}}]`), nil
		case "workspaces":
			return []byte(`[{"id":1,"name":"1","monitor":"DP-1","windows":1}]`), nil
		case "clients":
			select {
			case queries <- struct{}{}:
			default:
			}
			return clients.Load().([]byte), nil
		case "devices":
			return []byte(`{"keyboards":[]}`), nil
		default:
			t.Fatalf("unexpected query %v", args)
			return nil, nil
		}
	})
	defer restore()

	frames := make(chan wm.Frame, 32)
	provider, events := net.Pipe()
	defer events.Close()
	go consumeWithGeometryPoll(provider, func(frame wm.Frame) { frames <- frame }, func(wm.FrameKind) bool { return true }, 10*time.Millisecond)

	waitWindowFloating(t, frames, false)
	waitFrameKind(t, frames, wm.FrameReady)
	drainGeometryQueries(queries)
	assertNoGeometryQuery(t, queries, 50*time.Millisecond)

	writeWatchEvent(t, events, "activewindowv2>>a\n")
	awaitGeometryQuery(t, queries)
	assertNoGeometryQuery(t, queries, 50*time.Millisecond)

	clients.Store([]byte(`[{"address":"0xa","class":"kitty","monitor":0,"floating":true,"at":[20,30],"size":[800,600],"workspace":{"id":1,"name":"1"},"focusHistoryID":0}]`))
	writeWatchEvent(t, events, "changefloatingmode>>a,1\n")
	waitWindowFloating(t, frames, true)
	drainGeometryQueries(queries)
	awaitGeometryQuery(t, queries)

	clients.Store([]byte(`[{"address":"0xa","class":"kitty","monitor":0,"floating":false,"at":[20,30],"size":[800,600],"workspace":{"id":1,"name":"1"},"focusHistoryID":0}]`))
	writeWatchEvent(t, events, "changefloatingmode>>a,0\n")
	waitWindowFloating(t, frames, false)
	time.Sleep(20 * time.Millisecond)
	drainGeometryQueries(queries)
	assertNoGeometryQuery(t, queries, 50*time.Millisecond)

	clients.Store([]byte(`[{"address":"0xa","class":"kitty","monitor":0,"floating":true,"at":[40,50],"size":[800,600],"workspace":{"id":1,"name":"1"},"focusHistoryID":0}]`))
	writeWatchEvent(t, events, "changefloatingmode>>a,1\n")
	waitWindowFloating(t, frames, true)
	drainGeometryQueries(queries)
	awaitGeometryQuery(t, queries)
}

func writeWatchEvent(t *testing.T, conn net.Conn, event string) {
	t.Helper()
	if _, err := io.WriteString(conn, event); err != nil {
		t.Fatal(err)
	}
}

func waitFrameKind(t *testing.T, frames <-chan wm.Frame, kind wm.FrameKind) {
	t.Helper()
	select {
	case frame := <-frames:
		if frame.Kind != kind {
			t.Fatalf("frame kind = %q, want %q", frame.Kind, kind)
		}
	case <-time.After(time.Second):
		t.Fatalf("no %q frame", kind)
	}
}

func waitWindowFloating(t *testing.T, frames <-chan wm.Frame, floating bool) {
	t.Helper()
	timer := time.NewTimer(time.Second)
	defer timer.Stop()
	for {
		select {
		case frame := <-frames:
			if frame.Kind == wm.FrameWindows && len(frame.Windows) == 1 && frame.Windows[0].Floating == floating {
				return
			}
		case <-timer.C:
			t.Fatalf("no windows frame with floating=%v", floating)
		}
	}
}

func awaitGeometryQuery(t *testing.T, queries <-chan struct{}) {
	t.Helper()
	select {
	case <-queries:
	case <-time.After(time.Second):
		t.Fatal("geometry poll did not resume")
	}
}

func assertNoGeometryQuery(t *testing.T, queries <-chan struct{}, wait time.Duration) {
	t.Helper()
	select {
	case <-queries:
		t.Fatal("geometry poll ran while disabled")
	case <-time.After(wait):
	}
}

func drainGeometryQueries(queries <-chan struct{}) {
	for {
		select {
		case <-queries:
		default:
			return
		}
	}
}
