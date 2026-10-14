package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type whParams struct {
	query       string
	categories  string
	purity      string
	sorting     string
	order       string
	topRange    string
	atleast     string
	resolutions string
	ratios      string
	colors      string
	page        int
}

// topRange only applies to toplist sorting; resolutions take precedence over atleast.
func (p whParams) values() url.Values {
	v := url.Values{}
	if p.query != "" {
		v.Set("q", p.query)
	}
	v.Set("categories", p.categories)
	v.Set("purity", p.purity)
	v.Set("sorting", p.sorting)
	v.Set("order", p.order)
	if p.sorting == "toplist" && p.topRange != "" {
		v.Set("topRange", p.topRange)
	}
	if p.resolutions != "" {
		v.Set("resolutions", p.resolutions)
	} else if p.atleast != "" {
		v.Set("atleast", p.atleast)
	}
	if p.ratios != "" {
		v.Set("ratios", p.ratios)
	}
	if p.colors != "" {
		v.Set("colors", p.colors)
	}
	v.Set("page", strconv.Itoa(p.page))
	return v
}

type whThumbs struct {
	Small string `json:"small"`
	Large string `json:"large"`
}

type whItem struct {
	ID         string    `json:"id"`
	Path       string    `json:"path"`
	Resolution string    `json:"resolution"`
	FileSize   uint64    `json:"file_size"`
	Purity     string    `json:"purity"`
	Category   string    `json:"category"`
	Thumbs     *whThumbs `json:"thumbs"`
}

type whMeta struct {
	LastPage    *int `json:"last_page"`
	CurrentPage *int `json:"current_page"`
}

type whResp struct {
	Error *string  `json:"error"`
	Data  []whItem `json:"data"`
	Meta  *whMeta  `json:"meta"`
}

func parseWallhavenSearch(body string) (sourcePage, error) {
	var resp whResp
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return sourcePage{}, err
	}
	if resp.Error != nil && *resp.Error != "" {
		return sourcePage{}, fmt.Errorf("wallhaven error: %s", *resp.Error)
	}
	results := make([]sourceResult, 0, len(resp.Data))
	for _, it := range resp.Data {
		large := ""
		if it.Thumbs != nil {
			large = it.Thumbs.Large
			if large == "" {
				large = it.Thumbs.Small
			}
		}
		results = append(results, sourceResult{
			id:         it.ID,
			fullURL:    it.Path,
			thumbURL:   large,
			resolution: it.Resolution,
			fileSize:   it.FileSize,
			purity:     it.Purity,
			category:   it.Category,
		})
	}
	last, cur := 1, 1
	if resp.Meta != nil {
		if resp.Meta.LastPage != nil {
			last = *resp.Meta.LastPage
		}
		if resp.Meta.CurrentPage != nil {
			cur = *resp.Meta.CurrentPage
		}
	}
	return sourcePage{results: results, lastPage: last, currentPage: cur}, nil
}

func parseWxH(text string) (uint64, uint64, bool) {
	text = strings.TrimSpace(text)
	i := strings.IndexAny(text, "xX")
	if i < 0 {
		return 0, 0, false
	}
	w, err1 := strconv.ParseUint(strings.TrimSpace(text[:i]), 10, 64)
	h, err2 := strconv.ParseUint(strings.TrimSpace(text[i+1:]), 10, 64)
	if err1 != nil || err2 != nil {
		return 0, 0, false
	}
	return w, h, true
}

// The API has no atmost ceiling, so it is applied here.
func withinMax(resolution, atmost string) bool {
	mw, mh, ok := parseWxH(atmost)
	if !ok {
		return true
	}
	rw, rh, ok := parseWxH(resolution)
	if !ok {
		return true
	}
	return rw <= mw && rh <= mh
}

func (s *sources) wallhavenSearch(ctx context.Context, p map[string]interface{}) (sourcePage, error) {
	params := whParams{
		query:       strParam(p, "query", ""),
		categories:  strParam(p, "categories", "111"),
		purity:      strParam(p, "purity", "100"),
		sorting:     strParam(p, "sorting", "toplist"),
		order:       strParam(p, "order", "desc"),
		topRange:    strParam(p, "topRange", "1M"),
		atleast:     strParam(p, "atleast", ""),
		resolutions: strParam(p, "resolutions", ""),
		ratios:      strParam(p, "ratios", ""),
		colors:      strParam(p, "colors", ""),
		page:        int(intParam(p, "page", 1)),
	}
	if params.page < 1 {
		params.page = 1
	}
	apiKey := s.str("wallhaven.apiKey")
	collection := strParam(p, "collection", "")
	var (
		page sourcePage
		err  error
	)
	if collection == "" {
		page, err = s.wallhavenSearchAPI(ctx, params, apiKey)
	} else {
		page, err = s.wallhavenCollectionPage(ctx, s.str("wallhaven.username"), collection, params.page, apiKey)
	}
	if err != nil {
		return sourcePage{}, err
	}
	if atMost := strParam(p, "atmost", ""); atMost != "" {
		kept := page.results[:0]
		for _, r := range page.results {
			if withinMax(r.resolution, atMost) {
				kept = append(kept, r)
			}
		}
		page.results = kept
	}
	return page, nil
}

func (s *sources) wallhavenSearchAPI(ctx context.Context, params whParams, apiKey string) (sourcePage, error) {
	v := params.values()
	if apiKey != "" {
		v.Set("apikey", apiKey)
	}
	body, err := s.readText(ctx, http.MethodGet, "https://wallhaven.cc/api/v1/search?"+v.Encode(), nil, "Wallhaven")
	if err != nil {
		return sourcePage{}, err
	}
	return parseWallhavenSearch(body)
}

func (s *sources) wallhavenCollectionPage(ctx context.Context, username, id string, page int, apiKey string) (sourcePage, error) {
	v := url.Values{}
	v.Set("page", strconv.Itoa(page))
	if apiKey != "" {
		v.Set("apikey", apiKey)
	}
	u := fmt.Sprintf("https://wallhaven.cc/api/v1/collections/%s/%s?%s",
		url.PathEscape(username), url.PathEscape(id), v.Encode())
	body, err := s.readText(ctx, http.MethodGet, u, nil, "Wallhaven")
	if err != nil {
		return sourcePage{}, err
	}
	return parseWallhavenSearch(body)
}

type whCollection struct {
	ID    uint64 `json:"id"`
	Label string `json:"label"`
	Count uint64 `json:"count"`
}

type whCollections struct {
	Data []whCollection `json:"data"`
}

func parseWallhavenCollections(body string) ([]map[string]interface{}, error) {
	var parsed whCollections
	if err := json.Unmarshal([]byte(body), &parsed); err != nil {
		return nil, err
	}
	out := make([]map[string]interface{}, 0, len(parsed.Data))
	for _, c := range parsed.Data {
		out = append(out, map[string]interface{}{"id": c.ID, "label": c.Label, "count": c.Count})
	}
	return out, nil
}

func (s *sources) wallhavenCollections(reqID int64, p map[string]interface{}) response {
	username := strParam(p, "username", "")
	if username == "" {
		username = s.str("wallhaven.username")
	}
	if username == "" {
		return errResp(reqID, -1, "set your wallhaven username in settings first")
	}
	ctx, cancel := context.WithTimeout(context.Background(), searchFetchTimeout)
	defer cancel()
	v := url.Values{}
	if apiKey := s.str("wallhaven.apiKey"); apiKey != "" {
		v.Set("apikey", apiKey)
	}
	u := "https://wallhaven.cc/api/v1/collections/" + url.PathEscape(username)
	if e := v.Encode(); e != "" {
		u += "?" + e
	}
	body, err := s.readText(ctx, http.MethodGet, u, nil, "Wallhaven")
	if err != nil {
		return errResp(reqID, -1, searchError(err))
	}
	cols, err := parseWallhavenCollections(body)
	if err != nil {
		return errResp(reqID, -1, err.Error())
	}
	return ok(reqID, cols)
}

func importPreview(preview, dest string) error {
	if err := checkFile(preview, sniffImage); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	if os.Link(preview, dest) == nil {
		return nil
	}
	src, err := os.Open(preview)
	if err != nil {
		return err
	}
	defer src.Close()
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
	if _, err := copyBounded(src, file, previewMaxEncoded); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmp, dest); err != nil {
		return err
	}
	committed = true
	return nil
}

func (s *sources) wallhavenFetch(ctx context.Context, fullURL, wallpaperDir, id string, onProgress func(float64)) (string, error) {
	if err := requireSource("wallhaven", fullURL); err != nil {
		return "", err
	}
	ext := extFromURL(fullURL)
	dest := downloadDest(wallpaperDir, "wallhaven", id, ext)
	if importPreview(s.remotePreviewPath("wallhaven-full", id, ext), dest) == nil {
		return dest, nil
	}
	policy := func(u string) error { return requireSource("wallhaven", u) }
	if err := s.fetchToFile(ctx, fullURL, dest, sniffImage, maxDownloadBytes, policy, onProgress); err != nil {
		return "", err
	}
	return dest, nil
}

func (s *sources) wallhavenDownload(reqID int64, p map[string]interface{}) response {
	id := strParam(p, "id", "")
	fullURL := strParam(p, "fullUrl", "")
	if id == "" || fullURL == "" {
		return errResp(reqID, -32602, "missing id/fullUrl")
	}
	wdir := s.d.config().wallpaperDir()
	if existing, has := sourceLibraryPath(wdir, "wallhaven", id); has {
		return s.respondExists(reqID, id, existing)
	}
	return s.startDownload(reqID, id, s.images, "wallhaven:"+id, func(ctx context.Context, _ *gateSlot) {
		msg := "fetching"
		zero := 0.0
		s.emitDownload(downloadEvent{ID: id, Status: dlDownloading, Progress: &zero, Message: &msg})
		onProgress := func(pct float64) {
			p := pct
			s.emitDownload(downloadEvent{ID: id, Status: dlDownloading, Progress: &p, Message: &msg})
		}
		path, err := s.wallhavenFetch(ctx, fullURL, wdir, id, onProgress)
		s.finishDownload(id, path, err)
	})
}
