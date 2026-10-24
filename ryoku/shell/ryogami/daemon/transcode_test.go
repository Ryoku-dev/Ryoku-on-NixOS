package main

import (
	"os"
	"path/filepath"
	"testing"
)

const ffmpegEncoders = ` V....D h264_nvenc           NVIDIA NVENC H.264 encoder (codec h264)
 V....D h264_vaapi           H.264/AVC (VAAPI) (codec h264)
 V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)
`

func fakeRenderNode(t *testing.T, drm, name, driver, vram string) {
	t.Helper()
	dev := filepath.Join(drm, name, "device")
	if err := os.MkdirAll(dev, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("../../../bus/pci/drivers/"+driver, filepath.Join(dev, "driver")); err != nil {
		t.Fatal(err)
	}
	if vram != "" {
		if err := os.WriteFile(filepath.Join(dev, "mem_info_vram_total"), []byte(vram+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestVideoEncodesLandOnTheStrongestGPU(t *testing.T) {
	hybrid := t.TempDir()
	fakeRenderNode(t, hybrid, "renderD128", "nvidia", "")
	fakeRenderNode(t, hybrid, "renderD129", "amdgpu", "536870912")

	twoRadeons := t.TempDir()
	fakeRenderNode(t, twoRadeons, "renderD128", "amdgpu", "536870912")
	fakeRenderNode(t, twoRadeons, "renderD129", "amdgpu", "8589934592")

	cases := []struct {
		name     string
		drm      string
		nvidia   bool
		radeonsi bool
		encoders codecSet
		want     videoEncoder
	}{
		{"NVIDIA with an APU encodes on NVENC", hybrid, true, true, parseFFmpegCodecList(ffmpegEncoders), videoEncoder{nvenc: true, cpu: "libx264"}},
		{"NVIDIA without NVENC falls back to the CPU, not the APU", hybrid, true, true, parseFFmpegCodecList(" V....D h264_vaapi  VAAPI\n V....D libx264 x264\n"), videoEncoder{cpu: "libx264"}},
		{"two Radeons pick the one with more VRAM", twoRadeons, false, true, parseFFmpegCodecList(ffmpegEncoders), videoEncoder{vaapi: "/dev/dri/renderD129", cpu: "libx264"}},
		{"no VA-API driver leaves the CPU", twoRadeons, false, false, parseFFmpegCodecList(ffmpegEncoders), videoEncoder{cpu: "libx264"}},
	}
	for _, c := range cases {
		if got := detectVideoEncoder(c.drm, c.nvidia, c.radeonsi, c.encoders); got != c.want {
			t.Errorf("%s: got %+v, want %+v", c.name, got, c.want)
		}
	}
}

func TestVAAPIDriverSearchPaths(t *testing.T) {
	const driver = "radeonsi_drv_video.so"
	for _, label := range []string{"lib", "lib64", "multiarch"} {
		t.Run(label, func(t *testing.T) {
			dir := filepath.Join(t.TempDir(), label, "dri")
			if err := os.MkdirAll(dir, 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, driver), nil, 0o644); err != nil {
				t.Fatal(err)
			}
			if !vaapiDriverAvailable("", []string{dir}) {
				t.Fatalf("driver in %s was not found", dir)
			}
		})
	}

	envDir := filepath.Join(t.TempDir(), "custom")
	if err := os.MkdirAll(envDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(envDir, driver), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if !vaapiDriverAvailable(filepath.Join(t.TempDir(), "missing")+string(os.PathListSeparator)+envDir, nil) {
		t.Fatal("LIBVA_DRIVERS_PATH entry was not searched")
	}

	want := []string{"/usr/lib/dri", "/usr/lib64/dri", "/usr/lib/x86_64-linux-gnu/dri"}
	if len(defaultVAAPIDriverDirs) != len(want) {
		t.Fatalf("default driver dirs: got %v want %v", defaultVAAPIDriverDirs, want)
	}
	for i := range want {
		if defaultVAAPIDriverDirs[i] != want[i] {
			t.Fatalf("default driver dirs: got %v want %v", defaultVAAPIDriverDirs, want)
		}
	}
}
