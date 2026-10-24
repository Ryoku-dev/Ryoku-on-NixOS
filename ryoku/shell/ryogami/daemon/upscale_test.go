package main

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"
)

// mockUpscaler builds an Upscaler whose exec seam is fully faked, so the branch
// logic runs with no external binary present.
func mockUpscaler(t *testing.T, lookOK map[string]bool, runOut func(name string, args ...string) (string, error)) *Upscaler {
	t.Helper()
	return &Upscaler{
		stateDir: t.TempDir(),
		lookPath: func(name string) (string, error) {
			if lookOK[name] {
				return "/usr/bin/" + name, nil
			}
			return "", fmt.Errorf("not found: %s", name)
		},
		runOut: func(_ context.Context, _ time.Duration, name string, args ...string) ([]byte, error) {
			s, err := runOut(name, args...)
			return []byte(s), err
		},
	}
}

func argsHave(args []string, want string) bool {
	for _, a := range args {
		if a == want {
			return true
		}
	}
	return false
}

func TestNormalizeUpscaleKind(t *testing.T) {
	cases := []struct {
		kind, input, want string
	}{
		{"", "a.png", upscaleKindImage},
		{"", "a.jpg", upscaleKindImage},
		{"", "clip.mp4", upscaleKindVideo},
		{"", "clip.WEBM", upscaleKindVideo},
		{"", "clip.mkv", upscaleKindVideo},
		{"", "clip.mov", upscaleKindVideo},
		{"image", "clip.mp4", upscaleKindImage}, // explicit wins over the extension
		{"video", "a.png", upscaleKindVideo},
		{"bogus", "a.png", "bogus"}, // passed through so Start can reject it
	}
	for _, c := range cases {
		if got := normalizeUpscaleKind(c.kind, c.input); got != c.want {
			t.Fatalf("normalizeUpscaleKind(%q,%q)=%q want %q", c.kind, c.input, got, c.want)
		}
	}
}

func TestUpscaleArgBuilders(t *testing.T) {
	w := buildWaifu2xArgs("in.png", "out.png", 2, 1)
	want := []string{"-i", "in.png", "-o", "out.png", "-s", "2", "-n", "2", "-g", "1", "-m", waifu2xModel}
	if !reflect.DeepEqual(w, want) {
		t.Fatalf("waifu2x args:\n got %v\nwant %v", w, want)
	}
	// scale is a parameter, not the hardcoded 2.
	if got := buildWaifu2xArgs("d/in", "d/out", 4, 0); !argsHave(got, "4") || !argsHave(got, "d/in") {
		t.Fatalf("waifu2x scale/dir not applied: %v", got)
	}

	ex := buildExtractArgs("clip.mp4", "d/in/%08d.png")
	wantEx := []string{"-y", "-i", "clip.mp4", "-qscale:v", "1", "-qmin", "1", "-qmax", "1", "-vsync", "0", "d/in/%08d.png"}
	if !reflect.DeepEqual(ex, wantEx) {
		t.Fatalf("extract args:\n got %v\nwant %v", ex, wantEx)
	}

	as, err := buildAssembleArgs(codecSet{"libx264": true}, "d/out/%08d.png", "clip.mp4", "final.mp4", "30/1", 1920)
	if err != nil {
		t.Fatal(err)
	}
	wantAs := []string{"-y", "-framerate", "30/1", "-i", "d/out/%08d.png", "-i", "clip.mp4", "-map", "0:v:0", "-map", "1:a:0?", "-c:a", "copy", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "final.mp4"}
	if !reflect.DeepEqual(as, wantAs) {
		t.Fatalf("assemble args:\n got %v\nwant %v", as, wantAs)
	}
}

func TestWaifu2xOrderList(t *testing.T) {
	// discrete first, then the last-good pref, then all indices, de-duplicated.
	if got := waifu2xOrderList("2", "1"); !reflect.DeepEqual(got, []int{2, 1, 0, 3}) {
		t.Fatalf("order with disc+pref: %v", got)
	}
	// no discrete/pref: the plain 0..3 sweep.
	if got := waifu2xOrderList("", ""); !reflect.DeepEqual(got, []int{0, 1, 2, 3}) {
		t.Fatalf("order bare: %v", got)
	}
	// junk indices are dropped.
	if got := waifu2xOrderList("9", "x"); !reflect.DeepEqual(got, []int{0, 1, 2, 3}) {
		t.Fatalf("order with junk: %v", got)
	}
}

func TestParseDiscreteGPU(t *testing.T) {
	// dGPU at index 1, integrated iGPU at 0 -> pick 1.
	banner := "[0 AMD Radeon Graphics (RADV PHOENIX)]\n[1 NVIDIA GeForce RTX 4060]\n"
	if got := parseDiscreteGPU(banner); got != "1" {
		t.Fatalf("discrete pick: got %q want 1", got)
	}
	// only an integrated GPU -> none.
	if got := parseDiscreteGPU("[0 Intel Iris Xe Graphics]"); got != "" {
		t.Fatalf("integrated-only should yield no discrete, got %q", got)
	}
	// no banner at all.
	if got := parseDiscreteGPU("waifu2x-ncnn-vulkan usage..."); got != "" {
		t.Fatalf("no banner should yield no discrete, got %q", got)
	}
}

func TestUpscaleVerdictShape(t *testing.T) {
	v := upscaleVerdict("sharp", "image", 2400, 2160, "", "")
	if v["result"] != "sharp" || v["kind"] != "image" || v["px"] != 2400 || v["cap"] != 2160 {
		t.Fatalf("verdict core wrong: %v", v)
	}
	if _, has := v["out"]; has {
		t.Fatalf("empty out should be omitted: %v", v)
	}
	if _, has := v["why"]; has {
		t.Fatalf("empty why should be omitted: %v", v)
	}
	done := upscaleVerdict("done", "video", 0, 0, "/x/clip.mp4", "")
	if done["out"] != "/x/clip.mp4" {
		t.Fatalf("out not carried: %v", done)
	}
	fail := upscaleVerdict("error", "video", 0, 0, "", "gpu")
	if fail["why"] != "gpu" {
		t.Fatalf("why not carried: %v", fail)
	}
}

func TestUpscaleStatusShape(t *testing.T) {
	u := NewUpscaler(t.TempDir(), nil)
	st := u.Status()
	for _, k := range []string{"running", "phase", "progress", "total", "file", "kind", "verdict"} {
		if _, ok := st[k]; !ok {
			t.Fatalf("status missing key %q: %v", k, st)
		}
	}
	if st["running"] != false {
		t.Fatalf("fresh job should not be running: %v", st["running"])
	}
	if st["progress"] != 0 || st["total"] != 0 {
		t.Fatalf("fresh counters should be zero: %v", st)
	}
	// A fresh job carries no verdict; on the wire that is JSON null.
	if b, _ := json.Marshal(st); !strings.Contains(string(b), `"verdict":null`) {
		t.Fatalf("fresh verdict should marshal to null: %s", b)
	}
}

func TestUpscaleStartRejects(t *testing.T) {
	u := NewUpscaler(t.TempDir(), nil)

	if err := u.Start("", "", defaultUpscaleScale); err == nil {
		t.Fatal("empty input should error")
	}
	if err := u.Start("a.png", "bogus", defaultUpscaleScale); err == nil {
		t.Fatal("unknown kind should error")
	}

	// A concurrent run is refused; setting running directly avoids spawning exec.
	u.mu.Lock()
	u.job.running = true
	u.mu.Unlock()
	if err := u.Start("a.png", "image", defaultUpscaleScale); err == nil {
		t.Fatal("second concurrent run should be rejected")
	}
}

// The early-exit branches of the enhance paths must resolve to the right verdict
// without any binary, driven entirely through the mocked exec seam.
func TestEnhanceImageBranches(t *testing.T) {
	ctx := context.Background()

	// unreadable source -> error/read.
	u := mockUpscaler(t, map[string]bool{"waifu2x-ncnn-vulkan": true}, func(name string, args ...string) (string, error) {
		return "0", nil // identify %h -> 0
	})
	if v := u.enhanceImage(ctx, "x.png", 2); v["result"] != "error" || v["why"] != "read" {
		t.Fatalf("unreadable: %v", v)
	}

	// already 4K -> sharp, no tool needed.
	u = mockUpscaler(t, map[string]bool{}, func(name string, args ...string) (string, error) {
		return "2160", nil
	})
	if v := u.enhanceImage(ctx, "x.png", 2); v["result"] != "sharp" || v["px"] != 2160 || v["cap"] != waifu2xImageSharpCap {
		t.Fatalf("sharp: %v", v)
	}

	// enhanceable but no waifu2x installed -> unsupported.
	u = mockUpscaler(t, map[string]bool{}, func(name string, args ...string) (string, error) {
		return "1080", nil
	})
	if v := u.enhanceImage(ctx, "x.png", 2); v["result"] != "unsupported" {
		t.Fatalf("unsupported: %v", v)
	}
}

func TestEnhanceVideoBranches(t *testing.T) {
	ctx := context.Background()

	// ffmpeg missing -> error/tools.
	u := mockUpscaler(t, map[string]bool{}, func(name string, args ...string) (string, error) {
		return "", fmt.Errorf("unexpected %s", name)
	})
	if v := u.enhanceVideo(ctx, "clip.mp4", 2); v["result"] != "error" || v["why"] != "tools" {
		t.Fatalf("tools: %v", v)
	}

	// ffmpeg present, waifu2x missing -> unsupported.
	u = mockUpscaler(t, map[string]bool{"ffmpeg": true}, func(name string, args ...string) (string, error) {
		return "", fmt.Errorf("unexpected %s", name)
	})
	if v := u.enhanceVideo(ctx, "clip.mp4", 2); v["result"] != "unsupported" {
		t.Fatalf("unsupported: %v", v)
	}

	// both present, source already at/over the screen cap -> sharp. No compositor,
	// so the cap falls back to 1920; a 3000px-wide clip clears it.
	seedOutputs(t, nil)
	u = mockUpscaler(t, map[string]bool{"ffmpeg": true, "waifu2x-ncnn-vulkan": true}, func(name string, args ...string) (string, error) {
		switch name {
		case "ffprobe":
			if argsHave(args, "stream=width") {
				return "3000", nil
			}
			return "", nil
		}
		return "", fmt.Errorf("unexpected %s", name)
	})
	v := u.enhanceVideo(ctx, "clip.mp4", 2)
	if v["result"] != "sharp" || v["px"] != 3000 || v["cap"] != 1920 {
		t.Fatalf("sharp: %v", v)
	}
}

func TestParseFrameRate(t *testing.T) {
	cases := map[string]float64{"30/1": 30, "60000/1001": 60000.0 / 1001.0, "25": 25, "0/0": 0, "": 0, "junk": 0}
	for in, want := range cases {
		if got := parseFrameRate(in); got != want {
			t.Fatalf("parseFrameRate(%q)=%v want %v", in, got, want)
		}
	}
}
