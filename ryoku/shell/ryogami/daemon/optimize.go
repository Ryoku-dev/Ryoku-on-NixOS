package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

func init() {
	registerAvailability("videoOptimize", func(*daemon) bool {
		return hasEncoder("libx265")
	})
}

// A listed hardware HEVC encoder is not enough: Fedora advertises VA-API and
// QSV encoders even when the installed driver rejects HEVC at runtime.
func videoOptimizeAvailable(encoders codecSet) bool {
	return hasEncoderIn(encoders, "libx265")
}

func videoOptimizeUnavailableError() error {
	return errors.New("Video optimisation is unavailable because this system's ffmpeg has no libx265 encoder")
}

// Optimizer runs the two batch media pipelines the picker drives: re-encoding
// wallpaper images to webp (optimize) and transcoding videos to HEVC/mp4
// (convert). It is a faithful port of the Rust daemon's wall/optimize module,
// minus the sqlite bookkeeping that daemon never grew: eligibility here is
// purely by extension (already-webp images fall out of the image scan) plus the
// runtime codec probe that lets an already-HEVC video be skipped.
type Optimizer struct {
	wallDir  string
	videoDir string
	emit     func(event string, data map[string]interface{})
	repoint  func(oldPath, newPath string)

	mu   sync.Mutex
	jobs map[string]*jobState
}

// jobState tracks one in-flight (or last-finished) run. It mirrors the Rust
// BatchJobState counters; cancel tears down the run's context so an in-flight
// magick/ffmpeg is killed too.
type jobState struct {
	running     bool
	progress    int
	total       int
	currentFile string
	succeeded   int
	skipped     int
	failed      int
	cancel      context.CancelFunc
}

const (
	kindOptimize = "optimize"
	kindConvert  = "convert"
)

// Per-command ceilings. magick on a single image is quick; a full HEVC encode
// of a 4K clip is not, so the convert budget is generous. Both derive from the
// run's cancel context, so optimize.cancel/video_convert.cancel kill the child.
const (
	imageCmdTimeout = 180 * time.Second
	gifCmdTimeout   = 10 * time.Minute
	videoCmdTimeout = 60 * time.Minute
	probeCmdTimeout = 30 * time.Second
)

var imageOptimizeExts = []string{"png", "jpg", "jpeg", "gif"}
var videoConvertExts = []string{"mp4", "webm", "mkv", "avi", "mov"}

type imagePreset struct{ quality int }

var imagePresets = map[string]imagePreset{
	"light":    {quality: 82},
	"balanced": {quality: 88},
	"quality":  {quality: 94},
}

type videoPreset struct {
	crf     int
	maxrate string
	bufsize string
}

var videoPresets = map[string]videoPreset{
	"light":    {crf: 28, maxrate: "6M", bufsize: "12M"},
	"balanced": {crf: 26, maxrate: "10M", bufsize: "20M"},
	"quality":  {crf: 23, maxrate: "16M", bufsize: "32M"},
}

type resolution struct{ maxW, maxH int }

var resolutions = map[string]resolution{
	"1080p": {maxW: 1920, maxH: 1080},
	"2k":    {maxW: 2560, maxH: 1440},
	"4k":    {maxW: 3840, maxH: 2160},
}

// NewOptimizer wires the two source directories and the event sink. Main hands
// the result into the RPC switch.
func NewOptimizer(wallDir, videoDir string, emit func(event string, data map[string]interface{})) *Optimizer {
	return &Optimizer{
		wallDir:  wallDir,
		videoDir: videoDir,
		emit:     emit,
		jobs: map[string]*jobState{
			kindOptimize: {},
			kindConvert:  {},
		},
	}
}

// Start validates the request, refuses a second concurrent run of the same
// kind, then launches the pipeline in the background (mirroring the Rust
// dispatcher's tokio::spawn). The RPC returns {started:true} on a nil error.
// A nil files list processes the whole source directory.
func (o *Optimizer) Start(kind, preset, resolutionKey string, files []string) error {
	res, ok := resolutions[resolutionKey]
	if !ok {
		return fmt.Errorf("unknown resolution: %s", resolutionKey)
	}
	switch kind {
	case kindOptimize:
		if _, ok := imagePresets[preset]; !ok {
			return fmt.Errorf("unknown preset: %s", preset)
		}
	case kindConvert:
		if _, ok := videoPresets[preset]; !ok {
			return fmt.Errorf("unknown preset: %s", preset)
		}
		if !videoOptimizeAvailable(ffmpegCodecs().encoders) {
			return videoOptimizeUnavailableError()
		}
	default:
		return fmt.Errorf("unknown kind: %s", kind)
	}

	o.mu.Lock()
	js := o.jobs[kind]
	if js.running {
		o.mu.Unlock()
		return errors.New("already running")
	}
	ctx, cancel := context.WithCancel(context.Background())
	*js = jobState{running: true, cancel: cancel}
	o.mu.Unlock()

	go o.run(ctx, kind, preset, res, files)
	return nil
}

// Cancel signals a running job to stop; a cancelled run still emits its
// finished event with the tally of what it managed to do.
func (o *Optimizer) Cancel(kind string) {
	o.mu.Lock()
	defer o.mu.Unlock()
	if js, ok := o.jobs[kind]; ok && js.cancel != nil {
		js.cancel()
	}
}

// Status snapshots the counters for the given kind. The success key is named
// "optimized" for images and "converted" for videos, matching the picker's
// per-service parse.
func (o *Optimizer) Status(kind string) map[string]interface{} {
	o.mu.Lock()
	defer o.mu.Unlock()
	js, ok := o.jobs[kind]
	if !ok {
		js = &jobState{}
	}
	return statusPayload(kind, js)
}

func (o *Optimizer) run(ctx context.Context, kind, preset string, res resolution, files []string) {
	if files == nil {
		if kind == kindOptimize {
			files = scanDirByExt(o.wallDir, imageOptimizeExts)
		} else {
			files = scanDirByExt(o.videoDir, videoConvertExts)
		}
	}

	o.mu.Lock()
	js := o.jobs[kind]
	js.total = len(files)
	o.emitProgress(kind, js)
	o.mu.Unlock()

	if len(files) == 0 {
		o.finish(kind)
		return
	}

	for _, src := range files {
		if ctx.Err() != nil {
			break
		}

		o.mu.Lock()
		js.currentFile = filepath.Base(src)
		o.mu.Unlock()

		var outcome string
		if kind == kindOptimize {
			outcome = o.optimizeOne(ctx, src, imagePresets[preset].quality, res)
		} else {
			outcome = o.convertOne(ctx, src, videoPresets[preset], res)
		}

		o.mu.Lock()
		switch outcome {
		case "ok":
			js.succeeded++
		case "skip":
			js.skipped++
		default:
			js.failed++
		}
		js.progress++
		o.emitProgress(kind, js)
		o.mu.Unlock()
	}

	o.finish(kind)
}

func (o *Optimizer) finish(kind string) {
	o.mu.Lock()
	js := o.jobs[kind]
	js.running = false
	js.currentFile = ""
	o.emitFinished(kind, js)
	o.mu.Unlock()
}

// optimizeOne re-encodes one image to webp beside the source and moves the
// original to the trash, as skwd does. Static images go through magick; animated
// gifs through ffmpeg's libwebp_anim, exactly as the Rust pipeline split.
func (o *Optimizer) optimizeOne(ctx context.Context, src string, quality int, res resolution) string {
	stem := strings.TrimSuffix(filepath.Base(src), filepath.Ext(src))
	dir := filepath.Dir(src)
	final := filepath.Join(dir, stem+".webp")
	tmp := filepath.Join(dir, stem+".tmp.webp")
	os.Remove(tmp)

	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(src), "."))
	var err error
	if ext == "gif" {
		err = runCmd(ctx, gifCmdTimeout, "ffmpeg", buildGifArgs(src, tmp, quality, res)...)
	} else {
		err = runCmd(ctx, imageCmdTimeout, "magick", buildMagickArgs(src, tmp, quality, res)...)
	}
	if err != nil {
		os.Remove(tmp)
		return "fail"
	}

	// The original leaves first, so a failure never lists both copies.
	if err := trashOriginal(src); err != nil {
		os.Remove(tmp)
		return "fail"
	}
	if err := os.Rename(tmp, final); err != nil {
		os.Remove(tmp)
		return "fail"
	}
	if o.repoint != nil {
		o.repoint(src, final)
	}
	return "ok"
}

// convertOne probes the source; a clip that is already HEVC and within the
// target resolution is skipped. Otherwise it transcodes to HEVC/mp4 beside the
// source under a hash-suffixed name and removes the original.
func (o *Optimizer) convertOne(ctx context.Context, src string, p videoPreset, res resolution) string {
	codec, w, h, err := probeVideo(ctx, src)
	if err != nil {
		return "fail"
	}
	if codec == "hevc" && w <= res.maxW && h <= res.maxH {
		return "skip"
	}

	stem := strings.TrimSuffix(filepath.Base(src), filepath.Ext(src))
	dir := filepath.Dir(src)
	destName := fmt.Sprintf("%s_%s.mp4", stem, hashPrefix(src))
	final := filepath.Join(dir, destName)
	tmp := filepath.Join(dir, "."+destName+".part.mp4")
	os.Remove(tmp)

	if err := runCmd(ctx, videoCmdTimeout, "ffmpeg", buildConvertArgs(src, tmp, p, res)...); err != nil {
		os.Remove(tmp)
		return "fail"
	}
	if err := os.Rename(tmp, final); err != nil {
		os.Remove(tmp)
		return "fail"
	}
	os.Remove(src)
	return "ok"
}

func buildMagickArgs(src, dest string, quality int, res resolution) []string {
	return []string{
		"-limit", "memory", "512MiB", "-limit", "map", "1GiB",
		src, "-resize", fmt.Sprintf("%dx%d>", res.maxW, res.maxH),
		"-quality", strconv.Itoa(quality), dest,
	}
}

func buildGifArgs(src, dest string, quality int, res resolution) []string {
	vf := fmt.Sprintf("scale=min(%d\\,iw):min(%d\\,ih):force_original_aspect_ratio=decrease", res.maxW, res.maxH)
	return []string{
		"-y", "-i", src, "-vf", vf, "-c:v", "libwebp_anim",
		"-quality", strconv.Itoa(quality), "-loop", "0", "-an", dest,
	}
}

func buildConvertArgs(src, dest string, p videoPreset, res resolution) []string {
	vf := fmt.Sprintf("scale=min(%d\\,iw):min(%d\\,ih):force_original_aspect_ratio=decrease:force_divisible_by=2", res.maxW, res.maxH)
	return []string{
		"-y", "-i", src, "-c:v", "libx265", "-preset", "medium", "-crf", strconv.Itoa(p.crf),
		"-maxrate", p.maxrate, "-bufsize", p.bufsize, "-vf", vf, "-an", "-movflags", "+faststart",
		"-tag:v", "hvc1", dest,
	}
}

func probeVideo(ctx context.Context, path string) (string, int, int, error) {
	cctx, cancel := context.WithTimeout(ctx, probeCmdTimeout)
	defer cancel()
	out, err := exec.CommandContext(cctx, "ffprobe",
		"-v", "quiet", "-select_streams", "v:0", "-show_entries",
		"stream=codec_name,width,height", "-of", "csv=p=0", path).Output()
	if err != nil {
		return "", 0, 0, err
	}
	codec, w, h := parseFfprobeCSV(string(out))
	return codec, w, h, nil
}

func parseFfprobeCSV(text string) (string, int, int) {
	parts := strings.Split(strings.TrimSpace(text), ",")
	codec := ""
	if len(parts) > 0 {
		codec = parts[0]
	}
	w, h := 0, 0
	if len(parts) > 1 {
		w, _ = strconv.Atoi(strings.TrimSpace(parts[1]))
	}
	if len(parts) > 2 {
		h, _ = strconv.Atoi(strings.TrimSpace(parts[2]))
	}
	return codec, w, h
}

func runCmd(ctx context.Context, timeout time.Duration, name string, args ...string) error {
	cctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(cctx, name, args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%s: %w: %s", name, err, strings.TrimSpace(string(out)))
	}
	return nil
}

// scanDirByExt lists the immediate files of dir whose lowercased extension is
// in exts, sorted, mirroring the Rust util::scan_dir_by_ext.
func scanDirByExt(dir string, exts []string) []string {
	ents, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range ents {
		if e.IsDir() {
			continue
		}
		ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(e.Name()), "."))
		for _, want := range exts {
			if ext == want {
				out = append(out, filepath.Join(dir, e.Name()))
				break
			}
		}
	}
	sort.Strings(out)
	return out
}

// hashPrefix is the Rust util::hash_prefix: an 8-hex FNV-ish rolling hash used
// to make converted filenames collision-resistant against the source path.
func hashPrefix(s string) string {
	var h uint64
	for _, b := range []byte(s) {
		h = h*31 + uint64(b)
	}
	return fmt.Sprintf("%08x", h&0xFFFFFFFF)
}

func (o *Optimizer) emitProgress(kind string, js *jobState) {
	if o.emit == nil {
		return
	}
	if kind == kindOptimize {
		o.emit("ryogami.wall.optimize.progress", statusPayload(kind, js))
	} else {
		o.emit("ryogami.wall.convert.progress", statusPayload(kind, js))
	}
}

func (o *Optimizer) emitFinished(kind string, js *jobState) {
	if o.emit == nil {
		return
	}
	successKey := "optimized"
	event := "ryogami.wall.optimize.finished"
	if kind == kindConvert {
		successKey = "converted"
		event = "ryogami.wall.convert.finished"
	}
	o.emit(event, map[string]interface{}{
		successKey: js.succeeded,
		"skipped":  js.skipped,
		"failed":   js.failed,
	})
}

func statusPayload(kind string, js *jobState) map[string]interface{} {
	successKey := "optimized"
	if kind == kindConvert {
		successKey = "converted"
	}
	return map[string]interface{}{
		"running":     js.running,
		"progress":    js.progress,
		"total":       js.total,
		"currentFile": js.currentFile,
		successKey:    js.succeeded,
		"skipped":     js.skipped,
		"failed":      js.failed,
	}
}
