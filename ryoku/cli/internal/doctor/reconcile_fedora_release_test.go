package doctor

import (
	"errors"
	"strings"
	"testing"

	"ryoku-cli/internal/host"
)

func TestReconcileFedoraRelease(t *testing.T) {
	oldManager := doctorPackageManager
	oldStatus := doctorFedoraReleaseStatus
	t.Cleanup(func() {
		doctorPackageManager = oldManager
		doctorFedoraReleaseStatus = oldStatus
	})
	doctorPackageManager = func() (host.PackageManager, error) { return host.DNF, nil }

	for _, tc := range []struct {
		name       string
		status     host.FedoraReleaseStatus
		err        error
		wantStatus recStatus
		wantDetail string
	}{
		{
			name:       "published",
			status:     host.FedoraReleaseStatus{Version: "44", Published: true, RepositoryChecked: true, Supported: []string{"44", "45"}},
			wantStatus: recOK,
			wantDetail: "Ryoku publishes packages for Fedora 44",
		},
		{
			name:       "unpublished",
			status:     host.FedoraReleaseStatus{Version: "46", RepositoryChecked: true, Supported: []string{"44", "45"}},
			wantStatus: recWarn,
			wantDetail: "Ryoku has not published Fedora 46 yet; Ryoku packages stay at their current version until it does",
		},
		{
			name:       "unreachable",
			status:     host.FedoraReleaseStatus{Version: "44"},
			err:        errors.New("network unavailable"),
			wantStatus: recWarn,
			wantDetail: "could not check whether Ryoku publishes Fedora 44: network unavailable",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			doctorFedoraReleaseStatus = func() (host.FedoraReleaseStatus, error) { return tc.status, tc.err }
			got := reconcileFedoraRelease(true)
			if got.status != tc.wantStatus || got.detail != tc.wantDetail {
				t.Fatalf("result = %s %q, want %s %q", got.status.label(), got.detail, tc.wantStatus.label(), tc.wantDetail)
			}
		})
	}
}

func TestFedoraReleaseReconcilerIsDNFOnly(t *testing.T) {
	oldManager := doctorPackageManager
	oldStatus := doctorFedoraReleaseStatus
	t.Cleanup(func() {
		doctorPackageManager = oldManager
		doctorFedoraReleaseStatus = oldStatus
	})
	doctorFedoraReleaseStatus = func() (host.FedoraReleaseStatus, error) {
		t.Fatal("non-DNF host checked Fedora publication")
		return host.FedoraReleaseStatus{}, nil
	}

	for _, tc := range []struct {
		manager host.PackageManager
		want    bool
	}{
		{manager: host.DNF, want: true},
		{manager: host.Pacman},
		{manager: host.XBPS},
	} {
		doctorPackageManager = func() (host.PackageManager, error) { return tc.manager, nil }
		found := false
		for _, reconciler := range reconcilers() {
			if strings.EqualFold(reconciler.name, "Fedora release") {
				found = true
				break
			}
		}
		if found != tc.want {
			t.Fatalf("manager %q Fedora release registered = %v, want %v", tc.manager, found, tc.want)
		}
	}
}
