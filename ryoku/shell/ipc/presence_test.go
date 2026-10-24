package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func readPresenceFrame(t *testing.T, sub *topicSubscriber) presenceFrame {
	t.Helper()
	select {
	case body := <-sub.frames:
		var frame presenceFrame
		if err := json.Unmarshal(body, &frame); err != nil {
			t.Fatal(err)
		}
		return frame
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for presence frame")
		return presenceFrame{}
	}
}

func assertNoPresenceFrame(t *testing.T, sub *topicSubscriber) {
	t.Helper()
	select {
	case body := <-sub.frames:
		t.Fatalf("unexpected duplicate presence frame: %s", body)
	case <-time.After(30 * time.Millisecond):
	}
}

func TestPresenceStateDerivationAndTransitions(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "qylock.test.locked")
	generation := filepath.Join(dir, "generation")
	valid := false
	topic := newStateTopic()
	state := &presenceState{
		topic:          topic,
		marker:         marker,
		generation:     generation,
		lockProofValid: func() bool { return valid },
	}
	sub := topic.subscribe()
	defer topic.unsubscribe(sub)

	state.refresh(true, true)
	if got := readPresenceFrame(t, sub); got != (presenceFrame{}) {
		t.Fatalf("initial frame = %+v", got)
	}
	if err := os.WriteFile(marker, []byte("token\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	state.refresh(true, false)
	assertNoPresenceFrame(t, sub)

	valid = true
	state.refresh(true, false)
	if got := readPresenceFrame(t, sub); !got.Locked || got.DisplaysOff {
		t.Fatalf("locked frame = %+v", got)
	}
	state.refresh(true, false)
	assertNoPresenceFrame(t, sub)

	if err := os.WriteFile(generation, []byte("1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	state.refresh(false, true)
	if got := readPresenceFrame(t, sub); !got.Locked || !got.DisplaysOff {
		t.Fatalf("dark frame = %+v", got)
	}

	if err := os.Remove(marker); err != nil {
		t.Fatal(err)
	}
	state.refresh(true, false)
	if got := readPresenceFrame(t, sub); got.Locked || !got.DisplaysOff {
		t.Fatalf("display-only frame = %+v", got)
	}
	if err := os.Remove(generation); err != nil {
		t.Fatal(err)
	}
	state.refresh(false, true)
	if got := readPresenceFrame(t, sub); got != (presenceFrame{}) {
		t.Fatalf("restored frame = %+v", got)
	}
}
