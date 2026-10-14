package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestSavedSnapCurveAcrossPresets(t *testing.T) {
	lua, err := exec.LookPath("lua")
	if err != nil {
		t.Skip("lua is required to exercise the shipped preset loader")
	}
	root, err := filepath.Abs("../../hyprland")
	if err != nil {
		t.Fatal(err)
	}
	presets, err := filepath.Glob(filepath.Join(root, "modules/animations/*.lua"))
	if err != nil || len(presets) == 0 {
		t.Fatalf("find animation presets: %v", err)
	}
	for _, preset := range presets {
		name := strings.TrimSuffix(filepath.Base(preset), ".lua")
		t.Run(name, func(t *testing.T) {
			config := t.TempDir()
			if err := os.Symlink(root, filepath.Join(config, "hypr")); err != nil {
				t.Fatal(err)
			}
			if err := os.Mkdir(filepath.Join(config, "ryoku"), 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(config, "ryoku/anim-preset"), []byte(name), 0600); err != nil {
				t.Fatal(err)
			}
			o := defaultOverrides()
			o.Anim.Items = []AnimItem{{Leaf: "windows", Enabled: true, Speed: 3, Bezier: "snap", Style: "popin 80%"}}
			cmd := exec.Command(lua, "-")
			cmd.Env = append(os.Environ(), "XDG_CONFIG_HOME="+config, "LUA_PATH="+root+"/?.lua;;")
			cmd.Stdin = strings.NewReader(`
local curves = { default = true, linear = true }
hl = {
    config = function() end,
    curve = function(name, curve) curves[name] = curve end,
    animation = function(item)
        assert(item.bezier == nil or curves[item.bezier], "no such bezier: " .. tostring(item.bezier))
    end,
}
require("modules.animations")
` + genAnimBlock(o) + `
local custom = { type = "bezier", points = { { 0.2, 0.8 }, { 0.3, 1 } } }
hl.curve("snap", custom)
assert(curves.snap == custom, "user curve must win")
`)
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("load preset with saved snap override: %v\n%s", err, out)
			}
		})
	}
}

func TestScrollingLayoutWorkspaceAnimationAcrossPresets(t *testing.T) {
	lua, err := exec.LookPath("lua")
	if err != nil {
		t.Skip("lua is required to exercise the shipped preset loader")
	}
	root, err := filepath.Abs("../../hyprland")
	if err != nil {
		t.Fatal(err)
	}
	presets, err := filepath.Glob(filepath.Join(root, "modules/animations/*.lua"))
	if err != nil || len(presets) == 0 {
		t.Fatalf("find animation presets: %v", err)
	}
	for _, preset := range presets {
		name := strings.TrimSuffix(filepath.Base(preset), ".lua")
		for _, layout := range []string{"scrolling", "dwindle", "master"} {
			t.Run(name+"/"+layout, func(t *testing.T) {
				config := t.TempDir()
				if err := os.Symlink(root, filepath.Join(config, "hypr")); err != nil {
					t.Fatal(err)
				}
				if err := os.Mkdir(filepath.Join(config, "ryoku"), 0700); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(config, "ryoku/anim-preset"), []byte(name), 0600); err != nil {
					t.Fatal(err)
				}
				o := defaultOverrides()
				o.Appearance.Layout = layout
				cmd := exec.Command(lua, "-")
				cmd.Env = append(os.Environ(), "XDG_CONFIG_HOME="+config, "LUA_PATH="+root+"/?.lua;;")
				cmd.Stdin = strings.NewReader(`
local workspace
hl = {
    config = function() end,
    curve = function() end,
    animation = function(item)
        if item.leaf == "workspaces" then workspace = item end
    end,
}
require("modules.animations")
local presetStyle = workspace and workspace.style or nil
` + genLayoutWorkspaceAnimation(o) + `
local layout = ` + luaStr(layout) + `
if layout == "scrolling" then
    assert(workspace and workspace.style == "fade", "scrolling workspace style must be fade")
    hl.animation({ leaf = "workspaces", enabled = true, speed = 1, bezier = "linear", style = "slide" })
    assert(workspace.style == "slide", "a later user.lua animation must win")
else
    assert((workspace and workspace.style or nil) == presetStyle, layout .. " must keep the preset style")
end
`)
				if out, err := cmd.CombinedOutput(); err != nil {
					t.Fatalf("load %s preset with %s layout: %v\n%s", name, layout, err, out)
				}
			})
		}
	}
}

func TestScrollingLayoutGuardFollowsLeafOverrides(t *testing.T) {
	o := defaultOverrides()
	o.Appearance.Layout = "scrolling"
	o.Anim.Items = []AnimItem{{
		Leaf: "workspaces", Enabled: false, Speed: 9, Bezier: "quick", Style: "slidefade 40%",
	}}
	for name, config := range map[string]string{
		"saved config": genLua(o, false),
		"live preview": liveLua(o),
	} {
		t.Run(name, func(t *testing.T) {
			custom := `hl.animation({ leaf = "workspaces", enabled = false, speed = 9.0, bezier = "quick", style = "slidefade 40%" })`
			guard := `hl.animation({ leaf = "workspaces", enabled = false, speed = 9.0, bezier = "quick", style = "fade" })`
			if customAt, guardAt := strings.Index(config, custom), strings.LastIndex(config, guard); customAt < 0 || guardAt <= customAt {
				t.Fatalf("scrolling fade must follow the per-leaf override:\n%s", config)
			}
		})
	}
	for _, layout := range []string{"dwindle", "master"} {
		o.Appearance.Layout = layout
		if got := genLayoutWorkspaceAnimation(o); got != "" {
			t.Fatalf("%s emitted a workspace animation guard: %s", layout, got)
		}
	}
}
