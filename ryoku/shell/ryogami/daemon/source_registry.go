package main

import (
	"context"
	"os/exec"
	"sync"
	"time"
)

type searchFlight struct {
	generation int64
	cancel     context.CancelFunc
}

type searchScope struct {
	connectionID uint64
	source       string
}

type sources struct {
	d    *daemon
	http *httpStack

	previews *gate
	images   *gate
	videos   *gate

	inflightMu sync.Mutex
	inflight   map[string]bool

	cancelMu sync.Mutex
	cancels  map[string]context.CancelFunc

	searchMu          sync.Mutex
	searchNext        uint64
	searchConnections map[uint64]bool
	searchLatest      map[searchScope]int64
	searches          map[searchScope]map[uint64]searchFlight
	thumbLatest       map[searchScope]int64
	searchHook        func(context.Context, string, map[string]interface{}) (sourcePage, error)

	progressMu sync.Mutex
	progress   map[string]progressEventState

	libraryMu    sync.Mutex
	libraryCache map[string]libraryIDCache

	thumbSem chan struct{}
}

func newSources(d *daemon) *sources {
	return &sources{
		d:                 d,
		http:              newHTTPStack(),
		previews:          newGate(2, 16),
		images:            newGate(3, 12),
		videos:            newGate(2, 6),
		inflight:          map[string]bool{},
		cancels:           map[string]context.CancelFunc{},
		searchConnections: map[uint64]bool{},
		searchLatest:      map[searchScope]int64{},
		searches:          map[searchScope]map[uint64]searchFlight{},
		thumbLatest:       map[searchScope]int64{},
		progress:          map[string]progressEventState{},
		libraryCache:      map[string]libraryIDCache{},
		thumbSem:          make(chan struct{}, thumbFetchConcurrent),
	}
}

type providerDef struct {
	key        string
	label      string
	media      string
	searchable bool
}

// Steam Workshop is listed for its availability; its search and download ride workshop.* RPCs.
var providerTable = []providerDef{
	{"wallhaven", "Wallhaven", "image", true},
	{"steam", "Steam Workshop", "scene", true},
	{"unsplash", "Unsplash", "image", true},
	{"pexels", "Pexels", "image", true},
	{"youtube", "YouTube", "video", true},
	{"bing", "Bing Daily", "image", false},
	{"moewalls", "MoeWalls", "video", true},
	{"motionbgs", "MotionBGs", "video", true},
	{"ryostore", "Ryostore", "video", true},
	{"repos", "Repos", "video", true},
}

func providerSpec(key string) *providerDef {
	for i := range providerTable {
		if providerTable[i].key == key {
			return &providerTable[i]
		}
	}
	return nil
}

func (s *sources) providerAvailability(key string) (bool, string) {
	switch key {
	case "wallhaven":
		if !s.flag("features.wallhaven") {
			return false, "Disabled"
		}
		return true, ""
	case "steam":
		if !s.flag("features.steam") {
			return false, "Disabled"
		}
		return true, ""
	case "unsplash":
		if !s.flag("sources.unsplash.enabled") {
			return false, "Disabled"
		}
		if s.str("sources.unsplash.accessKey") == "" {
			return false, "MissingCredentials"
		}
		return true, ""
	case "pexels":
		if !s.flag("sources.pexels.enabled") {
			return false, "Disabled"
		}
		if s.str("sources.pexels.apiKey") == "" {
			return false, "MissingCredentials"
		}
		return true, ""
	case "youtube":
		if !s.flag("sources.youtube.enabled") {
			return false, "Disabled"
		}
		if !toolPresent(youtubeBin) {
			return false, "MissingTool"
		}
		return true, ""
	case "bing":
		if !s.flag("sources.bing.enabled") {
			return false, "Disabled"
		}
		return true, ""
	case "moewalls", "motionbgs", "ryostore", "repos":
		return true, ""
	}
	return false, "Disabled"
}

// MissingCredentials and MissingTool still reach the provider so its own error string shows.
func (s *sources) enabled(key string) bool {
	available, reason := s.providerAvailability(key)
	return available || reason != "Disabled"
}

func (s *sources) providers(reqID int64) response {
	list := make([]map[string]interface{}, 0, len(providerTable))
	for _, def := range providerTable {
		available, reason := s.providerAvailability(def.key)
		item := map[string]interface{}{
			"key":        def.key,
			"label":      def.label,
			"media":      def.media,
			"searchable": def.searchable,
			"available":  available,
		}
		if reason != "" {
			item["unavailableReason"] = reason
		}
		list = append(list, item)
	}
	return ok(reqID, list)
}

func toolPresent(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func (s *sources) str(key string) string {
	if v, ok := s.d.setting(key).(string); ok {
		return v
	}
	return ""
}

func (s *sources) flag(key string) bool {
	if v, ok := s.d.setting(key).(bool); ok {
		return v
	}
	return false
}

func (s *sources) num(key string) int64 {
	switch v := s.d.setting(key).(type) {
	case float64:
		return int64(v)
	case int64:
		return v
	case int:
		return int64(v)
	}
	return 0
}

func (s *sources) beginInflight(key string) bool {
	s.inflightMu.Lock()
	defer s.inflightMu.Unlock()
	if s.inflight[key] {
		return false
	}
	s.inflight[key] = true
	return true
}

func (s *sources) endInflight(key string) {
	s.inflightMu.Lock()
	defer s.inflightMu.Unlock()
	delete(s.inflight, key)
}

func (s *sources) registerCancel(id string, cancel context.CancelFunc) {
	s.cancelMu.Lock()
	defer s.cancelMu.Unlock()
	s.cancels[id] = cancel
}

func (s *sources) clearCancel(id string) {
	s.cancelMu.Lock()
	defer s.cancelMu.Unlock()
	delete(s.cancels, id)
}

func (s *sources) cancelDownload(id string) bool {
	s.cancelMu.Lock()
	cancel, ok := s.cancels[id]
	s.cancelMu.Unlock()
	if ok {
		cancel()
	}
	return ok
}

func (s *sources) openSearchConnection(connectionID uint64) {
	s.searchMu.Lock()
	s.searchConnections[connectionID] = true
	s.searchMu.Unlock()
}

func (s *sources) dropSearchConnection(connectionID uint64) {
	s.searchMu.Lock()
	delete(s.searchConnections, connectionID)
	for scope, flights := range s.searches {
		if scope.connectionID != connectionID {
			continue
		}
		for _, flight := range flights {
			flight.cancel()
		}
		delete(s.searches, scope)
		delete(s.searchLatest, scope)
		delete(s.thumbLatest, scope)
	}
	for scope := range s.searchLatest {
		if scope.connectionID == connectionID {
			delete(s.searchLatest, scope)
			delete(s.thumbLatest, scope)
		}
	}
	s.searchMu.Unlock()
}

func (s *sources) beginSearch(connectionID uint64, source string, generation int64, timeout time.Duration) (context.Context, func(), bool) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	scope := searchScope{connectionID: connectionID, source: source}
	s.searchMu.Lock()
	if connectionID != 0 && !s.searchConnections[connectionID] {
		s.searchMu.Unlock()
		cancel()
		return ctx, func() {}, true
	}
	if generation > 0 {
		if latest := s.searchLatest[scope]; latest > generation {
			s.searchMu.Unlock()
			cancel()
			return ctx, func() {}, true
		}
		if generation > s.searchLatest[scope] {
			s.searchLatest[scope] = generation
			s.thumbLatest[scope] = generation
			for token, flight := range s.searches[scope] {
				if flight.generation > 0 && flight.generation < generation {
					flight.cancel()
					delete(s.searches[scope], token)
				}
			}
		}
	}
	s.searchNext++
	token := s.searchNext
	if s.searches[scope] == nil {
		s.searches[scope] = map[uint64]searchFlight{}
	}
	s.searches[scope][token] = searchFlight{generation: generation, cancel: cancel}
	s.searchMu.Unlock()

	finish := func() {
		cancel()
		s.searchMu.Lock()
		delete(s.searches[scope], token)
		if len(s.searches[scope]) == 0 {
			delete(s.searches, scope)
		}
		s.searchMu.Unlock()
	}
	return ctx, finish, false
}

func (s *sources) thumbGenerationCurrent(connectionID uint64, source string, generation int64) bool {
	scope := searchScope{connectionID: connectionID, source: source}
	s.searchMu.Lock()
	active := connectionID == 0 || s.searchConnections[connectionID]
	current := s.thumbLatest[scope]
	s.searchMu.Unlock()
	return active && (generation <= 0 || generation >= current)
}
