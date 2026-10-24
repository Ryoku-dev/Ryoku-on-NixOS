package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

const unsplashUTM = "ryogami"

// The provider APIs reject unknown enum values, so an unrecognised filter is dropped.
func clampEnum(v string, allowed ...string) string {
	for _, a := range allowed {
		if v == a {
			return v
		}
	}
	return ""
}

// The Unsplash API guidelines require these UTM tags on photographer links.
func unsplashReferral(profile string) string {
	if profile == "" {
		return ""
	}
	sep := "?"
	if strings.Contains(profile, "?") {
		sep = "&"
	}
	return profile + sep + "utm_source=" + unsplashUTM + "&utm_medium=referral"
}

type unsplashURLs struct {
	Full  string `json:"full"`
	Raw   string `json:"raw"`
	Small string `json:"small"`
	Thumb string `json:"thumb"`
}

type unsplashLinks struct {
	DownloadLocation string `json:"download_location"`
	HTML             string `json:"html"`
}

type unsplashUser struct {
	Name  string        `json:"name"`
	Links unsplashLinks `json:"links"`
}

type unsplashPhoto struct {
	ID     string        `json:"id"`
	Width  int           `json:"width"`
	Height int           `json:"height"`
	URLs   unsplashURLs  `json:"urls"`
	Links  unsplashLinks `json:"links"`
	User   unsplashUser  `json:"user"`
}

type unsplashResp struct {
	TotalPages int             `json:"total_pages"`
	Results    []unsplashPhoto `json:"results"`
	Errors     []string        `json:"errors"`
}

func parseUnsplashSearch(body string, page int) (sourcePage, error) {
	var resp unsplashResp
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return sourcePage{}, err
	}
	if len(resp.Errors) > 0 {
		return sourcePage{}, fmt.Errorf("unsplash error: %s", resp.Errors[0])
	}
	results := make([]sourceResult, 0, len(resp.Results))
	for _, ph := range resp.Results {
		full := ph.URLs.Full
		if full == "" {
			full = ph.URLs.Raw
		}
		if full == "" {
			continue
		}
		thumb := ph.URLs.Small
		if thumb == "" {
			thumb = ph.URLs.Thumb
		}
		r := sourceResult{
			id:         ph.ID,
			fullURL:    full,
			thumbURL:   thumb,
			resolution: fmt.Sprintf("%dx%d", ph.Width, ph.Height),
			trackURL:   ph.Links.DownloadLocation,
		}
		if ph.User.Name != "" {
			r.attribution = "Photo by " + ph.User.Name + " on Unsplash"
			r.attributionURL = unsplashReferral(ph.User.Links.HTML)
		}
		results = append(results, r)
	}
	last := resp.TotalPages
	if last < 1 {
		last = 1
	}
	cur := page
	if cur < 1 {
		cur = 1
	}
	return sourcePage{results: results, lastPage: last, currentPage: cur}, nil
}

func (s *sources) unsplashSearch(ctx context.Context, p map[string]interface{}) (sourcePage, error) {
	accessKey := s.str("sources.unsplash.accessKey")
	if accessKey == "" {
		return sourcePage{}, fmt.Errorf("No Unsplash access key. Add one in Settings > Sources (free: unsplash.com/developers)")
	}
	query := strParam(p, "query", "")
	if query == "" {
		query = "wallpaper"
	}
	page := int(intParam(p, "page", 1))
	if page < 1 {
		page = 1
	}
	orderBy := strParam(p, "order_by", "relevant")
	if orderBy != "latest" {
		orderBy = "relevant"
	}
	contentFilter := strParam(p, "content_filter", "high")
	if contentFilter != "low" {
		contentFilter = "high"
	}
	orientation := clampEnum(strParam(p, "orientation", ""), "landscape", "portrait", "squarish")
	color := clampEnum(strParam(p, "color", ""),
		"black_and_white", "black", "white", "yellow", "orange", "red",
		"purple", "magenta", "green", "teal", "blue")
	v := url.Values{}
	v.Set("query", query)
	v.Set("page", strconv.Itoa(page))
	v.Set("per_page", "30")
	v.Set("order_by", orderBy)
	v.Set("content_filter", contentFilter)
	if orientation != "" {
		v.Set("orientation", orientation)
	}
	if color != "" {
		v.Set("color", color)
	}
	header := http.Header{"Authorization": []string{"Client-ID " + accessKey}}
	body, err := s.readText(ctx, http.MethodGet, "https://api.unsplash.com/search/photos?"+v.Encode(), header, "Unsplash")
	if err != nil {
		return sourcePage{}, err
	}
	return parseUnsplashSearch(body, page)
}

func (s *sources) unsplashTrack(ctx context.Context, trackURL, accessKey string) error {
	if trackURL == "" || accessKey == "" {
		return nil
	}
	if err := requireSource("unsplash", trackURL); err != nil {
		return err
	}
	header := http.Header{"Authorization": []string{"Client-ID " + accessKey}}
	_, err := s.getBytes(ctx, http.MethodGet, trackURL, header, nil, 1<<20)
	return err
}
