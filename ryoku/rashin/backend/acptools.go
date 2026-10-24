package main

import (
	"encoding/json"
	"strings"
)

// ToolDiff is one file edit a tool call proposes or made.
type ToolDiff struct {
	Path string `json:"path"`
	Old  string `json:"old,omitempty"`
	New  string `json:"new"`
}

// toolView is what a surface needs to show a tool call: a partial update,
// where an empty field means "unchanged since the last frame for this id".
type toolView struct {
	ID     string
	Title  string
	Kind   string
	Status string
	Input  string
	Output string
	Diffs  []ToolDiff
}

// Output and diffs ride every frame for a tool and sit in the join replay, so
// they are capped: enough to preview, never a megabyte log per update.
const (
	toolOutputCap = 6000
	toolDiffCap   = 4000
	toolInputCap  = 400
)

// acpToolCall is ACP's ToolCall / ToolCallUpdate; request_permission carries
// the same shape under toolCall.
type acpToolCall struct {
	ToolCallID string          `json:"toolCallId"`
	Title      string          `json:"title"`
	Kind       string          `json:"kind"`
	Status     string          `json:"status"`
	RawInput   json.RawMessage `json:"rawInput"`
	RawOutput  json.RawMessage `json:"rawOutput"`
	Content    json.RawMessage `json:"content"`
	Locations  []struct {
		Path string `json:"path"`
	} `json:"locations"`
}

type acpToolContent struct {
	Type    string `json:"type"`
	Content struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	Path    string  `json:"path"`
	OldText *string `json:"oldText"`
	NewText string  `json:"newText"`
}

func (t acpToolCall) display() toolView {
	out := toolView{
		ID:     t.ToolCallID,
		Title:  t.Title,
		Kind:   t.Kind,
		Status: t.Status,
		Input:  toolInputSummary(t.RawInput),
	}
	if out.Input == "" && len(t.Locations) > 0 {
		out.Input = t.Locations[0].Path
	}
	out.Input = clipRunes(strings.Join(strings.Fields(out.Input), " "), toolInputCap)

	var blocks []acpToolContent
	_ = json.Unmarshal(t.Content, &blocks)
	var texts []string
	for _, b := range blocks {
		switch b.Type {
		case "diff":
			d := ToolDiff{Path: b.Path, New: clipRunes(b.NewText, toolDiffCap)}
			if b.OldText != nil {
				d.Old = clipRunes(*b.OldText, toolDiffCap)
			}
			out.Diffs = append(out.Diffs, d)
		case "content":
			if b.Content.Type == "text" && b.Content.Text != "" {
				texts = append(texts, b.Content.Text)
			}
		}
	}
	// rawOutput is the tool's own result when the agent sends one; the content
	// blocks are the display copy, which some agents open with an echo of the
	// command ("$ uname -r"), so they are the fallback.
	output := rawOutputText(t.RawOutput)
	if output == "" {
		output = strings.Join(dropCommandEcho(texts, out.Input), "\n")
	}
	out.Output = clipRunes(strings.TrimRight(output, "\n"), toolOutputCap)
	return out
}

// toolInputSummary picks the one line that says what a call acts on: the
// command it runs, the file it touches, the pattern or URL it looks up.
func toolInputSummary(raw json.RawMessage) string {
	var in map[string]json.RawMessage
	if json.Unmarshal(raw, &in) != nil {
		return ""
	}
	for _, k := range []string{"command", "cmd", "file_path", "filePath", "path", "pattern", "query", "url", "paths"} {
		v, ok := in[k]
		if !ok {
			continue
		}
		var s string
		if json.Unmarshal(v, &s) == nil && s != "" {
			return s
		}
		var list []string
		if json.Unmarshal(v, &list) == nil && len(list) > 0 {
			return strings.Join(list, " ")
		}
	}
	return ""
}

// rawOutputText reads a rawOutput that is a string or carries MCP-style text
// content; anything else (structured details) is left to the content blocks.
func rawOutputText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var s string
	if json.Unmarshal(raw, &s) == nil {
		return s
	}
	var obj struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
		Output string `json:"output"`
		Stdout string `json:"stdout"`
	}
	if json.Unmarshal(raw, &obj) != nil {
		return ""
	}
	var parts []string
	for _, c := range obj.Content {
		if c.Type == "text" && c.Text != "" {
			parts = append(parts, c.Text)
		}
	}
	if len(parts) > 0 {
		return strings.Join(parts, "\n")
	}
	if obj.Output != "" {
		return obj.Output
	}
	return obj.Stdout
}

func dropCommandEcho(texts []string, input string) []string {
	if len(texts) > 0 && input != "" && strings.TrimSpace(texts[0]) == "$ "+input {
		return texts[1:]
	}
	return texts
}
