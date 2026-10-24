package updater

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

type channelBuild struct {
	Channel  string `json:"channel"`
	State    string `json:"state"`
	Commit   string `json:"commit"`
	Release  string `json:"release"`
	Run      string `json:"run"`
	Started  string `json:"started"`
	Finished string `json:"finished"`
}

type checkedRef struct {
	Commit string `json:"commit"`
	Run    string `json:"run"`
	At     string `json:"at"`
}

type checkedPointer struct {
	Commit string     `json:"commit"`
	State  string     `json:"state"`
	Run    string     `json:"run"`
	At     string     `json:"at"`
	Checks []string   `json:"checks"`
	Passed checkedRef `json:"passed"`
}

const buildStaleAfter = 90 * time.Minute

var (
	buildHTTPClient   = &http.Client{Timeout: 5 * time.Second}
	buildPollInterval = 20 * time.Second
	updateWait        bool
	updateForce       bool
)

func channelBuildStatus(channel string) (channelBuild, bool) {
	url := repoReleaseURL(channel)
	if url == "" {
		return channelBuild{}, false
	}
	var build channelBuild
	if !readStatusJSON(url+"/status.json", &build) {
		return channelBuild{}, false
	}
	return build, true
}

func (b channelBuild) inProgress(now time.Time) bool {
	if b.State != "building" {
		return false
	}
	started, err := time.Parse(time.RFC3339, b.Started)
	if err != nil {
		return false
	}
	age := now.Sub(started)
	return age >= 0 && age <= buildStaleAfter
}

func readCheckedPointer() (checkedPointer, bool) {
	base := sys.RepoBase
	if strings.TrimSpace(os.Getenv("RYOKU_RELEASE_BASE")) != "" {
		base = repoBase()
	}
	base = strings.TrimSuffix(base, "/")
	if base == "" {
		return checkedPointer{}, false
	}
	var pointer checkedPointer
	if !readStatusJSON(base+"/channels/testing/checked.json", &pointer) {
		return checkedPointer{}, false
	}
	return pointer, true
}

func readStatusJSON(url string, dst any) bool {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return false
	}
	req.Header.Set("Cache-Control", "no-cache")
	resp, err := buildHTTPClient.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false
	}
	decoder := json.NewDecoder(io.LimitReader(resp.Body, 1<<20))
	if decoder.Decode(dst) != nil {
		return false
	}
	var extra any
	return decoder.Decode(&extra) == io.EOF
}

func waitForChannelBuild(channel string, timeout time.Duration, log func(string)) channelBuild {
	deadline := time.Now().Add(timeout)
	lastLog := time.Time{}
	for {
		build, ok := channelBuildStatus(channel)
		now := time.Now()
		if !ok || !build.inProgress(now) {
			return build
		}
		if log != nil && (lastLog.IsZero() || now.Sub(lastLog) >= time.Minute) {
			log(i18n.Tf("Waiting for the %s channel build of %s to finish (%s)", sys.DisplayChannel(channel), shortSHA(build.Commit), build.Run))
			lastLog = now
		}
		if !now.Before(deadline) {
			return build
		}
		pause := buildPollInterval
		if remaining := time.Until(deadline); remaining < pause {
			pause = remaining
		}
		if pause > 0 {
			time.Sleep(pause)
		}
	}
}

func channelBuildAgeMinutes(build channelBuild, now time.Time) int {
	started, err := time.Parse(time.RFC3339, build.Started)
	if err != nil || now.Before(started) {
		return 0
	}
	return int(now.Sub(started) / time.Minute)
}

func shortSHA(commit string) string {
	if len(commit) > 7 {
		return commit[:7]
	}
	return commit
}
