package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	wm "ryoku-wm"
)

// outputs is the write half of the display seam for Hyprland: it renders the
// neutral output layout the editor built into the spec ryoku-monitor applies,
// which is the one place the DPI ladder, scale snapping and CVT-modeline forcing
// live. ryoku-monitor writes monitors.lua and pushes the layout live through
// hl.monitor, so the compositor needs no reload after.

// monitorSpec is one entry of the layout ryoku-monitor's `apply` reads. Mirror
// and the colour pipeline (cm + sdrbrightness) are the CapOutputMirror /
// CapOutputHdr leaves of OutputLayout, mapped straight through so the page's
// mirror and HDR controls drive the path they always did.
type monitorSpec struct {
	Output        string  `json:"output"`
	Mode          string  `json:"mode"`
	Position      string  `json:"position"`
	Scale         float64 `json:"scale"`
	Transform     int     `json:"transform"`
	VRR           int     `json:"vrr"`
	Mirror        string  `json:"mirror"`
	Cm            string  `json:"cm"`
	SdrBrightness float64 `json:"sdrbrightness"`
	Disabled      bool    `json:"disabled"`
}

func runOutputs(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("outputs: missing layout path")
	}
	raw, err := os.ReadFile(args[0])
	if err != nil {
		return err
	}
	var layout []wm.OutputLayout
	if err := json.Unmarshal(raw, &layout); err != nil {
		return fmt.Errorf("outputs: %w", err)
	}

	body, err := json.Marshal(layoutToSpecs(layout))
	if err != nil {
		return err
	}
	if err := runMonitor("apply", string(body)); err != nil {
		return err
	}

	rep := wm.ApplyReport{
		Provider:     wm.ProviderHyprland,
		Written:      []string{filepath.Join(hyprConfigDir(), "monitors.lua")},
		ReloadNeeded: false,
	}
	enc := json.NewEncoder(stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(rep)
}

// layoutToSpecs maps the neutral layout onto the spec ryoku-monitor reads. An
// empty mode becomes preferred, a zero scale becomes 1 and a bool VRR becomes
// ryoku-monitor's 0/1, so an output the editor left on auto still applies rather
// than sending a value ryoku-monitor would reject. Disabled outputs keep their
// complete layout because the hotplug guard may need to enable one temporarily.
func layoutToSpecs(layout []wm.OutputLayout) []monitorSpec {
	specs := make([]monitorSpec, 0, len(layout))
	for _, o := range layout {
		if o.Name == "" {
			continue
		}
		specs = append(specs, monitorSpec{
			Output:        o.Name,
			Mode:          modeOrPreferred(o.Mode),
			Position:      fmt.Sprintf("%dx%d", o.X, o.Y),
			Scale:         scaleOrOne(o.Scale),
			Transform:     o.Transform,
			VRR:           boolToInt(o.VRR),
			Mirror:        o.Mirror,
			Cm:            o.ColorMode,
			SdrBrightness: sdrOrOne(o.SdrBrightness),
			Disabled:      !o.Enabled,
		})
	}
	return specs
}

// modeOrPreferred maps an empty mode onto ryoku-monitor's automatic mode, so an
// output the editor left on auto comes up at its best available mode.
func modeOrPreferred(mode string) string {
	if mode == "" {
		return "preferred"
	}
	return mode
}

// scaleOrOne keeps a zero (automatic) scale at 1, the safe default Hyprland
// accepts for any mode; ryoku-monitor then snaps a real value to the valid ladder.
func scaleOrOne(scale float64) float64 {
	if scale <= 0 {
		return 1
	}
	return scale
}

// sdrOrOne keeps a zero SDR brightness at 1x: ryoku-monitor only honours it in
// HDR, and 1x is the neutral value that leaves SDR content untouched.
func sdrOrOne(v float64) float64 {
	if v <= 0 {
		return 1
	}
	return v
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

// runMonitor drives ryoku-monitor, the Hyprland display engine, discarding its
// stdout so its progress line never mixes with the JSON report the seam prints.
func runMonitor(args ...string) error {
	cmd := exec.Command("ryoku-monitor", args...)
	var stderr bytes.Buffer
	cmd.Stdout = io.Discard
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return fmt.Errorf("ryoku-monitor apply: %w: %s", err, msg)
		}
		return fmt.Errorf("ryoku-monitor apply: %w", err)
	}
	return nil
}
