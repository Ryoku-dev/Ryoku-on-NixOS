package main

import (
	"strings"
)

type paperSandPolicy struct {
	Quality string  `json:"quality,omitempty"`
	Scope   string  `json:"scope,omitempty"`
	Primary string  `json:"primary,omitempty"`
	Sharp   *bool   `json:"sharp,omitempty"`
	Fps     *uint32 `json:"fps,omitempty"`
}

type paperScenePolicyFull struct {
	Fps              *uint32 `json:"fps,omitempty"`
	DisableParticles *bool   `json:"disable_particles,omitempty"`
	AssetsDir        string  `json:"assets_dir,omitempty"`
	MaxDimension     *uint32 `json:"max_dimension,omitempty"`
	Clamp            string  `json:"clamp,omitempty"`
}

type paperRendererPolicy struct {
	LoadTimeoutMs      *uint64               `json:"load_timeout_ms,omitempty"`
	IdleSeconds        *uint32               `json:"idle_seconds,omitempty"`
	TransitionsEnabled *bool                 `json:"transitions_enabled,omitempty"`
	TransitionFps      *uint16               `json:"transition_fps,omitempty"`
	Sand               *paperSandPolicy      `json:"sand,omitempty"`
	Scene              *paperScenePolicyFull `json:"scene,omitempty"`
}

func paperFill(fit string) string {
	switch fit {
	case "Cover":
		return "fill"
	case "Contain", "ScaleDown":
		return "fit"
	case "Fill":
		return "stretch"
	case "Center":
		return "center"
	case "Tile":
		return "tile"
	}
	return "fill"
}

func (d *daemon) weSceneFillMode() string {
	switch s := d.settingString("weRender.scaling"); s {
	case "fill", "fit", "stretch", "center", "tile", "span":
		return s
	default:
		return paperFill(contentFit())
	}
}

func (d *daemon) weClampMode() string {
	switch c := d.settingString("weRender.clamp"); c {
	case "clamp", "border", "repeat":
		return c
	}
	return "clamp"
}

func (d *daemon) batterySaverActive() bool {
	return powerOnBattery() && d.settingBool("performance.batterySaver")
}

func (d *daemon) effectivePerformanceMode() bool {
	if d.settingBool("paper.performanceMode") {
		return true
	}
	return d.batterySaverActive() && d.settingBool("performance.batteryWallpaperPerformance")
}

func (d *daemon) effectiveIdleSeconds() int {
	idle := int(d.settingNumber("paper.idlePauseSeconds"))
	if d.batterySaverActive() {
		if b := int(d.settingNumber("performance.batteryVideoIdleSeconds")); b > 0 && (idle == 0 || b < idle) {
			idle = b
		}
	}
	if idle < 0 {
		idle = 0
	}
	return idle
}

func (d *daemon) buildRendererPolicy() *paperRendererPolicy {
	rp := &paperRendererPolicy{}
	if lt := d.settingNumber("paper.loadTimeoutSeconds"); lt >= 3 {
		ms := uint64(lt * 1000)
		if ms > 60000 {
			ms = 60000
		}
		rp.LoadTimeoutMs = &ms
	}
	if idle := d.effectiveIdleSeconds(); idle > 0 {
		u := uint32(idle)
		rp.IdleSeconds = &u
	}
	perf := d.effectivePerformanceMode()
	transEnabled := d.settingBool("transition.enabled") && !perf
	rp.TransitionsEnabled = &transEnabled
	if tf := int(d.settingNumber("transition.fps")); tf >= 1 && tf <= 1000 {
		u := uint16(tf)
		rp.TransitionFps = &u
	}
	rp.Sand = d.buildSandPolicy()
	rp.Scene = d.buildScenePolicy(perf)
	return rp
}

func (d *daemon) buildSandPolicy() *paperSandPolicy {
	sp := &paperSandPolicy{}
	set := false
	if q := d.settingString("transition.sandQuality"); q == "auto" || q == "full" || q == "low" {
		sp.Quality, set = q, true
	}
	if sc := d.settingString("transition.sandScope"); sc == "all" || sc == "primary" {
		sp.Scope, set = sc, true
	}
	if p := d.settingString("transition.sandPrimary"); p != "" {
		sp.Primary, set = p, true
	}
	if d.settingBool("transition.sandSharp") {
		t := true
		sp.Sharp, set = &t, true
	}
	if f := int(d.settingNumber("transition.sandFps")); f >= 1 && f <= 1000 {
		u := uint32(f)
		sp.Fps, set = &u, true
	}
	if !set {
		return nil
	}
	return sp
}

func (d *daemon) buildScenePolicy(perf bool) *paperScenePolicyFull {
	sc := &paperScenePolicyFull{}
	fps := int(d.settingNumber("weRender.fps"))
	if fps < 1 {
		fps = 30
	}
	if fps > 240 {
		fps = 240
	}
	if perf && fps > 30 {
		fps = 30
	}
	u := uint32(fps)
	sc.Fps = &u
	dp := d.settingBool("weRender.disableParticles")
	sc.DisableParticles = &dp
	sc.Clamp = d.weClampMode()
	sc.AssetsDir = d.workshop.weAssetsDir()
	if perf {
		md := uint32(2048)
		sc.MaxDimension = &md
	}
	return sc
}

func (d *daemon) paperServeEnv() []string {
	env := []string{}
	if dev := configuredGpuDevice(d.settingString("performance.gpuDevice")); dev != "auto" {
		env = append(env, "SKWD_VK_DEVICE="+dev)
	}
	return env
}

func configuredGpuDevice(raw string) string {
	v := strings.TrimSpace(raw)
	if rest, ok := strings.CutPrefix(v, "uuid:"); ok {
		hex := strings.ToLower(rest)
		if len(hex) == 32 && isHexDigits(hex) {
			return "uuid:" + hex
		}
	}
	return "auto"
}

func isHexDigits(s string) bool {
	for _, c := range s {
		switch {
		case c >= '0' && c <= '9', c >= 'a' && c <= 'f':
		default:
			return false
		}
	}
	return len(s) > 0
}
