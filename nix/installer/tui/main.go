package main

import (
	"fmt"
	"image/color"
	"os"
	"os/exec"
	"strings"
	"syscall"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

var (
	cBg    = lipgloss.Color("#060607")
	cText  = lipgloss.Color("#eae2d5")
	cSub   = lipgloss.Color("#8c857a")
	cDim   = lipgloss.Color("#3a3630")
	cBrand = lipgloss.Color("#c75d2b")
	cGreen = lipgloss.Color("#88a57d")
	cYell  = lipgloss.Color("#c79a5b")
	cRed   = lipgloss.Color("#b24a38")
)

func sty() lipgloss.Style                 { return lipgloss.NewStyle() }
func fg(c color.Color, s string) string   { return sty().Foreground(c).Render(s) }
func bold(c color.Color, s string) string { return sty().Foreground(c).Bold(true).Render(s) }
func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

var logo = []string{
	"█▀▄ █ █ █▀█ █▄▀ █ █",
	"█▀▄ ▀█▀ █ █ █▀▄ █ █",
	"▀ ▀ ░█░ ▀▀▀ ▀ ▀ ▀▀▀",
}

var ascii bool

func initGlyphs() {
	t := os.Getenv("TERM")
	ascii = os.Getenv("RYOKU_ASCII") != "" || t == "dumb" || t == "vt100" || t == ""
}
func checkGlyph() string {
	if ascii {
		return "+"
	}
	return "✓"
}
func currentGlyph() string {
	if ascii {
		return ">"
	}
	return "▸"
}
func fullGlyph() string {
	if ascii {
		return "#"
	}
	return "█"
}
func emptyGlyph() string {
	if ascii {
		return "-"
	}
	return "░"
}
func border() lipgloss.Border {
	if ascii {
		return lipgloss.Border{Top: "-", Bottom: "-", Left: "|", Right: "|", TopLeft: "+", TopRight: "+", BottomLeft: "+", BottomRight: "+"}
	}
	return lipgloss.NormalBorder()
}

type choice struct{ key, label, detail string }
type step struct {
	key, title, desc string
	choices          []choice
}

var flow = []step{
	{key: "compositor", title: "Window manager", desc: "Choose the session Ryoku preselects. All Ryoku providers stay installed.", choices: []choice{
		{"hyprland", "Hyprland", "dynamic tiling · effects · broad plugin ecosystem"},
		{"niri", "niri", "scrollable tiling · clean columns · Ryoku-supported"},
		{"mango", "MangoWM", "dynamic tiling · lightweight · Ryoku Nix supported"},
	}},
	{key: "browser", title: "Web browser", desc: "Installed declaratively and used by Ryoku's browser role.", choices: []choice{
		{"chromium", "Chromium", "Chromium engine · current NixOS default"},
		{"firefox", "Firefox", "Gecko engine · Mozilla browser"},
	}},
	{key: "shell", title: "Interactive shell", desc: "Ryoku configures the integration; your own shell rc files remain yours.", choices: []choice{
		{"fish", "Fish", "Ryoku default · friendly interactive shell"},
		{"zsh", "Zsh", "Ryoku integration · ~/.zshrc remains user-owned"},
	}},
	{key: "apps", title: "Apps & tools", desc: "Space toggles a tool. Required desktop contracts cannot be removed here."},
	{key: "review", title: "Review", desc: "The backend builds the new generation before switching. Disks and boot layout are untouched."},
}

type options struct {
	flake, source  string
	sourceExplicit bool
	dryRun         bool
	noCache        bool
	iso            bool
}

func defaultOptions() options {
	return options{flake: "/etc/nixos", source: envDefault("RYOKU_INSTALL_SOURCE", "github:aethctl/Ryoku-on-NixOS/main")}
}
func envDefault(k, d string) string {
	if v := strings.TrimSpace(os.Getenv(k)); v != "" {
		return v
	}
	return d
}

type model struct {
	w, h                              int
	state                             string
	idx, cursor, appCursor, appOffset int
	picks                             map[string]string
	keep                              map[string]bool
	opts                              options
	installAt                         int
	installLog                        []string
	err                               error
}

func newModel(opts options) model {
	keep := map[string]bool{}
	for _, a := range optionalApps() {
		keep[a.ID] = true
	}
	return model{state: "welcome", picks: map[string]string{"compositor": "hyprland", "browser": "chromium", "shell": "fish"}, keep: keep, opts: opts}
}
func (m model) Init() tea.Cmd { return nil }

func (m model) cur() step { return flow[clamp(m.idx, 0, len(flow)-1)] }
func (m *model) setCursorForStep() {
	if m.cur().key == "apps" {
		return
	}
	m.cursor = 0
	for i, c := range m.cur().choices {
		if c.key == m.picks[m.cur().key] {
			m.cursor = i
			break
		}
	}
}
func (m *model) advance() {
	if m.idx < len(flow)-1 {
		m.idx++
		m.setCursorForStep()
	}
}
func (m *model) back() {
	if m.idx > 0 {
		m.idx--
		m.setCursorForStep()
	} else {
		m.state = "welcome"
	}
}

type installDoneMsg struct{ err error }

func backendPath() string { return envDefault("RYOKU_INSTALL_BACKEND", "ryoku-install-backend") }
func (m model) selectedApps() []string {
	var out []string
	for _, a := range optionalApps() {
		if m.keep[a.ID] {
			out = append(out, a.ID)
		}
	}
	return out
}
func (m *model) startInstall() tea.Cmd {
	apps := m.selectedApps()
	appArg := "none"
	if len(apps) > 0 {
		appArg = strings.Join(apps, ",")
	}
	args := []string{"--flake", m.opts.flake}
	if m.opts.sourceExplicit {
		args = append(args, "--source", m.opts.source)
	}
	args = append(args,
		"--compositor", m.picks["compositor"], "--browser", m.picks["browser"],
		"--shell", m.picks["shell"], "--apps", appArg,
	)
	if m.opts.iso {
		args = append(args, "--iso")
	} else {
		args = append(args, "--yes")
	}
	if m.opts.noCache {
		args = append(args, "--no-cache")
	}
	if m.opts.dryRun {
		args = append(args, "--dry-run")
	}
	return tea.ExecProcess(exec.Command(backendPath(), args...), func(err error) tea.Msg {
		return installDoneMsg{err: err}
	})
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		return m, nil
	case installDoneMsg:
		m.err = msg.err
		if msg.err != nil {
			m.state = "failed"
		} else {
			m.state = "done"
			m.installAt = 5
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

func (m model) onKey(k string) (tea.Model, tea.Cmd) {
	if k == "ctrl+c" {
		return m, tea.Quit
	}
	switch m.state {
	case "welcome":
		switch k {
		case "enter":
			m.state = "wizard"
		case "q", "esc":
			return m, tea.Quit
		}
		return m, nil
	case "install":
		return m, nil
	case "done":
		if k == "enter" || k == "q" || k == "esc" {
			return m, tea.Quit
		}
		return m, nil
	case "failed":
		if k == "r" {
			m.state = "install"
			m.err = nil
			m.installAt = 0
			m.installLog = nil
			return m, m.startInstall()
		}
		if k == "q" || k == "esc" {
			return m, tea.Quit
		}
		return m, nil
	}
	if k == "q" {
		return m, tea.Quit
	}
	if k == "esc" {
		m.back()
		return m, nil
	}
	s := m.cur()
	if s.key == "apps" {
		apps := optionalApps()
		switch k {
		case "up", "k":
			m.appCursor = clamp(m.appCursor-1, 0, len(apps)-1)
		case "down", "j":
			m.appCursor = clamp(m.appCursor+1, 0, len(apps)-1)
		case "space":
			m.keep[apps[m.appCursor].ID] = !m.keep[apps[m.appCursor].ID]
		case "a":
			for _, a := range apps {
				m.keep[a.ID] = true
			}
		case "n":
			for _, a := range apps {
				m.keep[a.ID] = false
			}
		case "enter", "tab":
			m.advance()
		}
		m.fixAppScroll()
		return m, nil
	}
	if s.key == "review" {
		if k == "enter" {
			m.state = "install"
			m.installAt = 0
			m.installLog = nil
			return m, m.startInstall()
		}
		return m, nil
	}
	switch k {
	case "up", "k":
		m.cursor = clamp(m.cursor-1, 0, len(s.choices)-1)
	case "down", "j":
		m.cursor = clamp(m.cursor+1, 0, len(s.choices)-1)
	case "enter", "tab":
		m.picks[s.key] = s.choices[m.cursor].key
		m.advance()
	}
	return m, nil
}

func (m *model) fixAppScroll() {
	visible := 10
	if m.h > 35 {
		visible = 14
	}
	if m.appCursor < m.appOffset {
		m.appOffset = m.appCursor
	}
	if m.appCursor >= m.appOffset+visible {
		m.appOffset = m.appCursor - visible + 1
	}
}

func progressBar(cur, total, w int) string {
	if total <= 0 {
		total = 1
	}
	fill := clamp((cur+1)*w/total, 0, w)
	return fg(cBrand, strings.Repeat(fullGlyph(), fill)) + fg(cDim, strings.Repeat(emptyGlyph(), w-fill))
}
func keyHint(k, d string) string { return bold(cBrand, k) + " " + fg(cSub, d) }
func logoBlock() string {
	lines := make([]string, len(logo))
	for i, l := range logo {
		lines[i] = bold(cBrand, l)
	}
	return lipgloss.JoinVertical(lipgloss.Center, lines...)
}
func (m model) rail() string {
	var lines []string
	for i, s := range flow {
		mark := fg(cDim, "·")
		label := fg(cSub, s.title)
		if i < m.idx {
			mark = fg(cGreen, checkGlyph())
			label = fg(cSub, s.title)
		}
		if i == m.idx {
			mark = bold(cBrand, currentGlyph())
			label = bold(cText, s.title)
		}
		lines = append(lines, fmt.Sprintf("%s %d  %s", mark, i+1, label))
	}
	return sty().Width(24).Padding(1, 1).Render(strings.Join(lines, "\n\n"))
}
func (m model) choiceBody(s step, w int) string {
	var b strings.Builder
	for i, c := range s.choices {
		selected := i == m.cursor
		prefix := "  "
		if selected {
			prefix = bold(cBrand, "▌ ")
		}
		name := fg(cText, c.label)
		if selected {
			name = bold(cText, c.label)
		}
		b.WriteString(prefix + name + "\n")
		b.WriteString("    " + fg(cSub, c.detail) + "\n")
		if i < len(s.choices)-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}
func (m model) appsBody(w int) string {
	apps := optionalApps()
	visible := 10
	if m.h > 35 {
		visible = 14
	}
	start := clamp(m.appOffset, 0, len(apps))
	end := clamp(start+visible, 0, len(apps))
	var b strings.Builder
	b.WriteString(fg(cDim, "required  ") + fg(cText, strings.Join(requiredApps(), " · ")) + "\n\n")
	lastCat := ""
	for i := start; i < end; i++ {
		a := apps[i]
		if a.Category != lastCat {
			if lastCat != "" {
				b.WriteString("\n")
			}
			b.WriteString(bold(cBrand, a.Category) + "\n")
			lastCat = a.Category
		}
		cur := "  "
		if i == m.appCursor {
			cur = bold(cBrand, "▌ ")
		}
		mark := fg(cDim, "○")
		if m.keep[a.ID] {
			mark = fg(cGreen, "●")
		}
		name := fg(cText, a.Label)
		if i == m.appCursor {
			name = bold(cText, a.Label)
		}
		b.WriteString(cur + mark + " " + name + fg(cSub, "  "+a.Detail) + "\n")
	}
	if start > 0 {
		b.WriteString(fg(cDim, "  ↑ more") + "\n")
	}
	if end < len(apps) {
		b.WriteString(fg(cDim, "  ↓ more") + "\n")
	}
	return b.String()
}
func (m model) reviewBody() string {
	row := func(k, v string) string { return fg(cSub, fmt.Sprintf("%-12s", k)) + fg(cText, v) }
	apps := m.selectedApps()
	av := "none"
	if len(apps) > 0 {
		av = fmt.Sprintf("%d selected", len(apps))
	}

	cache := "enabled"
	if m.opts.noCache {
		cache = "disabled"
	}

	var lines []string
	if m.opts.iso {
		lines = []string{
			bold(cBrand, "Ready for full Ryoku installation"), "",
			row("source", m.opts.source), row("compositor", m.picks["compositor"]),
			row("browser", m.picks["browser"]), row("shell", m.picks["shell"]), row("apps", av), row("cache", cache), "",
			fg(cGreen, "✓ disk and filesystem selection happens next"),
			fg(cGreen, "✓ installs a flake-based NixOS target under /mnt"),
			bold(cYell, "! the selected target disk will be erased only after exact-path confirmation"),
		}
	} else {
		lines = []string{
			bold(cBrand, "Ready to configure Ryoku on NixOS"), "",
			row("flake", m.opts.flake), row("source", m.opts.source), row("compositor", m.picks["compositor"]),
			row("browser", m.picks["browser"]), row("shell", m.picks["shell"]), row("apps", av), row("cache", cache), "",
			fg(cGreen, "✓ builds the generation before switching"),
			fg(cGreen, "✓ backs up installer-managed Nix files"),
			fg(cGreen, "✓ leaves disks, boot layout and unrelated modules alone"),
		}
	}
	if m.opts.dryRun {
		lines = append(lines, "", bold(cYell, "DRY RUN · no files or disks will be changed"))
	}
	return strings.Join(lines, "\n")
}
func (m model) wizardBody() string {
	s := m.cur()
	desc := s.desc
	if m.opts.iso && s.key == "review" {
		desc = "Review Ryoku choices. Disk selection and destructive confirmation happen in the next stage."
	}
	var body string
	switch s.key {
	case "apps":
		body = m.appsBody(68)
	case "review":
		body = m.reviewBody()
	default:
		body = m.choiceBody(s, 68)
	}
	content := bold(cBrand, s.title) + "\n" + fg(cSub, desc) + "\n\n" + body
	card := sty().Width(72).Border(border()).BorderForeground(cSub).Padding(1, 2).Render(content)
	if m.w < 100 {
		return card
	}
	return lipgloss.JoinHorizontal(lipgloss.Top, m.rail(), "  ", card)
}
func installSteps() []string {
	return []string{"Prepare configuration", "Update flake lock", "Build NixOS generation", "Switch generation", "Materialize Ryoku"}
}
func (m model) installBody() string {
	steps := installSteps()
	var b strings.Builder
	b.WriteString(bold(cBrand, "Applying Ryoku") + "\n\n")
	for i, s := range steps {
		mark := fg(cDim, "·")
		if i < m.installAt {
			mark = fg(cGreen, checkGlyph())
		} else if i == m.installAt {
			mark = bold(cBrand, currentGlyph())
		}
		b.WriteString(fmt.Sprintf("%s  %s\n", mark, s))
	}
	b.WriteString("\n" + progressBar(clamp(m.installAt, 0, len(steps)-1), len(steps), 32) + "\n\n")
	log := m.installLog
	max := 8
	if m.h > 36 {
		max = 12
	}
	if len(log) > max {
		log = log[len(log)-max:]
	}
	for _, line := range log {
		if len(line) > 84 {
			line = line[:84] + "…"
		}
		b.WriteString(fg(cSub, line) + "\n")
	}

	return sty().Width(88).Border(border()).BorderForeground(cSub).Padding(1, 2).Render(strings.TrimRight(b.String(), "\n"))
}
func (m model) welcomeBody() string {
	var title, line1, line2, line3 string
	if m.opts.iso {
		title = "Install Ryoku on NixOS"
		line1 = "A full NixOS + Ryoku installation from the live ISO."
		line2 = "Choose the desktop here; disk and filesystem selection follows."
		line3 = "Nothing is erased until you type the exact target disk path."
	} else {
		title = "Ryoku for NixOS"
		line1 = "The same Ryoku installer language, adapted for a declarative host."
		line2 = "No partitioning. No pacstrap. No mutable package transaction."
		line3 = "Your flake is edited, built, then switched only after validation."
	}
	card := sty().Border(border()).BorderForeground(cSub).Padding(1, 3).Render(
		bold(cBrand, title) + "\n\n" +
			fg(cText, line1) + "\n" + fg(cSub, line2) + "\n" + fg(cSub, line3))
	return lipgloss.JoinVertical(lipgloss.Center, logoBlock(), "", fg(cDim, "NIXOS EDITION"), "", "", card)
}
func (m model) render() string {
	if m.w == 0 {
		return ""
	}
	if m.w < 72 || m.h < 22 {
		return lipgloss.Place(m.w, m.h, lipgloss.Center, lipgloss.Center, bold(cYell, "Terminal too small")+"\n"+fg(cSub, "Ryoku needs at least 72 × 22."))
	}
	var body, foot string
	switch m.state {
	case "welcome":
		body = m.welcomeBody()
		foot = keyHint("enter", "continue") + fg(cDim, "    ") + keyHint("q", "quit")
	case "wizard":
		body = lipgloss.JoinVertical(lipgloss.Left, logoBlock(), "", progressBar(m.idx, len(flow), 28)+fg(cDim, fmt.Sprintf("  %d/%d", m.idx+1, len(flow))), "", m.wizardBody())
		if m.cur().key == "apps" {
			foot = keyHint("↑↓/jk", "move") + fg(cDim, "  ·  ") + keyHint("space", "toggle") + fg(cDim, "  ·  ") + keyHint("a/n", "all/none") + fg(cDim, "  ·  ") + keyHint("enter", "next")
		} else if m.cur().key == "review" {
			action := "build & switch"
			if m.opts.iso {
				action = "continue to disk install"
			}
			foot = keyHint("enter", action) + fg(cDim, "  ·  ") + keyHint("esc", "back")
		} else {
			foot = keyHint("↑↓/jk", "move") + fg(cDim, "  ·  ") + keyHint("enter", "select") + fg(cDim, "  ·  ") + keyHint("esc", "back")
		}
	case "install":
		body = m.installBody()
		foot = keyHint("ctrl+c", "cancel")
	case "done":
		title := "Ryoku is ready"
		if m.opts.iso {
			title = "Ryoku is installed"
		}
		if m.opts.dryRun {
			title = "Dry run complete"
		}
		body = lipgloss.JoinVertical(lipgloss.Center, logoBlock(), "", bold(cGreen, checkGlyph()+"  "+title), "", fg(cSub, "The installer backend completed successfully."))
		foot = keyHint("enter", "close")
	case "failed":
		body = lipgloss.JoinVertical(lipgloss.Center, logoBlock(), "", bold(cRed, "Installation failed"), "", fg(cText, fmt.Sprint(m.err)), "", fg(cSub, "Your installer-managed files are rolled back by the backend on build/switch failure."))
		foot = keyHint("r", "retry") + fg(cDim, "    ") + keyHint("q", "quit")
	}
	placed := lipgloss.Place(m.w, m.h-2, lipgloss.Center, lipgloss.Center, body)
	return placed + "\n" + lipgloss.PlaceHorizontal(m.w, lipgloss.Center, foot)
}
func (m model) View() tea.View {
	v := tea.NewView(m.render())
	v.AltScreen = true
	v.BackgroundColor = cBg
	v.ForegroundColor = cText
	v.WindowTitle = "Ryoku NixOS installer"
	return v
}

func usage() {
	fmt.Println(`Usage: ryoku-install [options]

Interactive options:
  --flake PATH[#HOST]   NixOS flake to configure (default: /etc/nixos)
  --source REF          Ryoku flake reference
  --iso                 Full disk installation mode used by the Ryoku ISO
  --no-cache            Install without the Ryotunes Cachix binary cache
  --dry-run             Run the backend without writing files or disks
  snapshot              Print representative screens without installing

Automation / compatibility:
  --cli ...             Run ryoku-install-backend directly
  -y, --yes             Also selects the direct backend path
  --disk/--filesystem/--hostname/--username/--timezone/--locale/--keyboard/--kernel/--gpu/--firmware/--config-mode/--import-flake/--import-host/--confirm-disk
                        are accepted by the direct ISO backend
  --compositor/--browser/--shell/--apps are accepted by the direct backend`)
}

func parseOptions(args []string) (options, bool, []string, error) {
	o := defaultOptions()
	direct := false
	var backendArgs []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch a {
		case "--cli":
			direct = true
		case "--iso":
			o.iso = true
			backendArgs = append(backendArgs, a)
		case "-y", "--yes":
			direct = true
			backendArgs = append(backendArgs, a)
		case "--flake", "--source":
			if i+1 >= len(args) {
				return o, false, nil, fmt.Errorf("%s requires a value", a)
			}
			v := args[i+1]
			i++
			backendArgs = append(backendArgs, a, v)
			if a == "--flake" {
				o.flake = v
			} else {
				o.source = v
				o.sourceExplicit = true
			}
		case "--no-cache":
			o.noCache = true
			backendArgs = append(backendArgs, a)
		case "--dry-run":
			o.dryRun = true
			backendArgs = append(backendArgs, a)
		case "--compositor", "--browser", "--shell", "--apps", "--disk", "--filesystem", "--hostname", "--username", "--timezone", "--locale", "--keyboard", "--kernel", "--gpu", "--firmware", "--config-mode", "--import-flake", "--import-host", "--confirm-disk":
			if i+1 >= len(args) {
				return o, false, nil, fmt.Errorf("%s requires a value", a)
			}
			direct = true
			v := args[i+1]
			i++
			backendArgs = append(backendArgs, a, v)
		case "-h", "--help":
			usage()
			os.Exit(0)
		default:
			return o, false, nil, fmt.Errorf("unknown option %s", a)
		}
	}
	return o, direct, backendArgs, nil
}
func execBackend(args []string) error {
	bin := backendPath()
	path, err := exec.LookPath(bin)
	if err != nil {
		return err
	}
	return syscall.Exec(path, append([]string{path}, args...), os.Environ())
}
func snapshot(opts options) {
	m := newModel(opts)
	m.w, m.h = 112, 40
	fmt.Println("### welcome ###\n" + m.render())
	m.state = "wizard"
	for i := range flow {
		m.idx = i
		m.setCursorForStep()
		fmt.Printf("\n### %s ###\n%s\n", flow[i].key, m.render())
	}
	m.state = "install"
	m.installAt = 2
	m.installLog = []string{"Updating flake lock...", "evaluating NixOS configuration", "building Ryoku shell and compositor providers"}
	fmt.Println("\n### install ###\n" + m.render())
	m.state = "done"
	fmt.Println("\n### done ###\n" + m.render())
}
func main() {
	initGlyphs()
	if len(os.Args) > 1 && os.Args[1] == "snapshot" {
		snapshot(defaultOptions())
		return
	}
	opts, direct, args, err := parseOptions(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, "ryoku-install:", err)
		os.Exit(2)
	}
	if direct {
		if err := execBackend(args); err != nil {
			fmt.Fprintln(os.Stderr, "ryoku-install:", err)
			os.Exit(1)
		}
		return
	}
	if os.Getenv("TERM") == "dumb" {
		fmt.Fprintln(os.Stderr, "ryoku-install: TERM=dumb; use --cli for the non-interactive backend")
		os.Exit(2)
	}
	var fm tea.Model
	if opts.iso {
		fm, err = tea.NewProgram(newISOModel(opts)).Run()
	} else {
		fm, err = tea.NewProgram(newModel(opts)).Run()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ryoku-install:", err)
		os.Exit(1)
	}
	if result, ok := fm.(model); ok && result.err != nil {
		os.Exit(1)
	}
	if result, ok := fm.(isoModel); ok && result.err != nil {
		os.Exit(1)
	}
}
