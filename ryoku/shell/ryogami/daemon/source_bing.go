package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
)

const bingHost = "https://www.bing.com"

type bingImage struct {
	URLBase       string `json:"urlbase"`
	URL           string `json:"url"`
	StartDate     string `json:"startdate"`
	Copyright     string `json:"copyright"`
	CopyrightLink string `json:"copyrightlink"`
	Title         string `json:"title"`
}

type bingResp struct {
	Images []bingImage `json:"images"`
}

func bingID(urlbase, startdate string) string {
	if i := strings.Index(urlbase, "id="); i >= 0 {
		rest := urlbase[i+3:]
		if j := strings.IndexAny(rest, "&?"); j >= 0 {
			rest = rest[:j]
		}
		if rest != "" {
			return rest
		}
	}
	return startdate
}

func bingAbsolute(path string) string {
	if strings.HasPrefix(path, "http") {
		return path
	}
	return bingHost + path
}

func parseBingSearch(body string) (sourcePage, error) {
	var resp bingResp
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return sourcePage{}, err
	}
	results := make([]sourceResult, 0, len(resp.Images))
	for _, img := range resp.Images {
		if img.URLBase == "" && img.URL == "" {
			continue
		}
		var full, thumb string
		if img.URLBase == "" {
			full = bingAbsolute(img.URL)
			thumb = bingAbsolute(img.URL)
		} else {
			full = bingAbsolute(img.URLBase + "_UHD.jpg")
			thumb = bingAbsolute(img.URLBase + "_400x240.jpg")
		}
		r := sourceResult{
			id:         bingID(img.URLBase, img.StartDate),
			fullURL:    full,
			thumbURL:   thumb,
			resolution: "3840x2160",
			title:      img.Title,
		}
		if img.Copyright != "" {
			r.attribution = img.Copyright
			r.attributionURL = img.CopyrightLink
		}
		results = append(results, r)
	}
	return sourcePage{results: results, lastPage: 1, currentPage: 1}, nil
}

// The feed is not searchable: the query is ignored and only the market matters.
func (s *sources) bingSearch(ctx context.Context, p map[string]interface{}) (sourcePage, error) {
	market := strParam(p, "market", "")
	if market == "" {
		market = s.str("sources.bing.market")
	}
	if market == "" {
		market = "en-US"
	}
	v := url.Values{}
	v.Set("format", "js")
	v.Set("idx", "0")
	v.Set("n", "8")
	v.Set("mkt", market)
	body, err := s.readText(ctx, http.MethodGet, bingHost+"/HPImageArchive.aspx?"+v.Encode(), nil, "Bing")
	if err != nil {
		return sourcePage{}, err
	}
	return parseBingSearch(body)
}
