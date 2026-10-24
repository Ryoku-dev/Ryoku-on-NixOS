package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
)

func firstNonBlank(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

type pexelsSrc struct {
	Original string `json:"original"`
	Large2x  string `json:"large2x"`
	Large    string `json:"large"`
	Medium   string `json:"medium"`
}

type pexelsPhoto struct {
	ID              uint64    `json:"id"`
	Width           int       `json:"width"`
	Height          int       `json:"height"`
	URL             string    `json:"url"`
	Photographer    string    `json:"photographer"`
	PhotographerURL string    `json:"photographer_url"`
	Src             pexelsSrc `json:"src"`
	Alt             string    `json:"alt"`
}

type pexelsResp struct {
	Photos       []pexelsPhoto `json:"photos"`
	TotalResults int           `json:"total_results"`
	NextPage     *string       `json:"next_page"`
	Error        *string       `json:"error"`
}

func parsePexelsSearch(body string, page, perPage int) (sourcePage, error) {
	var resp pexelsResp
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return sourcePage{}, err
	}
	if resp.Error != nil && *resp.Error != "" {
		return sourcePage{}, fmt.Errorf("pexels error: %s", *resp.Error)
	}
	results := make([]sourceResult, 0, len(resp.Photos))
	for _, ph := range resp.Photos {
		full := firstNonBlank(ph.Src.Original, ph.Src.Large2x, ph.Src.Large, ph.Src.Medium)
		if full == "" {
			continue
		}
		thumb := ph.Src.Large
		if thumb == "" {
			thumb = ph.Src.Medium
		}
		r := sourceResult{
			id:         strconv.FormatUint(ph.ID, 10),
			fullURL:    full,
			thumbURL:   thumb,
			resolution: fmt.Sprintf("%dx%d", ph.Width, ph.Height),
			title:      ph.Alt,
		}
		if ph.Photographer != "" {
			r.attribution = "Photo by " + ph.Photographer + " on Pexels"
			r.attributionURL = firstNonBlank(ph.URL, ph.PhotographerURL)
		}
		results = append(results, r)
	}
	pp := perPage
	if pp < 1 {
		pp = 1
	}
	cur := page
	if cur < 1 {
		cur = 1
	}
	var last int
	switch {
	case resp.TotalResults > 0:
		last = (resp.TotalResults + pp - 1) / pp
		if last < 1 {
			last = 1
		}
	case resp.NextPage == nil || *resp.NextPage == "":
		last = cur
	default:
		last = cur + 1
	}
	return sourcePage{results: results, lastPage: last, currentPage: cur}, nil
}

func pexelsColor(color string) string {
	named := map[string]bool{
		"red": true, "orange": true, "yellow": true, "green": true,
		"turquoise": true, "blue": true, "violet": true, "pink": true,
		"brown": true, "black": true, "gray": true, "white": true,
	}
	if named[color] {
		return color
	}
	if len(color) == 7 && color[0] == '#' && allHex(color[1:]) {
		return color
	}
	return ""
}

func allHex(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
			return false
		}
	}
	return true
}

func (s *sources) pexelsSearch(ctx context.Context, p map[string]interface{}) (sourcePage, error) {
	apiKey := s.str("sources.pexels.apiKey")
	if apiKey == "" {
		return sourcePage{}, fmt.Errorf("No Pexels API key. Add one in Settings > Sources (free: pexels.com/api)")
	}
	query := strParam(p, "query", "")
	page := int(intParam(p, "page", 1))
	if page < 1 {
		page = 1
	}
	perPage := 30
	orientation := clampEnum(strParam(p, "orientation", ""), "landscape", "portrait", "square")
	size := clampEnum(strParam(p, "size", ""), "large", "medium", "small")
	color := pexelsColor(strParam(p, "color", ""))
	hasFilters := orientation != "" || size != "" || color != ""
	v := url.Values{}
	base := "https://api.pexels.com/v1/curated"
	if !(query == "" && !hasFilters) {
		base = "https://api.pexels.com/v1/search"
		q := query
		if q == "" {
			q = "wallpaper"
		}
		v.Set("query", q)
	}
	v.Set("page", strconv.Itoa(page))
	v.Set("per_page", strconv.Itoa(perPage))
	if orientation != "" {
		v.Set("orientation", orientation)
	}
	if size != "" {
		v.Set("size", size)
	}
	if color != "" {
		v.Set("color", color)
	}
	header := http.Header{"Authorization": []string{apiKey}}
	body, err := s.readText(ctx, http.MethodGet, base+"?"+v.Encode(), header, "Pexels")
	if err != nil {
		return sourcePage{}, err
	}
	return parsePexelsSearch(body, page, perPage)
}
