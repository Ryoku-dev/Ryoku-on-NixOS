package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type lightingSnapshot struct {
	Hub    bool                   `json:"hub"`
	Busy   bool                   `json:"busy"`
	Op     string                 `json:"op"`
	Report map[string]interface{} `json:"report"`
	Error  string                 `json:"error"`
	Seq    uint64                 `json:"seq"`
}

type lightingOperation struct {
	kind  string
	verb  string
	key   string
	patch map[string]interface{}
	args  []string
}

type lightingTimeoutSet struct {
	state  time.Duration
	scan   time.Duration
	enable time.Duration
	change time.Duration
	apply  time.Duration
}

type lightingController struct {
	d *daemon

	mu                  sync.Mutex
	hub                 bool
	queue               []lightingOperation
	running             string
	report              map[string]interface{}
	err                 string
	seq                 uint64
	watchingPalette     bool
	lastLightingRequest time.Time

	wake chan struct{}
	stop chan struct{}
	once sync.Once

	timeouts          lightingTimeoutSet
	paletteIdleWindow time.Duration
}

var lightingControllers sync.Map

func init() {
	registerAvailability("lighting", func(*daemon) bool {
		_, err := exec.LookPath("ryoku-hub")
		return err == nil
	})
}

func lightingControllerFor(d *daemon) *lightingController {
	if found, ok := lightingControllers.Load(d); ok {
		return found.(*lightingController)
	}
	_, err := exec.LookPath("ryoku-hub")
	candidate := &lightingController{
		d:                 d,
		hub:               err == nil,
		wake:              make(chan struct{}, 1),
		stop:              make(chan struct{}),
		paletteIdleWindow: 2 * time.Minute,
		timeouts: lightingTimeoutSet{
			state:  15 * time.Second,
			scan:   120 * time.Second,
			enable: 120 * time.Second,
			change: 60 * time.Second,
			apply:  60 * time.Second,
		},
	}
	actual, loaded := lightingControllers.LoadOrStore(d, candidate)
	controller := candidate
	if loaded {
		controller = actual.(*lightingController)
	}
	controller.start()
	return controller
}

func (c *lightingController) start() {
	c.once.Do(func() {
		go c.work()
	})
}

func (c *lightingController) snapshotLocked() lightingSnapshot {
	return lightingSnapshot{
		Hub:    c.hub,
		Busy:   c.running != "" || len(c.queue) > 0,
		Op:     c.running,
		Report: c.report,
		Error:  c.err,
		Seq:    c.seq,
	}
}

func lightingReportHasOnlineDevice(report map[string]interface{}) bool {
	devices, _ := report["devices"].([]interface{})
	for _, raw := range devices {
		device, ok := raw.(map[string]interface{})
		if ok && device["online"] == true {
			return true
		}
	}
	return false
}

func cloneLightingObject(source map[string]interface{}) map[string]interface{} {
	cloned := make(map[string]interface{}, len(source))
	for key, value := range source {
		cloned[key] = value
	}
	return cloned
}

func mergeLightingStateReport(cached, state map[string]interface{}) map[string]interface{} {
	enabled, _ := state["enabled"].(bool)
	if !enabled || !lightingReportHasOnlineDevice(cached) {
		return state
	}

	stateDevices, _ := state["devices"].([]interface{})
	savedByKey := make(map[string]map[string]interface{}, len(stateDevices))
	for _, raw := range stateDevices {
		device, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		key, ok := device["key"].(string)
		if ok {
			savedByKey[key] = device
		}
	}

	cachedDevices, _ := cached["devices"].([]interface{})
	devices := make([]interface{}, 0, len(cachedDevices)+len(stateDevices))
	seen := make(map[string]bool, len(cachedDevices))
	savedFields := [...]string{
		"managed", "mode", "effect", "source", "colors", "zoneColors",
		"brightness", "speed", "direction", "restore", "following", "name",
	}
	for _, raw := range cachedDevices {
		live, ok := raw.(map[string]interface{})
		if !ok || live["online"] != true {
			continue
		}
		merged := cloneLightingObject(live)
		key, _ := live["key"].(string)
		if saved, ok := savedByKey[key]; ok {
			for _, field := range savedFields {
				if value, exists := saved[field]; exists {
					merged[field] = value
				} else {
					delete(merged, field)
				}
			}
		}
		seen[key] = true
		devices = append(devices, merged)
	}
	for _, raw := range stateDevices {
		saved, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		key, _ := saved["key"].(string)
		if seen[key] {
			continue
		}
		offline := cloneLightingObject(saved)
		offline["online"] = false
		devices = append(devices, offline)
	}

	merged := cloneLightingObject(state)
	merged["devices"] = devices
	return merged
}

func (c *lightingController) enqueue(op lightingOperation) lightingSnapshot {
	return c.enqueueOperation(op, true)
}

func (c *lightingController) enqueuePaletteRefresh(op lightingOperation) lightingSnapshot {
	return c.enqueueOperation(op, false)
}

func (c *lightingController) enqueueOperation(op lightingOperation, lightingRequest bool) lightingSnapshot {
	c.mu.Lock()
	startWatcher := false
	if lightingRequest {
		c.lastLightingRequest = time.Now()
		if !c.watchingPalette {
			c.watchingPalette = true
			startWatcher = true
		}
	}

	appendOperation := true
	switch op.kind {
	case "state", "scan":
		if op.kind == "state" && c.running == op.verb {
			appendOperation = false
			break
		}
		for i := range c.queue {
			if c.queue[i].kind == op.kind {
				appendOperation = false
				break
			}
		}
	case "enable":
		for i := range c.queue {
			if c.queue[i].kind == op.kind {
				c.queue[i] = op
				appendOperation = false
				break
			}
		}
	case "set":
		for i := range c.queue {
			if c.queue[i].kind != op.kind || c.queue[i].key != op.key {
				continue
			}
			for key, value := range op.patch {
				c.queue[i].patch[key] = value
			}
			appendOperation = false
			break
		}
	}
	if appendOperation {
		c.queue = append(c.queue, op)
	}
	snapshot := c.snapshotLocked()
	c.mu.Unlock()

	if startWatcher {
		go c.watchPalette()
	}
	if appendOperation {
		select {
		case c.wake <- struct{}{}:
		default:
		}
	}
	return snapshot
}

func (c *lightingController) work() {
	for {
		select {
		case <-c.wake:
		case <-c.stop:
			return
		}
		for {
			c.mu.Lock()
			if len(c.queue) == 0 {
				c.mu.Unlock()
				break
			}
			op := c.queue[0]
			c.queue = c.queue[1:]
			c.running = op.verb
			c.err = ""
			c.seq++
			started := c.snapshotLocked()
			c.mu.Unlock()
			c.d.broadcast("ryogami.lighting", started)

			report, opErr := c.execute(op)

			c.mu.Lock()
			if report != nil {
				if op.kind == "state" || op.kind == "apply" {
					c.report = mergeLightingStateReport(c.report, report)
				} else {
					c.report = report
				}
			}
			c.err = opErr
			c.running = ""
			c.seq++
			finished := c.snapshotLocked()
			c.mu.Unlock()
			c.d.broadcast("ryogami.lighting", finished)
		}
	}
}

func (c *lightingController) execute(op lightingOperation) (map[string]interface{}, string) {
	if op.kind == "apply" {
		_, applyErr := c.run([]string{"apply"}, c.timeouts.apply, false)
		report, stateErr := c.run([]string{"state"}, c.timeouts.state, true)
		switch {
		case applyErr != "" && stateErr != "":
			return report, applyErr + "; " + stateErr
		case applyErr != "":
			return report, applyErr
		default:
			return report, stateErr
		}
	}

	args := op.args
	if op.kind == "set" {
		patch, err := json.Marshal(op.patch)
		if err != nil {
			return nil, err.Error()
		}
		args = []string{"set", op.key, string(patch)}
	}
	return c.run(args, c.timeout(op.kind), true)
}

func (c *lightingController) timeout(kind string) time.Duration {
	switch kind {
	case "state":
		return c.timeouts.state
	case "scan":
		return c.timeouts.scan
	case "enable":
		return c.timeouts.enable
	default:
		return c.timeouts.change
	}
}

func (c *lightingController) run(args []string, timeout time.Duration, wantsReport bool) (map[string]interface{}, string) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	argv := append([]string{"lighting"}, args...)
	cmd := exec.CommandContext(ctx, "ryoku-hub", argv...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return os.ErrProcessDone
		}
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()

	var report map[string]interface{}
	var parseErr error
	if wantsReport {
		body := bytes.TrimSpace(stdout.Bytes())
		if len(body) == 0 {
			parseErr = errors.New("empty response")
		} else if err := json.Unmarshal(body, &report); err != nil {
			parseErr = err
		} else if report == nil {
			parseErr = errors.New("response is not an object")
		}
	}

	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return report, fmt.Sprintf("lighting %s timed out after %s", args[0], timeout)
	}
	if err != nil {
		if line := lastNonEmptyLine(stderr.String()); line != "" {
			return report, line
		}
		return report, err.Error()
	}
	if parseErr != nil {
		return nil, fmt.Sprintf("invalid lighting response: %v", parseErr)
	}
	if reportErr, ok := report["error"].(string); ok && strings.TrimSpace(reportErr) != "" {
		return report, reportErr
	}
	return report, ""
}

type lightingPaletteStamp struct {
	exists bool
	mtime  int64
	size   int64
	inode  uint64
}

func paletteFileStamp(path string) lightingPaletteStamp {
	info, err := os.Stat(path)
	if err != nil {
		return lightingPaletteStamp{}
	}
	stamp := lightingPaletteStamp{exists: true, mtime: info.ModTime().UnixNano(), size: info.Size()}
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		stamp.inode = stat.Ino
	}
	return stamp
}

func lightingPalettePath() string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".cache")
	}
	return filepath.Join(base, "ryoku", "hypr-colors.lua")
}

func (c *lightingController) watchPalette() {
	path := lightingPalettePath()
	previous := paletteFileStamp(path)
	ticker := time.NewTicker(750 * time.Millisecond)
	defer ticker.Stop()

	c.mu.Lock()
	idleWindow := c.paletteIdleWindow
	c.mu.Unlock()
	idle := time.NewTimer(idleWindow)
	defer idle.Stop()

	for {
		select {
		case <-ticker.C:
			current := paletteFileStamp(path)
			if current != previous {
				previous = current
				c.enqueuePaletteRefresh(lightingOperation{kind: "state", verb: "state", args: []string{"state"}})
			}
		case <-idle.C:
			c.mu.Lock()
			remaining := idleWindow - time.Since(c.lastLightingRequest)
			if remaining > 0 {
				c.mu.Unlock()
				idle.Reset(remaining)
				continue
			}
			c.watchingPalette = false
			c.mu.Unlock()
			return
		case <-c.stop:
			return
		}
	}
}

func (d *daemon) dispatchLighting(req *request, p map[string]interface{}) (response, bool) {
	var op lightingOperation
	switch req.Method {
	case "lighting.state":
		op = lightingOperation{kind: "state", verb: "state", args: []string{"state"}}
	case "lighting.scan":
		op = lightingOperation{kind: "scan", verb: "scan", args: []string{"scan"}}
	case "lighting.enable":
		on, ok := p["on"].(bool)
		if !ok {
			return errResp(req.ID, 1, "missing 'on' parameter"), true
		}
		verb := "disable"
		if on {
			verb = "enable"
		}
		op = lightingOperation{kind: "enable", verb: verb, args: []string{verb}}
	case "lighting.follow":
		on, ok := p["on"].(bool)
		if !ok {
			return errResp(req.ID, 1, "missing 'on' parameter"), true
		}
		target := strParam(p, "key", "")
		if all, _ := p["all"].(bool); all {
			target = "--all"
		}
		if target == "" {
			return errResp(req.ID, 1, "missing 'key' or 'all' parameter"), true
		}
		state := "off"
		if on {
			state = "on"
		}
		op = lightingOperation{kind: "follow", verb: "follow", args: []string{"follow", target, state}}
	case "lighting.set":
		key := strParam(p, "key", "")
		patch, ok := p["patch"].(map[string]interface{})
		if key == "" || !ok {
			return errResp(req.ID, 1, "missing 'key' or 'patch' parameter"), true
		}
		copyPatch := make(map[string]interface{}, len(patch))
		for name, value := range patch {
			copyPatch[name] = value
		}
		op = lightingOperation{kind: "set", verb: "set", key: key, patch: copyPatch}
	case "lighting.save", "lighting.release":
		key := strParam(p, "key", "")
		if key == "" {
			return errResp(req.ID, 1, "missing 'key' parameter"), true
		}
		verb := strings.TrimPrefix(req.Method, "lighting.")
		op = lightingOperation{kind: verb, verb: verb, args: []string{verb, key}}
	case "lighting.apply":
		op = lightingOperation{kind: "apply", verb: "apply", args: []string{"apply"}}
	default:
		return response{}, false
	}
	return ok(req.ID, lightingControllerFor(d).enqueue(op)), true
}
