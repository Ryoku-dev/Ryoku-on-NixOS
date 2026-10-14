package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const (
	ryowallsUA      = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
	ryostoreBase    = "https://raw.githubusercontent.com/ryoku-dev/ryostore/main"
	motionbgsBase   = "https://motionbgs.com"
	moewallsBase    = "https://moewalls.com"
	ryowallsPerPage = 24
)

var (
	mbAnchorRe     = regexp.MustCompile(`(?s)<a title="([^"]*)" href=/([a-z0-9][a-z0-9-]*)>(.*?)</a>`)
	mbThumbRe      = regexp.MustCompile(`/i/c/([0-9]+)x[0-9]+/media/([0-9]+)/([^ >"]+?\.(?:jpe?g|png))`)
	mbTitleRe      = regexp.MustCompile(`<span class=ttl>([^<]*)</span>`)
	mbQualityRe    = regexp.MustCompile(`<span class=frm>\s*([^<]*?)\s*</span>`)
	mbStemRe       = regexp.MustCompile(`(?:\.[0-9]+x[0-9]+)?\.(?:jpe?g|png)$`)
	mbLiveSuffixRe = regexp.MustCompile(`(?i)\s+live wallpaper$`)
	mwSrcRe        = regexp.MustCompile(`src="(https://moewalls\.com/wp-content/uploads/[0-9]{4}/[0-9]{2}/[^"]*-thumb-[0-9]+x[0-9]+\.(?:jpe?g|png))"`)
	mwHrefRe       = regexp.MustCompile(`class="g1-frame" href="(https://moewalls\.com/[^"]*)"`)
	mwTitleRe      = regexp.MustCompile(`<a title="([^"]*)" class="g1-frame"`)
	mwResRe        = regexp.MustCompile(`resolutions-([0-9]+x[0-9]+)`)
	moeTokenRe     = regexp.MustCompile(`id="moe-download"[^>]*data-url="([^"]*)"`)
	moeTokenRe2    = regexp.MustCompile(`data-url="([^"]*)"[^>]*id="moe-download"`)
	vidExtRe       = regexp.MustCompile(`(?i)\.(mp4|webm|mkv|mov)$`)
	imgExtRe       = regexp.MustCompile(`(?i)\.(jpe?g|png|webp)$`)
	stripExtRe     = regexp.MustCompile(`\.[^.]+$`)
	trailNumRe     = regexp.MustCompile(`-[0-9]+$`)
	thumbNameRe    = regexp.MustCompile(`(?i)thumb|poster|cover`)
)

type ryowallsWall struct {
	ID     string   `json:"id"`
	Name   string   `json:"name"`
	Poster string   `json:"poster"`
	Video  string   `json:"video"`
	Author string   `json:"author"`
	Tags   []string `json:"tags"`
}

type ryowallsRegistry struct {
	Wallpapers []ryowallsWall `json:"wallpapers"`
}

func (s *sources) fetchHTML(ctx context.Context, rawURL, referer string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", ryowallsUA)
	if referer != "" {
		req.Header.Set("Referer", referer)
	}
	resp, err := s.http.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("network error: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", httpStatusError{resp.StatusCode}
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxTextBytes))
	if err != nil {
		return "", err
	}
	return string(body), nil
}

func matchQuery(q, name string, tags []string) bool {
	if q == "" {
		return true
	}
	if strings.Contains(strings.ToLower(name), q) {
		return true
	}
	for _, t := range tags {
		if strings.Contains(strings.ToLower(t), q) {
			return true
		}
	}
	return false
}

func clientPage(all []sourceResult, page int) sourcePage {
	per := ryowallsPerPage
	total := len(all)
	last := (total + per - 1) / per
	if last < 1 {
		last = 1
	}
	if page > last {
		page = last
	}
	if page < 1 {
		page = 1
	}
	start := (page - 1) * per
	end := start + per
	if start > total {
		start = total
	}
	if end > total {
		end = total
	}
	return sourcePage{results: append([]sourceResult(nil), all[start:end]...), lastPage: last, currentPage: page}
}

func serverPage(out []sourceResult, page int) sourcePage {
	last := page
	if len(out) > 0 {
		last = page + 1
	}
	return sourcePage{results: out, lastPage: last, currentPage: page}
}

func (s *sources) ryowallsSearch(ctx context.Context, source string, p map[string]interface{}) (sourcePage, error) {
	query := strParam(p, "query", "")
	page := int(intParam(p, "page", 1))
	if page < 1 {
		page = 1
	}
	switch source {
	case "ryostore":
		return s.ryostoreSearch(ctx, query, page)
	case "motionbgs":
		return s.motionbgsSearch(ctx, query, page)
	case "moewalls":
		return s.moewallsSearch(ctx, query, page)
	case "repos":
		return s.reposSearch(ctx, query, page, p)
	}
	return sourcePage{}, fmt.Errorf("unknown source '%s'", source)
}

func ryostoreAbs(base, p string) string {
	if p == "" {
		return ""
	}
	if strings.HasPrefix(p, "http://") || strings.HasPrefix(p, "https://") {
		return p
	}
	return base + "/" + strings.TrimPrefix(p, "/")
}

func (s *sources) ryostoreSearch(ctx context.Context, query string, page int) (sourcePage, error) {
	body, err := s.fetchHTML(ctx, ryostoreBase+"/livewalls/registry.json", "")
	if err != nil {
		return sourcePage{}, fmt.Errorf("search failed")
	}
	var reg ryowallsRegistry
	if json.Unmarshal([]byte(body), &reg) != nil {
		return sourcePage{}, fmt.Errorf("search failed")
	}
	return clientPage(ryowallsRegistryRows(reg, ryostoreBase, query, false), page), nil
}

func ryowallsRegistryRows(reg ryowallsRegistry, base, query string, proxyThumb bool) []sourceResult {
	q := strings.ToLower(query)
	out := make([]sourceResult, 0, len(reg.Wallpapers))
	for _, w := range reg.Wallpapers {
		if !matchQuery(q, w.Name, w.Tags) {
			continue
		}
		thumb := ryostoreAbs(base, w.Poster)
		if proxyThumb {
			thumb = reposThumbProxy(thumb)
		}
		out = append(out, sourceResult{
			id:          w.ID,
			thumbURL:    thumb,
			fullURL:     ryostoreAbs(base, w.Video),
			title:       w.Name,
			attribution: w.Author,
		})
	}
	return out
}

func (s *sources) motionbgsSearch(ctx context.Context, query string, page int) (sourcePage, error) {
	body, err := s.fetchHTML(ctx, motionbgsBase+motionbgsPath(query, page), motionbgsBase+"/")
	if err != nil {
		// Paging past the last page answers 404; that means no more results, not a failure.
		var status httpStatusError
		if page > 1 && errors.As(err, &status) && status.code == http.StatusNotFound {
			return serverPage(nil, page), nil
		}
		return sourcePage{}, fmt.Errorf("search failed")
	}
	return serverPage(parseMotionbgs(body), page), nil
}

// MotionBGs answers /search?q= with a redirect to the tag page, so the tag path is
// requested directly. An empty query browses the latest wallpapers.
func motionbgsPath(query string, page int) string {
	q := url.PathEscape(strings.Join(strings.Fields(strings.ToLower(query)), "-"))
	switch {
	case q != "":
		p := "/tag:" + q + "/"
		if page > 1 {
			p += strconv.Itoa(page) + "/"
		}
		return p
	case page > 1:
		return "/" + strconv.Itoa(page) + "/"
	default:
		return "/"
	}
}

func parseMotionbgs(body string) []sourceResult {
	seen := map[string]bool{}
	out := make([]sourceResult, 0, ryowallsPerPage)
	for _, m := range mbAnchorRe.FindAllStringSubmatch(body, -1) {
		anchorTitle, inner := m[1], m[3]
		id, thumbPath, file := bestMotionbgsThumb(inner)
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		quality := "HD"
		if qm := mbQualityRe.FindStringSubmatch(inner); qm != nil {
			quality = strings.ToUpper(strings.TrimSpace(qm[1]))
		}
		title := anchorTitle
		if tm := mbTitleRe.FindStringSubmatch(inner); tm != nil && strings.TrimSpace(tm[1]) != "" {
			title = tm[1]
		}
		title = html.UnescapeString(strings.TrimSpace(mbLiveSuffixRe.ReplaceAllString(title, "")))
		res := "1920x1080"
		if quality == "4K" {
			res = "3840x2160"
		}
		stem := mbStemRe.ReplaceAllString(file, "")
		out = append(out, sourceResult{
			id:       id,
			thumbURL: motionbgsBase + thumbPath,
			// The motion preview clip plays in the card and preview; the download resolves
			// the full-resolution file from the id and the quality setting.
			fullURL:    motionbgsBase + "/media/" + id + "/" + stem + ".960x540.mp4",
			resolution: res,
			title:      title,
		})
		if len(out) >= ryowallsPerPage {
			break
		}
	}
	return out
}

// bestMotionbgsThumb picks the largest thumbnail actually present in the card, so a
// missing size is never guessed into a broken URL.
func bestMotionbgsThumb(inner string) (id, path, file string) {
	best := 0
	for _, mm := range mbThumbRe.FindAllStringSubmatch(inner, -1) {
		w, _ := strconv.Atoi(mm[1])
		if w > best {
			best, path, id, file = w, mm[0], mm[2], mm[3]
		}
	}
	return id, path, file
}

func (s *sources) moewallsSearch(ctx context.Context, query string, page int) (sourcePage, error) {
	var u string
	if query != "" {
		base := moewallsBase + "/"
		if page > 1 {
			base = moewallsBase + "/page/" + strconv.Itoa(page) + "/"
		}
		u = base + "?s=" + url.QueryEscape(query)
	} else {
		u = moewallsBase + "/anime/"
		if page > 1 {
			u = moewallsBase + "/anime/page/" + strconv.Itoa(page) + "/"
		}
	}
	body, err := s.fetchHTML(ctx, u, moewallsBase+"/")
	if err != nil {
		return sourcePage{}, fmt.Errorf("search failed")
	}
	return serverPage(parseMoewalls(body), page), nil
}

func parseMoewalls(body string) []sourceResult {
	out := make([]sourceResult, 0, ryowallsPerPage)
	for _, card := range strings.Split(body, "<article ") {
		if !strings.Contains(card, "g1-frame") {
			continue
		}
		ms := mwSrcRe.FindStringSubmatch(card)
		if ms == nil {
			continue
		}
		srcURL := ms[1]
		href := ""
		if m := mwHrefRe.FindStringSubmatch(card); m != nil {
			href = m[1]
		}
		title := ""
		if m := mwTitleRe.FindStringSubmatch(card); m != nil {
			title = m[1]
		}
		res := ""
		if m := mwResRe.FindStringSubmatch(card); m != nil {
			res = m[1]
		}
		rel := ""
		if i := strings.Index(srcURL, "/uploads/"); i >= 0 {
			rel = srcURL[i+len("/uploads/"):]
		}
		relParts := strings.Split(rel, "/")
		if len(relParts) == 0 || relParts[0] == "" {
			continue
		}
		yy := relParts[0]
		last := relParts[len(relParts)-1]
		mb2 := last
		if i := strings.Index(last, "-thumb-"); i >= 0 {
			mb2 = last[:i]
		}
		webm := moewallsBase + "/wp-content/uploads/preview/" + yy + "/" + mb2 + "-preview.webm"
		name := strings.TrimSuffix(title, " Live Wallpaper")
		if name == "" {
			name = strings.ReplaceAll(mb2, "-", " ")
		}
		out = append(out, sourceResult{
			id:         mb2,
			thumbURL:   "https://wsrv.nl/?url=" + url.QueryEscape(srcURL),
			fullURL:    webm,
			resolution: res,
			title:      name,
			trackURL:   href,
		})
		if len(out) >= ryowallsPerPage {
			break
		}
	}
	return out
}

type ghRepoMeta struct {
	DefaultBranch string `json:"default_branch"`
}

type ghTreeEntry struct {
	Path string `json:"path"`
	Type string `json:"type"`
	Size *int64 `json:"size"`
}

type ghTree struct {
	Tree []ghTreeEntry `json:"tree"`
}

func reposThumbProxy(u string) string {
	if u == "" {
		return ""
	}
	stripped := strings.TrimPrefix(strings.TrimPrefix(u, "https://"), "http://")
	return "https://wsrv.nl/?url=" + stripped + "&w=480&output=webp&q=80"
}

func encPath(p string) string {
	parts := strings.Split(p, "/")
	for i, seg := range parts {
		parts[i] = url.PathEscape(seg)
	}
	return strings.Join(parts, "/")
}

func humanizeName(s string) string {
	s = trailNumRe.ReplaceAllString(s, "")
	return strings.NewReplacer("-", " ", "_", " ").Replace(s)
}

func baseName(p string) string {
	if i := strings.LastIndex(p, "/"); i >= 0 {
		return p[i+1:]
	}
	return p
}

func dirOf(p string) string {
	if i := strings.LastIndex(p, "/"); i >= 0 {
		return p[:i]
	}
	return p
}

// A typo and GitHub's unauthenticated rate limit are the usual reasons a repository will not list.
func reposFetchError(err error) error {
	var status httpStatusError
	if errors.As(err, &status) {
		switch status.code {
		case http.StatusNotFound:
			return fmt.Errorf("repository not found; check the owner/repo name")
		case http.StatusForbidden, http.StatusTooManyRequests:
			return fmt.Errorf("GitHub is limiting requests; try again later or set GITHUB_TOKEN")
		}
	}
	return fmt.Errorf("search failed")
}

func (s *sources) reposSearch(ctx context.Context, query string, page int, p map[string]interface{}) (sourcePage, error) {
	repo := strParam(p, "repo", "")
	branch := strParam(p, "branch", "")
	sub := strParam(p, "path", "")
	rtype := strParam(p, "type", "all")
	if repo == "" {
		return sourcePage{}, fmt.Errorf("no repo")
	}
	header := http.Header{"Accept": []string{"application/vnd.github+json"}}
	if tok := os.Getenv("GITHUB_TOKEN"); tok != "" {
		header.Set("Authorization", "Bearer "+tok)
	}
	if branch == "" {
		if meta, err := s.getBytes(ctx, http.MethodGet, "https://api.github.com/repos/"+repo, header, nil, maxTextBytes); err == nil {
			var m ghRepoMeta
			if json.Unmarshal(meta, &m) == nil && m.DefaultBranch != "" {
				branch = m.DefaultBranch
			}
		}
		if branch == "" {
			branch = "main"
		}
	}
	treeBody, err := s.getBytes(ctx, http.MethodGet, "https://api.github.com/repos/"+repo+"/git/trees/"+branch+"?recursive=1", header, nil, maxTextBytes)
	if err != nil {
		return sourcePage{}, reposFetchError(err)
	}
	var tree ghTree
	if json.Unmarshal(treeBody, &tree) != nil {
		return sourcePage{}, fmt.Errorf("search failed")
	}
	rawb := "https://raw.githubusercontent.com/" + repo + "/" + branch
	mediab := "https://media.githubusercontent.com/media/" + repo + "/" + branch
	q := strings.ToLower(query)

	regPath := ""
	for _, e := range tree.Tree {
		if strings.HasSuffix(e.Path, "livewalls/registry.json") || e.Path == "registry.json" {
			regPath = e.Path
			break
		}
	}
	if regPath != "" && rtype != "images" {
		if regBody, err := s.fetchHTML(ctx, rawb+"/"+regPath, ""); err == nil {
			var reg ryowallsRegistry
			if json.Unmarshal([]byte(regBody), &reg) == nil {
				return clientPage(ryowallsRegistryRows(reg, rawb, query, true), page), nil
			}
		}
	}

	lfs := map[string]bool{}
	for _, e := range tree.Tree {
		if e.Type == "blob" {
			size := int64(1 << 30)
			if e.Size != nil {
				size = *e.Size
			}
			if size < 1024 {
				lfs[e.Path] = true
			}
		}
	}
	host := func(p string) string {
		if lfs[p] {
			return mediab
		}
		return rawb
	}

	var imgs, vids []string
	for _, e := range tree.Tree {
		if e.Path == "" || (sub != "" && !strings.HasPrefix(e.Path, sub)) {
			continue
		}
		switch {
		case vidExtRe.MatchString(e.Path):
			vids = append(vids, e.Path)
		case imgExtRe.MatchString(e.Path):
			imgs = append(imgs, e.Path)
		}
	}
	viddirs := map[string]bool{}
	vpd := map[string]int{}
	for _, v := range vids {
		d := dirOf(v)
		viddirs[d] = true
		vpd[d]++
	}

	type row struct {
		kind, path, thumb, media, name string
	}
	rows := make([]row, 0, len(imgs)+len(vids))
	for _, img := range imgs {
		if viddirs[dirOf(img)] || thumbNameRe.MatchString(img) {
			continue
		}
		rows = append(rows, row{kind: "image", path: img, thumb: img, media: img, name: humanizeName(stripExtRe.ReplaceAllString(baseName(img), ""))})
	}
	for _, vid := range vids {
		d := dirOf(vid)
		var poster string
		for _, img := range imgs {
			if strings.HasPrefix(img, d+"/") {
				if poster == "" {
					poster = img
				}
				if thumbNameRe.MatchString(img) {
					poster = img
					break
				}
			}
		}
		name := ""
		if vpd[d] == 1 {
			name = baseName(d)
		} else {
			name = stripExtRe.ReplaceAllString(baseName(vid), "")
		}
		rows = append(rows, row{kind: "video", path: vid, thumb: poster, media: vid, name: humanizeName(name)})
	}

	all := make([]sourceResult, 0, len(rows))
	for _, r := range rows {
		keep := rtype == "all" || (rtype == "live" && r.kind == "video") || (rtype == "images" && r.kind == "image")
		if !keep {
			continue
		}
		if q != "" && !strings.Contains(strings.ToLower(r.path), q) {
			continue
		}
		turl := ""
		if r.thumb != "" {
			turl = host(r.thumb) + "/" + encPath(r.thumb)
		}
		all = append(all, sourceResult{
			id:       r.path,
			thumbURL: reposThumbProxy(turl),
			fullURL:  host(r.media) + "/" + encPath(r.media),
			title:    r.name,
		})
	}
	return clientPage(all, page), nil
}

func (s *sources) classifyByExt(u string) (string, sniffKind) {
	cfg := s.d.config()
	switch strings.ToLower(extFromURL(u)) {
	case "mp4", "webm", "mkv", "mov":
		return cfg.videoDir(), sniffVideo
	case "jpg", "jpeg", "png", "webp", "gif", "bmp", "avif":
		return cfg.wallpaperDir(), sniffImage
	}
	return cfg.videoDir(), sniffVideo
}

func (s *sources) moewallsToken(ctx context.Context, postURL string) (string, error) {
	if err := requireSource("moewalls", postURL); err != nil {
		return "", err
	}
	body, err := s.fetchHTML(ctx, postURL, "")
	if err != nil {
		return "", err
	}
	if m := moeTokenRe.FindStringSubmatch(body); m != nil {
		return m[1], nil
	}
	if m := moeTokenRe2.FindStringSubmatch(body); m != nil {
		return m[1], nil
	}
	return "", fmt.Errorf("no download token")
}

func (s *sources) moewallsDownload(ctx context.Context, id, fullURL, postURL, videoDir string) (string, error) {
	if postURL != "" {
		if token, err := s.moewallsToken(ctx, postURL); err == nil && token != "" {
			dest := filepath.Join(videoDir, "moewalls-"+safeSeg(id)+".mp4")
			policy := func(u string) error { return requireSource("moewalls", u) }
			dlURL := "https://go.moewalls.com/download.php?video=" + token
			if err := s.fetchToFile(ctx, dlURL, dest, sniffVideo, maxDownloadBytes, policy, nil); err == nil {
				return dest, nil
			}
		}
	}
	return s.downloadWithProgress(ctx, "moewalls", fullURL, videoDir, id, sniffVideo, nil)
}

// motionbgsDownload fetches the full-resolution clip for the chosen quality. "best"
// prefers 4K and falls back to HD (HD-only wallpapers answer the 4K route with 500);
// "light" fetches HD directly. The file is always saved with an .mp4 extension so the
// library recognises it as a video.
func (s *sources) motionbgsDownload(ctx context.Context, id, videoDir string, onProgress func(float64)) (string, error) {
	dest := filepath.Join(videoDir, "motionbgs-"+safeSeg(id)+".mp4")
	policy := func(u string) error { return requireSource("motionbgs", u) }
	seg := url.PathEscape(id)
	if s.str("sources.motionbgs.quality") != "light" {
		if err := s.fetchToFile(ctx, motionbgsBase+"/dl/4k/"+seg+"/", dest, sniffVideo, maxDownloadBytes, policy, onProgress); err == nil {
			return dest, nil
		}
	}
	if err := s.fetchToFile(ctx, motionbgsBase+"/dl/hd/"+seg+"/", dest, sniffVideo, maxDownloadBytes, policy, onProgress); err != nil {
		return "", err
	}
	return dest, nil
}

func (s *sources) ryowallsDownload(reqID int64, source string, p map[string]interface{}) response {
	id := strParam(p, "id", "")
	fullURL := strParam(p, "fullUrl", "")
	if id == "" || fullURL == "" {
		return errResp(reqID, -32602, "missing id/fullUrl")
	}
	var (
		dir  string
		want sniffKind
	)
	if source == "repos" {
		dir, want = s.classifyByExt(fullURL)
	} else {
		dir, want = s.d.config().videoDir(), sniffVideo
	}
	if existing, has := sourceLibraryPath(dir, source, id); has {
		return s.respondExists(reqID, id, existing)
	}
	g := s.videos
	if want == sniffImage {
		g = s.images
	}
	postURL := strParam(p, "trackUrl", "")
	return s.startDownload(reqID, id, g, source+":"+id, func(ctx context.Context, _ *gateSlot) {
		s.emitDownload(downloadEvent{ID: id, Status: dlDownloading})
		var (
			path string
			err  error
		)
		onProgress := func(pct float64) {
			v := pct
			m := "fetching"
			s.emitDownload(downloadEvent{ID: id, Status: dlDownloading, Progress: &v, Message: &m})
		}
		switch source {
		case "moewalls":
			path, err = s.moewallsDownload(ctx, id, fullURL, postURL, dir)
		case "motionbgs":
			path, err = s.motionbgsDownload(ctx, id, dir, onProgress)
		default:
			path, err = s.downloadWithProgress(ctx, source, fullURL, dir, id, want, onProgress)
		}
		s.finishDownload(id, path, err)
	})
}
