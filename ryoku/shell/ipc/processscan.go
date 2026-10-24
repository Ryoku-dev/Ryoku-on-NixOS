package main

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// currentUserProcessIDs is the in-process equivalent of pgrep -u <euid> -f.
// Linux exposes both the effective uid and the complete argv under /proc, so
// checking a locker never needs to fork another process.
func currentUserProcessIDs(pattern string) []string {
	return userProcessIDsUnder("/proc", os.Getuid(), pattern)
}

func currentUserProcessRunning(pattern string) bool {
	return len(currentUserProcessIDs(pattern)) != 0
}

func userProcessIDsUnder(root string, uid int, pattern string) []string {
	re, err := regexp.Compile(pattern)
	if err != nil {
		return nil
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	matches := make([]string, 0, 1)
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if _, err := strconv.Atoi(entry.Name()); err != nil {
			continue
		}
		base := filepath.Join(root, entry.Name())
		status, err := os.ReadFile(filepath.Join(base, "status"))
		if err != nil {
			continue
		}
		cmdline, err := os.ReadFile(filepath.Join(base, "cmdline"))
		if err != nil || !processRecordMatches(status, cmdline, uid, re) {
			continue
		}
		matches = append(matches, entry.Name())
	}
	return matches
}

func processRecordMatches(status, cmdline []byte, uid int, re *regexp.Regexp) bool {
	effective, ok := processEffectiveUID(status)
	return ok && effective == uid && re.MatchString(spaceJoinedCmdline(cmdline))
}

func processEffectiveUID(status []byte) (int, bool) {
	for _, line := range bytes.Split(status, []byte{'\n'}) {
		if !bytes.HasPrefix(line, []byte("Uid:")) {
			continue
		}
		fields := bytes.Fields(line)
		if len(fields) < 3 {
			return 0, false
		}
		uid, err := strconv.Atoi(string(fields[2]))
		return uid, err == nil
	}
	return 0, false
}

// pgrep -f joins argv with spaces before applying its extended regular
// expression. /proc writes a trailing NUL after the final argument.
func spaceJoinedCmdline(cmdline []byte) string {
	cmdline = bytes.TrimRight(cmdline, "\x00")
	return strings.ReplaceAll(string(cmdline), "\x00", " ")
}
