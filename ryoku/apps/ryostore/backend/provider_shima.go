package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func shimaProfile() string {
	return filepath.Join(stateHome(), "ryoku", "subshells", "iris", "profile")
}

func shimaRuntime() string {
	path := filepath.Join(shimaProfile(), "bin", "ryoku-shima")
	if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0111 != 0 {
		return path
	}
	path, _ = exec.LookPath("ryoku-shima")
	return path
}

func shimaItem() Item {
	installed := shimaRuntime() != ""
	_, ownedErr := os.Lstat(shimaProfile())
	ref := os.Getenv("RYOKU_SHIMA_FLAKE")
	version := ""
	if ref != "" {
		version = filepath.Base(ref)
	}
	current, _ := os.ReadFile(filepath.Join(filepath.Dir(shimaProfile()), "source"))
	return Item{
		ID: "iris", Category: "barstyles", Name: "Shima",
		Summary:     "iNiR desktop by snowarch",
		Description: "The iRiS, Material ii and Waffle panels, settings, widgets and animations, integrated with Ryoku wallpaper and authentication services.",
		Author:      "snowarch", Upstream: "https://github.com/snowarch/iNiR",
		Version: "2.33.0", Installed: installed,
		InstalledVersion: func() string {
			if installed {
				return "2.33.0"
			}
			return ""
		}(),
		UpdateAvailable:       installed && ownedErr == nil && version != "" && strings.TrimSpace(string(current)) != version,
		Tags:                  []string{"desktop", "island", "dock"},
		RequiredWindowManager: "niri", RequiredPackageManagers: []string{"nix"},
		Metadata: map[string]any{"scene": "Scene.qml", "core": installed && ownedErr != nil, "resourceTier": "heavy", "managedRuntime": true, "runtimeRevision": version},
	}
}

func installShima(ctx context.Context) error {
	ref := os.Getenv("RYOKU_SHIMA_FLAKE")
	if !filepath.IsAbs(ref) || !strings.HasPrefix(ref, "/nix/store/") {
		return fmt.Errorf("Shima installation requires the NixOS RyoStore package")
	}
	profile := shimaProfile()
	unlock, err := lockTree(profile)
	if err != nil {
		return err
	}
	defer unlock()
	// Nix owns the profile generations and GC roots. Build first so an interrupted
	// download or failed build leaves the running generation intact.
	dir, err := os.MkdirTemp(filepath.Dir(profile), ".build-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(dir)
	reportProgress(ctx, "download", 0, 0)
	candidate := filepath.Join(dir, "result")
	cmd := exec.CommandContext(ctx, "nix", "build", "--no-update-lock-file", "--out-link", candidate, "path:"+ref+"#default")
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("build Shima: %w", err)
	}
	output, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		return err
	}
	binary := filepath.Join(output, "bin", "ryoku-shima")
	if info, err := os.Stat(binary); err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0111 == 0 {
		return fmt.Errorf("Shima build has no executable runtime")
	}
	reportProgress(ctx, "install", 0, 0)
	cmd = exec.CommandContext(ctx, "nix-env", "--profile", profile, "--set", output)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("activate Shima package: %w", err)
	}
	if err := atomicWrite(filepath.Join(filepath.Dir(profile), "source"), []byte(filepath.Base(ref)+"\n"), 0600); err != nil {
		return err
	}
	return writeStoreRevision(StoreRevision{Category: "barstyles", ID: "iris", Version: "2.33.0", Operation: "install"})
}

func removeShima(ctx context.Context) error {
	profile := shimaProfile()
	unlock, err := lockTree(profile)
	if err != nil {
		return err
	}
	defer unlock()
	if _, err := os.Lstat(profile); os.IsNotExist(err) {
		return fmt.Errorf("Shima is not owned by RyoStore; remove its declarative package instead")
	} else if err != nil {
		return err
	}
	selection, _ := selectionFor("barstyles")
	token := "shima-remove"
	if err := selection.applyFallback("iris", token); err != nil {
		return err
	}
	// Only this dedicated profile is touched. Persistent Shima settings survive
	// removal, and another selection made during removal is preserved.
	entries, err := os.ReadDir(filepath.Dir(profile))
	if err != nil {
		_ = selection.finishFallback("iris", token, false)
		return err
	}
	for _, entry := range entries {
		name := entry.Name()
		if name == "profile" || (strings.HasPrefix(name, "profile-") && strings.HasSuffix(name, "-link")) || name == "source" {
			if err := os.Remove(filepath.Join(filepath.Dir(profile), name)); err != nil && !os.IsNotExist(err) {
				return err
			}
		}
	}
	if err := selection.finishFallback("iris", token, true); err != nil {
		return err
	}
	return writeStoreRevision(StoreRevision{Category: "barstyles", ID: "iris", Version: "2.33.0", Operation: "remove"})
}
