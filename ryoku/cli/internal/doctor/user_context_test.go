package doctor

import (
	"os"
	"os/user"
	"path/filepath"
	"strings"
	"testing"

	"ryoku-cli/internal/sys"
)

func TestConfigureDoctorUserResolvesSudoUserHome(t *testing.T) {
	oldEUID, oldLookup := doctorEffectiveUID, doctorLookupUser
	oldResolved := resolvedDoctorUser
	doctorEffectiveUID = func() int { return 0 }
	doctorLookupUser = func(name string) (*user.User, error) {
		return &user.User{Username: name, Uid: "1007", Gid: "1007", HomeDir: "/home/desktop"}, nil
	}
	t.Cleanup(func() {
		doctorEffectiveUID, doctorLookupUser = oldEUID, oldLookup
		resolvedDoctorUser = oldResolved
	})

	t.Setenv("SUDO_USER", "desktop")
	t.Setenv("HOME", "")
	t.Setenv("USER", "root")
	t.Setenv("LOGNAME", "root")
	t.Setenv("XDG_CONFIG_HOME", "/root/.config")
	t.Setenv("XDG_CACHE_HOME", "/root/.cache")
	t.Setenv("XDG_DATA_HOME", "/root/.local/share")
	t.Setenv("XDG_STATE_HOME", "/root/.local/state")
	t.Setenv("XDG_RUNTIME_DIR", "")
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "")

	if err := configureDoctorUser(true); err != nil {
		t.Fatal(err)
	}
	if got := sys.Home(); got != "/home/desktop" {
		t.Fatalf("home = %q, want desktop user's home", got)
	}
	if got := sys.ConfigHome(); got != "/home/desktop/.config" {
		t.Fatalf("config home = %q, want desktop user's config", got)
	}
	if got := sys.StateDir(); got != "/home/desktop/.local/state/ryoku" {
		t.Fatalf("state dir = %q, want desktop user's state", got)
	}
	if got := filepath.Clean(os.Getenv("XDG_RUNTIME_DIR")); got != "/run/user/1007" {
		t.Fatalf("runtime dir = %q, want desktop user's runtime", got)
	}
	if got := os.Getenv("DBUS_SESSION_BUS_ADDRESS"); got != "unix:path=/run/user/1007/bus" {
		t.Fatalf("bus = %q, want desktop user's bus", got)
	}
	if got := doctorUser(); got != "desktop" {
		t.Fatalf("doctor user = %q, want desktop", got)
	}
	if account, err := doctorAccount(); err != nil || account.Username != "desktop" || account.Uid != "1007" {
		t.Fatalf("doctor account = %+v, %v; want resolved desktop uid 1007", account, err)
	}
}

func TestConfigureDoctorUserRefusesRootOwnedRepairs(t *testing.T) {
	oldEUID, oldLookup := doctorEffectiveUID, doctorLookupUser
	oldResolved := resolvedDoctorUser
	doctorEffectiveUID = func() int { return 0 }
	doctorLookupUser = func(name string) (*user.User, error) {
		return &user.User{Username: name, Uid: "1007", Gid: "1007", HomeDir: "/home/desktop"}, nil
	}
	t.Cleanup(func() {
		doctorEffectiveUID, doctorLookupUser = oldEUID, oldLookup
		resolvedDoctorUser = oldResolved
	})
	t.Setenv("SUDO_USER", "desktop")
	t.Setenv("HOME", "/root")

	err := configureDoctorUser(false)
	if err == nil || !strings.Contains(err.Error(), "without sudo") {
		t.Fatalf("repairing sudo doctor error = %v, want run-without-sudo guidance", err)
	}
}

func TestConfigureDoctorUserRefusesRootShell(t *testing.T) {
	oldEUID := doctorEffectiveUID
	oldResolved := resolvedDoctorUser
	doctorEffectiveUID = func() int { return 0 }
	t.Cleanup(func() {
		doctorEffectiveUID = oldEUID
		resolvedDoctorUser = oldResolved
	})
	t.Setenv("SUDO_USER", "")

	err := configureDoctorUser(false)
	if err == nil || !strings.Contains(err.Error(), "desktop user account") ||
		!strings.Contains(err.Error(), "asks for sudo") {
		t.Fatalf("root-shell doctor error = %v, want normal-user guidance", err)
	}
}
