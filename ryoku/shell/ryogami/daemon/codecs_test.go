package main

import (
	"reflect"
	"strings"
	"testing"
)

const archCodecEncoders = ` V....D h264_nvenc           NVIDIA NVENC H.264 encoder (codec h264)
 V....D h264_vaapi           H.264/AVC (VAAPI) (codec h264)
 V....D libx264              libx264 H.264 / AVC (codec h264)
 V....D libx265              libx265 H.265 / HEVC (codec hevc)
`

const fedoraCodecEncoders = ` V....D h264_vaapi           H.264/AVC (VAAPI) (codec h264)
 V....D libopenh264          OpenH264 H.264 / AVC (codec h264)
 V....D libvpx-vp9           libvpx VP9 (codec vp9)
`

func TestCPUH264Selection(t *testing.T) {
	arch := parseFFmpegCodecList(archCodecEncoders)
	fedora := parseFFmpegCodecList(fedoraCodecEncoders)

	if got, err := pickCPUH264Encoder(arch); err != nil || got != "libx264" {
		t.Fatalf("Arch selection: encoder=%q err=%v", got, err)
	}
	if got, err := pickCPUH264Encoder(fedora); err != nil || got != "libopenh264" {
		t.Fatalf("Fedora selection: encoder=%q err=%v", got, err)
	}
	if _, err := pickCPUH264Encoder(codecSet{"libvpx": true}); err == nil ||
		!strings.Contains(err.Error(), "neither libx264 nor libopenh264") {
		t.Fatalf("missing encoder error: %v", err)
	}

	none := detectVideoEncoder(t.TempDir(), false, false, codecSet{"libvpx": true})
	if _, err := none.attempts(transcodeSpec{src: "in", dst: "out", fps: 30, maxWidth: 1920}); err == nil ||
		!strings.Contains(err.Error(), "libx264") || !strings.Contains(err.Error(), "libopenh264") {
		t.Fatalf("transcode missing encoder error: %v", err)
	}
}

func TestArchTranscodeArgvUnchanged(t *testing.T) {
	s := transcodeSpec{src: "in.mp4", dst: "out.mp4", fps: 30, maxWidth: 1920, qp: 20, crf: 18}
	encoder := detectVideoEncoder(t.TempDir(), false, false, parseFFmpegCodecList(archCodecEncoders))
	runs, err := encoder.attempts(s)
	if err != nil {
		t.Fatal(err)
	}
	want := [][]string{{
		"nice", "-n", "19", "ffmpeg", "-y", "-v", "error", "-i", "in.mp4",
		"-vf", "fps=30,scale='trunc(min(1920,iw)/2)*2':-2:flags=bicubic",
		"-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-bf", "0",
		"-threads", "4", "-pix_fmt", "yuv420p", "-an", "out.mp4",
	}}
	if !reflect.DeepEqual(runs, want) {
		t.Fatalf("Arch argv changed:\n got %v\nwant %v", runs, want)
	}
}

func TestFedoraTranscodeUsesOpenH264(t *testing.T) {
	s := transcodeSpec{src: "in.mp4", dst: "out.mp4", fps: 30, maxWidth: 1280, qp: 20, crf: 18}
	encoder := detectVideoEncoder(t.TempDir(), false, false, parseFFmpegCodecList(fedoraCodecEncoders))
	runs, err := encoder.attempts(s)
	if err != nil {
		t.Fatal(err)
	}
	if len(runs) != 1 {
		t.Fatalf("attempt count=%d, want 1", len(runs))
	}
	joined := strings.Join(runs[0], " ")
	for _, want := range []string{"-c:v libopenh264", "-profile:v constrained_baseline", "-b:v 2211k", "-maxrate 2211k", "-bufsize 4422k", "-pix_fmt yuv420p"} {
		if !strings.Contains(joined, want) {
			t.Fatalf("OpenH264 argv lacks %q: %v", want, runs[0])
		}
	}
	for _, forbidden := range []string{"libx264", "-crf", "-preset"} {
		if strings.Contains(joined, forbidden) {
			t.Fatalf("OpenH264 argv contains x264-only %q: %v", forbidden, runs[0])
		}
	}
}

func TestH264BuildersUseInjectedEncoderList(t *testing.T) {
	arch := parseFFmpegCodecList(archCodecEncoders)
	fedora := parseFFmpegCodecList(fedoraCodecEncoders)

	animated, err := animatedH264Args(arch)
	if err != nil {
		t.Fatal(err)
	}
	wantAnimated := []string{"-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p"}
	if !reflect.DeepEqual(animated, wantAnimated) {
		t.Fatalf("animated Arch args: got %v want %v", animated, wantAnimated)
	}

	assemble, err := buildAssembleArgs(fedora, "frames/%08d.png", "clip.mp4", "out.mp4", "30/1", 1920)
	if err != nil {
		t.Fatal(err)
	}
	joined := strings.Join(assemble, " ")
	if !strings.Contains(joined, "-c:v libopenh264") || strings.Contains(joined, "libx264") {
		t.Fatalf("Fedora assemble args: %v", assemble)
	}
}

func TestVideoDecoderAliasesAndMissingHEVC(t *testing.T) {
	fedora := codecSupportFromLists(fedoraCodecEncoders, ` V....D libopenh264 OpenH264 H.264 decoder (codec h264)
 VFS..D av1 Alliance for Open Media AV1
 VFS..D vp9 Google VP9
`)
	if err := videoDecodeError("h264", fedora.decoders); err != nil {
		t.Fatalf("libopenh264 should satisfy H.264 decode: %v", err)
	}
	err := videoSourceDecodeError(liveShape{codec: "hevc"}, fedora.decoders)
	if err == nil || err.Error() != "This video uses HEVC, which this system's ffmpeg cannot decode" {
		t.Fatalf("HEVC error=%v", err)
	}

	arch := codecSupportFromLists(archCodecEncoders, " VFS..D hevc HEVC decoder\n")
	if err := videoSourceDecodeError(liveShape{codec: "hevc"}, arch.decoders); err != nil {
		t.Fatalf("native HEVC decoder was not recognised: %v", err)
	}
}

func TestLibx265ArgvUnchanged(t *testing.T) {
	preset := videoPreset{crf: 26, maxrate: "10M", bufsize: "20M"}
	res := resolution{maxW: 1920, maxH: 1080}
	got := buildConvertArgs("in.mp4", "out.mp4", preset, res)
	want := []string{
		"-y", "-i", "in.mp4", "-c:v", "libx265", "-preset", "medium", "-crf", "26",
		"-maxrate", "10M", "-bufsize", "20M",
		"-vf", "scale=min(1920\\,iw):min(1080\\,ih):force_original_aspect_ratio=decrease:force_divisible_by=2",
		"-an", "-movflags", "+faststart", "-tag:v", "hvc1", "out.mp4",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("libx265 argv changed:\n got %v\nwant %v", got, want)
	}
}

func TestVideoOptimizeAvailability(t *testing.T) {
	if !videoOptimizeAvailable(parseFFmpegCodecList(archCodecEncoders)) {
		t.Fatal("libx265 should make video optimisation available")
	}
	if videoOptimizeAvailable(parseFFmpegCodecList(fedoraCodecEncoders)) {
		t.Fatal("video optimisation must be unavailable without libx265")
	}
	if got := videoOptimizeUnavailableError().Error(); !strings.Contains(got, "no libx265 encoder") {
		t.Fatalf("unavailable reason=%q", got)
	}
}
