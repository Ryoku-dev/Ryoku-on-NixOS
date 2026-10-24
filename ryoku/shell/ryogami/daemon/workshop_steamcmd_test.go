package main

import (
	"context"
	"encoding/json"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestSteamcmdArgs(t *testing.T) {
	args := steamcmdArgs("", "/install", []string{"123"})
	joined := strings.Join(args, " ")
	for _, want := range []string{
		"+force_install_dir /install",
		"+login anonymous",
		"+workshop_download_item " + workshopAppID + " 123",
		"+quit",
	} {
		if !strings.Contains(joined, want) {
			t.Fatalf("args %q missing %q", joined, want)
		}
	}

	named := strings.Join(steamcmdArgs("bob", "", []string{"1", "2"}), " ")
	if strings.Contains(named, "force_install_dir") {
		t.Fatalf("empty install dir should be omitted: %q", named)
	}
	if !strings.Contains(named, "+login bob") {
		t.Fatalf("username not used: %q", named)
	}
	if !strings.Contains(named, "+workshop_download_item "+workshopAppID+" 1") ||
		!strings.Contains(named, "+workshop_download_item "+workshopAppID+" 2") {
		t.Fatalf("batch ids missing: %q", named)
	}
}

func TestExtractPercent(t *testing.T) {
	cases := []struct {
		line string
		want float64
		ok   bool
	}{
		{"Downloading item 123, 45%", 0.45, true},
		{"  63.5%", 0.635, true},
		{"done 100%", 1.0, true},
		{"no percent here", 0, false},
	}
	for _, tc := range cases {
		got, ok := extractPercent(tc.line)
		if ok != tc.ok {
			t.Fatalf("%q ok=%v want %v", tc.line, ok, tc.ok)
		}
		if ok && got != tc.want {
			t.Fatalf("%q got %v want %v", tc.line, got, tc.want)
		}
	}
}

func TestIsAuthError(t *testing.T) {
	if !isAuthError("ERROR! Cached credentials not found.") {
		t.Fatal("cached credentials line should be auth error")
	}
	if !isAuthError("Login Failure: Invalid Password") {
		t.Fatal("login failure line should be auth error")
	}
	if isAuthError("Success! Downloaded item.") {
		t.Fatal("success line should not be auth error")
	}
}

func setWorkshopDownloadTimeouts(t *testing.T, stall, overall time.Duration) {
	t.Helper()
	oldStall := workshopDownloadStallTimeout
	oldOverall := workshopDownloadOverallTimeout
	workshopDownloadStallTimeout = stall
	workshopDownloadOverallTimeout = overall
	t.Cleanup(func() {
		workshopDownloadStallTimeout = oldStall
		workshopDownloadOverallTimeout = oldOverall
	})
}

func workshopTerminalEvent(t *testing.T, ch chan string) map[string]interface{} {
	t.Helper()
	var terminal map[string]interface{}
	count := 0
	for _, ev := range drainEvents(ch) {
		if ev.Event != "ryogami.workshop.download" {
			continue
		}
		var data map[string]interface{}
		if err := json.Unmarshal(ev.Data, &data); err != nil {
			t.Fatal(err)
		}
		if data["status"] != "downloading" {
			terminal = data
			count++
		}
	}
	if terminal == nil {
		t.Fatal("Workshop download emitted no terminal event")
	}
	if count != 1 {
		t.Fatalf("Workshop download emitted %d terminal events", count)
	}
	return terminal
}

func TestSteamcmdWorkshopFailureExplainsOwnershipAndLogin(t *testing.T) {
	d := newSettingsDaemon(t)
	ch := d.events.subscribe()
	defer d.events.unsubscribe(ch)
	w := &workshopLib{d: d}
	setWorkshopDownloadTimeouts(t, time.Second, 2*time.Second)

	oldCommand := steamcmdCommandContext
	steamcmdCommandContext = func(ctx context.Context, _ string, _ ...string) *exec.Cmd {
		return exec.CommandContext(ctx, "sh", "-c",
			"printf '%s\n' 'ERROR! Download item 1 failed (Failure).' >&2; exit 1")
	}
	t.Cleanup(func() { steamcmdCommandContext = oldCommand })

	w.runDownload("1", true)
	event := workshopTerminalEvent(t, ch)
	if event["status"] != "auth_error" {
		t.Fatalf("status = %v, want auth_error", event["status"])
	}
	message, _ := event["message"].(string)
	for _, want := range []string{
		"owns Wallpaper Engine (app " + workshopAppID + ")",
		"Set your Steam username in the picker's settings",
		"steamcmd +login <your-steam-username> +quit",
	} {
		if !strings.Contains(message, want) {
			t.Fatalf("message %q missing %q", message, want)
		}
	}
}
