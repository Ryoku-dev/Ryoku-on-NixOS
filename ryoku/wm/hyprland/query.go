package main

import (
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// query is the choke point for every JSON state read: the request hyprctl -j
// sends, written straight to the request socket so a refresh launches no
// process. Commands that change state stay on ctl. A var so tests can answer
// reads without a compositor.
var query = socketQuery

func socketQuery(args ...string) ([]byte, error) {
	sig := os.Getenv("HYPRLAND_INSTANCE_SIGNATURE")
	if sig == "" {
		return nil, fmt.Errorf("no live Hyprland session")
	}
	request := "j/" + strings.Join(args, " ")
	conn, err := net.DialTimeout("unix", filepath.Join(runDir(), sig, ".socket.sock"), 200*time.Millisecond)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", request, err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(500 * time.Millisecond))
	if _, err := io.WriteString(conn, request); err != nil {
		return nil, fmt.Errorf("%s: %w", request, err)
	}
	if unix, ok := conn.(*net.UnixConn); ok {
		_ = unix.CloseWrite()
	}
	out, err := io.ReadAll(conn)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", request, err)
	}
	return out, nil
}
