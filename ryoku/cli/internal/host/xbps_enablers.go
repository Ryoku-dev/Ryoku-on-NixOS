package host

import "strings"

// Void keeps 32-bit and non-free software in official repositories that stay
// off until their void-repo-* package is installed. A table row names the
// repositories its packages need in its notes (repo=nonfree, or a list such as
// repo=nonfree,multilib when the package and its 32-bit companions live apart).
// Ryoku's own repo=ryoku is configured by the installer and needs no enabler.
var xbpsEnablerPackages = map[string]string{
	"multilib":         "void-repo-multilib",
	"nonfree":          "void-repo-nonfree",
	"multilib-nonfree": "void-repo-multilib-nonfree",
}

// xbpsEnablers lists the enabler packages one row needs, in the order named.
func xbpsEnablers(mapping packageMapping) []string {
	repos, ok := strings.CutPrefix(strings.TrimSpace(mapping.Note), "repo=")
	if !ok {
		return nil
	}
	var enablers []string
	for _, repo := range strings.Split(repos, ",") {
		if enabler := xbpsEnablerPackages[strings.TrimSpace(repo)]; enabler != "" {
			enablers = append(enablers, enabler)
		}
	}
	return enablers
}

// xbpsEnablersFor lists, once each and in first-use order, the enablers the
// named rows need.
func xbpsEnablersFor(table packageTable, names []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, name := range names {
		for _, enabler := range xbpsEnablers(translatePackage(table, name)) {
			if !seen[enabler] {
				seen[enabler] = true
				out = append(out, enabler)
			}
		}
	}
	return out
}

// ensureXBPSEnablers installs the enablers that are not installed yet, so the
// package transaction that follows syncs their repositories too.
func (a *App) ensureXBPSEnablers(enablers []string) int {
	var missing []string
	for _, enabler := range enablers {
		if a.probe("xbps-query", enabler).Code != 0 {
			missing = append(missing, enabler)
		}
	}
	if len(missing) == 0 {
		return ExitOK
	}
	return commandExit(a.run("xbps-install", append([]string{"-Sy"}, missing...)...))
}

// xbpsRowAvailable answers whether one row can be installed on this host: its
// packages are in the enabled repositories, or a repository it needs is still
// off and its enabler can be installed (the table vouches for the rest).
func xbpsRowAvailable(mapping packageMapping, installed func(string) bool, remote func(string) bool) bool {
	pending := false
	for _, enabler := range xbpsEnablers(mapping) {
		if installed(enabler) {
			continue
		}
		if !remote(enabler) {
			return false
		}
		pending = true
	}
	if pending {
		return true
	}
	for _, name := range mapping.Names {
		if !remote(name) {
			return false
		}
	}
	return true
}
