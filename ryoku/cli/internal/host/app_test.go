package host

import (
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestSystemdAppArguments(t *testing.T) {
	opts := appOptions{
		cwd:     "/home/ryoku/My Files",
		label:   "Org.Example / Strange_App.desktop",
		command: []string{"demo-app", "--open", "two words"},
	}
	got := systemdAppArgs(opts, "001122aabbcc")
	want := []string{
		"--user",
		"--scope",
		"--collect",
		"--quiet",
		"--slice=app.slice",
		"--unit=app-ryoku-org-example-strange-app-desktop-001122aabbcc.scope",
		"--working-directory=/home/ryoku/My Files",
		"--",
		"demo-app",
		"--open",
		"two words",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("systemd app argv = %#v, want %#v", got, want)
	}
}

func TestSystemdAppExecsUniqueScopes(t *testing.T) {
	runner := &fakeRunner{paths: map[string]bool{"demo-app": true}}
	app, _, _ := testApp(runner, map[string]string{"RYOKU_HOST_INIT": "systemd"})
	for range 2 {
		if code := app.Execute([]string{"app", "--label", "Demo.desktop", "--", "demo-app"}); code != ExitOK {
			t.Fatalf("app exit = %d", code)
		}
	}
	if len(runner.commands) != 2 {
		t.Fatalf("commands = %d, want 2", len(runner.commands))
	}
	units := make([]string, 2)
	for i, command := range runner.commands {
		if command.Name != "systemd-run" || !command.Replace || command.Detached {
			t.Fatalf("command %d = %#v", i, command)
		}
		for _, arg := range command.Args {
			if strings.HasPrefix(arg, "--unit=") {
				units[i] = arg
			}
		}
		if !strings.HasPrefix(units[i], "--unit=app-ryoku-demo-desktop-") || !strings.HasSuffix(units[i], ".scope") {
			t.Fatalf("unit %d = %q", i, units[i])
		}
	}
	if units[0] == units[1] {
		t.Fatalf("scope units are not unique: %q", units[0])
	}
}

func TestAppScrubsOnlyQuickshellCrashEnvironment(t *testing.T) {
	for _, name := range quickshellCrashEnvironment {
		t.Setenv(name, "private-handle")
	}
	t.Setenv("XDG_ACTIVATION_TOKEN", "activation-token")
	t.Setenv("DESKTOP_STARTUP_ID", "startup-id")

	checked := false
	runner := &fakeRunner{
		paths: map[string]bool{"demo-app": true},
		answer: func(command Command) Result {
			checked = true
			for _, name := range quickshellCrashEnvironment {
				if _, present := os.LookupEnv(name); present {
					t.Errorf("%s was passed to the application launcher", name)
				}
			}
			if got := os.Getenv("XDG_ACTIVATION_TOKEN"); got != "activation-token" {
				t.Errorf("XDG_ACTIVATION_TOKEN = %q", got)
			}
			if got := os.Getenv("DESKTOP_STARTUP_ID"); got != "startup-id" {
				t.Errorf("DESKTOP_STARTUP_ID = %q", got)
			}
			return Result{}
		},
	}
	app, _, _ := testApp(runner, map[string]string{"RYOKU_HOST_INIT": "systemd"})
	if code := app.App([]string{"--", "demo-app"}); code != ExitOK {
		t.Fatalf("app exit = %d", code)
	}
	if !checked {
		t.Fatal("application launcher did not execute")
	}
	for _, name := range quickshellCrashEnvironment {
		if got := os.Getenv(name); got != "private-handle" {
			t.Errorf("%s was not restored after the test: %q", name, got)
		}
	}
}

func TestRunitAppStartsDetachedInWorkingDirectory(t *testing.T) {
	cwd := t.TempDir()
	original, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	observedDir := ""
	runner := &fakeRunner{
		paths: map[string]bool{"demo-app": true},
		answer: func(command Command) Result {
			observedDir, _ = os.Getwd()
			return Result{PID: 42}
		},
	}
	app, _, _ := testApp(runner, map[string]string{"RYOKU_HOST_INIT": "runit"})
	if code := app.App([]string{"--cwd", cwd, "--", "demo-app", "--flag"}); code != ExitOK {
		t.Fatalf("app exit = %d", code)
	}
	if observedDir != cwd {
		t.Fatalf("working directory = %q, want %q", observedDir, cwd)
	}
	if current, _ := os.Getwd(); current != original {
		t.Fatalf("working directory was not restored: %q", current)
	}
	if len(runner.commands) != 1 {
		t.Fatalf("commands = %d, want 1", len(runner.commands))
	}
	command := runner.commands[0]
	if command.Name != "demo-app" || !reflect.DeepEqual(command.Args, []string{"--flag"}) || !command.Detached || command.Replace {
		t.Fatalf("runit command = %#v", command)
	}
}

func TestAppCommandNotFound(t *testing.T) {
	runner := &fakeRunner{}
	app, stdout, stderr := testApp(runner, map[string]string{"RYOKU_HOST_INIT": "systemd"})
	if code := app.Execute([]string{"app", "--", "missing-app"}); code != appCommandNotFound {
		t.Fatalf("app exit = %d, want %d", code, appCommandNotFound)
	}
	if got := stderr.String(); got != "ryoku-host: missing-app: command not found\n" {
		t.Fatalf("stderr = %q", got)
	}
	if stdout.Len() != 0 || len(runner.commands) != 0 {
		t.Fatalf("unexpected output or command: stdout=%q commands=%#v", stdout.String(), runner.commands)
	}
}
