package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Reservations past the queue depth are refused so the RPC can answer queue-full.
type gate struct {
	mu             sync.Mutex
	cv             *sync.Cond
	limit          int
	maxOutstanding int
	outstanding    int
	issued         uint64
	admitted       uint64
	active         int
}

func newGate(limit, maxQueued int) *gate {
	g := &gate{limit: limit, maxOutstanding: limit + maxQueued}
	g.cv = sync.NewCond(&g.mu)
	return g
}

type reservation struct {
	g    *gate
	held bool
}

type gateSlot struct{ g *gate }

func (g *gate) tryReserve() (*reservation, bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.outstanding >= g.maxOutstanding {
		return nil, false
	}
	g.outstanding++
	return &reservation{g: g, held: true}, true
}

func (r *reservation) acquire(onWait func(ahead uint64)) *gateSlot {
	g := r.g
	g.mu.Lock()
	my := g.issued
	g.issued++
	told := ^uint64(0)
	for {
		if my == g.admitted && g.active < g.limit {
			g.admitted++
			g.active++
			r.held = false
			g.mu.Unlock()
			g.cv.Broadcast()
			return &gateSlot{g: g}
		}
		ahead := my - g.admitted
		if ahead != told {
			told = ahead
			if onWait != nil {
				onWait(ahead)
			}
		}
		g.cv.Wait()
	}
}

func (r *reservation) release() {
	r.g.mu.Lock()
	if r.held {
		r.held = false
		r.g.outstanding--
		r.g.mu.Unlock()
		r.g.cv.Broadcast()
		return
	}
	r.g.mu.Unlock()
}

func (s *gateSlot) release() {
	g := s.g
	g.mu.Lock()
	if g.active > 0 {
		g.active--
	}
	g.outstanding--
	g.mu.Unlock()
	g.cv.Broadcast()
}

func queueLabel(ahead uint64) string {
	if ahead == 0 {
		return "queued"
	}
	return fmt.Sprintf("queued - %d ahead", ahead)
}

const (
	progressMinDelta    = 0.01
	progressMinInterval = 125 * time.Millisecond
)

func shouldEmit(pct, last float64, elapsed time.Duration) bool {
	return (pct-last) >= progressMinDelta && elapsed >= progressMinInterval
}

// Held below 1 until the file is on disk and validated, so a full bar never shows early.
func contentProgress(done, total uint64) (float64, bool) {
	if total == 0 {
		return 0, false
	}
	p := float64(done) / float64(total)
	switch {
	case p < 0:
		p = 0
	case p > 0.99:
		p = 0.99
	}
	return p, true
}

const (
	dlQueued      = "queued"
	dlDownloading = "downloading"
	dlDone        = "done"
	dlError       = "error"
	dlAuthError   = "auth_error"
)

const (
	evDownload     = "ryogami.source.download"
	evPreviewReady = "ryogami.source.preview_ready"
	evRemoteThumb  = "ryogami.source.remote_thumb"
	evResults      = "ryogami.source.results"
)

type downloadEvent struct {
	ID       string   `json:"id"`
	Status   string   `json:"status"`
	Progress *float64 `json:"progress,omitempty"`
	Message  *string  `json:"message,omitempty"`
	Path     *string  `json:"path,omitempty"`
	Error    *string  `json:"error,omitempty"`
}

type progressEventState struct {
	status string
	at     time.Time
}

type libraryIDCache struct {
	mtime int64
	ids   map[string]bool
}

func (s *sources) allowDownloadEvent(ev downloadEvent, now time.Time) bool {
	s.progressMu.Lock()
	defer s.progressMu.Unlock()
	if s.progress == nil {
		s.progress = map[string]progressEventState{}
	}
	last, has := s.progress[ev.ID]
	terminal := ev.Status != dlQueued && ev.Status != dlDownloading
	if terminal {
		delete(s.progress, ev.ID)
		return true
	}
	if !has || last.status != ev.Status || now.Sub(last.at) >= progressMinInterval {
		s.progress[ev.ID] = progressEventState{status: ev.Status, at: now}
		return true
	}
	return false
}

func (s *sources) emitDownload(ev downloadEvent) {
	if !s.allowDownloadEvent(ev, time.Now()) {
		return
	}
	s.d.broadcast(evDownload, ev)
	if s.d.tasks == nil {
		return
	}
	id := "download:" + ev.ID
	switch ev.Status {
	case dlQueued, dlDownloading:
		if ev.Progress != nil {
			s.d.tasks.progress(id, int(*ev.Progress*100), 100, "")
		}
	case dlDone:
		s.d.tasks.finish(id, taskCompleted, 0, "")
	case dlError:
		state, detail := taskFailed, ""
		if ev.Error != nil {
			detail = *ev.Error
		}
		if detail == "cancelled" {
			state = taskCancelled
		}
		s.d.tasks.finish(id, state, 0, detail)
	}
}

type sourceResult struct {
	id             string
	fullURL        string
	thumbURL       string
	resolution     string
	fileSize       uint64
	title          string
	trackURL       string
	attribution    string
	attributionURL string
	durationSecs   uint64
	purity         string
	category       string
}

type sourcePage struct {
	results     []sourceResult
	lastPage    int
	currentPage int
	nextCursor  string
}

type sourceItem struct {
	ID             string `json:"id"`
	FullURL        string `json:"fullUrl"`
	ThumbURL       string `json:"thumbUrl"`
	ThumbPath      string `json:"thumbPath"`
	Resolution     string `json:"resolution"`
	FileSize       uint64 `json:"fileSize"`
	Purity         string `json:"purity,omitempty"`
	Category       string `json:"category,omitempty"`
	Title          string `json:"title,omitempty"`
	Attribution    string `json:"attribution,omitempty"`
	AttributionURL string `json:"attributionUrl,omitempty"`
	TrackURL       string `json:"trackUrl,omitempty"`
	DurationSecs   uint64 `json:"durationSecs,omitempty"`
	Downloaded     bool   `json:"downloaded"`
}

func streamTo(ctx context.Context, reader io.Reader, w io.Writer, total, max uint64, onProgress func(float64)) error {
	buf := make([]byte, 64*1024)
	var done uint64
	var last float64
	lastAt := time.Now()
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		n, err := reader.Read(buf)
		if n > 0 {
			next := done + uint64(n)
			if next > max {
				return fmt.Errorf("remote body exceeds %d byte limit", max)
			}
			if _, werr := w.Write(buf[:n]); werr != nil {
				return werr
			}
			done = next
			if pct, ok := contentProgress(done, total); ok && shouldEmit(pct, last, time.Since(lastAt)) {
				last = pct
				lastAt = time.Now()
				if onProgress != nil {
					onProgress(pct)
				}
			}
		}
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
	}
}

// Downloads land as .part and are renamed only after the size cap and magic-byte sniff pass.
func (s *sources) fetchToFile(ctx context.Context, rawURL, dest string, want sniffKind, max uint64, policy func(string) error, onProgress func(float64)) (err error) {
	if err = policy(rawURL); err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	resp, err := s.guardedGet(ctx, rawURL, policy)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if cl := declaredLength(resp); cl > max {
		return fmt.Errorf("remote body is %d bytes; limit is %d bytes", cl, max)
	}
	file, tmp, err := partialFile(dest)
	if err != nil {
		return err
	}
	committed := false
	defer func() {
		if !committed {
			os.Remove(tmp)
		}
	}()
	streamErr := streamTo(ctx, resp.Body, file, declaredLength(resp), max, onProgress)
	closeErr := file.Close()
	if streamErr != nil {
		return streamErr
	}
	if closeErr != nil {
		return closeErr
	}
	if err = checkFile(tmp, want); err != nil {
		return err
	}
	if err = os.Rename(tmp, dest); err != nil {
		return err
	}
	committed = true
	return nil
}

func downloadDest(destDir, source, id, ext string) string {
	return filepath.Join(destDir, fmt.Sprintf("%s-%s.%s", safeSeg(source), safeSeg(id), safeSeg(ext)))
}

func (s *sources) downloadWithProgress(ctx context.Context, source, fullURL, destDir, id string, want sniffKind, onProgress func(float64)) (string, error) {
	policy := func(u string) error { return requireSource(source, u) }
	dest := downloadDest(destDir, source, id, extFromURL(fullURL))
	if err := s.fetchToFile(ctx, fullURL, dest, want, maxDownloadBytes, policy, onProgress); err != nil {
		return "", err
	}
	return dest, nil
}

func libraryIDs(dir, source string) map[string]bool {
	ids := map[string]bool{}
	prefix := source + "-"
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ids
	}
	for _, e := range entries {
		if rest, ok := strings.CutPrefix(e.Name(), prefix); ok {
			id := rest
			if dot := strings.LastIndex(rest, "."); dot >= 0 {
				id = rest[:dot]
			}
			if id != "" {
				ids[id] = true
			}
		}
	}
	return ids
}

func (s *sources) cachedLibraryIDs(dir, source string) map[string]bool {
	fi, err := os.Stat(dir)
	if err != nil {
		return map[string]bool{}
	}
	key := dir + "\x00" + source
	mtime := fi.ModTime().UnixNano()
	s.libraryMu.Lock()
	if cached, ok := s.libraryCache[key]; ok && cached.mtime == mtime {
		s.libraryMu.Unlock()
		return cached.ids
	}
	s.libraryMu.Unlock()
	ids := libraryIDs(dir, source)
	s.libraryMu.Lock()
	s.libraryCache[key] = libraryIDCache{mtime: mtime, ids: ids}
	s.libraryMu.Unlock()
	return ids
}

func sourceLibraryPath(dir, source, id string) (string, bool) {
	prefix := fmt.Sprintf("%s-%s.", source, safeSeg(id))
	entries, err := os.ReadDir(dir)
	if err != nil {
		return "", false
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), prefix) {
			return filepath.Join(dir, e.Name()), true
		}
	}
	return "", false
}

func (s *sources) startDownload(reqID int64, id string, g *gate, inflightKey string, work func(ctx context.Context, slot *gateSlot)) response {
	if !s.beginInflight(inflightKey) {
		return ok(reqID, map[string]interface{}{"id": id, "status": "in_progress"})
	}
	res, okReserve := g.tryReserve()
	if !okReserve {
		s.endInflight(inflightKey)
		return errResp(reqID, -32000, "download queue is full; retry shortly")
	}
	ctx, cancel := context.WithTimeout(context.Background(), downloadFetchTimeout)
	s.registerCancel(id, cancel)
	if s.d.tasks != nil {
		s.d.tasks.start("download:"+id, "download", "Download", 100, cancel)
	}
	go func() {
		defer s.endInflight(inflightKey)
		defer s.clearCancel(id)
		defer cancel()
		slot := res.acquire(func(ahead uint64) {
			zero := 0.0
			msg := queueLabel(ahead)
			s.emitDownload(downloadEvent{ID: id, Status: dlQueued, Progress: &zero, Message: &msg})
		})
		defer slot.release()
		work(ctx, slot)
		// A worker that returned without reporting an outcome must not leave its chip running.
		if s.d.tasks != nil {
			if ctx.Err() != nil {
				s.d.tasks.finish("download:"+id, taskCancelled, 0, "")
			} else {
				s.d.tasks.finish("download:"+id, taskFailed, 0, "")
			}
		}
	}()
	return ok(reqID, map[string]interface{}{"id": id, "status": "started"})
}

func (s *sources) respondExists(reqID int64, id, path string) response {
	s.emitDownload(downloadEvent{ID: id, Status: dlDone, Path: &path})
	return ok(reqID, map[string]interface{}{"id": id, "status": "exists", "path": path})
}

func (s *sources) finishDownload(id, path string, err error) {
	if err != nil {
		msg := err.Error()
		if errors.Is(err, context.Canceled) {
			msg = "cancelled"
		}
		s.emitDownload(downloadEvent{ID: id, Status: dlError, Error: &msg})
		return
	}
	s.emitDownload(downloadEvent{ID: id, Status: dlDone, Path: &path})
	go s.d.rescan(true)
}

func (s *sources) mediaDirs(source, media string) []string {
	cfg := s.d.config()
	if source == "repos" {
		return []string{cfg.wallpaperDir(), cfg.videoDir()}
	}
	if media == "video" {
		return []string{cfg.videoDir()}
	}
	return []string{cfg.wallpaperDir()}
}

func (s *sources) buildResult(reqID int64, connectionID uint64, source, media string, page sourcePage, p map[string]interface{}) response {
	local := map[string]bool{}
	for _, dir := range s.mediaDirs(source, media) {
		for id := range s.cachedLibraryIDs(dir, source) {
			local[id] = true
		}
	}
	items := make([]sourceItem, 0, len(page.results))
	jobs := make([][2]string, 0, len(page.results))
	for _, r := range page.results {
		items = append(items, sourceItem{
			ID:             r.id,
			FullURL:        r.fullURL,
			ThumbURL:       r.thumbURL,
			ThumbPath:      s.remoteThumbPath(source, r.id, r.thumbURL),
			Resolution:     r.resolution,
			FileSize:       r.fileSize,
			Purity:         r.purity,
			Category:       r.category,
			Title:          r.title,
			Attribution:    r.attribution,
			AttributionURL: r.attributionURL,
			TrackURL:       r.trackURL,
			DurationSecs:   r.durationSecs,
			Downloaded:     local[safeSeg(r.id)],
		})
		if r.thumbURL != "" {
			jobs = append(jobs, [2]string{r.id, r.thumbURL})
		}
	}
	s.queueRemoteThumbs(connectionID, source, source, intParam(p, "generation", 0), jobs)
	result := map[string]interface{}{
		"results":     items,
		"lastPage":    page.lastPage,
		"currentPage": page.currentPage,
	}
	if page.nextCursor != "" {
		result["nextCursor"] = page.nextCursor
	}
	var gen int64
	if _, has := p["generation"]; has {
		gen = intParam(p, "generation", 0)
		result["generation"] = gen
	}
	s.d.broadcast(evResults, map[string]interface{}{"source": source, "generation": gen})
	return ok(reqID, result)
}

// Unsplash's API terms require pinging its download tracker.
func (s *sources) imageDownload(reqID int64, source string, p map[string]interface{}) response {
	id := strParam(p, "id", "")
	fullURL := strParam(p, "fullUrl", "")
	if id == "" || fullURL == "" {
		return errResp(reqID, -32602, "missing id/fullUrl")
	}
	wdir := s.d.config().wallpaperDir()
	if existing, has := sourceLibraryPath(wdir, source, id); has {
		return s.respondExists(reqID, id, existing)
	}
	trackURL := strParam(p, "trackUrl", "")
	accessKey := s.str("sources.unsplash.accessKey")
	return s.startDownload(reqID, id, s.images, source+":"+id, func(ctx context.Context, _ *gateSlot) {
		msg := "fetching"
		zero := 0.0
		s.emitDownload(downloadEvent{ID: id, Status: dlDownloading, Progress: &zero, Message: &msg})
		if source == "unsplash" {
			_ = s.unsplashTrack(ctx, trackURL, accessKey)
		}
		onProgress := func(pct float64) {
			p := pct
			s.emitDownload(downloadEvent{ID: id, Status: dlDownloading, Progress: &p, Message: &msg})
		}
		path, err := s.downloadWithProgress(ctx, source, fullURL, wdir, id, sniffImage, onProgress)
		s.finishDownload(id, path, err)
	})
}

func (s *sources) cancel(reqID int64, p map[string]interface{}) response {
	id := strParam(p, "id", "")
	cancelled := s.cancelDownload(id)
	return ok(reqID, map[string]interface{}{"ok": cancelled})
}

func (s *sources) search(reqID int64, connectionID uint64, p map[string]interface{}) response {
	source := strParam(p, "source", "")
	spec := providerSpec(source)
	if spec == nil {
		return errResp(reqID, -32602, "unknown source '"+source+"'")
	}
	if !s.enabled(source) {
		return errResp(reqID, -1, source+" source is disabled")
	}
	generation := intParam(p, "generation", 0)
	ctx, finish, stale := s.beginSearch(connectionID, source, generation, searchFetchTimeout)
	if stale {
		return errResp(reqID, -1, "search superseded")
	}
	defer finish()

	page, err := s.runSearch(ctx, source, p)
	if ctxErr := ctx.Err(); ctxErr != nil {
		err = ctxErr
	}
	if err != nil {
		return errResp(reqID, -1, searchError(err))
	}
	return s.buildResult(reqID, connectionID, source, spec.media, page, p)
}

func (s *sources) runSearch(ctx context.Context, source string, p map[string]interface{}) (sourcePage, error) {
	if s.searchHook != nil {
		return s.searchHook(ctx, source, p)
	}
	switch source {
	case "wallhaven":
		return s.wallhavenSearch(ctx, p)
	case "unsplash":
		return s.unsplashSearch(ctx, p)
	case "pexels":
		return s.pexelsSearch(ctx, p)
	case "youtube":
		return s.youtubeSearch(ctx, p)
	case "bing":
		return s.bingSearch(ctx, p)
	case "moewalls", "motionbgs", "ryostore", "repos":
		return s.ryowallsSearch(ctx, source, p)
	default:
		return sourcePage{}, fmt.Errorf("unknown source '%s'", source)
	}
}

func searchError(err error) string {
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		return fmt.Sprintf("search timed out after %s", searchFetchTimeout)
	case errors.Is(err, context.Canceled):
		return "search superseded"
	default:
		return err.Error()
	}
}

func (s *sources) download(reqID int64, p map[string]interface{}) response {
	source := strParam(p, "source", "")
	if providerSpec(source) == nil {
		return errResp(reqID, -32602, "unknown source '"+source+"'")
	}
	if !s.enabled(source) {
		return errResp(reqID, -1, source+" source is disabled")
	}
	switch source {
	case "wallhaven":
		return s.wallhavenDownload(reqID, p)
	case "youtube":
		return s.youtubeDownload(reqID, p)
	case "unsplash", "pexels", "bing":
		return s.imageDownload(reqID, source, p)
	case "moewalls", "motionbgs", "ryostore", "repos":
		return s.ryowallsDownload(reqID, source, p)
	}
	return errResp(reqID, -32601, "download not supported for source '"+source+"'")
}
