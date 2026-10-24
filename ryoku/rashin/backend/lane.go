package main

import (
	"os"
	"path/filepath"
)

// A lane is one purpose for an agent conversation. Each lane has its own
// working directory and harness process, so sessions and context never bleed
// between Agent, Chat, and internal Ask work.
type lane struct {
	Name string
	// Cwd is the session's working directory and the source of its context.
	Cwd string
	// ReadOnly marks internal lanes whose ACP permission policy never permits
	// a machine change.
	ReadOnly bool
	// Intro returns the preamble that rides a session's first turn, or "" for
	// none.
	Intro func() string
}

const (
	laneRyoku = "ryoku"
	laneChat  = "chat"
	laneAsk   = "ask"
)

func ryokuLane() lane {
	return lane{Name: laneRyoku, Cwd: VaultDir(),
		Intro: func() string { return LoadConfig().IntroPreamble() }}
}

func chatLane() lane {
	return lane{Name: laneChat, Cwd: ChatLaneDir(),
		Intro: func() string { return "" }}
}

func askLane() lane {
	return lane{Name: laneAsk, Cwd: AskLaneDir(), ReadOnly: true,
		Intro: func() string { return LoadConfig().IntroPreamble() }}
}

// ChatLaneDir is the plain-chat session cwd: under the state dir, outside the
// vault, so Hermes finds no AGENTS.md there (it reads the cwd only, never the
// parents) and nothing in it is a knowledge base anyone should write to.
func ChatLaneDir() string {
	if d := os.Getenv("RYOKU_RASHIN_CHAT_DIR"); d != "" {
		return d
	}
	state := os.Getenv("XDG_STATE_HOME")
	if state == "" {
		state = filepath.Join(home(), ".local", "state")
	}
	return filepath.Join(state, "ryoku", "rashin-chat")
}

// AskLaneDir is outside the vault so its fresh sessions cannot be mistaken for
// the persistent Agent lane's sessions.
func AskLaneDir() string {
	if d := os.Getenv("RYOKU_RASHIN_ASK_DIR"); d != "" {
		return d
	}
	state := os.Getenv("XDG_STATE_HOME")
	if state == "" {
		state = filepath.Join(home(), ".local", "state")
	}
	return filepath.Join(state, "ryoku", "rashin-ask")
}

func prepareLane(l lane) error {
	if err := os.MkdirAll(l.Cwd, 0o700); err != nil {
		return err
	}
	if l.Name != laneAsk {
		return nil
	}
	if err := os.Chmod(l.Cwd, 0o700); err != nil {
		return err
	}
	link := filepath.Join(l.Cwd, "AGENTS.md")
	target := filepath.Join(VaultDir(), "AGENTS.md")
	if got, err := os.Readlink(link); err == nil && resolvedPath(got) == resolvedPath(target) {
		return nil
	}
	if err := os.RemoveAll(link); err != nil {
		return err
	}
	return os.Symlink(target, link)
}

// ownsSession reports whether a stored session belongs to this lane: the one
// whose cwd it was opened in. Paths compare resolved, since a data dir reached
// through a symlink is still the same vault. An agent that reports no cwd
// cannot be sorted, so its sessions show in every lane rather than vanish.
func (l lane) ownsSession(s SessionMeta) bool {
	if s.Cwd == "" {
		return true
	}
	return resolvedPath(s.Cwd) == resolvedPath(l.Cwd)
}

// resolvedPath follows symlinks when the path still exists and cleans it
// either way, so two spellings of one directory compare equal.
func resolvedPath(p string) string {
	if r, err := filepath.EvalSymlinks(p); err == nil {
		return filepath.Clean(r)
	}
	return filepath.Clean(p)
}
