package host

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestPackageInstalledAtPacman(t *testing.T) {
	log := filepath.Join(t.TempDir(), "pacman.log")
	body := "[2026-02-03T04:05:06+0000] [ALPM] installed base (1-1)\n[2026-02-04T05:06:07+0000] [ALPM] installed ryoku-desktop (2-1)\n"
	if err := os.WriteFile(log, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	app, stdout, _ := testApp(&fakeRunner{}, map[string]string{"RYOKU_HOST_PKGMGR": "pacman"})
	app.cfg.PacmanLog = log
	if code := app.Package([]string{"installed-at", "ryoku-desktop"}); code != ExitOK {
		t.Fatalf("installed-at exit = %d", code)
	}
	if got := stdout.String(); got != "20260204\n" {
		t.Fatalf("date = %q", got)
	}
}

func TestPackageInstalledAtTranslatedHosts(t *testing.T) {
	for _, test := range []struct {
		name        string
		manager     string
		tableHeader string
		mapping     string
		result      string
		command     string
		want        string
	}{
		{name: "Fedora", manager: "dnf", tableHeader: "arch\tfedora\tlanes\tnotes\n", mapping: "ryoku-desktop\tryoku-desktop-fedora\tdesktop\t\n", result: "1767268800", command: "rpm -q --qf %{INSTALLTIME} ryoku-desktop-fedora", want: time.Unix(1767268800, 0).Format("20060102") + "\n"},
		{name: "Void", manager: "xbps", tableHeader: "arch\tvoid\tlanes\tnotes\n", mapping: "ryoku-desktop\tryoku-desktop-void\tdesktop\t\n", result: "2026-03-04 12:34 UTC", command: "xbps-query -p install-date ryoku-desktop-void", want: "20260304\n"},
	} {
		t.Run(test.name, func(t *testing.T) {
			table := filepath.Join(t.TempDir(), "packages.tsv")
			if err := os.WriteFile(table, []byte(test.tableHeader+test.mapping), 0o644); err != nil {
				t.Fatal(err)
			}
			runner := &fakeRunner{results: []Result{{Output: test.result}}}
			app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": test.manager, "RYOKU_HOST_PKG_TABLE": table})
			if code := app.Package([]string{"installed-at", "ryoku-desktop"}); code != ExitOK {
				t.Fatalf("installed-at exit = %d", code)
			}
			if got := argv(runner.commands[0]); got != test.command {
				t.Fatalf("command = %q", got)
			}
			if got := stdout.String(); got != test.want {
				t.Fatalf("date = %q, want %q", got, test.want)
			}
		})
	}
}
