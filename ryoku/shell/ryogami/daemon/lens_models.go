package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func init() {
	registerAction("ImportSemanticModel", actionImportSemanticModel)
	registerAction("AddSemanticModel", actionAddSemanticModel)
	registerAction("RemoveSemanticModel", actionRemoveSemanticModel)
	registerAction("DeleteSemanticModel", actionDeleteSemanticModel)
	registerAction("DeleteActiveSemanticModel", actionDeleteActiveSemanticModel)
}

func runLensJSON(helper string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, helper, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, lensError(stderr.Bytes(), err)
	}
	return stdout.Bytes(), nil
}

func lensError(stderr []byte, fallback error) error {
	var report struct {
		Error struct {
			Message string `json:"message"`
			Hint    string `json:"hint"`
		} `json:"error"`
	}
	if json.Unmarshal(stderr, &report) == nil && report.Error.Message != "" {
		if report.Error.Hint != "" {
			return fmt.Errorf("%s (%s)", report.Error.Message, report.Error.Hint)
		}
		return errors.New(report.Error.Message)
	}
	if msg := strings.TrimSpace(string(stderr)); msg != "" {
		return errors.New(msg)
	}
	return fallback
}

func actionImportSemanticModel(d *daemon, args map[string]interface{}) (interface{}, error) {
	source := strings.TrimSpace(strParam(args, "path", ""))
	if source == "" {
		source = strings.TrimSpace(strParam(args, "source", ""))
	}
	if source == "" {
		return nil, errors.New("choose a model pack to import")
	}
	helper := lensHelper()
	if helper == "" {
		return nil, errors.New("skwd-lens is not installed")
	}
	rt := lensRuntime(d.lensManifest())
	if rt == "" {
		return nil, errors.New("the semantic ONNX runtime is not installed")
	}
	models := lensModelsDir()
	if err := os.MkdirAll(models, 0o755); err != nil {
		return nil, fmt.Errorf("prepare model library: %w", err)
	}
	out, err := runLensJSON(helper,
		"--install-pack", source,
		"--models-dir", models,
		"--runtime", rt,
	)
	if err != nil {
		return nil, err
	}
	var report struct {
		ID         string `json:"id"`
		Version    string `json:"version"`
		Dimensions int    `json:"dimensions"`
		Manifest   string `json:"manifest"`
		Bytes      uint64 `json:"bytes"`
	}
	if json.Unmarshal(out, &report) != nil || report.Manifest == "" {
		return nil, errors.New("could not read the install report from skwd-lens")
	}
	d.addSemanticModel(map[string]interface{}{
		"name":       report.ID,
		"manifest":   report.Manifest,
		"managed":    true,
		"id":         report.ID,
		"version":    report.Version,
		"dimensions": report.Dimensions,
		"bytes":      report.Bytes,
	})
	if err := d.setSetting("semantic.manifest", report.Manifest); err != nil {
		return nil, err
	}
	return map[string]interface{}{
		"id":         report.ID,
		"version":    report.Version,
		"dimensions": report.Dimensions,
		"manifest":   report.Manifest,
		"bytes":      report.Bytes,
	}, nil
}

func actionAddSemanticModel(d *daemon, args map[string]interface{}) (interface{}, error) {
	path := strings.TrimSpace(strParam(args, "path", ""))
	entry := map[string]interface{}{"name": "", "manifest": ""}
	if path != "" {
		entry = map[string]interface{}{"name": manualModelName(path), "manifest": path}
	}
	list := d.settingList("semantic.models")
	list = append(list, entry)
	if err := d.setSetting("semantic.models", list); err != nil {
		return nil, err
	}
	return map[string]interface{}{"index": len(list) - 1}, nil
}

func manualModelName(path string) string {
	if b, err := os.ReadFile(path); err == nil {
		var m struct {
			ID string `json:"id"`
		}
		if json.Unmarshal(b, &m) == nil && m.ID != "" {
			return m.ID
		}
	}
	if base := filepath.Base(filepath.Dir(path)); base != "" && base != "." && base != string(os.PathSeparator) {
		return base
	}
	return "model"
}

func actionRemoveSemanticModel(d *daemon, args map[string]interface{}) (interface{}, error) {
	idx, ok := actionIndex(args)
	if !ok {
		return nil, errors.New("which model to forget was not given")
	}
	list := d.settingList("semantic.models")
	if idx < 0 || idx >= len(list) {
		return nil, errors.New("that model reference no longer exists")
	}
	kept := append(list[:idx:idx], list[idx+1:]...)
	if err := d.setSetting("semantic.models", kept); err != nil {
		return nil, err
	}
	d.reconcileSelectedModel()
	return map[string]interface{}{"removed": true}, nil
}

func actionDeleteActiveSemanticModel(d *daemon, _ map[string]interface{}) (interface{}, error) {
	return d.deleteSemanticModel(-1)
}

func actionDeleteSemanticModel(d *daemon, args map[string]interface{}) (interface{}, error) {
	idx, ok := actionIndex(args)
	if !ok {
		return nil, errors.New("which model to delete was not given")
	}
	return d.deleteSemanticModel(idx)
}

func actionIndex(args map[string]interface{}) (int, bool) {
	switch v := args["index"].(type) {
	case float64:
		return int(v), true
	case int:
		return v, true
	}
	return 0, false
}

func (d *daemon) addSemanticModel(entry map[string]interface{}) {
	manifest, _ := entry["manifest"].(string)
	list := d.settingList("semantic.models")
	for _, it := range list {
		if m, ok := it.(map[string]interface{}); ok {
			if s, _ := m["manifest"].(string); s != "" && s == manifest {
				return
			}
		}
	}
	list = append(list, entry)
	_ = d.setSetting("semantic.models", list)
}

func (d *daemon) reconcileSelectedModel() {
	selected := strings.TrimSpace(d.settingString("semantic.manifest"))
	if selected == "" {
		return
	}
	for _, it := range d.settingList("semantic.models") {
		if m, ok := it.(map[string]interface{}); ok {
			if s, _ := m["manifest"].(string); s == selected {
				return
			}
		}
	}
	_ = d.setSetting("semantic.manifest", "")
}

func (d *daemon) deleteSemanticModel(index int) (interface{}, error) {
	helper := lensHelper()
	if helper == "" {
		return nil, errors.New("skwd-lens is not installed")
	}
	list := d.settingList("semantic.models")
	selected := strings.TrimSpace(d.settingString("semantic.manifest"))

	var manifest string
	if index < 0 {
		manifest = selected
		if manifest == "" {
			manifest = d.lensManifest()
		}
	} else if index < len(list) {
		if m, ok := list[index].(map[string]interface{}); ok {
			manifest, _ = m["manifest"].(string)
		}
	} else {
		return nil, errors.New("that model no longer exists")
	}
	manifest = strings.TrimSpace(manifest)
	if manifest == "" {
		return nil, errors.New("that model has no manifest to delete")
	}

	managedID := ""
	for _, it := range list {
		m, ok := it.(map[string]interface{})
		if !ok {
			continue
		}
		if s, _ := m["manifest"].(string); s != manifest {
			continue
		}
		if managed, _ := m["managed"].(bool); managed {
			managedID, _ = m["id"].(string)
		}
	}

	if err := deleteModelFiles(helper, manifest, managedID); err != nil {
		return nil, err
	}

	kept := make([]interface{}, 0, len(list))
	for _, it := range list {
		if m, ok := it.(map[string]interface{}); ok {
			if s, _ := m["manifest"].(string); s == manifest {
				continue
			}
		}
		kept = append(kept, it)
	}
	_ = d.setSetting("semantic.models", kept)
	if index < 0 || selected == manifest {
		_ = d.setSetting("semantic.enabled", false)
		_ = d.setSetting("semantic.manifest", "")
	}
	return map[string]interface{}{"deleted": true, "manifest": manifest}, nil
}

func deleteModelFiles(helper, manifest, managedID string) error {
	if managedID != "" {
		return removeManagedPack(helper, lensModelsDir(), manifest, managedID)
	}
	out, err := runLensJSON(helper, "--remove-manifest", manifest)
	if err != nil {
		return err
	}
	return confirmRemoval(out)
}

// Refuses anything outside the model library so a stray path cannot delete arbitrary files.
func removeManagedPack(helper, modelsDir, manifest, id string) error {
	component, err := managedPackComponent(modelsDir, manifest)
	if err != nil {
		return err
	}
	out, err := runLensJSON(helper,
		"--remove-pack", id,
		"--models-dir", modelsDir,
		"--pack-component", component,
		"--allow-active",
	)
	if err != nil {
		return err
	}
	return confirmRemoval(out)
}

func managedPackComponent(modelsDir, manifest string) (string, error) {
	if filepath.Base(manifest) != "semantic-pack.json" {
		return "", errors.New("only models imported into the model library can be deleted")
	}
	modelsAbs, err := lensCanonPath(modelsDir)
	if err != nil {
		return "", err
	}
	rootAbs, err := lensCanonPath(filepath.Dir(manifest))
	if err != nil {
		return "", err
	}
	if filepath.Dir(rootAbs) != modelsAbs {
		return "", errors.New("only models imported into the model library can be deleted")
	}
	return filepath.Base(rootAbs), nil
}

func confirmRemoval(out []byte) error {
	var report struct {
		Removed bool `json:"removed"`
	}
	if json.Unmarshal(out, &report) != nil || !report.Removed {
		return errors.New("skwd-lens did not confirm the removal")
	}
	return nil
}

// Symlinks resolve first so a link cannot slip past the containment check.
func lensCanonPath(p string) (string, error) {
	if r, err := filepath.EvalSymlinks(p); err == nil {
		return r, nil
	}
	return filepath.Abs(p)
}
