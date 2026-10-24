package doctor

import (
	"errors"
	"strings"
	"testing"
)

func TestPlanWifiBssidPins(t *testing.T) {
	noRepair := func(string) error { t.Fatal("repair must not run"); return nil }

	t.Run("no pins passes", func(t *testing.T) {
		r := planWifiBssidPins(nil, nil, true, noRepair)
		if r.status != recOK {
			t.Fatalf("status = %v, want ok", r.status)
		}
	})

	t.Run("unreadable profiles warn without repairing", func(t *testing.T) {
		r := planWifiBssidPins(nil, errors.New("no nmcli"), true, noRepair)
		if r.status != recWarn {
			t.Fatalf("status = %v, want warn", r.status)
		}
	})

	t.Run("pinned profile reports in check mode", func(t *testing.T) {
		pinned := []pinnedBssidProfile{{name: "Home 5G", bssid: "AA:BB:CC:DD:EE:FF"}}
		r := planWifiBssidPins(pinned, nil, true, noRepair)
		if r.status != recWouldFix || !strings.Contains(r.detail, "Home 5G") {
			t.Fatalf("result = %v %q", r.status, r.detail)
		}
	})

	t.Run("pinned profiles unpin in apply mode", func(t *testing.T) {
		pinned := []pinnedBssidProfile{
			{name: "Home 5G", bssid: "AA:BB:CC:DD:EE:FF"},
			{name: "Office", bssid: "11:22:33:44:55:66"},
		}
		var got []string
		r := planWifiBssidPins(pinned, nil, false, func(name string) error {
			got = append(got, name)
			return nil
		})
		if r.status != recFixed || len(got) != 2 || got[0] != "Home 5G" || got[1] != "Office" {
			t.Fatalf("status=%v repaired=%v", r.status, got)
		}
	})

	t.Run("a failed unpin names the profile", func(t *testing.T) {
		pinned := []pinnedBssidProfile{{name: "Home 5G", bssid: "AA:BB:CC:DD:EE:FF"}}
		r := planWifiBssidPins(pinned, nil, false, func(string) error { return errors.New("denied") })
		if r.status != recFailed || !strings.Contains(r.detail, "Home 5G") {
			t.Fatalf("result = %v %q", r.status, r.detail)
		}
	})
}

func TestWifiBssidTerseFields(t *testing.T) {
	got := terseFields(`Carlos\302\222s iPhone:802-11-wireless`)
	if len(got) != 2 || got[1] != "802-11-wireless" {
		t.Fatalf("fields = %q", got)
	}
	got = terseFields(`a\\b\:c:802-11-wireless`)
	if len(got) != 2 || got[0] != `a\b:c` {
		t.Fatalf("escaped fields = %q, want name `a\\b:c`", got)
	}
}
