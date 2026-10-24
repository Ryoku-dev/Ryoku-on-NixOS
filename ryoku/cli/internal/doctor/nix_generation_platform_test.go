package doctor

import (
	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
	"testing"
)

func TestNixPlatformReconcilersPreserveGenerationAndSkipArchMutations(t *testing.T) {
	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")
	present := map[string]bool{}
	for _, r := range platformReconcilers() {
		present[r.name] = true
	}
	if !present[i18n.T("NixOS generation integrity")] {
		t.Fatal("missing generation integrity check")
	}
	for _, name := range []string{
		i18n.T("limine boot entry"), i18n.T("pacman database lock"),
		i18n.T("NVIDIA update guard hook"), pendingConfigCheckName(),
		i18n.T("orphaned packages"),
	} {
		if present[name] {
			t.Fatalf("NixOS must skip %q", name)
		}
	}
	if !sys.NixBackend() {
		t.Fatal("backend unexpectedly disabled")
	}
}
