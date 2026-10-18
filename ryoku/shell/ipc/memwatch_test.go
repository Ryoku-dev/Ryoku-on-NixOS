package main

import (
	"testing"
	"time"
)

func TestMemoryCeiling(t *testing.T) {
	for _, tc := range []struct {
		total, want uint64
	}{
		{8 << 30, 3 << 30},  // a quarter would be 2 GiB: the floor keeps a normal shell alive
		{12 << 30, 3 << 30}, // exactly the floor
		{44 << 30, 11 << 30},
		{0, 3 << 30}, // unreadable meminfo still gets a ceiling
	} {
		if got := memoryCeiling(tc.total); got != tc.want {
			t.Errorf("memoryCeiling(%d GiB) = %d MiB, want %d MiB", tc.total>>30, got>>20, tc.want>>20)
		}
	}
}

func TestProcessMemoryCountsSwap(t *testing.T) {
	status := "Name:\tqs\nVmPeak:\t 9999999 kB\nVmRSS:\t  1048576 kB\nVmSwap:\t  524288 kB\n"
	if got, ok := processMemory(status); !ok || got != (1<<30)+(512<<20) {
		t.Fatalf("processMemory = %d, %v; want 1.5 GiB", got, ok)
	}
	if got, ok := processMemory("Name:\tqs\nVmRSS:\t2048 kB\n"); !ok || got != 2<<20 {
		t.Fatalf("without VmSwap = %d, %v; want 2 MiB", got, ok)
	}
	// A zombie has no VmRSS line; that is no reading, not zero memory.
	if _, ok := processMemory("Name:\tqs\nState:\tZ (zombie)\n"); ok {
		t.Fatal("a status without VmRSS must not count as a reading")
	}
}

func TestWatchMemoryKillsOnlyPastTheCeiling(t *testing.T) {
	samples := []uint64{100, 0, 200, 900}
	readable := []bool{true, false, true, true}
	i := 0
	killed := 0
	used := watchMemory(make(chan struct{}), 500, time.Millisecond,
		func() (uint64, bool) {
			n, ok := samples[i], readable[i]
			i++
			return n, ok
		},
		func() { killed++ })
	if used != 900 || killed != 1 || i != len(samples) {
		t.Fatalf("used %d, killed %d times after %d samples; want 900, once, after %d", used, killed, i, len(samples))
	}
}

func TestWatchMemoryReturnsWhenTheProcessExits(t *testing.T) {
	exited := make(chan struct{})
	close(exited)
	used := watchMemory(exited, 500, time.Hour,
		func() (uint64, bool) { return 1 << 40, true },
		func() { t.Fatal("killed a process that already exited") })
	if used != 0 {
		t.Fatalf("used = %d, want 0", used)
	}
}
