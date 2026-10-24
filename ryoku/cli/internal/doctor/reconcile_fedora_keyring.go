package doctor

import (
	"fmt"
	"slices"
	"strings"

	"ryoku-cli/internal/host"
	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// ryoku-keyring owns the key file ryoku.repo names. Once that file is gone dnf
// cannot reinstall the package, because repo_gpgcheck needs the key to read the
// repository it would come from; only the installer, which fetches and verifies
// the key itself, gets such a machine back.
const ryokuReleaseKeyFingerprint = "eb6d3c0f55a7b3caba6b2838847b274f025dd6e3"

// keyring probes, variables so tests stub them.
var (
	verifyRPMPackage = func(name string) (string, error) {
		return sys.RunOut("rpm", "-V", name)
	}
	importRPMKey = func(path string) error {
		return sys.Sudo("rpm", "--import", path)
	}
)

func fedoraKeyReinstallAdvice() string {
	return i18n.T("re-run the Ryoku shell installer, which verifies and imports the release key")
}

// keyFileVerifyState reads `rpm -V` output for the key file: "missing",
// "changed" when its size or digest differs, or "" otherwise. A touched
// timestamp alone is not a different key.
func keyFileVerifyState(out string) string {
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 || fields[len(fields)-1] != dnfRepoKeyPath {
			continue
		}
		switch {
		case fields[0] == "missing":
			return "missing"
		case strings.ContainsAny(fields[0], "S5"):
			return "changed"
		}
	}
	return ""
}

func reconcileFedoraKeyring(checkOnly bool) recResult {
	if !doctorPackageInstalled("ryoku-desktop") {
		return okRes(i18n.T("not a packaged install (desktop runs from a checkout)"))
	}
	if !doctorPackageInstalled("ryoku-keyring") {
		if !dnfRepoKeyPresent() {
			return warnRes(i18n.T("ryoku-keyring and the Ryoku release key %s are missing, so the Ryoku RPM repository cannot be read"), dnfRepoKeyPath).
				withFix(fedoraKeyReinstallAdvice())
		}
		return warnRes(i18n.T("ryoku-keyring is not installed, so a new Ryoku release key cannot reach this machine")).
			withFix(fmt.Sprintf("sudo %s install ryoku-keyring", host.DNFCommand()))
	}
	// rpm -V exits non-zero whenever it reports a difference, so the output is
	// the answer and only an empty one with an error means it could not check.
	out, err := verifyRPMPackage("ryoku-keyring")
	switch keyFileVerifyState(out) {
	case "missing":
		return warnRes(i18n.T("the Ryoku release key %s is missing, so the Ryoku RPM repository cannot be read"), dnfRepoKeyPath).
			withFix(fedoraKeyReinstallAdvice())
	case "changed":
		return warnRes(i18n.T("the Ryoku release key %s no longer matches the one ryoku-keyring installed"), dnfRepoKeyPath).
			withFix(fedoraKeyReinstallAdvice())
	}
	if err != nil && strings.TrimSpace(out) == "" {
		return warnRes(i18n.T("could not verify ryoku-keyring: %v"), err).
			withFix("%s", "rpm -V ryoku-keyring")
	}
	trusted, err := trustedRPMKeys()
	if err != nil {
		return warnRes(i18n.T("could not list the rpm keyring to look for the Ryoku release key: %v"), err).
			withFix("%s", "rpmkeys --list")
	}
	if slices.Contains(trusted, ryokuReleaseKeyFingerprint) {
		return okRes(i18n.T("ryoku-keyring is installed and rpm trusts the Ryoku release key"))
	}
	// rpm -V just vouched for the file, so importing it needs no network.
	fix := fmt.Sprintf("sudo rpm --import %s", dnfRepoKeyPath)
	if checkOnly {
		return wouldRes(i18n.T("rpm does not trust the Ryoku release key, so Ryoku packages fail their signature check")).
			withFix("%s", fix)
	}
	if err := importRPMKey(dnfRepoKeyPath); err != nil {
		return failRes(i18n.T("could not import the Ryoku release key into the rpm keyring: %v"), err).
			withFix("%s", fix)
	}
	return fixedRes(i18n.T("imported the Ryoku release key into the rpm keyring"))
}
