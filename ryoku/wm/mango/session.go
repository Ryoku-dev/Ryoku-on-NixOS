package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	wm "ryoku-wm"
)

// mangoConfigDir is where this provider's generated and user-owned config lives.
func mangoConfigDir() string {
	if base := os.Getenv("XDG_CONFIG_HOME"); base != "" {
		return filepath.Join(base, "mango")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".config", "mango")
}

var sessionEnvironmentRoot = "/proc"

func processEnvironmentValue(data []byte, key string) string {
	for _, kv := range bytes.Split(data, []byte{0}) {
		if rest, ok := strings.CutPrefix(string(kv), key+"="); ok {
			return rest
		}
	}
	return ""
}

// runEnvironment exports only this provider's opaque session handle, as one
// `MANGO_INSTANCE_SIGNATURE=<path>` NUL-terminated record — the same shape the
// lifecycle owner (ryoku-power-cutover) folds into the per-session environment
// file it reads back for every provider.
//
// Two routes, tried in order:
//
//  1. the handle in the process's own environment. mango setenvs it at
//     startup, and every process the compositor spawns (the shell, terminals,
//     the whole session) inherits it, so any session client answers this way.
//  2. derived from the pid. /proc/<pid>/environ is frozen at exec, so the
//     compositor process ITSELF carries no handle there; but mango names its
//     socket after that pid ($XDG_RUNTIME_DIR/mango-<pid>.sock, src/ipc/ipc.c),
//     so when the scanned process is a verified mango instance the handle is
//     reconstructed exactly. The socket's presence is the proof.
//
// A process that answers neither route is not a mango session member, and the
// verb says so with a nonzero exit rather than printing an empty record.
func runEnvironment(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("environment: expected one process id")
	}
	pid, err := strconv.Atoi(args[0])
	if err != nil || pid <= 0 {
		return fmt.Errorf("environment: invalid process id %q", args[0])
	}
	envData, err := os.ReadFile(filepath.Join(sessionEnvironmentRoot, args[0], "environ"))
	if err != nil {
		return fmt.Errorf("environment: read process %s: %w", args[0], err)
	}
	if handle := processEnvironmentValue(envData, "MANGO_INSTANCE_SIGNATURE"); handle != "" {
		_, err = fmt.Fprintf(stdout, "MANGO_INSTANCE_SIGNATURE=%s%c", handle, byte(0))
		return err
	}
	comm, err := os.ReadFile(filepath.Join(sessionEnvironmentRoot, args[0], "comm"))
	if err != nil || strings.TrimSpace(string(comm)) != wm.ProviderMango {
		return fmt.Errorf("environment: pid %s is not a mango session", args[0])
	}
	runtime := processEnvironmentValue(envData, "XDG_RUNTIME_DIR")
	if runtime == "" {
		return fmt.Errorf("environment: pid %s has no runtime dir", args[0])
	}
	handle := filepath.Join(runtime, "mango-"+strconv.Itoa(pid)+".sock")
	if _, err := os.Stat(handle); err != nil {
		return fmt.Errorf("environment: pid %s names an unreachable socket", args[0])
	}
	_, err = fmt.Fprintf(stdout, "MANGO_INSTANCE_SIGNATURE=%s%c", handle, byte(0))
	return err
}
