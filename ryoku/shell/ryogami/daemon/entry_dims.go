package main

import (
	"context"
	"image"
	// Registers the gif header decoder; jpeg and png come in with the effects pipeline.
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

func fillDims(e *Entry, it scanned) {
	var w, h int
	if it.wpType == "video" {
		w, h = videoProbeDims(it.src)
	} else {
		w, h = imageConfigDims(it.src)
	}
	if w > 0 && h > 0 {
		e.Width = w
		e.Height = h
	}
}

func imageConfigDims(path string) (int, int) {
	f, err := os.Open(path)
	if err != nil {
		return 0, 0
	}
	cfg, _, decErr := image.DecodeConfig(f)
	f.Close()
	if decErr == nil {
		return cfg.Width, cfg.Height
	}
	return magickIdentifyDims(path)
}

func magickIdentifyDims(path string) (int, int) {
	ctx, cancel := context.WithTimeout(context.Background(), cmdTimeout)
	defer cancel()
	// [0] pins a multi-frame source (animated webp, tiff) to its first frame.
	out, err := exec.CommandContext(ctx, "magick", "identify",
		"-format", "%w %h", path+"[0]").Output()
	if err != nil {
		return 0, 0
	}
	fields := strings.Fields(strings.TrimSpace(string(out)))
	if len(fields) < 2 {
		return 0, 0
	}
	w, _ := strconv.Atoi(fields[0])
	h, _ := strconv.Atoi(fields[1])
	return w, h
}

func videoProbeDims(path string) (int, int) {
	ctx, cancel := context.WithTimeout(context.Background(), cmdTimeout)
	defer cancel()
	_, w, h, err := probeVideo(ctx, path)
	if err != nil {
		return 0, 0
	}
	return w, h
}
