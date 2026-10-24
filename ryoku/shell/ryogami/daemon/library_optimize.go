package main

import (
	"fmt"
	"path/filepath"
	"strings"
)

func init() {
	registerAfterScan(autoOptimizeNewImages)
	registerAction("OptimizeImages", actionOptimizeImages)
}

func autoOptimizeNewImages(d *daemon, added []Entry) {
	if !d.settingBool("performance.autoOptimizeImages") || d.optimizer == nil {
		return
	}
	files := optimizableImages(added)
	if len(files) == 0 {
		return
	}
	// Only the arrivals: re-encoding the rest of the library is the explicit Optimise action.
	_ = d.optimizer.Start(kindOptimize,
		d.settingString("performance.imageOptimizePreset"),
		d.settingString("performance.imageOptimizeResolution"), files)
}

func optimizableImages(added []Entry) []string {
	var files []string
	for _, e := range added {
		if e.Type != "static" || e.Path == "" {
			continue
		}
		ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(e.Path), "."))
		for _, x := range imageOptimizeExts {
			if ext == x {
				files = append(files, e.Path)
				break
			}
		}
	}
	return files
}

func actionOptimizeImages(d *daemon, args map[string]interface{}) (interface{}, error) {
	if d.optimizer == nil {
		return nil, fmt.Errorf("optimiser unavailable")
	}
	preset := strParam(args, "preset", d.settingString("performance.imageOptimizePreset"))
	res := strParam(args, "resolution", d.settingString("performance.imageOptimizeResolution"))
	if err := d.optimizer.Start(kindOptimize, preset, res, nil); err != nil {
		return nil, err
	}
	return map[string]interface{}{"started": true}, nil
}
