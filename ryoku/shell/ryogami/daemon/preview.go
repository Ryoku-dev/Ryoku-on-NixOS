package main

import (
	"fmt"
	"os"
)

// The wall preview: the picker paints a still it has not committed, so the
// desktop itself is the preview surface. A preview is a paint, never an
// apply: it records nothing (no assignment, no apply count, no applied
// event), and the frame entries it publishes carry the preview flag so
// downstream readers do not mistake the paint for the committed wallpaper.
// Clearing a preview repaints the committed wallpaper; a committed apply
// supersedes the preview outright.

// previewState is the daemon's one live preview: the outputs it covers (as
// given; empty means every output), the still it paints, and the wallpaper
// name that was current when the preview began, which the clear restores.
type previewState struct {
	outputs  []string
	path     string
	prevName string
}

func mergePreviewOutputs(current, next []string, fresh bool) []string {
	if len(next) == 0 || contains(next, "*") || (!fresh && len(current) == 0) {
		return nil
	}
	merged := make([]string, 0, len(current)+len(next))
	seen := make(map[string]bool, len(current)+len(next))
	if !fresh {
		for _, output := range current {
			if output != "" && !seen[output] {
				merged = append(merged, output)
				seen[output] = true
			}
		}
	}
	for _, output := range next {
		if output != "" && !seen[output] {
			merged = append(merged, output)
			seen[output] = true
		}
	}
	return merged
}

func (d *daemon) previewWallpaper(path string, outputs []string) error {
	if path == "" {
		return fmt.Errorf("missing 'path' parameter")
	}
	if _, err := os.Stat(path); err != nil {
		return fmt.Errorf("wallpaper not readable: %v", err)
	}
	// Stills only: the picker's affordance already withholds video, and a
	// Wallpaper Engine scene has no still to paint.
	if typeOf(path) != "static" {
		return fmt.Errorf("unsupported type for preview: %s", typeOf(path))
	}
	d.previewMu.Lock()
	defer d.previewMu.Unlock()
	fresh := d.preview == nil
	prevName := ""
	if fresh {
		prevName = d.currentName()
	}
	if err := d.paintWallpaperReason("preview", "static", path, "set", outputs, nil, nil); err != nil {
		return err
	}
	if fresh {
		d.preview = &previewState{prevName: prevName}
	}
	d.preview.outputs = mergePreviewOutputs(d.preview.outputs, outputs, fresh)
	d.preview.path = path
	return nil
}

// previewWallpaperKey previews the catalog entry a key names. The folio
// picker works in store keys rather than paths, so it asks by key; the
// entry's recorded type decides suitability, since a key carries no
// extension for typeOf to read.
func (d *daemon) previewWallpaperKey(key string, outputs []string) error {
	entry, ok := d.store.get(key)
	if !ok {
		return fmt.Errorf("unknown wallpaper: %s", key)
	}
	if entry.Type != "static" {
		return fmt.Errorf("unsupported type for preview: %s", entry.Type)
	}
	return d.previewWallpaper(entry.Path, outputs)
}

// clearPreview ends the live preview, repainting the committed wallpaper on
// every output it covered and restoring the name that was current when it
// began. With no live preview it is a no-op: the picker calls it whenever it
// closes, committed or not.
func (d *daemon) clearPreview() error {
	d.previewMu.Lock()
	defer d.previewMu.Unlock()
	st := d.preview
	if st == nil {
		return nil
	}
	d.preview = nil
	d.repaintCommitted(st.outputs)
	if st.prevName != "" {
		d.setCurrent(st.prevName)
	}
	return nil
}

// repaintCommitted repaints the committed wallpaper on the given outputs,
// resolving each the way startup restore does: the stored state first, with
// the active workspace's assignment overlaid on the outputs it owns. A
// named set repaints exactly those outputs the same way, one by one.
func (d *daemon) repaintCommitted(outputs []string) {
	if len(outputs) == 0 || contains(outputs, "*") {
		d.restoreOutputs()
		if d.workspaces != nil {
			for _, name := range connectedOutputNames() {
				if target, active := d.workspaces.activeTarget(name); active {
					_ = d.applyWorkspaceTarget(target, "init")
				}
			}
		}
		return
	}
	for _, output := range outputs {
		if d.workspaces != nil {
			if target, active := d.workspaces.activeTarget(output); active {
				_ = d.applyWorkspaceTarget(target, "init")
				continue
			}
		}
		d.restoreOutputTargets([]string{output})
	}
}
