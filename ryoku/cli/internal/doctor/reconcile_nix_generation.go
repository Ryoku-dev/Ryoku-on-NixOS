package doctor

import (
	"fmt"
	"os"
	"sort"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

var (
	readNixIntegration = sys.ReadNixIntegration
	nixPathExists      = sys.Exists
	nixStorePath       = sys.IsNixStorePath
	nixExecutable      = sys.FindExecutable
)

func nixGenerationProblems(integration sys.NixIntegration) []string {
	var problems []string
	if integration.Schema != 1 {
		problems = append(problems, fmt.Sprintf("unsupported integration manifest schema %d", integration.Schema))
	}
	for label, path := range map[string]string{
		"Ryoku config base":   integration.ConfigBase,
		"translation catalog": integration.I18nDir,
	} {
		if strings.TrimSpace(path) == "" {
			problems = append(problems, label+" is not recorded")
			continue
		}
		if !nixPathExists(path) {
			problems = append(problems, label+" is missing: "+path)
			continue
		}
		if !nixStorePath(path) {
			problems = append(problems, label+" does not resolve into /nix/store: "+path)
		}
	}
	if len(integration.Packages) == 0 {
		problems = append(problems, "active generation package manifest is empty")
	}
	for _, pkg := range integration.Packages {
		if pkg.Name == "" || pkg.Path == "" {
			problems = append(problems, "active generation contains an incomplete package record")
			continue
		}
		if !nixPathExists(pkg.Path) {
			problems = append(problems, fmt.Sprintf("package %s points at a missing store path", pkg.Name))
		} else if !nixStorePath(pkg.Path) {
			problems = append(problems, fmt.Sprintf("package %s is outside /nix/store", pkg.Name))
		}
	}
	for _, bin := range []string{
		"ryoku", "ryoku-shell", "ryoku-hub",
		"ryoku-wm-hyprland", "ryoku-wm-niri",
	} {
		if nixExecutable(bin) == "" {
			problems = append(problems, bin+" is not exposed by the active NixOS profiles")
		}
	}
	sort.Strings(problems)
	return problems
}

func nixRebuildRemedy(integration sys.NixIntegration) string {
	flake := strings.TrimSpace(integration.Flake)
	if flake == "" {
		flake = strings.TrimSpace(os.Getenv("RYOKU_NIX_FLAKE"))
	}
	if flake == "" {
		flake = "/etc/nixos"
	}
	host := strings.TrimSpace(integration.Host)
	if host != "" && !strings.Contains(flake, "#") {
		flake += "#" + host
	}
	return "sudo nixos-rebuild switch --flake " + flake
}

func reconcileNixGeneration(_ bool) recResult {
	if !sys.NixBackend() {
		return okRes(i18n.T("not a NixOS-managed Ryoku system"))
	}
	integration, err := readNixIntegration()
	if err != nil {
		return warnRes(i18n.T("the active NixOS generation has no readable Ryoku integration manifest: %v"), err).
			withFix("sudo nixos-rebuild switch --flake ${RYOKU_NIX_FLAKE:-/etc/nixos}")
	}
	problems := nixGenerationProblems(integration)
	if len(problems) == 0 {
		return okRes(i18n.T("NixOS generation %s is complete (%d direct packages)"), integration.Version, len(integration.Packages))
	}
	return warnRes(i18n.T("NixOS generation integrity: %s"), strings.Join(problems, "; ")).
		withFix(nixRebuildRemedy(integration))
}
