package doctor

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ryoku-cli/internal/host"
	"ryoku-cli/internal/ryotunesrelease"
)

func TestRyotunesUsesNativeRepositoryOutsidePacman(t *testing.T) {
	for _, manager := range []host.PackageManager{host.DNF, host.XBPS} {
		t.Run(string(manager), func(t *testing.T) {
			oldManager := doctorPackageManager
			oldInstalled := doctorPackageInstalled
			oldAdvice := doctorInstallAdvice
			oldEnsure := ryotunesEnsure
			t.Cleanup(func() {
				doctorPackageManager = oldManager
				doctorPackageInstalled = oldInstalled
				doctorInstallAdvice = oldAdvice
				ryotunesEnsure = oldEnsure
			})

			t.Setenv("HOME", t.TempDir())
			bin := t.TempDir()
			sudoLog := filepath.Join(bin, "sudo.log")
			if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte("#!/bin/sh\nprintf '%s\\n' \"$*\" >\"$RYOTUNES_SUDO_LOG\"\n"), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
			t.Setenv("RYOTUNES_SUDO_LOG", sudoLog)
			t.Setenv("XDG_STATE_HOME", t.TempDir())
			doctorPackageManager = func() (host.PackageManager, error) { return manager, nil }
			doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
			doctorInstallAdvice = func(names ...string) string {
				return fmt.Sprintf("native-%s-install %s", manager, strings.Join(names, " "))
			}

			ryotunesEnsure = func(context.Context) (ryotunesrelease.Status, error) {
				t.Fatal("native repository package used the standalone pacman release lane")
				return ryotunesrelease.Status{}, nil
			}

			result := reconcileRyotunes(false)
			got, err := os.ReadFile(sudoLog)
			if err != nil {
				t.Fatal(err)
			}
			if command := strings.TrimSpace(string(got)); command != "ryoku-host pkg install ryotunes" {
				t.Fatalf("sudo command = %q", command)
			}
			if result.status != recFixed {
				t.Fatalf("status = %s, detail = %q", result.status.label(), result.detail)
			}
			if strings.Contains(result.remedy+result.detail, "pacman") {
				t.Fatalf("native result mentions pacman: %#v", result)
			}
		})
	}
}

func TestRyotunesNativeRepositoryCheckOnlyUsesHostAdvice(t *testing.T) {
	oldManager := doctorPackageManager
	oldInstalled := doctorPackageInstalled
	oldInstall := doctorPackageInstall
	oldAdvice := doctorInstallAdvice
	t.Cleanup(func() {
		doctorPackageManager = oldManager
		doctorPackageInstalled = oldInstalled
		doctorPackageInstall = oldInstall
		doctorInstallAdvice = oldAdvice
	})

	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	doctorPackageManager = func() (host.PackageManager, error) { return host.DNF, nil }
	doctorPackageInstalled = func(name string) bool { return name == "ryoku-desktop" }
	doctorPackageInstall = func(...string) int {
		t.Fatal("check-only reconciliation installed a package")
		return host.ExitFailure
	}
	doctorInstallAdvice = func(...string) string { return "sudo dnf install -y ryotunes" }

	result := reconcileRyotunes(true)
	if result.status != recWouldFix {
		t.Fatalf("status = %s, want todo", result.status.label())
	}
	if result.remedy != "sudo dnf install -y ryotunes" {
		t.Fatalf("remedy = %q", result.remedy)
	}
}
