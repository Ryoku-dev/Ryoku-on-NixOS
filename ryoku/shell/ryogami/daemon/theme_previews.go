package main

import (
	"context"
	"encoding/json"
	"os/exec"
)

func themePreviews() map[string]interface{} {
	ctx, cancel := context.WithTimeout(context.Background(), previewCommandTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "ryoku-shell", "theme", "catalog").Output()
	previews := []map[string]interface{}{}
	if err == nil {
		var cards []struct {
			ID      string   `json:"id"`
			Label   string   `json:"label"`
			Dynamic bool     `json:"dynamic"`
			Sw      []string `json:"sw"`
		}
		if json.Unmarshal(out, &cards) == nil {
			for _, c := range cards {
				if c.Dynamic { // the follow-wallpaper variants have no fixed palette to audition
					continue
				}
				nine := nineFromSw(c.Sw)
				if nine == nil {
					continue
				}
				previews = append(previews, map[string]interface{}{
					"backend": "ryoku",
					"key":     "theme.staticTheme",
					"value":   c.ID,
					"label":   c.Label,
					"palette": nine,
				})
			}
		}
	}
	return map[string]interface{}{
		"backend":  "ryoku",
		"backends": []string{"ryoku"},
		"previews": previews,
	}
}
