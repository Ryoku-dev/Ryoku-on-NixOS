package main

import (
	"sync"
	"sync/atomic"
)

// A package-level atomic: ScanDirs runs without a daemon reference.
var thumbJobLimit atomic.Int32

// A seam so tests can measure the pool without shelling out.
var processOne = processItem

func init() {
	thumbJobLimit.Store(16)
	seed := func(d *daemon) { thumbJobLimit.Store(clampThumbJobs(d.settingNumber("performance.maxThumbJobs"))) }
	onStart(seed)
	watchSetting("performance.maxThumbJobs", func(d *daemon, _ string, _ interface{}) { seed(d) })
}

func clampThumbJobs(v float64) int32 {
	n := int32(v)
	if n < 1 {
		return 1
	}
	if n > 32 {
		return 32
	}
	return n
}

func processItemsParallel(items []scanned, prior map[string]Entry, onItem func(Entry)) map[string]Entry {
	unique := make([]scanned, 0, len(items))
	seen := make(map[string]bool, len(items))
	for _, it := range items {
		if seen[it.key] {
			continue
		}
		seen[it.key] = true
		unique = append(unique, it)
	}

	result := make(map[string]Entry, len(unique))
	if len(unique) == 0 {
		return result
	}

	workers := int(thumbJobLimit.Load())
	if workers < 1 {
		workers = 1
	}
	if workers > len(unique) {
		workers = len(unique)
	}

	var itemMu sync.Mutex
	emit := func(e Entry) {
		if onItem == nil {
			return
		}
		itemMu.Lock()
		onItem(e)
		itemMu.Unlock()
	}

	var resMu sync.Mutex
	var wg sync.WaitGroup
	jobs := make(chan scanned)
	for range workers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for it := range jobs {
				e := processOne(it, prior, emit)
				resMu.Lock()
				result[it.key] = e
				resMu.Unlock()
			}
		}()
	}
	for _, it := range unique {
		jobs <- it
	}
	close(jobs)
	wg.Wait()
	return result
}
