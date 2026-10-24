package main

import "testing"

func hasReason(rs []string, want string) bool {
	for _, r := range rs {
		if r == want {
			return true
		}
	}
	return false
}

func TestWindowCoverage(t *testing.T) {
	out := wmOutputGeom{width: 1920, height: 1080}
	cases := []struct {
		name                       string
		w, h                       int
		fullWidth, max, fullscreen bool
	}{
		{"normal tile", 800, 600, false, false, false},
		{"just under 90% width", 1700, 900, false, false, false}, // 1700/1920 = 0.885
		{"at 90% width, short", 1728, 1000, true, true, false},
		{"full width and height", 1920, 1080, true, false, true},
		{"full width, near-full height within tolerance", 1920, 1075, true, false, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fw, mx, fs := windowCoverage(wmWin{width: c.w, height: c.h}, out)
			if fw != c.fullWidth || mx != c.max || fs != c.fullscreen {
				t.Fatalf("coverage(%d,%d) = fw=%v max=%v fs=%v, want fw=%v max=%v fs=%v",
					c.w, c.h, fw, mx, fs, c.fullWidth, c.max, c.fullscreen)
			}
		})
	}
	if fw, _, _ := windowCoverage(wmWin{width: 1920, height: 1080}, wmOutputGeom{}); fw {
		t.Fatal("unknown output geometry must not report coverage")
	}
}

func baseSnapshot() wmSnapshot {
	out := wmOutputGeom{width: 1920, height: 1080}
	return wmSnapshot{
		outputs:          map[string]wmOutputGeom{"DP-1": out},
		activeWorkspaces: map[string]bool{"1": true},
		windows:          []wmWin{{output: "DP-1", workspace: "1", width: 1920, height: 1080}},
		focusedOutput:    "DP-1",
	}
}

func TestEvaluatePause(t *testing.T) {
	max := baseSnapshot()
	max.windows = []wmWin{{output: "DP-1", workspace: "1", width: 1900, height: 1040}}
	normal := baseSnapshot()
	normal.windows = []wmWin{{output: "DP-1", workspace: "1", width: 800, height: 600}}

	t.Run("fullscreen", func(t *testing.T) {
		p, rs := evaluatePause(pauseRules{fullscreen: true}, baseSnapshot(), nil)
		if !p || !hasReason(rs, "fullscreen") {
			t.Fatalf("fullscreen window must pause: %v %v", p, rs)
		}
		if p, _ := evaluatePause(pauseRules{maximized: true}, baseSnapshot(), nil); p {
			t.Fatal("a fullscreen window is not a maximised one")
		}
	})
	t.Run("maximized", func(t *testing.T) {
		if p, _ := evaluatePause(pauseRules{maximized: true}, max, nil); !p {
			t.Fatal("a full-width, sub-full-height window is maximised")
		}
		if p, _ := evaluatePause(pauseRules{fullscreen: true}, max, nil); p {
			t.Fatal("a maximised window is not fullscreen")
		}
	})
	t.Run("normal tile never pauses", func(t *testing.T) {
		r := pauseRules{fullscreen: true, maximized: true, fullWidth: true, capColumnFill: true}
		if p, _ := evaluatePause(r, normal, nil); p {
			t.Fatal("an ordinary tile must not pause")
		}
	})
	t.Run("fullWidth gated on capability", func(t *testing.T) {
		if p, _ := evaluatePause(pauseRules{fullWidth: true, capColumnFill: false}, max, nil); p {
			t.Fatal("full-width rule must not fire without the capability")
		}
		if p, rs := evaluatePause(pauseRules{fullWidth: true, capColumnFill: true}, max, nil); !p || !hasReason(rs, "fullWidth") {
			t.Fatal("full-width rule must fire with the capability")
		}
	})
	t.Run("process", func(t *testing.T) {
		r := pauseRules{processEnabled: true, processes: []string{"mpv"}}
		if p, rs := evaluatePause(r, baseSnapshot(), map[string]bool{"mpv": true}); !p || !hasReason(rs, "process") {
			t.Fatal("a listed running process must pause")
		}
		if p, _ := evaluatePause(r, baseSnapshot(), map[string]bool{"firefox": true}); p {
			t.Fatal("an unlisted process must not pause")
		}
	})
	t.Run("overviewOnly inverse and gated", func(t *testing.T) {
		r := pauseRules{overviewOnly: true, capOverviewState: true}
		if p, rs := evaluatePause(r, wmSnapshot{overviewOpen: false}, nil); !p || !hasReason(rs, "overview") {
			t.Fatal("overview-only must pause while the overview is closed")
		}
		if p, _ := evaluatePause(r, wmSnapshot{overviewOpen: true}, nil); p {
			t.Fatal("overview-only must play while the overview is open")
		}
		if p, _ := evaluatePause(pauseRules{overviewOnly: true, capOverviewState: false}, wmSnapshot{}, nil); p {
			t.Fatal("overview-only must not fire without the capability")
		}
	})
	t.Run("display scope", func(t *testing.T) {
		s := baseSnapshot()
		s.outputs["HDMI-1"] = wmOutputGeom{width: 1920, height: 1080}
		s.windows = []wmWin{{output: "HDMI-1", workspace: "1", width: 1920, height: 1080}}
		if p, _ := evaluatePause(pauseRules{fullscreen: true, scopeDisplay: true}, s, nil); p {
			t.Fatal("display scope must ignore a window off the focused output")
		}
		if p, _ := evaluatePause(pauseRules{fullscreen: true, scopeDisplay: false}, s, nil); !p {
			t.Fatal("all-displays scope must count a window on any output")
		}
	})
	t.Run("hidden workspace ignored", func(t *testing.T) {
		s := baseSnapshot()
		s.activeWorkspaces = map[string]bool{"2": true}
		if p, _ := evaluatePause(pauseRules{fullscreen: true}, s, nil); p {
			t.Fatal("a window on a hidden workspace must not pause")
		}
	})
}
