package host

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
)

func TestFedoraReleaseStatus(t *testing.T) {
	for _, tc := range []struct {
		name            string
		version         string
		repoBasePath    string
		repoPath        string
		writeRepo       bool
		headStatus      int
		getStatus       int
		wantPublished   bool
		wantRepoMethods []string
	}{
		{
			name:            "testing channel",
			version:         "44",
			repoBasePath:    "/fedora/$releasever/channels/testing/x86_64",
			repoPath:        "/fedora/44/channels/testing/x86_64/repodata/repomd.xml",
			writeRepo:       true,
			headStatus:      http.StatusOK,
			wantPublished:   true,
			wantRepoMethods: []string{http.MethodHead},
		},
		{
			name:            "frozen testing build",
			version:         "44",
			repoBasePath:    "/fedora/$releasever/channels/testing/builds/v0.60.0-beta.1.dev.7_gabc123/x86_64",
			repoPath:        "/fedora/44/channels/testing/builds/v0.60.0-beta.1.dev.7_gabc123/x86_64/repodata/repomd.xml",
			writeRepo:       true,
			headStatus:      http.StatusOK,
			wantPublished:   true,
			wantRepoMethods: []string{http.MethodHead},
		},
		{
			name:            "unpublished release",
			version:         "46",
			repoBasePath:    "/fedora/$releasever/channels/testing/x86_64",
			repoPath:        "/fedora/46/channels/testing/x86_64/repodata/repomd.xml",
			writeRepo:       true,
			headStatus:      http.StatusNotFound,
			wantRepoMethods: []string{http.MethodHead},
		},
		{
			name:            "HEAD unsupported",
			version:         "44",
			repoBasePath:    "/fedora/$releasever/channels/testing/x86_64",
			repoPath:        "/fedora/44/channels/testing/x86_64/repodata/repomd.xml",
			writeRepo:       true,
			headStatus:      http.StatusMethodNotAllowed,
			getStatus:       http.StatusOK,
			wantPublished:   true,
			wantRepoMethods: []string{http.MethodHead, http.MethodGet},
		},
		{
			name:            "missing config falls back to stable",
			version:         "44",
			repoPath:        "/fedora/44/x86_64/repodata/repomd.xml",
			headStatus:      http.StatusOK,
			wantPublished:   true,
			wantRepoMethods: []string{http.MethodHead},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var mu sync.Mutex
			var repoMethods []string
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch r.URL.Path {
				case tc.repoPath:
					mu.Lock()
					repoMethods = append(repoMethods, r.Method)
					mu.Unlock()
					status := tc.headStatus
					if r.Method == http.MethodGet && tc.getStatus != 0 {
						status = tc.getStatus
					}
					w.WriteHeader(status)
				case "/fedora/releases":
					_, _ = w.Write([]byte("44\n45\n44\n"))
				default:
					http.NotFound(w, r)
				}
			}))
			defer server.Close()

			osRelease := filepath.Join(t.TempDir(), "os-release")
			if err := os.WriteFile(osRelease, []byte("ID=fedora\nVERSION_ID="+tc.version+"\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			repoConfig := filepath.Join(t.TempDir(), "ryoku.repo")
			if tc.writeRepo {
				body := "[ryoku]\nbaseurl=" + server.URL + tc.repoBasePath + "\n"
				if err := os.WriteFile(repoConfig, []byte(body), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			t.Setenv("RYOKU_HOST_PKGMGR", "dnf")
			t.Setenv("RYOKU_OS_RELEASE", osRelease)
			t.Setenv("RYOKU_DNF_REPO_CONFIG", repoConfig)
			t.Setenv("RYOKU_RELEASE_BASE", server.URL+"/fedora/$releasever")
			app := New(Config{
				HTTPClient:        server.Client(),
				FedoraReleasesURL: server.URL + "/fedora/releases",
			})

			status, err := app.FedoraReleaseStatus()
			if err != nil {
				t.Fatal(err)
			}
			if status.Version != tc.version || status.Published != tc.wantPublished || !status.RepositoryChecked {
				t.Fatalf("status = %+v", status)
			}
			if !reflect.DeepEqual(status.Supported, []string{"44", "45"}) {
				t.Fatalf("supported = %v", status.Supported)
			}
			mu.Lock()
			gotMethods := append([]string(nil), repoMethods...)
			mu.Unlock()
			if !reflect.DeepEqual(gotMethods, tc.wantRepoMethods) {
				t.Fatalf("repository methods = %v, want %v", gotMethods, tc.wantRepoMethods)
			}
		})
	}
}

func TestFedoraReleaseStatusRejectsMalformedConfiguredRepo(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		requests++
	}))
	defer server.Close()

	osRelease := filepath.Join(t.TempDir(), "os-release")
	if err := os.WriteFile(osRelease, []byte("VERSION_ID=44\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	repoConfig := filepath.Join(t.TempDir(), "ryoku.repo")
	if err := os.WriteFile(repoConfig, []byte("[ryoku]\nenabled=1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_HOST_PKGMGR", "dnf")
	t.Setenv("RYOKU_OS_RELEASE", osRelease)
	t.Setenv("RYOKU_DNF_REPO_CONFIG", repoConfig)
	t.Setenv("RYOKU_RELEASE_BASE", server.URL+"/fedora/$releasever")

	status, err := New(Config{
		HTTPClient:        server.Client(),
		FedoraReleasesURL: server.URL + "/fedora/releases",
	}).FedoraReleaseStatus()
	if err == nil || !strings.Contains(err.Error(), "no [ryoku] baseurl") {
		t.Fatalf("error = %v", err)
	}
	if status.RepositoryChecked || requests != 0 {
		t.Fatalf("status = %+v after %d request(s)", status, requests)
	}
}

func TestFedoraReleaseStatusKeepsRepositoryResultWhenReleaseListFails(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/fedora/45/x86_64/repodata/repomd.xml" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		http.Error(w, "missing", http.StatusNotFound)
	}))
	defer server.Close()

	osRelease := filepath.Join(t.TempDir(), "os-release")
	if err := os.WriteFile(osRelease, []byte("VERSION_ID=45\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_HOST_PKGMGR", "dnf")
	t.Setenv("RYOKU_OS_RELEASE", osRelease)
	t.Setenv("RYOKU_DNF_REPO_CONFIG", filepath.Join(t.TempDir(), "missing.repo"))
	t.Setenv("RYOKU_RELEASE_BASE", server.URL+"/fedora/$releasever")
	app := New(Config{
		HTTPClient:        server.Client(),
		FedoraReleasesURL: server.URL + "/fedora/releases",
	})

	status, err := app.FedoraReleaseStatus()
	if err == nil {
		t.Fatal("missing release list returned no error")
	}
	if status.Version != "45" || status.Published || !status.RepositoryChecked {
		t.Fatalf("status = %+v", status)
	}
}
