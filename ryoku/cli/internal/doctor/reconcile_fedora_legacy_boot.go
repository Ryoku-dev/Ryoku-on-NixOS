package doctor

import (
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// The Fedora-only lineage before the current boot menu left state behind that
// no package owns, so an upgrade to the current packages does not take it
// away:
//
//   - its 95-ryoku-console.install plugin twinned every kernel's BLS entry as
//     <id>-<kver>~ryokuconsole.conf. The plugin is gone, so the twins stay in
//     GRUB's menu for good and no new kernel gets one. /boot/loader/entries is
//     root-only, so finding them takes sudo; that happens once, since nothing
//     writes a twin any more.
//   - its %post disabled Fedora's grub-boot-success.timer for every user, which
//     keeps GRUB from hiding its menu after a good boot and from counting a
//     failed one. The doctor turns it back on once, so a later choice to
//     disable it stands.
const (
	legacyConsoleSuffix = "~ryokuconsole"
	legacyConsolePlugin = "/usr/lib/kernel/install.d/95-ryoku-console.install"
	bootSuccessTimer    = "grub-boot-success.timer"
	bootSuccessUnit     = "/usr/lib/systemd/user/grub-boot-success.timer"
	bootSuccessMarker   = "/var/lib/ryoku/migrations/grub-boot-success-timer"
	consoleTwinsMarker  = "/var/lib/ryoku/migrations/ryoku-console-entries"
	legacyBLSDir        = "/boot/loader/entries"
)

// legacyBootState is what the reconciler looks at, lifted to a value so the
// plan is testable without a real /boot or systemd.
type legacyBootState struct {
	pluginPresent bool
	twinsChecked  bool
	entriesRead   bool
	entries       []string
	timerShipped  bool
	timerEnabled  bool
	timerMigrated bool
}

type legacyBootPlan struct {
	// readTwins: the entries still need a look that takes sudo.
	readTwins   bool
	removeTwins []string
	markTwins   bool
	enableTimer bool
	markTimer   bool
}

func (p legacyBootPlan) empty() bool {
	return !p.readTwins && len(p.removeTwins) == 0 && !p.markTwins && !p.enableTimer && !p.markTimer
}

// twinsPending reports whether the entries still have to be looked at.
func (s legacyBootState) twinsPending() bool { return !s.pluginPresent && !s.twinsChecked }

// planLegacyBoot picks what to undo. Twins are left alone while the old plugin
// is still installed, since it would only write them again.
func planLegacyBoot(s legacyBootState) legacyBootPlan {
	var p legacyBootPlan
	if s.twinsPending() {
		p.readTwins = !s.entriesRead
		p.markTwins = s.entriesRead
		for _, e := range s.entries {
			if strings.HasSuffix(filepath.Base(e), legacyConsoleSuffix+".conf") {
				p.removeTwins = append(p.removeTwins, e)
			}
		}
	}
	if s.timerShipped && !s.timerMigrated {
		p.enableTimer = !s.timerEnabled
		p.markTimer = true
	}
	return p
}

// legacy boot probes, variables so tests stub them.
var (
	// legacyBLSEntries lists the BLS entries; ask lets sudo prompt, which a
	// check never does.
	legacyBLSEntries = func(ask bool) ([]string, bool) {
		args := []string{"find", legacyBLSDir, "-maxdepth", "1", "-name", "*.conf"}
		if !ask {
			args = append([]string{"-n"}, args...)
		}
		out, err := sys.RunOut("sudo", args...)
		if err != nil {
			return nil, false
		}
		return strings.Fields(out), true
	}
	globalTimerEnabled = func() bool {
		return sys.Run("systemctl", "--global", "is-enabled", "--quiet", bootSuccessTimer) == nil
	}
)

func gatherLegacyBootState(checkOnly bool) legacyBootState {
	s := legacyBootState{
		pluginPresent: sys.Exists(legacyConsolePlugin),
		twinsChecked:  sys.Exists(consoleTwinsMarker),
		timerShipped:  sys.Exists(bootSuccessUnit),
		timerEnabled:  globalTimerEnabled(),
		timerMigrated: sys.Exists(bootSuccessMarker),
	}
	if s.twinsPending() {
		s.entries, s.entriesRead = legacyBLSEntries(!checkOnly)
	}
	return s
}

func reconcileFedoraLegacyBoot(checkOnly bool) recResult {
	if sys.NixBackend() {
		return okRes("boot entries and their timers are managed declaratively on NixOS")
	}
	plan := planLegacyBoot(gatherLegacyBootState(checkOnly))
	if plan.empty() {
		return okRes(i18n.T("no boot-menu leftovers from earlier Fedora packages"))
	}
	if checkOnly {
		var found []string
		if plan.readTwins {
			found = append(found, i18n.T("the boot entries were not yet checked for Ryoku console twins (that needs sudo)"))
		}
		if len(plan.removeTwins) > 0 {
			found = append(found, i18n.T("Ryoku console boot entries no package keeps up to date"))
		}
		if plan.enableTimer {
			found = append(found, i18n.T("Fedora's grub-boot-success.timer is off for every user"))
		}
		if len(found) == 0 {
			return okRes(i18n.T("no boot-menu leftovers from earlier Fedora packages"))
		}
		return wouldRes("%s", strings.Join(found, "; ")).
			withFix(i18n.T("ryoku doctor (removes them and turns the timer back on)"))
	}
	var done []string
	if len(plan.removeTwins) > 0 {
		if err := sys.Sudo(append([]string{"rm", "-f", "--"}, plan.removeTwins...)...); err != nil {
			return failRes(i18n.T("removing the Ryoku console boot entries: %v"), err).
				withFix(i18n.T("sudo rm -f %s/*%s.conf"), legacyBLSDir, legacyConsoleSuffix)
		}
		done = append(done, i18n.T("removed the Ryoku console boot entries"))
	}
	if plan.markTwins {
		if err := sys.Sudo("install", "-D", "-m", "0644", "/dev/null", consoleTwinsMarker); err != nil {
			return failRes(i18n.T("recording the Ryoku console boot entry cleanup: %v"), err)
		}
	}
	if plan.enableTimer {
		if err := sys.Sudo("systemctl", "--global", "enable", bootSuccessTimer); err != nil {
			return failRes(i18n.T("turning %s back on: %v"), bootSuccessTimer, err).
				withFix(i18n.T("sudo systemctl --global enable %s"), bootSuccessTimer)
		}
		done = append(done, i18n.T("turned Fedora's grub-boot-success.timer back on"))
	}
	if plan.markTimer {
		if err := sys.Sudo("install", "-D", "-m", "0644", "/dev/null", bootSuccessMarker); err != nil {
			return failRes(i18n.T("recording the %s migration: %v"), bootSuccessTimer, err)
		}
	}
	if plan.readTwins {
		return warnRes(i18n.T("could not read %s to look for Ryoku console boot entries"), legacyBLSDir).
			withFix(i18n.T("sudo rm -f %s/*%s.conf"), legacyBLSDir, legacyConsoleSuffix)
	}
	if len(done) == 0 {
		return okRes(i18n.T("no boot-menu leftovers from earlier Fedora packages"))
	}
	return fixedRes("%s", strings.Join(done, "; "))
}
