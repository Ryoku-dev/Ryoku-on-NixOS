package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// A resident helper keeps the model in memory and is reaped when idle.

const lensServeIdle = 90 * time.Second

type lensServe struct {
	cmd       *exec.Cmd
	wc        io.WriteCloser
	stdin     *bufio.Writer
	stdout    *bufio.Reader
	paths     semanticPaths
	closeOnce sync.Once
}

func spawnLensServe(paths semanticPaths) (*lensServe, error) {
	cmd := exec.Command(paths.helper,
		"--serve",
		"--manifest", paths.manifest,
		"--index", paths.index,
		"--runtime", paths.runtime,
		"--threads", strconv.Itoa(lensThreads()),
	)
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start semantic search: %w", err)
	}
	return &lensServe{
		cmd:    cmd,
		wc:     stdin,
		stdin:  bufio.NewWriter(stdin),
		stdout: bufio.NewReader(stdout),
		paths:  paths,
	}, nil
}

func (s *lensServe) search(gen uint64, text string, limit int) ([]map[string]interface{}, error) {
	line, err := json.Marshal(map[string]interface{}{
		"generation":         gen,
		"query":              text,
		"negativeWeight":     0.5,
		"topK":               limit,
		"scoreWindow":        0.022,
		"minScoreProminence": 0.015,
		"maxResults":         limit,
		"minResults":         0,
	})
	if err != nil {
		return nil, err
	}
	if _, err := s.stdin.Write(line); err != nil {
		return nil, err
	}
	if err := s.stdin.WriteByte('\n'); err != nil {
		return nil, err
	}
	if err := s.stdin.Flush(); err != nil {
		return nil, err
	}
	resp, err := s.stdout.ReadBytes('\n')
	if err != nil {
		return nil, fmt.Errorf("semantic search ended before responding: %w", err)
	}
	var decoded struct {
		Matches []struct {
			Key   string  `json:"key"`
			Score float32 `json:"score"`
		} `json:"matches"`
		Error *string `json:"error"`
	}
	if err := json.Unmarshal(resp, &decoded); err != nil {
		return nil, fmt.Errorf("decode semantic response: %w", err)
	}
	if decoded.Error != nil && *decoded.Error != "" {
		return nil, errors.New(*decoded.Error)
	}
	out := make([]map[string]interface{}, 0, len(decoded.Matches))
	for _, m := range decoded.Matches {
		out = append(out, map[string]interface{}{"key": m.Key, "score": m.Score})
	}
	return out, nil
}

func (s *lensServe) close() {
	s.closeOnce.Do(func() {
		if s.wc != nil {
			_ = s.wc.Close()
		}
		if s.cmd != nil && s.cmd.Process != nil {
			_ = syscall.Kill(-s.cmd.Process.Pid, syscall.SIGKILL)
			go func(c *exec.Cmd) { _ = c.Wait() }(s.cmd)
		}
	})
}

// An unavailable search is an error the folio shows, never a silent empty result.
func (m *lensManager) query(text string, limit int) ([]map[string]interface{}, error) {
	text = strings.TrimSpace(text)
	if text == "" {
		return []map[string]interface{}{}, nil
	}
	if limit <= 0 {
		limit = 48
	}

	m.svcMu.Lock()
	defer m.svcMu.Unlock()

	if !m.d.settingBool("semantic.enabled") {
		return nil, errors.New("semantic search is turned off")
	}
	paths, ok := m.d.discoverSemanticPaths()
	if !ok {
		return nil, errors.New("semantic search is unavailable: skwd-lens or a model pack is not installed")
	}
	if !indexModelMatches(paths) {
		return nil, errors.New("the semantic index is still being prepared")
	}
	if m.svc != nil && m.svc.paths != paths {
		m.svc.close()
		m.svc = nil
	}
	if m.svc == nil {
		svc, err := spawnLensServe(paths)
		if err != nil {
			return nil, err
		}
		m.svc = svc
	}
	m.gen++
	svc := m.svc
	timedOut := make(chan struct{})
	timer := time.AfterFunc(searchFetchTimeout, func() {
		close(timedOut)
		svc.close()
	})
	results, err := svc.search(m.gen, text, limit)
	if !timer.Stop() {
		<-timedOut
	}
	select {
	case <-timedOut:
		err = fmt.Errorf("semantic search timed out after %s", searchFetchTimeout)
	default:
	}
	if err != nil {
		svc.close()
		m.svc = nil
		return nil, err
	}
	m.armIdleReaperLocked()
	return results, nil
}

func (m *lensManager) armIdleReaperLocked() {
	if m.idle != nil {
		m.idle.Stop()
	}
	m.idle = time.AfterFunc(lensServeIdle, func() {
		m.svcMu.Lock()
		defer m.svcMu.Unlock()
		if m.svc != nil {
			m.svc.close()
			m.svc = nil
		}
	})
}

func (m *lensManager) stopService() {
	m.svcMu.Lock()
	defer m.svcMu.Unlock()
	if m.idle != nil {
		m.idle.Stop()
		m.idle = nil
	}
	if m.svc != nil {
		m.svc.close()
		m.svc = nil
	}
}

func (d *daemon) dispatchSemantic(req *request, p map[string]interface{}) (response, bool) {
	switch req.Method {
	case "semantic.query":
		results, err := d.lens().query(strParam(p, "query", ""), int(intParam(p, "limit", 48)))
		if err != nil {
			return errResp(req.ID, 6, err.Error()), true
		}
		return ok(req.ID, map[string]interface{}{"results": results}), true
	case "semantic.status":
		return ok(req.ID, d.lens().status()), true
	}
	return errResp(req.ID, -32601, "unknown method: "+req.Method), true
}
