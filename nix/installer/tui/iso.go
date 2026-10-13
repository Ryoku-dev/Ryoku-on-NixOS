package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

const minISODiskBytes = int64(16 * 1024 * 1024 * 1024)
const dryRunDiskPath = "/dev/vda"

type isoStep struct {
	key   string
	title string
	desc  string
}

var isoFlow = []isoStep{
	{key: "network", title: "Network", desc: "Ryoku verifies HTTPS access to the Nix binary cache before installation."},
	{key: "disk", title: "Installation disk", desc: "Choose the whole disk Ryoku will erase and partition."},
	{key: "filesystem", title: "Filesystem", desc: "Choose the filesystem for the new NixOS root."},
	{key: "hostname", title: "Hostname", desc: "Name this machine on your local network."},
	{key: "username", title: "Username", desc: "Create the primary Ryoku user."},
	{key: "password", title: "Password", desc: "The plaintext password stays inside this process. Only its yescrypt hash reaches the backend."},
	{key: "timezone", title: "Timezone", desc: "Use an IANA timezone such as Europe/London or UTC."},
	{key: "locale", title: "Locale", desc: "Choose the system locale, for example en_GB.UTF-8."},
	{key: "keyboard", title: "Keyboard", desc: "Choose the XKB keyboard layout, for example gb or us."},
	{key: "kernel", title: "Kernel", desc: "Choose a kernel policy from the ISO's pinned nixpkgs revision."},
	{key: "compositor", title: "Window manager", desc: "Choose the Ryoku compositor selected on first boot."},
	{key: "browser", title: "Web browser", desc: "Choose the declarative browser role."},
	{key: "shell", title: "Interactive shell", desc: "Choose the user's interactive shell."},
	{key: "apps", title: "Apps & tools", desc: "Space toggles optional software. Required desktop contracts remain installed."},
	{key: "configuration", title: "Configuration", desc: "Use Ryoku's generated configuration or import an existing NixOS flake."},
	{key: "import-path", title: "Import flake", desc: "Advanced mode: enter the directory containing the existing flake.nix."},
	{key: "import-host", title: "Import host", desc: "Optional when the imported flake exposes exactly one nixosConfiguration."},
	{key: "review", title: "Review", desc: "Nothing has been written yet. Check every destructive and declarative choice."},
	{key: "confirm", title: "Final confirmation", desc: "Type the exact target disk path. This is the final destructive gate."},
}

type isoDisk struct {
	Path  string
	Model string
	Size  int64
}

type isoModel struct {
	w, h int
	opts options

	idx       int
	cursor    int
	appCursor int
	appOffset int

	picks map[string]string
	keep  map[string]bool

	disks         []isoDisk
	diskLoading   bool
	syntheticDisk bool
	netChecked    bool
	netOnline     bool
	busy          bool
	status        string
	err           error

	text          map[string]string
	passwordField int
	passwordHash  string

	installing bool
	installAt  int
	installLog []string
	istream    *isoInstallStream
	done       bool
}

type isoNetworkMsg struct {
	online bool
	err    error
}

type isoNetworkConfiguredMsg struct{ err error }
type isoDisksMsg struct {
	disks []isoDisk
	err   error
}
type isoPasswordHashMsg struct {
	hash string
	err  error
}
type isoInstallLineMsg string
type isoInstallStepMsg int
type isoInstallDoneMsg struct{ err error }

type isoInstallStream struct {
	ch       chan tea.Msg
	cmd      *exec.Cmd
	procDone chan struct{}
}

func (s *isoInstallStream) wait() tea.Cmd { return func() tea.Msg { return <-s.ch } }

func (s *isoInstallStream) kill() {
	if s == nil || s.cmd == nil || s.cmd.Process == nil {
		return
	}
	if err := syscall.Kill(-s.cmd.Process.Pid, syscall.SIGTERM); err != nil {
		_ = s.cmd.Process.Signal(syscall.SIGTERM)
	}
	if s.procDone != nil {
		select {
		case <-s.procDone:
			return
		case <-time.After(3 * time.Second):
		}
	}
	_ = syscall.Kill(-s.cmd.Process.Pid, syscall.SIGKILL)
}

func newISOModel(opts options) isoModel {
	keep := map[string]bool{}
	for _, app := range optionalApps() {
		keep[app.ID] = true
	}
	return isoModel{
		opts: opts,
		picks: map[string]string{
			"filesystem":    "ext4",
			"kernel":        "default",
			"compositor":    "hyprland",
			"browser":       "chromium",
			"shell":         "fish",
			"configuration": "ryoku",
		},
		keep: keep,
		text: map[string]string{
			"hostname":     "ryoku",
			"username":     "ryoku",
			"password":     "",
			"confirm":      "",
			"timezone":     "UTC",
			"locale":       "en_US.UTF-8",
			"keyboard":     "us",
			"import-path":  "",
			"import-host":  "",
			"disk-confirm": "",
		},
	}
}

func (m isoModel) Init() tea.Cmd {
	return tea.Batch(isoCheckNetworkCmd(), isoLoadDisksCmd())
}

func isoCheckNetworkCmd() tea.Cmd {
	return func() tea.Msg {
		cmd := exec.Command("curl", "-fsS", "--connect-timeout", "3", "--max-time", "5", "https://cache.nixos.org/nix-cache-info")
		if err := cmd.Run(); err != nil {
			return isoNetworkMsg{online: false, err: err}
		}
		return isoNetworkMsg{online: true}
	}
}

func isoConfigureNetworkCmd() tea.Cmd {
	return tea.ExecProcess(exec.Command("nmtui-connect"), func(err error) tea.Msg {
		return isoNetworkConfiguredMsg{err: err}
	})
}

type lsblkDisk struct {
	Path  string          `json:"path"`
	Size  json.RawMessage `json:"size"`
	Model string          `json:"model"`
	Type  string          `json:"type"`
	RO    json.RawMessage `json:"ro"`
}

type lsblkRoot struct {
	Blockdevices []lsblkDisk `json:"blockdevices"`
}

func parseJSONInt(raw json.RawMessage) int64 {
	var n int64
	if err := json.Unmarshal(raw, &n); err == nil {
		return n
	}
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		n, _ = strconv.ParseInt(s, 10, 64)
	}
	return n
}

func parseJSONBool(raw json.RawMessage) bool {
	var b bool
	if err := json.Unmarshal(raw, &b); err == nil {
		return b
	}
	var n int
	if err := json.Unmarshal(raw, &n); err == nil {
		return n != 0
	}
	return false
}

func canonicalWholeDisk(dev string) string {
	dev = strings.TrimSpace(dev)
	if !strings.HasPrefix(dev, "/dev/") {
		return ""
	}
	typeOut, err := exec.Command("lsblk", "-dnro", "TYPE", dev).Output()
	if err != nil {
		return ""
	}
	if strings.TrimSpace(string(typeOut)) == "disk" {
		if p, err := filepath.EvalSymlinks(dev); err == nil {
			return p
		}
		return dev
	}
	parent, err := exec.Command("lsblk", "-dnro", "PKNAME", dev).Output()
	if err != nil || strings.TrimSpace(string(parent)) == "" {
		return ""
	}
	return "/dev/" + strings.TrimSpace(string(parent))
}

func detectLiveDisk() string {
	for _, mountpoint := range []string{"/iso", "/nix/.ro-store", "/run/rootfsbase", "/"} {
		out, err := exec.Command("findmnt", "-nro", "SOURCE", mountpoint).Output()
		if err != nil {
			continue
		}
		if disk := canonicalWholeDisk(strings.TrimSpace(string(out))); disk != "" {
			return disk
		}
	}
	return ""
}

func isoLoadDisksCmd() tea.Cmd {
	return func() tea.Msg {
		out, err := exec.Command("lsblk", "-J", "-b", "-d", "-o", "PATH,SIZE,MODEL,TYPE,RO").Output()
		if err != nil {
			return isoDisksMsg{err: err}
		}
		var root lsblkRoot
		if err := json.Unmarshal(out, &root); err != nil {
			return isoDisksMsg{err: err}
		}
		live := detectLiveDisk()
		var disks []isoDisk
		for _, d := range root.Blockdevices {
			size := parseJSONInt(d.Size)
			if d.Type != "disk" || parseJSONBool(d.RO) || size < minISODiskBytes {
				continue
			}
			path := d.Path
			if p, err := filepath.EvalSymlinks(path); err == nil {
				path = p
			}
			if live != "" && path == live {
				continue
			}
			disks = append(disks, isoDisk{Path: path, Model: strings.TrimSpace(d.Model), Size: size})
		}
		return isoDisksMsg{disks: disks}
	}
}

func isoHashPasswordCmd(password string) tea.Cmd {
	return func() tea.Msg {
		cmd := exec.Command("mkpasswd", "-m", "yescrypt", "-s")
		cmd.Stdin = strings.NewReader(password)
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			return isoPasswordHashMsg{err: fmt.Errorf("password hashing failed: %v: %s", err, strings.TrimSpace(stderr.String()))}
		}
		hash := strings.TrimSpace(stdout.String())
		if hash == "" || !strings.HasPrefix(hash, "$y$") {
			return isoPasswordHashMsg{err: fmt.Errorf("password hashing returned an invalid yescrypt hash")}
		}
		return isoPasswordHashMsg{hash: hash}
	}
}

func (m isoModel) current() isoStep {
	return isoFlow[clamp(m.idx, 0, len(isoFlow)-1)]
}

func (m *isoModel) gotoKey(key string) {
	for i, step := range isoFlow {
		if step.key == key {
			m.idx = i
			m.cursor = 0
			return
		}
	}
}

func (m *isoModel) next() {
	key := m.current().key
	if key == "network" && m.opts.dryRun && m.syntheticDisk {
		m.gotoKey("filesystem")
		return
	}
	if key == "configuration" && m.picks["configuration"] == "ryoku" {
		m.gotoKey("review")
		return
	}
	if key == "import-host" {
		m.gotoKey("review")
		return
	}
	if key == "review" {
		m.gotoKey("confirm")
		return
	}
	if m.idx < len(isoFlow)-1 {
		m.idx++
		m.cursor = 0
	}
}

func (m *isoModel) back() {
	key := m.current().key
	if key == "filesystem" && m.opts.dryRun && m.syntheticDisk {
		m.gotoKey("network")
		return
	}
	if key == "review" && m.picks["configuration"] == "ryoku" {
		m.gotoKey("configuration")
		return
	}
	if key == "confirm" {
		m.gotoKey("review")
		return
	}
	if m.idx > 0 {
		m.idx--
		m.cursor = 0
	}
}

func isoChoices(key string) []choice {
	switch key {
	case "filesystem":
		return []choice{{"ext4", "ext4", "mature · simple · conservative default"}, {"btrfs", "Btrfs", "checksums · snapshots capable"}}
	case "kernel":
		return []choice{
			{"default", "NixOS default", "LTS-oriented default from the pinned nixpkgs"},
			{"latest", "Latest", "newest kernel package exposed by the pinned nixpkgs"},
			{"zen", "Zen", "desktop-focused tuning from linuxPackages_zen"},
		}
	case "compositor":
		return []choice{{"hyprland", "Hyprland", "dynamic tiling · effects · broad ecosystem"}, {"niri", "niri", "scrollable tiling · clean columns"}, {"mango", "MangoWM", "dynamic tiling · lightweight"}}
	case "browser":
		return []choice{{"chromium", "Chromium", "Chromium engine · Ryoku NixOS default"}, {"firefox", "Firefox", "Gecko engine · Mozilla browser"}}
	case "shell":
		return []choice{{"fish", "Fish", "Ryoku default · friendly interactive shell"}, {"zsh", "Zsh", "Ryoku integration · user .zshrc remains user-owned"}}
	case "configuration":
		return []choice{
			{"ryoku", "Ryoku configuration", "recommended · installer owns the generated NixOS profile"},
			{"import", "Import existing NixOS flake", "ADVANCED · only adds the Ryoku flake input"},
		}
	}
	return nil
}

var (
	hostnameRE = regexp.MustCompile(`^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$|^[A-Za-z0-9]$`)
	usernameRE = regexp.MustCompile(`^[a-z_][a-z0-9_-]{0,31}$`)
	timezoneRE = regexp.MustCompile(`^[A-Za-z0-9_+.-]+(?:/[A-Za-z0-9_+.-]+)*$`)
	localeRE   = regexp.MustCompile(`^[A-Za-z0-9_.@-]+$`)
	keyboardRE = regexp.MustCompile(`^[A-Za-z0-9_,+-]+$`)
)

func (m isoModel) validateTextStep(key string) error {
	v := strings.TrimSpace(m.text[key])
	switch key {
	case "hostname":
		if !hostnameRE.MatchString(v) {
			return fmt.Errorf("hostname must contain only letters, digits and internal hyphens")
		}
	case "username":
		if !usernameRE.MatchString(v) {
			return fmt.Errorf("username must start with a lowercase letter or underscore")
		}
	case "timezone":
		if !timezoneRE.MatchString(v) || strings.Contains(v, "..") {
			return fmt.Errorf("invalid IANA timezone")
		}
	case "locale":
		if !localeRE.MatchString(v) {
			return fmt.Errorf("invalid locale")
		}
	case "keyboard":
		if !keyboardRE.MatchString(v) {
			return fmt.Errorf("invalid XKB keyboard layout")
		}
	case "import-path":
		if v == "" {
			return fmt.Errorf("enter the flake directory to import")
		}
		st, err := os.Stat(v)
		if err != nil || !st.IsDir() {
			return fmt.Errorf("import path is not a directory")
		}
		if _, err := os.Stat(filepath.Join(v, "flake.nix")); err != nil {
			return fmt.Errorf("import path does not contain flake.nix")
		}
	}
	return nil
}

func inputKey(k string) (string, bool) {
	if k == "space" || k == " " {
		return " ", true
	}
	if len([]rune(k)) == 1 {
		r := []rune(k)[0]
		if r >= 0x20 && r != 0x7f {
			return string(r), true
		}
	}
	return "", false
}

func appendInput(value, k string) string {
	if k == "backspace" {
		r := []rune(value)
		if len(r) > 0 {
			return string(r[:len(r)-1])
		}
		return value
	}
	if s, ok := inputKey(k); ok {
		return value + s
	}
	return value
}

func (m *isoModel) setChoiceCursor(key string) {
	choices := isoChoices(key)
	for i, c := range choices {
		if c.key == m.picks[key] {
			m.cursor = i
			return
		}
	}
	m.cursor = 0
}

func (m isoModel) selectedApps() []string {
	var out []string
	for _, app := range optionalApps() {
		if m.keep[app.ID] {
			out = append(out, app.ID)
		}
	}
	return out
}

func (m isoModel) selectedDisk() string {
	if len(m.disks) == 0 {
		return ""
	}
	i := clamp(m.cursor, 0, len(m.disks)-1)
	return m.disks[i].Path
}

func (m *isoModel) fixAppScroll() {
	visible := 9
	if m.h > 38 {
		visible = 13
	}
	apps := optionalApps()
	m.appCursor = clamp(m.appCursor, 0, len(apps)-1)
	if m.appCursor < m.appOffset {
		m.appOffset = m.appCursor
	}
	if m.appCursor >= m.appOffset+visible {
		m.appOffset = m.appCursor - visible + 1
	}
}

func (m isoModel) backendArgs() []string {
	apps := m.selectedApps()
	appArg := "none"
	if len(apps) > 0 {
		appArg = strings.Join(apps, ",")
	}
	args := []string{
		"--iso", "--yes",
	}
	if m.opts.sourceExplicit {
		args = append(args, "--source", m.opts.source)
	}
	args = append(args,
		"--disk", m.picks["disk"],
		"--confirm-disk", m.picks["disk"],
		"--filesystem", m.picks["filesystem"],
		"--hostname", strings.TrimSpace(m.text["hostname"]),
		"--username", strings.TrimSpace(m.text["username"]),
		"--timezone", strings.TrimSpace(m.text["timezone"]),
		"--locale", strings.TrimSpace(m.text["locale"]),
		"--keyboard", strings.TrimSpace(m.text["keyboard"]),
		"--kernel", m.picks["kernel"],
		"--gpu", "auto",
		"--firmware", "auto",
		"--compositor", m.picks["compositor"],
		"--browser", m.picks["browser"],
		"--shell", m.picks["shell"],
		"--apps", appArg,
		"--config-mode", m.picks["configuration"],
	)
	if m.picks["configuration"] == "import" {
		args = append(args, "--import-flake", strings.TrimSpace(m.text["import-path"]))
		if host := strings.TrimSpace(m.text["import-host"]); host != "" {
			args = append(args, "--import-host", host)
		}
	}
	if m.opts.dryRun {
		args = append(args, "--dry-run")
	}
	return args
}

func isoInstallStepIndex(id string) (int, bool) {
	order := []string{"lock", "validate", "partition", "filesystems", "configuration", "install", "finalize"}
	for i, step := range order {
		if step == id {
			return i, true
		}
	}
	return 0, false
}

var isoANSI = regexp.MustCompile("\\x1b\\[[0-9;?]*[ -/]*[@-~]")

func isoSanitizeLine(s string) string {
	if i := strings.LastIndexByte(s, '\r'); i >= 0 {
		s = s[i+1:]
	}
	s = isoANSI.ReplaceAllString(s, "")
	return strings.Map(func(r rune) rune {
		if r == '\t' {
			return r
		}
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, s)
}

func (m *isoModel) startInstall() tea.Cmd {
	stream := &isoInstallStream{ch: make(chan tea.Msg, 128), procDone: make(chan struct{})}
	m.istream = stream
	cmd := exec.Command(backendPath(), m.backendArgs()...)
	cmd.Env = os.Environ()
	if m.picks["configuration"] == "ryoku" && !m.opts.dryRun {
		cmd.Env = append(cmd.Env, "RYOKU_INSTALL_PASSWORD_HASH="+m.passwordHash)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	pr, pw := io.Pipe()
	cmd.Stdout, cmd.Stderr = pw, pw
	stream.cmd = cmd
	if err := cmd.Start(); err != nil {
		close(stream.procDone)
		stream.ch <- isoInstallDoneMsg{err: err}
		return stream.wait()
	}
	go func() {
		done := make(chan error, 1)
		go func() {
			done <- cmd.Wait()
			_ = pw.Close()
			close(stream.procDone)
		}()
		scanner := bufio.NewScanner(pr)
		scanner.Buffer(make([]byte, 64*1024), 1024*1024)
		for scanner.Scan() {
			line := scanner.Text()
			if id, ok := strings.CutPrefix(line, "@@RYOKU_STEP "); ok {
				if idx, ok := isoInstallStepIndex(strings.TrimSpace(id)); ok {
					stream.ch <- isoInstallStepMsg(idx)
					continue
				}
			}
			if line == "@@RYOKU_DONE" {
				continue
			}
			if clean := strings.TrimSpace(isoSanitizeLine(line)); clean != "" {
				stream.ch <- isoInstallLineMsg(clean)
			}
		}
		if err := scanner.Err(); err != nil {
			stream.ch <- isoInstallDoneMsg{err: err}
			return
		}
		stream.ch <- isoInstallDoneMsg{err: <-done}
	}()
	return stream.wait()
}

func (m isoModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		return m, nil
	case isoNetworkMsg:
		m.netChecked = true
		m.netOnline = msg.online
		m.busy = false
		if msg.online {
			m.status = "Connected to cache.nixos.org over HTTPS"
			m.err = nil
		} else {
			m.status = "No working HTTPS connection"
			m.err = msg.err
		}
		return m, nil
	case isoNetworkConfiguredMsg:
		m.busy = true
		m.status = "Rechecking network…"
		if msg.err != nil {
			m.err = msg.err
		}
		return m, isoCheckNetworkCmd()
	case isoDisksMsg:
		m.diskLoading = false
		if m.opts.dryRun && (msg.err != nil || len(msg.disks) == 0) {
			m.syntheticDisk = true
			m.disks = nil
			m.picks["disk"] = dryRunDiskPath
			m.err = nil
			m.status = "No eligible disks found; using /dev/vda as a synthetic dry-run target"
			if m.current().key == "disk" {
				m.next()
				m.setChoiceCursor(m.current().key)
			}
		} else if msg.err != nil {
			m.err = msg.err
		} else {
			m.syntheticDisk = false
			m.disks = msg.disks
		}
		return m, nil
	case isoPasswordHashMsg:
		m.busy = false
		if msg.err != nil {
			m.err = msg.err
			return m, nil
		}
		m.passwordHash = msg.hash
		m.text["password"] = ""
		m.text["confirm"] = ""
		m.err = nil
		m.next()
		return m, nil
	case isoInstallLineMsg:
		m.installLog = append(m.installLog, string(msg))
		return m, m.istream.wait()
	case isoInstallStepMsg:
		m.installAt = int(msg)
		return m, m.istream.wait()
	case isoInstallDoneMsg:
		m.installing = false
		m.err = msg.err
		if msg.err == nil {
			m.done = true
			m.installAt = len(isoInstallSteps())
		}
		return m, nil
	case tea.KeyPressMsg:
		return m.onKey(msg.String())
	case tea.MouseWheelMsg:
		if msg.Button == tea.MouseWheelUp {
			return m.onKey("up")
		}
		if msg.Button == tea.MouseWheelDown {
			return m.onKey("down")
		}
	}
	return m, nil
}

func (m isoModel) onKey(k string) (tea.Model, tea.Cmd) {
	if k == "ctrl+c" {
		if m.installing {
			m.istream.kill()
		}
		return m, tea.Quit
	}
	if m.done {
		if k == "enter" || k == "q" || k == "esc" {
			return m, tea.Quit
		}
		return m, nil
	}
	if m.installing {
		return m, nil
	}
	if m.busy {
		return m, nil
	}
	if k == "q" {
		switch m.current().key {
		case "password", "hostname", "username", "timezone", "locale", "keyboard", "import-path", "import-host", "confirm":
			// q is normal text while the user is typing into a field.
		default:
			return m, tea.Quit
		}
	}
	if k == "esc" {
		m.err = nil
		m.back()
		m.setChoiceCursor(m.current().key)
		return m, nil
	}

	key := m.current().key
	switch key {
	case "network":
		if m.netOnline {
			if k == "enter" || k == "tab" {
				m.next()
			}
			return m, nil
		}
		if k == "up" || k == "k" {
			m.cursor = clamp(m.cursor-1, 0, 2)
		} else if k == "down" || k == "j" {
			m.cursor = clamp(m.cursor+1, 0, 2)
		} else if k == "enter" {
			switch m.cursor {
			case 0:
				m.busy = true
				m.status = "Opening NetworkManager…"
				return m, isoConfigureNetworkCmd()
			case 1:
				m.busy = true
				m.status = "Rechecking network…"
				return m, isoCheckNetworkCmd()
			case 2:
				return m, tea.Quit
			}
		}
		return m, nil
	case "disk":
		if len(m.disks) == 0 {
			if k == "r" {
				m.diskLoading = true
				return m, isoLoadDisksCmd()
			}
			return m, nil
		}
		if k == "up" || k == "k" {
			m.cursor = clamp(m.cursor-1, 0, len(m.disks)-1)
		} else if k == "down" || k == "j" {
			m.cursor = clamp(m.cursor+1, 0, len(m.disks)-1)
		} else if k == "enter" || k == "tab" {
			m.picks["disk"] = m.selectedDisk()
			m.next()
			m.setChoiceCursor(m.current().key)
		}
		return m, nil
	case "apps":
		apps := optionalApps()
		switch k {
		case "up", "k":
			m.appCursor = clamp(m.appCursor-1, 0, len(apps)-1)
		case "down", "j":
			m.appCursor = clamp(m.appCursor+1, 0, len(apps)-1)
		case "space", " ":
			m.keep[apps[m.appCursor].ID] = !m.keep[apps[m.appCursor].ID]
		case "a":
			for _, app := range apps {
				m.keep[app.ID] = true
			}
		case "n":
			for _, app := range apps {
				m.keep[app.ID] = false
			}
		case "enter", "tab":
			m.next()
			m.setChoiceCursor(m.current().key)
		}
		m.fixAppScroll()
		return m, nil
	case "password":
		if k == "tab" {
			m.passwordField = 1 - m.passwordField
			return m, nil
		}
		if k == "enter" {
			if m.passwordField == 0 {
				m.passwordField = 1
				return m, nil
			}
			if m.text["password"] == "" {
				m.err = fmt.Errorf("password cannot be empty")
				return m, nil
			}
			if m.text["password"] != m.text["confirm"] {
				m.err = fmt.Errorf("passwords do not match")
				return m, nil
			}
			m.busy = true
			m.err = nil
			return m, isoHashPasswordCmd(m.text["password"])
		}
		field := "password"
		if m.passwordField == 1 {
			field = "confirm"
		}
		m.text[field] = appendInput(m.text[field], k)
		return m, nil
	case "hostname", "username", "timezone", "locale", "keyboard", "import-path", "import-host":
		if k == "enter" || k == "tab" {
			if err := m.validateTextStep(key); err != nil {
				m.err = err
				return m, nil
			}
			m.err = nil
			m.next()
			m.setChoiceCursor(m.current().key)
			return m, nil
		}
		m.text[key] = appendInput(m.text[key], k)
		return m, nil
	case "review":
		if k == "enter" {
			m.text["disk-confirm"] = ""
			m.next()
		}
		return m, nil
	case "confirm":
		if k == "enter" {
			if m.opts.dryRun || m.text["disk-confirm"] == m.picks["disk"] {
				m.installing = true
				m.installAt = 0
				m.installLog = nil
				m.err = nil
				return m, m.startInstall()
			}
			m.err = fmt.Errorf("confirmation must exactly match %s", m.picks["disk"])
			return m, nil
		}
		m.text["disk-confirm"] = appendInput(m.text["disk-confirm"], k)
		return m, nil
	}

	choices := isoChoices(key)
	if len(choices) > 0 {
		if k == "up" || k == "k" {
			m.cursor = clamp(m.cursor-1, 0, len(choices)-1)
		} else if k == "down" || k == "j" {
			m.cursor = clamp(m.cursor+1, 0, len(choices)-1)
		} else if k == "enter" || k == "tab" {
			m.picks[key] = choices[m.cursor].key
			m.next()
			m.setChoiceCursor(m.current().key)
		}
	}
	return m, nil
}

func humanBytes(n int64) string {
	const gib = 1024 * 1024 * 1024
	if n <= 0 {
		return "0 GiB"
	}
	return fmt.Sprintf("%.1f GiB", float64(n)/gib)
}

func (m isoModel) rail() string {
	var lines []string
	for i, step := range isoFlow {
		if (step.key == "import-path" || step.key == "import-host") && m.picks["configuration"] != "import" {
			continue
		}
		mark := fg(cDim, "·")
		label := fg(cSub, step.title)
		if i < m.idx {
			mark = fg(cGreen, checkGlyph())
		}
		if i == m.idx {
			mark = bold(cBrand, currentGlyph())
			label = bold(cText, step.title)
		}
		lines = append(lines, mark+"  "+label)
	}
	return sty().Width(25).Padding(1, 1).Render(strings.Join(lines, "\n"))
}

func (m isoModel) choiceBody(key string) string {
	choices := isoChoices(key)
	var b strings.Builder
	for i, c := range choices {
		prefix := "  "
		name := fg(cText, c.label)
		if i == m.cursor {
			prefix = bold(cBrand, "▌ ")
			name = bold(cText, c.label)
		}
		b.WriteString(prefix + name + "\n")
		b.WriteString("    " + fg(cSub, c.detail) + "\n")
		if i != len(choices)-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}

func (m isoModel) networkBody() string {
	if !m.netChecked || m.busy {
		return fg(cSub, "Checking https://cache.nixos.org …")
	}
	if m.netOnline {
		return bold(cGreen, checkGlyph()+"  Connected") + "\n\n" + fg(cSub, "The Nix cache is reachable over HTTPS. Press Enter to continue.")
	}
	items := []string{"Configure network", "Retry connection", "Quit installer"}
	var b strings.Builder
	b.WriteString(bold(cRed, "No working network connection") + "\n\n")
	for i, item := range items {
		prefix := "  "
		if i == m.cursor {
			prefix = bold(cBrand, "▌ ")
		}
		b.WriteString(prefix + fg(cText, item) + "\n")
	}
	b.WriteString("\n" + fg(cSub, "Network setup opens NetworkManager's nmtui and returns here automatically."))
	return b.String()
}

func (m isoModel) diskBody() string {
	if m.diskLoading {
		return fg(cSub, "Scanning writable disks …")
	}
	if len(m.disks) == 0 {
		return bold(cRed, "No eligible writable disks found") + "\n\n" + fg(cSub, "Ryoku hides the live installer disk and disks smaller than 16 GiB. Press R to rescan.")
	}
	var b strings.Builder
	for i, disk := range m.disks {
		prefix := "  "
		name := fg(cText, disk.Path)
		if i == m.cursor {
			prefix = bold(cBrand, "▌ ")
			name = bold(cText, disk.Path)
		}
		model := disk.Model
		if model == "" {
			model = "Unknown disk"
		}
		b.WriteString(prefix + name + "  " + fg(cSub, humanBytes(disk.Size)+" · "+model) + "\n")
	}
	b.WriteString("\n" + bold(cYell, "The selected whole disk will be erased after the final exact-path confirmation."))
	return b.String()
}

func masked(s string) string {
	if s == "" {
		return ""
	}
	return strings.Repeat("•", len([]rune(s)))
}

func inputLine(label, value string, active, secret bool) string {
	shown := value
	if secret {
		shown = masked(value)
	}
	cursor := "  "
	if active {
		cursor = bold(cBrand, "▌ ")
	}
	return cursor + fg(cSub, fmt.Sprintf("%-12s", label)) + fg(cText, shown) + fg(cDim, "_")
}

func (m isoModel) passwordBody() string {
	return inputLine("Password", m.text["password"], m.passwordField == 0, true) + "\n\n" +
		inputLine("Confirm", m.text["confirm"], m.passwordField == 1, true) + "\n\n" +
		fg(cSub, "Tab switches fields. Enter on Confirm hashes the password with yescrypt.")
}

func (m isoModel) textBody(key string) string {
	label := m.current().title
	if key == "import-host" {
		label = "Host"
	}
	return inputLine(label, m.text[key], true, false)
}

func (m isoModel) appsBody() string {
	apps := optionalApps()
	visible := 9
	if m.h > 38 {
		visible = 13
	}
	start := clamp(m.appOffset, 0, len(apps))
	end := clamp(start+visible, 0, len(apps))
	var b strings.Builder
	for i := start; i < end; i++ {
		app := apps[i]
		prefix := "  "
		if i == m.appCursor {
			prefix = bold(cBrand, "▌ ")
		}
		mark := fg(cDim, "○")
		if m.keep[app.ID] {
			mark = fg(cGreen, "●")
		}
		b.WriteString(prefix + mark + " " + fg(cText, app.Label) + fg(cSub, "  "+app.Detail) + "\n")
	}
	return b.String()
}

func (m isoModel) reviewBody() string {
	row := func(k, v string) string { return fg(cSub, fmt.Sprintf("%-13s", k)) + fg(cText, v) }
	apps := m.selectedApps()
	lines := []string{
		bold(cBrand, "Ready to install Ryoku on NixOS"), "",
		row("Disk", m.picks["disk"]),
		row("Filesystem", m.picks["filesystem"]),
		row("Hostname", strings.TrimSpace(m.text["hostname"])),
		row("Username", strings.TrimSpace(m.text["username"])),
		row("Timezone", strings.TrimSpace(m.text["timezone"])),
		row("Locale", strings.TrimSpace(m.text["locale"])),
		row("Keyboard", strings.TrimSpace(m.text["keyboard"])),
		row("Kernel", m.picks["kernel"]),
		row("Window mgr", m.picks["compositor"]),
		row("Browser", m.picks["browser"]),
		row("Shell", m.picks["shell"]),
		row("Apps", fmt.Sprintf("%d selected", len(apps))),
		row("Config", m.picks["configuration"]),
	}
	if m.picks["configuration"] == "import" {
		host := strings.TrimSpace(m.text["import-host"])
		if host == "" {
			host = "auto-detect single host"
		}
		lines = append(lines,
			row("Import", strings.TrimSpace(m.text["import-path"])),
			row("Import host", host), "",
			bold(cYell, "ADVANCED IMPORT: the imported flake owns users, kernel, desktop modules and system policy."),
			fg(cSub, "Ryoku only adds its flake input. The installer replaces root hardware-configuration.nix for this machine."),
			fg(cSub, "Earlier profile choices are shown for transparency but are not injected into the imported configuration."),
		)
	}
	if m.opts.dryRun {
		lines = append(lines, "", bold(cYell, "DRY RUN · no disk or file changes will be made"))
	} else {
		lines = append(lines, "", bold(cRed, "ALL DATA ON "+m.picks["disk"]+" WILL BE ERASED."))
	}
	return strings.Join(lines, "\n")
}

func (m isoModel) confirmBody() string {
	if m.opts.dryRun {
		return bold(cGreen, "Dry run confirmation") + "\n\n" + fg(cSub, "Press Enter to validate the complete backend plan. No disk will be touched.")
	}
	return bold(cRed, "Final destructive confirmation") + "\n\n" +
		fg(cText, "Type exactly: ") + bold(cYell, m.picks["disk"]) + "\n\n" +
		inputLine("Confirm", m.text["disk-confirm"], true, false) + "\n\n" +
		fg(cSub, "The backend validates the same exact disk token again before wipefs runs.")
}

func isoInstallSteps() []string {
	return []string{"Resolve flake inputs", "Validate target config", "Partition disk", "Create filesystems", "Write configuration", "Install NixOS", "Finalize"}
}

func (m isoModel) installBody() string {
	steps := isoInstallSteps()
	var b strings.Builder
	b.WriteString(bold(cBrand, "Installing Ryoku") + "\n\n")
	for i, step := range steps {
		mark := fg(cDim, "·")
		if i < m.installAt {
			mark = fg(cGreen, checkGlyph())
		} else if i == m.installAt {
			mark = bold(cBrand, currentGlyph())
		}
		b.WriteString(mark + "  " + fg(cText, step) + "\n")
	}
	b.WriteString("\n" + progressBar(clamp(m.installAt, 0, len(steps)-1), len(steps), 32) + "\n\n")
	log := m.installLog
	max := 8
	if m.h > 38 {
		max = 12
	}
	if len(log) > max {
		log = log[len(log)-max:]
	}
	for _, line := range log {
		if len([]rune(line)) > 96 {
			line = string([]rune(line)[:96]) + "…"
		}
		b.WriteString(fg(cSub, line) + "\n")
	}
	return sty().Width(92).Border(border()).BorderForeground(cSub).Padding(1, 2).Render(strings.TrimRight(b.String(), "\n"))
}

func (m isoModel) wizardBody() string {
	step := m.current()
	var body string
	switch step.key {
	case "network":
		body = m.networkBody()
	case "disk":
		body = m.diskBody()
	case "password":
		body = m.passwordBody()
	case "apps":
		body = m.appsBody()
	case "hostname", "username", "timezone", "locale", "keyboard", "import-path", "import-host":
		body = m.textBody(step.key)
	case "review":
		body = m.reviewBody()
	case "confirm":
		body = m.confirmBody()
	default:
		body = m.choiceBody(step.key)
	}
	content := bold(cBrand, step.title) + "\n" + fg(cSub, step.desc) + "\n\n" + body
	if m.err != nil {
		content += "\n\n" + bold(cRed, "! "+m.err.Error())
	}
	card := sty().Width(76).Border(border()).BorderForeground(cSub).Padding(1, 2).Render(content)
	if m.w < 108 {
		return card
	}
	return lipgloss.JoinHorizontal(lipgloss.Top, m.rail(), "  ", card)
}

func (m isoModel) footer() string {
	if m.installing {
		return keyHint("ctrl+c", "abort installation")
	}
	if m.done {
		return keyHint("enter", "close")
	}
	key := m.current().key
	switch key {
	case "network":
		if m.netOnline {
			return keyHint("enter", "continue") + fg(cDim, "  ·  ") + keyHint("q", "quit")
		}
		return keyHint("↑↓", "move") + fg(cDim, "  ·  ") + keyHint("enter", "select")
	case "apps":
		return keyHint("↑↓", "move") + fg(cDim, "  ·  ") + keyHint("space", "toggle") + fg(cDim, "  ·  ") + keyHint("a/n", "all/none") + fg(cDim, "  ·  ") + keyHint("enter", "next")
	case "password":
		return keyHint("tab", "switch field") + fg(cDim, "  ·  ") + keyHint("enter", "continue") + fg(cDim, "  ·  ") + keyHint("esc", "back")
	case "hostname", "username", "timezone", "locale", "keyboard", "import-path", "import-host", "confirm":
		return keyHint("enter", "continue") + fg(cDim, "  ·  ") + keyHint("backspace", "edit") + fg(cDim, "  ·  ") + keyHint("esc", "back")
	case "review":
		return keyHint("enter", "final confirmation") + fg(cDim, "  ·  ") + keyHint("esc", "back")
	default:
		return keyHint("↑↓", "move") + fg(cDim, "  ·  ") + keyHint("enter", "select") + fg(cDim, "  ·  ") + keyHint("esc", "back")
	}
}

func (m isoModel) render() string {
	if m.w == 0 {
		return ""
	}
	if m.w < 76 || m.h < 24 {
		return lipgloss.Place(m.w, m.h, lipgloss.Center, lipgloss.Center, bold(cYell, "Terminal too small")+"\n"+fg(cSub, "Ryoku needs at least 76 × 24."))
	}
	var body string
	if m.installing {
		body = m.installBody()
	} else if m.done {
		title := "Ryoku is installed"
		if m.opts.dryRun {
			title = "Dry run complete"
		}
		body = lipgloss.JoinVertical(lipgloss.Center, logoBlock(), "", bold(cGreen, checkGlyph()+"  "+title), "", fg(cSub, "The installer backend completed successfully."))
	} else {
		progress := progressBar(m.idx, len(isoFlow), 30)
		body = lipgloss.JoinVertical(lipgloss.Left, logoBlock(), "", progress+fg(cDim, fmt.Sprintf("  %d/%d", m.idx+1, len(isoFlow))), "", m.wizardBody())
	}
	placed := lipgloss.Place(m.w, m.h-2, lipgloss.Center, lipgloss.Center, body)
	return placed + "\n" + lipgloss.PlaceHorizontal(m.w, lipgloss.Center, m.footer())
}

func (m isoModel) View() tea.View {
	v := tea.NewView(m.render())
	v.AltScreen = true
	v.BackgroundColor = cBg
	v.ForegroundColor = cText
	v.WindowTitle = "Ryoku NixOS installer"
	return v
}
