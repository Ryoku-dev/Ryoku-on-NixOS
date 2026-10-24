package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

func (d *daemon) generateBugReport() (string, error) {
	dir := filepath.Join(d.config().cacheDir(), "reports")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	stamp := time.Now().Format("20060102-150405")
	path := filepath.Join(dir, stamp+".tar.gz")

	f, err := os.Create(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)

	add := func(name string, data []byte) {
		hdr := &tar.Header{Name: "report/" + name, Mode: 0o644, Size: int64(len(data)), ModTime: time.Now()}
		if tw.WriteHeader(hdr) == nil {
			_, _ = tw.Write(data)
		}
	}

	add("version.txt", []byte(fmt.Sprintf("ryogami-daemon %s\ngo %s\n%s/%s\n",
		daemonVersion, runtime.Version(), runtime.GOOS, runtime.GOARCH)))
	add("system.txt", systemInfo())
	add("environment.txt", redactedEnv())
	add("wm-caps.json", wmCapsJSON())

	for _, c := range []struct{ name, path string }{
		{"config/ryogami.json", configPath()},
		{"config/shell.json", filepath.Join(ryokuConfigDir(), "shell.json")},
		{"config/ryogami-wall.json", filepath.Join(ryogamiWallConfigDir(), "config.json")},
	} {
		if data, ok := redactedConfig(c.path); ok {
			add(c.name, data)
		}
	}

	for _, label := range []string{"picker", "video", "paper"} {
		if lp := managedLogPath(label); lp != "" {
			if data, err := os.ReadFile(lp); err == nil {
				add("logs/"+label+".log", data)
			}
		}
	}

	if err := tw.Close(); err != nil {
		return "", err
	}
	if err := gz.Close(); err != nil {
		return "", err
	}
	return path, nil
}

func systemInfo() []byte {
	var b bytes.Buffer
	for _, p := range []string{"/etc/os-release", "/proc/version"} {
		if data, err := os.ReadFile(p); err == nil {
			fmt.Fprintf(&b, "== %s ==\n%s\n", p, strings.TrimSpace(string(data)))
		}
	}
	return b.Bytes()
}

func wmCapsJSON() []byte {
	caps, err := wmClient.Caps()
	if err != nil {
		return []byte(fmt.Sprintf("{\"error\":%q}\n", err.Error()))
	}
	b, err := json.MarshalIndent(caps, "", "  ")
	if err != nil {
		return []byte("{}\n")
	}
	return b
}

func redactedEnv() []byte {
	env := os.Environ()
	lines := make([]string, 0, len(env))
	for _, kv := range env {
		if i := strings.IndexByte(kv, '='); i >= 0 && isSecretKey(kv[:i]) {
			lines = append(lines, kv[:i]+"=<redacted>")
			continue
		}
		lines = append(lines, kv)
	}
	return []byte(strings.Join(lines, "\n") + "\n")
}

// An unparseable file is left out rather than shipped raw, so it cannot leak a secret.
func redactedConfig(path string) ([]byte, bool) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}
	var v interface{}
	if json.Unmarshal(raw, &v) != nil {
		return []byte("(omitted: not valid JSON)\n"), true
	}
	out, err := json.MarshalIndent(redactSecrets(v), "", "  ")
	if err != nil {
		return nil, false
	}
	return out, true
}

func redactSecrets(v interface{}) interface{} {
	switch t := v.(type) {
	case map[string]interface{}:
		out := make(map[string]interface{}, len(t))
		for k, val := range t {
			if _, isStr := val.(string); isStr && isSecretKey(k) {
				out[k] = "<redacted>"
				continue
			}
			out[k] = redactSecrets(val)
		}
		return out
	case []interface{}:
		for i := range t {
			t[i] = redactSecrets(t[i])
		}
		return t
	}
	return v
}

func isSecretKey(k string) bool {
	l := strings.ToLower(k)
	for _, s := range []string{"apikey", "accesskey", "token", "secret", "password", "passwd", "credential"} {
		if strings.Contains(l, s) {
			return true
		}
	}
	return false
}

func init() {
	registerAction("GenerateBugReport", func(d *daemon, _ map[string]interface{}) (interface{}, error) {
		path, err := d.generateBugReport()
		if err != nil {
			return nil, err
		}
		return map[string]interface{}{"path": path}, nil
	})
}
