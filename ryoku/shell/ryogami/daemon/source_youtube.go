package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const youtubeBin = "yt-dlp"

const (
	ytOversample = 4
	ytMaxSearch  = 200
	ytMaxIDLen   = 24
)

func youtubeWatchURL(id string) string { return "https://www.youtube.com/watch?v=" + id }
func youtubeThumbURL(id string) string { return "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg" }
func youtubePreviewURL(id string) string {
	return "https://i.ytimg.com/vi/" + id + "/maxresdefault.jpg"
}

func youtubeSafeID(id string) bool {
	if id == "" || len(id) > ytMaxIDLen {
		return false
	}
	for _, ch := range id {
		if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
			(ch >= '0' && ch <= '9') || ch == '-' || ch == '_') {
			return false
		}
	}
	return true
}

func fmtDuration(secs float64) string {
	total := int64(math.Max(secs, 0))
	hr, min, sec := total/3600, (total%3600)/60, total%60
	if hr > 0 {
		return fmt.Sprintf("%d:%02d:%02d", hr, min, sec)
	}
	return fmt.Sprintf("%d:%02d", min, sec)
}

// Oversampled so enough candidates survive the client-side duration filter to fill a page.
func rawSearchSize(page, perPage int, maxSecs int64) int {
	end := max(page, 1) * max(perPage, 1)
	over := 1
	if maxSecs > 0 {
		over = ytOversample
	}
	n := end*over + 1
	if n > ytMaxSearch {
		n = ytMaxSearch
	}
	return n
}

func keepsDuration(dur, maxSecs int64) bool {
	if maxSecs == 0 {
		return true
	}
	return dur > 0 && dur <= maxSecs
}

type ytThumb struct {
	URL    string `json:"url"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
}

type ytEntry struct {
	ID         string    `json:"id"`
	Title      string    `json:"title"`
	Duration   *float64  `json:"duration"`
	Channel    string    `json:"channel"`
	Uploader   string    `json:"uploader"`
	Thumbnails []ytThumb `json:"thumbnails"`
	LiveStatus *string   `json:"live_status"`
}

func parseYoutubeSearch(ndjson string, page, perPage int, maxSecs int64) sourcePage {
	all := make([]sourceResult, 0)
	for _, line := range strings.Split(ndjson, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var e ytEntry
		if json.Unmarshal([]byte(line), &e) != nil {
			continue
		}
		if !youtubeSafeID(e.ID) {
			continue
		}
		if e.LiveStatus != nil && *e.LiveStatus == "is_live" {
			continue
		}
		r := sourceResult{id: e.ID, fullURL: youtubeWatchURL(e.ID), title: e.Title}
		best := ""
		bestArea := int64(-1)
		for _, t := range e.Thumbnails {
			if t.URL == "" {
				continue
			}
			if area := int64(t.Width) * int64(t.Height); area > bestArea {
				bestArea = area
				best = t.URL
			}
		}
		if best == "" {
			best = youtubeThumbURL(e.ID)
		}
		r.thumbURL = best
		var dur int64
		if e.Duration != nil {
			r.resolution = fmtDuration(*e.Duration)
			if *e.Duration > 0 {
				dur = int64(*e.Duration)
			}
		}
		r.durationSecs = uint64(dur)
		who := e.Channel
		if who == "" {
			who = e.Uploader
		}
		if who != "" {
			r.attribution = who
			r.attributionURL = youtubeWatchURL(e.ID)
		}
		if !keepsDuration(dur, maxSecs) {
			continue
		}
		all = append(all, r)
	}
	per := max(perPage, 1)
	pg := max(page, 1)
	start := (pg - 1) * per
	hasMore := len(all) > start+per
	results := make([]sourceResult, 0, per)
	if start < len(all) {
		end := start + per
		if end > len(all) {
			end = len(all)
		}
		results = append(results, all[start:end]...)
	}
	last := pg
	if hasMore {
		last = pg + 1
	}
	return sourcePage{results: results, lastPage: last, currentPage: pg}
}

func lastNonEmptyLine(text string) string {
	lines := strings.Split(text, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.TrimSpace(lines[i]) != "" {
			return strings.TrimSpace(lines[i])
		}
	}
	return ""
}

func youtubeMissingTool(action string) string {
	advice := "install yt-dlp"
	if out, err := exec.Command("ryoku-host", "pkg", "advice", "yt-dlp").Output(); err == nil {
		if value := strings.TrimSpace(string(out)); value != "" {
			advice = value
		}
	}
	return fmt.Sprintf("yt-dlp not found - %s to %s YouTube", advice, action)
}

func (s *sources) youtubeSearch(ctx context.Context, p map[string]interface{}) (sourcePage, error) {
	if !toolPresent(youtubeBin) {
		return sourcePage{}, errors.New(youtubeMissingTool("browse"))
	}
	query := strings.TrimSpace(strParam(p, "query", ""))
	if query == "" {
		query = "4k wallpaper"
	}
	page := int(intParam(p, "page", 1))
	if page < 1 {
		page = 1
	}
	const per = 24
	maxSecs := intParam(p, "max_duration", 0)
	if maxSecs < 0 {
		maxSecs = 0
	}
	raw := rawSearchSize(page, per, maxSecs)
	cmd := exec.CommandContext(ctx, youtubeBin,
		fmt.Sprintf("ytsearch%d:%s", raw, query),
		"--flat-playlist", "--dump-json", "--no-warnings")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if errors.Is(err, exec.ErrNotFound) {
			return sourcePage{}, errors.New(youtubeMissingTool("browse"))
		}
		return sourcePage{}, fmt.Errorf("yt-dlp search failed: %s", lastNonEmptyLine(stderr.String()))
	}
	return parseYoutubeSearch(stdout.String(), page, per, maxSecs), nil
}

func hhmmss(secs int64) string {
	return fmt.Sprintf("%d:%02d:%02d", secs/3600, (secs%3600)/60, secs%60)
}

func youtubeDownloadArgs(id, videoDir string, maxHeight int, startSecs, durSecs int64) []string {
	args := []string{
		"-f", fmt.Sprintf("bv*[height<=?%d]+ba/b[height<=?%d]/b", maxHeight, maxHeight),
		"--merge-output-format", "mp4",
		"--no-playlist", "--newline", "--no-warnings",
		"-o", fmt.Sprintf("%s/youtube-%s.%%(ext)s", videoDir, id),
	}
	if durSecs > 0 {
		end := startSecs + durSecs
		args = append(args, "--download-sections", fmt.Sprintf("*%s-%s", hhmmss(startSecs), hhmmss(end)))
	}
	return append(args, youtubeWatchURL(id))
}

// Tracks the yt-dlp stage so progress advances monotonically across both downloads and the mux.
type ytPhases struct {
	seen    int
	merging bool
}

func (ph *ytPhases) label() string {
	switch {
	case ph.merging:
		return "merging"
	case ph.seen <= 1:
		return "video"
	default:
		return "audio"
	}
}

func (ph *ytPhases) overall(pct float64) float64 {
	if ph.merging {
		return 0.98
	}
	if ph.seen <= 1 {
		return pct * 0.90
	}
	return 0.90 + pct*0.08
}

func ytExtractPercent(line string) (float64, bool) {
	rest, ok := strings.CutPrefix(line, "[download]")
	if !ok {
		return 0, false
	}
	rest = strings.TrimLeft(rest, " \t")
	idx := strings.Index(rest, "%")
	if idx < 0 {
		return 0, false
	}
	pct := strings.TrimSpace(rest[:idx])
	if pct == "" || !(pct[0] >= '0' && pct[0] <= '9') {
		return 0, false
	}
	val, err := strconv.ParseFloat(pct, 64)
	if err != nil {
		return 0, false
	}
	v := val / 100.0
	switch {
	case v < 0:
		v = 0
	case v > 1:
		v = 1
	}
	return v, true
}

func noteLine(ph *ytPhases, line string) (float64, bool) {
	if strings.HasPrefix(line, "[download] Destination:") {
		ph.seen++
		return 0, false
	}
	if strings.HasPrefix(line, "[Merger]") || strings.HasPrefix(line, "[VideoRemuxer]") {
		ph.merging = true
		return 0.98, true
	}
	if pct, ok := ytExtractPercent(line); ok {
		return ph.overall(pct), true
	}
	return 0, false
}

func parseFfmpegTime(line string) (float64, bool) {
	i := strings.Index(line, "time=")
	if i < 0 {
		return 0, false
	}
	field := strings.TrimSpace(line[i+5:])
	if sp := strings.IndexAny(field, " \t"); sp >= 0 {
		field = field[:sp]
	}
	parts := strings.Split(field, ":")
	if len(parts) != 3 {
		return 0, false
	}
	hr, e1 := strconv.ParseFloat(parts[0], 64)
	mn, e2 := strconv.ParseFloat(parts[1], 64)
	sc, e3 := strconv.ParseFloat(parts[2], 64)
	if e1 != nil || e2 != nil || e3 != nil {
		return 0, false
	}
	return hr*3600 + mn*60 + sc, true
}

func clipProgress(line string, durSecs int64) (float64, bool) {
	if durSecs == 0 {
		return 0, false
	}
	secs, ok := parseFfmpegTime(line)
	if !ok {
		return 0, false
	}
	v := secs / float64(durSecs)
	switch {
	case v < 0:
		v = 0
	case v > 0.98:
		v = 0.98
	}
	return v, true
}

func finishedYoutubeVideo(videoDir, id string) string {
	prefix := "youtube-" + id + "."
	entries, err := os.ReadDir(videoDir)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, prefix) && !strings.HasSuffix(name, ".part") {
			return filepath.Join(videoDir, name)
		}
	}
	return ""
}

func (s *sources) emitDownloadError(id, msg string) {
	m := msg
	s.emitDownload(downloadEvent{ID: id, Status: dlError, Error: &m})
}

func (s *sources) youtubeDownload(reqID int64, p map[string]interface{}) response {
	if !toolPresent(youtubeBin) {
		return errResp(reqID, -1, youtubeMissingTool("download from"))
	}
	id := strParam(p, "id", "")
	if !youtubeSafeID(id) {
		return errResp(reqID, -32602, "missing or invalid youtube id")
	}
	videoDir := s.d.config().videoDir()
	maxHeight := int(s.num("sources.youtube.maxHeight"))
	if maxHeight <= 0 {
		maxHeight = 2160
	}
	maxMinutes := s.num("sources.youtube.maxMinutes")
	if maxMinutes < 0 {
		maxMinutes = 0
	}
	startSecs := int64(0)
	durSecs := maxMinutes * 60
	if clip, ok := p["clip"].(map[string]interface{}); ok {
		startSecs = int64(numFrom(clip["start"]))
		if v, has := clip["dur"]; has {
			if d := int64(numFrom(v)); d > 0 {
				durSecs = d
			} else {
				durSecs = 0
			}
		}
	}
	if startSecs < 0 {
		startSecs = 0
	}
	if existing := finishedYoutubeVideo(videoDir, id); existing != "" {
		return s.respondExists(reqID, id, existing)
	}
	return s.startDownload(reqID, id, s.videos, "youtube:"+id, func(ctx context.Context, _ *gateSlot) {
		s.runYoutubeDownload(ctx, id, videoDir, maxHeight, startSecs, durSecs)
	})
}

func (s *sources) runYoutubeDownload(ctx context.Context, id, videoDir string, maxHeight int, startSecs, durSecs int64) {
	_ = os.MkdirAll(videoDir, 0o755)
	cmd := exec.CommandContext(ctx, youtubeBin, youtubeDownloadArgs(id, videoDir, maxHeight, startSecs, durSecs)...)
	// yt-dlp hands clip sections to an ffmpeg child that holds our pipes; a cancel
	// takes the whole group down, or the transfer runs on and never reports.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		s.emitDownloadError(id, "yt-dlp download failed")
		return
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		s.emitDownloadError(id, "yt-dlp download failed")
		return
	}
	zero := 0.0
	msg := "video"
	s.emitDownload(downloadEvent{ID: id, Status: dlDownloading, Progress: &zero, Message: &msg})
	if err := cmd.Start(); err != nil {
		if errors.Is(err, exec.ErrNotFound) {
			s.emitDownloadError(id, youtubeMissingTool("download from"))
			return
		}
		s.emitDownloadError(id, "yt-dlp failed to start")
		return
	}
	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); s.pumpYoutubeProgress(id, stdout, durSecs, false) }()
	go func() { defer wg.Done(); s.pumpYoutubeProgress(id, stderr, durSecs, true) }()
	wg.Wait()
	if err := cmd.Wait(); err != nil {
		if ctx.Err() != nil {
			// A stopped transfer would leave yt-dlp's partial files in the library folder.
			parts, _ := filepath.Glob(filepath.Join(videoDir, "youtube-"+id+".*.part*"))
			for _, p := range parts {
				_ = os.Remove(p)
			}
			s.emitDownloadError(id, "cancelled")
			return
		}
		s.emitDownloadError(id, "yt-dlp download failed")
		return
	}
	file := finishedYoutubeVideo(videoDir, id)
	if file == "" {
		s.emitDownloadError(id, "download finished but no file appeared")
		return
	}
	if err := checkFile(file, sniffVideo); err != nil {
		os.Remove(file)
		s.emitDownloadError(id, "downloaded file rejected: "+err.Error())
		return
	}
	s.emitDownload(downloadEvent{ID: id, Status: dlDone, Path: &file})
	go s.d.rescan(true)
}

// Both streams are always drained so yt-dlp never blocks on a full pipe.
func (s *sources) pumpYoutubeProgress(id string, r io.Reader, durSecs int64, ffmpeg bool) {
	ph := &ytPhases{}
	last := -1.0
	lastAt := time.Now()
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for sc.Scan() {
		line := sc.Text()
		var pct float64
		var ok bool
		label := "clipping"
		if ffmpeg {
			pct, ok = clipProgress(line, durSecs)
		} else {
			pct, ok = noteLine(ph, line)
			label = ph.label()
		}
		if !ok {
			continue
		}
		if last < 0 || pct >= 0.98 || ((pct-last) >= progressMinDelta && time.Since(lastAt) >= progressMinInterval) {
			last = pct
			lastAt = time.Now()
			v := pct
			m := label
			s.emitDownload(downloadEvent{ID: id, Status: dlDownloading, Progress: &v, Message: &m})
		}
	}
}

func numFrom(v interface{}) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case int:
		return float64(n)
	case int64:
		return float64(n)
	}
	return 0
}
