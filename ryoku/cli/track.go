package main

import (
	"fmt"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
	"ryoku-cli/internal/updater"
	i18n "ryoku-i18n"
	"strings"
)

// trackScriptURL is where a box with no local checkout fetches bin/ryoku-track
// from: the copy on the branch it is about to track. The main copy lags
// unstable-dev between releases, and the script's edition support travels
// with the branch, so fetching main's copy for unstable-dev ran the previous
// release's installer against the current tree.
func trackScriptURL(branch string) string {
	return "https://raw.githubusercontent.com/ryoku-dev/ryoku/" + branch + "/bin/ryoku-track"
}

// sourceBranches maps source-backed tracks to the branch bin/ryoku-track builds.
// Unstable always uses this lane; stable selects it only with --source.
var sourceBranches = map[string]string{
	sys.ChannelStable:   "main",
	sys.ChannelUnstable: "unstable-dev",
	sys.ChannelTesting:  "unstable-dev",
}

// cmdTrack points the box at an update channel. Unstable (and its quiet testing
// synonym) follows unstable-dev from a source checkout; --source remains
// accepted there for compatibility. Stable uses packages unless --source asks
// for main. Frozen release tags and unstable build names remain package pins.
// The old main/unstable-dev arguments fail with their replacement.
func cmdTrack(args []string) error {
	channel, source, err := parseTrackArgs(args)
	if err != nil {
		return err
	}
	if repl := retiredTrackName(channel); repl != "" {
		return fmt.Errorf(i18n.T("`ryoku track %s` was retired; use `ryoku track %s`"), channel, repl)
	}
	branch := sourceBranches[channel]
	if source || channel == sys.ChannelUnstable || channel == sys.ChannelTesting {
		if branch == "" {
			return fmt.Errorf(i18n.T("`--source` builds from a checkout and takes stable or unstable, not %q"), channel)
		}
		return trackFromSource(branch)
	}
	pkg := packageChannelFor(channel)
	if pkg == "" {
		return fmt.Errorf(i18n.T("unknown channel %q\n"+
			"  stable:   signed release packages (add --source for a main checkout)\n"+
			"  unstable: unstable-dev source checkout\n"+
			"  frozen:   a release tag or unstable build"), channel)
	}
	return updater.Track(pkg)
}

// retiredTrackName maps a retired track argument to its replacement, or "" when
// the name is still accepted. `main` and `unstable-dev` named the git branches a
// tester once tracked; the channels they selected are now `stable`/`unstable`.
func retiredTrackName(name string) string {
	switch name {
	case "main":
		return sys.ChannelStable
	case "unstable-dev":
		return sys.ChannelUnstable
	}
	return ""
}

// parseTrackArgs pulls the one channel and optional compatibility --source flag
// (either order) out of the track arguments.
func parseTrackArgs(args []string) (channel string, source bool, err error) {
	for _, a := range args {
		switch {
		case a == "--source":
			source = true
		case strings.HasPrefix(a, "-"):
			return "", false, fmt.Errorf(i18n.T("unknown flag %q (only --source is accepted)"), a)
		case channel != "":
			return "", false, fmt.Errorf(i18n.T("track takes one channel, got %q and %q"), channel, a)
		default:
			channel = a
		}
	}
	if channel == "" {
		return "", false, fmt.Errorf(i18n.T("usage: ryoku track unstable\n" +
			"       ryoku track stable [--source]\n" +
			"       ryoku track v<release-or-build>"))
	}
	return channel, source, nil
}

// packageChannelFor maps a package-backed track argument to its repository.
// Unstable and testing are intercepted by cmdTrack; retaining their mapping here
// keeps frozen-name recognition and channel vocabulary in one place.
func packageChannelFor(name string) string {
	if name == sys.ChannelUnstable {
		return sys.ChannelTesting
	}
	if sys.ChannelServer(name) != "" {
		return name
	}
	return ""
}

// trackFromSource hands off to bin/ryoku-track, which builds and deploys the box
// from a git checkout of main or unstable-dev. It prefers a local checkout's
// copy and otherwise fetches the canonical one, so source tracking works from a
// packaged install with no checkout. The script does the real work and does not
// lean on this binary.
func trackFromSource(branch string) error {
	if repo := sys.ResolveRepo(); repo != "" {
		if script := filepath.Join(repo, "bin", "ryoku-track"); sys.Exists(script) {
			return sys.Run("bash", script, branch)
		}
	}
	if !sys.Has("curl") {
		return fmt.Errorf(i18n.T("no local track script and curl is missing; run it by hand:\n  curl -fsSL %s | bash -s -- %s"), trackScriptURL(branch), branch)
	}
	tmp, err := os.CreateTemp("", "ryoku-track-*.sh")
	if err != nil {
		return err
	}
	tmp.Close()
	defer os.Remove(tmp.Name())
	if err := sys.Run("curl", "-fsSL", trackScriptURL(branch), "-o", tmp.Name()); err != nil {
		return fmt.Errorf(i18n.T("fetch track script from %s: %w"), trackScriptURL(branch), err)
	}
	return sys.Run("bash", tmp.Name(), branch)
}
