package main

import (
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"
)

// A read is the request hyprctl -j would send, answered on the request socket
// of the session the environment names, with no process launched.
func TestSocketQuerySendsJSONRequest(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "hypr", "sig")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_RUNTIME_DIR", filepath.Dir(filepath.Dir(dir)))
	t.Setenv("HYPRLAND_INSTANCE_SIGNATURE", "sig")
	listener, err := net.Listen("unix", filepath.Join(dir, ".socket.sock"))
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	requests := make(chan string, 1)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		raw, _ := io.ReadAll(conn)
		requests <- string(raw)
		_, _ = io.WriteString(conn, `[{"name":"DP-1"}]`)
	}()

	out, err := socketQuery("monitors", "all")
	if err != nil {
		t.Fatal(err)
	}
	if got := <-requests; got != "j/monitors all" {
		t.Fatalf("request = %q, want %q", got, "j/monitors all")
	}
	if string(out) != `[{"name":"DP-1"}]` {
		t.Fatalf("reply = %q", out)
	}
}

func TestSocketQueryWithoutSessionFails(t *testing.T) {
	t.Setenv("HYPRLAND_INSTANCE_SIGNATURE", "")
	if _, err := socketQuery("clients"); err == nil {
		t.Fatal("query without a session signature succeeded")
	}
}
