package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Mango's runtime layout and the one way this provider talks to the compositor.
//
// Mango's IPC is a line-oriented text protocol over a unix socket: one command
// line in, one JSON line back. Unlike niri there is no envelope to unwrap: the
// reply IS the payload, and an error arrives as an {"error":...} object with a
// zero exit, so every read path must check the error field rather than the
// process status. That difference is pinned by wire_test.
//
// request is the single choke point for every one-shot command, so the
// isolation gate has one line to allow. A var so tests can pin the emitted
// request line without a live compositor.
var request = sendRequest

const dialTimeout = 200 * time.Millisecond

func sendRequest(cmd string) (json.RawMessage, error) {
	conn, _, err := open(cmd)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		return nil, fmt.Errorf("mango %s: %w", cmd, err)
	}
	return unwrap(cmd, line)
}

// open dials and sends, returning the connection so a watch can keep reading
// from it. The command text comes back for error messages.
func open(cmd string) (net.Conn, string, error) {
	path := socketPath()
	if path == "" {
		return nil, cmd, fmt.Errorf("mango %s: no socket", cmd)
	}
	conn, err := net.DialTimeout("unix", path, dialTimeout)
	if err != nil {
		return nil, cmd, fmt.Errorf("mango %s: %w", cmd, err)
	}
	if _, err := conn.Write(append([]byte(cmd), '\n')); err != nil {
		_ = conn.Close()
		return nil, cmd, fmt.Errorf("mango %s: %w", cmd, err)
	}
	return conn, cmd, nil
}

// unwrap passes mango's own error wording through rather than paraphrasing, so
// a protocol change reads as itself. The {"success":true} ack carries nothing a
// caller needs; commands that change state answer only that.
func unwrap(cmd string, line []byte) (json.RawMessage, error) {
	trimmed := strings.TrimSpace(string(line))
	if trimmed == "" {
		return nil, fmt.Errorf("mango %s: empty reply", cmd)
	}
	var probe struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal([]byte(trimmed), &probe); err != nil {
		return nil, fmt.Errorf("mango %s: bad reply %q", cmd, trimmed)
	}
	if probe.Error != "" {
		return nil, fmt.Errorf("mango %s: %s", cmd, probe.Error)
	}
	return json.RawMessage(trimmed), nil
}

// socketPath prefers the handle the session exported, then the newest socket in
// the runtime dir. The fallback matters because the shell daemon restarts from
// the user manager's environment, which can name a socket whose instance died.
func socketPath() string {
	if h := os.Getenv("MANGO_INSTANCE_SIGNATURE"); h != "" && liveAt(h) {
		return h
	}
	return liveSocket()
}

// mango names its socket mango-<pid>.sock in $XDG_RUNTIME_DIR (src/ipc/ipc.c),
// so a stale file from a crashed instance sits beside a live one. Newest that
// actually answers wins.
func liveSocket() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		return ""
	}
	matches, err := filepath.Glob(filepath.Join(dir, "mango-*.sock"))
	if err != nil || len(matches) == 0 {
		return ""
	}
	var best string
	var bestTime time.Time
	for _, m := range matches {
		info, err := os.Stat(m)
		if err != nil {
			continue
		}
		if !liveAt(m) {
			continue
		}
		if info.ModTime().After(bestTime) {
			best, bestTime = m, info.ModTime()
		}
	}
	return best
}

// aliveCheck is a var so tests can satisfy live() without a compositor.
var aliveCheck = socketAlive

func socketAlive(path string) bool {
	conn, err := net.DialTimeout("unix", path, dialTimeout)
	if err != nil {
		return false
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(dialTimeout))
	if _, err := conn.Write([]byte("get version\n")); err != nil {
		return false
	}
	line, err := bufio.NewReader(conn).ReadString('\n')
	return err == nil && strings.Contains(line, `"version"`)
}

func liveAt(path string) bool { return aliveCheck(path) }

// live lets verbs fail fast instead of hanging on a dead socket.
func live() bool { return aliveCheck(socketPath()) && socketPath() != "" }

// instanceHandle is opaque to consumers, which only string-compare it. The
// socket path carries the instance pid, so it identifies this session and no
// other.
func instanceHandle() string {
	return socketPath()
}

// get runs a `get` command and decodes its JSON reply into dst.
func get(what string, dst any) error {
	raw, err := request("get " + what)
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, dst)
}

// dispatch runs a compositor action and checks the reply. An unknown function
// answers {"error":"unknown function"} with a zero exit, so a mistyped name
// only fails here, never silently.
func dispatch(args ...string) error {
	_, err := request("dispatch " + strings.Join(args, ","))
	return err
}
