package main

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// fix.go turns something the machine already knows is wrong (a dashboard tip,
// a doctor finding, or "app X broke") into a Fix with AI repair: a one-line
// display of the problem plus a brief on the problem and on how to work on
// this machine, which together open the user's agent harness (fixterm.go).

// fixRequest is the body of POST /api/fix and the CLI's parsed arguments.
type fixRequest struct {
	Kind string `json:"kind"` // tip, doctor, app
	ID   string `json:"id,omitempty"`
	Name string `json:"name,omitempty"`
	App  string `json:"app,omitempty"`
	Note string `json:"note,omitempty"`
}

// fixMethod is how every Fix with AI session is asked to work, whatever the
// problem: evidence first, the machine's own tools, the user in control.
const fixMethod = "How to work: investigate before you change anything, and gather the evidence yourself. " +
	"`ryoku-rashin logs <app or component>` pulls the journal, crash dumps, the app's own log files and recent package changes in one call, " +
	"and logs.md in the vault says where everything else lives. " +
	"Before you edit any file run `ryoku owner <path>`: never edit what it calls Ryoku-owned, generated, or a tool store; edit where it points instead. " +
	"Prefer Ryoku's own commands and reversible steps, and ask before anything destructive or anything that needs sudo. " +
	"Explain the cause in plain words, say what you will do, do it, then check that it worked and say how to undo it. " +
	"If nothing needs fixing, say so and stop. Write what you found and did to the vault journal (journal/YYYY-MM-DD.md)."

func fixTipBrief(t Tip) (display, brief string) {
	display = "Fix with AI: " + t.Title
	var b strings.Builder
	b.WriteString("The user pressed Fix with AI on a tip from Rashin's system scan. ")
	fmt.Fprintf(&b, "Tip (%s): %s. ", t.Severity, t.Title)
	fmt.Fprintf(&b, "What the scan saw: %s ", strings.TrimSpace(t.Detail))
	if t.Command != "" {
		fmt.Fprintf(&b, "The scan's suggested first look: `%s`. ", t.Command)
	}
	b.WriteString(fixMethod)
	return display, b.String()
}

func fixDoctorBrief(issues []DoctorFinding, report string) (display, brief string) {
	if len(issues) == 1 {
		display = "Fix with AI: " + issues[0].Name
	} else {
		display = "Fix with AI: the health check found " + strconv.Itoa(len(issues)) + " issues"
	}
	var b strings.Builder
	b.WriteString("The user pressed Fix with AI on Ryoku's health check (`ryoku doctor`). Findings that need attention:\n")
	for _, f := range issues {
		fmt.Fprintf(&b, "- %s, %s: %s", f.Status, f.Name, strings.TrimSpace(f.Detail))
		if f.Remedy != "" {
			fmt.Fprintf(&b, " (doctor suggests: %s)", f.Remedy)
		}
		b.WriteString("\n")
	}
	b.WriteString("A todo is something `ryoku doctor` applies on its own when run without flags; a warn or fail needs a person. " +
		"`ryoku doctor --check` reruns the checks without changing anything. ")
	if report != "" {
		fmt.Fprintf(&b, "Doctor's last full report (system state and recent error logs) is at %s. ", report)
	}
	b.WriteString("Work through the findings one at a time, most serious first. ")
	b.WriteString(fixMethod)
	return display, b.String()
}

func fixAppBrief(app, note string) (display, brief string) {
	display = "Fix with AI: " + app
	if note != "" {
		display += ": " + clipRunes(note, 140)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "The user says %s is broken", app)
	if note != "" {
		fmt.Fprintf(&b, ", in their words: %q", note)
	}
	fmt.Fprintf(&b, ". Start with `ryoku-rashin logs %s` and read what it finds before asking the user anything they have not already told you. ", app)
	b.WriteString(fixMethod)
	return display, b.String()
}

// appName is what `fix app` and `logs` accept: a program, unit, or component
// name, never a path or a shell fragment.
var appName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._+@-]{0,63}$`)

const maxFixNote = 2000

// clipRunes shortens s to n characters without splitting one.
func clipRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return strings.TrimSpace(string(r[:n])) + "…"
}

// buildFix resolves a request against what the machine reports right now.
func buildFix(req fixRequest) (display, brief string, err error) {
	switch req.Kind {
	case "tip":
		for _, t := range SystemNow().Tips {
			if t.ID == req.ID {
				display, brief = fixTipBrief(t)
				return display, brief, nil
			}
		}
		return "", "", errors.New("that tip is gone; rescan and try again")
	case "doctor":
		scan := DoctorNow(false)
		if scan.Error != "" {
			return "", "", errors.New(scan.Error)
		}
		issues := scan.Issues()
		if req.Name != "" {
			var one []DoctorFinding
			for _, f := range issues {
				if f.Name == req.Name {
					one = append(one, f)
				}
			}
			issues = one
		}
		if len(issues) == 0 {
			return "", "", errors.New("the health check has nothing left to fix")
		}
		display, brief = fixDoctorBrief(issues, scan.Report)
		return display, brief, nil
	case "app":
		if !appName.MatchString(req.App) {
			return "", "", errors.New("name the app, component, or unit that broke")
		}
		note := strings.TrimSpace(req.Note)
		if len(note) > maxFixNote {
			note = note[:maxFixNote]
		}
		display, brief = fixAppBrief(req.App, note)
		return display, brief, nil
	}
	return "", "", errors.New("unknown fix kind: " + req.Kind)
}
