package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image/color"
	"image/png"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

type stageEffect string

const (
	stageEffectOff      stageEffect = "off"
	stageEffectDepth    stageEffect = "depth"
	stageEffectParallax stageEffect = "parallax"
	stageEffectSpatial  stageEffect = "spatial"
)

// stageLayer is one entry in a wall's layer stack. layers[0] is always the cut
// subject; every later entry is a picture the user added. The daemon derives the
// identity keys (out, label) from the filesystem on every reconcile and owns the
// three arrangement flags: enabled (on/off), front (in front of / behind the
// widgets) and depth (near..far drift for Parallax, ignored in Depth). That is
// the whole per-layer schema; the v1 look overrides, offsets, animation and
// audio knobs are gone.
type stageLayer struct {
	Out     string  `json:"out"`
	Label   string  `json:"label"`
	Enabled bool    `json:"enabled"`
	Front   bool    `json:"front"`
	Depth   float64 `json:"depth"`
}

// stageWall is a wallpaper's persisted stage: which effect is on and the layer
// stack with its arrangement flags. Per-wall, because a cut belongs to one image
// and the user's arrangement belongs to it.
type stageWall struct {
	Effect stageEffect  `json:"effect"`
	Layers []stageLayer `json:"layers,omitempty"`
}

type stageWalls struct {
	Version int                  `json:"version"`
	Current string               `json:"current"`
	Walls   map[string]stageWall `json:"walls"`
}

type stageIndex struct {
	Source     string `json:"source"`
	Model      string `json:"model,omitempty"`
	Matting    bool   `json:"matting,omitempty"`
	DepthModel string `json:"depthModel,omitempty"`
}

type stageCut struct {
	model   string
	matting bool
}

type stageModels struct {
	Draft    string `json:"draft"`
	Standard string `json:"standard"`
	Fine     string `json:"fine"`
}

type stageTarget struct {
	slot   string
	source string
}

type stageWallFrame struct {
	Effect     stageEffect      `json:"effect"`
	Subject    string           `json:"subject"`
	Background string           `json:"background"`
	Depth      string           `json:"depth"`
	Rev        int64            `json:"rev"`
	Layers     []stageLayer     `json:"layers"`
	Steps      []stageStepFrame `json:"steps"`
}

type stageFrame struct {
	Current string                    `json:"current"`
	Busy    bool                      `json:"busy"`
	Job     *stageJobFrame            `json:"job"`
	Last    *stageJobResult           `json:"last"`
	Walls   map[string]stageWallFrame `json:"walls"`
}

var manualLayerRe = regexp.MustCompile(`^layer-(\d{2,})\.png$`)

func logStage(what string, err error) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "stage: %s: %v\n", what, err)
		return
	}
	fmt.Fprintf(os.Stderr, "stage: %s\n", what)
}

// --- paths -----------------------------------------------------------------

func stageWallsPath() string { return filepath.Join(stateDir(), "ryoku", "stage-walls.json") }
func stageDir() string       { return filepath.Join(os.Getenv("HOME"), "Pictures", "Stage") }

func stageStem(source string) string {
	base := filepath.Base(source)
	return strings.TrimSuffix(base, filepath.Ext(base))
}

func stageWallDir(source string) string    { return filepath.Join(stageDir(), stageStem(source)) }
func stageSubjectOut(source string) string { return filepath.Join(stageWallDir(source), "subject.png") }
func stageBackgroundOut(source string) string {
	return filepath.Join(stageWallDir(source), "background.png")
}
func stageDepthOut(source string) string  { return filepath.Join(stageWallDir(source), "depth.png") }
func stageIndexPath(source string) string { return filepath.Join(stageWallDir(source), ".index.json") }

// --- shared fs helpers -----------------------------------------------------

func fileModTime(p string) int64 {
	if st, err := os.Stat(p); err == nil {
		return st.ModTime().Unix()
	}
	return 0
}

func isDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

// writeJSONFileAtomic writes v as indented JSON via a temp file + rename in the
// same directory, so a crash never leaves a half-written registry or settings.
func writeJSONFileAtomic(path string, v any) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".stage-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Chmod(tmpName, 0o644); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		os.Remove(tmpName)
		return err
	}
	return nil
}

// --- registry --------------------------------------------------------------

func loadStageWalls() stageWalls {
	var w stageWalls
	if b, err := os.ReadFile(stageWallsPath()); err == nil {
		_ = json.Unmarshal(b, &w)
	}
	// Normalize after any read or decode failure so callers can assign into the
	// map without a nil-map panic.
	if w.Walls == nil {
		w.Walls = map[string]stageWall{}
	}
	return w
}

func saveStageWalls(w stageWalls) error {
	if w.Version == 0 {
		w.Version = 3
	}
	if w.Walls == nil {
		w.Walls = map[string]stageWall{}
	}
	return writeJSONFileAtomic(stageWallsPath(), w)
}

func loadStageIndex(source string) stageIndex {
	var idx stageIndex
	if b, err := os.ReadFile(stageIndexPath(source)); err == nil {
		_ = json.Unmarshal(b, &idx)
	}
	return idx
}

// --- settings --------------------------------------------------------------

func validStageCutModel(id string) bool {
	switch id {
	case "u2netp", "silueta", "birefnet-general-lite", "birefnet-general", "birefnet-portrait":
		return true
	}
	return false
}

// Unknown models use the default so stale settings cannot disable cutting.
func stageCutFor(mode stageEffect) stageCut {
	cut := stageCut{model: "u2netp"}
	if mode != stageEffectDepth && mode != stageEffectParallax {
		return cut
	}
	dir := ryokuConfigDir()
	if dir == "" {
		return cut
	}
	b, err := os.ReadFile(filepath.Join(dir, "stage.json"))
	if err != nil {
		return cut
	}
	var m struct {
		Depth struct {
			Cut struct {
				Model   string `json:"model"`
				Matting bool   `json:"matting"`
			} `json:"cut"`
		} `json:"depth"`
		Parallax struct {
			Cut struct {
				Model   string `json:"model"`
				Matting bool   `json:"matting"`
			} `json:"cut"`
		} `json:"parallax"`
	}
	if json.Unmarshal(b, &m) != nil {
		return cut
	}
	selected := m.Depth.Cut
	if mode == stageEffectParallax {
		selected = m.Parallax.Cut
	}
	if validStageCutModel(selected.Model) {
		cut.model = selected.Model
	}
	cut.matting = selected.Matting
	return cut
}

func stageSpatialModel() string {
	id := "small"
	if dir := ryokuConfigDir(); dir != "" {
		b, err := os.ReadFile(filepath.Join(dir, "stage.json"))
		if err == nil {
			var m struct {
				Spatial struct {
					Model string `json:"model"`
				} `json:"spatial"`
			}
			if json.Unmarshal(b, &m) == nil && m.Spatial.Model != "" {
				id = m.Spatial.Model
			}
		}
	}
	switch id {
	case "base", "large":
		return id
	default:
		return "small"
	}
}

// Missing settings keep the depth backdrop enabled.
func stageDepthBackdrop() bool {
	dir := ryokuConfigDir()
	if dir == "" {
		return true
	}
	b, err := os.ReadFile(filepath.Join(dir, "stage.json"))
	if err != nil {
		return true
	}
	var m struct {
		Parallax struct {
			DepthBackdrop *bool `json:"depthBackdrop"`
		} `json:"parallax"`
	}
	if json.Unmarshal(b, &m) != nil || m.Parallax.DepthBackdrop == nil {
		return true
	}
	return *m.Parallax.DepthBackdrop
}

// --- engine ----------------------------------------------------------------

// stageEngineBin resolves the ryostage helper. RYOKU_STAGE_ENGINE is the test /
// out-of-tree seam; a dev run reaches it under RYOKU_SHELL_DIR; otherwise it is
// on PATH once packaged.
func stageEngineBin() string {
	if bin := os.Getenv("RYOKU_STAGE_ENGINE"); bin != "" {
		return bin
	}
	if dir := os.Getenv("RYOKU_SHELL_DIR"); dir != "" {
		p := filepath.Join(dir, "scripts", "ryostage")
		if isFile(p) {
			return p
		}
	}
	return "ryostage"
}

// stageModelsJSON passes the curated catalogue through to the shell.
func stageModelsJSON() string {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, stageEngineBin(), "models", "--json").Output()
	if err != nil {
		return "err stage models: " + err.Error()
	}
	return strings.TrimSpace(string(out))
}

// --- layers ----------------------------------------------------------------

// newSubjectLayer is the always-present layers[0]: the cut subject, in front of
// the widgets, mid drift. It names the subject.png slot even before the cut
// lands, so the stack invariant (layers[0] is the subject) always holds.
func newSubjectLayer(out string) stageLayer {
	return stageLayer{Out: out, Label: "Subject", Enabled: true, Front: true, Depth: 0.5}
}

// manualLayers lists the user-placed layer-NN.png in a wall's folder, ordered,
// each defaulting to on, behind the widgets, mid drift.
func manualLayers(source string) []stageLayer {
	dir := stageWallDir(source)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	type found struct {
		idx   int
		layer stageLayer
	}
	var fs []found
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		m := manualLayerRe.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		var idx int
		_, _ = fmt.Sscanf(m[1], "%d", &idx)
		out := filepath.Join(dir, e.Name())
		fs = append(fs, found{idx, stageLayer{
			Out: out, Label: fmt.Sprintf("Layer %d", idx), Enabled: true, Front: false, Depth: 0.5,
		}})
	}
	sort.Slice(fs, func(i, j int) bool { return fs[i].idx < fs[j].idx })
	out := make([]stageLayer, 0, len(fs))
	for _, f := range fs {
		out = append(out, f.layer)
	}
	return out
}

// nextManualIndex is the next free NN for a wall folder's layer-NN.png files.
func nextManualIndex(dir string) int {
	next := 1
	if entries, err := os.ReadDir(dir); err == nil {
		for _, e := range entries {
			m := manualLayerRe.FindStringSubmatch(e.Name())
			if m == nil {
				continue
			}
			var idx int
			_, _ = fmt.Sscanf(m[1], "%d", &idx)
			if idx >= next {
				next = idx + 1
			}
		}
	}
	return next
}

// deriveLayers rebuilds a wall's layer stack from the filesystem (subject.png
// then the ordered layer-NN.png) and carries the user's arrangement flags
// forward from the previous registry entry, matched by output path. Identity is
// always the truth on disk; the flags are the user's and are never dropped.
func (d *daemon) deriveLayers(source string, prev []stageLayer) []stageLayer {
	next := []stageLayer{newSubjectLayer(stageSubjectOut(source))}
	next = append(next, manualLayers(source)...)
	byOut := map[string]stageLayer{}
	for _, p := range prev {
		byOut[p.Out] = p
	}
	for i := range next {
		if p, ok := byOut[next[i].Out]; ok {
			next[i].Enabled = p.Enabled
			next[i].Front = p.Front
			next[i].Depth = p.Depth
		}
	}
	return next
}

// --- worker ----------------------------------------------------------------

func (d *daemon) scheduleStage() {
	select {
	case d.stageSig <- struct{}{}:
	default:
	}
}

func (d *daemon) stageWorker() {
	for range d.stageSig {
		d.reconcileStage()
	}
}

// stageTargets are the still wallpapers on screen (default + per-output),
// skipping videos and live-claimed slots, each paired with its ryogami slot.
func (d *daemon) stageTargets() []stageTarget {
	f := d.wallFrame()
	var out []stageTarget
	if p := f.Default.Path; p != "" && !f.Default.Live && !f.Default.Video && !isVideo(p) && isFile(p) {
		out = append(out, stageTarget{"", p})
	}
	for name, e := range f.Outputs {
		if e.Path != "" && !e.Live && !e.Video && !isVideo(e.Path) && isFile(e.Path) {
			out = append(out, stageTarget{name, e.Path})
		}
	}
	return out
}

// Passive wakes republish state but never start engine work.
func (d *daemon) reconcileStage() {
	wall := d.currentWall()
	reg := loadStageWalls()
	dirty := reg.Current != wall
	reg.Current = wall
	targets := d.stageTargets()
	desired := map[string]stageTarget{}
	for _, target := range targets {
		entry := reg.Walls[target.source]
		if entry.Effect == stageEffectDepth || entry.Effect == stageEffectParallax {
			before, _ := json.Marshal(entry.Layers)
			entry.Layers = d.deriveLayers(target.source, entry.Layers)
			after, _ := json.Marshal(entry.Layers)
			if !bytes.Equal(before, after) {
				dirty = true
			}
			reg.Walls[target.source] = entry
		}
		if entry.Effect == stageEffectDepth &&
			stageStepUsable(stageStepStateFor(stageStepsForWall(target.source, entry.Effect), stageStepCut)) {
			desired[target.slot] = target
		}
	}
	frame := d.wallFrame()
	clear := frame.Default.Depth != "" && desired[""].source == ""
	for slot, entry := range frame.Outputs {
		if entry.Depth != "" && desired[slot].source == "" {
			clear = true
			break
		}
	}
	if clear {
		d.depthClear()
	}
	for _, target := range desired {
		d.depthPublish(target.slot, target.source, stageSubjectOut(target.source))
	}
	if dirty {
		if err := saveStageWalls(reg); err != nil {
			logStage("save walls", err)
		}
	}
	d.publishStage()
}

// stageDepthSample reads one bilinear depth sample from a wall's depth.png for
// the desktop widget depth-pick (docs/stage.md "Widgets on the depth"). nx/ny
// are output-normalised 0..1 with y down; width/height are the output pixel
// size; fit "Cover" centre-crops the map exactly like DepthMeshGeometry's UVs,
// anything else maps it straight. Returns the 16-bit value normalised 0..1,
// larger nearer.
func stageDepthSample(wall string, nx, ny, width, height float64, fit string) (float64, error) {
	nx = math.Max(0, math.Min(1, nx))
	ny = math.Max(0, math.Min(1, ny))
	raw, err := os.ReadFile(stageDepthOut(wall))
	if err != nil {
		return 0, fmt.Errorf("no depth map for this wallpaper")
	}
	img, err := png.Decode(bytes.NewReader(raw))
	if err != nil {
		return 0, fmt.Errorf("depth png unreadable: %w", err)
	}
	b := img.Bounds()
	if b.Dx() < 2 || b.Dy() < 2 {
		return 0, fmt.Errorf("depth png too small to sample")
	}
	cropU, cropV := 1.0, 1.0
	if fit == "Cover" && width > 0 && height > 0 {
		outAspect := width / height
		srcAspect := float64(b.Dx()) / float64(b.Dy())
		cropU = math.Min(1, outAspect/srcAspect)
		cropV = math.Min(1, srcAspect/outAspect)
	}
	fx := (0.5*(1-cropU) + nx*cropU) * float64(b.Dx()-1)
	fy := (0.5*(1-cropV) + ny*cropV) * float64(b.Dy()-1)
	x0, y0 := int(math.Floor(fx)), int(math.Floor(fy))
	x1, y1 := min(x0+1, b.Dx()-1), min(y0+1, b.Dy()-1)
	tx, ty := fx-float64(x0), fy-float64(y0)
	px := func(x, y int) float64 {
		switch g := img.At(x+b.Min.X, y+b.Min.Y).(type) {
		case color.Gray16:
			return float64(g.Y) / 65535
		case color.Gray:
			return float64(g.Y) / 255
		default:
			r, _, _, _ := g.RGBA()
			return float64(r) / 65535
		}
	}
	top := px(x0, y0)*(1-tx) + px(x1, y0)*tx
	bottom := px(x0, y1)*(1-tx) + px(x1, y1)*tx
	return top*(1-ty) + bottom*ty, nil
}

// stageDepthSampleCall parses the verb's fixed tail and formats the ok value.
func (d *daemon) stageDepthSampleCall(wall, xs, ys, ws, hs, fit string) (string, error) {
	vals := make([]float64, 4)
	for i, s := range []string{xs, ys, ws, hs} {
		v, err := strconv.ParseFloat(s, 64)
		if err != nil {
			return "", fmt.Errorf("%s is not a number", s)
		}
		vals[i] = v
	}
	val, err := stageDepthSample(wall, vals[0], vals[1], vals[2], vals[3], fit)
	if err != nil {
		return "", err
	}
	return strconv.FormatFloat(val, 'f', 4, 64), nil
}

// --- topic -----------------------------------------------------------------

func (d *daemon) buildStageFrame() stageFrame {
	reg := loadStageWalls()
	cur := d.currentWall()
	job, last := d.stageJobSnapshot()
	paths := map[string]bool{}
	if cur != "" {
		paths[cur] = true
	}
	for _, target := range d.stageTargets() {
		paths[target.source] = true
	}
	if job != nil {
		paths[job.Wall] = true
	}
	if last != nil {
		paths[last.Wall] = true
	}
	walls := map[string]stageWallFrame{}
	depthBackdrop := stageDepthBackdrop()
	for path := range paths {
		entry := reg.Walls[path]
		effect := entry.Effect
		if effect == "" {
			effect = stageEffectOff
		}
		steps := stageStepsForWall(path, effect)
		wf := stageWallFrame{
			Effect: effect,
			Layers: []stageLayer{},
			Steps:  steps,
		}
		if effect == stageEffectDepth || effect == stageEffectParallax {
			wf.Layers = d.deriveLayers(path, entry.Layers)
		}
		cutUsable := stageStepUsable(stageStepStateFor(steps, stageStepCut))
		fillReady := stageStepStateFor(steps, stageStepFill) == stageStateReady
		depthUsable := stageStepUsable(stageStepStateFor(steps, stageStepDepth))
		switch effect {
		case stageEffectDepth:
			if cutUsable {
				wf.Subject = stageSubjectOut(path)
			}
		case stageEffectParallax:
			if cutUsable && fillReady {
				wf.Subject = stageSubjectOut(path)
				wf.Background = stageBackgroundOut(path)
				if depthBackdrop && depthUsable {
					wf.Depth = stageDepthOut(path)
				}
			}
		case stageEffectSpatial:
			if depthUsable {
				wf.Depth = stageDepthOut(path)
			}
		}
		for _, artifact := range [3]string{wf.Subject, wf.Background, wf.Depth} {
			if rev := fileModTime(artifact); rev > wf.Rev {
				wf.Rev = rev
			}
		}
		for _, layer := range wf.Layers {
			if rev := fileModTime(layer.Out); rev > wf.Rev {
				wf.Rev = rev
			}
		}
		walls[path] = wf
	}
	return stageFrame{
		Current: cur,
		Busy:    job != nil,
		Job:     job,
		Last:    last,
		Walls:   walls,
	}
}

func (d *daemon) publishStage() {
	t := d.topic("stage")
	if t == nil {
		return
	}
	if b, err := json.Marshal(d.buildStageFrame()); err == nil {
		t.publish(b)
	}
}

func (d *daemon) stageStatusJSON() string {
	b, _ := json.Marshal(d.buildStageFrame())
	return string(b)
}

// --- verbs -----------------------------------------------------------------

// restField recovers a trailing argument that may contain spaces from the raw
// command line, splitting into exactly n fields.
func restField(line string, n int) string {
	parts := strings.SplitN(line, " ", n)
	if len(parts) == n {
		return parts[n-1]
	}
	return ""
}

func splitStageWall(line string) (string, string, bool) {
	parts := strings.SplitN(line, " -- ", 2)
	if len(parts) == 1 {
		return line, "", false
	}
	return parts[0], strings.TrimSpace(parts[1]), true
}

func (d *daemon) stageSetEffect(wall string, effect stageEffect) {
	if wall == "" {
		return
	}
	reg := loadStageWalls()
	entry := reg.Walls[wall]
	entry.Effect = effect
	reg.Walls[wall] = entry
	if err := saveStageWalls(reg); err != nil {
		logStage("set-effect save", err)
	}
	d.scheduleStage()
	d.publishStage()
}

// stageSetLayer applies the three arrangement flags (enabled/front/depth) to one
// layer (0-based, index 0 is the subject). Only those keys are accepted;
// identity (out/label) is the daemon's. The layer stack is re-derived first so a
// set that races an enable still lands on the right slot.
func (d *daemon) stageSetLayer(wall, indexArg, body string) error {
	if wall == "" {
		return fmt.Errorf("no active wallpaper")
	}
	index, err := strconv.Atoi(indexArg)
	if err != nil {
		return fmt.Errorf("bad index: %s", indexArg)
	}
	var patch struct {
		Enabled *bool    `json:"enabled"`
		Front   *bool    `json:"front"`
		Depth   *float64 `json:"depth"`
	}
	if err := json.Unmarshal([]byte(body), &patch); err != nil {
		return err
	}
	reg := loadStageWalls()
	e := reg.Walls[wall]
	e.Layers = d.deriveLayers(wall, e.Layers)
	if index < 0 || index >= len(e.Layers) {
		return fmt.Errorf("layer index out of range: %d", index)
	}
	if patch.Enabled != nil {
		e.Layers[index].Enabled = *patch.Enabled
	}
	if patch.Front != nil {
		e.Layers[index].Front = *patch.Front
	}
	if patch.Depth != nil {
		e.Layers[index].Depth = *patch.Depth
	}
	reg.Walls[wall] = e
	if err := saveStageWalls(reg); err != nil {
		return err
	}
	d.publishStage()
	return nil
}

// stageAddLayer copies a ready PNG into the wall's folder as the next numbered
// manual layer and re-derives; no re-cut of the auto subject.
func (d *daemon) stageAddLayer(wall, src string) (string, error) {
	if wall == "" {
		return "", fmt.Errorf("no active wallpaper")
	}
	if src == "" {
		return "", fmt.Errorf("empty source path")
	}
	st, err := os.Stat(src)
	if err != nil || st.IsDir() {
		return "", fmt.Errorf("source not a file: %s", src)
	}
	dir := stageWallDir(wall)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	dst := filepath.Join(dir, fmt.Sprintf("layer-%02d.png", nextManualIndex(dir)))
	if err := copyFile(src, dst); err != nil {
		return "", err
	}
	d.scheduleStage()
	return dst, nil
}

// stageRemoveLayer deletes a manual layer by its 0-based stack index. Index 0 is
// the subject and can never be removed; the resolved path is guarded to a
// layer-NN.png inside the wall's own folder.
func (d *daemon) stageRemoveLayer(wall, indexArg string) error {
	if wall == "" {
		return fmt.Errorf("no active wallpaper")
	}
	index, err := strconv.Atoi(indexArg)
	if err != nil {
		return fmt.Errorf("bad index: %s", indexArg)
	}
	if index == 0 {
		return fmt.Errorf("cannot remove the subject")
	}
	reg := loadStageWalls()
	e := reg.Walls[wall]
	e.Layers = d.deriveLayers(wall, e.Layers)
	if index < 0 || index >= len(e.Layers) {
		return fmt.Errorf("layer index out of range: %d", index)
	}
	clean := filepath.Clean(e.Layers[index].Out)
	dir := filepath.Clean(stageWallDir(wall))
	if filepath.Dir(clean) != dir || !manualLayerRe.MatchString(filepath.Base(clean)) {
		return fmt.Errorf("not a manual layer: %s", e.Layers[index].Out)
	}
	if err := os.Remove(clean); err != nil {
		return err
	}
	d.scheduleStage()
	return nil
}

// Clearing a cut preserves manual layers and the reusable depth map.
func (d *daemon) stageClear(wall string) {
	if wall == "" {
		return
	}
	d.stageForceCancelWall(wall)
	dir := stageWallDir(wall)
	for _, name := range []string{"subject.png", "background.png", ".index.json"} {
		_ = os.Remove(filepath.Join(dir, name))
	}
	reg := loadStageWalls()
	entry := reg.Walls[wall]
	if entry.Effect == stageEffectDepth || entry.Effect == stageEffectParallax {
		entry.Effect = stageEffectOff
	}
	reg.Walls[wall] = entry
	if err := saveStageWalls(reg); err != nil {
		logStage("clear save", err)
	}
	d.scheduleStage()
	d.publishStage()
}

// --- migration -------------------------------------------------------------

type stageWallV1 struct {
	Effect string           `json:"effect"`
	Mode   string           `json:"mode"`
	Scene  []string         `json:"scene"`
	Layers []map[string]any `json:"layers"`
}

type stageWallsV1 struct {
	Version int                    `json:"version"`
	Current string                 `json:"current"`
	Walls   map[string]stageWallV1 `json:"walls"`
}

func stageMigrationMarker() string {
	return filepath.Join(stateDir(), "ryoku", "migrations", "ryostage-v2-safe-fold")
}

func stageV3MigrationMarker() string {
	return filepath.Join(stateDir(), "ryoku", "migrations", "ryostage-v3-modes")
}

func oldStageMigrationMarker() string {
	return filepath.Join(stateDir(), "ryoku", "migrations", "ryostage-v2")
}

// Write migration markers last so interrupted folds retry safely.
func migrateStage() {
	foldedLegacy := false
	if marker := stageMigrationMarker(); !isFile(marker) {
		folded, err := migrateStageRegistry()
		if err != nil {
			logStage("migrate registry v2", err)
			return
		}
		foldedLegacy = folded
		if err := migrateStageSettings(); err != nil {
			logStage("migrate settings v2", err)
			return
		}
		if err := writeStageMigrationMarker(marker, "ryostage v2 safe fold complete\n"); err != nil {
			logStage("migrate marker v2", err)
			return
		}
	}

	marker := stageV3MigrationMarker()
	if isFile(marker) {
		return
	}
	if err := migrateStageRegistryV3(foldedLegacy); err != nil {
		logStage("migrate registry v3", err)
		return
	}
	if err := migrateStageSettingsV3(); err != nil {
		logStage("migrate settings v3", err)
		return
	}
	if err := writeStageMigrationMarker(marker, "ryostage v3 mode split complete\n"); err != nil {
		logStage("migrate marker v3", err)
	}
}

func writeStageMigrationMarker(path, body string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(body), 0o644)
}

// migrateStageRegistry converges the pre-v1 (retired Depth/Parallax) state and a
// v1 Ryostage registry onto one v2 stage-walls.json. The legacy fold runs first
// for walls the v1 registry has not already claimed -- a stable box that skipped
// v1 gets its whole Depth/Parallax arrangement, while a testing box's own v1
// entries win -- moving artifacts by rename; then every v1-shaped entry is
// normalised to v2. A missing v1 registry (a stable box) is just an empty base.
func migrateStageRegistry() (bool, error) {
	var raw stageWallsV1
	if b, err := os.ReadFile(stageWallsPath()); err == nil {
		if err := json.Unmarshal(b, &raw); err != nil {
			return false, fmt.Errorf("decode %s: %w", stageWallsPath(), err)
		}
		if raw.Version >= 2 {
			return false, nil
		}
	} else if !os.IsNotExist(err) {
		return false, err
	}
	claimed := map[string]bool{}
	for path := range raw.Walls {
		claimed[path] = true
	}
	out := stageWalls{Version: 2, Current: raw.Current, Walls: map[string]stageWall{}}
	migrateLegacyRegistry(&out, claimed)
	for path, w := range raw.Walls {
		out.Walls[path] = foldStageWallV1(path, w)
	}
	return true, writeJSONFileAtomic(stageWallsPath(), out)
}

// Artifact presence disambiguates the old depth wire during migration.
func migrateStageRegistryV3(foldedLegacy bool) error {
	b, err := os.ReadFile(stageWallsPath())
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var raw map[string]any
	if err := json.Unmarshal(b, &raw); err != nil {
		return fmt.Errorf("decode %s: %w", stageWallsPath(), err)
	}
	if stageSettingsVersion(raw) >= 3 {
		return nil
	}
	if walls, ok := raw["walls"].(map[string]any); ok && !foldedLegacy {
		for path, value := range walls {
			wall, ok := value.(map[string]any)
			if !ok || wall["effect"] != string(stageEffectDepth) {
				continue
			}
			switch {
			case isFile(stageDepthOut(path)):
				wall["effect"] = string(stageEffectSpatial)
			case isFile(stageSubjectOut(path)):
				wall["effect"] = string(stageEffectDepth)
			default:
				wall["effect"] = string(stageEffectSpatial)
			}
		}
	}
	raw["version"] = 3
	return writeJSONFileAtomic(stageWallsPath(), raw)
}

// Legacy on-disk formats (retired Depth and Parallax), read once to fold to v2.
type legacyDepthWalls struct {
	Walls map[string]bool `json:"walls"`
}

type legacyParallaxLayer struct {
	Out   string  `json:"out"`
	Rev   int64   `json:"rev"`
	Label string  `json:"label"`
	Depth float32 `json:"depth"`
	Area  float32 `json:"area"`
}

type legacyParallaxWall struct {
	Enabled bool     `json:"enabled"`
	Mode    string   `json:"mode"`
	Scene   []string `json:"scene"`
}

type legacyParallaxWalls struct {
	Walls  map[string]legacyParallaxWall    `json:"walls"`
	Layers map[string][]legacyParallaxLayer `json:"layers"`
}

func legacyDepthWallsPath() string { return filepath.Join(stateDir(), "ryoku", "depth-walls.json") }
func legacyDepthDir() string       { return filepath.Join(os.Getenv("HOME"), "Pictures", "Depth") }
func legacyParallaxDir() string    { return filepath.Join(os.Getenv("HOME"), "Pictures", "Parallax") }
func legacyLayersPath() string     { return filepath.Join(legacyParallaxDir(), "layers.pz") }

func loadLegacyDepthWalls() map[string]bool {
	b, err := os.ReadFile(legacyDepthWallsPath())
	if err != nil {
		return nil
	}
	var dw legacyDepthWalls
	if json.Unmarshal(b, &dw) != nil {
		return nil
	}
	return dw.Walls
}

func loadLegacyParallaxWalls() legacyParallaxWalls {
	var lp legacyParallaxWalls
	if b, err := os.ReadFile(legacyLayersPath()); err == nil {
		_ = json.Unmarshal(b, &lp)
	}
	return lp
}

// migrateLegacyRegistry folds the retired Depth (depth-walls.json + Pictures/
// Depth) and Parallax (layers.pz + Pictures/Parallax) state into v2 entries for
// walls the v1 registry has not claimed, moving each wall's artifacts by rename.
// Parallax is the richer effect and wins a wall enabled in both, so its folders
// move first (creating Stage/<stem>/), then the depth PNGs land beside them.
func migrateLegacyRegistry(out *stageWalls, claimed map[string]bool) {
	depthWalls := loadLegacyDepthWalls()
	lp := loadLegacyParallaxWalls()

	for path, w := range lp.Walls {
		if !w.Enabled || claimed[path] {
			continue
		}
		layers := migrateParallaxFolder(path, w, lp.Layers[path])
		e := out.Walls[path]
		e.Effect = stageEffectParallax
		if len(layers) > 0 {
			e.Layers = layers
		}
		out.Walls[path] = e
	}
	for path, on := range depthWalls {
		if !on || claimed[path] {
			continue
		}
		migrateDepthPNG(path)
		e := out.Walls[path]
		if e.Effect == "" || e.Effect == stageEffectOff {
			e.Effect = stageEffectDepth
		}
		if len(e.Layers) == 0 {
			e.Layers = []stageLayer{newSubjectLayer(stageSubjectOut(path))}
		}
		out.Walls[path] = e
	}
}

// migrateParallaxFolder moves ~/Pictures/Parallax/<stem>/ whole into the Stage
// tree, renames the auto subject (old layer-01.png) to subject.png, and returns
// the wall's v2 layer stack. A layer path follows the move only after the folder
// rename succeeds, after a previous successful move, or when the destination is
// byte-identical; conflicts and failures keep the legacy path.
func migrateParallaxFolder(path string, w legacyParallaxWall, layers []legacyParallaxLayer) []stageLayer {
	stem := stageStem(path)
	src := filepath.Join(legacyParallaxDir(), stem)
	dst := stageWallDir(path)
	moved := false
	if isDir(src) && !isDir(dst) {
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			logStage("migrate parallax mkdir "+stem, err)
		} else if err := os.Rename(src, dst); err != nil {
			logStage("migrate move parallax "+stem, err)
		} else {
			moved = true
		}
	}
	auto := w.Mode == "" || w.Mode == "auto"
	subjectReady := false
	if auto && (moved || (!isDir(src) && isDir(dst))) {
		l1 := filepath.Join(dst, "layer-01.png")
		sp := filepath.Join(dst, "subject.png")
		switch {
		case isFile(l1) && !isFile(sp):
			if err := os.Rename(l1, sp); err != nil {
				logStage("migrate rename subject "+stem, err)
			} else {
				subjectReady = true
			}
		case isFile(sp) && (!isFile(l1) || filesHaveSameContents(l1, sp)):
			subjectReady = true
		}
	}
	front := sceneFront(w.Scene, len(layers))
	v2 := make([]stageLayer, 0, len(layers)+1)
	hasSubject := false
	for i, ol := range layers {
		original := ol.Out
		base := filepath.Base(original)
		if auto && base == "layer-01.png" {
			candidate := filepath.Join(dst, "subject.png")
			if subjectReady || filesHaveSameContents(original, candidate) {
				base = "subject.png"
			}
		}
		candidate := filepath.Join(dst, base)
		out := original
		fromSourceFolder := filepath.Clean(filepath.Dir(original)) == filepath.Clean(src)
		switch {
		case moved && fromSourceFolder && isFile(candidate):
			out = candidate
		case fromSourceFolder && !isFile(original) && isFile(candidate):
			out = candidate
		case isFile(original) && filesHaveSameContents(original, candidate):
			out = candidate
		}
		nl := stageLayer{
			Out:     out,
			Label:   ol.Label,
			Enabled: true,
			Depth:   float64(ol.Depth),
		}
		if base == "subject.png" && out == candidate {
			nl.Label = "Subject"
			hasSubject = true
		} else if nl.Label == "" {
			nl.Label = fmt.Sprintf("Layer %d", i+1)
		}
		if front != nil && i < len(front) {
			nl.Front = front[i]
		}
		if nl.Depth == 0 {
			nl.Depth = 0.5
		}
		v2 = append(v2, nl)
	}
	if !hasSubject {
		v2 = append([]stageLayer{newSubjectLayer(stageSubjectOut(path))}, v2...)
	}
	return v2
}

func filesHaveSameContents(a, b string) bool {
	ai, err := os.Stat(a)
	if err != nil || !ai.Mode().IsRegular() {
		return false
	}
	bi, err := os.Stat(b)
	if err != nil || !bi.Mode().IsRegular() || ai.Size() != bi.Size() {
		return false
	}
	af, err := os.Open(a)
	if err != nil {
		return false
	}
	defer af.Close()
	bf, err := os.Open(b)
	if err != nil {
		return false
	}
	defer bf.Close()
	var ab, bb [32 * 1024]byte
	for {
		an, ae := af.Read(ab[:])
		bn, be := bf.Read(bb[:])
		if an != bn || !bytes.Equal(ab[:an], bb[:bn]) {
			return false
		}
		if ae == io.EOF && be == io.EOF {
			return true
		}
		if ae != nil || be != nil {
			return false
		}
	}
}

// migrateDepthPNG renames ~/Pictures/Depth/<stem>-depth.png to the wall's
// subject.png, unless a subject is already present (a wall enabled in both
// effects keeps the parallax subject).
func migrateDepthPNG(path string) {
	stem := stageStem(path)
	src := filepath.Join(legacyDepthDir(), stem+"-depth.png")
	if !isFile(src) {
		return
	}
	dst := stageSubjectOut(path)
	if isFile(dst) {
		logStage("migrate depth "+stem+": subject already present, left in place", nil)
		return
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		logStage("migrate depth mkdir "+stem, err)
		return
	}
	if err := os.Rename(src, dst); err != nil {
		logStage("migrate move depth "+stem, err)
	}
}

// foldStageWallV1 reduces one v1 wall to the v2 shape.
func foldStageWallV1(path string, w stageWallV1) stageWall {
	eff := stageEffect(w.Effect)
	if w.Effect == "subject" {
		eff = stageEffectDepth
	}
	switch eff {
	case stageEffectDepth, stageEffectParallax:
	default:
		eff = stageEffectOff
	}
	var front []bool
	if len(w.Scene) > 0 {
		front = sceneFront(w.Scene, len(w.Layers))
	}
	layers := make([]stageLayer, 0, len(w.Layers)+1)
	hasSubject := false
	for i, l := range w.Layers {
		nl := stageLayer{
			Out:     asString(l["out"]),
			Label:   asString(l["label"]),
			Enabled: asBool(l["enabled"], true),
			Depth:   layerDepthV1(l),
		}
		if nl.Label == "" {
			nl.Label = fmt.Sprintf("Layer %d", i+1)
		}
		if front != nil {
			nl.Front = front[i]
		} else if b, ok := l["front"].(bool); ok {
			nl.Front = b
		}
		if filepath.Base(nl.Out) == "subject.png" {
			hasSubject = true
		}
		layers = append(layers, nl)
	}
	// A v1 manual wall lists only layer-NN.png; v2 always leads with the subject.
	if !hasSubject && eff != stageEffectOff {
		layers = append([]stageLayer{newSubjectLayer(stageSubjectOut(path))}, layers...)
	}
	return stageWall{Effect: eff, Layers: layers}
}

// sceneFront reduces a v1 scene order (back-to-front tokens: wallpaper, layer:N
// 1-based, widget:*, visualizer) to each layer's front flag: a layer token that
// appears after any widget:* token sits in front of the widgets.
func sceneFront(scene []string, n int) []bool {
	front := make([]bool, n)
	firstWidget := -1
	for i, tok := range scene {
		if strings.HasPrefix(tok, "widget:") {
			firstWidget = i
			break
		}
	}
	if firstWidget < 0 {
		return front
	}
	for i, tok := range scene {
		if i <= firstWidget || !strings.HasPrefix(tok, "layer:") {
			continue
		}
		idx, err := strconv.Atoi(strings.TrimPrefix(tok, "layer:"))
		if err != nil {
			continue
		}
		idx-- // 1-based token -> 0-based layer
		if idx >= 0 && idx < n {
			front[idx] = true
		}
	}
	return front
}

// layerDepthV1 reads a v1 layer's drift knob: the v1 `depthFactor` becomes the
// v2 `depth`; a registry already carrying `depth` keeps it; otherwise the mid
// default.
func layerDepthV1(l map[string]any) float64 {
	if v, ok := l["depthFactor"].(float64); ok {
		return v
	}
	if v, ok := l["depth"].(float64); ok {
		return v
	}
	return 0.5
}

func asString(v any) string {
	s, _ := v.(string)
	return s
}

func asBool(v any, def bool) bool {
	if b, ok := v.(bool); ok {
		return b
	}
	return def
}

// stageMotionAmount reduces the v1 motion sub-knobs to the single v2 word:
// mouse:false is Subtle (motion off the cursor), a high sensitivity is Strong,
// otherwise Normal.
func stageMotionAmount(motion map[string]any) string {
	if mouse, ok := motion["mouse"].(bool); ok && !mouse {
		return "subtle"
	}
	if sens, ok := motion["sensitivity"].(float64); ok && sens >= 1.5 {
		return "strong"
	}
	return "normal"
}

func defaultStageModels() stageModels {
	return stageModels{
		Draft:    "u2netp",
		Standard: "u2netp",
		Fine:     "birefnet-general-lite",
	}
}

func legacyStageCutFor(tier string, models stageModels) stageCut {
	defaults := defaultStageModels()
	switch tier {
	case "standard":
		if models.Standard == "" {
			models.Standard = defaults.Standard
		}
		return stageCut{model: models.Standard, matting: true}
	case "fine":
		if models.Fine == "" {
			models.Fine = defaults.Fine
		}
		return stageCut{model: models.Fine, matting: true}
	default:
		if models.Draft == "" {
			models.Draft = defaults.Draft
		}
		return stageCut{model: models.Draft}
	}
}

// migrateStageSettings folds the shell-owned stage.json to v2. An existing v1
// file is rewritten in place; an already-v2 file is left byte-for-byte alone.
// A malformed source is never replaced, and the caller cannot commit the
// migration marker until every required write succeeds.
func migrateStageSettings() error {
	dir := ryokuConfigDir()
	if dir == "" {
		return nil
	}
	path := filepath.Join(dir, "stage.json")
	if b, err := os.ReadFile(path); err == nil {
		var m map[string]any
		if err := json.Unmarshal(b, &m); err != nil {
			return fmt.Errorf("decode %s: %w", path, err)
		}
		if stageSettingsVersion(m) >= 3 {
			return nil
		}
		motion, _ := m["motion"].(map[string]any)
		if !stageSettingsIsV1(m, motion) {
			legacy, err := loadLegacyStageSettings(dir)
			if err != nil {
				return err
			}
			if legacy == nil || !mergeLegacyStageSettings(m, legacy) {
				return nil
			}
			return writeJSONFileAtomic(path, m)
		}
		return writeJSONFileAtomic(path, settingsToV2(m))
	} else if !os.IsNotExist(err) {
		return err
	}
	legacy, err := loadLegacyStageSettings(dir)
	if err != nil {
		return err
	}
	if legacy == nil {
		return nil
	}
	return writeJSONFileAtomic(path, settingsToV2(legacy))
}

func migrateStageSettingsV3() error {
	dir := ryokuConfigDir()
	if dir == "" {
		return nil
	}
	path := filepath.Join(dir, "stage.json")
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		return fmt.Errorf("decode %s: %w", path, err)
	}
	if stageSettingsVersion(m) >= 3 {
		return nil
	}
	return writeJSONFileAtomic(path, settingsToV3(m))
}

func stageSettingsVersion(m map[string]any) int {
	if version, ok := m["version"].(float64); ok {
		return int(version)
	}
	return 0
}

// Preserve unknown keys so migration cannot discard newer editor settings.
func settingsToV3(m map[string]any) map[string]any {
	out := make(map[string]any, len(m)+1)
	for key, value := range m {
		out[key] = value
	}

	models := defaultStageModels()
	if values, ok := m["models"].(map[string]any); ok {
		models.Draft = firstString(values["draft"], models.Draft)
		models.Standard = firstString(values["standard"], models.Standard)
		models.Fine = firstString(values["fine"], models.Fine)
	}
	cut := legacyStageCutFor(firstString(m["quality"], "draft"), models)
	cutSettings := func() map[string]any {
		return map[string]any{"model": cut.model, "matting": cut.matting}
	}
	front := firstList(m["front"])
	depthFront := append([]any{}, front...)
	parallaxFront := append([]any{}, front...)
	edge := firstNumber(m["edge"], 0.15)
	shadow := firstNumber(m["shadow"], 0)
	shadowAngle := firstNumber(m["shadowAngle"], 90)

	oldMotion, _ := m["motion"].(map[string]any)
	parallaxMotion := make(map[string]any, len(oldMotion))
	for key, value := range oldMotion {
		parallaxMotion[key] = value
	}
	spatialMotion := map[string]any{
		"amount":      firstString(mapValue(oldMotion, "amount"), "normal"),
		"mouse":       true,
		"sensitivity": firstNumber(mapValue(oldMotion, "sensitivity"), 1),
		"range":       firstNumber(mapValue(oldMotion, "range"), 1),
	}
	if mouse, ok := mapValue(oldMotion, "mouse").(bool); ok {
		spatialMotion["mouse"] = mouse
	}

	out["version"] = 3
	out["depth"] = map[string]any{
		"cut": cutSettings(), "edge": edge, "shadow": shadow,
		"shadowAngle": shadowAngle, "front": depthFront,
	}
	out["parallax"] = map[string]any{
		"cut": cutSettings(), "edge": edge, "shadow": shadow,
		"shadowAngle": shadowAngle, "front": parallaxFront,
		"depthBackdrop": true, "motion": parallaxMotion,
	}
	out["spatial"] = map[string]any{
		"model":       firstString(m["depthModel"], "small"),
		"shadowAngle": shadowAngle,
		"motion":      spatialMotion,
	}
	for _, key := range []string{
		"quality", "models", "depthModel", "edge", "shadow", "shadowAngle",
		"motion", "front",
	} {
		delete(out, key)
	}
	return out
}

// settingsToV2 changes only the retired slots it understands. Starting from a
// copy keeps current model choices, editor settings and future keys intact when
// an otherwise-current file still carries one old key.
func settingsToV2(m map[string]any) map[string]any {
	out := make(map[string]any, len(m)+3)
	for k, v := range m {
		out[k] = v
	}
	motion := stageMotionView(m)
	quality := firstString(m["quality"], "")
	if quality != "draft" && quality != "standard" && quality != "fine" {
		model, _ := m["model"].(string)
		matting, _ := m["alphaMatting"].(bool)
		if model != "" || matting {
			if model == "" {
				model = "u2netp"
			}
			quality = qualityTierForModel(model, matting)
		} else {
			quality = "draft"
		}
	}
	out["quality"] = quality
	if _, ok := out["models"]; !ok {
		out["models"] = defaultStageModels()
	}
	if _, ok := out["edge"]; !ok {
		out["edge"] = firstNumber(m["feather"], 0.15)
	}
	if _, ok := out["shadow"]; !ok {
		out["shadow"] = float64(0)
	}
	if _, ok := out["shadowAngle"]; !ok {
		out["shadowAngle"] = float64(90)
	}
	if _, ok := motion["amount"]; !ok {
		motion["amount"] = stageMotionAmount(motion)
	}
	if _, ok := motion["idle"]; !ok {
		motion["idle"] = "none"
	}
	if _, ok := motion["music"]; !ok {
		motion["music"] = false
	}
	delete(motion, "wallpaper")
	out["motion"] = motion
	if _, ok := out["front"]; !ok {
		out["front"] = []any{}
	}
	for _, key := range []string{
		"feather", "lift", "preset", "model", "alphaMatting",
		"mouseEnabled", "mouseSensitivity", "mouseRange", "wallpaperParallax",
	} {
		delete(out, key)
	}
	return out
}

// mergeLegacyStageSettings fills only current slots that are absent. This lets
// installations already carrying the first v2 marker receive the newly folded
// parallax globals without replacing choices made in Stage since then.
func mergeLegacyStageSettings(current, legacy map[string]any) bool {
	changed := false
	setMissing := func(key string, value any) {
		if _, ok := current[key]; ok || value == nil {
			return
		}
		current[key] = value
		changed = true
	}
	if quality := firstString(legacy["quality"], ""); quality != "" {
		setMissing("quality", quality)
	}
	if edge, ok := legacy["feather"].(float64); ok {
		setMissing("edge", edge)
	}
	for _, key := range []string{"shadow", "shadowAngle", "front"} {
		if value, ok := legacy[key]; ok {
			setMissing(key, value)
		}
	}

	motion, _ := current["motion"].(map[string]any)
	mergedMotion := make(map[string]any, len(motion)+6)
	for key, value := range motion {
		mergedMotion[key] = value
	}
	legacyMotion := stageMotionView(legacy)
	motionChanged := false
	for _, key := range []string{"mouse", "sensitivity", "range", "backdrop", "musicLevel", "speed", "idle", "music"} {
		if _, ok := mergedMotion[key]; ok {
			continue
		}
		if value, ok := legacyMotion[key]; ok {
			mergedMotion[key] = value
			motionChanged = true
		}
	}
	if _, ok := mergedMotion["amount"]; !ok {
		_, hasMouse := legacyMotion["mouse"]
		_, hasSensitivity := legacyMotion["sensitivity"]
		if hasMouse || hasSensitivity {
			mergedMotion["amount"] = stageMotionAmount(legacyMotion)
			motionChanged = true
		}
	}
	if motionChanged {
		current["motion"] = mergedMotion
		changed = true
	}
	return changed
}

// stageMotionView surfaces the retired parallax.json motion globals on one v2
// motion map, so the amount word and the carry-over read both sources the same
// way the v2 file would have named them.
func stageMotionView(m map[string]any) map[string]any {
	motion, _ := m["motion"].(map[string]any)
	merged := map[string]any{}
	for k, v := range motion {
		merged[k] = v
	}
	if _, ok := merged["mouse"]; !ok {
		if mouse, ok := m["mouseEnabled"].(bool); ok {
			merged["mouse"] = mouse
		}
	}
	for _, pair := range []struct{ key, alt string }{
		{"sensitivity", "mouseSensitivity"},
		{"range", "mouseRange"},
	} {
		if _, ok := merged[pair.key]; !ok {
			if v, ok := m[pair.alt].(float64); ok {
				merged[pair.key] = v
			}
		}
	}
	if _, ok := merged["backdrop"]; !ok {
		if v, ok := merged["wallpaper"].(float64); ok {
			merged["backdrop"] = v
		} else if v, ok := m["wallpaperParallax"].(float64); ok {
			merged["backdrop"] = v
		} else if v, ok := m["wallpaper"].(float64); ok {
			merged["backdrop"] = v
		}
	}
	return merged
}

// loadLegacyStageSettings merges the retired depth.json and parallax.json into
// one settings map for the v2 fold. Invalid legacy JSON aborts the fold so it
// remains available for a corrected retry rather than being silently replaced
// by defaults or by only half of the user's settings.
func loadLegacyStageSettings(dir string) (map[string]any, error) {
	scalarProto := map[string]any{
		"feather": 0.0, "shadow": 0.0, "shadowAngle": 0.0,
		"mouseEnabled": false, "mouseSensitivity": 0.0, "mouseRange": 0.0,
		"wallpaperParallax": 0.0,
		"front":             []any{}, "motion": map[string]any{},
	}
	result := map[string]any{}
	found := false
	bestTier := ""
	for _, name := range []string{"parallax.json", "depth.json"} {
		path := filepath.Join(dir, name)
		b, err := os.ReadFile(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return nil, err
		}
		var mm map[string]any
		if err := json.Unmarshal(b, &mm); err != nil {
			return nil, fmt.Errorf("decode %s: %w", path, err)
		}
		found = true
		for k, proto := range scalarProto {
			if v, ok := mm[k]; ok && sameJSONKind(v, proto) {
				result[k] = v
			}
		}
		model, _ := mm["model"].(string)
		_, hasMatting := mm["alphaMatting"]
		if model != "" || hasMatting {
			matting, _ := mm["alphaMatting"].(bool)
			if model == "" {
				model = "u2netp"
			}
			if tier := qualityTierForModel(model, matting); qualityRank(tier) > qualityRank(bestTier) {
				bestTier = tier
			}
		}
	}
	if !found {
		return nil, nil
	}
	if bestTier != "" {
		result["quality"] = bestTier
	}
	return result, nil
}

func qualityRank(t string) int {
	switch t {
	case "fine":
		return 2
	case "standard":
		return 1
	}
	return 0
}

// qualityTierForModel maps a legacy model + matting pair to a v2 quality tier.
func qualityTierForModel(model string, matting bool) string {
	switch {
	case model == "birefnet-general-lite":
		return "fine"
	case matting:
		return "standard"
	default:
		return "draft"
	}
}

// sameJSONKind reports whether a legacy value has the shape of the scalar slot it
// would fill, so a per-layer array never lands where a scalar is expected.
func sameJSONKind(v, def any) bool {
	switch def.(type) {
	case float64, int:
		_, ok := v.(float64)
		return ok
	case bool:
		_, ok := v.(bool)
		return ok
	case string:
		_, ok := v.(string)
		return ok
	case []any, []string:
		_, ok := v.([]any)
		return ok
	case map[string]any:
		_, ok := v.(map[string]any)
		return ok
	}
	return false
}

// stageSettingsIsV1 looks only for the top-level slots unique to v1. Pointer
// tuning remains part of the current motion schema, so mouse, sensitivity and
// range must never make an otherwise-current file look old.
func stageSettingsIsV1(m, _ map[string]any) bool {
	for _, k := range []string{"feather", "lift", "preset"} {
		if _, ok := m[k]; ok {
			return true
		}
	}
	return false
}

func mapValue(m map[string]any, k string) any {
	if m == nil {
		return nil
	}
	return m[k]
}

func firstString(v any, def string) string {
	if s, ok := v.(string); ok && s != "" {
		return s
	}
	return def
}

func firstNumber(v any, def float64) float64 {
	if n, ok := v.(float64); ok {
		return n
	}
	return def
}

func firstList(v any) []any {
	if l, ok := v.([]any); ok {
		return l
	}
	return []any{}
}

func (d *daemon) startStage() {
	removeStageJobDirs()
	killStrayStageEngines()
	d.registerTopic("stage")
	migrateStage()
	d.publishStage()
	go d.stageWorker()
	if dir := ryokuConfigDir(); dir != "" {
		go d.watchFile(filepath.Join(dir, "stage.json"), d.scheduleStage)
	}
}
