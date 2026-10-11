package host

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"ryoku-cli/internal/sys"
)

const (
	FedoraReleasesURL    = "https://repo.ryoku.dev/stable/fedora/releases"
	fedoraReleaseTimeout = 3 * time.Second
	maxFedoraReleaseList = 64 << 10
)

type FedoraReleaseStatus struct {
	Version           string
	Published         bool
	RepositoryChecked bool
	Supported         []string
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
	repoURL = strings.TrimRight(ExpandRepoURL(repoURL), "/") + "/repodata/repomd.xml"
	published, checked, repoErr := fedoraRepositoryPublished(ctx, a.cfg.HTTPClient, repoURL)
	status.Published = published
	status.RepositoryChecked = checked

	supported, releasesErr := fetchFedoraReleases(ctx, a.cfg.HTTPClient, a.cfg.FedoraReleasesURL)
	status.Supported = supported
	return status, errors.Join(repoErr, releasesErr)
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
