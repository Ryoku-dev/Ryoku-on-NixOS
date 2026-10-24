package main

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// wlr-randr speaks the wlr-output-management-v1 protocol mango serves
// (verified in src/main.c). IPC carries none of the advertised modes, transform
// or EDID make/model.
type randrReadState uint8

const (
	randrUnavailable randrReadState = iota
	randrParsed
)

type randrRead struct {
	state randrReadState
	text  string
}

type randrOutput struct {
	x, y, transform int
	enabled         bool
	mode            string
	modes           []string
	make, model     string
	physicalWidth   int
}

var runRandr = func() ([]byte, error) {
	return exec.Command("wlr-randr").Output()
}

// A successful but empty parse is distinct from an unavailable client. The
// display state can then keep mango's IPC geometry without pretending the
// output-management query succeeded.
func readRandr() randrRead {
	out, err := runRandr()
	if err != nil {
		return randrRead{state: randrUnavailable}
	}
	return randrRead{state: randrParsed, text: string(out)}
}

func (r randrRead) detail(name string) (randrOutput, bool) {
	if r.state != randrParsed {
		return randrOutput{}, false
	}
	return parseRandr(r.text, name)
}

// parseRandr walks wlr-randr's output block for one named output: a header
// line `NAME "make" "model"`, then indented `Enabled:`, `Position: x,y`,
// `Transform:` and `Modes:` rows with `WxH px, Hz (current)` entries.

func randrHeaderIdentity(raw, name string) (string, string) {
	rest := strings.TrimSpace(strings.TrimPrefix(raw, name))
	parts := make([]string, 0, 2)

	for strings.HasPrefix(rest, `"`) {
		end := -1
		escaped := false
		for i := 1; i < len(rest); i++ {
			switch {
			case rest[i] == '"' && !escaped:
				end = i
			case rest[i] == '\\' && !escaped:
				escaped = true
			default:
				escaped = false
			}
			if end >= 0 {
				break
			}
		}
		if end < 0 {
			break
		}
		value, err := strconv.Unquote(rest[:end+1])
		if err != nil {
			break
		}
		parts = append(parts, value)
		rest = strings.TrimSpace(rest[end+1:])
	}

	switch len(parts) {
	case 0:
		return "", ""
	case 1:
		return "", parts[0]
	default:
		return parts[0], strings.Join(parts[1:], " ")
	}
}

func parseRandr(text, name string) (randrOutput, bool) {
	var cur randrOutput
	have, inBlock, inModes := false, false, false
	for _, raw := range strings.Split(text, "\n") {
		if raw == "" {
			continue
		}
		if !strings.HasPrefix(raw, " ") && !strings.HasPrefix(raw, "\t") {
			fields := strings.Fields(raw)
			inBlock = len(fields) > 0 && fields[0] == name
			inModes = false
			if inBlock {
				have = true
				cur = randrOutput{enabled: true}
				cur.make, cur.model = randrHeaderIdentity(raw, name)
			}
			continue
		}
		if !inBlock {
			continue
		}
		trimmed := strings.TrimSpace(raw)
		if trimmed == "Modes:" {
			inModes = true
			continue
		}
		if inModes {
			if mode, ok := parseRandrMode(trimmed); ok {
				cur.modes = append(cur.modes, mode)
				if strings.Contains(trimmed, "(current") {
					cur.mode = mode
				}
				continue
			}
			inModes = false
		}
		k, v, ok := strings.Cut(trimmed, ":")
		if !ok {
			continue
		}
		val := strings.TrimSpace(v)
		switch k {
		case "Make":
			cur.make = val

		case "Model":
			cur.model = val

		case "Physical size":
			size := strings.Fields(val)
			if len(size) > 0 {
				if w, _, ok := strings.Cut(size[0], "x"); ok {
					cur.physicalWidth, _ = strconv.Atoi(w)
				}
			}

		case "Enabled":
			cur.enabled = val == "yes"
		case "Position":
			xy := strings.Split(val, ",")
			if len(xy) == 2 {
				cur.x, _ = strconv.Atoi(strings.TrimSpace(xy[0]))
				cur.y, _ = strconv.Atoi(strings.TrimSpace(xy[1]))
			}
		case "Transform":
			cur.transform = waylandTransformName(val)
		}
	}
	return cur, have
}

func parseRandrMode(line string) (string, bool) {
	fields := strings.Fields(line)
	if len(fields) < 4 || fields[1] != "px," || fields[3] != "Hz" {
		return "", false
	}
	width, height, ok := strings.Cut(fields[0], "x")
	if !ok {
		return "", false
	}
	w, werr := strconv.Atoi(width)
	h, herr := strconv.Atoi(height)
	hz, hzerr := strconv.ParseFloat(fields[2], 64)
	if werr != nil || herr != nil || hzerr != nil || w <= 0 || h <= 0 || hz <= 0 {
		return "", false
	}
	return fields[0] + "@" + strconv.FormatFloat(hz, 'f', -1, 64), true
}

// waylandTransformName folds wlr-randr's spelling ("normal", "_90",
// "flipped-90", …) to the wayland transform integer the neutral Output carries.
// An unknown name reads as normal, the safe default.
func waylandTransformName(s string) int {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "_90", "90", "0_90":
		return 1
	case "_180", "180", "0_180":
		return 2
	case "_270", "270", "0_270":
		return 3
	case "flipped", "flipped_0":
		return 4
	case "flipped-90", "flipped_90":
		return 5
	case "flipped-180", "flipped_180":
		return 6
	case "flipped-270", "flipped_270":
		return 7
	}
	return 0
}

// fileExists is the provider's one stat helper, a var so a sandbox test can
// fake a tree without a filesystem.
var fileExists = func(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
