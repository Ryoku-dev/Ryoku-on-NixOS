package wm

import (
	"net"
	"path/filepath"
	"testing"
)

// LeafScriptsDir is the single definition of where a provider's bare-name
// scripts live; deploy.sh and the switch resolve them through it, so a wrong
// or empty path silently strands a compositor's display or workspace tools.
func TestLeafScriptsDir(t *testing.T) {
	if got, want := LeafScriptsDir(ProviderHyprland), "ryoku/hyprland/scripts"; got != want {
		t.Errorf("hyprland = %q, want %q", got, want)
	}
	if got, want := LeafScriptsDir(ProviderNiri), "ryoku/niri/scripts"; got != want {
		t.Errorf("niri = %q, want %q", got, want)
	}
	if got := LeafScriptsDir(""); got != "" {
		t.Errorf("empty name = %q, want empty", got)
	}
}

func TestDetectUsesLiveSystemdManagerHandle(t *testing.T) {
	for _, key := range []string{"HYPRLAND_INSTANCE_SIGNATURE", "NIRI_SOCKET"} {
		t.Setenv(key, "")
	}
	t.Setenv("RYOKU_WM", "")
	t.Setenv("XDG_CURRENT_DESKTOP", "")

	sock := filepath.Join(t.TempDir(), "niri.sock")
	ln, err := net.Listen("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	orig := managerEnvironment
	t.Cleanup(func() { managerEnvironment = orig })
	managerEnvironment = func() map[string]string {
		return map[string]string{"NIRI_SOCKET": sock}
	}

	got := Detect()
	if got.Name != ProviderNiri || !got.Live || got.Source != "systemd:NIRI_SOCKET" {
		t.Fatalf("Detect() = %+v, want live niri from systemd manager environment", got)
	}
}
