package main

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestFreshInstallerSelectsSupportedApps(t *testing.T) {
	m := newModel(defaultOptions())
	got := m.selectedApps()
	var want []string
	for _, app := range optionalApps() {
		want = append(want, app.ID)
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("fresh selected apps = %v, want %v", got, want)
	}
}

func TestAppSelectionKeepsCatalogueOrder(t *testing.T) {
	m := newModel(defaultOptions())
	for id := range m.keep {
		m.keep[id] = false
	}
	m.keep["docker"] = true
	m.keep["prompt"] = true
	m.keep["go"] = true
	got := m.selectedApps()
	want := []string{"prompt", "docker", "go"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("selected apps = %v, want catalogue order %v", got, want)
	}
}

func TestParseOptionsDirectBackendCompatibility(t *testing.T) {
	opts, direct, args, err := parseOptions([]string{
		"--cli", "--flake", "/tmp/nixos#host", "--source", "path:/tmp/ryoku",
		"--compositor", "niri", "--browser", "firefox", "--shell", "zsh",
		"--apps", "prompt,docker", "--dry-run", "-y",
	})
	if err != nil {
		t.Fatal(err)
	}
	if !direct {
		t.Fatal("--cli/-y should select direct backend mode")
	}
	if opts.flake != "/tmp/nixos#host" || opts.source != "path:/tmp/ryoku" || !opts.sourceExplicit || !opts.dryRun {
		t.Fatalf("parsed options = %+v", opts)
	}
	if len(args) == 0 || args[0] != "--flake" {
		t.Fatalf("backend args = %v", args)
	}
}

func TestRenderAllScreens(t *testing.T) {
	m := newModel(defaultOptions())
	m.w, m.h = 112, 40
	if got := m.render(); got == "" {
		t.Fatal("welcome rendered empty")
	}
	m.state = "wizard"
	for i := range flow {
		m.idx = i
		m.setCursorForStep()
		if got := m.render(); got == "" {
			t.Fatalf("screen %s rendered empty", flow[i].key)
		}
	}
	m.state = "install"
	if got := m.render(); got == "" {
		t.Fatal("install rendered empty")
	}
}

func TestBackendOnlyOptionsSelectDirectMode(t *testing.T) {
	_, direct, args, err := parseOptions([]string{"--compositor", "niri", "--browser", "firefox"})
	if err != nil {
		t.Fatal(err)
	}
	if !direct {
		t.Fatal("backend-only selection flags must bypass the interactive TUI")
	}
	if len(args) != 4 {
		t.Fatalf("backend args = %v", args)
	}
}

func TestISOFlagKeepsInteractiveTUI(t *testing.T) {
	opts, direct, args, err := parseOptions([]string{"--iso"})
	if err != nil {
		t.Fatal(err)
	}
	if direct {
		t.Fatal("--iso alone must keep the interactive TUI")
	}
	if !opts.iso {
		t.Fatal("--iso did not set ISO mode")
	}
	if !reflect.DeepEqual(args, []string{"--iso"}) {
		t.Fatalf("backend args = %v", args)
	}

	m := newModel(opts)
	m.w, m.h = 112, 40
	if got := m.render(); got == "" {
		t.Fatal("ISO welcome rendered empty")
	}
}

func TestISODiskAutomationSelectsDirectBackend(t *testing.T) {
	opts, direct, args, err := parseOptions([]string{
		"--iso", "--disk", "/dev/vda", "--filesystem", "ext4",
		"--hostname", "ryoku-test", "--username", "tester",
		"--confirm-disk", "/dev/vda", "--yes",
	})
	if err != nil {
		t.Fatal(err)
	}
	if !opts.iso || !direct {
		t.Fatalf("opts=%+v direct=%v", opts, direct)
	}
	if len(args) < 2 || args[0] != "--iso" {
		t.Fatalf("backend args = %v", args)
	}
}

func TestISOKernelChoicesMatchBackendContract(t *testing.T) {
	want := []string{"default", "latest", "zen"}
	choices := isoChoices("kernel")
	if len(choices) != len(want) {
		t.Fatalf("kernel choices = %d, want %d", len(choices), len(want))
	}
	for i, key := range want {
		if choices[i].key != key {
			t.Fatalf("kernel choice %d = %q, want %q", i, choices[i].key, key)
		}
	}
}

func TestISOBackendArgsAreFullyNonInteractive(t *testing.T) {
	o := defaultOptions()
	o.iso = true
	m := newISOModel(o)
	m.disks = []isoDisk{{Path: "/dev/vda", Size: minISODiskBytes}}
	m.picks["disk"] = "/dev/vda"
	m.passwordHash = "$y$test$hash"
	m.text["password"] = "super secret plaintext"
	m.text["confirm"] = "super secret plaintext"
	args := m.backendArgs()
	joined := strings.Join(args, " ")
	for _, required := range []string{
		"--iso", "--yes", "--disk /dev/vda", "--confirm-disk /dev/vda",
		"--filesystem ext4", "--hostname ryoku", "--username user",
		"--timezone UTC", "--locale en_US.UTF-8", "--keyboard us",
		"--kernel default", "--gpu auto", "--firmware auto",
		"--config-mode ryoku",
	} {
		if !strings.Contains(joined, required) {
			t.Fatalf("backend args missing %q: %s", required, joined)
		}
	}
	if strings.Contains(joined, "super secret plaintext") || strings.Contains(joined, m.passwordHash) {
		t.Fatalf("password material leaked into argv: %s", joined)
	}
}

func TestISOImportArgsOnlyDeclareImportContract(t *testing.T) {
	o := defaultOptions()
	o.iso = true
	m := newISOModel(o)
	m.picks["disk"] = "/dev/vda"
	m.picks["configuration"] = "import"
	m.text["import-path"] = "/tmp/existing"
	m.text["import-host"] = "laptop"
	joined := strings.Join(m.backendArgs(), " ")
	for _, required := range []string{"--config-mode import", "--import-flake /tmp/existing", "--import-host laptop"} {
		if !strings.Contains(joined, required) {
			t.Fatalf("import args missing %q: %s", required, joined)
		}
	}
}

func TestISOExactDiskConfirmation(t *testing.T) {
	o := defaultOptions()
	o.iso = true
	m := newISOModel(o)
	m.w, m.h = 112, 40
	m.picks["disk"] = "/dev/vda"
	m.gotoKey("confirm")
	m.text["disk-confirm"] = "/dev/sda"
	model, cmd := m.onKey("enter")
	got := model.(isoModel)
	if cmd != nil || got.installing || got.err == nil {
		t.Fatalf("wrong confirmation unexpectedly started install: installing=%v err=%v", got.installing, got.err)
	}
}
func TestISODryRunUsesSyntheticDiskWhenNoneFound(t *testing.T) {
	o := defaultOptions()
	o.iso = true
	o.dryRun = true
	m := newISOModel(o)
	m.gotoKey("network")

	model, _ := m.Update(isoDisksMsg{disks: nil})
	got := model.(isoModel)
	if !got.syntheticDisk {
		t.Fatal("dry run with no disks must enable the synthetic target")
	}
	if got.picks["disk"] != dryRunDiskPath {
		t.Fatalf("synthetic disk = %q, want %q", got.picks["disk"], dryRunDiskPath)
	}

	got.next()
	if got.current().key != "filesystem" {
		t.Fatalf("dry run should skip disk picker, landed on %q", got.current().key)
	}
}

func TestISORealInstallDoesNotInventDisk(t *testing.T) {
	o := defaultOptions()
	o.iso = true
	m := newISOModel(o)

	model, _ := m.Update(isoDisksMsg{disks: nil})
	got := model.(isoModel)
	if got.syntheticDisk || got.picks["disk"] != "" {
		t.Fatalf("real install invented a disk: synthetic=%v disk=%q", got.syntheticDisk, got.picks["disk"])
	}
}

func TestDefaultSourceIsNotForwardedAsExplicitOverride(t *testing.T) {
	opts := defaultOptions()
	if opts.sourceExplicit {
		t.Fatal("environment/default source must not be treated as an explicit CLI override")
	}
	m := newISOModel(opts)
	m.picks["disk"] = "/dev/vda"
	args := m.backendArgs()
	for i := 0; i < len(args); i++ {
		if args[i] == "--source" {
			t.Fatalf("implicit source leaked into ISO backend args: %v", args)
		}
	}
}

func TestISOTextFieldsAcceptQ(t *testing.T) {
	o := defaultOptions()
	o.iso = true
	for _, key := range []string{"hostname", "username", "import-path", "import-host"} {
		m := newISOModel(o)
		m.gotoKey(key)
		before := m.text[key]
		model, cmd := m.onKey("q")
		got := model.(isoModel)
		if cmd != nil {
			t.Fatalf("%s: q unexpectedly returned a command", key)
		}
		if got.text[key] != before+"q" {
			t.Fatalf("%s: q was not entered as text: before=%q after=%q", key, before, got.text[key])
		}
	}

	m := newISOModel(o)
	m.gotoKey("confirm")
	model, cmd := m.onKey("q")
	got := model.(isoModel)
	if cmd != nil || got.text["disk-confirm"] != "q" {
		t.Fatalf("confirm: q was not entered into disk confirmation: %q", got.text["disk-confirm"])
	}
}

func TestISOTimezonePickerAcceptsQAsSearch(t *testing.T) {
    o := defaultOptions()
    o.iso = true

    m := newISOModel(o)
    m.timezones = []string{
        "America/Sao_Paulo",
        "UTC",
    }

    m.gotoKey("timezone")

    before := m.text["timezone"]

    model, cmd := m.onKey("q")
    got := model.(isoModel)

    if cmd != nil {
        t.Fatal("typing q unexpectedly returned a command")
    }

    if got.timezoneQuery != "q" {
        t.Fatalf(
            "q was not entered into timezone search: got %q",
            got.timezoneQuery,
        )
    }

    if got.text["timezone"] != before {
        t.Fatalf(
            "search modified selected timezone: before=%q after=%q",
            before,
            got.text["timezone"],
        )
    }
}

func TestISOInstallStepContractIncludesPreflightValidation(t *testing.T) {
	steps := isoInstallSteps()
	if len(steps) != 7 || steps[0] != "Resolve flake inputs" || steps[1] != "Validate target config" {
		t.Fatalf("unexpected install steps: %v", steps)
	}
	if idx, ok := isoInstallStepIndex("validate"); !ok || idx != 1 {
		t.Fatalf("validate step index = %d, %v", idx, ok)
	}
}

func TestISOBackendFailureKeepsDiagnosticsAndBlocksRetry(t *testing.T) {
	dir := t.TempDir()
	backend := filepath.Join(dir, "backend")
	content := "#!/bin/sh\nprintf '@@RYOKU_STEP install\\n'\nprintf 'nixos-install: simulated build failure\\n'\nexit 42\n"
	if err := os.WriteFile(backend, []byte(content), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_INSTALL_BACKEND", backend)
	t.Setenv("TMPDIR", dir)
	o := defaultOptions()
	o.iso = true
	m := newISOModel(o)
	m.w, m.h = 120, 44
	m.gotoKey("confirm")
	m.picks["disk"] = "/dev/vda"
	m.text["disk-confirm"] = "/dev/vda"
	started, next := m.onKey("enter")
	m = started.(isoModel)
	if !m.installing || next == nil {
		t.Fatal("confirmed install did not start")
	}
	for i := 0; i < 15; i++ {
		model, cmd := m.Update(next())
		m = model.(isoModel)
		if !m.installing {
			break
		}
		next = cmd
		if next == nil {
			t.Fatal("stream stopped before backend completed")
		}
	}
	if !m.failed || m.done || m.err == nil || m.installing {
		t.Fatalf("backend failure not retained: failed=%v done=%v installing=%v err=%v", m.failed, m.done, m.installing, m.err)
	}
	if m.installAt != 5 || m.installLogPath == "" {
		t.Fatalf("missing install stage or log: stage=%d path=%q", m.installAt, m.installLogPath)
	}
	data, err := os.ReadFile(m.installLogPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "simulated build failure") {
		t.Fatalf("backend output not logged: %q", data)
	}
	screen := isoANSI.ReplaceAllString(m.render(), "")
	if !strings.Contains(screen, "Do not confirm the disk again") || !strings.Contains(screen, "Full log:") || !strings.Contains(screen, "ryoku-") {
		t.Fatal("failure screen lacks safety guidance or log filename")
	}
	for _, key := range []string{"x", "r"} {
		model, cmd := m.onKey(key)
		m = model.(isoModel)
		if cmd != nil || m.installing || !m.failed || m.current().key != "confirm" {
			t.Fatalf("%s restarted installation or cleared failure", key)
		}
	}
}

func TestFailedInstallPointsToBackendOutput(t *testing.T) {
	// The backend writes the Nix error and the restore result to the normal
	// terminal screen, which the TUI covers again. The failure screen must
	// not promise a rollback the backend may not have managed.
	m := newModel(defaultOptions())
	m.w, m.h = 112, 40
	next, _ := m.Update(installDoneMsg{err: errors.New("exit status 1")})
	m = next.(model)
	got := m.render()
	if m.state != "failed" || !strings.Contains(got, "exit status 1") {
		t.Fatalf("backend failure not shown:\n%s", got)
	}
	if strings.Contains(got, "rolled back") {
		t.Fatalf("failure screen claims a rollback:\n%s", got)
	}
	if !strings.Contains(got, "whether your files were restored") {
		t.Fatalf("failure screen does not point to the backend output:\n%s", got)
	}
}
