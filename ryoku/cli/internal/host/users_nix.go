package host

import (
	"encoding/json"
	"os"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// nixDeclaredUsersReason says why the users manager must not change accounts,
// or "" when it may. With users.mutableUsers = false NixOS rewrites
// /etc/passwd from the configuration on every switch, so an account added or
// changed here would silently disappear at the next rebuild.
func nixDeclaredUsersReason() string {
	if !sys.NixBackend() {
		return ""
	}
	path := os.Getenv("RYOKU_NIX_INTEGRATION")
	if path == "" {
		path = "/etc/ryoku/nix-integration.json"
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	var integration struct {
		MutableUsers *bool `json:"mutableUsers"`
	}
	if json.Unmarshal(raw, &integration) != nil || integration.MutableUsers == nil || *integration.MutableUsers {
		return ""
	}
	return i18n.T("This NixOS system declares its accounts in its configuration (users.mutableUsers = false). Add or change people there, then rebuild.")
}
