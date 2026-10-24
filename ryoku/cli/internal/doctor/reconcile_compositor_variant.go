package doctor

import (
	"strings"

	"ryoku-cli/internal/host"

	i18n "ryoku-i18n"
	wm "ryoku-wm"
)

var compositorVariantSessionDirs = func() []string {
	return []string{"/usr/local/share/wayland-sessions", "/usr/share/wayland-sessions"}
}

var compositorVariantSessionOffered = wm.SessionOffered

type compositorVariantGap struct {
	provider string
	pkg      string
}

func offeredCompositorVariantGaps() []compositorVariantGap {
	var gaps []compositorVariantGap
	dirs := compositorVariantSessionDirs()
	for _, provider := range wm.Providers() {
		if !compositorVariantSessionOffered(provider, dirs) {
			continue
		}
		pkg := wm.VariantPackage(provider)
		if pkg == "" || doctorPackageInstalled(pkg) {
			continue
		}
		gaps = append(gaps, compositorVariantGap{provider: provider, pkg: pkg})
	}
	return gaps
}

func compositorVariantGapNames(gaps []compositorVariantGap) string {
	names := make([]string, 0, len(gaps))
	for _, gap := range gaps {
		names = append(names, gap.provider+" ("+gap.pkg+")")
	}
	return strings.Join(names, ", ")
}

func reconcileCompositorVariants(checkOnly bool) recResult {
	gaps := offeredCompositorVariantGaps()
	if len(gaps) == 0 {
		return okRes(i18n.T("every compositor offered at login has its Ryoku desktop variant"))
	}

	manager, err := doctorPackageManager()
	if err != nil || manager != host.Pacman && manager != host.XBPS && manager != host.DNF {
		return warnRes(i18n.T("could not determine how to install the missing Ryoku desktop variant for %s"), compositorVariantGapNames(gaps))
	}

	var installable, unavailable []compositorVariantGap
	for _, gap := range gaps {
		if doctorPackageUnavailable(manager, gap.pkg) {
			unavailable = append(unavailable, gap)
		} else {
			installable = append(installable, gap)
		}
	}

	if checkOnly && len(installable) > 0 {
		detail := i18n.Tf("login entries without Ryoku desktop variants: %s; those sessions will be bare", compositorVariantGapNames(installable))
		if len(unavailable) > 0 {
			detail += i18n.Tf("; unavailable in this distribution's Ryoku repository: %s", compositorVariantGapNames(unavailable))
		}
		return warnRes("%s", detail).withFix(i18n.T("run `ryoku doctor` to install the missing desktop variant"))
	}

	if len(installable) > 0 {
		pkgs := make([]string, 0, len(installable))
		for _, gap := range installable {
			pkgs = append(pkgs, gap.pkg)
		}
		if code := doctorPackageInstall(pkgs...); code != host.ExitOK {
			return warnRes(i18n.T("could not install the missing Ryoku desktop variant for %s"), compositorVariantGapNames(installable)).
				withFix("%s", doctorInstallAdvice(pkgs...))
		}
		var missed []compositorVariantGap
		for _, gap := range installable {
			if !doctorPackageInstalled(gap.pkg) {
				missed = append(missed, gap)
			}
		}
		if len(missed) > 0 {
			return warnRes(i18n.T("the Ryoku desktop variant did not land for %s"), compositorVariantGapNames(missed)).
				withFix("%s", doctorInstallAdvice(pkgs...))
		}
	}

	if len(unavailable) > 0 {
		return noteRes(i18n.T("Ryoku desktop variants are not available in this distribution's repository for %s; those login sessions will be bare"), compositorVariantGapNames(unavailable))
	}
	return fixedRes(i18n.T("installed the missing Ryoku desktop variant for %s"), compositorVariantGapNames(installable))
}
