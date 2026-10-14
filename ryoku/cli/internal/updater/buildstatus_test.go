package updater

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestChannelBuildStatusParsesStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/channels/testing/x86_64/status.json" {
			t.Errorf("path = %q, want /channels/testing/x86_64/status.json", r.URL.Path)
		}
		if r.Header.Get("Cache-Control") != "no-cache" {
			t.Errorf("Cache-Control = %q, want no-cache", r.Header.Get("Cache-Control"))
		}
		fmt.Fprint(w, `{"channel":"testing","state":"building","commit":"1d40d7a123","release":"v1","run":"https://example.test/run/1","started":"2026-10-12T18:34:55Z","finished":""}`)
	}))
	defer server.Close()
	t.Setenv("RYOKU_RELEASE_BASE", server.URL)
	t.Setenv("RYOKU_HOST_PKGMGR", "pacman")

	build, ok := channelBuildStatus("testing")
	if !ok {
		t.Fatal("channelBuildStatus returned ok=false")
	}
	if build.Channel != "testing" || build.State != "building" || build.Commit != "1d40d7a123" ||
		build.Release != "v1" || build.Run != "https://example.test/run/1" || build.Started != "2026-10-12T18:34:55Z" {
		t.Fatalf("unexpected build: %+v", build)
	}
}

func TestChannelBuildStatusNotFound(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	defer server.Close()
	t.Setenv("RYOKU_RELEASE_BASE", server.URL)
	t.Setenv("RYOKU_HOST_PKGMGR", "pacman")

	if build, ok := channelBuildStatus("testing"); ok {
		t.Fatalf("channelBuildStatus = %+v, true; want ok=false", build)
	}
}

func TestChannelBuildInProgress(t *testing.T) {
	now := time.Date(2026, time.October, 12, 20, 0, 0, 0, time.UTC)
	for _, test := range []struct {
		name  string
		build channelBuild
		want  bool
	}{
		{
			name:  "fresh building",
			build: channelBuild{State: "building", Started: now.Add(-12 * time.Minute).Format(time.RFC3339)},
			want:  true,
		},
		{
			name:  "stale building",
			build: channelBuild{State: "building", Started: now.Add(-2 * time.Hour).Format(time.RFC3339)},
			want:  false,
		},
		{
			name:  "published",
			build: channelBuild{State: "published", Started: now.Add(-12 * time.Minute).Format(time.RFC3339)},
			want:  false,
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := test.build.inProgress(now); got != test.want {
				t.Fatalf("inProgress() = %v, want %v", got, test.want)
			}
		})
	}
}

func TestReadCheckedPointerParsesPassed(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/channels/testing/checked.json" {
			t.Errorf("path = %q, want /channels/testing/checked.json", r.URL.Path)
		}
		fmt.Fprint(w, `{"commit":"new","state":"checking","run":"https://example.test/run/2","at":"2026-10-12T18:35:00Z","checks":["Go unit tests"],"passed":{"commit":"good","run":"https://example.test/run/1","at":"2026-10-12T18:30:00Z"}}`)
	}))
	defer server.Close()
	t.Setenv("RYOKU_RELEASE_BASE", server.URL)

	pointer, ok := readCheckedPointer()
	if !ok {
		t.Fatal("readCheckedPointer returned ok=false")
	}
	if pointer.Passed.Commit != "good" || pointer.Passed.Run != "https://example.test/run/1" || pointer.Passed.At != "2026-10-12T18:30:00Z" {
		t.Fatalf("unexpected passed pointer: %+v", pointer.Passed)
	}
}

func TestWaitForChannelBuildReturnsPublished(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		state := "building"
		if requests.Add(1) >= 2 {
			state = "published"
		}
		fmt.Fprintf(w, `{"channel":"testing","state":%q,"commit":"1d40d7a","started":%q}`, state, time.Now().Add(-time.Minute).Format(time.RFC3339))
	}))
	defer server.Close()
	t.Setenv("RYOKU_RELEASE_BASE", server.URL)
	t.Setenv("RYOKU_HOST_PKGMGR", "pacman")

	oldInterval := buildPollInterval
	buildPollInterval = 10 * time.Millisecond
	t.Cleanup(func() { buildPollInterval = oldInterval })

	build := waitForChannelBuild("testing", time.Second, nil)
	if build.State != "published" {
		t.Fatalf("state = %q, want published", build.State)
	}
	if requests.Load() < 2 {
		t.Fatalf("requests = %d, want at least 2", requests.Load())
	}
}
