package main

// Ryogami-live starts from the source, then reuses a capped cache on later plays.

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const liveDaemon = "ryogami-live"

type liveTranscodeFunc func(context.Context, transcodeSpec) error

var liveTranscodeGate = make(chan struct{}, 1)

// liveTranscodeSettle keeps the cache encode from competing with the reveal it follows.
var liveTranscodeSettle = 15 * time.Second

func init() {
	guardApply(func(d *daemon, req *applyRequest) error {
		if req.Type != "video" || d.settingBool("pickOnlyMode") {
			return nil
		}
		src := liveProbe(req.Path)
		return videoSourceDecodeError(src, ffmpegCodecs().decoders)
	})
}

func videoSourceDecodeError(src liveShape, decoders codecSet) error {
	return videoDecodeError(src.codec, decoders)
}

// liveEncRev marks the transcode flags a cached clip was produced with. Bump it
// whenever they change, so old clips are re-encoded instead of being replayed
// with settings livewall no longer expects.
const liveEncRev = "4"

// liveCapWidth caps the player's decode/render width at the widest monitor's
// PHYSICAL pixel width, so a video wallpaper renders 1:1 with the panel.
// Encoding at the logical width (physical / fractional scale) comes out soft on
// a scaled monitor: 1920 @ 1.25 cached at 1536 and stretched back up. The
// ceiling bounds decode and the player's RSS by resource tier. 1920 when no
// compositor answers.
func liveCapWidth(tier string) int {
	floor, ceil := 1280, 2560
	switch tier {
	case "low":
		ceil = 1920
	case "high":
		ceil = 3840
	}
	best := 1920
	w := 0
	for _, o := range outputs.list() {
		if o.Width > w {
			w = o.Width
		}
	}
	if w > 0 {
		best = w
	}
	if best < floor {
		best = floor
	}
	if best > ceil {
		best = ceil
	}
	return best
}

// liveProbe reads the one video stream's shape in a single ffprobe call.
// Zero-value fields on failure: callers fall back to transcoding.
type liveShape struct {
	codec  string
	pixFmt string
	width  int
	fps    float64
}

func liveProbe(path string) liveShape {
	out, err := exec.Command("ffprobe", "-v", "error", "-select_streams", "v:0",
		"-show_entries", "stream=codec_name,pix_fmt,width,r_frame_rate",
		"-of", "default=nw=1", path).Output()
	var s liveShape
	if err != nil {
		return s
	}
	for _, line := range strings.Split(string(out), "\n") {
		k, v, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok {
			continue
		}
		switch k {
		case "codec_name":
			s.codec = v
		case "pix_fmt":
			s.pixFmt = v
		case "width":
			s.width, _ = strconv.Atoi(v)
		case "r_frame_rate":
			num, den, _ := strings.Cut(v, "/")
			n, errN := strconv.ParseFloat(num, 64)
			d, errD := strconv.ParseFloat(den, 64)
			if errN == nil && errD == nil && d > 0 {
				s.fps = n / d
			}
		}
	}
	return s
}

// liveFps is the rate a clip is transcoded to, and so the rate the player
// decodes it at (it paces off the stream's own frame rate). The source rate is
// kept, only capped by tier: padding a 24fps clip to 30 would duplicate frames
// into judder, and downsampling to below the cap loses nothing but decode
// cost. An unreadable rate falls back to 30.
func liveFps(tier string, src liveShape) string {
	ceil := 30.0
	switch tier {
	case "low":
		ceil = 24
	case "high":
		ceil = 60
	}
	fps := src.fps
	if fps <= 0 {
		fps = 30
	}
	if fps > ceil {
		fps = ceil
	}
	if fps < 1 {
		fps = 1
	}
	return strconv.Itoa(int(fps + 0.5))
}

func liveCacheUnneeded(src liveShape, capW int, fps string) bool {
	target, _ := strconv.ParseFloat(fps, 64)
	return src.codec == "h264" && src.pixFmt == "yuv420p" &&
		src.width > 0 && src.width <= capW &&
		src.fps > 0 && src.fps <= target+6
}

func livewallCachePath(pic string, src liveShape, capW int, fps string) string {
	if liveCacheUnneeded(src, capW, fps) {
		return ""
	}
	st, err := os.Stat(pic)
	if err != nil {
		return ""
	}
	name := strings.TrimSuffix(filepath.Base(pic), filepath.Ext(pic))
	return filepath.Join(livewallCacheDir(), name+"-"+strconv.FormatInt(st.ModTime().Unix(), 10)+
		"-"+strconv.Itoa(capW)+"-"+fps+"-r"+liveEncRev+".mp4")
}

func livewallSource(pic string, src liveShape, capW int, fps string) string {
	if _, err := os.Stat(pic); err != nil {
		return ""
	}
	cache := livewallCachePath(pic, src, capW, fps)
	if cache != "" && fileExists(cache) {
		return cache
	}
	return pic
}

func cacheLivewallSource(ctx context.Context, pic string, src liveShape, capW int, fps string, transcode liveTranscodeFunc) string {
	if ctx.Err() != nil {
		return ""
	}
	out := livewallCachePath(pic, src, capW, fps)
	if out == "" || fileExists(out) {
		return out
	}
	select {
	case <-time.After(liveTranscodeSettle):
	case <-ctx.Done():
		return ""
	}
	select {
	case liveTranscodeGate <- struct{}{}:
		defer func() { <-liveTranscodeGate }()
	case <-ctx.Done():
		return ""
	}
	if ctx.Err() != nil {
		return ""
	}
	if fileExists(out) {
		return out
	}
	if os.MkdirAll(filepath.Dir(out), 0o755) != nil {
		return ""
	}
	tmp := out + ".tmp." + strconv.Itoa(os.Getpid()) + "-" + strconv.FormatInt(time.Now().UnixNano(), 10) + ".mp4"
	rate, _ := strconv.Atoi(fps)
	err := transcode(ctx, transcodeSpec{
		src: pic, dst: tmp, fps: rate, maxWidth: capW, qp: 20, crf: 18, idle: true,
	})
	if err != nil || ctx.Err() != nil {
		_ = os.Remove(tmp)
		return ""
	}
	if os.Rename(tmp, out) != nil {
		_ = os.Remove(tmp)
		return ""
	}
	return out
}

// liveStill extracts one full-resolution frame from a clip, cached per mtime.
// The shell paints it as the frame under the player: the reveal transition, the
// depth cutout and the palette all read this still, and it holds the screen
// through the one-time transcode and if the player ever dies. "" on failure.
func liveStill(video string, sec float64) string {
	st, err := os.Stat(video)
	if err != nil {
		return ""
	}
	if sec <= 0 {
		sec = 1
	}
	secStr := strconv.FormatFloat(sec, 'f', 1, 64)
	dir := livewallCacheDir()
	name := strings.TrimSuffix(filepath.Base(video), filepath.Ext(video))
	out := filepath.Join(dir, name+"-"+strconv.FormatInt(st.ModTime().Unix(), 10)+"-still-"+secStr+".jpg")
	if fileExists(out) {
		return out
	}
	if os.MkdirAll(dir, 0o755) != nil {
		return ""
	}
	tmp := fmt.Sprintf("%s.tmp.%d-%d.jpg", out, os.Getpid(), time.Now().UnixNano())
	err = exec.Command("ffmpeg", "-y", "-v", "error", "-ss", secStr, "-i", video,
		"-frames:v", "1", "-q:v", "2", tmp).Run()
	if err != nil || !fileExists(tmp) {
		// Clips shorter than a second: take the first frame instead.
		err = exec.Command("ffmpeg", "-y", "-v", "error", "-i", video,
			"-frames:v", "1", "-q:v", "2", tmp).Run()
		if err != nil || !fileExists(tmp) {
			_ = os.Remove(tmp)
			return ""
		}
	}
	if os.Rename(tmp, out) != nil {
		_ = os.Remove(tmp)
		return ""
	}
	return out
}

// cacheHome resolves XDG_CACHE_HOME with the ~/.cache fallback.
func cacheHome() string {
	if base := os.Getenv("XDG_CACHE_HOME"); base != "" {
		return base
	}
	return filepath.Join(os.Getenv("HOME"), ".cache")
}

// liveFit maps the shell's contentFit vocabulary onto livewall's argv: "fit"
// letterboxes the whole clip (Contain), anything else covers the screen.
func liveFit(contentFit string) string {
	if contentFit == "Contain" {
		return "fit"
	}
	return "fill"
}

// transcodeCachePath is the cached re-encode path for a clip at a given
// fps/width cap, keyed by source mtime + cap (distinct from livewallSource).
func transcodeCachePath(src string, fps, capW int) string {
	st, err := os.Stat(src)
	if err != nil {
		return ""
	}
	dir := filepath.Join(cacheHome(), "ryogami", "livewall")
	name := strings.TrimSuffix(filepath.Base(src), filepath.Ext(src))
	return filepath.Join(dir, name+"-"+strconv.FormatInt(st.ModTime().Unix(), 10)+
		"-w"+strconv.Itoa(capW)+"-f"+strconv.Itoa(fps)+"-a.mp4")
}

// ensureVideoTranscode re-encodes a clip to a bite-sized mp4 (fps + width
// capped, its audio kept so the in-shell player can unmute), cached per source
// mtime and cap, for the in-shell engine. "" on failure keeps the original.
func ensureVideoTranscode(src string, fps, capW int) string {
	out := transcodeCachePath(src, fps, capW)
	if out == "" {
		return ""
	}
	if fileExists(out) {
		return out
	}
	if os.MkdirAll(filepath.Dir(out), 0o755) != nil {
		return ""
	}
	tmp := out + ".tmp." + strconv.Itoa(os.Getpid()) + "-" + strconv.FormatInt(time.Now().UnixNano(), 10) + ".mp4"
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	if transcodeH264(ctx, transcodeSpec{src: src, dst: tmp, fps: fps, maxWidth: capW, qp: 23, crf: 23, audio: true}) != nil {
		_ = os.Remove(tmp)
		return ""
	}
	if os.Rename(tmp, out) != nil {
		_ = os.Remove(tmp)
		return ""
	}
	return out
}
