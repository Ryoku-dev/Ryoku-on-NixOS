package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestResolveComponent(t *testing.T) {
	cases := map[string]string{
		"shell":       "shell",
		"SHELL":       "shell",
		"Quickshell":  "shell",
		"ryoku-shell": "shell",
		"ryogami":     "wallpaper",
		"WALLPAPER":   "wallpaper",
		"Idle":        "idle",
		"lockscreen":  "idle",
		"pipewire":    "audio",
		"portals":     "portals",
		"doctor":      "updates",
		"compositor":  "compositor",
		"wm":          "compositor",
		"  hub  ":     "hub",
		"firefox":     "",
		"blorptron":   "",
	}
	for in, want := range cases {
		if got := resolveComponent(in); got != want {
			t.Errorf("resolveComponent(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestCommName(t *testing.T) {
	if got := commName("firefox"); got != "firefox" {
		t.Errorf("short comm changed: %q", got)
	}
	if got := commName("/usr/bin/ryoku-shell"); got != "ryoku-shell" {
		t.Errorf("path base not taken: %q", got)
	}
	// The kernel records at most 15 bytes of the process name.
	long := commName("some-really-long-binary-name")
	if len(long) != 15 {
		t.Fatalf("long comm not truncated to 15: %q (len %d)", long, len(long))
	}
	if long != "some-really-lon" {
		t.Errorf("truncation wrong: %q", long)
	}
}

func TestDiscoverLogFiles(t *testing.T) {
	root := t.TempDir()
	mk := func(rel string, age time.Duration) string {
		p := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
		when := time.Now().Add(-age)
		if err := os.Chtimes(p, when, when); err != nil {
			t.Fatal(err)
		}
		return p
	}
	top := mk("a.log", 1*time.Hour) // newest
	mid := mk("sub/c.log", 2*time.Hour)
	deep := mk("sub/deep/d.log", 3*time.Hour) // oldest
	mk("b.txt", 0)                            // not a log, must be ignored
	mk("sub/e.txt", 0)                        // not a log

	// Depth 1: only files directly under root.
	if got := discoverLogFiles([]string{root}, 1, 10); len(got) != 1 || got[0] != top {
		t.Fatalf("depth 1 = %v, want just %s", got, top)
	}
	// Depth 2: root plus one level, newest first, non-.log ignored.
	got := discoverLogFiles([]string{root}, 2, 10)
	if len(got) != 2 || got[0] != top || got[1] != mid {
		t.Fatalf("depth 2 = %v, want [%s %s]", got, top, mid)
	}
	// Depth 3 reaches the deep file.
	if got := discoverLogFiles([]string{root}, 3, 10); len(got) != 3 || got[2] != deep {
		t.Fatalf("depth 3 = %v, want deep last", got)
	}
	// Count cap keeps only the newest.
	if got := discoverLogFiles([]string{root}, 3, 1); len(got) != 1 || got[0] != top {
		t.Fatalf("count cap = %v, want just newest", got)
	}
}

func TestRenderLogReportBounds(t *testing.T) {
	var big strings.Builder
	for i := 0; i < 1000; i++ {
		big.WriteString("line\n")
	}
	secs := []logSection{{head: "cmd", body: big.String()}}
	out := renderLogReport("thing", "", logsConfig{since: "6h", lines: 60}, secs)
	if n := strings.Count(out, "\n"); n > logsTotalLineCap+50 {
		t.Fatalf("bundle not bounded: %d lines for a %d-line source", n, 1000)
	}
	if !strings.Contains(out, "trimmed to the output budget") {
		t.Error("oversized section was not marked as trimmed")
	}
}

func TestLogsCommandTarget(t *testing.T) {
	for _, c := range []struct {
		args []string
		want string
	}{
		{[]string{"firefox"}, "firefox"},
		{[]string{"shell", "--since", "2h"}, "shell"},
		{[]string{"--lines", "10", "ryogami"}, "ryogami"},
	} {
		if got := logsCommandTarget(c.args); got != c.want {
			t.Errorf("logsCommandTarget(%v) = %q, want %q", c.args, got, c.want)
		}
	}
	// A sentence, extra tokens, or a broken flag must not shortcut to the command.
	for _, args := range [][]string{
		{"are", "huge", "how", "do", "i", "clean"},
		{"firefox", "crashed"},
		{"--since"},
		{},
	} {
		if got := logsCommandTarget(args); got != "" {
			t.Errorf("logsCommandTarget(%v) = %q, want fall-through", args, got)
		}
	}
}

func TestParseLogsArgs(t *testing.T) {
	target, cfg, err := parseLogsArgs([]string{"ryogami"})
	if err != nil || target != "ryogami" || cfg.since != logsDefaultSince || cfg.lines != logsDefaultLines {
		t.Fatalf("defaults wrong: %q %+v %v", target, cfg, err)
	}
	_, cfg, err = parseLogsArgs([]string{"x", "--since", "30m", "--lines", "5"})
	if err != nil || cfg.since != "30m" || cfg.lines != 5 {
		t.Fatalf("flags not parsed: %+v %v", cfg, err)
	}
	if _, _, err := parseLogsArgs([]string{"x", "--lines", "zero"}); err == nil {
		t.Error("non-numeric --lines accepted")
	}
}

func TestQuickshellInstanceFor(t *testing.T) {
	list := strings.Join([]string{
		"Instance aaa111:",
		"  Config path: /home/u/Work/iNiR/shell.qml",
		"Instance bbb222:",
		"  Config path: /home/u/.config/quickshell/shell/shell.qml",
	}, "\n")
	if got := quickshellInstanceFor(list, "/home/u/.config/quickshell/shell"); got != "bbb222" {
		t.Fatalf("matched %q, want bbb222", got)
	}
	if got := quickshellInstanceFor(list, "/nope"); got != "" {
		t.Fatalf("unexpected match %q", got)
	}
}

func TestJournalSince(t *testing.T) {
	if got := journalSince("6h"); got != "-6h" {
		t.Errorf("bare duration -> %q, want -6h", got)
	}
	if got := journalSince("-2h"); got != "-2h" {
		t.Errorf("already relative changed: %q", got)
	}
	if got := journalSince("yesterday"); got != "yesterday" {
		t.Errorf("absolute changed: %q", got)
	}
}

func TestUpdatesSectionsUseNativeTransactionSource(t *testing.T) {
	cfg := logsConfig{lines: 5}
	for manager, want := range map[string]string{
		"pacman": pacmanLogPath,
		"xbps":   xbpsLogPath,
	} {
		sections := updatesSectionsFor(manager, cfg)
		if got := sections[len(sections)-1].head; !strings.HasPrefix(got, want) {
			t.Errorf("%s transaction section = %q, want %q", manager, got, want)
		}
	}
	sections := updatesSectionsFor("", cfg)
	if got := sections[len(sections)-1].head; strings.Contains(got, "pacman") {
		t.Fatalf("unknown manager fell through to pacman: %q", got)
	}
}
