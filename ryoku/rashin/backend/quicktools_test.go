package main

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func setupQuickReadRoots(t *testing.T) (string, string) {
	t.Helper()
	homeDir := t.TempDir()
	vaultDir := filepath.Join(homeDir, "vault")
	t.Setenv("HOME", homeDir)
	t.Setenv("RYOKU_RASHIN_VAULT", vaultDir)
	for _, dir := range []string{
		vaultDir,
		filepath.Join(homeDir, ".config", "ryoku"),
		filepath.Join(homeDir, ".local", "share", "ryoku"),
	} {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	return homeDir, vaultDir
}

func writeQuickFixture(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestQuickReadToolsStayInsideApprovedRoots(t *testing.T) {
	homeDir, vaultDir := setupQuickReadRoots(t)
	allowed := []string{
		filepath.Join(vaultDir, "note.txt"),
		filepath.Join(homeDir, ".config", "ryoku", "settings.json"),
		filepath.Join(homeDir, ".local", "share", "ryoku", "state.txt"),
	}
	for _, path := range allowed {
		writeQuickFixture(t, path, "ordinary")
		if got := toolReadFile(path); got != "ordinary" {
			t.Errorf("toolReadFile(%q) = %q, want ordinary", path, got)
		}
	}

	outside := filepath.Join(homeDir, "outside", "leak.txt")
	writeQuickFixture(t, outside, "leak")
	boundary := filepath.Join(homeDir, ".config-escape", "leak.txt")
	writeQuickFixture(t, boundary, "leak")
	secretPaths := []string{
		filepath.Join(homeDir, ".ssh", "id_rsa"),
		filepath.Join(homeDir, ".hermes", ".env"),
		filepath.Join(homeDir, ".mozilla", "key4.db"),
		filepath.Join(homeDir, ".config", "app", "token"),
		filepath.Join(homeDir, ".config", "app", "api-key"),
		filepath.Join(homeDir, ".config", "app", "password"),
		filepath.Join(homeDir, ".config", "prowl-agent", "state"),
	}
	for _, path := range secretPaths {
		writeQuickFixture(t, path, "credential")
	}
	for _, path := range append([]string{outside, boundary}, secretPaths...) {
		if got := toolReadFile(path); !strings.HasPrefix(got, "error:") {
			t.Errorf("toolReadFile(%q) exposed %q", path, got)
		}
	}

	link := filepath.Join(homeDir, ".config", "ryoku", "outside-link")
	if err := os.Symlink(outside, link); err != nil {
		t.Fatal(err)
	}
	if got := toolReadFile(link); !strings.HasPrefix(got, "error:") {
		t.Errorf("toolReadFile(symlink outside roots) exposed %q", got)
	}

	if got := toolListDir(filepath.Join(homeDir, ".config", "ryoku")); strings.HasPrefix(got, "error:") {
		t.Errorf("toolListDir(allowed) = %q", got)
	}
	for _, path := range []string{
		filepath.Join(homeDir, ".ssh"),
		filepath.Join(homeDir, ".config", "app", "token"),
		filepath.Join(homeDir, ".config", "ryoku", "outside-link"),
	} {
		if got := toolListDir(path); !strings.HasPrefix(got, "error:") {
			t.Errorf("toolListDir(%q) exposed %q", path, got)
		}
	}
}

func TestQuickURLPolicyRejectsSSRFTargets(t *testing.T) {
	rejected := []string{
		"file:///etc/passwd",
		"ftp://example.com/file",
		"http://localhost:3600/api/manifest",
		"http://127.0.0.1:3600/api/manifest",
		"http://[::1]:3600/api/manifest",
		"http://0.0.0.0/",
		"http://[::]/",
		"http://10.0.0.1/",
		"http://172.16.0.1/",
		"http://192.168.1.1/",
		"http://169.254.169.254/latest/meta-data/",
		"http://[fe80::1]/",
	}
	for _, raw := range rejected {
		if err := validateQuickURL(raw); err == nil {
			t.Errorf("validateQuickURL(%q) accepted an SSRF target", raw)
		}
		if got := toolFetchURL(context.Background(), raw); !strings.HasPrefix(got, "error:") {
			t.Errorf("toolFetchURL(%q) = %q, want refusal", raw, got)
		}
	}
	for _, raw := range []string{"http://8.8.8.8/", "https://1.1.1.1/"} {
		if err := validateQuickURL(raw); err != nil {
			t.Errorf("validateQuickURL(%q) = %v, want public URL accepted", raw, err)
		}
	}
	for _, address := range []string{"127.0.0.1:80", "[::1]:80", "169.254.169.254:80"} {
		conn, err := quickDialContext(context.Background(), "tcp", address)
		if conn != nil {
			conn.Close()
		}
		if err == nil {
			t.Errorf("quickDialContext(%q) accepted a private address", address)
		}
	}
}

func TestQuickRedirectPolicyRechecksEveryHop(t *testing.T) {
	privateReq, err := http.NewRequest(http.MethodGet, "http://[::1]:3600/api/manifest", nil)
	if err != nil {
		t.Fatal(err)
	}
	publicReq, err := http.NewRequest(http.MethodGet, "https://1.1.1.1/", nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := quickCheckRedirect(privateReq, []*http.Request{publicReq}); err == nil {
		t.Fatal("redirect to loopback was accepted")
	}
	if err := quickCheckRedirect(publicReq, []*http.Request{publicReq, publicReq, publicReq}); err != nil {
		t.Fatalf("third public redirect was rejected: %v", err)
	}
	if err := quickCheckRedirect(publicReq, []*http.Request{publicReq, publicReq, publicReq, publicReq}); err == nil {
		t.Fatal("fourth redirect was accepted")
	}
}
