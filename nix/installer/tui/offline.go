package main

import (
	"fmt"
	"os"

	tea "charm.land/bubbletea/v2"
)

func isoOffline() bool { return os.Getenv("RYOKU_INSTALL_OFFLINE") != "" }

func isoStepForMode(step isoStep) isoStep {
	if isoOffline() && step.key == "network" {
		step.title = "Installation media"
		step.desc = "This standalone image installs using its local payload, with network access disabled."
	}
	return step
}

func isoCheckMediaCmd() tea.Cmd {
	return func() tea.Msg {
		path := os.Getenv("RYOKU_INSTALL_OFFLINE")
		info, err := os.Stat(path)
		if err != nil {
			return isoNetworkMsg{err: fmt.Errorf("offline source payload unavailable: %w", err)}
		}
		if !info.IsDir() {
			return isoNetworkMsg{err: fmt.Errorf("offline source payload is not a directory")}
		}
		return isoNetworkMsg{online: true}
	}
}

func (m isoModel) offlineMediaBody() string {
	if !m.netChecked {
		return fg(cSub, "Checking the offline installation payload…")
	}
	if !m.netOnline {
		return bold(cRed, "Offline payload unavailable") + "\n\n" +
			fg(cSub, "Rebuild the standalone ISO. Network setup cannot repair missing media content. Press q to quit.")
	}
	return bold(cGreen, checkGlyph()+"  Offline media ready") + "\n\n" +
		fg(cSub, "Continue through the same guided installer. Packages come from this image; no connection is required.")
}

func isoMinimalChoices(key string) []choice {
	switch key {
	case "kernel":
		return []choice{{"latest", "Latest", "the only kernel included in this image"}}
	case "compositor":
		return []choice{{"niri", "niri", "the only installed compositor"}}
	case "browser":
		return []choice{{"firefox", "Firefox", "the only included browser"}}
	case "shell":
		return []choice{{"fish", "Fish", "base interactive shell"}}
	case "configuration":
		return []choice{{"ryoku", "Minimal Ryoku configuration", "niri · Firefox · latest kernel · no optional apps"}}
	}
	return nil
}
