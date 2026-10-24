package main

import (
	"context"
	"errors"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Upscaler ports ryowalls' `enhance` verb into the daemon as a single
// cancellable job, structured like the Optimizer: a mutex-guarded job struct,
// phase/progress tracking, and a start/status/cancel triple that broadcasts
// events. waifu2x-ncnn-vulkan doubles resolution and denoises; images run in one
// shot, videos go frame-by-frame (ffmpeg extract -> waifu2x every frame ->
// ffmpeg reassemble at the source rate). The GPU-selection dance (discrete GPU
// first, validate the output, fall back and remember the good one) is ported so
// a hybrid laptop enhances on its dGPU without starving the compositor.
type Upscaler struct {
	stateDir string
	emit     func(event string, data map[string]interface{})

	mu  sync.Mutex
	job upscaleJob

	// exec seam: overridable so tests exercise the arg/branch logic without the
	// external binaries. Defaults wire the real exec helpers.
	lookPath func(string) (string, error)
	runOut   func(ctx context.Context, timeout time.Duration, name string, args ...string) ([]byte, error)

	// worker seam: where the job's child process comes from. Defaults to the
	// daemon's own binary in upscale-worker mode; tests substitute a fake.
	spawnWorker func(upscaleSpec) (workerProcess, error)
}

// upscaleJob is the in-flight (or last-finished) run, mirroring optimize.go's
// jobState. phase is the ryowalls phase word (probe | extract | enhance |
// assemble | done | sharp | error | unsupported); verdict is the final result
// object, set once on finish.
type upscaleJob struct {
	running  bool
	phase    string
	progress int
	total    int
	file     string
	kind     string
	verdict  map[string]interface{}
	cancel   context.CancelFunc
}

const (
	upscaleKindImage = "image"
	upscaleKindVideo = "video"
)

// waifu2xModel is the cunet model ryowalls runs; waifu2xImageSharpCap is the
// 4K height at/above which an image is already sharp and enhancing is pure GPU
// burn for no gain.
const (
	waifu2xModel         = "/usr/share/waifu2x-ncnn-vulkan/models-cunet"
	waifu2xImageSharpCap = 2160
	defaultUpscaleScale  = 2
)

// Per-phase ceilings. A single image is usually quick; a full frame-by-frame
// video enhance is not, so its extract/enhance/assemble budgets are generous.
// All derive from the run's cancel context, so upscale.cancel kills the child.
const (
	upscaleImageTimeout    = 30 * time.Minute
	upscaleProbeTimeout    = 30 * time.Second
	upscaleExtractTimeout  = 30 * time.Minute
	upscaleEnhanceTimeout  = 2 * time.Hour
	upscaleAssembleTimeout = 30 * time.Minute
)

var videoUpscaleExts = map[string]bool{"mp4": true, "webm": true, "mkv": true, "mov": true}

// NewUpscaler wires the state dir (where the GPU-preference and discrete-GPU
// caches live, matching ryowalls' XDG_STATE_HOME files) and the event sink.
func NewUpscaler(stateDir string, emit func(event string, data map[string]interface{})) *Upscaler {
	return &Upscaler{
		stateDir:    stateDir,
		emit:        emit,
		lookPath:    exec.LookPath,
		runOut:      realRunOut,
		spawnWorker: spawnWorkerProcess,
	}
}

// Start validates the request, refuses a second concurrent run, then launches
// the enhance in the background. kind is inferred from the extension when the
// caller leaves it blank. The RPC returns {started:true} on a nil error.
func (u *Upscaler) Start(input, kind string, scale int) error {
	if input == "" {
		return errors.New("missing 'input' parameter")
	}
	kind = normalizeUpscaleKind(kind, input)
	if kind != upscaleKindImage && kind != upscaleKindVideo {
		return fmt.Errorf("unknown kind: %s", kind)
	}
	if scale <= 0 {
		scale = defaultUpscaleScale
	}

	u.mu.Lock()
	if u.job.running {
		u.mu.Unlock()
		return errors.New("already running")
	}
	ctx, cancel := context.WithCancel(context.Background())
	u.job = upscaleJob{running: true, phase: "probe", kind: kind, file: input, cancel: cancel}
	u.mu.Unlock()

	go u.supervise(ctx, upscaleSpec{Input: input, Kind: kind, Scale: scale})
	return nil
}

// Cancel tears down the running job's context, killing an in-flight
// waifu2x/ffmpeg child. A cancelled run still lands on a terminal verdict.
func (u *Upscaler) Cancel() {
	u.mu.Lock()
	defer u.mu.Unlock()
	if u.job.cancel != nil {
		u.job.cancel()
	}
}

// Status snapshots the current job.
func (u *Upscaler) Status() map[string]interface{} {
	u.mu.Lock()
	defer u.mu.Unlock()
	return upscaleStatusPayload(&u.job)
}

// normalizeUpscaleKind honours an explicit kind and otherwise infers it from the
// extension, so upscale.start with just {input} does the right thing.
func normalizeUpscaleKind(kind, input string) string {
	switch kind {
	case upscaleKindImage, upscaleKindVideo:
		return kind
	case "":
		ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(input), "."))
		if videoUpscaleExts[ext] {
			return upscaleKindVideo
		}
		return upscaleKindImage
	default:
		return kind
	}
}

// upscaleWorkerCap is the failsafe ceiling on a whole job, far above every
// per-phase budget inside the worker (probes, extract, per-GPU enhance,
// assemble). It exists for a wedged worker, not for honest work: cancel is
// the knob for a run the user no longer wants.
const upscaleWorkerCap = 8 * time.Hour

// supervise runs the enhance in the worker child and translates its stream
// back into the job: progress lines become the usual broadcast events, the
// verdict (or the worker's death, a cancel, or the failsafe cap) lands as the
// final one, and the running lock always clears. A panic inside the pipeline
// kills the worker, never the daemon.
func (u *Upscaler) supervise(ctx context.Context, spec upscaleSpec) {
	defer u.finish(spec.Kind)
	wp, err := u.spawnWorker(spec)
	if err != nil {
		u.mu.Lock()
		u.job.verdict = upscaleVerdict("error", spec.Kind, 0, 0, "", "spawn")
		u.mu.Unlock()
		return
	}

	// one relay owns the worker's stdout for its whole life: progress lines
	// become the usual events, the verdict lands on the job directly. Draining
	// to EOF here means no send can ever block, whatever the exit path.
	relayed := make(chan struct{})
	go func() {
		defer close(relayed)
		for ev := range wp.events {
			u.mu.Lock()
			if ev.Verdict != nil {
				u.job.verdict = ev.Verdict
				u.mu.Unlock()
				continue
			}
			if p, ok := ev.Data["phase"].(string); ok {
				u.job.phase = p
			}
			if n, ok := ev.Data["progress"].(float64); ok {
				u.job.progress = int(n)
			}
			if n, ok := ev.Data["total"].(float64); ok {
				u.job.total = int(n)
			}
			u.emitProgress()
			u.mu.Unlock()
		}
	}()

	watchdog := time.NewTimer(upscaleWorkerCap)
	defer watchdog.Stop()
	for {
		select {
		case <-ctx.Done():
			u.fail(spec.Kind, "cancelled", wp.kill)
			return
		case <-watchdog.C:
			u.fail(spec.Kind, "timeout", wp.kill)
			return
		case <-relayed:
			<-wp.done
			u.settle(ctx, spec.Kind)
			return
		case <-wp.done:
			<-relayed
			u.settle(ctx, spec.Kind)
			return
		}
	}
}

// fail records the verdict for a job the daemon stopped itself, then kills
// the worker group.
func (u *Upscaler) fail(kind, why string, kill func()) {
	u.mu.Lock()
	if u.job.verdict == nil {
		u.job.verdict = upscaleVerdict("error", kind, 0, 0, "", why)
	}
	u.mu.Unlock()
	kill()
}

// settle records the terminal verdict for a worker that exited on its own:
// whatever it reported, else cancelled (the run's context was done) or a bare
// worker death.
func (u *Upscaler) settle(ctx context.Context, kind string) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if u.job.verdict != nil {
		return
	}
	if ctx.Err() != nil {
		u.job.verdict = upscaleVerdict("error", kind, 0, 0, "", "cancelled")
		return
	}
	u.job.verdict = upscaleVerdict("error", kind, 0, 0, "", "worker")
}

// finish clears the running lock and lands the finished event, whatever the
// exit path was. Runs as supervise's defer.
func (u *Upscaler) finish(kind string) {
	u.mu.Lock()
	u.job.running = false
	if u.job.verdict == nil {
		u.job.verdict = upscaleVerdict("error", kind, 0, 0, "", "worker")
	}
	if r, _ := u.job.verdict["result"].(string); r != "" {
		u.job.phase = r
	}
	u.emitFinished()
	u.mu.Unlock()
}

// enhanceImage doubles an image in place on the GPU. A 4K source is already
// sharp and is skipped; a missing tool reports unsupported. Every GPU output is
// sanity-checked so a wedged GPU's near-black frame never overwrites the source.
func (u *Upscaler) enhanceImage(ctx context.Context, f string, scale int) map[string]interface{} {
	h := u.imageHeight(ctx, f)
	if h <= 0 {
		return upscaleVerdict("error", upscaleKindImage, 0, 0, "", "read")
	}
	if h >= waifu2xImageSharpCap {
		u.setPhase("sharp")
		return upscaleVerdict("sharp", upscaleKindImage, h, waifu2xImageSharpCap, "", "")
	}
	if _, err := u.lookPath("waifu2x-ncnn-vulkan"); err != nil {
		u.setPhase("unsupported")
		return upscaleVerdict("unsupported", upscaleKindImage, 0, 0, "", "")
	}

	u.setPhase("enhance")
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(f), "."))
	if ext == "jpeg" {
		ext = "jpg"
	}
	tmp := f + ".up." + ext
	for _, gpu := range u.waifu2xOrder(ctx) {
		os.Remove(tmp)
		if err := runCmd(ctx, upscaleImageTimeout, "waifu2x-ncnn-vulkan", buildWaifu2xArgs(f, tmp, scale, gpu)...); err != nil {
			continue
		}
		if fileNonEmpty(tmp) && u.saneImage(ctx, tmp) {
			if err := os.Rename(tmp, f); err != nil {
				os.Remove(tmp)
				continue
			}
			u.rememberGPU(gpu)
			u.setPhase("done")
			return upscaleVerdict("done", upscaleKindImage, 0, 0, f, "")
		}
	}
	os.Remove(tmp)
	return upscaleVerdict("error", upscaleKindImage, 0, 0, "", "gpu")
}

// enhanceVideo enhances a clip frame by frame: ffmpeg extracts every frame,
// waifu2x doubles the batch, ffmpeg reassembles at the source rate (audio copied
// when present). It writes a correctly-named .mp4 beside the source and never
// overwrites the original clip.
func (u *Upscaler) enhanceVideo(ctx context.Context, f string, scale int) map[string]interface{} {
	if _, err := u.lookPath("ffmpeg"); err != nil {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "tools")
	}
	if _, err := u.lookPath("waifu2x-ncnn-vulkan"); err != nil {
		u.setPhase("unsupported")
		return upscaleVerdict("unsupported", upscaleKindVideo, 0, 0, "", "")
	}

	u.setPhase("probe")
	w := u.videoWidth(ctx, f)
	capW := u.screenCap()
	if w >= capW {
		u.setPhase("sharp")
		return upscaleVerdict("sharp", upscaleKindVideo, w, capW, "", "")
	}
	fps := u.videoFPS(ctx, f)
	est := u.videoFrameEstimate(ctx, f, fps)

	work, err := os.MkdirTemp("", "ryogami-upscale-")
	if err != nil {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "io")
	}
	defer os.RemoveAll(work)
	inDir := filepath.Join(work, "in")
	outDir := filepath.Join(work, "out")
	if err := os.MkdirAll(inDir, 0o755); err != nil {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "io")
	}
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "io")
	}

	u.setProgress("extract", 0, est)
	if err := u.runProcPoll(ctx, upscaleExtractTimeout, inDir, "ffmpeg", buildExtractArgs(f, filepath.Join(inDir, "%08d.png"))...); err != nil {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "read")
	}
	total := countPNGs(inDir)
	if total <= 0 {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "read")
	}

	okGPU := -1
	for _, gpu := range u.waifu2xOrder(ctx) {
		os.RemoveAll(outDir)
		if err := os.MkdirAll(outDir, 0o755); err != nil {
			return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "io")
		}
		u.setProgress("enhance", 0, total)
		if err := u.runProcPoll(ctx, upscaleEnhanceTimeout, outDir, "waifu2x-ncnn-vulkan", buildWaifu2xArgs(inDir, outDir, scale, gpu)...); err != nil {
			continue
		}
		chk := filepath.Join(outDir, fmt.Sprintf("%08d.png", midFrame(total)))
		if fileNonEmpty(chk) && u.saneImage(ctx, chk) {
			okGPU = gpu
			break
		}
	}
	if okGPU < 0 {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "gpu")
	}
	u.rememberGPU(okGPU)

	u.setProgress("assemble", total, total)
	final := filepath.Join(work, "final.mp4")
	assemble, err := buildAssembleArgs(ffmpegCodecs().encoders,
		filepath.Join(outDir, "%08d.png"), f, final, fps, w*scale)
	if err != nil {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", err.Error())
	}
	if err := runCmd(ctx, upscaleAssembleTimeout, "ffmpeg", assemble...); err != nil {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "assemble")
	}

	out, err := siblingExt(f, "mp4")
	if err != nil {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "io")
	}
	if err := moveFile(final, out); err != nil {
		return upscaleVerdict("error", upscaleKindVideo, 0, 0, "", "io")
	}
	u.setPhase("done")
	return upscaleVerdict("done", upscaleKindVideo, 0, 0, out, "")
}

// ---- command builders (pure) ----------------------------------------------

// buildWaifu2xArgs is ryowalls' waifu2x invocation, for a single image (src/dst
// files) or a whole frame directory (src/dst dirs): `-i IN -o OUT -s SCALE -n 2
// -g GPU -m MODEL`.
func buildWaifu2xArgs(in, out string, scale, gpu int) []string {
	return []string{"-i", in, "-o", out, "-s", strconv.Itoa(scale), "-n", "2", "-g", strconv.Itoa(gpu), "-m", waifu2xModel}
}

// buildExtractArgs is ryowalls' lossless frame extract: `ffmpeg -y -i F
// -qscale:v 1 -qmin 1 -qmax 1 -vsync 0 OUT/%08d.png`.
func buildExtractArgs(src, pattern string) []string {
	return []string{"-y", "-i", src, "-qscale:v", "1", "-qmin", "1", "-qmax", "1", "-vsync", "0", pattern}
}

// buildAssembleArgs is ryowalls' reassemble: H.264 at the source rate, source
// audio copied when present, faststart for scrubbing.
func buildAssembleArgs(encoders codecSet, pattern, orig, out, fps string, width int) ([]string, error) {
	encoder, err := pickCPUH264Encoder(encoders)
	if err != nil {
		return nil, err
	}
	rate := parseFrameRate(fps)
	codec, err := h264CPUArgs(encoder, width, int(math.Ceil(rate)),
		"-pix_fmt", "yuv420p")
	if err != nil {
		return nil, err
	}
	args := []string{"-y", "-framerate", fps, "-i", pattern, "-i", orig,
		"-map", "0:v:0", "-map", "1:a:0?", "-c:a", "copy"}
	args = append(args, codec...)
	args = append(args, "-movflags", "+faststart", out)
	return args, nil
}

// waifu2xOrderList is ryowalls' w2x_order: the discrete GPU first, then the
// last-known-good preference, then every index, de-duplicated. Only 0..3 are
// valid indices; anything else is dropped.
func waifu2xOrderList(disc, pref string) []int {
	var out []int
	seen := map[int]bool{}
	for _, s := range append([]string{disc, pref}, "0", "1", "2", "3") {
		n, err := strconv.Atoi(strings.TrimSpace(s))
		if err != nil || n < 0 || n > 3 || seen[n] {
			continue
		}
		seen[n] = true
		out = append(out, n)
	}
	return out
}

// parseDiscreteGPU reads waifu2x's device banner ("[0 GPU name]" lines) and
// returns the lowest index whose name is not an integrated GPU, or "" when none
// is found. Mirrors ryowalls' w2x_discrete name filter.
func parseDiscreteGPU(banner string) string {
	re := regexp.MustCompile(`\[(\d+)\s+([^\]]+)\]`)
	seen := map[int]string{}
	for _, m := range re.FindAllStringSubmatch(banner, -1) {
		idx, err := strconv.Atoi(m[1])
		if err != nil {
			continue
		}
		if _, ok := seen[idx]; !ok {
			seen[idx] = strings.TrimSpace(m[2])
		}
	}
	idxs := make([]int, 0, len(seen))
	for i := range seen {
		idxs = append(idxs, i)
	}
	sort.Ints(idxs)
	for _, i := range idxs {
		if !isIntegratedGPU(seen[i]) {
			return strconv.Itoa(i)
		}
	}
	return ""
}

func isIntegratedGPU(name string) bool {
	l := strings.ToLower(name)
	for _, needle := range []string{"intel", "iris", "uhd", "llvmpipe", "swiftshader", "mali", "adreno"} {
		if strings.Contains(l, needle) {
			return true
		}
	}
	// "Radeon ... Graphics" is an AMD APU (integrated); a discrete Radeon has a
	// model number, not the "Graphics" suffix.
	if strings.Contains(l, "radeon") && strings.Contains(l, "graphics") {
		return true
	}
	return false
}

// ---- verdict / status shapes ----------------------------------------------

// upscaleVerdict builds the final result object ryowalls' enh_verdict printed:
// result (done|sharp|error|unsupported), kind, the measured px against the cap
// it was checked against, plus out (the written path) and why (the error cause)
// when they apply.
func upscaleVerdict(result, kind string, px, cap int, out, why string) map[string]interface{} {
	v := map[string]interface{}{
		"result": result,
		"kind":   kind,
		"px":     px,
		"cap":    cap,
	}
	if out != "" {
		v["out"] = out
	}
	if why != "" {
		v["why"] = why
	}
	return v
}

func upscaleStatusPayload(j *upscaleJob) map[string]interface{} {
	return map[string]interface{}{
		"running":  j.running,
		"phase":    j.phase,
		"progress": j.progress,
		"total":    j.total,
		"file":     j.file,
		"kind":     j.kind,
		"verdict":  j.verdict,
	}
}

// setPhase updates the phase and emits progress. setProgress additionally resets
// the counters for a new phase. Both take the lock.
func (u *Upscaler) setPhase(phase string) {
	u.mu.Lock()
	u.job.phase = phase
	u.emitProgress()
	u.mu.Unlock()
}

func (u *Upscaler) setProgress(phase string, progress, total int) {
	u.mu.Lock()
	u.job.phase = phase
	u.job.progress = progress
	u.job.total = total
	u.emitProgress()
	u.mu.Unlock()
}

func (u *Upscaler) emitProgress() {
	if u.emit != nil {
		u.emit("ryogami.wall.upscale.progress", upscaleStatusPayload(&u.job))
	}
}

func (u *Upscaler) emitFinished() {
	if u.emit != nil {
		u.emit("ryogami.wall.upscale.finished", upscaleStatusPayload(&u.job))
	}
}

// ---- probes (through the exec seam) ----------------------------------------

func (u *Upscaler) imageHeight(ctx context.Context, f string) int {
	out, err := u.runOut(ctx, upscaleProbeTimeout, "identify", "-format", "%h", f+"[0]")
	if err != nil {
		return 0
	}
	return atoiFirst(string(out))
}

func (u *Upscaler) videoWidth(ctx context.Context, f string) int {
	out, err := u.runOut(ctx, upscaleProbeTimeout, "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width", "-of", "csv=p=0", f)
	if err != nil {
		return 0
	}
	return atoiFirst(string(out))
}

// videoFPS reads r_frame_rate; a missing/degenerate rate falls back to 30, the
// same default ryowalls used.
func (u *Upscaler) videoFPS(ctx context.Context, f string) string {
	out, err := u.runOut(ctx, upscaleProbeTimeout, "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate", "-of", "csv=p=0", f)
	fps := strings.TrimSpace(firstLine(string(out)))
	if err != nil || fps == "" || fps == "0/0" {
		return "30"
	}
	return fps
}

// videoFrameEstimate is the extract bar's target: nb_frames when the container
// carries it, else duration x fps.
func (u *Upscaler) videoFrameEstimate(ctx context.Context, f, fps string) int {
	out, err := u.runOut(ctx, upscaleProbeTimeout, "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=nb_frames", "-of", "csv=p=0", f)
	if err == nil {
		if n := atoiFirst(string(out)); n > 0 {
			return n
		}
	}
	durOut, err := u.runOut(ctx, upscaleProbeTimeout, "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f)
	if err != nil {
		return 0
	}
	dur, err := strconv.ParseFloat(strings.TrimSpace(firstLine(string(durOut))), 64)
	if err != nil || dur <= 0 {
		return 0
	}
	r := parseFrameRate(fps)
	if r <= 0 {
		return 0
	}
	return int(dur * r)
}

// screenCap is ryowalls' screen_cap: the widest monitor's logical width (physical
// / fractional scale), clamped to 1280..2560, 1920 when no compositor answers. A
// source already this wide gains nothing on screen, so it is skipped.
func (u *Upscaler) screenCap() int {
	outs := outputs.list()
	if len(outs) == 0 {
		return 1920
	}
	best := 0.0
	for _, o := range outs {
		s := o.Scale
		if s <= 0 {
			s = 1
		}
		if v := float64(o.Width) / s; v > best {
			best = v
		}
	}
	w := int(math.Floor(best))
	if w < 1280 {
		w = 1280
	}
	if w > 2560 {
		w = 2560
	}
	return w
}

// saneImage is ryowalls' sane_img: an output is real content only when the first
// frame's mean brightness and standard deviation clear a floor, so a wedged
// GPU's near-black or flat output is rejected instead of written over a source.
func (u *Upscaler) saneImage(ctx context.Context, path string) bool {
	mOut, err := u.runOut(ctx, upscaleProbeTimeout, "identify", "-format", "%[fx:mean]", path+"[0]")
	if err != nil {
		return false
	}
	sOut, err := u.runOut(ctx, upscaleProbeTimeout, "identify", "-format", "%[fx:standard_deviation]", path+"[0]")
	if err != nil {
		return false
	}
	mean, err1 := strconv.ParseFloat(strings.TrimSpace(firstLine(string(mOut))), 64)
	std, err2 := strconv.ParseFloat(strings.TrimSpace(firstLine(string(sOut))), 64)
	if err1 != nil || err2 != nil {
		return false
	}
	return mean > 0.02 && std > 0.01
}

// waifu2xOrder resolves the GPU attempt order for this run: the cached/probed
// discrete GPU, then the last-good preference, then every index.
func (u *Upscaler) waifu2xOrder(ctx context.Context) []int {
	return waifu2xOrderList(u.waifu2xDiscrete(ctx), u.readState(u.gpuPrefFile()))
}

// waifu2xDiscrete detects the ncnn index of the discrete GPU once and caches it.
// ncnn's Vulkan enumeration order is not fixed, so it reads the index from
// waifu2x's own device banner (a 64x64 probe op) and takes the first non-
// integrated device. Cached as an index or -1 (none found).
func (u *Upscaler) waifu2xDiscrete(ctx context.Context) string {
	discFile := u.discreteFile()
	switch c := u.readState(discFile); c {
	case "0", "1", "2", "3":
		return c
	case "-1":
		return ""
	}
	if _, err := u.lookPath("waifu2x-ncnn-vulkan"); err != nil {
		return ""
	}
	tmp, err := os.MkdirTemp("", "ryogami-w2xprobe-")
	if err != nil {
		return ""
	}
	defer os.RemoveAll(tmp)
	in := filepath.Join(tmp, "in.png")
	out := filepath.Join(tmp, "out.png")
	if _, err := u.runOut(ctx, upscaleProbeTimeout, "magick", "-size", "64x64", "xc:gray", in); err != nil {
		_ = os.WriteFile(in, []byte{}, 0o644)
	}
	// CombinedOutput carries the banner (waifu2x prints devices to stderr) even
	// on a non-zero exit, so the banner is parsed regardless of err.
	banner, _ := u.runOut(ctx, upscaleProbeTimeout, "waifu2x-ncnn-vulkan", "-i", in, "-o", out, "-s", "2", "-n", "0", "-m", waifu2xModel)
	disc := parseDiscreteGPU(string(banner))
	if disc == "" {
		u.writeState(discFile, "-1")
		return ""
	}
	u.writeState(discFile, disc)
	return disc
}

func (u *Upscaler) rememberGPU(gpu int) {
	u.writeState(u.gpuPrefFile(), strconv.Itoa(gpu))
}

// ---- process runner with progress polling ---------------------------------

// runProcPoll starts a command and, while it runs, polls watchDir's PNG count
// into the job's progress so a long extract/enhance moves the bar. Ported from
// ryowalls' background-and-poll loop; the command's context cancel kills it.
func (u *Upscaler) runProcPoll(ctx context.Context, timeout time.Duration, watchDir, name string, args ...string) error {
	cctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(cctx, name, args...)
	if err := cmd.Start(); err != nil {
		return err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	tick := time.NewTicker(500 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case err := <-done:
			return err
		case <-tick.C:
			n := countPNGs(watchDir)
			u.mu.Lock()
			u.job.progress = n
			u.emitProgress()
			u.mu.Unlock()
		}
	}
}

// ---- small helpers ---------------------------------------------------------

func realRunOut(ctx context.Context, timeout time.Duration, name string, args ...string) ([]byte, error) {
	cctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	return exec.CommandContext(cctx, name, args...).CombinedOutput()
}

func (u *Upscaler) gpuPrefFile() string  { return filepath.Join(u.stateDir, "ryoku-w2x-gpu") }
func (u *Upscaler) discreteFile() string { return filepath.Join(u.stateDir, "ryoku-w2x-discrete") }

func (u *Upscaler) readState(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func (u *Upscaler) writeState(path, val string) {
	if u.stateDir == "" {
		return
	}
	_ = os.MkdirAll(u.stateDir, 0o755)
	_ = os.WriteFile(path, []byte(val), 0o644)
}

func fileNonEmpty(path string) bool {
	fi, err := os.Stat(path)
	return err == nil && fi.Size() > 0
}

func countPNGs(dir string) int {
	ents, err := os.ReadDir(dir)
	if err != nil {
		return 0
	}
	n := 0
	for _, e := range ents {
		if !e.IsDir() && strings.EqualFold(filepath.Ext(e.Name()), ".png") {
			n++
		}
	}
	return n
}

func midFrame(total int) int {
	if total/2 > 0 {
		return total / 2
	}
	return 1
}

// siblingExt returns the input's path with its extension replaced, keeping the
// stem and directory -- ryowalls' `${f%.*}.mp4` for the reassembled clip.
func siblingExt(input, newExt string) (string, error) {
	stem, _, err := stemExt(input)
	if err != nil {
		return "", err
	}
	return filepath.Join(filepath.Dir(input), stem+"."+newExt), nil
}

// moveFile renames, falling back to a copy across filesystems (the frame dump
// lives in the temp dir, which may be a different mount than the wallpaper).
func moveFile(src, dst string) error {
	if err := os.Rename(src, dst); err == nil {
		return nil
	}
	if err := copyFile(src, dst); err != nil {
		return err
	}
	return os.Remove(src)
}

func atoiFirst(s string) int {
	n, err := strconv.Atoi(strings.TrimSpace(firstLine(s)))
	if err != nil {
		return 0
	}
	return n
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

// parseFrameRate turns ffprobe's "num/den" (or a bare number) into a float.
func parseFrameRate(fps string) float64 {
	fps = strings.TrimSpace(fps)
	if i := strings.IndexByte(fps, '/'); i >= 0 {
		num, err1 := strconv.ParseFloat(fps[:i], 64)
		den, err2 := strconv.ParseFloat(fps[i+1:], 64)
		if err1 != nil || err2 != nil || den == 0 {
			return 0
		}
		return num / den
	}
	v, err := strconv.ParseFloat(fps, 64)
	if err != nil {
		return 0
	}
	return v
}
