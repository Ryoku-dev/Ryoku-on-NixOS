package main

import (
	"bufio"
	"io"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// A healthy surface holds about a gigabyte. A runaway one (a dock image that
// decoded itself bigger on every load) reached 40 GiB in under a minute, and the
// kernel's OOM killer only acted after swap was full and the whole machine,
// network included, had stalled for minutes. The daemon ends that at the
// surface: past the ceiling it kills the qs process and respawns it. That leak
// grew by up to 2.5 GiB a second, so the poll stays at one second to keep the
// overshoot small on an 8 GiB machine; one /proc read per surface is free.
const (
	memoryPollInterval = time.Second
	memoryCeilingFloor = 3 << 30
)

// memoryCeiling is how much RAM plus swap one supervised qs process may hold:
// a quarter of the machine's memory, never less than memoryCeilingFloor so a
// small machine still fits a normal shell.
func memoryCeiling(memTotal uint64) uint64 {
	if quarter := memTotal / 4; quarter > memoryCeilingFloor {
		return quarter
	}
	return memoryCeilingFloor
}

// readKBField returns the value of a "Name:   1234 kB" line from a /proc file.
func readKBField(r io.Reader, field string) (uint64, bool) {
	sc := bufio.NewScanner(r)
	prefix := field + ":"
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, prefix) {
			continue
		}
		fields := strings.Fields(line[len(prefix):])
		if len(fields) == 0 {
			return 0, false
		}
		kb, err := strconv.ParseUint(fields[0], 10, 64)
		return kb << 10, err == nil
	}
	return 0, false
}

func systemMemory() uint64 {
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0
	}
	defer f.Close()
	total, _ := readKBField(f, "MemTotal")
	return total
}

// processMemory is resident plus swapped-out memory: a leak that is being
// pushed to swap is still a leak, and swap is where the machine stalls.
func processMemory(status string) (uint64, bool) {
	rss, ok := readKBField(strings.NewReader(status), "VmRSS")
	if !ok {
		return 0, false
	}
	swap, _ := readKBField(strings.NewReader(status), "VmSwap")
	return rss + swap, true
}

func readProcessMemory(pid int) (uint64, bool) {
	b, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/status")
	if err != nil {
		return 0, false
	}
	return processMemory(string(b))
}

// watchMemory samples the process until exited closes. The first sample over
// limit kills it and returns what it held; a process that exits on its own
// returns 0.
func watchMemory(exited <-chan struct{}, limit uint64, interval time.Duration,
	sample func() (uint64, bool), kill func()) uint64 {
	tick := time.NewTicker(interval)
	defer tick.Stop()
	for {
		select {
		case <-exited:
			return 0
		case <-tick.C:
			used, ok := sample()
			if ok && used > limit {
				kill()
				return used
			}
		}
	}
}

// watchSurfaceMemory runs watchMemory on a supervised qs process and sends what
// it held when killed, or 0, once the process is gone. SIGKILL, not SIGTERM: a
// process deep in swap can take minutes to reach its signal handler.
func watchSurfaceMemory(pid int, limit uint64, exited <-chan struct{}, result chan<- uint64) {
	result <- watchMemory(exited, limit, memoryPollInterval,
		func() (uint64, bool) { return readProcessMemory(pid) },
		func() { _ = syscall.Kill(pid, syscall.SIGKILL) })
}
