package main

type afterScanFunc func(d *daemon, added []Entry)

var afterScanHooks []afterScanFunc

func registerAfterScan(fn afterScanFunc) { afterScanHooks = append(afterScanHooks, fn) }

// An empty prior is a baseline scan (fresh install, cache reset), not a stream of arrivals.
func (d *daemon) runAfterScan(prior, fresh map[string]Entry) {
	if len(prior) == 0 || len(afterScanHooks) == 0 {
		return
	}
	var added []Entry
	for key, e := range fresh {
		if p, ok := prior[key]; !ok || p.Mtime != e.Mtime {
			added = append(added, e)
		}
	}
	if len(added) == 0 {
		return
	}
	for _, fn := range afterScanHooks {
		fn(d, added)
	}
}
