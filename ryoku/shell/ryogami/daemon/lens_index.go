package main

import (
	"bufio"
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
)

type buildEntry struct {
	Key         string `json:"key"`
	Path        string `json:"path"`
	Fingerprint uint64 `json:"fingerprint"`
	View        string `json:"view"`
}

type buildRequest struct {
	Fingerprint uint64       `json:"fingerprint"`
	Entries     []buildEntry `json:"entries"`
}

func lensEligible(e Entry) bool {
	return strings.TrimRight(e.Name, "/") != "" && strings.TrimSpace(e.Thumb) != ""
}

// Stable per thumbnail so the helper reuses cached embeddings and reindexing stays incremental.
func entryFingerprint(thumb string, mtime int64, view string) uint64 {
	h := fnv.New64a()
	h.Write([]byte(thumb))
	var b [8]byte
	binary.LittleEndian.PutUint64(b[:], uint64(mtime))
	h.Write(b[:])
	if fi, err := os.Stat(thumb); err == nil {
		binary.LittleEndian.PutUint64(b[:], uint64(fi.Size()))
		h.Write(b[:])
		binary.LittleEndian.PutUint64(b[:], uint64(fi.ModTime().UnixNano()))
		h.Write(b[:])
	}
	if view != "full" {
		h.Write([]byte(view))
	}
	return h.Sum64()
}

func (d *daemon) catalogRequest(multiview bool) buildRequest {
	h := fnv.New64a()
	feed := func(s string) {
		h.Write([]byte(s))
		h.Write([]byte{0})
	}
	feedU := func(v uint64) {
		var b [8]byte
		binary.LittleEndian.PutUint64(b[:], v)
		h.Write(b[:])
	}
	var entries []buildEntry
	for _, e := range d.store.list(false) {
		if !lensEligible(e) {
			continue
		}
		key := e.Key
		if key == "" {
			key = strings.TrimRight(e.Name, "/")
		}
		thumb := e.Thumb
		feed(key)
		feed(thumb)
		feedU(uint64(e.Mtime))
		fp := entryFingerprint(thumb, e.Mtime, "full")
		feedU(fp)
		entries = append(entries, buildEntry{Key: key, Path: thumb, Fingerprint: fp, View: "full"})
		if !multiview {
			continue
		}
		feed("multiview-v1")
		feedU(uint64(e.Width))
		feedU(uint64(e.Height))
		entries = append(entries, buildEntry{
			Key: key, Path: thumb, Fingerprint: entryFingerprint(thumb, e.Mtime, "center"), View: "center",
		})
		if e.Type == "static" && e.Width > 0 && e.Height > 0 && e.Width >= e.Height*2 {
			for _, view := range []string{"leftThird", "rightThird"} {
				entries = append(entries, buildEntry{
					Key: key, Path: thumb, Fingerprint: entryFingerprint(thumb, e.Mtime, view), View: view,
				})
			}
		}
	}
	return buildRequest{Fingerprint: h.Sum64(), Entries: entries}
}

func (d *daemon) eligibleCount() int {
	n := 0
	for _, e := range d.store.list(false) {
		if lensEligible(e) {
			n++
		}
	}
	return n
}

func lensThreads() int {
	n := runtime.NumCPU()
	if n > 4 {
		n = 4
	}
	if n < 1 {
		n = 1
	}
	return n
}

func clearIndex(index string) {
	for _, p := range []string{index, index + ".fingerprint"} {
		if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
			fmt.Fprintf(os.Stderr, "ryogami: clear semantic index: %v\n", err)
		}
	}
}

func (m *lensManager) start() {
	go m.watchLibraryEvents()
	go m.buildLoop()
	m.requestReindex()
}

// Dropping a duplicate request loses nothing: a rebuild reuses cached embeddings.
func (m *lensManager) requestReindex() {
	select {
	case m.refresh <- struct{}{}:
	default:
	}
}

func (m *lensManager) watchLibraryEvents() {
	ch := m.d.events.subscribe()
	defer m.d.events.unsubscribe(ch)
	for line := range ch {
		var ev struct {
			Event string `json:"event"`
			Data  struct {
				Status string `json:"status"`
			} `json:"data"`
		}
		if json.Unmarshal([]byte(line), &ev) != nil {
			continue
		}
		switch ev.Event {
		case "ryogami.wall.scan_done":
			m.requestReindex()
		case "ryogami.wall.cache":
			if ev.Data.Status == "ready" {
				m.requestReindex()
			}
		}
	}
}

func (m *lensManager) buildLoop() {
	for range m.refresh {
		m.runReindex()
	}
}

func (m *lensManager) runReindex() {
	if !m.d.settingBool("semantic.enabled") {
		m.publishStatus()
		return
	}
	paths, ok := m.d.discoverSemanticPaths()
	if !ok {
		m.publishStatus()
		return
	}
	req := m.d.catalogRequest(paths.multiview)
	if len(req.Entries) == 0 {
		clearIndex(paths.index)
		m.publishStatus()
		return
	}
	if indexCurrent(paths, req.Fingerprint) {
		m.publishStatus()
		return
	}
	m.build(paths, req)
	m.publishStatus()
}

func (m *lensManager) build(paths semanticPaths, req buildRequest) {
	ctx, cancel := context.WithCancel(context.Background())
	m.buildMu.Lock()
	if m.cancelBuild != nil {
		m.cancelBuild()
	}
	m.cancelBuild = cancel
	m.building = true
	m.buildMu.Unlock()
	defer func() {
		m.buildMu.Lock()
		m.building = false
		m.cancelBuild = nil
		m.buildMu.Unlock()
		cancel()
	}()

	if dir := filepath.Dir(paths.index); dir != "" {
		_ = os.MkdirAll(dir, 0o755)
	}
	m.publishStatus()
	m.d.tasks.start("semantic-index", "semantic", "Index", len(req.Entries), cancel)

	// nice keeps the encode at idle priority so it never contends with the desktop.
	cmd := exec.CommandContext(ctx, "nice", "-n", "19", paths.helper,
		"--build-index",
		"--manifest", paths.manifest,
		"--index", paths.index,
		"--runtime", paths.runtime,
		"--threads", strconv.Itoa(lensThreads()),
		"--progress-json",
	)
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		m.d.tasks.finish("semantic-index", taskFailed, 0, err.Error())
		fmt.Fprintf(os.Stderr, "ryogami: semantic index: %v\n", err)
		return
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		m.d.tasks.finish("semantic-index", taskFailed, 0, err.Error())
		fmt.Fprintf(os.Stderr, "ryogami: semantic index: %v\n", err)
		return
	}
	if err := cmd.Start(); err != nil {
		m.d.tasks.finish("semantic-index", taskFailed, 0, err.Error())
		fmt.Fprintf(os.Stderr, "ryogami: semantic index: %v\n", err)
		return
	}
	go func() {
		defer stdin.Close()
		if enc, err := json.Marshal(req); err == nil {
			_, _ = stdin.Write(enc)
		}
	}()
	sc := bufio.NewScanner(stdout)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for sc.Scan() {
		var p struct {
			Progress int    `json:"progress"`
			Total    int    `json:"total"`
			Detail   string `json:"detail"`
		}
		if json.Unmarshal(sc.Bytes(), &p) == nil {
			m.publishBuildProgress(p.Detail, p.Progress, p.Total)
			m.d.tasks.progress("semantic-index", p.Progress, p.Total, p.Detail)
		}
	}
	err = cmd.Wait()
	switch {
	case ctx.Err() != nil:
		m.d.tasks.finish("semantic-index", taskCancelled, 0, "")
	case err != nil:
		m.d.tasks.finish("semantic-index", taskFailed, 0, err.Error())
		fmt.Fprintf(os.Stderr, "ryogami: semantic index build failed: %v\n", err)
	default:
		m.d.tasks.finish("semantic-index", taskCompleted, 0, "")
	}
}

type lensStatus struct {
	// State is the plain condition the search UI shows: "ready", "indexing",
	// "noModel" (import a pack), "disabled" (turned off) or "unavailable"
	// (skwd-lens or its runtime is not installed on this system).
	State   string `json:"state"`
	Indexed int    `json:"indexed"`
	Total   int    `json:"total"`
	Model   string `json:"model"`
	Busy    bool   `json:"busy"`
}

func (m *lensManager) status() lensStatus {
	m.buildMu.Lock()
	busy := m.building
	m.buildMu.Unlock()
	st := lensStatus{State: m.semanticState(), Busy: busy, Total: m.d.eligibleCount()}
	if paths, ok := m.d.discoverSemanticPaths(); ok {
		st.Model = manifestIdentity(paths.manifest)
		st.Indexed = indexUniqueKeys(paths.index)
	}
	return st
}

// semanticState reports exactly why Describe search is or is not usable, so the picker
// can say what is missing instead of failing silently. The checks mirror the order of
// discoverSemanticPaths so a component that is present is never reported as missing.
func (m *lensManager) semanticState() string {
	if lensHelper() == "" {
		return "unavailable"
	}
	manifest := m.d.lensManifest()
	if manifest == "" || !fileExists(manifest) {
		return "noModel"
	}
	if rt := lensRuntime(manifest); rt == "" || !fileExists(rt) {
		return "unavailable"
	}
	if !m.d.settingBool("semantic.enabled") {
		return "disabled"
	}
	paths, ok := m.d.discoverSemanticPaths()
	if !ok {
		return "unavailable"
	}
	m.buildMu.Lock()
	busy := m.building
	m.buildMu.Unlock()
	if busy {
		return "indexing"
	}
	// An empty library has nothing to index, so search is set up even with no index file.
	if m.d.eligibleCount() == 0 {
		return "ready"
	}
	if !indexModelMatches(paths) || indexUniqueKeys(paths.index) == 0 {
		return "indexing"
	}
	return "ready"
}

func (m *lensManager) publishStatus() {
	m.d.broadcast("ryogami.semantic.status", m.status())
}

func (m *lensManager) publishBuildProgress(detail string, encoded, encodeTotal int) {
	st := m.status()
	m.d.broadcast("ryogami.semantic.status", map[string]interface{}{
		"state":       st.State,
		"indexed":     st.Indexed,
		"total":       st.Total,
		"model":       st.Model,
		"busy":        st.Busy,
		"detail":      detail,
		"encoded":     encoded,
		"encodeTotal": encodeTotal,
	})
}

func (m *lensManager) onSettingChanged(key string) {
	switch key {
	case "semantic.enabled":
		if m.d.settingBool("semantic.enabled") {
			m.requestReindex()
		} else {
			m.cancelBuildNow()
			m.stopService()
			m.publishStatus()
		}
	case "semantic.manifest", "semantic.indexProfile":
		m.stopService()
		m.requestReindex()
	}
}

func (m *lensManager) cancelBuildNow() {
	m.buildMu.Lock()
	if m.cancelBuild != nil {
		m.cancelBuild()
	}
	m.buildMu.Unlock()
}
