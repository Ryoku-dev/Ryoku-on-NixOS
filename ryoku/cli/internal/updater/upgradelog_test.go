package updater

import (
	"os"
	"strings"
	"testing"
)

func TestConflictPath(t *testing.T) {
	cases := map[string]string{
		"noto-fonts: /usr/share/fontconfig/conf.avail/46-noto-sans.conf exists in filesystem":          "/usr/share/fontconfig/conf.avail/46-noto-sans.conf",
		"ryoku-desktop: /usr/lib/systemd/system/ryoku-network-kill-guard.service exists in filesystem": "/usr/lib/systemd/system/ryoku-network-kill-guard.service",
		"foo: /a/b exists in filesystem (owned by bar)":                                                "/a/b",
		" downloading...": "",
		"error: failed to commit transaction (conflicting files)": "",
		":: Proceed with installation? [Y/n]":                     "",
	}
	for line, want := range cases {
		if got := conflictPath(line); got != want {
			t.Errorf("conflictPath(%q) = %q, want %q", line, got, want)
		}
	}
}

// A failed transaction hands back what the healing retry needs: the conflict
// paths pacman named, and its own error lines in the returned error instead of
// a bare "exit status 1".
func TestTransactionCollectsConflictsAndReasons(t *testing.T) {
	oldInhibit := sleepInhibitOK
	sleepInhibitOK = func() bool { return false }
	t.Cleanup(func() { sleepInhibitOK = oldInhibit })

	devnull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		t.Skip(err)
	}
	keep := os.Stdout
	os.Stdout = devnull
	script := `printf '%s\n' '(1/2) upgrading ryoku' 'ryoku-desktop: /usr/share/plymouth/themes/ryoku/bullet.png exists in filesystem' 'error: failed to commit transaction (conflicting files)' 'error: failed to commit transaction (conflicting files)'; exit 1`
	conflicts, err := runUpgradeCollecting("test", []string{"bash", "-c", script})
	os.Stdout = keep
	devnull.Close()

	if len(conflicts) != 1 || conflicts[0] != "/usr/share/plymouth/themes/ryoku/bullet.png" {
		t.Errorf("conflicts = %q, want the one pacman conflict path", conflicts)
	}
	if err == nil || strings.Count(err.Error(), "failed to commit transaction") != 1 {
		t.Errorf("error = %v, want pacman's reason exactly once", err)
	}
}

// A refused transaction names its culprit in the returned error, which is all
// the Hub's failure card shows. The pair pacman prints twice is reported once,
// and a package name never sends the healing down the database path (#271).
func TestTransactionErrorNamesTheConflict(t *testing.T) {
	oldInhibit := sleepInhibitOK
	sleepInhibitOK = func() bool { return false }
	t.Cleanup(func() { sleepInhibitOK = oldInhibit })

	devnull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		t.Skip(err)
	}
	keep := os.Stdout
	os.Stdout = devnull
	script := `printf '%s\n' ':: limine-mkinitcpio-hook-1.37.1-1 and limine-entry-tool-1.40.0-1 are in conflict. Remove limine-entry-tool? [y/N] error: unresolvable package conflicts detected' 'error: failed to prepare transaction (conflicting dependencies)' '' ':: limine-mkinitcpio-hook-1.37.1-1 and limine-entry-tool-1.40.0-1 are in conflict' ":: unable to satisfy dependency 'python-databases' required by ryoku-rashin"; exit 1`
	_, err = runUpgradeCollecting("test", []string{"bash", "-c", script})
	os.Stdout = keep
	devnull.Close()

	want := "failed to prepare transaction (conflicting dependencies); limine-mkinitcpio-hook-1.37.1-1 and limine-entry-tool-1.40.0-1 are in conflict; unable to satisfy dependency 'python-databases' required by ryoku-rashin: exit status 1"
	if err == nil || err.Error() != want {
		t.Fatalf("error = %v\nwant %s", err, want)
	}
	if dbRejection(err) {
		t.Fatal("a dependency naming python-databases was read as a database rejection")
	}
}

func TestVoidInhibitorUsesHostSeam(t *testing.T) {
	oldInhibit := sleepInhibitOK
	sleepInhibitOK = func() bool { return true }
	t.Cleanup(func() { sleepInhibitOK = oldInhibit })
	t.Setenv("RYOKU_HOST_INIT", "runit")

	got := strings.Join(inhibited("package update", []string{"xbps-install", "-Syu"}), " ")
	want := "ryoku-host inhibit --what=sleep:idle --who=ryoku update --why=package update --mode=block xbps-install -Syu"
	if got != want || strings.Contains(got, "systemd") {
		t.Fatalf("inhibited command = %q, want %q", got, want)
	}
}
