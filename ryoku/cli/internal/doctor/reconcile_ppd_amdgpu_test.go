package doctor

import (
	"strings"
	"testing"

	"github.com/godbus/dbus/v5"
)

func ppdState(panel, abm, dpm bool) ppdAmdgpuState {
	return ppdAmdgpuState{
		amdgpuDrivesPanel: panel,
		provider:          "power-profiles-daemon",
		actionsAvailable:  true,
		actions: map[string]bool{
			"amdgpu_panel_power": abm,
			"amdgpu_dpm":         dpm,
		},
	}
}

func TestPpdActions(t *testing.T) {
	raw := []map[string]dbus.Variant{
		{"Name": dbus.MakeVariant("amdgpu_panel_power"), "Enabled": dbus.MakeVariant(false)},
		{"Name": dbus.MakeVariant("amdgpu_dpm"), "Enabled": dbus.MakeVariant(true)},
		{"Name": dbus.MakeVariant(7), "Enabled": dbus.MakeVariant(true)},
	}
	actions, available := ppdActions(raw)
	if !available {
		t.Fatal("ActionsInfo was not recognized")
	}
	if actions["amdgpu_panel_power"] || !actions["amdgpu_dpm"] {
		t.Fatalf("actions = %v", actions)
	}
	if _, available := ppdActions([]string{"amdgpu_dpm"}); available {
		t.Fatal("a provider without ActionsInfo was recognized as power-profiles-daemon")
	}
}

func TestPlanPpdAmdgpu(t *testing.T) {
	t.Run("silent without amdgpu panel", func(t *testing.T) {
		r := planPpdAmdgpu(ppdState(false, true, true))
		if r.status != recOK {
			t.Fatalf("status = %v, want ok", r.status)
		}
	})

	t.Run("not applicable without provider", func(t *testing.T) {
		r := planPpdAmdgpu(ppdAmdgpuState{amdgpuDrivesPanel: true})
		if r.status != recOK || !strings.Contains(r.detail, "not applicable") {
			t.Fatalf("result = %v %q, want not-applicable ok", r.status, r.detail)
		}
	})

	t.Run("tuned provider has no ppd action audit", func(t *testing.T) {
		r := planPpdAmdgpu(ppdAmdgpuState{
			amdgpuDrivesPanel: true,
			provider:          "tuned-ppd",
			actionsAvailable:  false,
		})
		if r.status != recOK || !strings.Contains(r.detail, "not applicable") {
			t.Fatalf("result = %v %q, want not-applicable ok", r.status, r.detail)
		}
	})

	t.Run("clean actions pass", func(t *testing.T) {
		r := planPpdAmdgpu(ppdState(true, false, false))
		if r.status != recOK {
			t.Fatalf("status = %v, want ok", r.status)
		}
	})

	t.Run("enabled dpm warns about saver lag", func(t *testing.T) {
		r := planPpdAmdgpu(ppdState(true, false, true))
		if r.status != recWarn || !strings.Contains(r.detail, "power-saver") {
			t.Fatalf("result = %v %q", r.status, r.detail)
		}
	})

	t.Run("enabled abm warns about colours", func(t *testing.T) {
		r := planPpdAmdgpu(ppdState(true, true, false))
		if r.status != recWarn || !strings.Contains(r.detail, "ABM") {
			t.Fatalf("result = %v %q", r.status, r.detail)
		}
	})

	t.Run("both enabled warn once", func(t *testing.T) {
		r := planPpdAmdgpu(ppdState(true, true, true))
		if r.status != recWarn || !strings.Contains(r.detail, "amdgpu_dpm and amdgpu_panel_power") {
			t.Fatalf("result = %v %q", r.status, r.detail)
		}
	})
}
