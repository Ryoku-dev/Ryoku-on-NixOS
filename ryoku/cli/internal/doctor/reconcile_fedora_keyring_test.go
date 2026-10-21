package doctor

import (
	"errors"
	"testing"
)

func TestReconcileFedoraKeyring(t *testing.T) {
	const keyLine = "     " + dnfRepoKeyPath
	verifyFailed := errors.New("exit status 1")
	for _, tc := range []struct {
		name       string
		installed  []string
		keyPresent bool
		verify     string
		verifyErr  error
		trusted    []string
		checkOnly  bool
		wantStatus recStatus
		wantImport bool
	}{
		{name: "checkout desktop", wantStatus: recOK},
		{name: "keyring removed, key file kept", installed: []string{"ryoku-desktop"}, keyPresent: true, wantStatus: recWarn},
		{name: "keyring and key file removed", installed: []string{"ryoku-desktop"}, wantStatus: recWarn},
		{name: "key file missing", installed: []string{"ryoku-desktop", "ryoku-keyring"}, verify: "missing" + keyLine + "\n", verifyErr: verifyFailed, wantStatus: recWarn},
		{name: "key file changed", installed: []string{"ryoku-desktop", "ryoku-keyring"}, verify: "S.5....T." + keyLine + "\n", verifyErr: verifyFailed, wantStatus: recWarn},
		{name: "only the timestamp moved", installed: []string{"ryoku-desktop", "ryoku-keyring"}, verify: ".......T." + keyLine + "\n", verifyErr: verifyFailed, trusted: []string{ryokuReleaseKeyFingerprint}, wantStatus: recOK},
		{name: "rpm cannot verify", installed: []string{"ryoku-desktop", "ryoku-keyring"}, verifyErr: verifyFailed, wantStatus: recWarn},
		{name: "trusted", installed: []string{"ryoku-desktop", "ryoku-keyring"}, trusted: []string{"105ef944105ef944105ef944105ef944105ef944", ryokuReleaseKeyFingerprint}, wantStatus: recOK},
		{name: "check reports an untrusted key", installed: []string{"ryoku-desktop", "ryoku-keyring"}, trusted: []string{"105ef944105ef944105ef944105ef944105ef944"}, checkOnly: true, wantStatus: recWouldFix},
		{name: "repair imports the packaged key", installed: []string{"ryoku-desktop", "ryoku-keyring"}, wantStatus: recFixed, wantImport: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			oldInstalled, oldKey := doctorPackageInstalled, dnfRepoKeyPresent
			oldVerify, oldTrusted, oldImport := verifyRPMPackage, trustedRPMKeys, importRPMKey
			t.Cleanup(func() {
				doctorPackageInstalled, dnfRepoKeyPresent = oldInstalled, oldKey
				verifyRPMPackage, trustedRPMKeys, importRPMKey = oldVerify, oldTrusted, oldImport
			})
			doctorPackageInstalled = func(name string) bool {
				for _, pkg := range tc.installed {
					if pkg == name {
						return true
					}
				}
				return false
			}
			dnfRepoKeyPresent = func() bool { return tc.keyPresent }
			verifyRPMPackage = func(string) (string, error) { return tc.verify, tc.verifyErr }
			trustedRPMKeys = func() ([]string, error) { return tc.trusted, nil }
			imported := false
			importRPMKey = func(path string) error {
				if path != dnfRepoKeyPath {
					t.Fatalf("imported %s, want %s", path, dnfRepoKeyPath)
				}
				imported = true
				return nil
			}
			got := reconcileFedoraKeyring(tc.checkOnly)
			if got.status != tc.wantStatus {
				t.Fatalf("status = %v, want %v (%+v)", got.status, tc.wantStatus, got)
			}
			if imported != tc.wantImport {
				t.Fatalf("imported = %v, want %v", imported, tc.wantImport)
			}
			if got.status == recWarn && got.remedy == "" {
				t.Fatalf("warning without a fix: %+v", got)
			}
			assertNoForeignPackageAdvice(t, got)
		})
	}
}
