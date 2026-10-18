package main

import (
	"net/http/httptest"
	"strings"
	"testing"
)

// runs collects the Run field of every command in a plan for comparison.
func runs(p *termPlan) []string {
	if p == nil {
		return nil
	}
	out := make([]string, 0, len(p.Commands))
	for _, c := range p.Commands {
		out = append(out, c.Run)
	}
	return out
}

func eqStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// TestPlanFromText covers the three lift paths: a fenced block (language tag
// and `#` comment lines dropped), `$ `-prefixed prose lines, and prose with no
// commands (nil).
func TestPlanFromText(t *testing.T) {
	cases := []struct {
		name   string
		answer string
		want   []string // nil means planFromText must return nil
	}{
		{
			name:   "fenced drops tag and comment",
			answer: "Here's the plan:\n```bash\n# update the system first\nsudo pacman -Syu\neza -la\n```\nThat's it.",
			want:   []string{"sudo pacman -Syu", "eza -la"},
		},
		{
			name:   "dollar prefixed prose lines",
			answer: "To list files, run:\n$ eza -la\nThen inspect:\n$ bat notes.md\nDone.",
			want:   []string{"eza -la", "bat notes.md"},
		},
		{
			name:   "prose without commands is nil",
			answer: "This is just an explanation with no runnable commands.",
			want:   nil,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := planFromText(tc.answer)
			if tc.want == nil {
				if got != nil {
					t.Fatalf("planFromText(%q) = %+v, want nil", tc.answer, got)
				}
				return
			}
			if got == nil {
				t.Fatalf("planFromText(%q) = nil, want %v", tc.answer, tc.want)
			}
			if !eqStrings(runs(got), tc.want) {
				t.Fatalf("planFromText(%q) runs = %v, want %v", tc.answer, runs(got), tc.want)
			}
		})
	}
}

// TestValidatePlan proves validatePlan drops empty commands, tiers every
// survivor, and forces Oneliner to be true iff exactly one command remains
// (in both directions).
func TestValidatePlan(t *testing.T) {
	t.Setenv("HOME", t.TempDir())

	t.Run("drops empty, tiers survivors, oneliner off for many", func(t *testing.T) {
		// Oneliner starts true but two survive, so it must be forced false.
		p := &termPlan{
			Oneliner: true,
			Commands: []termCommand{
				{Run: "rm -rf ~"},
				{Run: "   "}, // whitespace-only: dropped
				{Run: "eza -la"},
			},
		}
		validatePlan(p)

		if len(p.Commands) != 2 {
			t.Fatalf("commands = %d, want 2 (empty dropped)", len(p.Commands))
		}
		if p.Commands[0].Run != "rm -rf ~" || p.Commands[1].Run != "eza -la" {
			t.Fatalf("survivors = %v", runs(p))
		}
		if p.Commands[0].Tier != "danger" {
			t.Errorf("rm -rf ~ tier = %q, want danger", p.Commands[0].Tier)
		}
		if p.Commands[1].Tier != "read" {
			t.Errorf("eza -la tier = %q, want read", p.Commands[1].Tier)
		}
		if p.Oneliner {
			t.Error("Oneliner must be false when more than one command remains")
		}
		for _, c := range p.Commands {
			if c.Tier == "" {
				t.Errorf("command %q got empty tier", c.Run)
			}
		}
	})

	t.Run("oneliner forced true when one survives", func(t *testing.T) {
		// Oneliner starts false but only one survives, so it must be true.
		p := &termPlan{
			Oneliner: false,
			Commands: []termCommand{
				{Run: "rm -rf ~"},
				{Run: ""}, // dropped
			},
		}
		validatePlan(p)

		if len(p.Commands) != 1 {
			t.Fatalf("commands = %d, want 1", len(p.Commands))
		}
		if p.Commands[0].Tier != "danger" {
			t.Errorf("tier = %q, want danger", p.Commands[0].Tier)
		}
		if !p.Oneliner {
			t.Error("Oneliner must be true when exactly one command remains")
		}
	})
}

// TestStripCodeFences proves prose survives while fenced blocks and `$ `-prefixed
// command lines are removed, blank runs collapse to a single blank line, and the
// result is trimmed -- so a fence-only answer (whose commands were already lifted
// into the plan) renders as nothing rather than a second copy.
func TestStripCodeFences(t *testing.T) {
	cases := []struct {
		name   string
		answer string
		want   string
	}{
		{
			name:   "fence only becomes empty",
			answer: "```sh\ncd ~/.config/kitty\n```",
			want:   "",
		},
		{
			name:   "prose kept, fence dropped",
			answer: "The config is here.\n```sh\ncd ~/x\n```",
			want:   "The config is here.",
		},
		{
			name:   "dollar prefixed command removed",
			answer: "Run this:\n$ ls -la",
			want:   "Run this:",
		},
		{
			name:   "plain prose preserved",
			answer: "First line.\nSecond line.",
			want:   "First line.\nSecond line.",
		},
		{
			name:   "blank runs collapse and edges trimmed",
			answer: "   \n\nIntro paragraph.\n\n\nSecond paragraph.\n\n   ",
			want:   "Intro paragraph.\n\nSecond paragraph.",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := stripCodeFences(tc.answer); got != tc.want {
				t.Errorf("stripCodeFences(%q) = %q, want %q", tc.answer, got, tc.want)
			}
		})
	}
}

func TestFinishTermRecordsIDAndSourceWithoutAgentBroadcast(t *testing.T) {
	quickTestEnv(t)
	agentHub := newChatHub(ryokuLane())
	client := &chatClient{out: make(chan wsOut, 2)}
	agentHub.mu.Lock()
	agentHub.clients[client] = true
	agentHub.mu.Unlock()
	askHub := newChatHub(askLane())
	res := httptest.NewRecorder()
	sink := &askSink{w: res, f: res}
	askHub.finishTerm(sink, "t1", termReq{Q: "where am I"}, "Here.", nil, "Prowl · model", "")
	if len(agentHub.transcript) != 0 || len(client.out) != 0 {
		t.Fatalf("terminal answer reached Agent: transcript=%+v queued=%d", agentHub.transcript, len(client.out))
	}
	if body := res.Body.String(); !strings.Contains(body, `"id":"t1"`) || !strings.Contains(body, `"via":"Prowl · model"`) {
		t.Fatalf("answer marker = %s", body)
	}
	recent := RecentAsks(1)
	if len(recent) != 1 || recent[0].ID != "t1" || recent[0].Via != "Prowl · model" {
		t.Fatalf("recent terminal record = %+v", recent)
	}
}
