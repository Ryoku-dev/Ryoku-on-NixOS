package doctor

// A Ryoku session is Ryoku because ~/.config/<compositor>/ holds Ryoku's tree:
// its keybinds and the autostart line that starts the session target, the shell
// daemon and the wallpaper daemon. A package lays that tree under
// /usr/share/ryoku/config and writes nothing into ~/.config, and only the
// installer, the dev deploy, and an update on a box that already has it ever
// materialize -- so a plain package install boots a bare compositor: the
// compositor's own default keybinds, no shell, grey desktop, and nothing that
// tells the user why.
//
// This is the reconciler for that. It asks the seam which providers are installed
// and which one is live, notices a tree that is missing (or was pruned while the
// box ran the other compositor), lays the packaged tree with the same materialize
// the installer and update run, and -- for the live compositor only, whose
// session is the broken one right now -- starts what its autostart would have.

import (
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"
	"ryoku-cli/internal/updater"

	i18n "ryoku-i18n"
	wm "ryoku-wm"
)

// materializeNow is the config delivery `ryoku update` and the installer run.
// A var so a test drives the layout without a packaged base tree.
var materializeNow = updater.Materialize

// sessionLive reports whether the compositor this box is configured for is the
// one running now, which decides whether a repaired tree can be brought up
// without a relogin. A var so a test needs no live compositor.
var sessionLive = func() bool { return wm.Detect().Live }

// startSession brings a live but bare session up through the same guarded
// lifecycle entry point compositor autostart uses. A var keeps tests from
// restarting the desktop they run on.
var startSession = func() error {
	if sys.NixBackend() {
		return sys.Run("systemctl", "--user", "restart", "ryoku-session.target")
	}
	return sys.Run("ryoku-power-cutover", "session-start")
}

// shippedProviders lists the providers whose tree the packaged base carries, i.e.
// the ones whose variant package is installed. Reading the base rather than
// pacman keeps a checkout box honest: there the base is the repository and every
// provider counts as shipped.
func shippedProviders() []string {
	var out []string
	for _, name := range wm.Providers() {
		if dir := wm.ConfigDir(name); dir != "" && sys.Exists(filepath.Join(sys.BaseConfigDir(), dir)) {
			out = append(out, name)
		}
	}
	return out
}

// missingConfigTrees returns the shipped providers whose tree is not usable in
// ~/.config -- either not laid down at all, or laid but still missing the
// generated includes its entry point hard-requires (a fresh install whose
// materialize ran before any store existed rendered none, and niri treats a
// missing include as a hard parse error, so the first login dies). The live
// one is separated so the urgent case reads first.
func missingConfigTrees() (live, other []string) {
	active := wm.Detect().Name
	for _, name := range shippedProviders() {
		entry := wm.ConfigEntry(name)
		if entry == "" {
			continue
		}
		laid := sys.Exists(filepath.Join(sys.ConfigHome(), entry))
		if laid && !generatedIncludesMissing(name) {
			continue
		}
		if name == active {
			live = append(live, name)
		} else {
			other = append(other, name)
		}
	}
	return live, other
}

// generatedIncludesMissing reports whether a laid tree still lacks a file its
// provider generates. The user_edits mirrors are forks, not generated state:
// one of those standing is not a gap.
func generatedIncludesMissing(name string) bool {
	dir := wm.ConfigDir(name)
	if dir == "" {
		return false
	}
	for _, rel := range wm.GeneratedConfig(name) {
		d, _, ok := strings.Cut(rel, "/")
		if !ok || d != dir {
			continue
		}
		if !sys.Exists(filepath.Join(sys.ConfigHome(), rel)) {
			return true
		}
	}
	return false
}

func reconcileConfigTree(checkOnly bool) recResult {
	if !sys.Exists(sys.BaseConfigDir()) {
		// A checkout box deploys its own tree (`ryoku deploy`): no packaged base
		// to compare against, and nothing here to lay down.
		return okRes(i18n.T("no packaged config tree on this box"))
	}
	live, other := missingConfigTrees()
	if len(live) == 0 && len(other) == 0 {
		return okRes(i18n.T("the compositor config is laid down for every installed desktop"))
	}
	if checkOnly {
		return wouldRes("%s", configGapDetail(live, other)).
			withFix(i18n.T("ryoku doctor"))
	}

	if err := materializeNow(); err != nil {
		return failRes(i18n.T("could not lay down the compositor config: %v"), err).
			withFix(i18n.T("ryoku materialize"))
	}
	// The layout is proven by the entry points, not by materialize's exit code: a
	// base that no longer ships a tree leaves the compositor bare either way.
	stillLive, stillOther := missingConfigTrees()
	if len(stillLive) > 0 {
		return failRes("%s", configGapDetail(stillLive, stillOther)).
			withFix(i18n.T("install that desktop's package, then run `ryoku doctor` again"))
	}
	if len(live) > 0 && sessionLive() {
		// The session came up before the tree existed, so the compositor already
		// read its own defaults. The lifecycle helper holds sleep blocked until
		// qylock, shell, lid, and logout ownership are all proven.
		if err := startSession(); err != nil {
			return failRes(i18n.T("laid down the %s config but could not safely start the desktop: %v"),
				strings.Join(live, ", "), err).
				withFix(i18n.T("run `ryoku doctor` again from the live desktop"))
		}
		return fixedRes(i18n.T("laid down the %s config and started the desktop; log out and back in if a surface is still missing"),
			strings.Join(live, ", "))
	}
	return fixedRes(i18n.T("laid down the compositor config for %s"), strings.Join(append(live, other...), ", "))
}

// configGapDetail names the gap in the terms that matter: the live compositor's
// tree is why the desktop is bare (or, with the generated includes missing,
// why its session cannot start at all) now, and the other one is why
// switching back would boot a default session.
func configGapDetail(live, other []string) string {
	switch {
	case len(live) > 0 && len(other) > 0:
		return i18n.Tf("the config for %s (running now) and %s (switch back) is not laid down complete",
			strings.Join(live, ", "), strings.Join(other, ", "))
	case len(live) > 0:
		return i18n.Tf("the config for %s (running now) is not laid down complete, so the session keeps the compositor's own defaults or it cannot start",
			strings.Join(live, ", "))
	default:
		return i18n.Tf("the config for %s is not laid down complete, so switching back would boot a default session",
			strings.Join(other, ", "))
	}
}
