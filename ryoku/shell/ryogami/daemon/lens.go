package main

import (
	"bufio"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const indexMagic = "SKWDSEM3"

var errNotIndex = errors.New("not a semantic index")

func dataHome() string {
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		return d
	}
	return filepath.Join(home(), ".local", "share")
}

func lensDataDir() string { return filepath.Join(dataHome(), "ryogami", "lens") }

func lensModelsDir() string { return filepath.Join(lensDataDir(), "models") }

func semanticRoots() []string {
	return []string{
		filepath.Join(lensModelsDir(), "semantic"),
		filepath.Join(dataHome(), "skwd-lens", "models", "semantic"),
		"/usr/share/ryogami/lens/models/semantic",
		"/usr/share/skwd-lens/models/semantic",
	}
}

func envPathAny(canonical, legacy string) string {
	if v := os.Getenv(canonical); v != "" {
		return v
	}
	return os.Getenv(legacy)
}

func lensHelper() string {
	if p := envPathAny("SKWD_LENS_BIN", "SKWD_SEMANTIC_BIN"); p != "" {
		if isExecutableFile(p) {
			return p
		}
		if !strings.ContainsRune(p, os.PathSeparator) {
			if lp, err := exec.LookPath(p); err == nil {
				return lp
			}
		}
		return ""
	}
	for _, name := range []string{"skwd-lens", "skwd-wall-semantic"} {
		if lp, err := exec.LookPath(name); err == nil {
			return lp
		}
	}
	return ""
}

func findRuntime(root string) string {
	for _, name := range []string{
		"runtime/libonnxruntime.so.1.27.0",
		"runtime/libonnxruntime.so",
		"runtime/libonnxruntime.dylib",
		"runtime/onnxruntime.dll",
	} {
		p := filepath.Join(root, filepath.FromSlash(name))
		if fileExists(p) {
			return p
		}
	}
	return ""
}

func findRuntimeNear(start string) string {
	dir := start
	for i := 0; i < 4 && dir != "" && dir != string(os.PathSeparator); i++ {
		if p := findRuntime(dir); p != "" {
			return p
		}
		dir = filepath.Dir(dir)
	}
	return ""
}

func lensRuntime(manifest string) string {
	if p := envPathAny("SKWD_LENS_ORT_DYLIB", "SKWD_SEMANTIC_ORT_DYLIB"); p != "" {
		return p
	}
	if manifest != "" {
		if p := findRuntimeNear(filepath.Dir(manifest)); p != "" {
			return p
		}
	}
	for _, root := range semanticRoots() {
		if p := findRuntime(root); p != "" {
			return p
		}
	}
	return ""
}

func (d *daemon) lensManifest() string {
	if p := envPathAny("SKWD_LENS_MANIFEST", "SKWD_SEMANTIC_MANIFEST"); p != "" {
		return p
	}
	if sel := strings.TrimSpace(d.settingString("semantic.manifest")); sel != "" {
		return sel
	}
	for _, root := range semanticRoots() {
		if m := filepath.Join(root, "semantic-pack.json"); fileExists(m) {
			return m
		}
	}
	return ""
}

func (d *daemon) indexProfile() string {
	if d.settingString("semantic.indexProfile") == "multiview" {
		return "multiview"
	}
	return "full"
}

// Must match skwd-lens's index file name so the query side finds a rebuilt index.
func cacheIndexName(model, profile string) string {
	const offset uint64 = 0xcbf29ce484222325
	const prime uint64 = 0x00000100000001b3
	hash := offset
	feed := func(b byte) {
		hash ^= uint64(b)
		hash *= prime
	}
	for i := range len(model) {
		feed(model[i])
	}
	feed(0xff)
	for i := range len(profile) {
		feed(profile[i])
	}
	return fmt.Sprintf("index-%016x.sidx", hash)
}

func manifestIdentity(manifest string) string {
	b, err := os.ReadFile(manifest)
	if err != nil {
		return ""
	}
	var m struct {
		ID      string `json:"id"`
		Version string `json:"version"`
	}
	if json.Unmarshal(b, &m) != nil || m.ID == "" || m.Version == "" {
		return ""
	}
	return m.ID + "@" + m.Version
}

func (d *daemon) lensIndexPath(manifest, profile string) string {
	if p := envPathAny("SKWD_LENS_INDEX", "SKWD_SEMANTIC_INDEX"); p != "" {
		return p
	}
	semDir := filepath.Join(d.config().cacheDir(), "semantic")
	custom := strings.TrimSpace(d.settingString("semantic.manifest")) != "" ||
		envPathAny("SKWD_LENS_MANIFEST", "SKWD_SEMANTIC_MANIFEST") != ""
	if !custom && profile == "full" {
		return filepath.Join(semDir, "index-siglip2.sidx")
	}
	identity := manifestIdentity(manifest)
	if identity == "" {
		identity = manifest
	}
	return filepath.Join(semDir, cacheIndexName(identity, profile))
}

type semanticPaths struct {
	helper    string
	manifest  string
	runtime   string
	index     string
	multiview bool
}

func (d *daemon) discoverSemanticPaths() (semanticPaths, bool) {
	helper := lensHelper()
	if helper == "" {
		return semanticPaths{}, false
	}
	manifest := d.lensManifest()
	if manifest == "" || !fileExists(manifest) {
		return semanticPaths{}, false
	}
	rt := lensRuntime(manifest)
	if rt == "" || !fileExists(rt) {
		return semanticPaths{}, false
	}
	profile := d.indexProfile()
	return semanticPaths{
		helper:    helper,
		manifest:  manifest,
		runtime:   rt,
		index:     d.lensIndexPath(manifest, profile),
		multiview: profile == "multiview",
	}, true
}

type indexHeader struct {
	dimensions  uint32
	model       string
	fingerprint uint64
	count       uint64
}

func lensReadU32(r io.Reader) (uint32, error) {
	var b [4]byte
	if _, err := io.ReadFull(r, b[:]); err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint32(b[:]), nil
}

func lensReadU64(r io.Reader) (uint64, error) {
	var b [8]byte
	if _, err := io.ReadFull(r, b[:]); err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint64(b[:]), nil
}

func readIndexHeader(r io.Reader) (indexHeader, error) {
	var magic [8]byte
	if _, err := io.ReadFull(r, magic[:]); err != nil {
		return indexHeader{}, err
	}
	if string(magic[:]) != indexMagic {
		return indexHeader{}, errNotIndex
	}
	dims, err := lensReadU32(r)
	if err != nil {
		return indexHeader{}, err
	}
	modelLen, err := lensReadU32(r)
	if err != nil {
		return indexHeader{}, err
	}
	if modelLen == 0 || modelLen > 4096 {
		return indexHeader{}, errNotIndex
	}
	model := make([]byte, modelLen)
	if _, err := io.ReadFull(r, model); err != nil {
		return indexHeader{}, err
	}
	fp, err := lensReadU64(r)
	if err != nil {
		return indexHeader{}, err
	}
	count, err := lensReadU64(r)
	if err != nil {
		return indexHeader{}, err
	}
	return indexHeader{dimensions: dims, model: string(model), fingerprint: fp, count: count}, nil
}

func readIndexModel(index string) string {
	f, err := os.Open(index)
	if err != nil {
		return ""
	}
	defer f.Close()
	h, err := readIndexHeader(bufio.NewReader(f))
	if err != nil {
		return ""
	}
	return h.model
}

// Multiview stores several views per key, so the status counts distinct keys.
func indexUniqueKeys(index string) int {
	f, err := os.Open(index)
	if err != nil {
		return 0
	}
	defer f.Close()
	r := bufio.NewReader(f)
	h, err := readIndexHeader(r)
	if err != nil {
		return 0
	}
	seen := map[string]struct{}{}
	skip := int64(h.dimensions) * 4
	for range h.count {
		keyLen, err := lensReadU32(r)
		if err != nil || keyLen > 1<<20 {
			break
		}
		key := make([]byte, keyLen)
		if _, err := io.ReadFull(r, key); err != nil {
			break
		}
		if _, err := lensReadU64(r); err != nil {
			break
		}
		if _, err := io.CopyN(io.Discard, r, skip); err != nil {
			break
		}
		seen[string(key)] = struct{}{}
	}
	return len(seen)
}

func indexModelMatches(paths semanticPaths) bool {
	want := manifestIdentity(paths.manifest)
	return want != "" && want == readIndexModel(paths.index)
}

func indexCurrent(paths semanticPaths, fingerprint uint64) bool {
	b, err := os.ReadFile(paths.index + ".fingerprint")
	if err != nil {
		return false
	}
	got, err := strconv.ParseUint(strings.TrimSpace(string(b)), 10, 64)
	if err != nil || got != fingerprint {
		return false
	}
	return indexModelMatches(paths)
}

type lensManager struct {
	d *daemon

	refresh chan struct{}

	buildMu     sync.Mutex
	building    bool
	cancelBuild context.CancelFunc

	svcMu sync.Mutex
	svc   *lensServe
	idle  *time.Timer
	gen   uint64
}

func newLensManager(d *daemon) *lensManager {
	return &lensManager{d: d, refresh: make(chan struct{}, 1)}
}

var (
	lensOnce sync.Once
	lensInst *lensManager
)

func (d *daemon) lens() *lensManager {
	lensOnce.Do(func() { lensInst = newLensManager(d) })
	return lensInst
}

func init() {
	registerAvailability("lens", func(d *daemon) bool {
		_, ok := d.discoverSemanticPaths()
		return ok
	})
	// The Lens component (skwd-lens plus its ONNX runtime) is present but a model pack may
	// not be; the settings model-import controls stay reachable so search can be set up.
	registerAvailability("lensHelper", func(d *daemon) bool {
		if lensHelper() == "" {
			return false
		}
		rt := lensRuntime(d.lensManifest())
		return rt != "" && fileExists(rt)
	})
	onStart(func(d *daemon) { d.lens().start() })
	watchSetting("semantic.", func(d *daemon, key string, _ interface{}) {
		d.lens().onSettingChanged(key)
	})
}
