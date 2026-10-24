package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func init() {
	registerAction("ClearCache", actionClearCache)
	registerAction("RecomputeColors", actionRecomputeColors)
	registerAction("CaptureWeThumbnails", actionCaptureWeThumbnails)
	registerAction("ConvertVideos", actionConvertVideos)
}

func actionClearCache(d *daemon, _ map[string]interface{}) (interface{}, error) {
	go d.resetCache()
	return map[string]interface{}{"started": true}, nil
}

func actionConvertVideos(d *daemon, args map[string]interface{}) (interface{}, error) {
	if d.optimizer == nil {
		return nil, fmt.Errorf("converter unavailable")
	}
	preset := strParam(args, "preset", d.settingString("performance.videoConvertPreset"))
	res := strParam(args, "resolution", d.settingString("performance.videoConvertResolution"))
	if err := d.optimizer.Start(kindConvert, preset, res, nil); err != nil {
		return nil, err
	}
	return map[string]interface{}{"started": true}, nil
}

func actionRecomputeColors(d *daemon, _ map[string]interface{}) (interface{}, error) {
	go d.recomputeColors()
	return map[string]interface{}{"started": true}, nil
}

func (d *daemon) recomputeColors() {
	for _, e := range d.store.snapshotEntries() {
		if e.Thumb == "" || !fileExists(e.Thumb) {
			continue
		}
		hue, sat, richness := extractColors(e.Thumb)
		key := e.Key
		d.store.mutate(key, func(x *Entry) {
			x.Hue = int(hueBucket(hue, sat))
			x.Sat = int(sat)
			x.Richness = int(richness)
		})
		if updated, ok := d.store.get(key); ok {
			d.broadcast("ryogami.wall.cached", updated)
		}
	}
	d.broadcast("ryogami.wall.recompute_colors.complete", map[string]interface{}{})
}

func actionCaptureWeThumbnails(d *daemon, _ map[string]interface{}) (interface{}, error) {
	bin := skwdStillBinary()
	if bin == "" {
		return nil, fmt.Errorf("skwd-wall-still is not installed")
	}
	go d.captureWeThumbnails(bin)
	return map[string]interface{}{"started": true}, nil
}

func (d *daemon) captureWeThumbnails(bin string) {
	cacheDir := d.config().cacheDir()
	var scenes []Entry
	for _, e := range d.store.snapshotEntries() {
		if e.Type == "we" && e.WeID != "" {
			scenes = append(scenes, e)
		}
	}
	d.tasks.start("we-thumbnails", "capture", "Scene thumbnails", len(scenes), nil)
	var captured, skipped, failed int
	for i, e := range scenes {
		d.tasks.progress("we-thumbnails", i, len(scenes), e.Name)
		src := weStillSource(e)
		if src == "" {
			skipped++
			continue
		}
		thumb, thumbSm := weThumbPaths(cacheDir, e.WeID)
		if err := captureStill(bin, src, thumb); err != nil {
			fmt.Fprintf(os.Stderr, "ryogami: WE still failed for %s: %v\n", e.WeID, err)
			failed++
			continue
		}
		if err := genSmallThumb(thumb, thumbSm); err != nil {
			fmt.Fprintf(os.Stderr, "ryogami: WE small thumb failed for %s: %v\n", e.WeID, err)
			failed++
			continue
		}
		key := e.Key
		d.store.mutate(key, func(x *Entry) {
			x.Thumb = thumb
			x.ThumbSm = thumbSm
			hue, sat, richness := extractColors(thumb)
			x.Hue = int(hueBucket(hue, sat))
			x.Sat = int(sat)
			x.Richness = int(richness)
		})
		if updated, ok := d.store.get(key); ok {
			d.broadcast("ryogami.wall.cached", updated)
		}
		captured++
	}
	state := taskCompleted
	if failed > 0 && captured == 0 {
		state = taskFailed
	}
	d.tasks.finish("we-thumbnails", state, len(scenes), "")
	d.broadcast("ryogami.wall.we_capture.complete", map[string]interface{}{
		"captured": captured, "skipped": skipped, "failed": failed,
	})
}

func weStillSource(e Entry) string {
	if e.Preview != "" && fileExists(e.Preview) {
		return e.Preview
	}
	return ""
}

func skwdStillBinary() string {
	if p := os.Getenv("SKWD_PAPER_STILL_BIN"); p != "" && fileExists(p) {
		return p
	}
	if p, err := exec.LookPath("skwd-wall-still"); err == nil {
		return p
	}
	return ""
}

// Video and gif previews reduce to their first frame: the still renderer decodes images only.
func captureStill(bin, src, dest string) error {
	still := src
	if needsFirstFrame(src) {
		frame, err := extractFirstFrame(src)
		if frame != "" {
			defer os.Remove(frame)
		}
		if err != nil {
			return err
		}
		still = frame
	}
	rgba, err := renderStillRGBA(bin, still)
	if err != nil {
		return err
	}
	return encodeRGBAWebP(rgba, thumbW, thumbH, dest)
}

func needsFirstFrame(src string) bool {
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(src), "."))
	return videoExts[ext] || ext == "gif"
}

func extractFirstFrame(src string) (string, error) {
	tmp := filepath.Join(os.TempDir(), fmt.Sprintf("ryogami-we-%d.png", time.Now().UnixNano()))
	ctx, cancel := context.WithTimeout(context.Background(), cmdTimeout)
	defer cancel()
	if err := exec.CommandContext(ctx, "ffmpeg", "-y", "-i", src, "-frames:v", "1", tmp).Run(); err != nil {
		return "", err
	}
	return tmp, nil
}

// stdin stays closed so the renderer exits after the one frame.
func renderStillRGBA(bin, src string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), cmdTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, "*", src,
		"--frame-stream", fmt.Sprintf("%dx%d", thumbW, thumbH),
		"--stream-no-header",
		"--fill-mode", "fill")
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return nil, err
	}
	want := thumbW * thumbH * 4
	if b := out.Bytes(); len(b) >= want {
		return b[:want], nil
	}
	return nil, fmt.Errorf("still frame short: %d of %d bytes", out.Len(), want)
}

func encodeRGBAWebP(rgba []byte, w, h int, dest string) error {
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	tmp := tmpPath(dest)
	ctx, cancel := context.WithTimeout(context.Background(), cmdTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "magick",
		"-size", fmt.Sprintf("%dx%d", w, h), "-depth", "8", "rgba:-",
		"-quality", "85", tmp)
	cmd.Stdin = bytes.NewReader(rgba)
	if out, err := cmd.CombinedOutput(); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("magick encode: %v: %s", err, out)
	}
	return os.Rename(tmp, dest)
}
