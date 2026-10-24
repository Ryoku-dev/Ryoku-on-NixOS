package sys

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

const defaultNixIntegrationPath = "/etc/ryoku/nix-integration.json"

type NixPackage struct {
	Name string `json:"name"`
	Path string `json:"path"`
}

type NixIntegration struct {
	Schema            int          `json:"schema"`
	Version           string       `json:"version"`
	Flake             string       `json:"flake"`
	Host              string       `json:"host"`
	Input             string       `json:"input"`
	ConfigBase        string       `json:"configBase"`
	I18nDir           string       `json:"i18nDir"`
	Browser           string       `json:"browser"`
	DefaultCompositor string       `json:"defaultCompositor"`
	Shell             string       `json:"shell"`
	OptionalApps      []string     `json:"optionalApps"`
	Packages          []NixPackage `json:"packages"`
}

func NixIntegrationPath() string {
	if p := strings.TrimSpace(os.Getenv("RYOKU_NIX_INTEGRATION")); p != "" {
		return p
	}
	return defaultNixIntegrationPath
}

func ReadNixIntegration() (NixIntegration, error) {
	var integration NixIntegration
	body, err := os.ReadFile(NixIntegrationPath())
	if err != nil {
		return integration, err
	}
	err = json.Unmarshal(body, &integration)
	return integration, err
}

// NixBackend reports whether this Ryoku binary is running under the
// declarative NixOS integration.
func NixBackend() bool {
	backend := strings.ToLower(strings.TrimSpace(os.Getenv("RYOKU_UPDATE_BACKEND")))
	switch backend {
	case "nix":
		return true
	case "pacman", "arch":
		return false
	}

	if _, err := os.Stat(NixIntegrationPath()); err == nil {
		return true
	}
	_, err := os.Stat("/etc/ryoku/nix-system-package-count")
	return err == nil
}

func NixPackageInstalled(name string) bool {
	integration, err := ReadNixIntegration()
	if err != nil {
		return false
	}
	name = strings.TrimSpace(name)
	for _, pkg := range integration.Packages {
		if pkg.Name == name {
			return true
		}
	}
	return false
}

func NixPackagePath(name string) string {
	integration, err := ReadNixIntegration()
	if err != nil {
		return ""
	}
	for _, pkg := range integration.Packages {
		if pkg.Name == name {
			return pkg.Path
		}
	}
	return ""
}

func IsNixStorePath(path string) bool {
	path = strings.TrimSpace(path)
	if path == "" {
		return false
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err == nil {
		path = resolved
	}
	return strings.HasPrefix(filepath.Clean(path), "/nix/store/")
}
