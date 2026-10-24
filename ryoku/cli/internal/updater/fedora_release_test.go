package updater

import (
	"io"
	"os"
	"strings"
	"testing"

	"ryoku-cli/internal/host"
)

const unpublishedFedoraNotice = "Ryoku has not published Fedora 46 yet; Ryoku packages stay at their current version until it does"

func TestFedoraReleaseNotice(t *testing.T) {
	oldStatus := updaterFedoraReleaseStatus
	t.Cleanup(func() { updaterFedoraReleaseStatus = oldStatus })

	for _, tc := range []struct {
		name    string
		manager string
		status  host.FedoraReleaseStatus
		want    string
	}{
		{
			name:    "unpublished Fedora",
			manager: "dnf",
			status:  host.FedoraReleaseStatus{Version: "46", RepositoryChecked: true, Supported: []string{"44", "45"}},
			want:    unpublishedFedoraNotice,
		},
		{
			name:    "published Fedora",
			manager: "dnf",
			status:  host.FedoraReleaseStatus{Version: "44", Published: true, RepositoryChecked: true},
		},
		{
			name:    "unreachable repository",
			manager: "dnf",
			status:  host.FedoraReleaseStatus{Version: "44"},
		},
		{
			name:    "non-DNF host",
			manager: "pacman",
			status:  host.FedoraReleaseStatus{Version: "46", RepositoryChecked: true},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("RYOKU_HOST_PKGMGR", tc.manager)
			updaterFedoraReleaseStatus = func() (host.FedoraReleaseStatus, error) { return tc.status, nil }
			if got := fedoraReleaseNotice(); got != tc.want {
				t.Fatalf("notice = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestStatusExplainsUnpublishedFedoraRelease(t *testing.T) {
	oldStatus := updaterFedoraReleaseStatus
	t.Cleanup(func() { updaterFedoraReleaseStatus = oldStatus })
	updaterFedoraReleaseStatus = func() (host.FedoraReleaseStatus, error) {
		return host.FedoraReleaseStatus{Version: "46", RepositoryChecked: true, Supported: []string{"44", "45"}}, nil
	}
	t.Setenv("RYOKU_HOST_PKGMGR", "dnf")
	t.Setenv("PATH", t.TempDir())
	t.Setenv("RYOKU_REPO", "")
	t.Setenv("RYOKU_CONFIG_BASE", t.TempDir())

	read, write, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	oldStdout := os.Stdout
	os.Stdout = write
	t.Cleanup(func() { os.Stdout = oldStdout })
	statusErr := Status(nil)
	_ = write.Close()
	os.Stdout = oldStdout
	output, readErr := io.ReadAll(read)
	_ = read.Close()
	if statusErr != nil {
		t.Fatal(statusErr)
	}
	if readErr != nil {
		t.Fatal(readErr)
	}
	if !strings.Contains(string(output), unpublishedFedoraNotice) {
		t.Fatalf("status output = %q", output)
	}
	if strings.Contains(string(output), "behind:        up to date") {
		t.Fatalf("status called unpublished Fedora up to date: %q", output)
	}
}
