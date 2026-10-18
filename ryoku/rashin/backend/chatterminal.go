package main

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type chatTerminalConflict string

func (e chatTerminalConflict) Error() string { return string(e) }

type chatTerminalPlan struct {
	Cwd  string
	Argv []string
}

func resumeArgv(backendID, sessionID string) ([]string, error) {
	sessionID = strings.TrimSpace(sessionID)
	if sessionID == "" {
		return nil, chatTerminalConflict("no session to open")
	}
	switch backendID {
	case "hermes":
		bin, ok := FindHermes()
		if !ok {
			return nil, chatTerminalConflict("Hermes is not available")
		}
		return []string{bin, "--resume", sessionID}, nil
	case "omp":
		return []string{"omp", "--resume=" + sessionID}, nil
	case "claude":
		return []string{"claude", "--resume", sessionID}, nil
	case "codex":
		return []string{"codex", "resume", sessionID}, nil
	default:
		return nil, chatTerminalConflict("this agent cannot resume sessions in a terminal")
	}
}

func planChatTerminal(h *chatHub) (chatTerminalPlan, error) {
	if h == nil {
		return chatTerminalPlan{}, chatTerminalConflict("no session to open")
	}
	h.mu.Lock()
	conn := h.conn
	cwd := h.lane.Cwd
	h.mu.Unlock()
	if conn == nil {
		return chatTerminalPlan{}, chatTerminalConflict("no session to open")
	}
	backendID, sessionID := conn.backendSession()
	argv, err := resumeArgv(backendID, sessionID)
	if err != nil {
		return chatTerminalPlan{}, err
	}
	return chatTerminalPlan{Cwd: cwd, Argv: argv}, nil
}

var chatTerminalLauncher = launchTerminal

func openChatTerminal(h *chatHub) error {
	plan, err := planChatTerminal(h)
	if err != nil {
		return err
	}
	return chatTerminalLauncher(plan.Cwd, "ryoku-rashin-", plan.Argv)
}

func cmdChatTerminal(args []string) error {
	lane := laneRyoku
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--lane" && i+1 < len(args):
			i++
			lane = args[i]
		case strings.HasPrefix(args[i], "--lane="):
			lane = strings.TrimPrefix(args[i], "--lane=")
		default:
			return fmt.Errorf("usage: ryoku-rashin terminal [--lane ryoku|chat]")
		}
	}
	if lane != laneRyoku && lane != laneChat {
		return fmt.Errorf("unknown lane %q", lane)
	}
	cfg := LoadConfig()
	endpoint := fmt.Sprintf("http://127.0.0.1:%d/api/chat/terminal?lane=%s", cfg.Port, url.QueryEscape(lane))
	req, err := http.NewRequest(http.MethodPost, endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("Rashin is not running: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNoContent {
		return nil
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	reason := strings.TrimSpace(string(body))
	if reason == "" {
		reason = resp.Status
	}
	if resp.StatusCode == http.StatusConflict {
		return errors.New(reason)
	}
	return fmt.Errorf("open session: %s", reason)
}
