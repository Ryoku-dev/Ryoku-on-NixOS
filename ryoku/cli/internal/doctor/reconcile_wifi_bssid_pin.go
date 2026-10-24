package doctor

import (
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// ---- reconciler: Wi-Fi profiles pinned to one access point -------------------
//
// The Hub's Connections page used to join a band-picked network through
// `nmcli dev wifi connect <BSSID>`, which writes 802-11-wireless.bssid into
// the saved profile. A BSSID-pinned profile can never roam: on a multi-AP
// 5 GHz network the access points steer the client between themselves, the
// pinned profile forces it back, and the association cycles. The reports read
// as "the 5 GHz connection keeps reconnecting", and the same network works
// from nmtui, which joins by SSID with no pin. The Hub now pins only the band
// (802-11-wireless.band), which keeps the 5 GHz choice without freezing the
// AP. Profiles already written by the old join keep the stale pin across
// updates, so this check drops it: every Wi-Fi profile whose bssid is set
// loses the pin, and the client roams inside whatever band the profile names.
//
// Silent on a box with no Wi-Fi profiles, and on profiles with no pin, which
// is every profile a current Hub or nmtui joined.

// pinnedBssidProfile is one saved Wi-Fi profile and the AP it is stuck to.
type pinnedBssidProfile struct {
	name  string
	bssid string
}

// listPinnedBssidProfiles reads the Wi-Fi profiles and their bssid pins. A var
// so a test drives the verdict without NetworkManager on the box.
var listPinnedBssidProfiles = func() ([]pinnedBssidProfile, error) {
	names, err := sys.RunOut("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show")
	if err != nil {
		return nil, err
	}
	var pinned []pinnedBssidProfile
	for _, line := range strings.Split(names, "\n") {
		fields := terseFields(line)
		if len(fields) < 2 || fields[1] != "802-11-wireless" || fields[0] == "" {
			continue
		}
		bssid, err := sys.RunOut("nmcli", "-g", "802-11-wireless.bssid", "connection", "show", fields[0])
		if err != nil {
			continue
		}
		if bssid = strings.TrimSpace(bssid); bssid != "" {
			pinned = append(pinned, pinnedBssidProfile{name: fields[0], bssid: bssid})
		}
	}
	return pinned, nil
}

// terseFields splits one `-t` nmcli line on unescaped colons, undoing the
// `\\:` and `\\\\` escaping nmcli applies inside values, so a profile whose
// name contains a colon (or a backslash) survives the round trip.
func terseFields(line string) []string {
	var fields []string
	var cur strings.Builder
	for i := 0; i < len(line); i++ {
		switch c := line[i]; c {
		case '\\':
			if i+1 < len(line) && (line[i+1] == ':' || line[i+1] == '\\') {
				cur.WriteByte(line[i+1])
				i++
			} else {
				cur.WriteByte(c)
			}
		case ':':
			fields = append(fields, cur.String())
			cur.Reset()
		default:
			cur.WriteByte(c)
		}
	}
	fields = append(fields, cur.String())
	return fields
}

// unpinBssidProfile drops the AP pin from one profile. nmcli's modify clears a
// string property with an empty value; the band (if any) stays, so the profile
// keeps its band lock and regains roaming inside it. A var so a test records
// the repairs without touching a real profile store.
var unpinBssidProfile = func(name string) error {
	return sys.Sudo("nmcli", "connection", "modify", name, "802-11-wireless.bssid", "")
}

// planWifiBssidPins turns the observed pins into a result. pure.
func planWifiBssidPins(pinned []pinnedBssidProfile, err error, checkOnly bool, unpin func(string) error) recResult {
	if err != nil {
		return warnRes(i18n.T("could not read the Wi-Fi profiles; leaving any access-point pin alone: %v"), err)
	}
	if len(pinned) == 0 {
		return okRes(i18n.T("no Wi-Fi profile is pinned to one access point"))
	}
	names := make([]string, len(pinned))
	for i, p := range pinned {
		names[i] = p.name
	}
	joined := strings.Join(names, ", ")
	if checkOnly {
		return wouldRes(i18n.T("%d Wi-Fi profile(s) are pinned to one access point and cannot roam: %s"),
			len(pinned), joined).
			withFix(i18n.T("ryoku doctor drops the pin so the network roams again"))
	}
	var failed []string
	for _, p := range pinned {
		if err := unpin(p.name); err != nil {
			failed = append(failed, p.name)
		}
	}
	if len(failed) > 0 {
		return failRes(i18n.T("could not unpin %d access-point-pinned profile(s): %s"),
			len(failed), strings.Join(failed, ", ")).
			withFix("ryoku doctor")
	}
	return fixedRes(i18n.T("dropped the access-point pin from %d Wi-Fi profile(s): %s; they roam again"),
		len(pinned), joined)
}

func reconcileWifiBssidPin(checkOnly bool) recResult {
	pinned, err := listPinnedBssidProfiles()
	return planWifiBssidPins(pinned, err, checkOnly, unpinBssidProfile)
}
