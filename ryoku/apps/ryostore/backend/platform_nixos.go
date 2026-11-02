package main

import (
	"os"
	"strings"
)

func isNixOS() bool {
	data, err := os.ReadFile("/etc/os-release")
	return err == nil && isNixOSRelease(data)
}

func isNixOSRelease(data []byte) bool {
	for _, line := range strings.Split(string(data), "\n") {
		key, value, found := strings.Cut(strings.TrimSpace(line), "=")
		if found && key == "ID" {
			return strings.Trim(strings.TrimSpace(value), `"'`) == "nixos"
		}
	}
	return false
}
