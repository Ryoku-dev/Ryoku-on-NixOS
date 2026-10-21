package doctor

import (
	"errors"
	"io/fs"
	"slices"
	"testing"
)

const (
	revokedTestKey = "1111111111111111111111111111111111111111"
	currentTestKey = "eb6d3c0f55a7b3caba6b2838847b274f025dd6e3"
)

func stubRevokedKeys(t *testing.T, revoked []string, revokedErr error, trusted []string) *[]string {
	t.Helper()
	oldRead, oldTrusted, oldDelete := readRevokedRPMKeys, trustedRPMKeys, deleteRPMKey
	t.Cleanup(func() { readRevokedRPMKeys, trustedRPMKeys, deleteRPMKey = oldRead, oldTrusted, oldDelete })
	var deleted []string
	readRevokedRPMKeys = func() ([]string, error) { return revoked, revokedErr }
	trustedRPMKeys = func() ([]string, error) { return trusted, nil }
	deleteRPMKey = func(key string) error { deleted = append(deleted, key); return nil }
	return &deleted
}

func TestReconcileFedoraRevokedKeys(t *testing.T) {
	for _, tc := range []struct {
		name        string
		revoked     []string
		revokedErr  error
		trusted     []string
		checkOnly   bool
		wantStatus  recStatus
		wantDeleted []string
	}{
		{name: "no keyring package", revokedErr: fs.ErrNotExist, wantStatus: recOK},
		{name: "unreadable list", revokedErr: errors.New("denied"), wantStatus: recWarn},
		{name: "nothing revoked", trusted: []string{currentTestKey}, wantStatus: recOK},
		{name: "revoked key not trusted", revoked: []string{revokedTestKey}, trusted: []string{currentTestKey}, wantStatus: recOK},
		{name: "check reports a trusted revoked key", revoked: []string{revokedTestKey}, trusted: []string{currentTestKey, revokedTestKey}, checkOnly: true, wantStatus: recWouldFix},
		{name: "repair deletes only the revoked key", revoked: []string{revokedTestKey}, trusted: []string{currentTestKey, revokedTestKey}, wantStatus: recFixed, wantDeleted: []string{revokedTestKey}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			deleted := stubRevokedKeys(t, tc.revoked, tc.revokedErr, tc.trusted)
			got := reconcileFedoraRevokedKeys(tc.checkOnly)
			if got.status != tc.wantStatus {
				t.Fatalf("status = %v, want %v (%+v)", got.status, tc.wantStatus, got)
			}
			if !slices.Equal(*deleted, tc.wantDeleted) {
				t.Fatalf("deleted = %q, want %q", *deleted, tc.wantDeleted)
			}
			assertNoForeignPackageAdvice(t, got)
		})
	}
}

func TestNormalizedFingerprintsSkipsCommentsAndCase(t *testing.T) {
	got := normalizedFingerprints("# retired 2027\n  EB6D3C0F55A7B3CABA6B2838847B274F025DD6E3 \n\n")
	if !slices.Equal(got, []string{currentTestKey}) {
		t.Fatalf("fingerprints = %q", got)
	}
}
