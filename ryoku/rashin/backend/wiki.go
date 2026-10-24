package main

import (
	"os"
	"path/filepath"
	"strings"
)

// The wiki is the plain-language guide set for someone new to Linux, Ryoku,
// its compositors, Quickshell QML and the Go tools. It ships with Rashin
// (ryoku/rashin/wiki in the repo) and is mirrored into the vault as `wiki/`
// on every EnsureVault, so the Needle can read and cite it, prowl indexes it
// with the rest of the vault, the console renders it, and an update that
// rewrites a page reaches every box. The mirror is read only by contract:
// a page edited in place is overwritten on the next run.

// wikiRoots is the resolution order for the shipped wiki dir: an explicit
// override, the packaged tree, then the dev checkout the last deploy
// recorded; the same order the `ryoku` skill resolves by.
func wikiRoots() []string {
	var roots []string
	if v := os.Getenv("RYOKU_RASHIN_WIKI"); v != "" {
		roots = append(roots, v)
	}
	roots = append(roots, "/usr/share/ryoku/rashin/wiki")
	if repo := recordedCheckout(); repo != "" {
		roots = append(roots, filepath.Join(repo, "ryoku", "rashin", "wiki"))
	}
	return roots
}

// wikiSourceDir returns the first root that carries the index page, or "".
func wikiSourceDir() string {
	for _, d := range wikiRoots() {
		if fileExists(filepath.Join(d, "README.md")) {
			return d
		}
	}
	return ""
}

// syncWiki mirrors the shipped pages into vault/wiki, replacing changed pages
// and dropping pages that no longer ship so a renamed guide leaves no ghost.
// Without a shipped wiki it leaves whatever is there alone and reports no
// error: a box that predates the wiki is not broken, it is just older.
func syncWiki(vault string) error {
	src := wikiSourceDir()
	if src == "" {
		return nil
	}
	dst := filepath.Join(vault, "wiki")
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	shipped := map[string]bool{}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(src, e.Name()))
		if err != nil {
			return err
		}
		shipped[e.Name()] = true
		target := filepath.Join(dst, e.Name())
		if cur, err := os.ReadFile(target); err == nil && string(cur) == string(b) {
			continue
		}
		if err := atomicWrite(target, b, 0o644); err != nil {
			return err
		}
	}
	have, err := os.ReadDir(dst)
	if err != nil {
		return err
	}
	for _, e := range have {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".md") && !shipped[e.Name()] {
			if err := os.Remove(filepath.Join(dst, e.Name())); err != nil {
				return err
			}
		}
	}
	return nil
}

// isWikiPage reports whether a vault-relative path is a mirrored wiki page,
// which the tree marks generated like the maps: read it, never edit it.
func isWikiPage(rel string) bool {
	return strings.HasPrefix(rel, "wiki/") && strings.HasSuffix(rel, ".md")
}
