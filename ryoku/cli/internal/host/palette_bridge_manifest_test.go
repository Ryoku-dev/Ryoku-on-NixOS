package host

import (
	"path/filepath"
	"testing"
)

func TestSystemdPaletteBridgeOnDemandPreservesManualActivation(t *testing.T) {
	fixture := newSystemdManifestFixture(t, "ryoku-palette-bridge\tuser\ton-demand\tryoku-palette-bridge.service\tryoku-palette-bridge\tpreserve\n", nil)
	touchFixture(t, filepath.Join(fixture.userUnits, "ryoku-palette-bridge.service"))
	if code := fixture.app.Service([]string{"reconcile", "--user"}); code != ExitOK {
		t.Fatalf("reconcile = %d", code)
	}
	if got := manifestCommandLines(fixture.runner); got != "" {
		t.Fatalf("on-demand reconcile changed service: %s", got)
	}
	if code := fixture.app.Service([]string{"--user", "enable", "--now", "ryoku-palette-bridge.service"}); code != ExitOK {
		t.Fatalf("manual enable = %d", code)
	}
	if got := manifestCommandLines(fixture.runner); got != "systemctl --user enable --now ryoku-palette-bridge.service" {
		t.Fatalf("manual enable commands = %s", got)
	}
	fixture.runner.commands = nil
	if code := fixture.app.Service([]string{"reconcile", "--user"}); code != ExitOK {
		t.Fatalf("reconcile after manual enable = %d", code)
	}
	if got := manifestCommandLines(fixture.runner); got != "" {
		t.Fatalf("on-demand reconcile changed opted-in service: %s", got)
	}
}
