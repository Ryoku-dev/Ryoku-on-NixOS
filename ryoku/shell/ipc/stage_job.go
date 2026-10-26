package main

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type stageStep string

type stageStepState string

const (
	stageStepCut   stageStep = "cut"
	stageStepFill  stageStep = "fill"
	stageStepDepth stageStep = "depth"

	stageStateMissing  stageStepState = "missing"
	stageStateStale    stageStepState = "stale"
	stageStateOutdated stageStepState = "outdated"
	stageStateReady    stageStepState = "ready"
)

const (
	stageCutTimeout   = 20 * time.Minute
	stageFillTimeout  = 5 * time.Minute
	stageDepthTimeout = 20 * time.Minute
	stageProbeTimeout = 30 * time.Second
)

type stageStepFrame struct {
	Step        stageStep      `json:"step"`
	State       stageStepState `json:"state"`
	Model       string         `json:"model,omitempty"`
	Matting     *bool          `json:"matting,omitempty"`
	Want        string         `json:"want,omitempty"`
	WantMatting *bool          `json:"wantMatting,omitempty"`
}

type stageJobFrame struct {
	ID          int64       `json:"id"`
	Wall        string      `json:"wall"`
	Kind        string      `json:"kind"`
	Mode        stageEffect `json:"mode"`
	Steps       []stageStep `json:"steps"`
	Step        stageStep   `json:"step"`
	Index       int         `json:"index"`
	Model       string      `json:"model"`
	Picture     string      `json:"picture"`
	Region      bool        `json:"region"`
	State       string      `json:"state"`
	Started     int64       `json:"started"`
	StepStarted int64       `json:"stepStarted"`
}

type stageJobResult struct {
	ID       int64       `json:"id"`
	Wall     string      `json:"wall"`
	Kind     string      `json:"kind"`
	Mode     stageEffect `json:"mode"`
	State    string      `json:"state"`
	Step     stageStep   `json:"step"`
	Error    string      `json:"error,omitempty"`
	Detail   string      `json:"detail,omitempty"`
	Limit    int         `json:"limit,omitempty"`
	Model    string      `json:"model,omitempty"`
	Finished int64       `json:"finished"`
}

type stageJobRun struct {
	frame        stageJobFrame
	tempDir      string
	cut          stageCut
	spatialModel string
	region       string
	pid          int
	committed    bool
}

type stageEngineResult struct {
	err      error
	stdout   string
	stderr   string
	timedOut bool
}

type stageJobError struct {
	code   string
	detail string
	limit  int
	model  string
}

func (e *stageJobError) Error() string {
	if e.detail != "" {
		return e.detail
	}
	return e.code
}

func stageFileModTime(path string) time.Time {
	info, err := os.Stat(path)
	if err != nil {
		return time.Time{}
	}
	return info.ModTime()
}

func stageStepsForMode(mode stageEffect) []stageStep {
	switch mode {
	case stageEffectDepth:
		return []stageStep{stageStepCut}
	case stageEffectParallax:
		steps := []stageStep{stageStepCut, stageStepFill}
		if stageDepthBackdrop() {
			steps = append(steps, stageStepDepth)
		}
		return steps
	case stageEffectSpatial:
		return []stageStep{stageStepDepth}
	default:
		return []stageStep{}
	}
}

func stageStepsForWall(wall string, mode stageEffect) []stageStepFrame {
	steps := stageStepsForMode(mode)
	out := make([]stageStepFrame, 0, len(steps))
	wallTime := stageFileModTime(wall)
	subjectTime := stageFileModTime(stageSubjectOut(wall))
	index := loadStageIndex(wall)
	cut := stageCutFor(mode)
	spatialModel := stageSpatialModel()
	for _, step := range steps {
		frame := stageStepFrame{Step: step}
		switch step {
		case stageStepCut:
			frame.Want = cut.model
			frame.WantMatting = new(cut.matting)
			switch {
			case subjectTime.IsZero():
				frame.State = stageStateMissing
			case !wallTime.IsZero() && subjectTime.Before(wallTime):
				frame.State = stageStateStale
			case index.Model != "" && (index.Model != cut.model || index.Matting != cut.matting):
				frame.State = stageStateOutdated
			default:
				frame.State = stageStateReady
			}
			if index.Model != "" {
				frame.Model = index.Model
				frame.Matting = new(index.Matting)
			}
		case stageStepFill:
			backgroundTime := stageFileModTime(stageBackgroundOut(wall))
			switch {
			case backgroundTime.IsZero():
				frame.State = stageStateMissing
			case (!wallTime.IsZero() && backgroundTime.Before(wallTime)) ||
				(!subjectTime.IsZero() && backgroundTime.Before(subjectTime)):
				frame.State = stageStateStale
			default:
				frame.State = stageStateReady
			}
		case stageStepDepth:
			frame.Want = spatialModel
			depthTime := stageFileModTime(stageDepthOut(wall))
			switch {
			case depthTime.IsZero():
				frame.State = stageStateMissing
			case !wallTime.IsZero() && depthTime.Before(wallTime):
				frame.State = stageStateStale
			case index.DepthModel != "" && index.DepthModel != spatialModel:
				frame.State = stageStateOutdated
			default:
				frame.State = stageStateReady
			}
			if index.DepthModel != "" {
				frame.Model = index.DepthModel
			}
		}
		out = append(out, frame)
	}
	return out
}

func stageStepStateFor(steps []stageStepFrame, wanted stageStep) stageStepState {
	for _, step := range steps {
		if step.Step == wanted {
			return step.State
		}
	}
	return ""
}

func stageStepUsable(state stageStepState) bool {
	return state == stageStateReady || state == stageStateOutdated
}

func stageContainsStep(steps []stageStep, wanted stageStep) bool {
	for _, step := range steps {
		if step == wanted {
			return true
		}
	}
	return false
}

func (d *daemon) stageJobSnapshot() (*stageJobFrame, *stageJobResult) {
	d.stageJobMu.Lock()
	defer d.stageJobMu.Unlock()
	var job *stageJobFrame
	if d.stageJob != nil {
		copyFrame := d.stageJob.frame
		copyFrame.Steps = append([]stageStep(nil), copyFrame.Steps...)
		job = &copyFrame
	}
	var last *stageJobResult
	if d.stageLast != nil {
		copyResult := *d.stageLast
		last = &copyResult
	}
	return job, last
}

func (d *daemon) stageJobBusy() bool {
	d.stageJobMu.Lock()
	defer d.stageJobMu.Unlock()
	return d.stageJob != nil
}

func (d *daemon) stageGenerate(wall string) (string, error) {
	if d.stageJobBusy() {
		return "", errors.New("busy")
	}
	if wall == "" || !isFile(wall) {
		return "", errors.New("no wallpaper")
	}
	mode := loadStageWalls().Walls[wall].Effect
	if mode == "" || mode == stageEffectOff {
		return "", errors.New("the wallpaper is plain")
	}
	states := stageStepsForWall(wall, mode)
	steps := make([]stageStep, 0, len(states))
	for _, step := range states {
		if step.State != stageStateReady {
			steps = append(steps, step.Step)
		}
	}
	if mode == stageEffectParallax && stageContainsStep(steps, stageStepCut) &&
		!stageContainsStep(steps, stageStepFill) {
		withFill := make([]stageStep, 0, len(steps)+1)
		for _, step := range stageStepsForMode(mode) {
			if step == stageStepFill || stageContainsStep(steps, step) {
				withFill = append(withFill, step)
			}
		}
		steps = withFill
	}
	if len(steps) == 0 {
		return "ok nothing to do", nil
	}
	if err := d.startStageJob(wall, "scene", mode, steps, "", false, ""); err != nil {
		return "", err
	}
	return "ok", nil
}

func (d *daemon) stageRefresh(wall string, wanted stageStep) error {
	if d.stageJobBusy() {
		return errors.New("busy")
	}
	if wall == "" || !isFile(wall) {
		return errors.New("no wallpaper")
	}
	mode := loadStageWalls().Walls[wall].Effect
	if mode == "" || mode == stageEffectOff {
		return errors.New("the wallpaper is plain")
	}
	modeSteps := stageStepsForMode(mode)
	steps := make([]stageStep, 0, len(modeSteps))
	if wanted == "" {
		steps = append(steps, modeSteps...)
	} else {
		if !stageContainsStep(modeSteps, wanted) {
			return fmt.Errorf("%s has no %s step", mode, wanted)
		}
		for _, step := range modeSteps {
			if step == wanted || (wanted == stageStepCut && mode == stageEffectParallax && step == stageStepFill) {
				steps = append(steps, step)
			}
		}
	}
	return d.startStageJob(wall, "scene", mode, steps, "", false, "")
}

func (d *daemon) stageCutLayer(wall, picture string) error {
	if d.stageJobBusy() {
		return errors.New("busy")
	}
	return d.startStageLayerJob(wall, picture, false, "")
}

func (d *daemon) stageCutRegion(wall string, values [4]float64) error {
	if d.stageJobBusy() {
		return errors.New("busy")
	}
	for _, value := range values {
		if math.IsNaN(value) || math.IsInf(value, 0) {
			return errors.New("region values must be finite")
		}
	}
	x := math.Max(0, math.Min(0.98, values[0]))
	y := math.Max(0, math.Min(0.98, values[1]))
	width := math.Max(0.02, math.Min(values[2], 1-x))
	height := math.Max(0.02, math.Min(values[3], 1-y))
	region := strings.Join([]string{
		strconv.FormatFloat(x, 'f', -1, 64),
		strconv.FormatFloat(y, 'f', -1, 64),
		strconv.FormatFloat(width, 'f', -1, 64),
		strconv.FormatFloat(height, 'f', -1, 64),
	}, ",")
	return d.startStageLayerJob(wall, wall, true, region)
}

func (d *daemon) startStageLayerJob(wall, picture string, region bool, box string) error {
	if wall == "" || !isFile(wall) {
		return errors.New("no wallpaper")
	}
	mode := loadStageWalls().Walls[wall].Effect
	if mode != stageEffectParallax {
		mode = stageEffectDepth
	}
	return d.startStageJob(wall, "layer", mode, []stageStep{stageStepCut}, picture, region, box)
}

func (d *daemon) startStageJob(
	wall, kind string,
	mode stageEffect,
	steps []stageStep,
	picture string,
	region bool,
	box string,
) error {
	d.stageJobMu.Lock()
	if d.stageJob != nil {
		d.stageJobMu.Unlock()
		return errors.New("busy")
	}
	d.stageJobNext++
	id := d.stageJobNext
	tempDir := filepath.Join(stageWallDir(wall), fmt.Sprintf(".job-%d", id))
	if err := os.MkdirAll(tempDir, 0o755); err != nil {
		d.stageJobMu.Unlock()
		return err
	}
	now := time.Now().UnixMilli()
	cut := stageCutFor(mode)
	spatialModel := stageSpatialModel()
	model := ""
	switch steps[0] {
	case stageStepCut:
		model = cut.model
	case stageStepDepth:
		model = spatialModel
	}
	job := &stageJobRun{
		frame: stageJobFrame{
			ID:          id,
			Wall:        wall,
			Kind:        kind,
			Mode:        mode,
			Steps:       append([]stageStep(nil), steps...),
			Step:        steps[0],
			Index:       0,
			Model:       model,
			Picture:     picture,
			Region:      region,
			State:       "running",
			Started:     now,
			StepStarted: now,
		},
		tempDir:      tempDir,
		cut:          cut,
		spatialModel: spatialModel,
		region:       box,
	}
	d.stageJob = job
	d.stageJobMu.Unlock()
	d.publishStage()
	go d.runStageJob(job)
	return nil
}

func (d *daemon) runStageJob(job *stageJobRun) {
	if err := d.probeStageJob(job); err != nil {
		d.finishStageJob(job, err)
		return
	}
	if d.stageJobStopping(job) {
		d.finishStageJob(job, nil)
		return
	}
	index := loadStageIndex(job.frame.Wall)
	for i, step := range job.frame.Steps {
		if !d.setStageJobStep(job, i, step) {
			d.finishStageJob(job, nil)
			return
		}
		var result stageEngineResult
		switch step {
		case stageStepCut:
			result = d.runStageCut(job)
			if result.err == nil && job.frame.Kind == "scene" {
				index.Source = job.frame.Wall
				index.Model = job.cut.model
				index.Matting = job.cut.matting
			}
		case stageStepFill:
			result = d.runStageFill(job)
		case stageStepDepth:
			result = d.runStageDepth(job)
			if result.err == nil {
				index.DepthModel = job.spatialModel
			}
		}
		if result.err != nil {
			d.finishStageJob(job, stageErrorFromEngine(job, result, stageLimitForStep(step)))
			return
		}
		if d.stageJobStopping(job) {
			d.finishStageJob(job, nil)
			return
		}
	}
	if job.frame.Kind == "scene" &&
		(stageContainsStep(job.frame.Steps, stageStepCut) || stageContainsStep(job.frame.Steps, stageStepDepth)) {
		if err := writeJSONFileAtomic(filepath.Join(job.tempDir, ".index.json"), index); err != nil {
			d.finishStageJob(job, &stageJobError{code: "engine-failed", detail: err.Error()})
			return
		}
	}
	if err := d.commitStageJob(job); err != nil {
		d.finishStageJob(job, &stageJobError{code: "engine-failed", detail: err.Error()})
		return
	}
	d.finishStageJob(job, nil)
}

func (d *daemon) probeStageJob(job *stageJobRun) *stageJobError {
	if stageContainsStep(job.frame.Steps, stageStepCut) {
		result := d.runStageEngine(job, stageProbeTimeout, "check", job.cut.model)
		if result.err != nil {
			return stageProbeError(job.cut.model, result)
		}
		if d.stageJobStopping(job) {
			return nil
		}
	}
	if stageContainsStep(job.frame.Steps, stageStepDepth) {
		result := d.runStageEngine(job, stageProbeTimeout, "depth-check", "--model", job.spatialModel)
		if result.err != nil {
			index := 0
			for i, step := range job.frame.Steps {
				if step == stageStepDepth {
					index = i
					break
				}
			}
			d.setStageJobStep(job, index, stageStepDepth)
			return stageProbeError(job.spatialModel, result)
		}
	}
	return nil
}

func stageProbeError(model string, result stageEngineResult) *stageJobError {
	detail := result.stderr
	if detail == "" {
		detail = result.stdout
	}
	code := stageErrorCode(result.stderr + "\n" + result.stdout)
	if code != "runtime-missing" && code != "model-missing" {
		code = "runtime-missing"
	}
	return &stageJobError{code: code, detail: stageLastLine(detail), model: model}
}

func (d *daemon) setStageJobStep(job *stageJobRun, index int, step stageStep) bool {
	d.stageJobMu.Lock()
	if d.stageJob != job || job.frame.State != "running" {
		d.stageJobMu.Unlock()
		return false
	}
	job.frame.Index = index
	job.frame.Step = step
	job.frame.Model = ""
	switch step {
	case stageStepCut:
		job.frame.Model = job.cut.model
	case stageStepDepth:
		job.frame.Model = job.spatialModel
	}
	job.frame.StepStarted = time.Now().UnixMilli()
	d.stageJobMu.Unlock()
	d.publishStage()
	return true
}

func (d *daemon) runStageCut(job *stageJobRun) stageEngineResult {
	input := job.frame.Wall
	output := filepath.Join(job.tempDir, "subject.png")
	if job.frame.Kind == "layer" {
		input = job.frame.Picture
		output = filepath.Join(job.tempDir, "layer.png")
	}
	args := []string{"cut", input, output, "--model", job.cut.model}
	if job.cut.matting {
		args = append(args, "--matting")
	}
	if job.region != "" {
		args = append(args, "--region", job.region)
	}
	result := d.runStageEngine(job, stageCutTimeout, args...)
	if result.err == nil && !isFile(output) {
		result.err = errors.New("cut output missing")
		result.stderr = "cut output missing"
	}
	return result
}

func (d *daemon) runStageFill(job *stageJobRun) stageEngineResult {
	subject := stageSubjectOut(job.frame.Wall)
	if stageContainsStep(job.frame.Steps, stageStepCut) {
		subject = filepath.Join(job.tempDir, "subject.png")
	}
	output := filepath.Join(job.tempDir, "background.png")
	result := d.runStageEngine(job, stageFillTimeout, "inpaint", job.frame.Wall, subject, output)
	if result.err == nil && !isFile(output) {
		result.err = errors.New("fill output missing")
		result.stderr = "fill output missing"
	}
	return result
}

func (d *daemon) runStageDepth(job *stageJobRun) stageEngineResult {
	output := filepath.Join(job.tempDir, "depth.png")
	result := d.runStageEngine(job, stageDepthTimeout, "depth", job.frame.Wall, output, "--model", job.spatialModel)
	if result.err == nil && !isFile(output) {
		result.err = errors.New("depth output missing")
		result.stderr = "depth output missing"
	}
	return result
}

func stageLimitForStep(step stageStep) int {
	switch step {
	case stageStepFill:
		return int(stageFillTimeout / time.Minute)
	case stageStepCut:
		return int(stageCutTimeout / time.Minute)
	default:
		return int(stageDepthTimeout / time.Minute)
	}
}

func stageErrorFromEngine(job *stageJobRun, result stageEngineResult, limit int) *stageJobError {
	if result.timedOut {
		return &stageJobError{code: "timeout", detail: stageLastLine(result.stderr), limit: limit, model: job.frame.Model}
	}
	return &stageJobError{
		code:   stageErrorCode(result.stderr),
		detail: stageLastLine(result.stderr),
		model:  job.frame.Model,
	}
}

func stageErrorCode(stderr string) string {
	lower := strings.ToLower(stderr)
	switch {
	case strings.Contains(lower, "too large"):
		return "too-large"
	case strings.Contains(lower, "input not found"), strings.Contains(lower, "image not found"),
		strings.Contains(lower, "mask not found"), strings.Contains(lower, "no such file"):
		return "input-missing"
	case strings.Contains(lower, "runtime missing"), strings.Contains(lower, "engine not installed"),
		strings.Contains(lower, "runtime not installed"):
		return "runtime-missing"
	case strings.Contains(lower, "model") && (strings.Contains(lower, "missing") ||
		strings.Contains(lower, "not downloaded") || strings.Contains(lower, "not installed")):
		return "model-missing"
	default:
		return "engine-failed"
	}
}

type stageTail struct {
	data []byte
}

func (w *stageTail) Write(p []byte) (int, error) {
	const keep = 8192
	if len(p) >= keep {
		w.data = append(w.data[:0], p[len(p)-keep:]...)
		return len(p), nil
	}
	if excess := len(w.data) + len(p) - keep; excess > 0 {
		copy(w.data, w.data[excess:])
		w.data = w.data[:len(w.data)-excess]
	}
	w.data = append(w.data, p...)
	return len(p), nil
}

func (w *stageTail) String() string {
	return strings.TrimSpace(string(w.data))
}

func stageLastLine(text string) string {
	lines := strings.Split(strings.TrimSpace(text), "\n")
	last := ""
	for i := len(lines) - 1; i >= 0; i-- {
		if candidate := strings.TrimSpace(lines[i]); candidate != "" {
			last = candidate
			break
		}
	}
	runes := []rune(last)
	if len(runes) > 200 {
		last = string(runes[len(runes)-200:])
	}
	return last
}

func (d *daemon) runStageEngine(job *stageJobRun, timeout time.Duration, args ...string) stageEngineResult {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, stageEngineBin(), args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
	var stdout, stderr stageTail
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		return stageEngineResult{err: err, stderr: err.Error()}
	}
	d.stageJobMu.Lock()
	active := d.stageJob == job
	if active {
		job.pid = cmd.Process.Pid
	}
	stopping := !active || job.frame.State == "stopping"
	d.stageJobMu.Unlock()
	if stopping {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
	}
	err := cmd.Wait()
	d.stageJobMu.Lock()
	if d.stageJob == job && job.pid == cmd.Process.Pid {
		job.pid = 0
	}
	d.stageJobMu.Unlock()
	return stageEngineResult{
		err:      err,
		stdout:   stdout.String(),
		stderr:   stderr.String(),
		timedOut: ctx.Err() == context.DeadlineExceeded,
	}
}

func (d *daemon) stageJobStopping(job *stageJobRun) bool {
	d.stageJobMu.Lock()
	defer d.stageJobMu.Unlock()
	return d.stageJob != job || job.frame.State == "stopping"
}

func (d *daemon) commitStageJob(job *stageJobRun) error {
	d.stageJobMu.Lock()
	defer d.stageJobMu.Unlock()
	if d.stageJob != job || job.frame.State != "running" {
		return errors.New("job stopped")
	}
	type move struct {
		source string
		target string
		backup string
		hadOld bool
	}
	moves := make([]move, 0, 4)
	add := func(name, target string) {
		source := filepath.Join(job.tempDir, name)
		if isFile(source) {
			moves = append(moves, move{source: source, target: target})
		}
	}
	if job.frame.Kind == "layer" {
		target := filepath.Join(stageWallDir(job.frame.Wall),
			fmt.Sprintf("layer-%02d.png", nextManualIndex(stageWallDir(job.frame.Wall))))
		add("layer.png", target)
	} else {
		add("subject.png", stageSubjectOut(job.frame.Wall))
		add("background.png", stageBackgroundOut(job.frame.Wall))
		add("depth.png", stageDepthOut(job.frame.Wall))
		add(".index.json", stageIndexPath(job.frame.Wall))
	}
	committed := 0
	rollback := func() {
		for i := committed - 1; i >= 0; i-- {
			entry := moves[i]
			_ = os.Remove(entry.target)
			if entry.hadOld {
				_ = os.Rename(entry.backup, entry.target)
			}
		}
	}
	for i := range moves {
		if isFile(moves[i].target) {
			moves[i].hadOld = true
			moves[i].backup = filepath.Join(job.tempDir, fmt.Sprintf(".backup-%d", i))
			if err := os.Rename(moves[i].target, moves[i].backup); err != nil {
				rollback()
				return err
			}
		}
		if err := os.Rename(moves[i].source, moves[i].target); err != nil {
			if moves[i].hadOld {
				_ = os.Rename(moves[i].backup, moves[i].target)
			}
			rollback()
			return err
		}
		committed++
	}
	job.committed = true
	return nil
}

func (d *daemon) finishStageJob(job *stageJobRun, jobErr *stageJobError) {
	d.stageJobMu.Lock()
	if d.stageJob != job {
		d.stageJobMu.Unlock()
		_ = os.RemoveAll(job.tempDir)
		return
	}
	state := "done"
	if job.frame.State == "stopping" {
		state = "cancelled"
	} else if jobErr != nil {
		state = "failed"
	}
	result := &stageJobResult{
		ID:       job.frame.ID,
		Wall:     job.frame.Wall,
		Kind:     job.frame.Kind,
		Mode:     job.frame.Mode,
		State:    state,
		Finished: time.Now().UnixMilli(),
	}
	if state != "done" {
		result.Step = job.frame.Step
		result.Model = job.frame.Model
	}
	if state == "failed" {
		result.Error = jobErr.code
		result.Detail = jobErr.detail
		result.Limit = jobErr.limit
		if jobErr.model != "" {
			result.Model = jobErr.model
		}
	}
	d.stageLast = result
	d.stageJob = nil
	d.stageJobMu.Unlock()
	_ = os.RemoveAll(job.tempDir)
	d.scheduleStage()
	d.publishStage()
}

func (d *daemon) stageCancel(force bool) {
	if force {
		d.stageForceCancel()
		return
	}
	d.stageJobMu.Lock()
	job := d.stageJob
	if job == nil || job.committed {
		d.stageJobMu.Unlock()
		return
	}
	job.frame.State = "stopping"
	pid := job.pid
	d.stageJobMu.Unlock()
	if pid > 0 {
		_ = syscall.Kill(-pid, syscall.SIGTERM)
	}
	d.publishStage()
}

func (d *daemon) stageForceCancelWall(wall string) {
	d.stageJobMu.Lock()
	matches := d.stageJob != nil && d.stageJob.frame.Wall == wall
	d.stageJobMu.Unlock()
	if matches {
		d.stageForceCancel()
	}
}

func (d *daemon) stageForceCancel() {
	d.stageJobMu.Lock()
	job := d.stageJob
	if job == nil || job.committed {
		d.stageJobMu.Unlock()
		if job == nil {
			killStrayStageEngines()
		}
		return
	}
	pid := job.pid
	d.stageLast = &stageJobResult{
		ID:       job.frame.ID,
		Wall:     job.frame.Wall,
		Kind:     job.frame.Kind,
		Mode:     job.frame.Mode,
		State:    "cancelled",
		Step:     job.frame.Step,
		Model:    job.frame.Model,
		Finished: time.Now().UnixMilli(),
	}
	d.stageJob = nil
	d.stageJobMu.Unlock()
	if pid > 0 {
		_ = syscall.Kill(-pid, syscall.SIGKILL)
	}
	_ = os.RemoveAll(job.tempDir)
	killStrayStageEngines()
	d.scheduleStage()
	d.publishStage()
}

func removeStageJobDirs() {
	root := stageDir()
	var paths []string
	_ = filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if entry.IsDir() && path != root && strings.HasPrefix(entry.Name(), ".job-") {
			paths = append(paths, path)
			return filepath.SkipDir
		}
		return nil
	})
	for _, path := range paths {
		_ = os.RemoveAll(path)
	}
}

func killStrayStageEngines() {
	root := filepath.Clean(stageDir()) + string(os.PathSeparator)
	engine := filepath.Clean(stageEngineBin())
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return
	}
	uid := uint32(os.Getuid())
	self := os.Getpid()
	ownGroup := syscall.Getpgrp()
	groups := map[int]bool{}
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil || pid == self {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok || stat.Uid != uid {
			continue
		}
		cmdline, err := os.ReadFile(filepath.Join("/proc", entry.Name(), "cmdline"))
		if err != nil || !isStageEngineRun(cmdline, engine, root) {
			continue
		}
		group, err := syscall.Getpgid(pid)
		if err != nil || group <= 0 || group == ownGroup || groups[group] {
			continue
		}
		groups[group] = true
		_ = syscall.Kill(-group, syscall.SIGKILL)
	}
}

// Only engine job verbs writing under the stage root count as orphaned jobs.
func isStageEngineRun(cmdline []byte, engine, root string) bool {
	args := strings.Split(strings.TrimRight(string(cmdline), "\x00"), "\x00")
	for i, arg := range args {
		if arg != engine && filepath.Base(arg) != "ryostage" {
			continue
		}
		if i+1 >= len(args) {
			return false
		}
		switch args[i+1] {
		case "cut", "inpaint", "depth":
		default:
			return false
		}
		for _, rest := range args[i+2:] {
			if strings.HasPrefix(rest, root) {
				return true
			}
		}
		return false
	}
	return false
}
