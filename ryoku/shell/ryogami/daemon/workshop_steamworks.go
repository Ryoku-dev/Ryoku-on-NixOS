package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// The skwd-steam helper needs Steam running and an account that owns Wallpaper Engine.

const steamHelperBin = "skwd-steam"

func resolveSteamHelper() string {
	if exe, err := os.Executable(); err == nil {
		if cand := filepath.Join(filepath.Dir(exe), steamHelperBin); isExecutableFile(cand) {
			return cand
		}
	}
	if p, err := exec.LookPath(steamHelperBin); err == nil {
		return p
	}
	return ""
}

func steamHelperPresent() bool {
	return resolveSteamHelper() != ""
}

func isExecutableFile(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.Mode().IsRegular() && fi.Mode().Perm()&0o111 != 0
}

func (w *workshopLib) steamworksDownload(item, requested string) bool {
	d := w.d
	bin := resolveSteamHelper()
	if bin == "" {
		d.emitWorkshopDownload(requested, "error", 0, "Steam Client helper (skwd-steam) is not installed", "")
		return false
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, item)
	cmd.Stdin = nil
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		d.emitWorkshopDownload(requested, "error", 0, "Steam Client helper output could not be read", "")
		return false
	}
	if err := cmd.Start(); err != nil {
		d.emitWorkshopDownload(requested, "error", 0, "failed to start Steam Client helper", "")
		return false
	}

	var folder, lastError string
	sc := bufio.NewScanner(stdout)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		var ev map[string]interface{}
		if json.Unmarshal(sc.Bytes(), &ev) != nil {
			continue
		}
		id, _ := ev["id"].(string)
		if id == "" {
			continue
		}
		status, _ := ev["status"].(string)
		progress, _ := ev["progress"].(float64)
		message, _ := ev["message"].(string)
		msg := message
		if item != requested && msg == "" {
			msg = "Downloading required Workshop item " + item
		}
		switch status {
		case "done":
			if f, ok := ev["folder"].(string); ok {
				folder = f
			}
			d.emitWorkshopDownload(requested, "downloading", 1.0, msg, "")
		case "error":
			if message != "" {
				lastError = message
			}
		default:
			d.emitWorkshopDownload(requested, "downloading", progress, msg, "")
		}
	}
	_ = cmd.Wait()

	if folder != "" {
		reconcileWeItem(w.workshopDir(), item, folder)
	}
	if dirExists(filepath.Join(w.workshopDir(), item)) {
		return true
	}
	if lastError == "" {
		lastError = "Steam couldn't install the item - make sure Steam is running and signed in to the account that owns Wallpaper Engine"
	}
	d.emitWorkshopDownload(requested, "error", 0, lastError, "")
	return false
}

func (w *workshopLib) steamworksSearch(ctx context.Context, p steamSearchParams) (searchPage, error) {
	bin := resolveSteamHelper()
	if bin == "" {
		return searchPage{}, fmt.Errorf("Steam Client helper (skwd-steam) is not installed")
	}
	req, _ := json.Marshal(map[string]interface{}{
		"query":         p.query,
		"query_type":    p.queryType,
		"days":          p.days,
		"tags":          p.tags,
		"excluded_tags": p.excludedTags,
		"page":          p.page,
	})
	cmd := exec.CommandContext(ctx, bin, "search", string(req))
	cmd.Stdin = nil
	out, err := cmd.Output()
	line := lastJSONLine(string(out))
	if err != nil && line == "" {
		return searchPage{}, fmt.Errorf("Steam Client helper failed; is native Steam running and signed in? %w", err)
	}
	return parseHelperSearch([]byte(line), p.page)
}

func lastJSONLine(s string) string {
	lines := strings.Split(s, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.HasPrefix(strings.TrimSpace(lines[i]), "{") {
			return lines[i]
		}
	}
	return ""
}

type helperItem struct {
	ID            string `json:"id"`
	Title         string `json:"title"`
	PreviewURL    string `json:"preview_url"`
	FileSize      uint64 `json:"file_size"`
	Subscriptions uint64 `json:"subscriptions"`
	Tags          string `json:"tags"`
}

type helperRoot struct {
	Results []helperItem `json:"results"`
	Error   string       `json:"error"`
}

func parseHelperSearch(body []byte, page int) (searchPage, error) {
	var root helperRoot
	if err := json.Unmarshal(body, &root); err != nil {
		return searchPage{}, err
	}
	if root.Error != "" {
		return searchPage{}, fmt.Errorf("%s", root.Error)
	}
	var results []steamResult
	for _, it := range root.Results {
		if it.ID == "" {
			continue
		}
		var tags []string
		for _, t := range strings.Split(it.Tags, ",") {
			if t = strings.TrimSpace(t); t != "" {
				tags = append(tags, t)
			}
		}
		results = append(results, steamResult{
			id:            it.ID,
			title:         it.Title,
			previewURL:    it.PreviewURL,
			fileSize:      it.FileSize,
			subscriptions: it.Subscriptions,
			tags:          tags,
		})
	}
	page = maxInt(page, 1)
	last := page
	if len(results) > 0 {
		last = page + 1
	}
	return searchPage{results: results, currentPage: page, lastPage: last}, nil
}
