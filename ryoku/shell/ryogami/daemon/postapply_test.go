package main

import (
	"strings"
	"testing"
)

func TestExpandPostPlaceholders(t *testing.T) {
	got := expandPostPlaceholders("set %type% %name% %path% %thumb%", "video", "clip.mp4", "/w/clip.mp4", "/c/clip.webp")
	want := "set 'video' 'clip.mp4' '/w/clip.mp4' '/c/clip.webp'"
	if got != want {
		t.Fatalf("expansion:\n got %q\nwant %q", got, want)
	}
}

// Filenames are attacker-influenced: quotes and metacharacters must stay inside the quoted argument.
func TestExpandPostPlaceholdersQuotesHostileNames(t *testing.T) {
	name := "a'; rm -rf ~ #.png"
	got := expandPostPlaceholders("setter %name%", "static", name, "/w/"+name, "")
	if strings.Contains(got, "; rm -rf") && !strings.Contains(got, `'\''`) {
		t.Fatalf("hostile name was not neutralised: %q", got)
	}
	if !strings.Contains(got, `'a'\''; rm -rf ~ #.png'`) {
		t.Fatalf("expected shell-safe quoting, got %q", got)
	}
}

func TestExpandPostPlaceholdersEmptyThumb(t *testing.T) {
	got := expandPostPlaceholders("%thumb%", "static", "x.png", "/w/x.png", "")
	if got != "''" {
		t.Fatalf("empty thumb should render as empty quoted string, got %q", got)
	}
}

func TestPostProcessCommandTypeFilter(t *testing.T) {
	cmds := parsePostCommands([]interface{}{
		"echo bare",
		map[string]interface{}{"command": "echo vid", "type": "video"},
		map[string]interface{}{"command": "   ", "type": "static"},
		map[string]interface{}{"type": "static"},
	})
	if len(cmds) != 2 {
		t.Fatalf("expected 2 commands (bare + video), got %d: %+v", len(cmds), cmds)
	}
	if cmds[0].typ != "all" || cmds[1].typ != "video" {
		t.Fatalf("types wrong: %+v", cmds)
	}
}
