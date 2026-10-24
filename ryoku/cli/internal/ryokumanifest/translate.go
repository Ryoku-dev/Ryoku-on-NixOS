package ryokumanifest

import (
	"fmt"
	"sort"
	"strings"
)

// Translation is one Arch name's row in an edition's translation table.
type Translation struct {
	Names []string
	Lanes []string
}

// Translate rewrites an Arch-named manifest in an edition's package names.
// The converge lanes keep only rows in lane, the set the edition's installer
// installs; otherwise the first update would install the host's own system
// packages and optional apps onto an existing host.
func Translate(m Manifest, table map[string]Translation, lane string) (Manifest, error) {
	missing := map[string]bool{}
	translate := func(names []string, filter bool) []string {
		set := map[string]bool{}
		for _, name := range names {
			row, ok := table[name]
			if !ok {
				missing[name] = true
				continue
			}
			if filter && !contains(row.Lanes, lane) {
				continue
			}
			for _, native := range row.Names {
				set[native] = true
			}
		}
		out := make([]string, 0, len(set))
		for name := range set {
			out = append(out, name)
		}
		sort.Strings(out)
		return out
	}
	translateMap := func(sections map[string][]string) map[string][]string {
		if sections == nil {
			return nil
		}
		out := map[string][]string{}
		for section, names := range sections {
			if native := translate(names, false); len(native) > 0 {
				out[section] = native
			}
		}
		return out
	}

	out := m
	out.Base = translate(m.Base, true)
	out.Dev = translate(m.Dev, true)
	out.AUR = translate(m.AUR, true)
	out.FirstParty = translate(m.FirstParty, true)
	out.Hardware = translateMap(m.Hardware)
	out.Compositor = translateMap(m.Compositor)
	out.Provisioned = translate(m.Provisioned, false)
	if len(missing) > 0 {
		names := make([]string, 0, len(missing))
		for name := range missing {
			names = append(names, name)
		}
		sort.Strings(names)
		return Manifest{}, fmt.Errorf("no translation row for %s", strings.Join(names, ", "))
	}
	return out, nil
}
