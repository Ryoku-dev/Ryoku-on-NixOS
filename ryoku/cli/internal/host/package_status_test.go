package host

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTable(t *testing.T, distribution, rows string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), distribution+".tsv")
	body := "arch\t" + distribution + "\tlanes\tnotes\n" + rows
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// The catalogue overlay fills names the edition table does not list; Ryoku's
// own row still wins for a name both tables map.
func TestPackageOverlayFillsUnderTheEditionTable(t *testing.T) {
	edition := writeTable(t, "void", "shared\tvoid-shared\tdesktop\t\n")
	overlay := writeTable(t, "void", "obs-studio\tobs\tmedia\t\nshared\twrong-name\tmedia\t\nheroic\t-\tgaming\tHeroic is not packaged for Void.\n")
	runner := &fakeRunner{}
	app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "xbps", "RYOKU_HOST_PKG_TABLE": edition})

	if code := app.Package([]string{"--overlay", overlay, "local", "obs-studio", "shared", "plain"}); code != ExitOK {
		t.Fatal(code)
	}
	if got := stdout.String(); got != "obs\nvoid-shared\nplain\n" {
		t.Fatalf("local with overlay = %q", got)
	}

	stdout.Reset()
	if code := app.Package([]string{"--overlay", overlay, "why", "heroic"}); code != ExitOK || stdout.String() != "Heroic is not packaged for Void.\n" {
		t.Fatalf("why = %d %q", code, stdout.String())
	}

	// Without the option a later call is back on the edition table alone.
	stdout.Reset()
	if code := app.Package([]string{"local", "obs-studio"}); code != ExitOK || stdout.String() != "obs-studio\n" {
		t.Fatalf("local without overlay = %d %q", code, stdout.String())
	}
}

func TestPackageOverlayFromEnvironmentMissingAndMalformed(t *testing.T) {
	edition := writeTable(t, "void", "")
	overlay := writeTable(t, "void", "obs-studio\tobs\tmedia\t\n")
	runner := &fakeRunner{}
	env := map[string]string{"RYOKU_HOST_PKGMGR": "xbps", "RYOKU_HOST_PKG_TABLE": edition, "RYOKU_HOST_PKG_OVERLAY": overlay}
	app, stdout, stderr := testApp(runner, env)
	if code := app.Package([]string{"local", "obs-studio"}); code != ExitOK || stdout.String() != "obs\n" {
		t.Fatalf("env overlay = %d %q", code, stdout.String())
	}

	stdout.Reset()
	env["RYOKU_HOST_PKG_OVERLAY"] = filepath.Join(t.TempDir(), "gone.tsv")
	if code := app.Package([]string{"local", "obs-studio"}); code != ExitOK || stdout.String() != "obs-studio\n" {
		t.Fatalf("missing overlay = %d %q", code, stdout.String())
	}
	if !strings.Contains(stderr.String(), "is missing") {
		t.Fatalf("missing overlay warning = %q", stderr.String())
	}

	bad := filepath.Join(t.TempDir(), "bad.tsv")
	if err := os.WriteFile(bad, []byte("arch\tfedora\tlanes\tnotes\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code := app.Package([]string{"--overlay", bad, "local", "obs-studio"}); code != ExitFailure {
		t.Fatalf("malformed overlay exit = %d", code)
	}
	if code := app.Package([]string{"--overlay"}); code != ExitUsage {
		t.Fatalf("bare --overlay exit = %d", code)
	}
}

// A package Void ships in a repository that is off until its enabler is
// installed counts as available, and installing it turns the repository on
// first so the package transaction can see it.
func TestXBPSStatusAndInstallEnableTheRepositoriesARowNeeds(t *testing.T) {
	edition := writeTable(t, "void", "firefox\tfirefox\tdesktop\t\n")
	overlay := writeTable(t, "void", strings.Join([]string{
		"steam\tsteam libgcc-32bit\tgaming\trepo=nonfree,multilib",
		"obs-studio\tobs\tmedia\t",
		"heroic\t-\tgaming\tHeroic is not packaged for Void.",
		"pair\tpart-a part-b\tgaming\t",
		"",
	}, "\n"))
	installed := map[string]bool{"firefox": true, "part-a": true}
	remote := map[string]bool{"firefox": true, "obs": true, "part-a": true, "part-b": true,
		"void-repo-nonfree": true, "void-repo-multilib": true}
	runner := &fakeRunner{answer: func(command Command) Result {
		switch {
		case argv(command) == "xbps-query -l":
			var lines []string
			for name := range installed {
				lines = append(lines, "ii "+name+"-1.0_1 desc")
			}
			return Result{Output: strings.Join(lines, "\n") + "\n"}
		case command.Name == "xbps-query" && len(command.Args) == 2 && command.Args[0] == "-R":
			if remote[command.Args[1]] {
				return Result{}
			}
			return Result{Code: 2}
		case command.Name == "xbps-query" && len(command.Args) == 1:
			if installed[command.Args[0]] {
				return Result{}
			}
			return Result{Code: 2}
		}
		return Result{}
	}}
	app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "xbps", "RYOKU_HOST_PKG_TABLE": edition})

	if code := app.Package([]string{"--overlay", overlay, "status", "steam", "firefox", "obs-studio", "heroic", "pair", "nothing-here"}); code != ExitOK {
		t.Fatal(code)
	}
	want := strings.Join([]string{
		"steam\tavailable\trepo\t",
		"firefox\tinstalled\trepo\t",
		"obs-studio\tavailable\trepo\t",
		"heroic\tunavailable\t\tHeroic is not packaged for Void.",
		"pair\tavailable\trepo\t",
		"nothing-here\tunavailable\t\tNot in the Void repositories.",
		"",
	}, "\n")
	if got := stdout.String(); got != want {
		t.Fatalf("status =\n%s\nwant\n%s", got, want)
	}
	if code := app.Package([]string{"--overlay", overlay, "available", "steam"}); code != ExitOK {
		t.Fatalf("available steam = %d", code)
	}

	runner.commands = nil
	if code := app.Package([]string{"--overlay", overlay, "install", "steam"}); code != ExitOK {
		t.Fatal(code)
	}
	var transactions []string
	for _, command := range runner.commands {
		if command.Name == "xbps-install" {
			transactions = append(transactions, argv(command))
		}
	}
	if strings.Join(transactions, " | ") != "xbps-install -Sy void-repo-nonfree void-repo-multilib | xbps-install -Sy steam libgcc-32bit" {
		t.Fatalf("install transactions = %q", transactions)
	}

	// Once the enablers are in, the repositories answer for the package itself.
	installed["void-repo-nonfree"], installed["void-repo-multilib"] = true, true
	stdout.Reset()
	if code := app.Package([]string{"--overlay", overlay, "status", "steam"}); code != ExitOK || stdout.String() != "steam\tunavailable\t\tNot in the Void repositories.\n" {
		t.Fatalf("status with repos on but no steam in them = %d %q", code, stdout.String())
	}
}

func TestDNFStatusBatchesTheRepositoryQuery(t *testing.T) {
	edition := writeTable(t, "fedora", "")
	overlay := writeTable(t, "fedora", "obs-studio\tobs-studio\tmedia\t\nsteam\t-\tgaming\tSteam needs RPM Fusion, which Ryoku does not enable.\nprovided\tvirtual-name\tmedia\t\n")
	var batches, providers []string
	runner := &fakeRunner{paths: map[string]bool{"dnf5": true, "rpm": true}, answer: func(command Command) Result {
		switch {
		case argv(command) == "rpm -qa --qf %{NAME}\n":
			return Result{Output: "bash\n"}
		case command.Name == "rpm":
			return Result{Code: 1}
		case command.Name == "dnf5" && strings.Contains(argv(command), "--whatprovides="):
			providers = append(providers, argv(command))
			if strings.Contains(argv(command), "--whatprovides=virtual-name") {
				return Result{Output: "real-provider\n"}
			}
			return Result{}
		case command.Name == "dnf5":
			batches = append(batches, argv(command))
			return Result{Output: "obs-studio\n\n"}
		}
		return Result{}
	}}
	app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "dnf", "RYOKU_HOST_PKG_TABLE": edition})
	if code := app.Package([]string{"--overlay", overlay, "status", "obs-studio", "steam", "bash", "provided", "missing"}); code != ExitOK {
		t.Fatal(code)
	}
	want := strings.Join([]string{
		"obs-studio\tavailable\trepo\t",
		"steam\tunavailable\t\tSteam needs RPM Fusion, which Ryoku does not enable.",
		"bash\tinstalled\trepo\t",
		"provided\tavailable\trepo\t",
		"missing\tunavailable\t\tNot in the Fedora repositories.",
		"",
	}, "\n")
	if got := stdout.String(); got != want {
		t.Fatalf("status =\n%s\nwant\n%s", got, want)
	}
	if len(batches) != 1 || !strings.HasSuffix(batches[0], "obs-studio virtual-name missing") || len(providers) != 2 {
		t.Fatalf("one batched repoquery, then one provider query per miss: %q %q", batches, providers)
	}
}

// Fedora names 32-bit packages with their architecture. rpm and dnf match such
// a spec as a package, never as a provided capability, so a 32-bit row must
// read installed once its package is in and available while it is not.
func TestDNFStatusMatchesArchitectureQualifiedNames(t *testing.T) {
	edition := writeTable(t, "fedora", "lib32-mesa\tmesa-dri-drivers.i686 mesa-libGL.i686\toptional\t\nlib32-gamemode\tgamemode.i686\tgaming\t\n")
	installed := map[string]bool{"mesa-dri-drivers.i686": true, "mesa-libGL.i686": true}
	runner := &fakeRunner{paths: map[string]bool{"dnf5": true, "rpm": true}, answer: func(command Command) Result {
		args := argv(command)
		switch {
		case args == "rpm -qa --qf %{NAME}\n":
			return Result{Output: "mesa-dri-drivers\nmesa-libGL\n"}
		case strings.HasPrefix(args, "rpm -q --quiet "):
			if installed[strings.TrimPrefix(args, "rpm -q --quiet ")] {
				return Result{}
			}
			return Result{Code: 1}
		case strings.Contains(args, "--whatprovides"):
			return Result{Code: 1}
		case args == "dnf5 repoquery -y --available gamemode.i686 --qf %{name}\n":
			return Result{Output: "gamemode\n"}
		case command.Name == "dnf5":
			return Result{Output: "gamemode\n"}
		}
		return Result{Code: 1}
	}}
	app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "dnf", "RYOKU_HOST_PKG_TABLE": edition})
	if code := app.Package([]string{"status", "lib32-mesa", "lib32-gamemode"}); code != ExitOK {
		t.Fatal(code)
	}
	if got, want := stdout.String(), "lib32-mesa\tinstalled\trepo\t\nlib32-gamemode\tavailable\trepo\t\n"; got != want {
		t.Fatalf("status = %q, want %q", got, want)
	}
}

func TestPacmanStatusSplitsRepositoriesFromTheAUR(t *testing.T) {
	runner := &fakeRunner{answer: func(command Command) Result {
		switch argv(command) {
		case "pacman -Qq":
			return Result{Output: "steam\n"}
		case "pacman -Slq":
			return Result{Output: "steam\nlutris\n"}
		}
		return Result{}
	}}
	app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "pacman"})
	if code := app.Package([]string{"status", "steam", "lutris", "heroic-games-launcher-bin"}); code != ExitOK {
		t.Fatal(code)
	}
	want := "steam\tinstalled\trepo\t\nlutris\tavailable\trepo\t\nheroic-games-launcher-bin\tavailable\taur\t\n"
	if got := stdout.String(); got != want {
		t.Fatalf("status = %q", got)
	}
}

func TestPackageStatusFailsWhenTheManagerCannotBeQueried(t *testing.T) {
	runner := &fakeRunner{answer: func(command Command) Result { return Result{Code: 1} }}
	app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "pacman"})
	if code := app.Package([]string{"status", "steam"}); code != ExitFailure || stdout.Len() != 0 {
		t.Fatalf("status with a broken pacman = %d %q", code, stdout.String())
	}
}
