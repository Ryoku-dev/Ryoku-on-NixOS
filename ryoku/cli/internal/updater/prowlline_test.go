package updater

import (
	"strings"
	"testing"

	"ryoku-cli/internal/host"
)

func TestTheProwlLineNamesTheManagerTheHostRuns(t *testing.T) {
	for _, c := range []struct {
		manager host.PackageManager
		want    string
	}{
		{host.Pacman, "prowl is managed by pacman; refreshed with the system packages"},
		{host.XBPS, "prowl is managed by xbps; refreshed with the system packages"},
		{host.DNF, "prowl is managed by dnf; refreshed with the system packages"},
		{"", "prowl comes from a package; refreshed with the system packages"},
	} {
		if got := prowlManagedLine(c.manager); got != c.want {
			t.Errorf("on %q the line reads %q, wanted %q", c.manager, got, c.want)
		}
	}
	if got := prowlManagedLine(host.XBPS); strings.Contains(got, "pacman") {
		t.Errorf("a Void box was told about pacman: %q", got)
	}
}
