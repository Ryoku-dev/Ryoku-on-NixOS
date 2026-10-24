package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestBarUpdateUsesRefreshedRegistry(t *testing.T) {
	for _, key := range []string{"XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"} {
		t.Setenv(key, t.TempDir())
	}
	previous := barStyleShellPatch
	barStyleShellPatch = func(string) error { return nil }
	defer func() { barStyleShellPatch = previous }()
	root := t.TempDir()
	write := func(name string, data []byte) {
		p := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	publish := func(version string) {
		entry, _ := productManifestContract()
		entry.ID, entry.Path, entry.Version = "nacre", "barstyles/nacre", version
		scene := []byte("import QtQuick\nItem { property string version: \"" + version + "\" }\n")
		manifest := ProductManifest{Schema: 1, ID: entry.ID, Category: "barstyles", Version: version, Destination: "ryoku/barstyles/nacre",
			Files: []ProductFile{{Source: "Scene.qml", Destination: "Scene.qml", Mode: "0644", Size: int64(len(scene)), SHA256: fmt.Sprintf("%x", sha256.Sum256(scene)), Install: true}}}
		raw, _ := json.Marshal(manifest)
		entry.ManifestSHA256 = fmt.Sprintf("%x", sha256.Sum256(raw))
		registry, _ := json.Marshal(map[string]any{"schema": 1, "barstyles": []ProductEntry{entry}})
		write(entry.Path+"/manifest.json", raw)
		write(entry.Path+"/Scene.qml", scene)
		write("barstyles/registry.json", registry)
	}
	cache := &Cache{base: "file://" + root, dir: t.TempDir(), memo: map[string]memoEntry{}, client: http.DefaultClient}
	provider := newBarProvider(cache)
	publish("1.0.1")
	if err := provider.Install(context.Background(), "nacre"); err != nil {
		t.Fatal(err)
	}
	publish("1.0.2")
	if err := provider.Install(context.Background(), "nacre"); err != nil {
		t.Fatal(err)
	}
	receipt, err := readReceipt("barstyles", "nacre")
	if err != nil {
		t.Fatal(err)
	}
	if receipt.Version != "1.0.2" {
		t.Fatalf("installed %s", receipt.Version)
	}
	items, _, err := provider.Load(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if item := barStyleByID(items, "nacre"); item == nil || item.UpdateAvailable {
		t.Fatalf("update remains available: %+v", item)
	}
}
