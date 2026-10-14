package host

import (
	"reflect"
	"testing"
)

func TestSystemdUserServiceTargetsCurrentUserNormally(t *testing.T) {
	runner := &fakeRunner{}
	app, _, _ := testApp(runner, map[string]string{
		"RYOKU_HOST_INIT": "systemd",
		"SUDO_USER":       "desktop",
	})
	app.cfg.UID, app.cfg.UIDSet = 1000, true

	if code := app.Service([]string{"--user", "restart", "ryoku-shell"}); code != ExitOK {
		t.Fatalf("service exit = %d", code)
	}
	if got, want := argv(runner.commands[0]), "systemctl --user restart ryoku-shell.service"; got != want {
		t.Fatalf("argv = %q, want %q", got, want)
	}
}

func TestSystemdUserServiceTargetsResolvedSudoUser(t *testing.T) {
	runner := &fakeRunner{}
	app, _, _ := testApp(runner, map[string]string{
		"RYOKU_HOST_INIT": "systemd",
		"SUDO_USER":       "desktop",
	})
	app.cfg.UID, app.cfg.UIDSet = 0, true

	if code := app.Service([]string{"--user", "restart", "ryoku-shell"}); code != ExitOK {
		t.Fatalf("service exit = %d", code)
	}
	if got, want := argv(runner.commands[0]), "systemctl --machine=desktop@.host --user restart ryoku-shell.service"; got != want {
		t.Fatalf("argv = %q, want %q", got, want)
	}
}

func TestSystemdUserQueriesUseTargetedScope(t *testing.T) {
	runner := &fakeRunner{results: []Result{
		{Output: "loaded\n"},
		{Output: "app-demo-1.scope loaded failed failed Demo\n"},
	}}
	app, _, _ := testApp(runner, map[string]string{
		"RYOKU_HOST_INIT": "systemd",
		"SUDO_USER":       "desktop",
	})
	app.cfg.UID, app.cfg.UIDSet = 0, true

	state, err := app.ServiceProperty("--user", "app-demo-1.scope", "LoadState")
	if err != nil || state != "loaded" {
		t.Fatalf("load state = %q, %v", state, err)
	}
	failures, err := app.FailedServicesFor("--user")
	if err != nil {
		t.Fatal(err)
	}
	if want := []ServiceFailure{{Scope: "--user", Name: "app-demo-1.scope"}}; !reflect.DeepEqual(failures, want) {
		t.Fatalf("failures = %+v, want %+v", failures, want)
	}

	want := []string{
		"systemctl --machine=desktop@.host --user show -p LoadState --value app-demo-1.scope",
		"systemctl --machine=desktop@.host --user --failed --no-legend --plain",
	}
	for i := range want {
		if got := argv(runner.commands[i]); got != want[i] {
			t.Fatalf("argv %d = %q, want %q", i, got, want[i])
		}
	}
}

func TestSystemdManifestUserArgsUseSameScope(t *testing.T) {
	for _, test := range []struct {
		name string
		uid  int
		want []string
	}{
		{name: "current user", uid: 1000, want: []string{"--user", "is-enabled", "demo.service"}},
		{name: "sudo user", uid: 0, want: []string{"--machine=desktop@.host", "--user", "is-enabled", "demo.service"}},
	} {
		t.Run(test.name, func(t *testing.T) {
			app, _, _ := testApp(&fakeRunner{}, map[string]string{"SUDO_USER": "desktop"})
			app.cfg.UID, app.cfg.UIDSet = test.uid, true
			got := app.systemdManifestArgs(true, "is-enabled", "demo.service")
			if !reflect.DeepEqual(got, test.want) {
				t.Fatalf("args = %q, want %q", got, test.want)
			}
		})
	}
}
