package main

import (
	"errors"
	"strings"
)

// A locked output only changes through the multipicker, which names it explicitly.

var errAllLocked = errors.New("ryogami: every target output is locked")

func init() {
	guardApply(func(d *daemon, req *applyRequest) error {
		if restoreLikeApply(req.Reason) {
			return nil
		}
		locked := d.lockedOutputs()
		if len(locked) == 0 {
			return nil
		}
		keep, ok := filterUnlockedOutputs(req.Outputs, connectedOutputNames(), locked)
		if !ok {
			return errAllLocked
		}
		req.Outputs = keep
		return nil
	})
}

// A broadcast with no outputs reported yet stays a broadcast.
func filterUnlockedOutputs(requested, connected []string, locked map[string]bool) ([]string, bool) {
	if len(requested) == 0 || contains(requested, "*") {
		if len(connected) == 0 {
			return nil, true
		}
		var keep []string
		for _, name := range connected {
			if name != "" && !locked[name] {
				keep = append(keep, name)
			}
		}
		return keep, len(keep) > 0
	}
	var keep []string
	for _, o := range requested {
		if !locked[strings.TrimSpace(o)] {
			keep = append(keep, o)
		}
	}
	return keep, len(keep) > 0
}

func (d *daemon) lockedOutputs() map[string]bool {
	m := d.settingMap("display.outputLocks")
	if len(m) == 0 {
		return nil
	}
	out := map[string]bool{}
	for name, v := range m {
		if locked, ok := v.(bool); ok && locked {
			out[name] = true
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}
