package updater

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"testing"
	"time"
)

func piecePublisher() *publisher {
	return &publisher{
		active: true,
		phase:  "running",
		steps: []runStep{{
			Key: "deploy", Label: "Deploying the desktop", State: stepRunning, Began: nowMs(),
		}},
		lastWrite: time.Now(),
	}
}

func seedPieceHistory(t *testing.T, entries ...pieceHistoryEntry) {
	t.Helper()
	writePieceHistory(entries)
	if got := loadPieceHistory(); !reflect.DeepEqual(got, entries) {
		t.Fatalf("seeded piece history = %#v, want %#v", got, entries)
	}
}

func TestPieceLabelsTranslateFixedKeysAndCarryDynamicApps(t *testing.T) {
	if got := pieceLabel("shell", "carried"); got != pieceLabels["shell"] {
		t.Fatalf("fixed label = %q", got)
	}
	if got := pieceLabel("app-ryovm", "the ryovm app"); got != "the ryovm app" {
		t.Fatalf("dynamic app label = %q", got)
	}
}

func TestPieceMarkersBeginEndAndNote(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	seedPieceHistory(t, pieceHistoryEntry{Key: "shell", Label: "old shell", Took: 1200, Runs: 2})
	p := piecePublisher()

	p.activity = "before marker"

	p.observe("::piece:: begin shell carried shell label")
	v := p.currentPieces()
	if v.Step != "deploy" || v.Running != 0 || len(v.Pieces) != 1 {
		t.Fatalf("begin view = %+v", v)
	}
	if v.Pieces[0].Label != pieceLabels["shell"] || v.Pieces[0].State != stepRunning {
		t.Fatalf("begin piece = %+v", v.Pieces[0])
	}
	if p.activity != "before marker" {
		t.Fatalf("begin marker became activity: %q", p.activity)
	}

	p.observe("::piece:: note compiled against Hyprland headers")
	if got := p.currentPieces().Pieces[0].Note; got != "compiled against Hyprland headers" {
		t.Fatalf("piece note = %q", got)
	}
	p.observe("[2/4] Building shell")
	if got := p.currentPieces().Pieces[0]; got.Frac != 0.5 || got.Detail != "[2/4] Building shell" {
		t.Fatalf("piece output = %+v", got)
	}
	activity := p.activity

	p.observe("::piece:: end shell ok")
	got := p.currentPieces().Pieces[0]
	if got.State != stepDone || p.currentPieces().Running != -1 {
		t.Fatalf("ended piece = %+v", got)
	}
	if p.activity != activity {
		t.Fatalf("end marker became activity: %q", p.activity)
	}
}

func TestPieceBeginImplicitlyEndsRunningPiece(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	p := piecePublisher()
	p.observe("::piece:: begin shell shell")
	p.observe("::piece:: begin wm providers")
	v := p.currentPieces()
	if len(v.Pieces) != 2 || v.Running != 1 {
		t.Fatalf("piece view = %+v", v)
	}
	if v.Pieces[0].State != stepDone || v.Pieces[1].State != stepRunning {
		t.Fatalf("implicit settlement = %+v", v.Pieces)
	}
}

func TestPieceImplicitSettleAtStepEnd(t *testing.T) {
	for _, tc := range []struct {
		name      string
		stepState stepState
		want      stepState
	}{
		{name: "ok", stepState: stepDone, want: stepDone},
		{name: "failed", stepState: stepFailed, want: stepFailed},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("XDG_STATE_HOME", t.TempDir())
			seedPieceHistory(t,
				pieceHistoryEntry{Key: "shell", Label: "shell", Took: 1000, Runs: 1},
				pieceHistoryEntry{Key: "wm", Label: "providers", Took: 500, Runs: 1},
			)
			p := piecePublisher()
			p.observe("::piece:: begin shell shell")
			p.mu.Lock()
			settled, ok := p.settle(0, tc.stepState)
			p.mu.Unlock()
			if !ok || settled.State != tc.want {
				t.Fatalf("settled = %+v, %v; want state %q", settled, ok, tc.want)
			}
			v := p.currentPieces()
			if len(v.Pieces) != 1 || v.Pieces[0].State != tc.want {
				t.Fatalf("final pieces = %+v", v.Pieces)
			}
		})
	}
}

func TestPieceMarkersNeverBecomeActivity(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	seedPieceHistory(t, pieceHistoryEntry{Key: "shell", Label: "shell", Took: 1000, Runs: 1})
	p := piecePublisher()
	p.activity = "compiler output"
	markers := []string{
		"::piece:: begin shell shell",
		"::piece:: note a useful fact",
		"::piece:: end shell skipped",
		"::piece:: malformed marker",
	}
	for _, marker := range markers {
		p.observe(marker)
		if p.activity == marker {
			t.Fatalf("marker reached activity: %q", marker)
		}
	}
}

func TestPieceProgressNeverDecreases(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	seedPieceHistory(t, pieceHistoryEntry{Key: "blobs", Label: "blobs", Took: 1000, Runs: 1})
	p := piecePublisher()
	p.observe("::piece:: begin blobs blobs")
	p.observe("[8/10] compiling")
	p.observe("[2/10] another compiler phase")
	if got := p.currentPieces().Pieces[0].Frac; got != 0.8 {
		t.Fatalf("piece progress fell to %v, want 0.8", got)
	}
}

func TestPieceHistoryRoundTripAndBlend(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	initial := []pieceHistoryEntry{
		{Key: "shell", Label: "shell", Took: 1000, Runs: 3},
		{Key: "wm", Label: "providers", Took: 400, Runs: 1},
	}
	writePieceHistory(initial)
	if got := loadPieceHistory(); !reflect.DeepEqual(got, initial) {
		t.Fatalf("history round trip = %#v, want %#v", got, initial)
	}

	p := &publisher{
		pieces:       []piece{{Key: "shell", Label: "shell", State: stepDone, Took: 2001}},
		pieceHistory: initial,
		pieceOrder:   []string{"shell"},
	}
	p.updatePieceHistoryLocked()
	got := loadPieceHistory()
	wantTook := int64(math.Round(0.6*1000 + 0.4*2001))
	if len(got) != 2 || got[0].Took != wantTook || got[0].Runs != 4 {
		t.Fatalf("blended history = %#v, want took=%d runs=4", got, wantTook)
	}
	if got[1] != initial[1] {
		t.Fatalf("untouched history entry = %#v, want %#v", got[1], initial[1])
	}
}

func TestFailedPieceLeavesHistoryUntouched(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	initial := []pieceHistoryEntry{{Key: "shell", Label: "shell", Took: 1000, Runs: 3}}
	writePieceHistory(initial)
	p := &publisher{
		pieces:       []piece{{Key: "shell", Label: "new label", State: stepFailed, Took: 9000}},
		pieceHistory: initial,
		pieceOrder:   []string{"shell"},
	}
	p.updatePieceHistoryLocked()
	if got := loadPieceHistory(); !reflect.DeepEqual(got, initial) {
		t.Fatalf("failed piece changed history: got %#v, want %#v", got, initial)
	}
}

func TestPieceStepFractionMonotonicAndBounded(t *testing.T) {
	for _, tc := range []struct {
		name    string
		pieces  []piece
		typical int64
	}{
		{
			name: "with history",
			pieces: []piece{
				{Key: "shell", State: stepDone, Typical: 1000},
				{Key: "wm", State: stepRunning, Began: nowMs(), Frac: 0.8, Typical: 1000},
				{Key: "hub", State: stepPending, Typical: 1000},
			},
			typical: 3000,
		},
		{
			name: "without history",
			pieces: []piece{
				{Key: "shell", State: stepDone},
				{Key: "wm", State: stepRunning, Began: nowMs(), Frac: 0.8},
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := &publisher{
				steps:         []runStep{{Key: "deploy", State: stepRunning}},
				piecesStep:    "deploy",
				pieces:        tc.pieces,
				piecesTypical: tc.typical,
			}
			first := p.fraction()
			for i := range p.pieces {
				if p.pieces[i].State == stepRunning {
					p.pieces[i].Frac = 0.1
				}
			}
			second := p.fraction()
			if first < 0.02 || first > 0.97 || second < 0.02 || second > 0.97 {
				t.Fatalf("fractions out of bounds: %v then %v", first, second)
			}
			if second < first {
				t.Fatalf("fraction decreased: %v then %v", first, second)
			}
		})
	}
}

func TestCurrentPiecesReturnsCopy(t *testing.T) {
	p := &publisher{
		piecesStep:    "deploy",
		piecesTypical: 1000,
		pieces:        []piece{{Key: "shell", Label: "shell", State: stepRunning}},
	}
	v := p.currentPieces()
	v.Pieces[0].Label = "changed"
	v.Pieces = append(v.Pieces, piece{Key: "extra"})
	got := p.currentPieces()
	if len(got.Pieces) != 1 || got.Pieces[0].Label != "shell" {
		t.Fatalf("mutating view changed publisher: %+v", got)
	}
}

func TestPieceRunStateFieldsOmitUntilSet(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	p := &publisher{active: true, phase: "running", steps: []runStep{{Key: "deploy", State: stepRunning}}}
	p.write()
	b, err := os.ReadFile(runStatePath())
	if err != nil {
		t.Fatal(err)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(b, &raw); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"pieces", "piecesStep", "piecesTypical", "firstBuild"} {
		if _, ok := raw[key]; ok {
			t.Errorf("empty run-state unexpectedly contains %q", key)
		}
	}

	p.pieces = []piece{{Key: "shell", Label: "shell", State: stepRunning}}
	p.piecesStep = "deploy"
	p.piecesTypical = 1000
	p.firstBuild = true
	p.write()
	st := readRunState(t)
	if len(st.Pieces) != 1 || st.PiecesStep != "deploy" || st.PiecesTypical != 1000 || !st.FirstBuild {
		t.Fatalf("piece run-state fields = %+v", st)
	}
}
