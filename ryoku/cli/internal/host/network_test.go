package host

import "testing"

func TestNetworkReadCommandsForwardToHelpers(t *testing.T) {
	runner := &fakeRunner{}
	app, _, _ := testApp(runner, nil)
	app.cfg.UID, app.cfg.UIDSet = 0, true
	for _, args := range [][]string{{"kill", "status"}, {"wifi-backend", "get"}} {
		if code := app.Network(args); code != ExitOK {
			t.Fatalf("Network(%v) exit = %d", args, code)
		}
	}
	if got := argv(runner.commands[0]); got != "ryoku-network-kill status" {
		t.Fatalf("kill status = %q", got)
	}
	if got := argv(runner.commands[1]); got != "ryoku-wifi-backend get" {
		t.Fatalf("wifi get = %q", got)
	}
}

func TestNetworkWritesUsePackagedPolkitHelpers(t *testing.T) {
	runner := &fakeRunner{}
	app, _, _ := testApp(runner, nil)
	app.cfg.UID, app.cfg.UIDSet = 1000, true
	for _, args := range [][]string{{"kill", "on"}, {"wifi-backend", "set", "wpa_supplicant"}} {
		if code := app.Network(args); code != ExitOK {
			t.Fatalf("Network(%v) exit = %d", args, code)
		}
	}
	if got := argv(runner.commands[0]); got != "pkexec /usr/bin/ryoku-network-kill on" {
		t.Fatalf("kill set = %q", got)
	}
	if got := argv(runner.commands[1]); got != "pkexec ryoku-wifi-backend wpa_supplicant" {
		t.Fatalf("wifi set = %q", got)
	}
}

func TestNetworkRootWritesForwardToHelpers(t *testing.T) {
	runner := &fakeRunner{}
	app, _, _ := testApp(runner, nil)
	app.cfg.UID, app.cfg.UIDSet = 0, true
	if code := app.Network([]string{"wifi-backend", "set", "iwd"}); code != ExitOK {
		t.Fatal(code)
	}
	if got := argv(runner.commands[0]); got != "ryoku-wifi-backend iwd" {
		t.Fatalf("wifi set = %q", got)
	}
}
