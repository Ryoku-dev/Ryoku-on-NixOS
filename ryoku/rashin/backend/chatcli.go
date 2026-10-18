package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// `chat` connects Rashin's Agent surfaces to the persistent Agent lane on
// /ws/chat. In `--follow` mode it is a transparent proxy between stdio and the
// socket: each server frame is one JSON line and every client line is forwarded
// unchanged. `--encode-image` turns attached image paths into prompt payloads.

func chatWSURL() string {
	// The shell's Agent mode names its persistent lane explicitly.
	return fmt.Sprintf("ws://127.0.0.1:%d/ws/chat?lane=ryoku", LoadConfig().Port)
}

func emitChat(frame map[string]any) {
	if b, err := json.Marshal(frame); err == nil {
		fmt.Println(string(b))
	}
}

func chatImageMime(p string) string {
	switch strings.ToLower(filepath.Ext(p)) {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".webp":
		return "image/webp"
	case ".gif":
		return "image/gif"
	default:
		return "image/png"
	}
}

func loadPromptImages(paths []string) []PromptImage {
	var out []PromptImage
	for _, p := range paths {
		data, mime := encodeImage(p)
		if data == "" {
			continue
		}
		out = append(out, PromptImage{Data: data, MimeType: mime})
	}
	return out
}

// encodeImage base64-encodes an image for the model, downscaling through
// ImageMagick to a sane edge (as the dashboard does) so a big screenshot or
// photo is small on the wire. If magick is missing or fails, the original
// bytes are sent.
func encodeImage(p string) (data, mime string) {
	if _, err := exec.LookPath("magick"); err == nil {
		out, err := exec.Command("magick", p, "-resize", "1568x1568>", "-strip", "-quality", "85", "jpeg:-").Output()
		if err == nil && len(out) > 0 {
			return base64.StdEncoding.EncodeToString(out), "image/jpeg"
		}
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return "", ""
	}
	return base64.StdEncoding.EncodeToString(b), chatImageMime(p)
}

func cmdChat(args []string) error {
	if len(args) > 0 && args[0] == "--follow" {
		return cmdChatFollow()
	}
	// --encode-image <path> (repeatable): the sidebar cannot base64 a file in
	// QML, so it asks here and drops the result into a user message it sends
	// over the follow stream.
	var images []string
	for i := 0; i < len(args); i++ {
		if args[i] == "--encode-image" && i+1 < len(args) {
			i++
			images = append(images, args[i])
		}
	}
	if len(images) > 0 {
		imgs := loadPromptImages(images)
		if imgs == nil {
			imgs = []PromptImage{}
		}
		emitChat(map[string]any{"type": "images", "images": imgs})
	}
	return nil
}

// followBackoff doubles the reconnect wait from 0.5s and caps it at 8s.
func followBackoff(d time.Duration) time.Duration {
	d *= 2
	if d > 8*time.Second {
		return 8 * time.Second
	}
	return d
}

// followDead is the frame the bridge prints whenever the socket is down; the
// daemon's join replay resyncs the view once it reconnects.
func followDead() {
	emitChat(map[string]any{"type": "state", "state": "dead", "error": "connection lost"})
}

// followSleep waits d or until ctx ends, reporting whether the wait completed.
func followSleep(ctx context.Context, d time.Duration) bool {
	select {
	case <-ctx.Done():
		return false
	case <-time.After(d):
		return true
	}
}

func cmdChatFollow() error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// conn is the live socket, swapped on each reconnect and read by the stdin
	// pump under mu so a forwarded message always lands on the current one.
	var mu sync.Mutex
	var conn *websocket.Conn

	go func() {
		r := bufio.NewReader(os.Stdin)
		for {
			line, err := r.ReadBytes('\n')
			if msg := bytes.TrimRight(line, "\r\n"); len(msg) > 0 {
				mu.Lock()
				c := conn
				mu.Unlock()
				if c != nil {
					_ = c.Write(ctx, websocket.MessageText, msg)
				}
			}
			if err != nil {
				cancel() // stdin closed: the sidebar is gone, so exit.
				return
			}
		}
	}()

	backoff := 500 * time.Millisecond
	for ctx.Err() == nil {
		dctx, dcancel := context.WithTimeout(ctx, 5*time.Second)
		c, _, err := websocket.Dial(dctx, chatWSURL(), nil)
		dcancel()
		if err != nil {
			followDead()
			if !followSleep(ctx, backoff) {
				return nil
			}
			backoff = followBackoff(backoff)
			continue
		}
		c.SetReadLimit(32 << 20)
		mu.Lock()
		conn = c
		mu.Unlock()
		backoff = 500 * time.Millisecond

		for {
			_, data, rerr := c.Read(ctx)
			if rerr != nil {
				break
			}
			_, _ = os.Stdout.Write(append(data, '\n'))
		}
		mu.Lock()
		conn = nil
		mu.Unlock()
		c.Close(websocket.StatusNormalClosure, "")
		if ctx.Err() != nil {
			return nil
		}
		followDead()
		if !followSleep(ctx, backoff) {
			return nil
		}
		backoff = followBackoff(backoff)
	}
	return nil
}
