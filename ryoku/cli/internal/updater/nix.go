package updater

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"ryoku-cli/internal/sys"
)

var nixSteps = []runStep{
	{Key: "resolve", Label: "Checking Ryoku for NixOS"},
	{Key: "generation", Label: "Building the Ryoku generation"},
	{Key: "finalize", Label: "Finishing up"},
}

func nixBackend() bool {
	return sys.NixBackend()
}

func nixVersion() string {
	return strings.TrimSpace(os.Getenv("RYOKU_NIX_VERSION"))
}

func nixChannel() string {
	if ch := strings.TrimSpace(os.Getenv("RYOKU_NIX_CHANNEL")); ch != "" {
		return ch
	}
	return "nix"
}

func nixStatus() statusReport {
	fallback := statusReport{
		Installed: nixVersion(),
		Latest:    nixVersion(),
		Updates:   []updateItem{},
		Recent: []updateItem{
			{
				Name: "Ryoku for NixOS",
				New:  nixVersion(),
			},
		},
		Channel:   nixChannel(),
		Packages:  []updateItem{},
		Backend:   "nix",
		CanUpdate: false,
	}

	out, err := sys.RunOut(
		"ryoku-nix-update",
		"status",
		"--json",
	)
	if err != nil || strings.TrimSpace(out) == "" {
		return fallback
	}

	var report statusReport
	if err := json.Unmarshal([]byte(out), &report); err != nil {
		return fallback
	}

	report.Backend = "nix"

	if report.Updates == nil {
		report.Updates = []updateItem{}
	}
	if report.Recent == nil {
		report.Recent = []updateItem{}
	}
	if report.Packages == nil {
		report.Packages = []updateItem{}
	}

	return report
}

func nixUpdate() error {
	progress.begin(nixSteps)

	progress.at("resolve")
	progress.logf("Checking the Ryoku Nix update channel")

	// A Hub-driven update runs inside a detached PTY. Prime sudo through the
	// Hub's secret prompt before the Nix helper starts, otherwise a password
	// prompt from nixos-rebuild is invisible and the Updates page appears hung.
	if updateUI() == "hub" {
		if err := authorizeGUI(); err != nil {
			progress.fail(err)
			return err
		}
	}

	progress.at("generation")
	progress.logf("Updating the Ryoku Nix source")

	if err := sys.Run("ryoku-nix-update", "update"); err != nil {
		e := fmt.Errorf("Ryoku Nix update failed: %w", err)
		progress.fail(e)
		return e
	}

	progress.at("finalize")
	progress.logf("Ryoku for NixOS update complete")

	return finishRun()
}

func NixTrack(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("usage: ryoku track <stable|unstable>")
	}

	channel := strings.TrimSpace(args[0])

	switch channel {
	case "stable", "main":
		channel = "stable"
	case "unstable", "unstable-dev":
		channel = "unstable"
	default:
		return fmt.Errorf(
			"unknown NixOS channel %q (use: stable or unstable)",
			channel,
		)
	}

	return sys.Run(
		"ryoku-nix-update",
		"track",
		channel,
	)
}
