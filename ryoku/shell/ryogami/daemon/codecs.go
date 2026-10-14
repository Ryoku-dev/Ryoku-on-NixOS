package main

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"sync"
)

type codecSet map[string]bool

type ffmpegCodecSupport struct {
	encoders codecSet
	decoders codecSet
}

var (
	ffmpegCodecOnce    sync.Once
	ffmpegCodecCurrent ffmpegCodecSupport
)

func parseFFmpegCodecList(output string) codecSet {
	set := codecSet{}
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) > 1 && len(fields[0]) == 6 {
			set[fields[1]] = true
		}
	}
	return set
}

func codecSupportFromLists(encoders, decoders string) ffmpegCodecSupport {
	return ffmpegCodecSupport{
		encoders: parseFFmpegCodecList(encoders),
		decoders: parseFFmpegCodecList(decoders),
	}
}

func ffmpegCodecs() ffmpegCodecSupport {
	ffmpegCodecOnce.Do(func() {
		encoders, _ := exec.Command("ffmpeg", "-hide_banner", "-encoders").Output()
		decoders, _ := exec.Command("ffmpeg", "-hide_banner", "-decoders").Output()
		ffmpegCodecCurrent = codecSupportFromLists(string(encoders), string(decoders))
	})
	return ffmpegCodecCurrent
}

func hasEncoderIn(encoders codecSet, name string) bool { return encoders[name] }
func hasDecoderIn(decoders codecSet, name string) bool { return decoders[name] }

func hasEncoder(name string) bool { return hasEncoderIn(ffmpegCodecs().encoders, name) }
func hasDecoder(name string) bool { return hasDecoderIn(ffmpegCodecs().decoders, name) }

func pickCPUH264Encoder(encoders codecSet) (string, error) {
	if hasEncoderIn(encoders, "libx264") {
		return "libx264", nil
	}
	if hasEncoderIn(encoders, "libopenh264") {
		return "libopenh264", nil
	}
	return "", fmt.Errorf("H.264 encoding is unavailable: this system's ffmpeg has neither libx264 nor libopenh264")
}

func h264BitrateKbps(width, fps int) int {
	if width < 2 {
		width = 1920
	}
	if fps < 1 {
		fps = 30
	}
	// An estimated 16:9 frame at 0.08 bits per pixel keeps OpenH264 previews
	// useful without letting high-refresh 4K cache clips grow without bound.
	kbps := int(int64(width) * int64(width) * 9 * int64(fps) / 16 / 12500)
	if kbps < 500 {
		return 500
	}
	if kbps > 16000 {
		return 16000
	}
	return kbps
}

func h264CPUArgs(encoder string, width, fps int, x264Tail ...string) ([]string, error) {
	switch encoder {
	case "libx264":
		return append([]string{"-c:v", "libx264"}, x264Tail...), nil
	case "libopenh264":
		bitrate := h264BitrateKbps(width, fps)
		return []string{
			"-c:v", "libopenh264",
			"-profile:v", "constrained_baseline",
			"-b:v", strconv.Itoa(bitrate) + "k",
			"-maxrate", strconv.Itoa(bitrate) + "k",
			"-bufsize", strconv.Itoa(bitrate*2) + "k",
			"-bf", "0", "-threads", "4", "-pix_fmt", "yuv420p",
		}, nil
	default:
		return nil, fmt.Errorf("H.264 encoding is unavailable: unsupported CPU encoder %q", encoder)
	}
}

func canDecodeVideoCodec(codec string, decoders codecSet) bool {
	switch strings.ToLower(codec) {
	case "h264":
		return hasDecoderIn(decoders, "h264") || hasDecoderIn(decoders, "libopenh264")
	case "av1":
		return hasDecoderIn(decoders, "av1") || hasDecoderIn(decoders, "libdav1d") || hasDecoderIn(decoders, "libaom-av1")
	case "vp8":
		return hasDecoderIn(decoders, "vp8") || hasDecoderIn(decoders, "libvpx")
	case "vp9":
		return hasDecoderIn(decoders, "vp9") || hasDecoderIn(decoders, "libvpx-vp9")
	default:
		return codec == "" || hasDecoderIn(decoders, strings.ToLower(codec))
	}
}

func videoCodecName(codec string) string {
	switch strings.ToLower(codec) {
	case "h264":
		return "H.264"
	case "hevc", "h265":
		return "HEVC"
	case "av1":
		return "AV1"
	case "vp8":
		return "VP8"
	case "vp9":
		return "VP9"
	case "mpeg4":
		return "MPEG-4"
	default:
		return strings.ToUpper(codec)
	}
}

func videoDecodeError(codec string, decoders codecSet) error {
	if codec == "" || canDecodeVideoCodec(codec, decoders) {
		return nil
	}
	return fmt.Errorf("This video uses %s, which this system's ffmpeg cannot decode", videoCodecName(codec))
}
