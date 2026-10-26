package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"math"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func writeStageStub(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	logf := filepath.Join(dir, "calls.log")
	bin := filepath.Join(dir, "ryostage-stub")
	const script = `#!/usr/bin/env bash
echo "$*" >> "$STAGE_STUB_LOG"
cmd="${1:-}"; shift || true
if [[ -n "${STAGE_STUB_IGNORE_TERM:-}" ]]; then trap '' TERM; fi
if [[ -n "${STAGE_STUB_SLEEP:-}" ]] &&
   [[ -z "${STAGE_STUB_SLEEP_CMD:-}" || "${STAGE_STUB_SLEEP_CMD}" == "$cmd" ]]; then
  sleep "$STAGE_STUB_SLEEP" || true
fi
if [[ -n "${STAGE_STUB_FAIL_CMD:-}" && "${STAGE_STUB_FAIL_CMD}" == "$cmd" ]]; then
  echo "${STAGE_STUB_FAIL_LINE:-engine failed}" >&2
  exit 1
fi
case "$cmd" in
  check)
    if [[ -n "${STAGE_STUB_MISSING:-}" ]]; then echo "${STAGE_STUB_CHECK_REASON:-missing}"; exit 1; fi
    echo available; exit 0 ;;
  models)
    echo '[{"id":"u2netp","tier":"draft","label":"Draft","installed":true}]'; exit 0 ;;
  cut)
    out="$2"
    if [[ -n "${STAGE_STUB_CUT_FAIL:-}" ]]; then echo "${STAGE_STUB_FAIL_LINE:-cut failed}" >&2; exit 1; fi
    mkdir -p "$(dirname "$out")"; printf 'SUBJECTPNG' > "$out"; echo "$out"; exit 0 ;;
  inpaint)
    out="$3"
    if [[ -n "${STAGE_STUB_INPAINT_FAIL:-}" ]]; then echo "${STAGE_STUB_FAIL_LINE:-inpaint failed}" >&2; exit 1; fi
    mkdir -p "$(dirname "$out")"; printf 'BGPNG' > "$out"; echo "$out"; exit 0 ;;
  depth-check)
    if [[ -n "${STAGE_STUB_DEPTH:-}" ]]; then echo available; exit 0; fi
    echo "model missing"; exit 1 ;;
  depth)
    out="$2"
    mkdir -p "$(dirname "$out")"; printf 'DEPTHPNG' > "$out"; echo "$out"; exit 0 ;;
esac
exit 0
`
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_STAGE_ENGINE", bin)
	t.Setenv("STAGE_STUB_LOG", logf)
	return logf
}

// countCalls returns how many logged engine invocations began with verb.
func countCalls(logf, verb string) int {
	b, err := os.ReadFile(logf)
	if err != nil {
		return 0
	}
	n := 0
	for _, line := range strings.Split(string(b), "\n") {
		if fields := strings.Fields(line); len(fields) > 0 && fields[0] == verb {
			n++
		}
	}
	return n
}

// stageHome wires a hermetic HOME + XDG tree and returns it.
func stageHome(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, ".local", "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(home, ".cache"))
	// An empty runtime dir: no ryogami socket, so depthClear/publish fail fast
	// and harmlessly instead of reaching the live daemon.
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	return home
}

func (d *daemon) showWall(pic string) {
	d.ryoWallMu.Lock()
	d.ryoWall = ryogamiFrame{Default: ryogamiFrameEntry{Path: pic}}
	d.ryoWallMu.Unlock()
}

func TestStageWallsRoundTrip(t *testing.T) {
	home := stageHome(t)
	wall := filepath.Join(home, "w.png")

	reg := stageWalls{Current: wall, Walls: map[string]stageWall{}}
	reg.Walls[wall] = stageWall{
		Effect: stageEffectParallax,
		Layers: []stageLayer{
			{Out: "/a/subject.png", Label: "Subject", Enabled: true, Front: true, Depth: 0.5},
			{Out: "/a/layer-02.png", Label: "Layer 2", Enabled: false, Front: false, Depth: 0.9},
		},
	}
	if err := saveStageWalls(reg); err != nil {
		t.Fatal(err)
	}
	got := loadStageWalls()
	if got.Version != 3 {
		t.Fatalf("version = %d, want 3", got.Version)
	}
	if got.Current != wall {
		t.Fatalf("current = %q, want %q", got.Current, wall)
	}
	w := got.Walls[wall]
	if w.Effect != stageEffectParallax {
		t.Fatalf("effect = %v, want parallax", w.Effect)
	}
	if len(w.Layers) != 2 {
		t.Fatalf("layers = %d, want 2", len(w.Layers))
	}
	if s := w.Layers[0]; s.Label != "Subject" || !s.Enabled || !s.Front || s.Depth != 0.5 {
		t.Fatalf("subject layer round-trip = %+v", s)
	}
	if l := w.Layers[1]; l.Enabled || l.Front || l.Depth != 0.9 {
		t.Fatalf("manual layer round-trip = %+v", l)
	}
	raw, _ := os.ReadFile(stageWallsPath())
	for _, gone := range []string{"\"mode\"", "\"scene\"", "opacity", "feather"} {
		if strings.Contains(string(raw), gone) {
			t.Fatalf("v3 registry still carries the retired %q: %s", gone, raw)
		}
	}

	// Normalisation after a decode failure: a garbage file still yields a
	// non-nil map.
	if err := os.WriteFile(stageWallsPath(), []byte("{not json"), 0o644); err != nil {
		t.Fatal(err)
	}
	if norm := loadStageWalls(); norm.Walls == nil {
		t.Fatal("corrupt registry did not normalise to a non-nil Walls map")
	}
}

func TestStageSetEffectAndRyogamiWakeAreManualOnly(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.showWall(wall)

	if got := d.dispatch("stage set-effect parallax"); got != "ok" {
		t.Fatalf("set-effect = %q", got)
	}
	d.reconcileStage()
	select {
	case <-d.stageSig:
	default:
	}
	d.consumeRyogamiFrames(strings.NewReader(
		fmt.Sprintf("{\"default\":{\"path\":%q},\"outputs\":{}}\n", wall)))
	select {
	case <-d.stageSig:
	default:
		t.Fatal("ryogami frame did not wake the publish worker")
	}
	d.reconcileStage()

	if calls := countCalls(logFile, "check") + countCalls(logFile, "cut") +
		countCalls(logFile, "inpaint") + countCalls(logFile, "depth"); calls != 0 {
		t.Fatalf("set-effect or ryogami wake made %d engine calls", calls)
	}
	frame := d.buildStageFrame()
	if frame.Job != nil || frame.Busy {
		t.Fatalf("publish-only wake created a job: %+v", frame.Job)
	}
	if got := stageStepStateFor(frame.Walls[wall].Steps, stageStepCut); got != stageStateMissing {
		t.Fatalf("cut readiness = %q, want missing", got)
	}
}

func TestStageDepthPublishesRyogamiPixelLock(t *testing.T) {
	home := stageHome(t)
	listener, err := net.Listen("unix", ryogamiSock())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	command := make(chan string, 1)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			command <- ""
			return
		}
		defer conn.Close()
		line, _ := bufio.NewReader(conn).ReadString('\n')
		command <- strings.TrimSpace(line)
		_, _ = conn.Write([]byte("ok\n"))
	}()

	wall := filepath.Join(home, "w.png")
	writeFile(t, wall, "wall")
	if err := os.MkdirAll(stageWallDir(wall), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, stageSubjectOut(wall), "subject")
	future := time.Now().Add(time.Minute)
	if err := os.Chtimes(stageSubjectOut(wall), future, future); err != nil {
		t.Fatal(err)
	}
	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.showWall(wall)
	d.stageSetEffect(wall, stageEffectDepth)
	d.reconcileStage()

	var line string
	select {
	case line = <-command:
	case <-time.After(2 * time.Second):
		t.Fatal("Depth did not hand its subject to ryogami")
	}
	if !strings.HasPrefix(line, "depth set ") {
		t.Fatalf("ryogami command = %q, want depth set", line)
	}
	var request struct {
		Source string `json:"source"`
		Out    string `json:"out"`
	}
	if err := json.Unmarshal([]byte(strings.TrimPrefix(line, "depth set ")), &request); err != nil {
		t.Fatal(err)
	}
	if request.Source != wall || request.Out != stageSubjectOut(wall) {
		t.Fatalf("pixel-lock handoff = %+v", request)
	}
}

func TestStageSetEffectValidationAndWallScope(t *testing.T) {
	home := stageHome(t)
	defaultWall := filepath.Join(home, "default.png")
	outputWall := filepath.Join(home, "output wall.png")
	writeFile(t, defaultWall, "default")
	writeFile(t, outputWall, "output")
	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.showWall(defaultWall)

	if got := d.dispatch("stage set-effect spatial -- " + outputWall); got != "ok" {
		t.Fatalf("scoped set-effect = %q", got)
	}
	registry := loadStageWalls()
	if got := registry.Walls[outputWall].Effect; got != stageEffectSpatial {
		t.Fatalf("output effect = %q, want spatial", got)
	}
	if got := registry.Walls[defaultWall].Effect; got != "" {
		t.Fatalf("default wall changed to %q", got)
	}
	const want = "err stage set-effect: expected off|depth|parallax|spatial"
	if got := d.dispatch("stage set-effect junk"); got != want {
		t.Fatalf("invalid set-effect = %q, want %q", got, want)
	}
}

func TestStageClearKeepsManualLayersAndDepthMap(t *testing.T) {
	home := stageHome(t)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	if err := os.MkdirAll(stageWallDir(wall), 0o755); err != nil {
		t.Fatal(err)
	}
	for path, body := range map[string]string{
		stageSubjectOut(wall):                             "subject",
		stageBackgroundOut(wall):                          "background",
		stageDepthOut(wall):                               "depth",
		stageIndexPath(wall):                              "{}",
		filepath.Join(stageWallDir(wall), "layer-01.png"): "manual",
	} {
		writeFile(t, path, body)
	}
	if err := saveStageWalls(stageWalls{Walls: map[string]stageWall{
		wall: {Effect: stageEffectParallax},
	}}); err != nil {
		t.Fatal(err)
	}
	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.stageClear(wall)

	if isFile(stageSubjectOut(wall)) || isFile(stageBackgroundOut(wall)) || isFile(stageIndexPath(wall)) {
		t.Fatal("clear left generated cut artifacts")
	}
	if !isFile(stageDepthOut(wall)) || !isFile(filepath.Join(stageWallDir(wall), "layer-01.png")) {
		t.Fatal("clear removed the depth map or a manual layer")
	}
	if got := loadStageWalls().Walls[wall].Effect; got != stageEffectOff {
		t.Fatalf("effect after clear = %q, want off", got)
	}
}

func TestStageV3SettingsReaders(t *testing.T) {
	home := stageHome(t)
	dir := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(dir, "stage.json"), `{
  "version": 3,
  "depth": {"cut": {"model": "birefnet-portrait", "matting": true}},
  "parallax": {
    "cut": {"model": "silueta", "matting": false},
    "depthBackdrop": false
  },
  "spatial": {"model": "large"}
}`)
	depthCut := stageCutFor(stageEffectDepth)
	if depthCut.model != "birefnet-portrait" || !depthCut.matting {
		t.Fatalf("depth cut = %+v, want portrait with matting", depthCut)
	}
	parallaxCut := stageCutFor(stageEffectParallax)
	if parallaxCut.model != "silueta" || parallaxCut.matting {
		t.Fatalf("parallax cut = %+v, want silueta without matting", parallaxCut)
	}
	if got := stageSpatialModel(); got != "large" {
		t.Fatalf("spatial model = %q, want large", got)
	}
	if stageDepthBackdrop() {
		t.Fatal("depthBackdrop = true, want false")
	}

	writeFile(t, filepath.Join(dir, "stage.json"),
		`{"version":3,"depth":{"cut":{"model":"unknown","matting":true}},`+
			`"parallax":{"cut":{"model":"unknown"}},"spatial":{"model":"unknown"}}`)
	if got := stageCutFor(stageEffectDepth); got.model != "u2netp" || !got.matting {
		t.Fatalf("unknown Depth model fallback = %+v", got)
	}
	if got := stageCutFor(stageEffectParallax); got.model != "u2netp" {
		t.Fatalf("unknown Parallax model fallback = %+v", got)
	}
	if got := stageSpatialModel(); got != "small" {
		t.Fatalf("unknown Spatial model fallback = %q", got)
	}
	if !stageDepthBackdrop() {
		t.Fatal("missing depthBackdrop did not default true")
	}
}

// TestStageEngineBinSeam pins the resolution order: the RYOKU_STAGE_ENGINE seam
// wins, and a bad RYOKU_SHELL_DIR falls back to the PATH name.
func TestStageEngineBinSeam(t *testing.T) {
	t.Setenv("RYOKU_STAGE_ENGINE", "/opt/ryostage")
	if got := stageEngineBin(); got != "/opt/ryostage" {
		t.Fatalf("engine bin = %q, want the RYOKU_STAGE_ENGINE seam", got)
	}
	t.Setenv("RYOKU_STAGE_ENGINE", "")
	t.Setenv("RYOKU_SHELL_DIR", "/dev/null")
	if got := stageEngineBin(); got != "ryostage" {
		t.Fatalf("engine bin with bad RYOKU_SHELL_DIR = %q, want ryostage", got)
	}
}

// TestStageManualLayers pins the manual-layer naming and ordering contract:
// layer-NN.png in order, subject.png and single-digit names excluded, each
// defaulting to on and behind the widgets.
func TestStageManualLayers(t *testing.T) {
	home := stageHome(t)
	wall := filepath.Join(home, "w.png")
	dir := stageWallDir(wall)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"layer-03.png", "layer-01.png", "layer-02.png", "subject.png", "notes.txt", "layer-1.png"} {
		writeFile(t, filepath.Join(dir, name), name)
	}
	layers := manualLayers(wall)
	if len(layers) != 3 {
		t.Fatalf("manual layers = %d, want 3 (subject.png and single-digit excluded)", len(layers))
	}
	wantLabel := []string{"Layer 1", "Layer 2", "Layer 3"}
	wantSuffix := []string{"layer-01.png", "layer-02.png", "layer-03.png"}
	for i, l := range layers {
		if l.Label != wantLabel[i] {
			t.Errorf("layer[%d] label = %v, want %q", i, l.Label, wantLabel[i])
		}
		if !strings.HasSuffix(l.Out, wantSuffix[i]) {
			t.Errorf("layer[%d] out = %v, want suffix %q", i, l.Out, wantSuffix[i])
		}
		if !l.Enabled || l.Front {
			t.Errorf("layer[%d] defaults = %+v, want enabled & behind", i, l)
		}
	}
}

// TestStageAddLayerNumbering pins add-layer's naming: the next free NN after the
// highest existing layer-NN.png, formatted two-digit.
func TestStageAddLayerNumbering(t *testing.T) {
	home := stageHome(t)
	wall := filepath.Join(home, "w.png")
	writeFile(t, wall, "wp")
	src := filepath.Join(home, "extra.png")
	writeFile(t, src, "X")

	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.showWall(wall)

	dir := stageWallDir(wall)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	// A pre-existing layer-03.png: the next add must be layer-04.png (max+1).
	writeFile(t, filepath.Join(dir, "layer-03.png"), "L3")

	p1, err := d.stageAddLayer(wall, src)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(p1) != "layer-04.png" {
		t.Fatalf("first add = %s, want layer-04.png", filepath.Base(p1))
	}
	p2, err := d.stageAddLayer(wall, src)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(p2) != "layer-05.png" {
		t.Fatalf("second add = %s, want layer-05.png", filepath.Base(p2))
	}
}

// TestStageRemoveLayerRejectsSubject pins the guard: index 0 (the subject) is
// never removable, while a manual layer removes its file.
func TestStageRemoveLayerRejectsSubject(t *testing.T) {
	home := stageHome(t)
	wall := filepath.Join(home, "w.png")
	writeFile(t, wall, "wp")
	if err := saveStageWalls(stageWalls{Walls: map[string]stageWall{wall: {Effect: stageEffectDepth}}}); err != nil {
		t.Fatal(err)
	}

	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.showWall(wall)

	if err := d.stageRemoveLayer(wall, "0"); err == nil {
		t.Fatal("remove-layer 0 must be rejected: the subject is not removable")
	}

	dir := stageWallDir(wall)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	layer := filepath.Join(dir, "layer-01.png")
	writeFile(t, layer, "L1")
	if err := d.stageRemoveLayer(wall, "1"); err != nil {
		t.Fatalf("remove-layer 1 (a manual layer) failed: %v", err)
	}
	if isFile(layer) {
		t.Fatal("remove-layer 1 did not delete the manual layer file")
	}
}

func TestStageRegistryMigrationV1toV3(t *testing.T) {
	home := stageHome(t)
	if err := os.MkdirAll(filepath.Join(stateDir(), "ryoku"), 0o755); err != nil {
		t.Fatal(err)
	}
	wpA := filepath.Join(home, "a.png") // static subject + one manual layer
	wpB := filepath.Join(home, "b.png") // parallax manual: layers only
	wpC := filepath.Join(home, "c.png") // v1 static depth with no artifact
	writeFile(t, wpA, "A")
	writeFile(t, wpB, "B")
	writeFile(t, wpC, "C")

	subjA := stageSubjectOut(wpA)
	layA2 := filepath.Join(stageWallDir(wpA), "layer-02.png")
	layB1 := filepath.Join(stageWallDir(wpB), "layer-01.png")
	v1 := `{
      "current": "` + wpA + `",
      "walls": {
        "` + wpA + `": {
          "effect": "subject",
          "mode": "auto",
          "scene": ["wallpaper", "layer:1", "widget:clock", "layer:2"],
          "layers": [
            {"out":"` + subjA + `","label":"Subject","depthFactor":0.3,"opacity":0.8,"enabled":true},
            {"out":"` + layA2 + `","label":"Layer 2","depthFactor":0.7,"feather":0.1}
          ]
        },
        "` + wpB + `": {
          "effect": "parallax",
          "mode": "manual",
          "layers": [
            {"out":"` + layB1 + `","label":"Layer 1","depthFactor":0.4}
          ]
        },
        "` + wpC + `": {"effect": "depth", "layers": []}
      }
    }`
	writeFile(t, stageWallsPath(), v1)

	migrateStage()

	reg := loadStageWalls()
	if reg.Version != 3 {
		t.Fatalf("registry version = %d, want 3", reg.Version)
	}
	a := reg.Walls[wpA]
	if a.Effect != stageEffectDepth {
		t.Fatalf("wpA effect = %v, want depth (was subject)", a.Effect)
	}
	if len(a.Layers) != 2 {
		t.Fatalf("wpA layers = %d, want 2", len(a.Layers))
	}
	// Scene reduction: layer:1 (subject, idx0) is before widget:clock -> behind;
	// layer:2 (idx1) is after it -> in front.
	if a.Layers[0].Front {
		t.Fatalf("subject listed before the widget should be behind: %+v", a.Layers[0])
	}
	if !a.Layers[1].Front {
		t.Fatalf("layer after the widget should be in front: %+v", a.Layers[1])
	}
	if a.Layers[0].Depth != 0.3 || a.Layers[1].Depth != 0.7 {
		t.Fatalf("depthFactor not folded to depth: %+v", a.Layers)
	}
	raw, _ := os.ReadFile(stageWallsPath())
	for _, gone := range []string{"depthFactor", "opacity", "feather", "\"mode\"", "\"scene\""} {
		if strings.Contains(string(raw), gone) {
			t.Fatalf("v3 registry still carries the retired %q: %s", gone, raw)
		}
	}

	// A manual wall keeps its layer-NN.png after a prepended subject slot.
	b := reg.Walls[wpB]
	if b.Effect != stageEffectParallax {
		t.Fatalf("wpB effect = %v, want parallax", b.Effect)
	}
	if len(b.Layers) != 2 {
		t.Fatalf("wpB layers = %d, want 2 (subject + kept manual)", len(b.Layers))
	}
	if filepath.Base(b.Layers[0].Out) != "subject.png" || b.Layers[0].Label != "Subject" {
		t.Fatalf("wpB layer[0] is not the prepended subject: %+v", b.Layers[0])
	}
	if filepath.Base(b.Layers[1].Out) != "layer-01.png" {
		t.Fatalf("wpB layer[1] is not the kept manual: %+v", b.Layers[1])
	}
	if got := reg.Walls[wpC].Effect; got != stageEffectDepth {
		t.Fatalf("v1 static depth effect = %v, want depth", got)
	}

	if !isFile(stageMigrationMarker()) || !isFile(stageV3MigrationMarker()) {
		t.Fatal("v2 or v3 migration marker not written")
	}
	before, _ := os.ReadFile(stageWallsPath())
	migrateStage()
	after, _ := os.ReadFile(stageWallsPath())
	if string(before) != string(after) {
		t.Fatal("second migration mutated the registry (not a no-op)")
	}
}

func TestStageRegistryV2toV3Heuristics(t *testing.T) {
	home := stageHome(t)
	if err := writeStageMigrationMarker(stageMigrationMarker(), "done\n"); err != nil {
		t.Fatal(err)
	}
	withMap := filepath.Join(home, "with-map.png")
	withSubject := filepath.Join(home, "with-subject.png")
	withoutArtifacts := filepath.Join(home, "without-artifacts.png")
	for _, wall := range []string{withMap, withSubject, withoutArtifacts} {
		writeFile(t, wall, "WALL")
	}
	if err := os.MkdirAll(stageWallDir(withMap), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(stageWallDir(withSubject), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, stageDepthOut(withMap), "DEPTH")
	writeFile(t, stageSubjectOut(withSubject), "SUBJECT")
	reg := map[string]any{
		"future": "kept",
		"walls": map[string]any{
			withMap: map[string]any{
				"effect": stageEffectDepth,
				"future": "wall-kept",
			},
			withSubject:      map[string]any{"effect": stageEffectDepth},
			withoutArtifacts: map[string]any{"effect": stageEffectDepth},
		},
	}
	if err := writeJSONFileAtomic(stageWallsPath(), reg); err != nil {
		t.Fatal(err)
	}

	migrateStage()

	got := loadStageWalls()
	if got.Version != 3 {
		t.Fatalf("registry version = %d, want 3", got.Version)
	}
	if effect := got.Walls[withMap].Effect; effect != stageEffectSpatial {
		t.Fatalf("depth.png wall = %v, want spatial", effect)
	}
	if effect := got.Walls[withSubject].Effect; effect != stageEffectDepth {
		t.Fatalf("subject.png wall = %v, want depth", effect)
	}
	if effect := got.Walls[withoutArtifacts].Effect; effect != stageEffectSpatial {
		t.Fatalf("artifact-free wall = %v, want spatial", effect)
	}
	raw, err := os.ReadFile(stageWallsPath())
	if err != nil {
		t.Fatal(err)
	}
	var preserved map[string]any
	if err := json.Unmarshal(raw, &preserved); err != nil {
		t.Fatal(err)
	}
	if preserved["future"] != "kept" {
		t.Fatalf("unknown registry key = %#v, want kept", preserved["future"])
	}
	walls := preserved["walls"].(map[string]any)
	withMapRaw := walls[withMap].(map[string]any)
	if withMapRaw["future"] != "wall-kept" {
		t.Fatalf("unknown wall key = %#v, want wall-kept", withMapRaw["future"])
	}
	if !isFile(stageV3MigrationMarker()) {
		t.Fatal("v3 migration marker not written")
	}
	before, _ := os.ReadFile(stageWallsPath())
	migrateStage()
	after, _ := os.ReadFile(stageWallsPath())
	if string(after) != string(before) {
		t.Fatal("second registry v3 migration was not a no-op")
	}
}

func TestStageRegistryMalformedJSONIsRetried(t *testing.T) {
	stageHome(t)
	if err := writeStageMigrationMarker(stageMigrationMarker(), "done\n"); err != nil {
		t.Fatal(err)
	}
	writeFile(t, stageWallsPath(), `{"version":2,"walls":`)
	before, err := os.ReadFile(stageWallsPath())
	if err != nil {
		t.Fatal(err)
	}

	migrateStage()

	after, err := os.ReadFile(stageWallsPath())
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatal("malformed registry was changed")
	}
	if isFile(stageV3MigrationMarker()) {
		t.Fatal("v3 migration marked complete after malformed registry")
	}
}

// TestStageSettingsFoldV1toV2 pins the one-time stage.json fold: feather becomes
// edge, mouse:false folds to motion.amount subtle, lift/preset drop, idle/music
// default, quality/shadow/front carry, and an already-v2 file is left alone.
func TestStageSettingsFoldV1toV2(t *testing.T) {
	home := stageHome(t)
	cfg := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(cfg, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(cfg, "stage.json")
	writeFile(t, path, `{"quality":"fine","feather":0.2,"lift":1,"shadow":0.3,"shadowAngle":45,`+
		`"models":{"draft":"custom-draft","standard":"custom-standard","fine":"custom-fine"},`+
		`"depthModel":"large","editGridSize":24,"editGridSnap":false,"futureSetting":{"kept":true},`+
		`"motion":{"mouse":false,"sensitivity":2,"range":0.3,"wallpaper":0.2,"futureMotion":"kept"},`+
		`"preset":"deep","front":["clock"]}`)

	if err := migrateStageSettings(); err != nil {
		t.Fatal(err)
	}

	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	if got["edge"] != 0.2 {
		t.Fatalf("feather did not fold to edge=0.2: %v", got["edge"])
	}
	if got["quality"] != "fine" || got["shadow"] != 0.3 {
		t.Fatalf("carried keys wrong: quality=%v shadow=%v", got["quality"], got["shadow"])
	}
	for _, gone := range []string{"feather", "lift", "preset"} {
		if _, ok := got[gone]; ok {
			t.Fatalf("v1-only key %q not dropped: %s", gone, b)
		}
	}
	motion, _ := got["motion"].(map[string]any)
	if motion["amount"] != "subtle" {
		t.Fatalf("mouse:false must fold to amount=subtle, got %v", motion["amount"])
	}
	if motion["idle"] != "none" || motion["music"] != false {
		t.Fatalf("motion idle/music not defaulted: %+v", motion)
	}
	if motion["mouse"] != false || motion["sensitivity"] != 2.0 ||
		motion["range"] != 0.3 || motion["backdrop"] != 0.2 {
		t.Fatalf("motion tunables must carry over: %v", motion)
	}
	for _, gone := range []string{"wallpaper"} {
		if _, ok := motion[gone]; ok {
			t.Fatalf("v1 motion key %q must map to backdrop: %s", gone, b)
		}
	}
	front, _ := got["front"].([]any)
	if len(front) != 1 || front[0] != "clock" {
		t.Fatalf("front = %v, want [clock]", got["front"])
	}

	models, _ := got["models"].(map[string]any)
	if models["draft"] != "custom-draft" || got["depthModel"] != "large" ||
		got["editGridSize"] != 24.0 || got["editGridSnap"] != false {
		t.Fatalf("current model/editor settings did not survive: %s", b)
	}
	future, _ := got["futureSetting"].(map[string]any)
	if future["kept"] != true || motion["futureMotion"] != "kept" {
		t.Fatalf("forward-compatible keys did not survive: %s", b)
	}

	// Current pointer tuning belongs to v2 and must not trigger migration.
	v2 := `{"quality":"draft","edge":0.1,"depthModel":"base","editGridSize":32,` +
		`"customModel":"mine","future":{"version":3},"motion":{"amount":"strong",` +
		`"idle":"float","music":true,"mouse":true,"sensitivity":1.25,"range":0.4},"front":[]}`
	writeFile(t, path, v2)
	if err := migrateStageSettings(); err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(path)
	if string(after) != v2 {
		t.Fatalf("already-v2 stage.json was rewritten:\n got %s\nwant %s", after, v2)
	}
}

func TestStageSettingsV2toV3QualityMapping(t *testing.T) {
	cases := []struct {
		quality string
		model   string
		matting bool
	}{
		{"draft", "silueta", false},
		{"standard", "birefnet-portrait", true},
		{"fine", "birefnet-general", true},
	}
	for _, tc := range cases {
		t.Run(tc.quality, func(t *testing.T) {
			home := stageHome(t)
			cfg := filepath.Join(home, ".config", "ryoku")
			if err := os.MkdirAll(cfg, 0o755); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(cfg, "stage.json")
			writeFile(t, path, `{"version":2,"quality":"`+tc.quality+`",`+
				`"models":{"draft":"silueta","standard":"birefnet-portrait",`+
				`"fine":"birefnet-general"}}`)
			if err := migrateStageSettingsV3(); err != nil {
				t.Fatal(err)
			}
			b, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			var got map[string]any
			if err := json.Unmarshal(b, &got); err != nil {
				t.Fatal(err)
			}
			for _, mode := range []string{"depth", "parallax"} {
				modeSettings, _ := got[mode].(map[string]any)
				cut, _ := modeSettings["cut"].(map[string]any)
				if cut["model"] != tc.model || cut["matting"] != tc.matting {
					t.Fatalf("%s cut = %v, want model %s matting %v",
						mode, cut, tc.model, tc.matting)
				}
			}
		})
	}
}

func TestStageSettingsV2toV3SplitAndNoOp(t *testing.T) {
	home := stageHome(t)
	cfg := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(cfg, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(cfg, "stage.json")
	writeFile(t, path, `{
  "version": 2,
  "quality": "fine",
  "models": {"fine": "birefnet-general-lite"},
  "depthModel": "large",
  "edge": 0.22,
  "shadow": 0.4,
  "shadowAngle": 135,
  "front": ["clock"],
  "motion": {
    "amount": "strong", "idle": "sway", "music": true, "musicLevel": 0.7,
    "speed": 1.4, "mouse": false, "sensitivity": 1.6, "range": 0.8,
    "backdrop": 0.3, "futureMotion": "kept"
  },
  "editGridSize": 24,
  "editGridSnap": false,
  "futureSetting": {"kept": true}
}`)

	if err := migrateStageSettingsV3(); err != nil {
		t.Fatal(err)
	}
	first, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(first, &got); err != nil {
		t.Fatal(err)
	}
	if got["version"] != 3.0 || got["editGridSize"] != 24.0 || got["editGridSnap"] != false {
		t.Fatalf("version or editor settings wrong: %s", first)
	}
	future, _ := got["futureSetting"].(map[string]any)
	if future["kept"] != true {
		t.Fatalf("unknown top-level key was lost: %s", first)
	}
	depth, _ := got["depth"].(map[string]any)
	parallax, _ := got["parallax"].(map[string]any)
	spatial, _ := got["spatial"].(map[string]any)
	for mode, settings := range map[string]map[string]any{"depth": depth, "parallax": parallax} {
		if settings["edge"] != 0.22 || settings["shadow"] != 0.4 ||
			settings["shadowAngle"] != 135.0 {
			t.Fatalf("%s look did not copy: %v", mode, settings)
		}
		front, _ := settings["front"].([]any)
		if len(front) != 1 || front[0] != "clock" {
			t.Fatalf("%s front = %v, want [clock]", mode, settings["front"])
		}
	}
	if parallax["depthBackdrop"] != true {
		t.Fatalf("Parallax depthBackdrop = %v, want true", parallax["depthBackdrop"])
	}
	parallaxMotion, _ := parallax["motion"].(map[string]any)
	if parallaxMotion["idle"] != "sway" || parallaxMotion["futureMotion"] != "kept" ||
		parallaxMotion["backdrop"] != 0.3 {
		t.Fatalf("Parallax motion did not copy whole: %v", parallaxMotion)
	}
	if spatial["model"] != "large" || spatial["shadowAngle"] != 135.0 {
		t.Fatalf("Spatial model/look did not copy: %v", spatial)
	}
	spatialMotion, _ := spatial["motion"].(map[string]any)
	if spatialMotion["amount"] != "strong" || spatialMotion["mouse"] != false ||
		spatialMotion["sensitivity"] != 1.6 || spatialMotion["range"] != 0.8 {
		t.Fatalf("Spatial motion split wrong: %v", spatialMotion)
	}
	if _, ok := spatialMotion["idle"]; ok {
		t.Fatalf("Spatial inherited Parallax-only motion: %v", spatialMotion)
	}
	for _, retired := range []string{
		"quality", "models", "depthModel", "edge", "shadow", "shadowAngle",
		"motion", "front",
	} {
		if _, ok := got[retired]; ok {
			t.Fatalf("retired key %q remains: %s", retired, first)
		}
	}

	if err := migrateStageSettingsV3(); err != nil {
		t.Fatal(err)
	}
	second, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(second) != string(first) {
		t.Fatal("second v3 settings migration was not a no-op")
	}
}

func TestStageSettingsMalformedJSONIsRetried(t *testing.T) {
	home := stageHome(t)
	cfg := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(cfg, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(cfg, "stage.json")
	const malformed = `{"quality":"fine","feather":`
	writeFile(t, path, malformed)

	if err := migrateStageSettingsV3(); err == nil {
		t.Fatal("malformed stage.json v3 migration succeeded")
	}
	migrateStage()
	if isFile(stageMigrationMarker()) || isFile(stageV3MigrationMarker()) {
		t.Fatal("migration marker written for malformed stage.json")
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != malformed {
		t.Fatalf("malformed stage.json was changed: %q", after)
	}
}

func TestStageSettingsWriteFailureDoesNotMarkMigration(t *testing.T) {
	home := stageHome(t)
	cfg := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(cfg, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(cfg, "stage.json")
	const v1 = `{"quality":"draft","feather":0.2,"motion":{"mouse":true}}`
	writeFile(t, path, v1)
	if err := os.Chmod(cfg, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(cfg, 0o755) })

	if err := migrateStageSettings(); err == nil {
		t.Fatal("migration into a read-only directory succeeded")
	}
	migrateStage()
	if isFile(stageMigrationMarker()) || isFile(stageV3MigrationMarker()) {
		t.Fatal("migration marker written after settings write failure")
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != v1 {
		t.Fatalf("stage.json changed after failed write: %q", after)
	}
}

func TestStageOldMarkerStillFoldsLegacySettings(t *testing.T) {
	home := stageHome(t)
	cfg := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(cfg, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(oldStageMigrationMarker()), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, oldStageMigrationMarker(), "old migration complete\n")
	writeFile(t, filepath.Join(cfg, "stage.json"),
		`{"quality":"fine","depthModel":"large","customModel":"mine",`+
			`"motion":{"amount":"strong","future":"kept"}}`)
	writeFile(t, filepath.Join(cfg, "parallax.json"),
		`{"feather":0.27,"mouseEnabled":false,"wallpaperParallax":0.6}`)

	migrateStage()

	b, err := os.ReadFile(filepath.Join(cfg, "stage.json"))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	parallax, _ := got["parallax"].(map[string]any)
	motion, _ := parallax["motion"].(map[string]any)
	if parallax["edge"] != 0.27 || motion["mouse"] != false || motion["backdrop"] != 0.6 {
		t.Fatalf("legacy settings were not folded past the old marker: %s", b)
	}
	spatial, _ := got["spatial"].(map[string]any)
	spatialMotion, _ := spatial["motion"].(map[string]any)
	if got["version"] != 3.0 || got["customModel"] != "mine" ||
		spatial["model"] != "large" || spatialMotion["amount"] != "strong" ||
		motion["future"] != "kept" {
		t.Fatalf("current settings were overwritten by the legacy fold: %s", b)
	}
	if !isFile(stageMigrationMarker()) || !isFile(stageV3MigrationMarker()) {
		t.Fatal("v2 or v3 corrective migration marker not written")
	}
}

func TestStageParallaxMoveConflictKeepsLegacyPath(t *testing.T) {
	home := stageHome(t)
	wall := filepath.Join(home, "wall.png")
	srcDir := filepath.Join(legacyParallaxDir(), "wall")
	dstDir := stageWallDir(wall)
	if err := os.MkdirAll(srcDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(dstDir, 0o755); err != nil {
		t.Fatal(err)
	}
	src := filepath.Join(srcDir, "layer-02.png")
	dst := filepath.Join(dstDir, "layer-02.png")
	writeFile(t, src, "legacy")
	writeFile(t, dst, "different")

	layers := migrateParallaxFolder(wall, legacyParallaxWall{Mode: "manual"},
		[]legacyParallaxLayer{{Out: src, Label: "Layer 2", Depth: 0.7}})

	if len(layers) != 2 || layers[1].Out != src {
		t.Fatalf("conflicting layer path was rewritten: %+v", layers)
	}
	srcBody, _ := os.ReadFile(src)
	dstBody, _ := os.ReadFile(dst)
	if string(srcBody) != "legacy" || string(dstBody) != "different" {
		t.Fatalf("conflicting files were modified: src=%q dst=%q", srcBody, dstBody)
	}
}

// TestStageRyogamiFrameWake pins the bridge trigger: a frame showing a new
// wallpaper, one that lost its subject fold, or a live claim wakes the stage
// worker, while the frame our own publish produces (same sources, subject
// folded) stays quiet, so the publish-subscribe loop settles.
func TestStageRyogamiFrameWake(t *testing.T) {
	d := &daemon{stageSig: make(chan struct{}, 1)}
	woke := func() bool {
		select {
		case <-d.stageSig:
			return true
		default:
			return false
		}
	}
	feed := func(js string) { d.consumeRyogamiFrames(strings.NewReader(js + "\n")) }

	feed(`{"default":{"path":"/w/a.png"},"outputs":{}}`)
	if !woke() {
		t.Fatal("a new wallpaper did not wake the stage worker")
	}
	feed(`{"default":{"path":"/w/a.png","depth":"/d/a-subject.png"},"outputs":{}}`)
	if woke() {
		t.Fatal("our own subject fold woke the worker again")
	}
	feed(`{"default":{"path":"/w/a.png"},"outputs":{}}`)
	if !woke() {
		t.Fatal("a re-set that dropped the subject fold did not wake the worker")
	}
	feed(`{"default":{"path":"/w/a.png","live":true},"outputs":{}}`)
	if !woke() {
		t.Fatal("a live claim did not wake the worker")
	}
}

func TestPreviewFrameDoesNotReachCommittedConsumers(t *testing.T) {
	d := &daemon{stageSig: make(chan struct{}, 1), paintSig: make(chan struct{}, 1)}
	feed := func(js string) { d.consumeRyogamiFrames(strings.NewReader(js + "\n")) }
	drain := func(ch chan struct{}) {
		select {
		case <-ch:
		default:
		}
	}
	quiet := func(ch chan struct{}) bool {
		select {
		case <-ch:
			return false
		default:
			return true
		}
	}

	feed(`{"default":{"path":"/w/base.png"},"outputs":{"DP-1":{"path":"/w/left.png"}}}`)
	drain(d.stageSig)
	drain(d.paintSig)
	feed(`{"default":{"path":"/w/preview.png","preview":true},"outputs":{}}`)
	if !quiet(d.stageSig) || !quiet(d.paintSig) {
		t.Fatal("broadcast preview woke a committed wallpaper consumer")
	}
	if got := d.currentWall(); got != "/w/base.png" {
		t.Fatalf("current wall changed to preview %q", got)
	}

	feed(`{"default":{"path":"/w/base.png"},"outputs":{"DP-1":{"path":"/w/preview.png","preview":true}}}`)
	if !quiet(d.stageSig) || !quiet(d.paintSig) {
		t.Fatal("per-output preview woke a committed wallpaper consumer")
	}
	if got := d.wallFrame().Outputs["DP-1"].Path; got != "/w/left.png" {
		t.Fatalf("committed output changed to preview %q", got)
	}
}

func TestStageLegacyMigrationV3(t *testing.T) {
	home := stageHome(t)
	if err := os.MkdirAll(filepath.Join(stateDir(), "ryoku"), 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(cfg, 0o755); err != nil {
		t.Fatal(err)
	}

	wpA := filepath.Join(home, "walls", "a.png") // depth-only
	wpB := filepath.Join(home, "walls", "b.png") // parallax auto
	if err := os.MkdirAll(filepath.Dir(wpA), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, wpA, "A")
	writeFile(t, wpB, "B")

	// Retired depth-walls.json (per-wall opt-in) + its cutout.
	writeFile(t, legacyDepthWallsPath(), `{"current":true,"walls":{"`+wpA+`":true}}`)
	depthPNG := filepath.Join(legacyDepthDir(), "a-depth.png")
	if err := os.MkdirAll(filepath.Dir(depthPNG), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, depthPNG, "OLDCUT")

	// Retired parallax layers.pz + its folder. The scene lifts layer 2 in front
	// of the widgets; the subject (layer 1) stays behind.
	pbDir := filepath.Join(legacyParallaxDir(), "b")
	if err := os.MkdirAll(pbDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(pbDir, "layer-01.png"), "OLDSUBJECT")
	writeFile(t, filepath.Join(pbDir, "layer-02.png"), "OLDLAYER2")
	writeFile(t, filepath.Join(pbDir, "background.png"), "OLDBG")
	lp := legacyParallaxWalls{
		Walls: map[string]legacyParallaxWall{
			wpB: {Enabled: true, Mode: "auto", Scene: []string{"wallpaper", "layer:1", "widget:clock", "layer:2"}},
		},
		Layers: map[string][]legacyParallaxLayer{
			wpB: {
				{Out: filepath.Join(pbDir, "layer-01.png"), Rev: 1, Label: "subject", Depth: 0.5},
				{Out: filepath.Join(pbDir, "layer-02.png"), Rev: 2, Label: "Layer 2", Depth: 0.7},
			},
		},
	}
	lpBytes, _ := json.Marshal(lp)
	writeFile(t, legacyLayersPath(), string(lpBytes))

	// Retired settings: parallax's model+matting wins the derived quality (fine),
	// and a user's front from depth.json survives.
	writeFile(t, filepath.Join(cfg, "depth.json"), `{"model":"u2netp","alphaMatting":false,"front":["clock"]}`)
	writeFile(t, filepath.Join(cfg, "parallax.json"), `{"mode":"auto","model":"birefnet-general-lite","alphaMatting":true}`)

	migrateStage()

	reg := loadStageWalls()
	if reg.Version != 3 {
		t.Fatalf("registry version = %d, want 3", reg.Version)
	}
	if reg.Walls[wpA].Effect != stageEffectDepth {
		t.Fatalf("wpA effect = %v, want depth", reg.Walls[wpA].Effect)
	}
	if a := reg.Walls[wpA]; len(a.Layers) == 0 ||
		filepath.Base(a.Layers[0].Out) != "subject.png" || a.Layers[0].Label != "Subject" {
		t.Fatalf("wpA layers[0] is not the subject: %+v", a.Layers)
	}
	b := reg.Walls[wpB]
	if b.Effect != stageEffectParallax {
		t.Fatalf("wpB effect = %v, want parallax", b.Effect)
	}
	if len(b.Layers) != 2 {
		t.Fatalf("wpB layers = %d, want 2", len(b.Layers))
	}
	if filepath.Base(b.Layers[0].Out) != "subject.png" || b.Layers[0].Label != "Subject" {
		t.Fatalf("wpB layer[0] is not the rewritten subject: %+v", b.Layers[0])
	}
	if b.Layers[0].Depth != 0.5 {
		t.Fatalf("wpB subject depth = %v, want 0.5 (from the legacy layer)", b.Layers[0].Depth)
	}
	if filepath.Base(b.Layers[1].Out) != "layer-02.png" {
		t.Fatalf("wpB layer[1] out = %v", b.Layers[1].Out)
	}
	// Scene reduction: the subject (layer:1) is behind the widget; layer 2 is in front.
	if b.Layers[0].Front {
		t.Fatalf("wpB subject should be behind the widgets: %+v", b.Layers[0])
	}
	if !b.Layers[1].Front {
		t.Fatalf("wpB layer 2 should be in front (listed after the widget): %+v", b.Layers[1])
	}

	// Artifact tree: renamed, sources gone.
	if !isFile(stageSubjectOut(wpA)) {
		t.Fatal("depth cutout did not become Stage/a/subject.png")
	}
	if isFile(depthPNG) {
		t.Fatal("old depth cutout was copied, not moved")
	}
	if !isFile(stageSubjectOut(wpB)) || !isFile(stageBackgroundOut(wpB)) ||
		!isFile(filepath.Join(stageWallDir(wpB), "layer-02.png")) {
		t.Fatal("parallax folder did not move whole into Stage/b/")
	}
	if isDir(pbDir) {
		t.Fatal("old parallax folder was copied, not moved")
	}

	sb, err := os.ReadFile(filepath.Join(cfg, "stage.json"))
	if err != nil {
		t.Fatalf("stage.json not written: %v", err)
	}
	var settings map[string]any
	if err := json.Unmarshal(sb, &settings); err != nil {
		t.Fatal(err)
	}
	if settings["version"] != 3.0 {
		t.Fatalf("settings version = %v, want 3", settings["version"])
	}
	for _, mode := range []string{"depth", "parallax"} {
		modeSettings, _ := settings[mode].(map[string]any)
		cut, _ := modeSettings["cut"].(map[string]any)
		if cut["model"] != "birefnet-general-lite" || cut["matting"] != true {
			t.Fatalf("%s cut did not inherit fine quality: %v", mode, cut)
		}
		front, _ := modeSettings["front"].([]any)
		if len(front) != 1 || front[0] != "clock" {
			t.Fatalf("%s front = %v, want [clock]", mode, modeSettings["front"])
		}
	}
	for _, gone := range []string{"quality", "models", "depthModel", "edge", "motion", "front"} {
		if _, ok := settings[gone]; ok {
			t.Fatalf("v3 stage.json still carries %q: %s", gone, sb)
		}
	}
	if !isFile(stageMigrationMarker()) || !isFile(stageV3MigrationMarker()) {
		t.Fatal("v2 or v3 migration marker not written")
	}
	before, _ := os.ReadFile(stageWallsPath())
	migrateStage()
	after, _ := os.ReadFile(stageWallsPath())
	if string(before) != string(after) {
		t.Fatal("second migration mutated the registry (not a no-op)")
	}
}

// TestStageLegacySettingsFoldV2 pins the retired depth.json + parallax.json fold
// when a stable box has no stage.json: the depth scalar wins over a parallax
// per-layer array, feather -> edge, the higher model+matting tier wins the
// quality (fine), the user's shadow 0.85 intact, and the parallax motion
// globals keep their tuning on their v2 keys.
func TestStageLegacySettingsFoldV2(t *testing.T) {
	home := stageHome(t)
	cfg := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(cfg, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(cfg, "parallax.json"),
		`{"feather":[0],"lift":[0],"shadow":[0],"shadowAngle":[331],"model":"u2netp",`+
			`"mouseEnabled":false,"mouseSensitivity":1.4,"mouseRange":0.7,"wallpaperParallax":0.4}`)
	writeFile(t, filepath.Join(cfg, "depth.json"),
		`{"feather":0.15,"lift":1,"shadow":0.85,"model":"birefnet-general-lite","alphaMatting":true}`)

	if err := migrateStageSettings(); err != nil {
		t.Fatal(err)
	}

	b, err := os.ReadFile(filepath.Join(cfg, "stage.json"))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	if got["shadow"] != 0.85 {
		t.Fatalf("shadow = %v, want the depth scalar 0.85", got["shadow"])
	}
	if got["edge"] != 0.15 {
		t.Fatalf("edge = %v, want feather 0.15", got["edge"])
	}
	if got["quality"] != "fine" {
		t.Fatalf("quality = %v, want fine (birefnet+matting)", got["quality"])
	}
	if _, isList := got["shadowAngle"].([]any); isList {
		t.Fatalf("shadowAngle folded as a list: %s", b)
	}
	if _, ok := got["feather"]; ok {
		t.Fatalf("feather not dropped: %s", b)
	}
	motion, _ := got["motion"].(map[string]any)
	if motion["amount"] != "subtle" || motion["mouse"] != false {
		t.Fatalf("mouse:false must fold to amount=subtle with mouse carried: %v", motion)
	}
	if motion["sensitivity"] != 1.4 || motion["range"] != 0.7 || motion["backdrop"] != 0.4 {
		t.Fatalf("parallax motion globals must carry over: %v", motion)
	}
}

// TestStageDepthSample pins the depth-pick sampler (docs/stage.md "Widgets on
// the depth"): Fill maps the output straight onto the map, Cover applies the
// centre crop DepthMeshGeometry's UVs use, and the daemon's verb declines a
// wall without a depth map instead of zeroing.
func TestStageDepthSample(t *testing.T) {
	home := stageHome(t)
	wall := filepath.Join(home, "wall.png")
	img := image.NewGray16(image.Rect(0, 0, 16, 2))
	for x := 0; x < 16; x++ {
		v := uint16(math.Round(float64(x) / 15 * 65535))
		img.SetGray16(x, 0, color.Gray16{Y: v})
		img.SetGray16(x, 1, color.Gray16{Y: v})
	}
	if err := os.MkdirAll(stageWallDir(wall), 0o755); err != nil {
		t.Fatal(err)
	}
	out, err := os.Create(stageDepthOut(wall))
	if err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(out, img); err != nil {
		t.Fatal(err)
	}
	out.Close()

	cases := []struct {
		nx, ny, w, h float64
		fit          string
		want         float64
		tol          float64
	}{
		{0, 0.5, 1920, 1080, "Fill", 0, 0.01},
		{1, 0.5, 1920, 1080, "Fill", 1, 0.01},
		{0.5, 0.5, 1920, 1080, "Fill", 0.5, 0.02},
		{0, 0.5, 1000, 1000, "Cover", 0.4375, 0.02},
		{1, 0.5, 1000, 1000, "Cover", 0.5625, 0.02},
		{0.5, 0.5, 1000, 1000, "Cover", 0.5, 0.01},
	}
	for _, c := range cases {
		got, err := stageDepthSample(wall, c.nx, c.ny, c.w, c.h, c.fit)
		if err != nil {
			t.Fatalf("sample(%v %v %v %v %s): %v", c.nx, c.ny, c.w, c.h, c.fit, err)
		}
		if math.Abs(got-c.want) > c.tol {
			t.Fatalf("sample(%v %v %v %v %s) = %v, want %v ±%v",
				c.nx, c.ny, c.w, c.h, c.fit, got, c.want, c.tol)
		}
	}

	if _, err := stageDepthSample(filepath.Join(home, "other.png"),
		0.5, 0.5, 100, 100, "Fill"); err == nil {
		t.Fatal("sampling a wall without a depth map did not error")
	}
}
