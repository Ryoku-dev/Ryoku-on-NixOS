package host

import (
	"fmt"
	"os"
)

// The catalogue overlay names packages Ryoku's edition tables never list: the
// RyoStore bundles map their own Arch catalogue names to each edition in a
// table of the same format. `pkg --overlay PATH` (or RYOKU_HOST_PKG_OVERLAY)
// lays it under the edition table, so Ryoku's own mapping wins and a name in
// neither table keeps its identity fallback. The option crosses sudo, which
// drops the environment.
func (a *App) packageOverlayArgs(args []string) ([]string, bool) {
	a.overlay = a.getenv("RYOKU_HOST_PKG_OVERLAY")
	if len(args) == 0 || args[0] != "--overlay" {
		return args, true
	}
	if len(args) < 3 || args[1] == "" {
		return nil, false
	}
	a.overlay = args[1]
	return args[2:], true
}

func (a *App) withOverlay(table packageTable, distribution string) (packageTable, error) {
	if a.overlay == "" {
		return table, nil
	}
	overlay, err := readPackageTableFor(a.overlay, distribution)
	if os.IsNotExist(err) {
		fmt.Fprintf(a.cfg.Stderr, "ryoku-host: warning: package overlay %s is missing; using the edition table only\n", a.overlay)
		return table, nil
	}
	if err != nil {
		return nil, fmt.Errorf("package overlay: %w", err)
	}
	merged := make(packageTable, len(table)+len(overlay))
	for name, mapping := range overlay {
		merged[name] = mapping
	}
	for name, mapping := range table {
		merged[name] = mapping
	}
	return merged, nil
}
