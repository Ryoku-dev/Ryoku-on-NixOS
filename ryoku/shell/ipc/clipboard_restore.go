package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
)

// The selection keeper is tied to the daemon, so a daemon restart (an update, a
// deploy, a crash) takes the current copy with it and the next paste finds
// nothing, though the history still holds the entry. Within one compositor
// session the daemon puts that newest entry back. A new session (a login, a
// reboot, a compositor switch) starts with an empty clipboard as usual.

const clipSessionFile = "ryoku-clip-session"

// clipSessionKey names the compositor session the selection lives in. Every
// compositor start creates its Wayland socket afresh, so the socket's inode and
// change time differ after a re-login or a switch.
func clipSessionKey() string {
	sock := os.Getenv("WAYLAND_DISPLAY")
	if sock == "" {
		return ""
	}
	if !filepath.IsAbs(sock) {
		runtime := os.Getenv("XDG_RUNTIME_DIR")
		if runtime == "" {
			return ""
		}
		sock = filepath.Join(runtime, sock)
	}
	var st syscall.Stat_t
	if err := syscall.Stat(sock, &st); err != nil {
		return ""
	}
	return fmt.Sprintf("%d:%d.%d", st.Ino, st.Ctim.Sec, st.Ctim.Nsec)
}

func clipSessionPath() string {
	runtime := os.Getenv("XDG_RUNTIME_DIR")
	if runtime == "" {
		return ""
	}
	return filepath.Join(runtime, clipSessionFile)
}

// shouldRestoreSelection is the whole decision: only the session that recorded
// the marker, only with an entry to put back, only when nothing owns the
// selection now (asked last, since that spawns wl-paste).
func shouldRestoreSelection(recorded, current string, haveEntry bool, selectionEmpty func() bool) bool {
	return current != "" && recorded == current && haveEntry && selectionEmpty()
}

// selectionEmpty asks wl-paste whether anything offers the regular selection.
// An owner that does not answer counts as present: never overwrite a live copy.
func selectionEmpty() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	err := exec.CommandContext(ctx, "wl-paste", "--list-types").Run()
	if ctx.Err() != nil {
		return false
	}
	exit, ok := err.(*exec.ExitError)
	return ok && exit.ExitCode() == 1
}

// restoreSelection re-offers the newest history entry after a daemon restart in
// the same session, then records this session for the next restart. The watcher
// sees the selection change and promotes the same entry in place, so nothing is
// appended.
func (s *clipState) restoreSelection() {
	path := clipSessionPath()
	current := clipSessionKey()
	if path == "" || current == "" {
		return
	}
	recorded, _ := os.ReadFile(path)
	s.mu.Lock()
	var mime string
	var hash uint64
	var haveEntry bool
	if len(s.entries) > 0 {
		mime, hash = s.entries[0].Mime, s.entries[0].hash
		haveEntry = s.entries[0].Size > 0
	}
	s.mu.Unlock()
	if shouldRestoreSelection(string(recorded), current, haveEntry, selectionEmpty) {
		payload, err := s.openPayload(hash)
		if err == nil {
			cmd := exec.Command("wl-copy", "--type", mime)
			cmd.Stdin = payload
			_ = cmd.Run()
			_ = payload.Close()
		}
	}
	_ = os.WriteFile(path, []byte(current), 0o600)
}
