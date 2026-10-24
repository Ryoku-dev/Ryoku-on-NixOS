package main

import (
	"bufio"
	"encoding/json"
	"hash/fnv"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// askhistory.go persists recent quick asks so the launcher's "\resume" can
// list them and recall a cached answer instantly, no model call. It is a
// small append-capped JSONL under XDG_STATE_HOME, newest last.

type askRecord struct {
	ID               string      `json:"id"`
	At               string      `json:"at"`             // RFC3339
	Kind             string      `json:"kind,omitempty"` // quick (default) | term
	Question         string      `json:"q"`
	Answer           string      `json:"a"`
	Images           []string    `json:"images,omitempty"`
	Actions          []askAction `json:"actions,omitempty"`
	Plan             *termPlan   `json:"plan,omitempty"` // the terminal lane's command plan
	Via              string      `json:"via,omitempty"`
	NeedsAgent       bool        `json:"needsAgent,omitempty"`
	NeedsAgentReason string      `json:"needsAgentReason,omitempty"`
}

const askHistoryCap = 40

func askHistoryPath() string {
	return filepath.Join(xdgState(), "ryoku", "rashin-asks.jsonl")
}

var askHistoryMu sync.Mutex

var askIDClock atomic.Int64

func newAskID(prefix byte) string {
	for {
		old := askIDClock.Load()
		next := time.Now().UnixNano()
		if next <= old {
			next = old + 1
		}
		if askIDClock.CompareAndSwap(old, next) {
			return string(prefix) + strconv.FormatInt(next, 36)
		}
	}
}

// recordAsk appends one completed ask, trimming the file to the cap. New
// records keep their id even when no answer arrived, so an in-progress hand-off
// can still resolve the original question.
func recordAsk(rec askRecord) {
	empty := strings.TrimSpace(rec.Answer) == "" || strings.HasPrefix(rec.Answer, "(no answer")
	if empty && rec.Plan == nil && rec.ID == "" {
		return
	}
	if rec.ID == "" {
		prefix := byte('a')
		if rec.Kind == "term" {
			prefix = 't'
		}
		rec.ID = newAskID(prefix)
	}
	askHistoryMu.Lock()
	defer askHistoryMu.Unlock()

	recs := readAskHistoryLocked()
	recs = append(recs, rec)
	if len(recs) > askHistoryCap {
		recs = recs[len(recs)-askHistoryCap:]
	}
	p := askHistoryPath()
	if os.MkdirAll(filepath.Dir(p), 0o755) != nil {
		return
	}
	var b strings.Builder
	enc := json.NewEncoder(&b)
	for _, r := range recs {
		_ = enc.Encode(r)
	}
	tmp := p + ".tmp"
	if os.WriteFile(tmp, []byte(b.String()), 0o644) == nil {
		_ = os.Rename(tmp, p)
	}
}

func readAskHistoryLocked() []askRecord {
	f, err := os.Open(askHistoryPath())
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []askRecord
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64*1024), 4<<20)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var r askRecord
		if json.Unmarshal([]byte(line), &r) == nil && r.Question != "" {
			if r.ID == "" {
				r.ID = legacyAskID(r)
			}
			out = append(out, r)
		}
	}
	return out
}

func legacyAskID(rec askRecord) string {
	h := fnv.New64a()
	_, _ = h.Write([]byte(rec.At))
	_, _ = h.Write([]byte{0})
	_, _ = h.Write([]byte(rec.Kind))
	_, _ = h.Write([]byte{0})
	_, _ = h.Write([]byte(rec.Question))
	prefix := "a"
	if rec.Kind == "term" {
		prefix = "t"
	}
	return prefix + strconv.FormatUint(h.Sum64(), 36)
}

// RecentAsks returns up to n asks, newest first, for the resume list.
func RecentAsks(n int) []askRecord {
	askHistoryMu.Lock()
	recs := readAskHistoryLocked()
	askHistoryMu.Unlock()
	// newest first
	for i, j := 0, len(recs)-1; i < j; i, j = i+1, j-1 {
		recs[i], recs[j] = recs[j], recs[i]
	}
	if n > 0 && len(recs) > n {
		recs = recs[:n]
	}
	return recs
}

func askByID(id string) (askRecord, bool) {
	askHistoryMu.Lock()
	defer askHistoryMu.Unlock()
	for _, rec := range readAskHistoryLocked() {
		if rec.ID == id {
			return rec, true
		}
	}
	return askRecord{}, false
}

func nowRFC3339() string { return time.Now().Format(time.RFC3339) }
