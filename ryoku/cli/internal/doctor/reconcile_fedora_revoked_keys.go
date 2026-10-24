package doctor

import (
	"errors"
	"io/fs"
	"os"
	"slices"
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// ryoku-keyring ships the Arch keyring's revoked list here. rpm holds its
// transaction lock while scriptlets run, so the package cannot drop a revoked
// key from the rpm keyring itself; the doctor, which runs after every update,
// does it instead.
const revokedRPMKeysPath = "/usr/share/ryoku-keyring/revoked"

// revoked-key probes, variables so tests stub them.
var (
	readRevokedRPMKeys = func() ([]string, error) {
		data, err := os.ReadFile(revokedRPMKeysPath)
		if err != nil {
			return nil, err
		}
		return normalizedFingerprints(string(data)), nil
	}
	trustedRPMKeys = func() ([]string, error) {
		out, err := sys.RunOut("rpmkeys", "--list")
		if err != nil {
			return nil, err
		}
		var keys []string
		for _, line := range strings.Split(out, "\n") {
			if fields := strings.Fields(line); len(fields) > 0 {
				keys = append(keys, strings.ToLower(fields[0]))
			}
		}
		return keys, nil
	}
	deleteRPMKey = func(fingerprint string) error {
		return sys.Sudo("rpmkeys", "--delete", fingerprint)
	}
)

func normalizedFingerprints(text string) []string {
	var keys []string
	for _, line := range strings.Split(text, "\n") {
		if key := strings.ToLower(strings.TrimSpace(line)); key != "" && !strings.HasPrefix(key, "#") {
			keys = append(keys, key)
		}
	}
	return keys
}

func stillTrustedRevokedKeys(revoked, trusted []string) []string {
	var found []string
	for _, key := range revoked {
		if slices.Contains(trusted, key) && !slices.Contains(found, key) {
			found = append(found, key)
		}
	}
	return found
}

func reconcileFedoraRevokedKeys(checkOnly bool) recResult {
	revoked, err := readRevokedRPMKeys()
	if errors.Is(err, fs.ErrNotExist) {
		return okRes(i18n.T("ryoku-keyring is not installed, so there are no revoked Ryoku keys to check"))
	}
	if err != nil {
		return warnRes(i18n.T("could not read the revoked Ryoku keys in %s: %v"), revokedRPMKeysPath, err)
	}
	if len(revoked) == 0 {
		return okRes(i18n.T("no Ryoku release key has been revoked"))
	}
	trusted, err := trustedRPMKeys()
	if err != nil {
		return warnRes(i18n.T("could not list the rpm keyring to look for revoked Ryoku keys: %v"), err)
	}
	found := stillTrustedRevokedKeys(revoked, trusted)
	if len(found) == 0 {
		return okRes(i18n.T("no revoked Ryoku release key is trusted"))
	}
	const fix = "sudo rpmkeys --delete %s"
	keys := strings.Join(found, " ")
	if checkOnly {
		return wouldRes(i18n.T("rpm still trusts revoked Ryoku release keys: %s"), strings.Join(found, ", ")).
			withFix(fix, keys)
	}
	for _, key := range found {
		if err := deleteRPMKey(key); err != nil {
			return failRes(i18n.T("removing the revoked Ryoku release key %s: %v"), key, err).withFix(fix, keys)
		}
	}
	return fixedRes(i18n.T("rpm no longer trusts the revoked Ryoku release keys: %s"), strings.Join(found, ", "))
}
