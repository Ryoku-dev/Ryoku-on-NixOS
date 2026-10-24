package doctor

import (
	"fmt"
	"os"
	"strings"

	"github.com/godbus/dbus/v5"
	i18n "ryoku-i18n"
)

// ---- reconciler: power-profiles-daemon vs the AMD compositor GPU ------------
//
// power-profiles-daemon 0.30 ships two optional actions aimed at amdgpu. Both
// default off, and both are wrong for a Ryoku desktop whose compositor renders
// on the AMD iGPU (the default once no render pin exists):
//
//   amdgpu_dpm          forces the GPU's dynamic power management level down in
//                       the power-saver profile: the profile meant to save the
//                       battery clamps the very GPU drawing every frame, and the
//                       whole desktop turns to syrup the moment saver engages.
//   amdgpu_panel_power  drives the panel's adaptive backlight (ABM), which
//                       visibly washes out colours on the shipped themes.
//
// Field reports pin exactly this: "saver mode lags the desktop" with a healthy
// system, and the culprit is the enabled dpm action. Toggling ppd actions is
// the user's policy (a distro config or a deliberate choice), so this check
// REPORTS only and never rewrites power-profiles-daemon configuration.

// ppdAmdgpuState is what the verdict needs: whether an amdgpu card drives a
// connected connector, which provider owns the standard PowerProfiles name,
// and power-profiles-daemon's optional action state.
type ppdAmdgpuState struct {
	amdgpuDrivesPanel bool
	provider          string
	actions           map[string]bool
	actionsAvailable  bool
}

var gatherPpdAmdgpu = func() ppdAmdgpuState {
	var s ppdAmdgpuState
	cards := drmCards()
	for _, connected := range connectedConnectorCards() {
		if cards[connected].driver == "amdgpu" {
			s.amdgpuDrivesPanel = true
			break
		}
	}
	conn, err := dbus.ConnectSystemBus()
	if err != nil {
		return s
	}
	defer conn.Close()
	s.provider = powerProfilesProvider(conn)
	obj := conn.Object("org.freedesktop.UPower.PowerProfiles", dbus.ObjectPath("/org/freedesktop/UPower/PowerProfiles"))
	v, err := obj.GetProperty("org.freedesktop.UPower.PowerProfiles.ActionsInfo")
	if err == nil {
		s.actions, s.actionsAvailable = ppdActions(v.Value())
		if s.actionsAvailable {
			s.provider = "power-profiles-daemon"
		}
	}
	return s
}

func powerProfilesProvider(conn *dbus.Conn) string {
	var pid uint32
	if err := conn.BusObject().Call("org.freedesktop.DBus.GetConnectionUnixProcessID", 0,
		"org.freedesktop.UPower.PowerProfiles").Store(&pid); err != nil {
		return ""
	}
	raw, err := os.ReadFile(fmt.Sprintf("/proc/%d/comm", pid))
	if err != nil {
		return ""
	}
	name := strings.TrimSpace(string(raw))
	if strings.HasPrefix(name, "power-profiles-") {
		return "power-profiles-daemon"
	}
	return name
}

func ppdActions(v any) (map[string]bool, bool) {
	rows, ok := v.([]map[string]dbus.Variant)
	if !ok {
		return nil, false
	}
	actions := make(map[string]bool, len(rows))
	for _, row := range rows {
		name, nameOK := row["Name"].Value().(string)
		enabled, enabledOK := row["Enabled"].Value().(bool)
		if nameOK && enabledOK {
			actions[name] = enabled
		}
	}
	return actions, true
}

// planPpdAmdgpu turns observed state into a result. pure.
func planPpdAmdgpu(s ppdAmdgpuState) recResult {
	if s.provider != "power-profiles-daemon" || !s.actionsAvailable {
		return okRes(i18n.T("not applicable: the active power-profile provider does not expose power-profiles-daemon actions"))
	}
	if !s.amdgpuDrivesPanel {
		return okRes(i18n.T("no amdgpu-driven panel with power-profiles-daemon actions to audit"))
	}
	dpm := s.actions["amdgpu_dpm"]
	abm := s.actions["amdgpu_panel_power"]
	switch {
	case dpm && abm:
		return warnRes(i18n.T("power-profiles-daemon has amdgpu_dpm and amdgpu_panel_power enabled: power-saver will clamp the GPU rendering the desktop (visible lag) and ABM will wash panel colours. Disable them in the power-profiles-daemon action configuration"))
	case dpm:
		return warnRes(i18n.T("power-profiles-daemon has amdgpu_dpm enabled: the power-saver profile clamps the GPU rendering the desktop, which shows up as whole-desktop lag in saver mode. Disable the action in the power-profiles-daemon configuration"))
	case abm:
		return warnRes(i18n.T("power-profiles-daemon has amdgpu_panel_power enabled: adaptive backlight (ABM) visibly washes out panel colours. Disable the action in the power-profiles-daemon configuration"))
	default:
		return okRes(i18n.T("power-profiles-daemon leaves the AMD compositor GPU alone (amdgpu actions disabled)"))
	}
}

func reconcilePpdAmdgpu(_ bool) recResult {
	return planPpdAmdgpu(gatherPpdAmdgpu())
}
