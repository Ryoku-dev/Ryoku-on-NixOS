package host

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"slices"
	"strings"
	"time"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

const (
	FedoraReleasesURL    = "https://repo.ryoku.dev/stable/fedora/releases"
	fedoraReleaseTimeout = 3 * time.Second
	maxFedoraReleaseList = 64 << 10
)

type FedoraReleaseStatus struct {
	Version              string
	Published            bool
	RepositoryChecked    bool
	Supported            []string
	AwaitingFirstRelease bool
}

func (s FedoraReleaseStatus) UnpublishedNotice() string {
	if s.AwaitingFirstRelease {
		return i18n.Tf("the stable channel has no Fedora %s packages until Ryoku's first Fedora release; the shell installer's --ref unstable-dev sets up the testing packages", s.Version)
	}
	return i18n.Tf("Ryoku has not published Fedora %s yet; Ryoku packages stay at their current version until it does", s.Version)
}

func (a *App) FedoraReleaseStatus() (FedoraReleaseStatus, error) {
	path := a.getenv("RYOKU_OS_RELEASE")
	if path == "" {
		path = "/etc/os-release"
	}
	status := FedoraReleaseStatus{Version: osReleaseVersion(path)}
	if status.Version == "" {
		return status, fmt.Errorf("Fedora VERSION_ID is missing from %s", path)
	}

	ctx, cancel := context.WithTimeout(context.Background(), fedoraReleaseTimeout)
	defer cancel()

	repoURL, err := a.RepoURL()
	if errors.Is(err, ErrRepoAbsent) {
		if _, statErr := os.Stat(a.dnfRepoPath()); statErr == nil {
			return status, fmt.Errorf("configured Fedora repository has no [ryoku] baseurl")
		} else if !errors.Is(statErr, os.ErrNotExist) {
			return status, fmt.Errorf("inspect configured Fedora repository: %w", statErr)
		}
		repoURL = RepoURLFor(DNF, sys.ChannelStable)
	} else if err != nil {
		return status, err
	}
	published, checked, repoErr := fedoraRepositoryPublished(ctx, a.cfg.HTTPClient, fedoraRepomdURL(repoURL, status.Version))
	status.Published = published
	status.RepositoryChecked = checked

	supported, releasesErr := fetchFedoraReleases(ctx, a.cfg.HTTPClient, a.cfg.FedoraReleasesURL)
	status.Supported = supported
	if checked && !published && RepoChannelOf(DNF, repoURL) == sys.ChannelStable && slices.Contains(supported, status.Version) {
		status.AwaitingFirstRelease = channelPublishesNoFedora(ctx, a.cfg.HTTPClient, repoURL, supported)
	}
	return status, errors.Join(repoErr, releasesErr)
}

func fedoraRepomdURL(repoURL, release string) string {
	return strings.TrimRight(ExpandRepoURL(strings.ReplaceAll(repoURL, "$releasever", release)), "/") + "/repodata/repomd.xml"
}

// channelPublishesNoFedora is true only when every listed release is
// confirmed absent. The releases list is shared with testing, so a listed
// release says nothing about whether stable has shipped it.
func channelPublishesNoFedora(ctx context.Context, client *http.Client, repoURL string, releases []string) bool {
	for _, release := range releases {
		published, checked, _ := fedoraRepositoryPublished(ctx, client, fedoraRepomdURL(repoURL, release))
		if published || !checked {
			return false
		}
	}
	return true
}

func fedoraRepositoryPublished(ctx context.Context, client *http.Client, url string) (bool, bool, error) {
	code, err := fedoraHTTPStatus(ctx, client, http.MethodHead, url)
	if err != nil {
		return false, false, fmt.Errorf("check Fedora repository: %w", err)
	}
	if code == http.StatusMethodNotAllowed || code == http.StatusNotImplemented {
		code, err = fedoraHTTPStatus(ctx, client, http.MethodGet, url)
		if err != nil {
			return false, false, fmt.Errorf("check Fedora repository: %w", err)
		}
	}
	return code == http.StatusOK, true, nil
}

func fedoraHTTPStatus(ctx context.Context, client *http.Client, method, url string) (int, error) {
	req, err := http.NewRequestWithContext(ctx, method, url, nil)
	if err != nil {
		return 0, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	return resp.StatusCode, nil
}

func fetchFedoraReleases(ctx context.Context, client *http.Client, url string) ([]string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch supported Fedora releases: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetch supported Fedora releases: HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxFedoraReleaseList+1))
	if err != nil {
		return nil, fmt.Errorf("read supported Fedora releases: %w", err)
	}
	if len(body) > maxFedoraReleaseList {
		return nil, fmt.Errorf("supported Fedora release list is too large")
	}

	seen := map[string]bool{}
	var releases []string
	for _, line := range strings.Split(string(body), "\n") {
		release := strings.TrimSpace(line)
		if release == "" || seen[release] {
			continue
		}
		if !decimalRelease(release) {
			return nil, fmt.Errorf("invalid Fedora release %q", release)
		}
		seen[release] = true
		releases = append(releases, release)
	}
	return releases, nil
}
