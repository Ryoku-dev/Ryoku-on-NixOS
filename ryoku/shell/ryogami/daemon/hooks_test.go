package main

import (
	"testing"
	"time"
)

func TestAvailabilityMapDoesNotRunProbeInline(t *testing.T) {
	const name = "__test_slow"
	availabilityMu.Lock()
	savedFn, hadFn := availability[name]
	savedState, hadState := availabilityCache[name]
	availabilityMu.Unlock()

	entered := make(chan struct{})
	release := make(chan struct{})
	done := make(chan struct{})
	registerAvailability(name, func(*daemon) bool {
		close(entered)
		<-release
		close(done)
		return false
	})
	t.Cleanup(func() {
		select {
		case <-done:
		default:
			close(release)
			<-done
		}
		availabilityMu.Lock()
		if hadFn {
			availability[name] = savedFn
		} else {
			delete(availability, name)
		}
		if hadState {
			availabilityCache[name] = savedState
		} else {
			delete(availabilityCache, name)
		}
		availabilityMu.Unlock()
	})

	result := make(chan map[string]bool, 1)
	go func() { result <- (&daemon{}).availabilityMap() }()
	select {
	case got := <-result:
		if !got[name] {
			t.Fatalf("uncached asynchronous availability should stay reachable: %v", got)
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("availabilityMap waited for a slow probe")
	}
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("background availability probe did not start")
	}
	close(release)
	<-done
}
