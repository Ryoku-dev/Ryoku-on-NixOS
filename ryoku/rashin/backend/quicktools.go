package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// quicktools.go is the fast lane's toolset: a small set of READ-ONLY,
// Go-native tools that run in milliseconds, so a quick ask can look things up
// without spinning hermes's full Python agent. Anything heavier (image
// generation, a real browser, running skills, writing files) is not here on
// purpose: the model escalates those to the hermes session with the
// TOOLS_REQUIRED sentinel. Every tool is safe by construction, so no approval
// gate is needed on this path.

// quickToolSchemas is the OpenAI function-calling schema advertised to the
// model on the fast lane.
func quickToolSchemas() []map[string]any {
	strProp := func(desc string) map[string]any {
		return map[string]any{"type": "string", "description": desc}
	}
	fn := func(name, desc string, props map[string]any, required []string) map[string]any {
		return map[string]any{
			"type": "function",
			"function": map[string]any{
				"name":        name,
				"description": desc,
				"parameters": map[string]any{
					"type":       "object",
					"properties": props,
					"required":   required,
				},
			},
		}
	}
	return []map[string]any{
		fn("system_query", "Read live system state on this Ryoku machine.",
			map[string]any{"topic": map[string]any{
				"type":        "string",
				"enum":        []string{"packages", "updates", "service", "processes", "disk", "kernel", "gpu", "network"},
				"description": "what to look up",
			}, "arg": strProp("optional filter, e.g. a package or service name")},
			[]string{"topic"}),
		fn("read_file", "Read a text file in the Rashin vault or Ryoku configuration roots.",
			map[string]any{"path": strProp("absolute or ~ path")}, []string{"path"}),
		fn("list_dir", "List a directory in the Rashin vault or Ryoku configuration roots.",
			map[string]any{"path": strProp("absolute or ~ path")}, []string{"path"}),
		fn("search_code", "Search the Ryoku source with prowl (when indexed).",
			map[string]any{"query": strProp("free text or a symbol name")}, []string{"query"}),
		fn("fetch_url", "Fetch a public http(s) URL as text (readable content).",
			map[string]any{"url": strProp("an http or https URL")}, []string{"url"}),
	}
}

// execQuickTool runs one tool call and returns a compact text result. It never
// errors out the turn: a failure is returned as text the model can read.
func execQuickTool(ctx context.Context, name, argsJSON string) string {
	var a struct {
		Topic string `json:"topic"`
		Arg   string `json:"arg"`
		Path  string `json:"path"`
		Query string `json:"query"`
		URL   string `json:"url"`
	}
	_ = json.Unmarshal([]byte(argsJSON), &a)
	switch name {
	case "system_query":
		return toolSystemQuery(ctx, a.Topic, a.Arg)
	case "read_file":
		return toolReadFile(a.Path)
	case "list_dir":
		return toolListDir(a.Path)
	case "search_code":
		return toolSearchCode(a.Query)
	case "fetch_url":
		return toolFetchURL(ctx, a.URL)
	default:
		return "error: unknown tool " + name
	}
}

func runCapped(ctx context.Context, cap int, name string, args ...string) string {
	c, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	out, err := exec.CommandContext(c, name, args...).CombinedOutput()
	s := string(out)
	if len(s) > cap {
		s = s[:cap] + "\n...(truncated)"
	}
	if err != nil && strings.TrimSpace(s) == "" {
		return "error: " + err.Error()
	}
	return strings.TrimSpace(s)
}

func toolSystemQuery(ctx context.Context, topic, arg string) string {
	switch topic {
	case "packages":
		if arg != "" {
			return runCapped(ctx, 4096, "ryoku-host", "pkg", "version", arg)
		}
		return runCapped(ctx, 2048, "ryoku-host", "pkg", "count")
	case "updates":
		return runCapped(ctx, 4096, "ryoku", "status", "--json")
	case "service":
		if arg == "" {
			return "error: service topic needs a name in arg"
		}
		return runCapped(ctx, 4096, "systemctl", "status", "--no-pager", "--lines=5", arg)
	case "processes":
		return runCapped(ctx, 4096, "sh", "-c", "ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -16")
	case "disk":
		return runCapped(ctx, 2048, "df", "-h", "--output=source,size,used,avail,pcent,target", "/", "/home")
	case "kernel":
		return runCapped(ctx, 512, "uname", "-r")
	case "gpu":
		if _, err := exec.LookPath("ryoku-gpu"); err == nil {
			return runCapped(ctx, 2048, "ryoku-gpu", "status")
		}
		return runCapped(ctx, 2048, "sh", "-c", "lspci | grep -iE 'vga|3d'")
	case "network":
		return runCapped(ctx, 2048, "sh", "-c", "ip -brief addr 2>/dev/null | head -12")
	default:
		return "error: unknown topic " + topic
	}
}

func safeReadRoots() []string {
	return []string{
		VaultDir(),
		filepath.Join(home(), ".config"),
		filepath.Join(home(), ".local", "share", "ryoku"),
	}
}

func pathWithinRoot(p, root string) bool {
	return p == root || strings.HasPrefix(p, root+string(filepath.Separator))
}

func absoluteQuickPath(p string) (string, error) {
	p = strings.TrimSpace(p)
	if p == "" {
		return "", fmt.Errorf("path is empty")
	}
	return filepath.Abs(filepath.Clean(expandHome(p)))
}

func withinSafeRoot(p string, resolveRoots bool) bool {
	for _, root := range safeReadRoots() {
		root, err := absoluteQuickPath(root)
		if err != nil {
			continue
		}
		if resolveRoots {
			root, err = filepath.EvalSymlinks(root)
			if err != nil {
				continue
			}
		}
		if pathWithinRoot(p, root) {
			return true
		}
	}
	return false
}

func quickReadPath(path string) (string, error) {
	p, err := absoluteQuickPath(path)
	if err != nil {
		return "", err
	}
	if !withinSafeRoot(p, false) {
		return "", fmt.Errorf("reads are limited to the Rashin vault, ~/.config, and ~/.local/share/ryoku")
	}
	if marker, secret := roSecretPath(p); secret {
		return "", fmt.Errorf("refusing secret path (%s)", marker)
	}
	resolved, err := filepath.EvalSymlinks(p)
	if err != nil {
		return "", err
	}
	if !withinSafeRoot(resolved, true) {
		return "", fmt.Errorf("resolved path leaves the allowed roots")
	}
	if marker, secret := roSecretPath(resolved); secret {
		return "", fmt.Errorf("refusing secret path (%s)", marker)
	}
	return resolved, nil
}

func toolReadFile(path string) string {
	p, err := quickReadPath(path)
	if err != nil {
		return "error: " + err.Error()
	}
	fi, err := os.Stat(p)
	if err != nil {
		return "error: " + err.Error()
	}
	if fi.IsDir() {
		return "error: that is a directory, use list_dir"
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return "error: " + err.Error()
	}
	if len(b) > 32*1024 {
		b = b[:32*1024]
		return string(b) + "\n...(truncated at 32KB)"
	}
	return string(b)
}

func toolListDir(path string) string {
	p, err := quickReadPath(path)
	if err != nil {
		return "error: " + err.Error()
	}
	entries, err := os.ReadDir(p)
	if err != nil {
		return "error: " + err.Error()
	}
	var b strings.Builder
	for i, e := range entries {
		if i >= 200 {
			fmt.Fprintf(&b, "...(%d more)\n", len(entries)-200)
			break
		}
		name := e.Name()
		if e.IsDir() {
			name += "/"
		}
		b.WriteString(name + "\n")
	}
	return strings.TrimSpace(b.String())
}

func toolSearchCode(query string) string {
	hits := ProwlSearch(query)
	if len(hits) == 0 {
		if _, ok := findProwl(); !ok {
			return "prowl is not installed; code search is unavailable"
		}
		return "no matches"
	}
	var b strings.Builder
	for i, h := range hits {
		if i >= 12 {
			break
		}
		fmt.Fprintf(&b, "%s:%d  %s\n", h.File, h.Line, h.Text)
	}
	return strings.TrimSpace(b.String())
}

var quickFetchClient = func() *http.Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.DialContext = quickDialContext
	return &http.Client{Transport: transport, CheckRedirect: quickCheckRedirect}
}()

// toolFetchURL reads a public URL as text, refusing loopback and private
// ranges on every hop so redirects and DNS changes cannot reach local services.
func toolFetchURL(ctx context.Context, raw string) string {
	raw = strings.TrimSpace(raw)
	if err := validateQuickURL(raw); err != nil {
		return "error: " + err.Error()
	}
	c, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(c, http.MethodGet, raw, nil)
	if err != nil {
		return "error: " + err.Error()
	}
	req.Header.Set("User-Agent", "ryoku-rashin/quick")
	resp, err := quickFetchClient.Do(req)
	if err != nil {
		return "error: " + err.Error()
	}
	defer resp.Body.Close()
	buf := make([]byte, 24*1024)
	n, _ := resp.Body.Read(buf)
	text := stripTags(string(buf[:n]))
	if len(text) > 8*1024 {
		text = text[:8*1024] + "\n...(truncated)"
	}
	return fmt.Sprintf("[%d] %s\n%s", resp.StatusCode, raw, strings.TrimSpace(text))
}

func blockedQuickIP(ip net.IP) bool {
	return ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified()
}

func validateQuickURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return fmt.Errorf("invalid URL: %w", err)
	}
	if !strings.EqualFold(u.Scheme, "http") && !strings.EqualFold(u.Scheme, "https") {
		return fmt.Errorf("only http(s) URLs")
	}
	host := u.Hostname()
	if host == "" {
		return fmt.Errorf("URL has no host")
	}
	if strings.EqualFold(strings.TrimSuffix(host, "."), "localhost") {
		return fmt.Errorf("refusing loopback or private-network URLs")
	}
	ipHost := host
	if before, _, found := strings.Cut(host, "%"); found {
		ipHost = before
	}
	if ip := net.ParseIP(ipHost); ip != nil {
		if blockedQuickIP(ip) {
			return fmt.Errorf("refusing loopback or private-network URLs")
		}
		return nil
	}
	ips, err := net.LookupIP(host)
	if err != nil {
		return fmt.Errorf("cannot resolve URL host: %w", err)
	}
	for _, ip := range ips {
		if blockedQuickIP(ip) {
			return fmt.Errorf("refusing loopback or private-network URLs")
		}
	}
	if len(ips) == 0 {
		return fmt.Errorf("URL host has no addresses")
	}
	return nil
}

func isPrivateURL(raw string) bool {
	return validateQuickURL(raw) != nil
}

func quickCheckRedirect(req *http.Request, via []*http.Request) error {
	if len(via) > 3 {
		return fmt.Errorf("stopped after 3 redirects")
	}
	if err := validateQuickURL(req.URL.String()); err != nil {
		return fmt.Errorf("refusing redirect: %w", err)
	}
	return nil
}

func quickDialContext(ctx context.Context, network, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, err
	}
	for _, resolved := range ips {
		if blockedQuickIP(resolved.IP) {
			return nil, fmt.Errorf("refusing loopback or private-network address")
		}
	}
	var dialer net.Dialer
	var lastErr error
	for _, resolved := range ips {
		conn, dialErr := dialer.DialContext(ctx, network, net.JoinHostPort(resolved.IP.String(), port))
		if dialErr == nil {
			return conn, nil
		}
		lastErr = dialErr
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return nil, fmt.Errorf("URL host has no addresses")
}

// stripTags is a crude html-to-text: drop tags and script/style bodies so a
// fetched page reads as content, not markup.
func stripTags(s string) string {
	for _, tag := range []string{"script", "style"} {
		for {
			lo := strings.Index(strings.ToLower(s), "<"+tag)
			if lo < 0 {
				break
			}
			hi := strings.Index(strings.ToLower(s[lo:]), "</"+tag+">")
			if hi < 0 {
				s = s[:lo]
				break
			}
			s = s[:lo] + s[lo+hi+len(tag)+3:]
		}
	}
	var b strings.Builder
	depth := 0
	for _, r := range s {
		switch r {
		case '<':
			depth++
		case '>':
			if depth > 0 {
				depth--
			}
		default:
			if depth == 0 {
				b.WriteRune(r)
			}
		}
	}
	lines := strings.Split(b.String(), "\n")
	var keep []string
	for _, ln := range lines {
		if t := strings.TrimSpace(ln); t != "" {
			keep = append(keep, t)
		}
	}
	return strings.Join(keep, "\n")
}
