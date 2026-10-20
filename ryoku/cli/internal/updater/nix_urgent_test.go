package updater

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
)

func TestUrgentReason(t *testing.T) {
	cases := []struct {
		name, message, want string
	}{
		{"trailer", "fix(lock): close the bypass\n\nBody.\n\nUrgent: the lock screen opened without a password", "the lock screen opened without a password"},
		{"beside Note", "fix(x): y\n\nNote: Fixed: the lock\nUrgent: lock bypass\n", "lock bypass"},
		{"merge commit", "Merge pull request #30 from someone/fix\n\nfix(lock): close the bypass\n\nUrgent: lock bypass", "lock bypass"},
		{"any case", "s\n\nurgent:   spaced out  ", "spaced out"},
		{"crlf", "s\r\n\r\nUrgent: windows line ends\r\n", "windows line ends"},
		{"subject only", "Urgent: a subject is no trailer", ""},
		{"body paragraph", "s\n\nUrgent: in the body\n\nNote: New: something", ""},
		{"empty value", "s\n\nUrgent:   ", ""},
		{"other key", "s\n\nUrgently: no", ""},
		{"none", "s\n\nbody only", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := urgentReason(tc.message); got != tc.want {
				t.Errorf("urgentReason(%q) = %q, want %q", tc.message, got, tc.want)
			}
		})
	}
	long := "s\n\nUrgent: " + strings.Repeat("x", 400)
	if got := []rune(urgentReason(long)); len(got) != urgentReasonMax {
		t.Errorf("a long reason clips to %d runes, got %d", urgentReasonMax, len(got))
	}
}

// urgentFixture is one commit for the stub compare API: sha, message and its
// parents, first parent first.
type urgentFixture struct {
	sha, message string
	parents      []string
}

func urgentFixtureJSON(c urgentFixture) map[string]any {
	parents := make([]map[string]string, 0, len(c.parents))
	for _, p := range c.parents {
		parents = append(parents, map[string]string{"sha": p})
	}
	return map[string]any{"sha": c.sha, "commit": map[string]any{"message": c.message}, "parents": parents}
}

// A merged pull request on the port: the maintainer's own commit and the merge
// are on the first-parent line, the contributor's commit is the merge's
// second parent.
var portMergedPR = []urgentFixture{
	{"1111111aaaaaa", "fix(lock): close it\n\nUrgent: maintainer fix", []string{"0000000aaaaaa"}},
	{"2222222bbbbbb", "feat(x): contributor\n\nUrgent: smuggled in", []string{"0000000aaaaaa"}},
	{"3333333cccccc", "Merge pull request #30 from someone/x", []string{"1111111aaaaaa", "2222222bbbbbb"}},
	{"4444444dddddd", "Merge pull request #31 from someone/y\n\nfix(y): head\n\nUrgent: head fix", []string{"3333333cccccc"}},
}

func TestFirstParentUrgentSkipsMergedBranch(t *testing.T) {
	var commits []urgentCompareCommit
	for _, c := range portMergedPR {
		b, _ := json.Marshal(urgentFixtureJSON(c))
		var cc urgentCompareCommit
		if err := json.Unmarshal(b, &cc); err != nil {
			t.Fatal(err)
		}
		commits = append(commits, cc)
	}
	got := firstParentUrgent(commits, "4444444")
	want := []urgentCommit{
		{Commit: "4444444", Subject: "Merge pull request #31 from someone/y", Reason: "head fix"},
		{Commit: "1111111", Subject: "fix(lock): close it", Reason: "maintainer fix"},
	}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("firstParentUrgent = %+v, want %+v (the merged branch's commit never counts)", got, want)
	}
	if got := firstParentUrgent(commits, "9999999"); len(got) != 0 {
		t.Errorf("a head outside the compare lists nothing, got %+v", got)
	}
}

// stubUrgentCompare serves fixtures oldest first in pages of per_page, the way
// GitHub pages a long compare, records the paths asked for and counts them.
func stubUrgentCompare(t *testing.T, fixtures []urgentFixture) (*httptest.Server, *int32, *[]string) {
	t.Helper()
	var hits int32
	paths := []string{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&hits, 1)
		paths = append(paths, r.URL.Path)
		if r.Header.Get("User-Agent") == "" {
			t.Error("request missing User-Agent (GitHub 403s without one)")
		}
		perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
		page, _ := strconv.Atoi(r.URL.Query().Get("page"))
		if perPage <= 0 || page <= 0 {
			t.Errorf("compare request without paging: %s", r.URL)
			perPage, page = len(fixtures), 1
		}
		from := min((page-1)*perPage, len(fixtures))
		to := min(from+perPage, len(fixtures))
		arr := []map[string]any{}
		for _, c := range fixtures[from:to] {
			arr = append(arr, urgentFixtureJSON(c))
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"total_commits": len(fixtures), "commits": arr})
	}))
	t.Cleanup(srv.Close)
	return srv, &hits, &paths
}

var portSource = nixUrgentSource{Repository: "aethctl/Ryoku-on-NixOS", InstalledRev: "0000000aaaaaa", LatestRev: "4444444dddddd"}

func TestNixUrgentAsksThePortRepository(t *testing.T) {
	srv, hits, paths := stubUrgentCompare(t, portMergedPR)
	t.Setenv("RYOKU_GITHUB_API", srv.URL)
	t.Setenv("XDG_CACHE_HOME", t.TempDir())

	got := nixUrgent(portSource)
	if len(got) != 2 || got[0].Reason != "head fix" || got[1].Reason != "maintainer fix" {
		t.Fatalf("urgent = %+v, want the head and the maintainer's commit", got)
	}
	if want := "/repos/aethctl/Ryoku-on-NixOS/compare/0000000aaaaaa...4444444dddddd"; (*paths)[0] != want {
		t.Errorf("asked %s, want %s", (*paths)[0], want)
	}
	// The hourly probe asks again with the same pair: the cache answers.
	if got := nixUrgent(portSource); len(got) != 2 {
		t.Errorf("cached urgent = %+v, want the same two commits", got)
	}
	if n := atomic.LoadInt32(hits); n != 1 {
		t.Errorf("compare requests = %d, want 1", n)
	}
	// The branch moved: a new lookup.
	moved := portSource
	moved.LatestRev = "3333333cccccc"
	if got := nixUrgent(moved); len(got) != 1 || got[0].Reason != "maintainer fix" {
		t.Errorf("urgent after the branch moved = %+v, want the maintainer's commit", got)
	}
	if n := atomic.LoadInt32(hits); n != 2 {
		t.Errorf("compare requests = %d, want 2", n)
	}
}

func TestNixUrgentNothingToCompare(t *testing.T) {
	srv, hits, _ := stubUrgentCompare(t, portMergedPR)
	t.Setenv("RYOKU_GITHUB_API", srv.URL)
	t.Setenv("XDG_CACHE_HOME", t.TempDir())

	for _, src := range []nixUrgentSource{
		{},
		{Repository: "aethctl/Ryoku-on-NixOS", InstalledRev: "4444444dddddd", LatestRev: "4444444dddddd"},
		{Repository: "aethctl/Ryoku-on-NixOS", InstalledRev: "0000000aaaaaa"},
		{InstalledRev: "0000000aaaaaa", LatestRev: "4444444dddddd"},
	} {
		if got := nixUrgent(src); got == nil || len(got) != 0 {
			t.Errorf("nixUrgent(%+v) = %#v, want an empty, non-nil list", src, got)
		}
	}
	if n := atomic.LoadInt32(hits); n != 0 {
		t.Errorf("compare requests = %d, want none", n)
	}
}

// A box left without updates for months jumps hundreds of commits. The head
// sits on the last page, so every page is read before the walk can start.
func TestNixUrgentReadsEveryPage(t *testing.T) {
	var fixtures []urgentFixture
	parent := "0000000aaaaaa"
	for i := range 330 {
		sha := fmt.Sprintf("%07x%05d", i+1, i)
		msg := fmt.Sprintf("Merge pull request #%d from someone/x", i)
		if i == 5 || i == 329 {
			msg += fmt.Sprintf("\n\nUrgent: fix %d", i)
		}
		fixtures = append(fixtures, urgentFixture{sha, msg, []string{parent}})
		parent = sha
	}
	srv, hits, _ := stubUrgentCompare(t, fixtures)
	t.Setenv("RYOKU_GITHUB_API", srv.URL)
	t.Setenv("XDG_CACHE_HOME", t.TempDir())

	got := nixUrgent(nixUrgentSource{Repository: "aethctl/Ryoku-on-NixOS", InstalledRev: "0000000aaaaaa", LatestRev: fixtures[329].sha})
	if len(got) != 2 || got[0].Reason != "fix 329" || got[1].Reason != "fix 5" {
		t.Errorf("urgent = %+v, want fix 329 and fix 5", got)
	}
	if n := atomic.LoadInt32(hits); n != 4 {
		t.Errorf("compare requests = %d, want 4 pages of 100", n)
	}
}

// Offline or rate-limited: nothing is listed and nothing is cached, so the next
// probe asks again.
func TestNixUrgentFailureIsNotCached(t *testing.T) {
	var fail atomic.Bool
	fail.Store(true)
	ok, _, _ := stubUrgentCompare(t, portMergedPR)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if fail.Load() {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		ok.Config.Handler.ServeHTTP(w, r)
	}))
	t.Cleanup(srv.Close)
	t.Setenv("RYOKU_GITHUB_API", srv.URL)
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)

	if got := nixUrgent(portSource); got == nil || len(got) != 0 {
		t.Errorf("a failed lookup = %#v, want an empty, non-nil list", got)
	}
	if _, err := os.Stat(filepath.Join(cache, "ryoku", "nix-urgent.json")); !os.IsNotExist(err) {
		t.Errorf("a failed lookup must not write the cache (stat err = %v)", err)
	}
	fail.Store(false)
	if got := nixUrgent(portSource); len(got) != 2 {
		t.Errorf("urgent once GitHub answers = %+v, want both commits", got)
	}
}

// fakeNixUpdate puts a `ryoku-nix-update` on PATH that prints status and logs
// that it ran.
func fakeNixUpdate(t *testing.T, status string) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "ran")
	script := "#!/bin/sh\nprintf '%s\\n' \"$*\" >> " + log + "\ncat <<'EOF'\n" + status + "\nEOF\n"
	if err := os.WriteFile(filepath.Join(dir, "ryoku-nix-update"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+":"+os.Getenv("PATH"))
	return log
}

func TestNixStatusCarriesUrgent(t *testing.T) {
	srv, _, _ := stubUrgentCompare(t, portMergedPR)
	t.Setenv("RYOKU_GITHUB_API", srv.URL)
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	fakeNixUpdate(t, `{"installedVersion":"0.102.3-beta.20","latestVersion":"0.102.3-beta.20","available":true,"pendingUpdates":1,`+
		`"updates":[],"recent":[],"channel":"unstable-dev","packages":[],"backend":"nix","canUpdate":true,`+
		`"source":"github:aethctl/Ryoku-on-NixOS/unstable-dev","repository":"aethctl/Ryoku-on-NixOS",`+
		`"installedRev":"0000000aaaaaa","latestRev":"4444444dddddd"}`)

	r := nixStatus()
	if len(r.Urgent) != 2 || r.Urgent[0].Commit != "4444444" {
		t.Fatalf("nix status urgent = %+v, want the head and the maintainer's commit", r.Urgent)
	}
	b, _ := json.Marshal(r)
	if !strings.Contains(string(b), `"urgent":[{"commit":"4444444","subject":"Merge pull request #31 from someone/y","reason":"head fix"}`) {
		t.Errorf("status JSON = %s, want the urgent list under \"urgent\"", b)
	}
}

func TestUrgentStatusIsNixOnly(t *testing.T) {
	srv, hits, _ := stubUrgentCompare(t, portMergedPR)
	t.Setenv("RYOKU_GITHUB_API", srv.URL)
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	ran := fakeNixUpdate(t, `{"repository":"aethctl/Ryoku-on-NixOS","installedRev":"0000000aaaaaa","latestRev":"4444444dddddd"}`)

	t.Setenv("RYOKU_UPDATE_BACKEND", "pacman")
	if got := urgentStatus(); got == nil || len(got) != 0 {
		t.Errorf("urgentStatus off Nix = %#v, want an empty, non-nil list", got)
	}
	if _, err := os.Stat(ran); !os.IsNotExist(err) || atomic.LoadInt32(hits) != 0 {
		t.Errorf("off Nix neither the helper nor GitHub is asked (helper log err = %v, requests = %d)", err, atomic.LoadInt32(hits))
	}
	b, _ := json.Marshal(statusReport{})
	if strings.Contains(string(b), `"urgent"`) {
		t.Errorf("a report with no urgent list leaves the key out: %s", b)
	}

	t.Setenv("RYOKU_UPDATE_BACKEND", "nix")
	if got := urgentStatus(); len(got) != 2 {
		t.Errorf("urgentStatus on Nix = %+v, want both commits", got)
	}
	if log, _ := os.ReadFile(ran); strings.TrimSpace(string(log)) != "status --json" {
		t.Errorf("helper ran with %q, want status --json", log)
	}
}
