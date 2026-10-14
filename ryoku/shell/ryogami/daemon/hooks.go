package main

import (
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"
)

// Features register at package init so each lives in its own file.

type applyRequest struct {
	Type    string
	Path    string
	WeID    string
	Outputs []string // empty means every output
	Reason  string
}

type applyEvent struct {
	applyRequest
	Name string
	Key  string
}

type settingWatcher struct {
	prefix string
	fn     func(d *daemon, key string, value interface{})
}

var (
	startHooks      []func(d *daemon)
	applyGuards     []func(d *daemon, req *applyRequest) error
	afterApplyHooks []func(d *daemon, ev applyEvent)
	settingWatchers []settingWatcher
)

func onStart(fn func(d *daemon)) { startHooks = append(startHooks, fn) }

func guardApply(fn func(d *daemon, req *applyRequest) error) {
	applyGuards = append(applyGuards, fn)
}

func afterApply(fn func(d *daemon, ev applyEvent)) { afterApplyHooks = append(afterApplyHooks, fn) }

func watchSetting(prefix string, fn func(d *daemon, key string, value interface{})) {
	settingWatchers = append(settingWatchers, settingWatcher{prefix: prefix, fn: fn})
}

func (d *daemon) runStartHooks() {
	for _, fn := range startHooks {
		fn(d)
	}
}

// Guards run in registration order and see the outputs narrowed by earlier ones.
func (d *daemon) runApplyGuards(req *applyRequest) error {
	for _, fn := range applyGuards {
		if err := fn(d, req); err != nil {
			return err
		}
	}
	return nil
}

// Hooks run on their own goroutine so a slow one never delays the reply.
func (d *daemon) runAfterApply(ev applyEvent) {
	if len(afterApplyHooks) == 0 {
		return
	}
	go func() {
		for _, fn := range afterApplyHooks {
			fn(d, ev)
		}
	}()
}

type settingChange struct {
	key   string
	value interface{}
}

var (
	settingNotifyMu      sync.Mutex
	settingNotifyQueue   []settingChange
	settingNotifyRunning bool
)

// notifySetting runs watchers one change at a time so a watcher never races itself.
// A watcher may write further settings: those changes queue behind the current one
// and the caller already running watchers drains them, instead of re-entering.
func (d *daemon) notifySetting(key string, value interface{}) {
	settingNotifyMu.Lock()
	settingNotifyQueue = append(settingNotifyQueue, settingChange{key, value})
	if settingNotifyRunning {
		settingNotifyMu.Unlock()
		return
	}
	settingNotifyRunning = true
	for len(settingNotifyQueue) > 0 {
		c := settingNotifyQueue[0]
		settingNotifyQueue = settingNotifyQueue[1:]
		settingNotifyMu.Unlock()
		for _, w := range settingWatchers {
			if strings.HasPrefix(c.key, w.prefix) {
				w.fn(d, c.key, c.value)
			}
		}
		settingNotifyMu.Lock()
	}
	settingNotifyRunning = false
	settingNotifyMu.Unlock()
}

type actionFunc func(d *daemon, args map[string]interface{}) (interface{}, error)

type availabilityState struct {
	value      bool
	ready      bool
	refreshing bool
	at         time.Time
}

const availabilityTTL = 30 * time.Second

var (
	actions           = map[string]actionFunc{}
	availability      = map[string]func(d *daemon) bool{}
	availabilityMu    sync.Mutex
	availabilityCache = map[string]availabilityState{}
)

func registerAction(id string, fn actionFunc) {
	if _, dup := actions[id]; dup {
		panic("ryogami: duplicate action " + id)
	}
	actions[id] = fn
}

func (d *daemon) runAction(id string, args map[string]interface{}) (interface{}, error) {
	fn, ok := actions[id]
	if !ok {
		return nil, fmt.Errorf("unknown action: %s", id)
	}
	return fn(d, args)
}

func registerAvailability(name string, fn func(d *daemon) bool) {
	availabilityMu.Lock()
	availability[name] = fn
	delete(availabilityCache, name)
	availabilityMu.Unlock()
}

func (d *daemon) refreshAvailability(name string, fn func(*daemon) bool) {
	value := fn(d)
	availabilityMu.Lock()
	state := availabilityCache[name]
	state.value = value
	state.ready = true
	state.refreshing = false
	state.at = time.Now()
	availabilityCache[name] = state
	availabilityMu.Unlock()
}

func (d *daemon) availabilityValue(name string, fn func(*daemon) bool) bool {
	availabilityMu.Lock()
	state := availabilityCache[name]
	if !state.refreshing && (!state.ready || time.Since(state.at) >= availabilityTTL) {
		state.refreshing = true
		availabilityCache[name] = state
		go d.refreshAvailability(name, fn)
	}
	value := state.value
	if !state.ready {
		value = true
	}
	availabilityMu.Unlock()
	return value
}

func (d *daemon) warmAvailability() {
	availabilityMu.Lock()
	funcs := make(map[string]func(*daemon) bool, len(availability))
	for name, fn := range availability {
		funcs[name] = fn
	}
	availabilityMu.Unlock()
	for name, fn := range funcs {
		d.availabilityValue(name, fn)
	}
}

func (d *daemon) availabilityMap() map[string]bool {
	availabilityMu.Lock()
	names := make([]string, 0, len(availability))
	funcs := make(map[string]func(*daemon) bool, len(availability))
	for name, fn := range availability {
		names = append(names, name)
		funcs[name] = fn
	}
	availabilityMu.Unlock()
	sort.Strings(names)
	out := make(map[string]bool, len(names))
	for _, name := range names {
		out[name] = d.availabilityValue(name, funcs[name])
	}
	return out
}
