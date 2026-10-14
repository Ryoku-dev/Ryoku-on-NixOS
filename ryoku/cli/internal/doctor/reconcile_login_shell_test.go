package doctor

import (
	"os"
	"os/user"
	"path/filepath"
	"strings"
	"testing"
)

// lsHome writes a desktop.json carrying the given desktop.env array and points
// XDG at it, returning the store path.
func lsHome(t *testing.T, env string) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	dir := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	store := filepath.Join(dir, "desktop.json")
	body := `{"desktop":{"env":` + env + `,"cursor":{"theme":"Bibata"}}}`
	if err := os.WriteFile(store, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return store
}

func stubAccountShell(t *testing.T, path string) {
	t.Helper()
	orig := accountLoginShell
	accountLoginShell = func() string { return path }
	t.Cleanup(func() { accountLoginShell = orig })
}

func stubSessionSync(t *testing.T) *[]string {
	t.Helper()
	var got []string
	orig := syncSessionShellEnv
	syncSessionShellEnv = func(path string) { got = append(got, path) }
	t.Cleanup(func() { syncSessionShellEnv = orig })
	return &got
}

func TestAccountLoginShellUsesResolvedSudoUser(t *testing.T) {
	oldEUID, oldLookup := doctorEffectiveUID, doctorLookupUser
	oldResolved, oldPasswd := resolvedDoctorUser, accountPasswdPath
	doctorEffectiveUID = func() int { return 0 }
	doctorLookupUser = func(name string) (*user.User, error) {
		return &user.User{Username: name, Uid: "1007", HomeDir: "/home/desktop"}, nil
	}
	t.Cleanup(func() {
		doctorEffectiveUID, doctorLookupUser = oldEUID, oldLookup
		resolvedDoctorUser, accountPasswdPath = oldResolved, oldPasswd
	})

	passwd := filepath.Join(t.TempDir(), "passwd")
	if err := os.WriteFile(passwd, []byte("root:x:0:0:root:/root:/bin/bash\ndesktop:x:1007:1007::/home/desktop:/usr/bin/zsh\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	accountPasswdPath = passwd
	t.Setenv("SUDO_USER", "desktop")
	t.Setenv("HOME", "/root")
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
	if got := accountLoginShell(); got != "/usr/bin/zsh" {
		t.Fatalf("account shell = %q, want sudo user's zsh", got)
	}
}

// When the override already mirrors the account shell there is nothing to do,
// and the clean line names the shell.
func TestLoginShellAgrees(t *testing.T) {
	lsHome(t, `[{"key":"SHELL","value":"/usr/bin/fish"}]`)
	stubAccountShell(t, "/usr/bin/fish")
	synced := stubSessionSync(t)

	r := reconcileLoginShell(true)
	if r.status != recOK {
		t.Fatalf("status=%s detail=%q, want ok", r.status.label(), r.detail)
	}
	if !strings.Contains(r.detail, "fish") {
		t.Errorf("clean report should name the shell: %q", r.detail)
	}
	if len(*synced) != 0 {
		t.Errorf("agreement must not refresh the session env: %v", *synced)
	}
}

// The drift the live box shows: account fish, override zsh. Check names both and
// changes nothing; repair aligns the override, refreshes the session, keeps the
// other env pair, and a second check is clean.
func TestLoginShellDriftRepaired(t *testing.T) {
	store := lsHome(t, `[{"key":"SHELL","value":"/usr/bin/zsh"},{"key":"EDITOR","value":"nvim"}]`)
	stubAccountShell(t, "/usr/bin/fish")
	synced := stubSessionSync(t)

	r := reconcileLoginShell(true)
	if r.status != recWouldFix {
		t.Fatalf("check: status=%s detail=%q, want todo", r.status.label(), r.detail)
	}
	if !strings.Contains(r.detail, "fish") || !strings.Contains(r.detail, "zsh") {
		t.Errorf("drift report must name both shells: %q", r.detail)
	}
	if v, _ := storeShellOverride(readFileSafe(store)); v != "/usr/bin/zsh" {
		t.Errorf("check-only rewrote the override to %q", v)
	}
	if len(*synced) != 0 {
		t.Errorf("check-only must not refresh the session: %v", *synced)
	}

	r = reconcileLoginShell(false)
	if r.status != recFixed {
		t.Fatalf("repair: status=%s detail=%q, want fixed", r.status.label(), r.detail)
	}
	raw := readFileSafe(store)
	if v, ok := storeShellOverride(raw); !ok || v != "/usr/bin/fish" {
		t.Fatalf("override should align to the account shell, got %q present=%v", v, ok)
	}
	if !strings.Contains(raw, "nvim") {
		t.Errorf("repair dropped an unrelated env pair: %s", raw)
	}
	if len(*synced) != 1 || (*synced)[0] != "/usr/bin/fish" {
		t.Fatalf("repair must refresh the session with the account shell, got %v", *synced)
	}

	if r := reconcileLoginShell(true); r.status != recOK {
		t.Fatalf("idempotent second run: status=%s detail=%q, want ok", r.status.label(), r.detail)
	}
}

// No SHELL override is unset, not drift: the session inherits the account shell.
// It must never be reported as a problem nor invented into an explicit pair.
func TestLoginShellNoOverrideIsNotDrift(t *testing.T) {
	store := lsHome(t, `[{"key":"EDITOR","value":"nvim"}]`)
	stubAccountShell(t, "/usr/bin/fish")
	synced := stubSessionSync(t)

	if r := reconcileLoginShell(true); r.status != recOK {
		t.Fatalf("check: status=%s detail=%q, want ok (unset is not drift)", r.status.label(), r.detail)
	}
	if r := reconcileLoginShell(false); r.status != recOK {
		t.Fatalf("repair: status=%s detail=%q, want ok", r.status.label(), r.detail)
	}
	if _, ok := storeShellOverride(readFileSafe(store)); ok {
		t.Error("an absent SHELL override must be left absent, not created")
	}
	if len(*synced) != 0 {
		t.Errorf("no drift means no session refresh: %v", *synced)
	}
}

// The rewrite touches only the SHELL value; every other env pair and store key
// survives.
func TestSetStoreShellOverrideLeavesOtherStateAlone(t *testing.T) {
	raw := `{"desktop":{"env":[{"key":"SHELL","value":"/usr/bin/zsh"},{"key":"EDITOR","value":"nvim"}],"cursor":{"theme":"Bibata"}}}`
	out, err := setStoreShellOverride(raw, "/usr/bin/fish")
	if err != nil {
		t.Fatal(err)
	}
	if v, ok := storeShellOverride(out); !ok || v != "/usr/bin/fish" {
		t.Fatalf("override = %q present=%v, want /usr/bin/fish true", v, ok)
	}
	for _, keep := range []string{`"EDITOR"`, `"nvim"`, `"Bibata"`} {
		if !strings.Contains(out, keep) {
			t.Errorf("rewrite dropped %s: %s", keep, out)
		}
	}
}
