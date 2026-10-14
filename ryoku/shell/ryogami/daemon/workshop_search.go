package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

// Keyless browse (community HTML plus GetPublishedFileDetails) needs no key or running Steam.

type steamSearchParams struct {
	query        string
	queryType    int
	days         int
	tags         []string
	excludedTags []string
	page         int
	numPerPage   int
	allowNsfw    bool
}

type steamResult struct {
	id            string
	title         string
	previewURL    string
	fileSize      uint64
	subscriptions uint64
	tags          []string
}

type searchPage struct {
	results     []steamResult
	currentPage int
	lastPage    int
}

// Keyed like every other source's results; the picker reads one shape for all of them.
type wsItem struct {
	ID            string `json:"id"`
	FullURL       string `json:"fullUrl"`
	ThumbURL      string `json:"thumbUrl"`
	ThumbPath     string `json:"thumbPath"`
	FileSize      uint64 `json:"fileSize"`
	Category      string `json:"category"`
	Title         string `json:"title"`
	Subscriptions uint64 `json:"subscriptions,omitempty"`
	Downloaded    bool   `json:"downloaded"`
}

func (w *workshopLib) search(ctx context.Context, p steamSearchParams) (searchPage, error) {
	backend := wkString(w.d.setting("steam.backend"))
	apiKey := wkString(w.d.setting("steam.apiKey"))
	var page searchPage
	var err error
	switch {
	case backend == "steam" && steamHelperPresent():
		page, err = w.steamworksSearch(ctx, p)
	case apiKey != "":
		page, err = w.webAPISearch(ctx, p, apiKey)
	default:
		page, err = w.keylessSearch(ctx, p)
	}
	if err != nil {
		return searchPage{}, err
	}
	kept := page.results[:0]
	for _, r := range page.results {
		if acceptWorkshopTags(r.tags, p.allowNsfw) {
			kept = append(kept, r)
		}
	}
	page.results = kept
	return page, nil
}

func (w *workshopLib) items(page searchPage) []wsItem {
	downloaded := map[string]bool{}
	for _, entry := range w.d.store.list(false) {
		if entry.Type == "we" && entry.WeID != "" {
			downloaded[entry.WeID] = true
		}
	}
	out := make([]wsItem, 0, len(page.results))
	for _, r := range page.results {
		out = append(out, wsItem{
			ID:            r.id,
			FullURL:       r.previewURL,
			ThumbURL:      r.previewURL,
			ThumbPath:     w.d.remoteThumbPath("steam", r.id, r.previewURL),
			FileSize:      r.fileSize,
			Category:      strings.Join(r.tags, ", "),
			Title:         r.title,
			Subscriptions: r.subscriptions,
			Downloaded:    downloaded[r.id],
		})
	}
	return out
}

func thumbJobs(page searchPage) [][2]string {
	var jobs [][2]string
	for _, r := range page.results {
		if r.previewURL != "" {
			jobs = append(jobs, [2]string{r.id, r.previewURL})
		}
	}
	return jobs
}

func acceptWorkshopTags(tags []string, allowNsfw bool) bool {
	hasType := false
	for _, t := range tags {
		switch t {
		case "Scene", "Video":
			hasType = true
		case "Web", "Application":
			return false
		}
		if !allowNsfw && isNsfwTag(t) {
			return false
		}
	}
	return hasType
}

func isNsfwTag(t string) bool {
	switch t {
	case "Mature", "Questionable", "Nudity", "NSFW":
		return true
	}
	return false
}

func (w *workshopLib) keylessSearch(ctx context.Context, p steamSearchParams) (searchPage, error) {
	body, err := w.d.httpGetBytesContext(ctx, communityBrowseURL(p), nil, 8<<20)
	if err != nil {
		return searchPage{}, fmt.Errorf("Steam Workshop request failed: %w", err)
	}
	ids := extractWorkshopIDs(string(body))
	page := maxInt(p.page, 1)
	if len(ids) == 0 {
		return searchPage{currentPage: page, lastPage: page}, nil
	}
	results, err := w.getPublishedFileDetails(ctx, ids)
	if err != nil {
		return searchPage{}, err
	}
	last := page
	if len(results) > 0 {
		last = page + 1
	}
	return searchPage{results: results, currentPage: page, lastPage: last}, nil
}

func communityBrowseURL(p steamSearchParams) string {
	v := url.Values{}
	v.Set("appid", workshopAppID)
	v.Set("section", "readytouseitems")
	v.Set("browsesort", browseSort(p.queryType))
	v.Set("p", strconv.Itoa(maxInt(p.page, 1)))
	if p.query != "" {
		v.Set("searchtext", p.query)
	}
	for _, t := range p.tags {
		if t != "" {
			v.Add("requiredtags[]", t)
		}
	}
	if p.queryType == 3 && p.days > 0 {
		v.Set("days", strconv.Itoa(clampInt(p.days, 1, 7)))
	}
	return "https://steamcommunity.com/workshop/browse/?" + v.Encode()
}

func browseSort(queryType int) string {
	switch queryType {
	case 0:
		return "toprated"
	case 1:
		return "mostrecent"
	case 9:
		return "totaluniquesubscribers"
	case 21:
		return "lastupdated"
	default:
		return "trend"
	}
}

var workshopIDRe = regexp.MustCompile(`filedetails/\?id=(\d+)`)

func extractWorkshopIDs(html string) []string {
	matches := workshopIDRe.FindAllStringSubmatch(html, -1)
	seen := map[string]bool{}
	var out []string
	for _, m := range matches {
		id := m[1]
		if id == "" || id == "0" || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

func (w *workshopLib) getPublishedFileDetails(ctx context.Context, ids []string) ([]steamResult, error) {
	form := url.Values{}
	form.Set("itemcount", strconv.Itoa(len(ids)))
	for i, id := range ids {
		form.Set(fmt.Sprintf("publishedfileids[%d]", i), id)
	}
	body, err := w.d.httpPostFormContext(ctx, "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/", form, 8<<20)
	if err != nil {
		return nil, fmt.Errorf("Steam Workshop request failed: %w", err)
	}
	return parsePublishedFileDetails(body)
}

func (w *workshopLib) webAPISearch(ctx context.Context, p steamSearchParams, apiKey string) (searchPage, error) {
	u := "https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/?" + queryFilesValues(p, apiKey).Encode()
	body, err := w.d.httpGetBytesContext(ctx, u, nil, 8<<20)
	if err != nil {
		return searchPage{}, fmt.Errorf("Steam Workshop request failed: %w", err)
	}
	return parseQueryFiles(body, p.page, p.numPerPage)
}

func queryFilesValues(p steamSearchParams, apiKey string) url.Values {
	v := url.Values{}
	v.Set("key", apiKey)
	v.Set("appid", workshopAppID)
	v.Set("query_type", strconv.Itoa(p.queryType))
	v.Set("numperpage", strconv.Itoa(clampInt(p.numPerPage, 1, 50)))
	v.Set("page", strconv.Itoa(maxInt(p.page, 1)))
	v.Set("return_previews", "true")
	v.Set("return_tags", "true")
	v.Set("match_all_tags", "true")
	if p.query != "" {
		v.Set("search_text", p.query)
	}
	if p.queryType == 3 && p.days > 0 {
		v.Set("days", strconv.Itoa(clampInt(p.days, 1, 7)))
	}
	for i, t := range p.tags {
		if t != "" {
			v.Set(fmt.Sprintf("requiredtags[%d]", i), t)
		}
	}
	for i, t := range p.excludedTags {
		if t != "" {
			v.Set(fmt.Sprintf("excludedtags[%d]", i), t)
		}
	}
	return v
}

type steamTag struct {
	Tag string `json:"tag"`
}

type steamDetail struct {
	PublishedFileID string     `json:"publishedfileid"`
	Title           string     `json:"title"`
	PreviewURL      string     `json:"preview_url"`
	FileSize        string     `json:"file_size"`
	Subscriptions   uint64     `json:"subscriptions"`
	Tags            []steamTag `json:"tags"`
}

type steamAPIRoot struct {
	Response *struct {
		Total                uint32        `json:"total"`
		PublishedFileDetails []steamDetail `json:"publishedfiledetails"`
	} `json:"response"`
}

func detailToResult(d steamDetail) steamResult {
	fs, _ := strconv.ParseUint(strings.TrimSpace(d.FileSize), 10, 64)
	var tags []string
	for _, t := range d.Tags {
		if t.Tag != "" {
			tags = append(tags, t.Tag)
		}
	}
	return steamResult{
		id:            d.PublishedFileID,
		title:         d.Title,
		previewURL:    d.PreviewURL,
		fileSize:      fs,
		subscriptions: d.Subscriptions,
		tags:          tags,
	}
}

func parsePublishedFileDetails(body []byte) ([]steamResult, error) {
	var root steamAPIRoot
	if err := json.Unmarshal(body, &root); err != nil {
		return nil, err
	}
	if root.Response == nil {
		return nil, fmt.Errorf("steam: empty response")
	}
	var out []steamResult
	for _, d := range root.Response.PublishedFileDetails {
		if d.PublishedFileID == "" || d.PublishedFileID == "0" {
			continue
		}
		out = append(out, detailToResult(d))
	}
	return out, nil
}

func parseQueryFiles(body []byte, page, numPerPage int) (searchPage, error) {
	var root steamAPIRoot
	if err := json.Unmarshal(body, &root); err != nil {
		return searchPage{}, err
	}
	if root.Response == nil {
		return searchPage{}, fmt.Errorf("steam: empty response")
	}
	var results []steamResult
	for _, d := range root.Response.PublishedFileDetails {
		if d.PublishedFileID == "" || d.PublishedFileID == "0" {
			continue
		}
		results = append(results, detailToResult(d))
	}
	per := maxInt(numPerPage, 1)
	last := maxInt(divCeil(int(root.Response.Total), per), 1)
	return searchPage{results: results, currentPage: maxInt(page, 1), lastPage: last}, nil
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func divCeil(a, b int) int {
	if b <= 0 {
		return a
	}
	return (a + b - 1) / b
}
