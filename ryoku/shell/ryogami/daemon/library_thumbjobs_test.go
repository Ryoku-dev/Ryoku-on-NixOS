package main

import (
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestClampThumbJobs(t *testing.T) {
	cases := map[float64]int32{-5: 1, 0: 1, 1: 1, 16: 16, 32: 32, 50: 32}
	for in, want := range cases {
		if got := clampThumbJobs(in); got != want {
			t.Errorf("clampThumbJobs(%v) = %d, want %d", in, got, want)
		}
	}
}

func TestProcessItemsParallelDedup(t *testing.T) {
	orig := processOne
	defer func() { processOne = orig }()
	defer thumbJobLimit.Store(16)
	processOne = func(it scanned, _ map[string]Entry, _ func(Entry)) Entry {
		return Entry{Key: it.key, Name: it.name}
	}
	thumbJobLimit.Store(4)

	items := []scanned{
		{key: "a", name: "a"},
		{key: "b", name: "b"},
		{key: "a", name: "a-dup"},
		{key: "c", name: "c"},
	}
	res := processItemsParallel(items, nil, nil)
	if len(res) != 3 {
		t.Fatalf("got %d unique entries, want 3", len(res))
	}
	if res["a"].Name != "a" {
		t.Fatalf("first-key-wins broken: a.Name = %q, want %q", res["a"].Name, "a")
	}
}

func TestProcessItemsParallelRespectsLimit(t *testing.T) {
	orig := processOne
	defer func() { processOne = orig }()
	defer thumbJobLimit.Store(16)

	const limit = 3
	thumbJobLimit.Store(limit)

	var live, peak int32
	var mu sync.Mutex
	processOne = func(it scanned, _ map[string]Entry, _ func(Entry)) Entry {
		n := atomic.AddInt32(&live, 1)
		mu.Lock()
		if n > peak {
			peak = n
		}
		mu.Unlock()
		time.Sleep(3 * time.Millisecond)
		atomic.AddInt32(&live, -1)
		return Entry{Key: it.key}
	}

	items := make([]scanned, 24)
	for i := range items {
		items[i] = scanned{key: fmt.Sprintf("k%d", i)}
	}
	res := processItemsParallel(items, nil, nil)
	if len(res) != 24 {
		t.Fatalf("processed %d, want 24", len(res))
	}
	if peak > limit {
		t.Fatalf("peak concurrency %d exceeded the limit %d", peak, limit)
	}
	if peak < 2 {
		t.Fatalf("no real parallelism observed (peak %d)", peak)
	}
}
