package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func stageTestDaemon(wall string) *daemon {
	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.showWall(wall)
	return d
}

func waitForStageJob(t *testing.T, d *daemon) *stageJobFrame {
	t.Helper()
	deadline := time.Now().Add(4 * time.Second)
	for time.Now().Before(deadline) {
		job, _ := d.stageJobSnapshot()
		if job != nil {
			return job
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("stage job did not start")
	return nil
}

func waitForStageEngine(t *testing.T, d *daemon, logFile, verb string) {
	t.Helper()
	deadline := time.Now().Add(4 * time.Second)
	for time.Now().Before(deadline) {
		d.stageJobMu.Lock()
		pid := 0
		if d.stageJob != nil {
			pid = d.stageJob.pid
		}
		d.stageJobMu.Unlock()
		if pid > 0 && countCalls(logFile, verb) > 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("stage engine did not start %s", verb)
}

func waitForStageIdle(t *testing.T, d *daemon) *stageJobResult {
	t.Helper()
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		job, last := d.stageJobSnapshot()
		if job == nil && last != nil {
			return last
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("stage job did not finish")
	return nil
}

func stageEngineVerbs(t *testing.T, logFile string) []string {
	t.Helper()
	body, err := os.ReadFile(logFile)
	if err != nil {
		return nil
	}
	var verbs []string
	for _, line := range strings.Split(strings.TrimSpace(string(body)), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		switch fields[0] {
		case "cut", "inpaint", "depth":
			verbs = append(verbs, fields[0])
		}
	}
	return verbs
}

func TestStageGenerateRunsNeededStepsTransactionally(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	t.Setenv("STAGE_STUB_DEPTH", "1")
	configDir := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(configDir, "stage.json"), `{
  "version": 3,
  "parallax": {"cut": {"model": "silueta", "matting": true}, "depthBackdrop": true},
  "spatial": {"model": "base"}
}`)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	d := stageTestDaemon(wall)

	if got := d.dispatch("stage set-effect parallax"); got != "ok" {
		t.Fatalf("set-effect = %q", got)
	}
	if got := d.dispatch("stage generate"); got != "ok" {
		t.Fatalf("generate = %q", got)
	}
	last := waitForStageIdle(t, d)
	if last.State != "done" || last.Step != "" {
		t.Fatalf("last result = %+v", last)
	}
	if got := strings.Join(stageEngineVerbs(t, logFile), ","); got != "cut,inpaint,depth" {
		t.Fatalf("engine step order = %q", got)
	}
	calls, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatal(err)
	}
	position := -1
	for _, needle := range []string{"check silueta", "depth-check --model base", "cut ", "inpaint ", "depth "} {
		next := strings.Index(string(calls), needle)
		if next <= position {
			t.Fatalf("probe and step order for %q in %q", needle, calls)
		}
		position = next
	}
	for _, artifact := range []string{stageSubjectOut(wall), stageBackgroundOut(wall), stageDepthOut(wall)} {
		if !isFile(artifact) {
			t.Fatalf("job did not commit %s", artifact)
		}
	}
	index := loadStageIndex(wall)
	if index.Model != "silueta" || !index.Matting || index.DepthModel != "base" {
		t.Fatalf("provenance = %+v", index)
	}
	if matches, _ := filepath.Glob(filepath.Join(stageWallDir(wall), ".job-*")); len(matches) != 0 {
		t.Fatalf("completed job left transactions: %v", matches)
	}
}

func TestStageGenerateSkipsReadySteps(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	t.Setenv("STAGE_STUB_DEPTH", "1")
	configDir := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(configDir, "stage.json"),
		`{"version":3,"parallax":{"cut":{"model":"u2netp"},"depthBackdrop":true},"spatial":{"model":"large"}}`)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	if err := os.MkdirAll(stageWallDir(wall), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, stageSubjectOut(wall), "subject")
	writeFile(t, stageDepthOut(wall), "old depth")
	future := time.Now().Add(time.Minute)
	for _, path := range []string{stageSubjectOut(wall), stageDepthOut(wall)} {
		if err := os.Chtimes(path, future, future); err != nil {
			t.Fatal(err)
		}
	}
	if err := writeJSONFileAtomic(stageIndexPath(wall), stageIndex{
		Source: wall, Model: "u2netp", DepthModel: "small",
	}); err != nil {
		t.Fatal(err)
	}
	if err := saveStageWalls(stageWalls{Walls: map[string]stageWall{
		wall: {Effect: stageEffectParallax},
	}}); err != nil {
		t.Fatal(err)
	}
	d := stageTestDaemon(wall)
	if got := d.dispatch("stage generate"); got != "ok" {
		t.Fatal(got)
	}
	if last := waitForStageIdle(t, d); last.State != "done" {
		t.Fatalf("mixed readiness result = %+v", last)
	}
	if got := strings.Join(stageEngineVerbs(t, logFile), ","); got != "inpaint,depth" {
		t.Fatalf("mixed readiness steps = %q", got)
	}
	index := loadStageIndex(wall)
	if index.Model != "u2netp" || index.DepthModel != "large" {
		t.Fatalf("mixed readiness provenance = %+v", index)
	}
}

func TestStageBusyRefusesSecondJob(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	t.Setenv("STAGE_STUB_SLEEP", "3")
	t.Setenv("STAGE_STUB_SLEEP_CMD", "cut")
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	d := stageTestDaemon(wall)
	if got := d.dispatch("stage set-effect depth"); got != "ok" {
		t.Fatal(got)
	}
	if got := d.dispatch("stage generate"); got != "ok" {
		t.Fatal(got)
	}
	waitForStageEngine(t, d, logFile, "cut")
	if got := d.dispatch("stage refresh"); got != "err stage refresh: busy" {
		t.Fatalf("second job = %q", got)
	}
	d.dispatch("stage cancel --force")
	last := waitForStageIdle(t, d)
	if last.State != "cancelled" {
		t.Fatalf("force-cancel result = %+v", last)
	}
}

func TestStageFailedStepKeepsOldFilesAndNeverRetries(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	t.Setenv("STAGE_STUB_FAIL_CMD", "inpaint")
	t.Setenv("STAGE_STUB_FAIL_LINE", "fill exploded")
	configDir := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(configDir, "stage.json"),
		`{"version":3,"parallax":{"depthBackdrop":false}}`)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	if err := os.MkdirAll(stageWallDir(wall), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, stageSubjectOut(wall), "OLD SUBJECT")
	writeFile(t, stageBackgroundOut(wall), "OLD BACKGROUND")
	writeFile(t, stageIndexPath(wall), `{"source":"old","model":"silueta","matting":true}`)
	if err := saveStageWalls(stageWalls{Walls: map[string]stageWall{
		wall: {Effect: stageEffectParallax},
	}}); err != nil {
		t.Fatal(err)
	}
	d := stageTestDaemon(wall)

	if got := d.dispatch("stage refresh"); got != "ok" {
		t.Fatal(got)
	}
	last := waitForStageIdle(t, d)
	if last.State != "failed" || last.Step != stageStepFill || last.Error != "engine-failed" || last.Detail != "fill exploded" {
		t.Fatalf("failed result = %+v", last)
	}
	for path, want := range map[string]string{
		stageSubjectOut(wall):    "OLD SUBJECT",
		stageBackgroundOut(wall): "OLD BACKGROUND",
	} {
		body, err := os.ReadFile(path)
		if err != nil || string(body) != want {
			t.Fatalf("%s = %q, %v", path, body, err)
		}
	}
	index := loadStageIndex(wall)
	if index.Source != "old" || index.Model != "silueta" || !index.Matting {
		t.Fatalf("failed transaction changed provenance: %+v", index)
	}
	before := len(stageEngineVerbs(t, logFile))
	d.reconcileStage()
	d.scheduleStage()
	d.reconcileStage()
	if after := len(stageEngineVerbs(t, logFile)); after != before {
		t.Fatalf("publish wakes retried a failed job: before=%d after=%d", before, after)
	}
}

func TestStageGracefulCancelEndsCancelled(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	t.Setenv("STAGE_STUB_SLEEP", "1")
	t.Setenv("STAGE_STUB_SLEEP_CMD", "cut")
	t.Setenv("STAGE_STUB_IGNORE_TERM", "1")
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	d := stageTestDaemon(wall)
	d.dispatch("stage set-effect depth")
	if got := d.dispatch("stage generate"); got != "ok" {
		t.Fatal(got)
	}
	waitForStageEngine(t, d, logFile, "cut")
	if got := d.dispatch("stage cancel"); got != "ok" {
		t.Fatal(got)
	}
	job, _ := d.stageJobSnapshot()
	if job == nil || job.State != "stopping" {
		t.Fatalf("cancel did not publish stopping: %+v", job)
	}
	last := waitForStageIdle(t, d)
	if last.State != "cancelled" || isFile(stageSubjectOut(wall)) {
		t.Fatalf("cancel result = %+v subject=%v", last, isFile(stageSubjectOut(wall)))
	}
}

func TestStageForceCancelFreesRunnerAndBlocksLateCommit(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	t.Setenv("STAGE_STUB_SLEEP", "3")
	t.Setenv("STAGE_STUB_SLEEP_CMD", "cut")
	t.Setenv("STAGE_STUB_IGNORE_TERM", "1")
	first := filepath.Join(home, "first.png")
	second := filepath.Join(home, "second.png")
	writeFile(t, first, "first")
	writeFile(t, second, "second")
	d := stageTestDaemon(first)
	d.dispatch("stage set-effect depth")
	if got := d.dispatch("stage generate"); got != "ok" {
		t.Fatal(got)
	}
	waitForStageEngine(t, d, logFile, "cut")
	started := time.Now()
	if got := d.dispatch("stage cancel --force"); got != "ok" {
		t.Fatal(got)
	}
	if elapsed := time.Since(started); elapsed > time.Second {
		t.Fatalf("force cancel took %s", elapsed)
	}
	if job, last := d.stageJobSnapshot(); job != nil || last == nil || last.State != "cancelled" {
		t.Fatalf("force cancel did not free runner: job=%+v last=%+v", job, last)
	}

	t.Setenv("STAGE_STUB_SLEEP", "")
	t.Setenv("STAGE_STUB_IGNORE_TERM", "")
	if got := d.dispatch("stage set-effect depth -- " + second); got != "ok" {
		t.Fatal(got)
	}
	if got := d.dispatch("stage generate -- " + second); got != "ok" {
		t.Fatalf("new job after force cancel = %q", got)
	}
	if last := waitForStageIdle(t, d); last.State != "done" || last.Wall != second {
		t.Fatalf("new job result = %+v", last)
	}
	time.Sleep(100 * time.Millisecond)
	if isFile(stageSubjectOut(first)) {
		t.Fatal("force-cancelled job committed after the runner was freed")
	}
	if !isFile(stageSubjectOut(second)) {
		t.Fatal("replacement job did not commit")
	}
}

func TestStageRefreshCutAlsoRefillsParallax(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	configDir := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(configDir, "stage.json"),
		`{"version":3,"parallax":{"depthBackdrop":false}}`)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	if err := saveStageWalls(stageWalls{Walls: map[string]stageWall{
		wall: {Effect: stageEffectParallax},
	}}); err != nil {
		t.Fatal(err)
	}
	d := stageTestDaemon(wall)
	if got := d.dispatch("stage refresh cut"); got != "ok" {
		t.Fatal(got)
	}
	waitForStageIdle(t, d)
	if got := strings.Join(stageEngineVerbs(t, logFile), ","); got != "cut,inpaint" {
		t.Fatalf("refresh cut steps = %q", got)
	}
}

func TestStageReadinessStates(t *testing.T) {
	home := stageHome(t)
	configDir := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(configDir, "stage.json"), `{
  "version":3,
  "parallax":{"cut":{"model":"u2netp","matting":false},"depthBackdrop":true},
  "spatial":{"model":"large"}
}`)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	d := stageTestDaemon(wall)
	if got := d.dispatch("stage set-effect parallax"); got != "ok" {
		t.Fatal(got)
	}
	steps := d.buildStageFrame().Walls[wall].Steps
	for _, step := range []stageStep{stageStepCut, stageStepFill, stageStepDepth} {
		if got := stageStepStateFor(steps, step); got != stageStateMissing {
			t.Fatalf("%s initial state = %q", step, got)
		}
	}

	if err := os.MkdirAll(stageWallDir(wall), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{stageSubjectOut(wall), stageBackgroundOut(wall), stageDepthOut(wall)} {
		writeFile(t, path, path)
	}
	wallTime := time.Now()
	artifactTime := wallTime.Add(time.Minute)
	if err := os.Chtimes(wall, wallTime, wallTime); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{stageSubjectOut(wall), stageBackgroundOut(wall), stageDepthOut(wall)} {
		if err := os.Chtimes(path, artifactTime, artifactTime); err != nil {
			t.Fatal(err)
		}
	}
	if err := writeJSONFileAtomic(stageIndexPath(wall), stageIndex{
		Source: wall, Model: "u2netp", DepthModel: "large",
	}); err != nil {
		t.Fatal(err)
	}
	steps = d.buildStageFrame().Walls[wall].Steps
	for _, step := range []stageStep{stageStepCut, stageStepFill, stageStepDepth} {
		if got := stageStepStateFor(steps, step); got != stageStateReady {
			t.Fatalf("%s ready state = %q", step, got)
		}
	}

	old := wallTime.Add(-time.Minute)
	if err := os.Chtimes(stageSubjectOut(wall), old, old); err != nil {
		t.Fatal(err)
	}
	if got := stageStepStateFor(d.buildStageFrame().Walls[wall].Steps, stageStepCut); got != stageStateStale {
		t.Fatalf("cut stale state = %q", got)
	}
	if err := os.Chtimes(stageSubjectOut(wall), artifactTime.Add(time.Minute), artifactTime.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if got := stageStepStateFor(d.buildStageFrame().Walls[wall].Steps, stageStepFill); got != stageStateStale {
		t.Fatalf("fill after re-cut = %q, want stale", got)
	}
	if err := writeJSONFileAtomic(stageIndexPath(wall), stageIndex{
		Source: wall, Model: "silueta", DepthModel: "small",
	}); err != nil {
		t.Fatal(err)
	}
	steps = d.buildStageFrame().Walls[wall].Steps
	if got := stageStepStateFor(steps, stageStepCut); got != stageStateOutdated {
		t.Fatalf("cut model state = %q", got)
	}
	if got := stageStepStateFor(steps, stageStepDepth); got != stageStateOutdated {
		t.Fatalf("depth model state = %q", got)
	}
}

func TestStageGenerateTargetsScopedWallpaper(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	defaultWall := filepath.Join(home, "default.png")
	outputWall := filepath.Join(home, "output wall.png")
	writeFile(t, defaultWall, "default")
	writeFile(t, outputWall, "output")
	d := stageTestDaemon(defaultWall)
	if got := d.dispatch("stage set-effect depth -- " + outputWall); got != "ok" {
		t.Fatal(got)
	}
	if got := d.dispatch("stage generate -- " + outputWall); got != "ok" {
		t.Fatal(got)
	}
	if last := waitForStageIdle(t, d); last.Wall != outputWall || last.State != "done" {
		t.Fatalf("scoped job result = %+v", last)
	}
	if isFile(stageSubjectOut(defaultWall)) || !isFile(stageSubjectOut(outputWall)) {
		t.Fatalf("scoped outputs default=%v output=%v", isFile(stageSubjectOut(defaultWall)), isFile(stageSubjectOut(outputWall)))
	}
	calls, err := os.ReadFile(logFile)
	if err != nil || !strings.Contains(string(calls), "cut "+outputWall+" ") {
		t.Fatalf("scoped calls = %q, %v", calls, err)
	}
}

func TestStageCutRegionPassesBoxAndAddsLayer(t *testing.T) {
	home := stageHome(t)
	logFile := writeStageStub(t)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	d := stageTestDaemon(wall)
	if got := d.dispatch("stage cut-region 0.1 0.2 0.3 0.4"); got != "ok" {
		t.Fatal(got)
	}
	last := waitForStageIdle(t, d)
	if last.State != "done" || last.Kind != "layer" {
		t.Fatalf("region job result = %+v", last)
	}
	calls, err := os.ReadFile(logFile)
	if err != nil || !strings.Contains(string(calls), "--region 0.1,0.2,0.3,0.4") {
		t.Fatalf("region call = %q, %v", calls, err)
	}
	if !isFile(filepath.Join(stageWallDir(wall), "layer-01.png")) {
		t.Fatal("region job did not commit a manual layer")
	}
}

func TestStageJobMapsCapturedEngineError(t *testing.T) {
	home := stageHome(t)
	writeStageStub(t)
	t.Setenv("STAGE_STUB_FAIL_CMD", "depth")
	t.Setenv("STAGE_STUB_FAIL_LINE", "image is too large for depth inference")
	t.Setenv("STAGE_STUB_DEPTH", "1")
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	d := stageTestDaemon(wall)
	d.dispatch("stage set-effect spatial")
	if got := d.dispatch("stage generate"); got != "ok" {
		t.Fatal(got)
	}
	last := waitForStageIdle(t, d)
	if last.State != "failed" || last.Error != "too-large" || last.Detail != "image is too large for depth inference" {
		t.Fatalf("mapped result = %+v", last)
	}
}

func TestStageStartupRemovesAbandonedJobs(t *testing.T) {
	home := stageHome(t)
	writeStageStub(t)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	abandoned := filepath.Join(stageWallDir(wall), ".job-41")
	if err := os.MkdirAll(abandoned, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(abandoned, "subject.png"), "partial")
	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.startStage()
	if isDir(abandoned) {
		t.Fatal("startStage left an abandoned transaction")
	}
}

func TestStageGenerateNothingToDo(t *testing.T) {
	home := stageHome(t)
	writeStageStub(t)
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	if err := os.MkdirAll(stageWallDir(wall), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, stageSubjectOut(wall), "subject")
	future := time.Now().Add(time.Minute)
	if err := os.Chtimes(stageSubjectOut(wall), future, future); err != nil {
		t.Fatal(err)
	}
	if err := writeJSONFileAtomic(stageIndexPath(wall), stageIndex{
		Source: wall, Model: "u2netp",
	}); err != nil {
		t.Fatal(err)
	}
	if err := saveStageWalls(stageWalls{Walls: map[string]stageWall{
		wall: {Effect: stageEffectDepth},
	}}); err != nil {
		t.Fatal(err)
	}
	d := stageTestDaemon(wall)
	if got := d.dispatch("stage generate"); got != "ok nothing to do" {
		t.Fatalf("generate ready scene = %q", got)
	}
	if job, _ := d.stageJobSnapshot(); job != nil {
		t.Fatalf("nothing-to-do started %+v", job)
	}
}

func TestStageJobFrameCarriesCurrentStep(t *testing.T) {
	home := stageHome(t)
	writeStageStub(t)
	t.Setenv("STAGE_STUB_SLEEP", "3")
	t.Setenv("STAGE_STUB_SLEEP_CMD", "cut")
	wall := filepath.Join(home, "wall.png")
	writeFile(t, wall, "wall")
	d := stageTestDaemon(wall)
	d.dispatch("stage set-effect depth")
	d.dispatch("stage generate")
	job := waitForStageJob(t, d)
	if job.Kind != "scene" || job.Mode != stageEffectDepth || job.Step != stageStepCut ||
		job.Model != "u2netp" || len(job.Steps) != 1 || job.Started == 0 || job.StepStarted == 0 {
		t.Fatalf("running frame = %+v", job)
	}
	d.dispatch("stage cancel --force")
	waitForStageIdle(t, d)
}

func TestStageStrayEngineMatch(t *testing.T) {
	const engine = "/usr/bin/ryostage"
	const root = "/home/u/Pictures/Stage/"
	argv := func(args ...string) []byte { return []byte(strings.Join(args, "\x00") + "\x00") }
	cases := []struct {
		name    string
		cmdline []byte
		want    bool
	}{
		{"engine cut into a job dir", argv("bash", engine, "cut", "/w/a.png", root+"a/.job-3/subject.png", "--model", "u2netp"), true},
		{"engine inpaint", argv("bash", engine, "inpaint", "/w/a.png", root+"a/subject.png", root+"a/.job-3/background.png"), true},
		{"checkout engine by name", argv("bash", "/home/u/ryoku/shell/scripts/ryostage", "depth", "/w/a.png", root+"a/.job-1/depth.png"), true},
		{"editor on a stage file", argv("nvim", root+"a/ryostage-notes.txt"), false},
		{"viewer on a cut", argv("imv", root+"a/subject.png"), false},
		{"engine download", argv("bash", engine, "install", "u2netp"), false},
		{"engine cut outside the stage root", argv("bash", engine, "cut", "/w/a.png", "/tmp/out.png"), false},
	}
	for _, tc := range cases {
		if got := isStageEngineRun(tc.cmdline, engine, root); got != tc.want {
			t.Errorf("%s: match = %v, want %v", tc.name, got, tc.want)
		}
	}
}
