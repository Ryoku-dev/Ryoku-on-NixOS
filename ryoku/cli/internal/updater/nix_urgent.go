package updater

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"ryoku-cli/internal/sys"
)

// A port maintainer marks a commit urgent with a trailer beside Note: and the
// others:
//
//	Urgent: <why every box should take this update now>
//
// On the Nix backend `ryoku status` lists the urgent commits between the one
// this generation was built from and the tip of the branch its flake input
// follows, and the shell raises an alert for them (docs/nixos.md, "Urgent
// updates"). Only commits on that branch's first-parent line count: a
// maintainer's own push, or the merge commit a maintainer writes. A
// contributor's commits arrive as the second parent of that merge, so a
// trailer there alerts nobody, and the Urgent trailer workflow refuses a pull
// request that carries one. Other backends list nothing.

// urgentCommit is one urgent commit this box does not run yet.
type urgentCommit struct {
	Commit  string `json:"commit"`
	Subject string `json:"subject"`
	Reason  string `json:"reason"`
}

// urgentReasonMax bounds the reason an alert shows. The commit-msg hook keeps
// new trailers shorter; this guards one that bypassed it.
const urgentReasonMax = 200

// urgentReason returns the text of a message's Urgent: trailer, or "" when it
// has none. Trailers live in the last paragraph, as git reads them, so a
// one-paragraph message (a bare subject) never carries one. The key matches
// in any case.
func urgentReason(message string) string {
	lines := strings.Split(strings.ReplaceAll(message, "\r\n", "\n"), "\n")
	end := len(lines)
	for end > 0 && strings.TrimSpace(lines[end-1]) == "" {
		end--
	}
	start := end
	for start > 0 && strings.TrimSpace(lines[start-1]) != "" {
		start--
	}
	if start == 0 {
		return ""
	}
	for _, line := range lines[start:end] {
		key, value, ok := strings.Cut(line, ":")
		if !ok || !strings.EqualFold(key, "Urgent") {
			continue
		}
		if value = strings.TrimSpace(value); value != "" {
			return clip(value, urgentReasonMax)
		}
	}
	return ""
}

func subjectOf(message string) string {
	subject, _, _ := strings.Cut(message, "\n")
	return strings.TrimSpace(subject)
}

// urgentCompareCommit is the slice of one commit in GitHub's compare payload
// the urgent walk reads: its message and the parents that carry the
// first-parent line.
type urgentCompareCommit struct {
	SHA    string `json:"sha"`
	Commit struct {
		Message string `json:"message"`
	} `json:"commit"`
	Parents []struct {
		SHA string `json:"sha"`
	} `json:"parents"`
}

// firstParentUrgent walks head's first-parent line through the compared
// commits and returns the urgent ones, newest first. The walk ends where the
// line leaves the range, at the base. head may be abbreviated.
func firstParentUrgent(commits []urgentCompareCommit, head string) []urgentCommit {
	out := []urgentCommit{}
	if head == "" {
		return out
	}
	bySHA := make(map[string]*urgentCompareCommit, len(commits))
	var cur *urgentCompareCommit
	for i := range commits {
		c := &commits[i]
		bySHA[c.SHA] = c
		if strings.HasPrefix(c.SHA, head) {
			cur = c
		}
	}
	for steps := 0; cur != nil && steps < len(commits); steps++ {
		if reason := urgentReason(cur.Commit.Message); reason != "" {
			out = append(out, urgentCommit{Commit: shortSHA(cur.SHA), Subject: subjectOf(cur.Commit.Message), Reason: reason})
		}
		if len(cur.Parents) == 0 {
			break
		}
		cur = bySHA[cur.Parents[0].SHA]
	}
	return out
}

// nixUrgentSource is what `ryoku-nix-update status --json` reports for the
// lookup: the flake input's GitHub repository, the commit this generation was
// built from and the tip of the branch the input follows.
type nixUrgentSource struct {
	Repository   string `json:"repository"`
	InstalledRev string `json:"installedRev"`
	LatestRev    string `json:"latestRev"`
}

// nixUrgentCache is the last resolved lookup, keyed by repository and commit
// pair. Both commits move only when the box updates or the branch moves, so
// the hourly probe asks GitHub once per move.
type nixUrgentCache struct {
	Repository string         `json:"repository"`
	Base       string         `json:"base"`
	Head       string         `json:"head"`
	Urgent     []urgentCommit `json:"urgent"`
}

func nixUrgentCacheFile() string {
	return filepath.Join(sys.Xdg("XDG_CACHE_HOME", ".cache"), "ryoku", "nix-urgent.json")
}

// GitHub pages a long compare, oldest commits first. Every page is read, so
// the head (on the last one) and its first-parent line are in hand, up to a
// bound well past a box left without updates for months.
const (
	urgentComparePerPage  = 100
	urgentCompareMaxPages = 20
)

// nixUrgent lists the urgent commits between the source's installed commit
// and its branch tip. Best-effort and never nil: a missing commit, an
// up-to-date box or a failed lookup lists nothing, and only a lookup that
// answered is cached.
func nixUrgent(src nixUrgentSource) []urgentCommit {
	repo, base, head := src.Repository, src.InstalledRev, src.LatestRev
	if repo == "" || base == "" || head == "" || base == head {
		return []urgentCommit{}
	}
	if b, err := os.ReadFile(nixUrgentCacheFile()); err == nil {
		var c nixUrgentCache
		if json.Unmarshal(b, &c) == nil && c.Repository == repo && c.Base == base && c.Head == head && c.Urgent != nil {
			return c.Urgent
		}
	}
	commits, ok := fetchUrgentCompare(repo, base, head)
	if !ok {
		return []urgentCommit{}
	}
	urgent := firstParentUrgent(commits, head)
	if b, err := json.Marshal(nixUrgentCache{Repository: repo, Base: base, Head: head, Urgent: urgent}); err == nil {
		if os.MkdirAll(filepath.Dir(nixUrgentCacheFile()), 0o755) == nil {
			_ = os.WriteFile(nixUrgentCacheFile(), b, 0o644)
		}
	}
	return urgent
}

func fetchUrgentCompare(repo, base, head string) ([]urgentCompareCommit, bool) {
	var commits []urgentCompareCommit
	for page := 1; page <= urgentCompareMaxPages; page++ {
		var resp struct {
			TotalCommits int                   `json:"total_commits"`
			Commits      []urgentCompareCommit `json:"commits"`
		}
		url := fmt.Sprintf("%s/repos/%s/compare/%s...%s?per_page=%d&page=%d",
			githubAPI(), repo, base, head, urgentComparePerPage, page)
		if !getGitHubJSON(url, &resp) {
			return nil, false
		}
		commits = append(commits, resp.Commits...)
		if len(resp.Commits) < urgentComparePerPage || len(commits) >= resp.TotalCommits {
			break
		}
	}
	return commits, true
}

// getGitHubJSON fetches one GitHub API document into dst. Bounded, so an
// offline or rate-limited box answers at once.
func getGitHubJSON(url string, dst any) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return false
	}
	// GitHub 403s an API request with no User-Agent; the media type pins the
	// response shape.
	req.Header.Set("User-Agent", "ryoku-cli")
	req.Header.Set("Accept", "application/vnd.github+json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false
	}
	return json.NewDecoder(resp.Body).Decode(dst) == nil
}

// nixUrgentFrom reads the lookup source out of the helper's status document.
func nixUrgentFrom(status string) []urgentCommit {
	var src nixUrgentSource
	if json.Unmarshal([]byte(status), &src) != nil {
		return []urgentCommit{}
	}
	return nixUrgent(src)
}

// urgentStatus is `ryoku status --urgent`: the urgent list alone, so the
// shell can ask every hour between full checks. Only the Nix backend has one.
func urgentStatus() []urgentCommit {
	if !nixBackend() {
		return []urgentCommit{}
	}
	out, err := sys.RunOut("ryoku-nix-update", "status", "--json")
	if err != nil {
		return []urgentCommit{}
	}
	return nixUrgentFrom(out)
}
