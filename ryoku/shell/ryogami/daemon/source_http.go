package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"time"
)

// Several hosts answer a default Go agent with a challenge page, so requests carry a browser UA.
const userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

const (
	maxDownloadBytes     = 500 * 1024 * 1024
	previewMaxEncoded    = 24 * 1024 * 1024
	maxTextBytes         = 32 * 1024 * 1024
	maxRedirects         = 5
	dialTimeout          = 10 * time.Second
	responseHeadTimeout  = 30 * time.Second
	apiRequestTimeout    = 45 * time.Second
	searchFetchTimeout   = 20 * time.Second
	downloadFetchTimeout = 2 * time.Hour
	thumbFetchTimeout    = 20 * time.Second
	previewFetchTimeout  = 60 * time.Second
	sniffHeadLen         = 16
	thumbFetchConcurrent = 6
)

// noRedirect hands back each hop so a guarded fetch re-checks the allowlist before every jump.
type httpStack struct {
	client     *http.Client
	noRedirect *http.Client
}

func newHTTPStack() *httpStack {
	transport := &http.Transport{
		DialContext:           (&net.Dialer{Timeout: dialTimeout, KeepAlive: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout:   dialTimeout,
		ResponseHeaderTimeout: responseHeadTimeout,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          32,
		MaxIdleConnsPerHost:   8,
		IdleConnTimeout:       90 * time.Second,
	}
	return &httpStack{
		client: &http.Client{Transport: transport, Timeout: apiRequestTimeout},
		noRedirect: &http.Client{
			Transport:     transport,
			CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
		},
	}
}

// The SSRF floor under every per-source allowlist: no private, loopback or link-local hosts.
func requirePublic(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return err
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return fmt.Errorf("unsupported url scheme %q", u.Scheme)
	}
	host := u.Hostname()
	if host == "" {
		return fmt.Errorf("url has no host")
	}
	if ip := net.ParseIP(host); ip != nil {
		if !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() ||
			ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() {
			return fmt.Errorf("blocked non-public host: %s", host)
		}
	}
	return nil
}

func wallhavenHost(host string) bool {
	return host == "wallhaven.cc" || host == "whvn.cc" ||
		strings.HasSuffix(host, ".wallhaven.cc") || strings.HasSuffix(host, ".whvn.cc")
}

func githubContentHost(host string) bool {
	return host == "raw.githubusercontent.com" ||
		host == "media.githubusercontent.com" ||
		host == "objects.githubusercontent.com" ||
		strings.HasSuffix(host, ".githubusercontent.com")
}

// Per-source allowlist so a poisoned result cannot point a download at an arbitrary host.
func hostAllowed(source, host string) bool {
	host = strings.ToLower(host)
	switch source {
	case "wallhaven", "wallhaven-full":
		return wallhavenHost(host)
	case "unsplash":
		return host == "unsplash.com" || strings.HasSuffix(host, ".unsplash.com")
	case "pexels":
		return host == "pexels.com" || strings.HasSuffix(host, ".pexels.com")
	case "youtube":
		return strings.HasSuffix(host, ".ytimg.com") || strings.HasSuffix(host, ".ggpht.com")
	case "bing":
		return host == "bing.com" || strings.HasSuffix(host, ".bing.com")
	case "steam":
		return host == "steamstatic.com" || strings.HasSuffix(host, ".steamstatic.com") ||
			host == "steamusercontent.com" || strings.HasSuffix(host, ".steamusercontent.com") ||
			strings.HasSuffix(host, ".akamaihd.net")
	case "moewalls":
		return host == "moewalls.com" || strings.HasSuffix(host, ".moewalls.com") || host == "wsrv.nl"
	case "motionbgs":
		return host == "motionbgs.com" || strings.HasSuffix(host, ".motionbgs.com")
	case "ryostore":
		return githubContentHost(host) || host == "wsrv.nl"
	case "repos":
		return host == "api.github.com" || githubContentHost(host) || host == "wsrv.nl"
	}
	return false
}

func requireSource(source, raw string) error {
	if err := requirePublic(raw); err != nil {
		return err
	}
	u, err := url.Parse(raw)
	if err != nil {
		return err
	}
	if !hostAllowed(source, u.Hostname()) {
		return fmt.Errorf("blocked non-%s host: %s", source, u.Hostname())
	}
	return nil
}

func resolveRedirect(base, loc string) (string, error) {
	b, err := url.Parse(base)
	if err != nil {
		return "", err
	}
	l, err := url.Parse(loc)
	if err != nil {
		return "", err
	}
	return b.ResolveReference(l).String(), nil
}

func (s *sources) guardedGet(ctx context.Context, rawURL string, policy func(string) error) (*http.Response, error) {
	current := rawURL
	for hop := 0; hop <= maxRedirects; hop++ {
		if err := policy(current); err != nil {
			return nil, err
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, current, nil)
		if err != nil {
			return nil, err
		}
		req.Header.Set("User-Agent", userAgent)
		resp, err := s.http.noRedirect.Do(req)
		if err != nil {
			return nil, err
		}
		if resp.StatusCode >= 300 && resp.StatusCode < 400 {
			loc := resp.Header.Get("Location")
			resp.Body.Close()
			if loc == "" {
				return nil, fmt.Errorf("redirect without Location")
			}
			next, err := resolveRedirect(current, loc)
			if err != nil {
				return nil, fmt.Errorf("blocked bad redirect location")
			}
			current = next
			continue
		}
		return resp, nil
	}
	return nil, fmt.Errorf("too many redirects")
}

func (s *sources) readText(ctx context.Context, method, rawURL string, header http.Header, provider string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, method, rawURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", userAgent)
	for k, vs := range header {
		for _, v := range vs {
			req.Header.Add(k, v)
		}
	}
	resp, err := s.http.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("%s network error: %w", provider, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("%s request failed: HTTP %d", provider, resp.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, maxTextBytes))
	if err != nil {
		return "", fmt.Errorf("%s network error: %w", provider, err)
	}
	return string(b), nil
}

func declaredLength(resp *http.Response) uint64 {
	if resp.ContentLength > 0 {
		return uint64(resp.ContentLength)
	}
	return 0
}

// Fails before writing the byte past max, so a lying Content-Length cannot fill the disk.
func copyBounded(reader io.Reader, writer io.Writer, max uint64) (uint64, error) {
	buf := make([]byte, 64*1024)
	var copied uint64
	for {
		room := max - copied
		want := uint64(len(buf))
		if room+1 < want {
			want = room + 1
		}
		n, err := reader.Read(buf[:want])
		if n > 0 {
			next := copied + uint64(n)
			if next > max {
				return copied, fmt.Errorf("remote body exceeds %d byte limit", max)
			}
			if _, werr := writer.Write(buf[:n]); werr != nil {
				return copied, werr
			}
			copied = next
		}
		if err == io.EOF {
			return copied, nil
		}
		if err != nil {
			return copied, err
		}
	}
}

// httpStatusError keeps the status so a source can say why a request was refused.
type httpStatusError struct{ code int }

func (e httpStatusError) Error() string { return fmt.Sprintf("request failed: HTTP %d", e.code) }

// Trusted provider endpoints only, so no SSRF allowlist here.
func (s *sources) getBytes(ctx context.Context, method, rawURL string, header http.Header, body io.Reader, sizeCap int64) ([]byte, error) {
	if sizeCap <= 0 {
		sizeCap = maxTextBytes
	}
	req, err := http.NewRequestWithContext(ctx, method, rawURL, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)
	for k, vs := range header {
		for _, v := range vs {
			req.Header.Add(k, v)
		}
	}
	resp, err := s.http.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, httpStatusError{resp.StatusCode}
	}
	return io.ReadAll(io.LimitReader(resp.Body, sizeCap))
}

func (d *daemon) httpGetBytesContext(ctx context.Context, rawURL string, header http.Header, sizeCap int64) ([]byte, error) {
	return d.sources.getBytes(ctx, http.MethodGet, rawURL, header, nil, sizeCap)
}

func (d *daemon) httpPostFormContext(ctx context.Context, rawURL string, form url.Values, sizeCap int64) ([]byte, error) {
	h := http.Header{"Content-Type": []string{"application/x-www-form-urlencoded"}}
	return d.sources.getBytes(ctx, http.MethodPost, rawURL, h, strings.NewReader(form.Encode()), sizeCap)
}

var partSequence atomic.Uint64

// A unique .part name so a half-written download never collides with the file or shows in a scan.
func partialFile(dest string) (*os.File, string, error) {
	dir := filepath.Dir(dest)
	name := filepath.Base(dest)
	for attempt := 0; attempt < 8; attempt++ {
		serial := partSequence.Add(1)
		path := filepath.Join(dir, fmt.Sprintf(".%s.%d.%d.part", name, os.Getpid(), serial))
		f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if err == nil {
			return f, path, nil
		}
		if !os.IsExist(err) {
			return nil, "", err
		}
	}
	return nil, "", fmt.Errorf("could not allocate a unique partial file beside %s", dest)
}

func extFromURL(rawURL string) string {
	clean := rawURL
	if i := strings.IndexAny(clean, "?#"); i >= 0 {
		clean = clean[:i]
	}
	if i := strings.LastIndex(clean, "/"); i >= 0 {
		clean = clean[i+1:]
	}
	dot := strings.LastIndex(clean, ".")
	if dot < 0 {
		return "jpg"
	}
	ext := clean[dot+1:]
	if len(ext) == 0 || len(ext) > 5 {
		return "jpg"
	}
	for _, ch := range ext {
		if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
			return "jpg"
		}
	}
	return ext
}

func safeSeg(segment string) string {
	return strings.NewReplacer("/", "_", "\\", "_", "\x00", "_").Replace(segment)
}

type sniffKind int

const (
	sniffUnknown sniffKind = iota
	sniffImage
	sniffVideo
)

func (k sniffKind) String() string {
	switch k {
	case sniffImage:
		return "image"
	case sniffVideo:
		return "video"
	default:
		return "unknown"
	}
}

func detectKind(head []byte) sniffKind {
	if len(head) >= 12 {
		if string(head[4:8]) == "ftyp" {
			switch string(head[8:12]) {
			case "avif", "avis", "heic", "heix", "mif1":
				return sniffImage
			default:
				return sniffVideo
			}
		}
		if string(head[0:4]) == "RIFF" {
			switch {
			case string(head[8:12]) == "WEBP":
				return sniffImage
			case string(head[8:11]) == "AVI":
				return sniffVideo
			default:
				return sniffUnknown
			}
		}
	}
	switch {
	case hasPrefix(head, []byte{0xFF, 0xD8, 0xFF}),
		hasPrefix(head, []byte{0x89, 'P', 'N', 'G'}),
		hasPrefix(head, []byte("GIF87a")),
		hasPrefix(head, []byte("GIF89a")),
		hasPrefix(head, []byte("BM")):
		return sniffImage
	case hasPrefix(head, []byte{0x1A, 0x45, 0xDF, 0xA3}):
		return sniffVideo
	}
	return sniffUnknown
}

func hasPrefix(data, prefix []byte) bool {
	return len(data) >= len(prefix) && string(data[:len(prefix)]) == string(prefix)
}

func describeHead(head []byte) string {
	if len(head) == 0 {
		return "an empty file"
	}
	trimmed := strings.TrimLeft(string(head), " \t\r\n")
	switch {
	case strings.HasPrefix(trimmed, "<"):
		return "an HTML/text page"
	case strings.HasPrefix(trimmed, "{"), strings.HasPrefix(trimmed, "["):
		return "a JSON document"
	}
	n := len(head)
	if n > 8 {
		n = 8
	}
	parts := make([]string, 0, n)
	for _, b := range head[:n] {
		parts = append(parts, fmt.Sprintf("%02x", b))
	}
	return "unrecognised data (" + strings.Join(parts, " ") + ")"
}

func verifyKind(head []byte, want sniffKind) error {
	switch got := detectKind(head); got {
	case want:
		return nil
	case sniffUnknown:
		return fmt.Errorf("expected %s data but the server sent %s", want, describeHead(head))
	default:
		return fmt.Errorf("expected %s data but the server sent a %s", want, got)
	}
}

// Rejects an error page saved with an image extension before it reaches the library.
func checkFile(path string, want sniffKind) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	head := make([]byte, sniffHeadLen)
	n, err := io.ReadFull(f, head)
	if err != nil && err != io.ErrUnexpectedEOF && err != io.EOF {
		return err
	}
	return verifyKind(head[:n], want)
}
