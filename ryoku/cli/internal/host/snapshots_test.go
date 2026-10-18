package host

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSnapshotsCapabilityAndCommand(t *testing.T) {
	tests := []struct {
		name       string
		manager    string
		supported  bool
		exit       int
		wantOutput string
	}{
		{name: "pacman", manager: "pacman", supported: true, exit: ExitOK},
		{name: "xbps", manager: "xbps", supported: true, exit: ExitOK},
		{name: "dnf", manager: "dnf", supported: true, exit: ExitOK},
		{name: "unknown", manager: "other", supported: false, exit: ExitNotProvided, wantOutput: snapshotsUnavailableReason + "\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app, stdout, stderr := testApp(&fakeRunner{}, map[string]string{"RYOKU_HOST_PKGMGR": tt.manager})
			supported, reason := app.Snapshots()
			if supported != tt.supported {
				t.Fatalf("Snapshots supported = %v, want %v", supported, tt.supported)
			}
			if tt.supported && reason != "" {
				t.Fatalf("supported host reason = %q, want empty", reason)
			}
			if !tt.supported && reason != snapshotsUnavailableReason {
				t.Fatalf("unsupported host reason = %q, want %q", reason, snapshotsUnavailableReason)
			}
			if code := app.Execute([]string{"snapshots"}); code != tt.exit {
				t.Fatalf("snapshots exit = %d, want %d", code, tt.exit)
			}
			if got := stdout.String(); got != tt.wantOutput {
				t.Fatalf("snapshots stdout = %q, want %q", got, tt.wantOutput)
			}
			if stderr.Len() != 0 {
				t.Fatalf("snapshots stderr = %q, want empty", stderr.String())
			}
		})
	}
}

func TestSnapshotsCommandRejectsArguments(t *testing.T) {
	app, stdout, stderr := testApp(&fakeRunner{}, map[string]string{"RYOKU_HOST_PKGMGR": "pacman"})
	if code := app.Execute([]string{"snapshots", "extra"}); code != ExitUsage {
		t.Fatalf("snapshots with arguments exit = %d, want %d", code, ExitUsage)
	}
	if stdout.Len() != 0 || stderr.Len() != 0 {
		t.Fatalf("usage-only rejection wrote stdout=%q stderr=%q", stdout.String(), stderr.String())
	}
}

func TestSnapshotCreateRunsNumberedSnapshotAndCleanup(t *testing.T) {
	runner := &fakeRunner{paths: map[string]bool{"snapper": true}}
	app, stdout, stderr := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "pacman"})
	config := filepath.Join(t.TempDir(), "root")
	if err := os.WriteFile(config, []byte("[root]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	app.cfg.SnapperRootConfig = config

	if code := app.Execute([]string{"snapshots", "create", "GPU passthrough enable"}); code != ExitOK {
		t.Fatalf("snapshot create exit = %d", code)
	}
	want := []string{
		"snapper -c root create -c number --description GPU passthrough enable",
		"snapper -c root cleanup number",
	}
	if len(runner.commands) != len(want) {
		t.Fatalf("commands = %v, want %v", runner.commands, want)
	}
	for index := range want {
		if got := argv(runner.commands[index]); got != want[index] {
			t.Fatalf("command %d = %q, want %q", index, got, want[index])
		}
	}
	if stdout.Len() != 0 || stderr.Len() != 0 {
		t.Fatalf("snapshot create wrote stdout=%q stderr=%q", stdout.String(), stderr.String())
	}
}

func TestSnapshotCreateStopsAfterSnapperFailure(t *testing.T) {
	runner := &fakeRunner{
		paths:   map[string]bool{"snapper": true},
		results: []Result{{Code: 7}},
	}
	app, _, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "xbps"})
	config := filepath.Join(t.TempDir(), "root")
	if err := os.WriteFile(config, []byte("[root]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	app.cfg.SnapperRootConfig = config

	if code := app.Execute([]string{"snapshots", "create", "before import"}); code != ExitFailure {
		t.Fatalf("failed snapshot exit = %d, want %d", code, ExitFailure)
	}
	if len(runner.commands) != 1 || argv(runner.commands[0]) != "snapper -c root create -c number --description before import" {
		t.Fatalf("commands after failure = %v", runner.commands)
	}
}

func TestSnapshotCreateRequiresToolAndRootConfig(t *testing.T) {
	app, _, stderr := testApp(&fakeRunner{}, map[string]string{"RYOKU_HOST_PKGMGR": "pacman"})
	if code := app.Execute([]string{"snapshots", "create", "before change"}); code != ExitAbsent {
		t.Fatalf("missing snapper exit = %d, want %d", code, ExitAbsent)
	}
	if stderr.String() != "snapper is not installed\n" {
		t.Fatalf("missing snapper stderr = %q", stderr.String())
	}

	runner := &fakeRunner{paths: map[string]bool{"snapper": true}}
	app, _, stderr = testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "pacman"})
	app.cfg.SnapperRootConfig = filepath.Join(t.TempDir(), "missing")
	if code := app.Execute([]string{"snapshots", "create", "before change"}); code != ExitAbsent {
		t.Fatalf("missing root config exit = %d, want %d", code, ExitAbsent)
	}
	if stderr.String() != "snapper's root configuration is not available\n" {
		t.Fatalf("missing root config stderr = %q", stderr.String())
	}
	if len(runner.commands) != 0 {
		t.Fatalf("missing root config ran commands: %v", runner.commands)
	}
}

func TestSnapshotCreateKeepsUnsupportedReason(t *testing.T) {
	runner := &fakeRunner{paths: map[string]bool{"snapper": true}}
	app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "other"})
	if code := app.Execute([]string{"snapshots", "create", "before change"}); code != ExitNotProvided {
		t.Fatalf("unsupported snapshot exit = %d, want %d", code, ExitNotProvided)
	}
	if stdout.String() != snapshotsUnavailableReason+"\n" {
		t.Fatalf("unsupported snapshot output = %q", stdout.String())
	}
	if len(runner.commands) != 0 {
		t.Fatalf("unsupported snapshot ran commands: %v", runner.commands)
	}
}

func TestSnapshotsUnavailableInSnapshotLookBoot(t *testing.T) {
	runner := &fakeRunner{paths: map[string]bool{"snapper": true}}
	app, stdout, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "dnf"})
	cmdline := filepath.Join(t.TempDir(), "cmdline")
	if err := os.WriteFile(cmdline, []byte("BOOT_IMAGE=/ryoku/snapshots/7.2/vmlinuz ro rootflags=subvol=.snapshots/12/snapshot rd.ryoku.preview=.snapshots/12/snapshot quiet\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	app.cfg.ProcCmdline = cmdline

	if got := app.SnapshotPreview(); got != ".snapshots/12/snapshot" {
		t.Fatalf("SnapshotPreview = %q", got)
	}
	supported, reason := app.Snapshots()
	if supported {
		t.Fatal("a look boot reported snapshots as supported")
	}
	if want := "This boot runs snapshot 12 read-only and keeps its changes in RAM. Run `sudo ryoku boot-menu restore` to make it the system, or reboot to go back."; reason != want {
		t.Fatalf("look boot reason = %q, want %q", reason, want)
	}
	if code := app.Execute([]string{"snapshots", "create", "inside the look"}); code != ExitNotProvided {
		t.Fatalf("look boot snapshot create exit = %d, want %d", code, ExitNotProvided)
	}
	if stdout.String() != reason+"\n" || len(runner.commands) != 0 {
		t.Fatalf("look boot create wrote %q and ran %v", stdout.String(), runner.commands)
	}
}

func TestSnapshotLabelKeepsUnfamiliarPaths(t *testing.T) {
	if got := snapshotLabel("@/.snapshots/3/snapshot"); got != "@/.snapshots/3/snapshot" {
		t.Fatalf("snapshotLabel = %q", got)
	}
}
