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

// A healthy surface holds about a gigabyte. A runaway one once reached 40 GiB
// in under a minute and stalled the whole machine. Observed growth pulls the
// next sample closer, and every wait is also capped by the headroom a known
// 2.5 GiB/s leak could consume so a flat sample never creates a blind window.
const (
	memoryNearInterval              = time.Second
	memoryIdleInterval              = 15 * time.Second
	memoryCeilingFloor              = 3 << 30
	memoryWorstGrowthBytesPerSecond = uint64(5 << 29)
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
	return processMemoryReader(strings.NewReader(status))
}

func processMemoryReader(r io.Reader) (uint64, bool) {
	sc := bufio.NewScanner(r)
	var rss, swap uint64
	var haveRSS, haveSwap bool
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "VmRSS:"):
			rss, haveRSS = parseStatusKB(line[len("VmRSS:"):])
		case strings.HasPrefix(line, "VmSwap:"):
			swap, haveSwap = parseStatusKB(line[len("VmSwap:"):])
		}
		if haveRSS && haveSwap {
			break
		}
	}
	return rss + swap, haveRSS
}

func parseStatusKB(value string) (uint64, bool) {
	fields := strings.Fields(value)
	if len(fields) == 0 {
		return 0, false
	}
	kb, err := strconv.ParseUint(fields[0], 10, 64)
	return kb << 10, err == nil
}

func readProcessMemory(pid int) (uint64, bool) {
	f, err := os.Open("/proc/" + strconv.Itoa(pid) + "/status")
	if err != nil {
		return 0, false
	}
	defer f.Close()
	return processMemoryReader(f)
}

// memorySampleInterval uses the smaller of the observed time-to-ceiling
// estimate and the worst leak rate the guard has seen in production.
func memorySampleInterval(limit, previous, current uint64, elapsed time.Duration) time.Duration {
	if current >= limit {
		return memoryNearInterval
	}
	headroom := limit - current
	next := time.Duration(float64(headroom) /
		float64(memoryWorstGrowthBytesPerSecond) * float64(time.Second))
	if elapsed > 0 && current > previous {
		growth := current - previous
		observed := time.Duration(float64(elapsed) * float64(headroom) / float64(growth) / 4)
		if observed < next {
			next = observed
		}
	}
	if next < memoryNearInterval {
		return memoryNearInterval
	}
	if next > memoryIdleInterval {
		return memoryIdleInterval
	}
	return next
}

// watchMemory samples the process until exited closes. The first sample over
// limit kills it and returns what it held; a process that exits on its own
// returns 0. maxInterval is injectable so the loop stays fast in tests.
func watchMemory(exited <-chan struct{}, limit uint64, maxInterval time.Duration,
	sample func() (uint64, bool), kill func()) uint64 {
	var previous uint64
	var sampledAt time.Time
	wait := time.Duration(0)
	for {
		if wait > 0 {
			timer := time.NewTimer(wait)
			select {
			case <-exited:
				timer.Stop()
				return 0
			case <-timer.C:
			}
		} else {
			select {
			case <-exited:
				return 0
			default:
			}
		}

		now := time.Now()
		used, ok := sample()
		if ok && used > limit {
			kill()
			return used
		}
		if !ok {
			wait = memoryNearInterval
		} else if sampledAt.IsZero() {
			previous, sampledAt = used, now
			wait = memoryNearInterval
		} else {
			wait = memorySampleInterval(limit, previous, used, now.Sub(sampledAt))
			previous, sampledAt = used, now
		}
		if maxInterval > 0 && wait > maxInterval {
			wait = maxInterval
		}
	}
}

// watchSurfaceMemory runs watchMemory on a supervised qs process and sends what
// it held when killed, or 0, once the process is gone. SIGKILL, not SIGTERM: a
// process deep in swap can take minutes to reach its signal handler.
func watchSurfaceMemory(pid int, limit uint64, exited <-chan struct{}, result chan<- uint64) {
	result <- watchMemory(exited, limit, memoryIdleInterval,
		func() (uint64, bool) { return readProcessMemory(pid) },
		func() { _ = syscall.Kill(pid, syscall.SIGKILL) })
}
