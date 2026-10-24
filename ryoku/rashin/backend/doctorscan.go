package main

import (
	"context"
	"encoding/json"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// doctorscan.go runs Ryoku's own health check (`ryoku doctor --json`, read-only)
// for the dashboard's Doctor tab and for Fix with AI. The findings are the
// doctor's, not Rashin's guesses: the dashboard only shows them and hands them
// to the agent.

// DoctorFinding is one reconciler result, the shape `ryoku doctor --json` emits.
type DoctorFinding struct {
	Name   string `json:"name"`
	Status string `json:"status"` // ok, note, fixed, todo, warn, fail
	Detail string `json:"detail"`
	Remedy string `json:"remedy,omitempty"`
}

// DoctorScan is one health-check run.
type DoctorScan struct {
	Findings    []DoctorFinding `json:"findings"`
	CollectedAt time.Time       `json:"collectedAt"`
	Report      string          `json:"report,omitempty"` // the saved report, when doctor wrote one
	Error       string          `json:"error,omitempty"`
}

// Issues are the findings that need a human or an agent: everything doctor
// could not settle on its own.
func (s DoctorScan) Issues() []DoctorFinding {
	var out []DoctorFinding
	for _, f := range s.Findings {
		if doctorNeedsAttention(f.Status) {
			out = append(out, f)
		}
	}
	return out
}

func doctorNeedsAttention(status string) bool {
	switch status {
	case "todo", "warn", "fail":
		return true
	}
	return false
}

// doctorTTL keeps the tab quick: a run takes several seconds, and the machine
// rarely changes under the user between two looks.
const doctorTTL = 2 * time.Minute

var doctorCache struct {
	run  sync.Mutex // one run at a time; a second caller waits and reuses it
	mu   sync.Mutex
	scan *DoctorScan
}

// DoctorNow returns a recent scan, running the check when there is none, it
// aged out, or force asks for a fresh one.
func DoctorNow(force bool) DoctorScan {
	doctorCache.run.Lock()
	defer doctorCache.run.Unlock()
	doctorCache.mu.Lock()
	cached := doctorCache.scan
	doctorCache.mu.Unlock()
	if cached != nil && !force && time.Since(cached.CollectedAt) < doctorTTL {
		return *cached
	}
	scan := runDoctorScan()
	doctorCache.mu.Lock()
	doctorCache.scan = &scan
	doctorCache.mu.Unlock()
	return scan
}

func runDoctorScan() DoctorScan {
	scan := DoctorScan{CollectedAt: time.Now(), Report: doctorReportPath()}
	bin, err := exec.LookPath("ryoku")
	if err != nil {
		scan.Error = "the ryoku command is not installed"
		return scan
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, bin, "doctor", "--json").Output()
	if jerr := json.Unmarshal(out, &scan.Findings); jerr != nil {
		if err == nil {
			err = jerr
		}
		scan.Error = "ryoku doctor did not answer: " + strings.TrimSpace(err.Error())
	}
	if !fileExists(scan.Report) {
		scan.Report = ""
	}
	return scan
}

// doctorReportPath is where `ryoku doctor` saves its shareable report whenever
// it finds something it cannot fix (system state and recent error logs).
func doctorReportPath() string {
	return filepath.Join(stateHome(), "ryoku", "doctor-report.txt")
}
