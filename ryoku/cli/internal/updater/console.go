package updater

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"
	"unsafe"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// The update console is the one thing `ryoku update` prints. Everything the
// run's helpers and children write goes to the raw log (capture.go); the
// terminal gets a header, one settled line per step with what it found, a live
// line for the step in flight, a progress bar, and a closing card that says
// how it went and where the full log is. `ryoku update -v` skips all of it and
// streams the raw output instead.
//
// Three modes: live (a terminal: animated, redrawn in place), plain (stdout is
// a pipe, or the Hub drives the run: the same narrative as plain lines, no
// escapes), and verbose (raw passthrough; only the step headers and the
// closing card are ours).

type conMode int

const (
	conVerbose conMode = iota
	conPlain
	conLive
)

type noteKind int

const (
	noteInfo noteKind = iota
	noteOK
	noteWarn
	noteErr
)

type conNote struct {
	kind noteKind
	text string
}

type conStep struct {
	key, label string
	state      stepState
	began      time.Time
	took       time.Duration
	meta       string
	printed    bool
	open       bool
	pieces     int
	pieceLabel string
}

// errStopped is the failure a signal-driven stop records.
var errStopped = errors.New("stopped by request")

// noteCap bounds what one step leaves on screen; the rest is in the log.
const noteCap = 6

type console struct {
	mu      sync.Mutex
	mode    conMode
	w       io.Writer // every byte the console prints goes through here
	tty     *os.File  // the terminal itself, for size and mode queries
	color   bool
	cap     *capture
	started time.Time
	channel string
	release string
	footer  func() string
	steps   []conStep
	cur     int
	notes   []conNote
	hidden  int
	seen    map[string]bool
	latest  string
	watch   watchState
	tail    []string
	frame   int
	live    int
	paused  bool
	held    bool
	closed  bool
	failed  bool
	stop    chan struct{}
	done    chan struct{}
}

// con is this process's console; nil outside an update, where every method is
// a no-op (or a plain print, for narration).
var con *console

// openConsole starts the console for an update. channel and release head the
// view; footer, called at the end, names what the box now runs.
func openConsole(verbose bool, channel, release string, footer func() string) *console {
	c := &console{
		mode: conVerbose, w: os.Stdout, tty: os.Stdout, color: sys.StdoutIsTTY() && os.Getenv("NO_COLOR") == "",
		channel: channel, release: release, footer: footer, cur: -1, seen: map[string]bool{},
		started: time.Now(),
	}
	if verbose || updateLogFile == nil {
		return c
	}
	c.cap = startCapture(updateLogFile, c.captured)
	if c.cap == nil {
		return c
	}
	c.tty = c.cap.term
	c.w = c.tty
	tty := isTerminal(c.tty)
	c.color = tty && os.Getenv("NO_COLOR") == ""
	switch {
	case tty && updateUI() != "hub" && os.Getenv("TERM") != "dumb":
		c.mode = conLive
		// sudo runs its command on a pty of its own and switches this
		// terminal to raw mode until it returns, output processing included:
		// a bare "\n" then moves down without going back to column 0, every
		// redraw lands mid-row, wraps, and strands a copy of the step line.
		// The console says what it means instead of trusting the tty.
		c.w = crlfWriter{c.tty}
		c.stop, c.done = make(chan struct{}), make(chan struct{})
		fmt.Fprint(c.w, "\033[?25l")
		go c.animate()
	default:
		c.mode = conPlain
	}
	return c
}

// crlfWriter writes every line ending as "\r\n", so the view lays out the same
// whether or not the terminal is translating newlines at that moment.
type crlfWriter struct{ f *os.File }

func (w crlfWriter) Write(p []byte) (int, error) {
	if _, err := w.f.Write(bytes.ReplaceAll(p, []byte("\n"), []byte("\r\n"))); err != nil {
		return 0, err
	}
	return len(p), nil
}

func isTerminal(f *os.File) bool {
	var t syscall.Termios
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), syscall.TCGETS, uintptr(unsafe.Pointer(&t)))
	return e == 0
}

func (c *console) width() int {
	var ws struct{ row, col, x, y uint16 }
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, c.tty.Fd(), syscall.TIOCGWINSZ, uintptr(unsafe.Pointer(&ws))); e == 0 && ws.col > 0 {
		return int(ws.col)
	}
	return 80
}

// inner is the content width the view lays out to: the terminal less a two
// column margin, never wider than reads comfortably.
func (c *console) inner() int {
	w := c.width() - 4
	if w > 76 {
		w = 76
	}
	if w < 30 {
		w = 30
	}
	return w
}

// --- colour -----------------------------------------------------------------

func (c *console) rgb(r, g, b int, s string) string {
	if !c.color {
		return s
	}
	return fmt.Sprintf("\033[38;2;%d;%d;%dm%s\033[0m", r, g, b, s)
}

func (c *console) sgr(code, s string) string {
	if !c.color {
		return s
	}
	return "\033[" + code + "m" + s + "\033[0m"
}

func (c *console) brand(s string) string { return c.rgb(242, 86, 35, s) }
func (c *console) green(s string) string { return c.rgb(152, 195, 121, s) }
func (c *console) amber(s string) string { return c.rgb(229, 181, 103, s) }
func (c *console) red(s string) string   { return c.rgb(224, 108, 117, s) }
func (c *console) dim(s string) string   { return c.sgr("2", s) }
func (c *console) bold(s string) string  { return c.sgr("1", s) }

// ramp colours s cell by cell along Ryoku's vermilion-to-amber ramp.
func (c *console) ramp(s string, from, span int) string {
	if !c.color {
		return s
	}
	var b strings.Builder
	i := 0
	for _, r := range s {
		t := 0.0
		if span > 1 {
			t = float64(from+i) / float64(span-1)
		}
		if t > 1 {
			t = 1
		}
		fmt.Fprintf(&b, "\033[38;2;%d;%d;%dm%c", 242+int(t*(229-242)), 86+int(t*(181-86)), 35+int(t*(103-35)), r)
		i++
	}
	b.WriteString("\033[0m")
	return b.String()
}

// --- layout helpers ---------------------------------------------------------

// clip shortens s to at most n runes, marking the cut. pure.
func clip(s string, n int) string {
	if n <= 1 || utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return string(r[:n-1]) + "…"
}

func pad(n int) string {
	if n < 1 {
		return " "
	}
	return strings.Repeat(" ", n)
}

// span lays out left and right across width: right flush to the edge, left
// clipped so the two never touch. Both are plain text; paint applies after.
func span(left, right string, width int) (string, string, int) {
	lw := width - utf8.RuneCountInString(right) - 2
	left = clip(left, lw)
	return left, right, width - utf8.RuneCountInString(left) - utf8.RuneCountInString(right)
}

type pieceLineLayout struct {
	branch string
	glyph  string
	label  string
	right  string
	gap    int
}

func (l pieceLineLayout) text() string {
	return "     " + l.branch + " " + l.glyph + "  " + l.label + pad(l.gap) + l.right
}

// layoutPieceLine keeps the status at the right edge and gives the label
// whatever remains. Compiler names can be long, but the useful timing must
// stay visible on a narrow terminal.
func layoutPieceLine(branch, glyph, label, right string, width int) pieceLineLayout {
	prefixText := "     " + branch + " " + glyph + "  "
	prefix := utf8.RuneCountInString(prefixText)
	room := width - prefix - utf8.RuneCountInString(right) - 2
	switch {
	case room <= 0:
		label = ""
	case utf8.RuneCountInString(label) > room:
		if room == 1 {
			label = "…"
		} else {
			label = clip(label, room)
		}
	}
	left, right, gap := span(prefixText+label, right, width)
	label = strings.TrimPrefix(left, prefixText)
	return pieceLineLayout{branch: branch, glyph: glyph, label: label, right: right, gap: gap}
}

func closingPieceLine(state stepState, count int, label, right string, width int) pieceLineLayout {
	glyph := "✓"
	text := fmt.Sprintf(i18n.T("%d pieces built"), count)
	switch state {
	case stepSkipped:
		glyph = "–"
	case stepFailed:
		glyph = "✗"
		text = fmt.Sprintf(i18n.T("stopped while building %s"), label)
	}
	return layoutPieceLine("╰─", glyph, text, right, width)
}

// human renders a duration the way a person reads one: 0.8s, 42s, 3m 05s.
func human(d time.Duration) string {
	switch {
	case d < 10*time.Second:
		return fmt.Sprintf("%.1fs", d.Seconds())
	case d < time.Minute:
		return fmt.Sprintf("%ds", int(d.Seconds()))
	case d < time.Hour:
		return fmt.Sprintf("%dm %02ds", int(d.Minutes()), int(d.Seconds())%60)
	}
	return fmt.Sprintf("%dh %02dm", int(d.Hours()), int(d.Minutes())%60)
}

func tildePath(p string) string {
	if home, err := os.UserHomeDir(); err == nil && home != "" && strings.HasPrefix(p, home+"/") {
		return "~" + p[len(home):]
	}
	return p
}

// --- the live region --------------------------------------------------------

// clearLive erases the animated lines so a permanent one can print above them.
// The caller holds the lock.
func (c *console) clearLive() {
	if c.live == 0 {
		return
	}
	fmt.Fprint(c.w, "\r")
	if c.live > 1 {
		fmt.Fprintf(c.w, "\033[%dA", c.live-1)
	}
	fmt.Fprint(c.w, "\033[J")
	c.live = 0
}

// println prints one permanent line above the live region. The caller holds
// the lock.
func (c *console) println(line string) {
	if c.mode == conLive {
		c.clearLive()
	}
	fmt.Fprintln(c.w, line)
}

func (c *console) animate() {
	defer close(c.done)
	t := time.NewTicker(100 * time.Millisecond)
	defer t.Stop()
	for {
		select {
		case <-c.stop:
			return
		case <-t.C:
			frac := progress.currentFraction()
			pieces := progress.currentPieces()
			c.mu.Lock()
			if !c.paused && !c.closed {
				c.frame++
				c.drawLive(frac, pieces)
			}
			c.mu.Unlock()
		}
	}
}

var spinFrames = []rune("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")

// inner removes four terminal columns, so 56 is the compact-view boundary for
// a 60-column terminal.
const (
	pieceBarMinInner = 56
	pieceBarCells    = 14
	pieceBarBlank    = "              "
)

// drawLive redraws the work in flight and the overall bar. The caller holds
// the lock.
func (c *console) drawLive(frac float64, v pieceView) {
	if c.mode != conLive || c.held {
		return
	}
	in := c.inner()
	overall := "  " + c.bar(frac, in-18) + "  " + c.bold(fmt.Sprintf("%3d%%", int(frac*100+0.5))) + c.dim("  ·  "+human(time.Since(c.started)))
	if c.cur >= 0 && c.steps[c.cur].open {
		if v.Step == c.steps[c.cur].key && v.Running >= 0 && v.Running < len(v.Pieces) {
			p := v.Pieces[v.Running]
			elapsed := time.Duration(0)
			if p.Began > 0 {
				elapsed = time.Since(time.UnixMilli(p.Began))
				if elapsed < 0 {
					elapsed = 0
				}
			}
			gauge := p.Frac
			if gauge <= 0 && p.Typical > 0 {
				gauge = min(0.95, float64(elapsed)/float64(time.Duration(p.Typical)*time.Millisecond))
			}
			showProgress := p.Frac > 0 || p.Typical > 0
			times := human(elapsed)
			if p.Typical > 0 {
				times += " / ~" + human(time.Duration(p.Typical)*time.Millisecond)
			}
			right, paintedRight := times, c.dim(times)
			if showProgress {
				percent := fmt.Sprintf("%3d%%", int(gauge*100+0.5))
				right, paintedRight = percent+"  "+times, c.bold(percent)+"  "+c.dim(times)
				if in >= pieceBarMinInner {
					right = pieceBarBlank + "  " + right
					paintedRight = c.bar(gauge, pieceBarCells) + "  " + paintedRight
				}
			}
			line := layoutPieceLine("├─", string(spinFrames[c.frame%len(spinFrames)]), p.Label, right, in)
			pieceLine := "     " + c.dim(line.branch+" ") + c.brand(line.glyph) + "  " + c.bold(line.label) + pad(line.gap) + paintedRight
			detail := p.Detail
			if detail == "" {
				detail = p.Note
			}
			if detail == "" {
				detail = i18n.T("starting…")
			}
			lines := []string{pieceLine, "     " + c.dim("│       "+clip(detail, in-13)), "", overall}
			c.redraw(lines)
			return
		}
		// The permanent header stands for the step even in the short gap
		// between one compiler finishing and the next one starting.
		c.redraw([]string{"", "", overall})
		return
	}

	label, took := i18n.T("Starting"), ""
	if c.cur >= 0 {
		s := c.steps[c.cur]
		label, took = s.label, human(time.Since(s.began))
	}
	l, r, gap := span(label, took, in-4)
	spin := string(spinFrames[c.frame%len(spinFrames)])
	lines := []string{"  " + c.brand(spin) + "  " + c.bold(l) + pad(gap) + c.dim(r)}

	detail, tone := c.latest, 0
	switch c.watch.State {
	case "stalled":
		detail, tone = fmt.Sprintf(i18n.T("no progress for %s · %s · Ctrl-C stops the update"), human(time.Duration(c.watch.Quiet)*time.Second), c.watch.Current), 2
	case "quiet":
		if c.watch.Current != "" {
			detail = fmt.Sprintf(i18n.T("%s · quiet %s"), c.watch.Current, human(time.Duration(c.watch.Quiet)*time.Second))
		}
		tone = 1
	}
	if detail != "" {
		d := clip(detail, in-7)
		switch tone {
		case 2:
			d = c.amber(d)
		default:
			d = c.dim(d)
		}
		lines = append(lines, "     "+c.dim("╰─ ")+d)
	} else {
		lines = append(lines, "")
	}
	lines = append(lines, overall)
	c.redraw(lines)
}

// redraw replaces the complete animated region. Keeping this in one place
// makes c.live the exact number of terminal rows that clearLive walks back.
func (c *console) redraw(lines []string) {
	c.clearLive()
	// autowrap off for the redraw: a line that ever outgrows the terminal is
	// cut at its edge instead of pushing the region a row taller than the
	// count the next clear walks back over
	fmt.Fprint(c.w, "\033[?7l"+strings.Join(lines, "\n")+"\033[?7h")
	c.live = len(lines)
}

// bar draws a cells-wide gauge: the done part a vermilion-to-amber ramp ending
// in a half cell, the rest a faint rule.
func (c *console) bar(frac float64, cells int) string {
	if cells < 10 {
		cells = 10
	}
	if frac < 0 {
		frac = 0
	}
	if frac > 1 {
		frac = 1
	}
	full := int(frac * float64(cells))
	head := ""
	rest := cells - full
	if full < cells {
		head = "╸"
		rest--
	}
	return c.ramp(strings.Repeat("━", full)+head, 0, cells) + c.dim(strings.Repeat("─", rest))
}

// --- events -----------------------------------------------------------------

func (c *console) header() {
	in := c.inner()
	word := "R Y O K U"
	right := c.channel
	gap := in - utf8.RuneCountInString(word) - utf8.RuneCountInString(i18n.T("update")) - 4 - utf8.RuneCountInString(right)
	fmt.Fprintln(c.w)
	fmt.Fprintln(c.w, "  "+c.bold(c.ramp(word, 0, utf8.RuneCountInString(word)))+"  "+c.dim("·")+"  "+i18n.T("update")+pad(gap)+c.dim(right))
	fmt.Fprintln(c.w, "  "+c.ramp(strings.Repeat("─", in/3), 0, in/3)+c.dim(strings.Repeat("─", in-in/3)))
	if c.release != "" {
		fmt.Fprintln(c.w, "  "+c.dim(c.release))
	}
	fmt.Fprintln(c.w)
}

// begin lays out the run's steps; a resumed stage2 skips the header and the
// steps stage1 already printed.
func (c *console) begin(steps []runStep, resumed bool, started time.Time) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.steps = make([]conStep, len(steps))
	for i, s := range steps {
		c.steps[i] = conStep{key: s.Key, label: s.Label, state: s.State, took: time.Duration(s.Took) * time.Millisecond}
		c.steps[i].printed = resumed && s.State != stepPending
	}
	if !started.IsZero() {
		c.started = started
	}
	if resumed {
		return
	}
	switch c.mode {
	case conLive, conVerbose:
		c.header()
	case conPlain:
		fmt.Fprintf(c.w, "Ryoku update · %s\n", c.channel)
	}
}

func (c *console) index(key string) int {
	for i := range c.steps {
		if c.steps[i].key == key {
			return i
		}
	}
	return -1
}

// settleThrough prints every unprinted step before idx in order, the running
// one closed with its time and notes. The caller holds the lock.
func (c *console) settleThrough(idx int) {
	for i := range min(idx, len(c.steps)) {
		s := &c.steps[i]
		if s.printed {
			continue
		}
		if s.state == stepRunning || s.state == stepPending {
			if !s.began.IsZero() {
				s.took = time.Since(s.began)
			}
			s.state = stepDone
		}
		c.printStep(s, i == c.cur)
		if i == c.cur {
			c.printNotes()
		}
	}
}

// printStep prints a settled step line; own says whether the pending notes are
// this step's, so a warning among them marks it. The caller holds the lock.
func (c *console) printStep(s *conStep, own bool) {
	s.printed = true
	if c.mode == conPlain {
		switch s.state {
		case stepSkipped:
			fmt.Fprintf(c.w, "    %s: %s\n", s.label, i18n.T("skipped"))
		case stepFailed:
			fmt.Fprintf(c.w, "    %s: %s\n", s.label, i18n.T("failed"))
		}
		return
	}
	if s.open {
		warn := own && c.hasWarn()
		if own {
			c.printOpenNotes()
		}
		right := ""
		if s.took > 0 {
			right = human(s.took)
		}
		if s.state == stepSkipped {
			right = i18n.T("skipped")
		}
		label := s.pieceLabel
		if label == "" {
			label = s.label
		}
		line := closingPieceLine(s.state, s.pieces, label, right, c.inner())
		glyph := c.green(line.glyph)
		switch s.state {
		case stepSkipped:
			glyph = c.dim(line.glyph)
		case stepFailed:
			glyph = c.red(line.glyph)
		default:
			if warn {
				glyph = c.amber("!")
			}
		}
		text := line.label
		if s.state == stepSkipped {
			text = c.dim(text)
		}
		c.println("     " + c.dim(line.branch+" ") + glyph + "  " + text + pad(line.gap) + c.dim(line.right))
		return
	}
	glyph := c.green("✓")
	switch s.state {
	case stepSkipped:
		glyph = c.dim("–")
	case stepFailed:
		glyph = c.red("✗")
	default:
		if own && c.hasWarn() {
			glyph = c.amber("!")
		}
	}
	right := s.meta
	if s.took > 0 {
		if right != "" {
			right += "   "
		}
		right += human(s.took)
	}
	if s.state == stepSkipped {
		right = i18n.T("skipped")
	}
	l, r, gap := span(s.label, right, c.inner()-4)
	label := l
	if s.state == stepSkipped {
		label = c.dim(l)
	}
	c.println("  " + glyph + "  " + label + pad(gap) + c.dim(r))
}

func (c *console) hasWarn() bool {
	for _, n := range c.notes {
		if n.kind == noteWarn || n.kind == noteErr {
			return true
		}
	}
	return false
}

// printNotes prints and clears the running step's notes as a small tree under
// it. The caller holds the lock.
func (c *console) printNotes() {
	c.printNotesTree(true)
}

func (c *console) printOpenNotes() {
	c.printNotesTree(false)
}

func (c *console) printNotesTree(closeLast bool) {
	defer func() { c.notes, c.hidden = nil, 0 }()
	if c.mode == conPlain {
		return // plain mode printed each note as it came
	}
	n := len(c.notes)
	extra := ""
	if c.hidden > 0 {
		extra = fmt.Sprintf(i18n.T("+%d more in the log"), c.hidden)
	}
	in := c.inner()
	for i, note := range c.notes {
		branch := "├─ "
		if closeLast && i == n-1 && extra == "" {
			branch = "╰─ "
		}
		text := clip(note.text, in-9)
		switch note.kind {
		case noteWarn:
			text = c.amber("! ") + text
		case noteErr:
			text = c.red("✗ ") + text
		case noteOK:
			text = c.green("✓ ") + c.dim(text)
		default:
			text = c.dim(text)
		}
		c.println("     " + c.dim(branch) + text)
	}
	if extra != "" {
		branch := "╰─ "
		if !closeLast {
			branch = "├─ "
		}
		c.println("     " + c.dim(branch+extra))
	}
}

// enter starts the step key, settling the one before it on screen.
func (c *console) enter(key string) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	idx := c.index(key)
	if idx < 0 {
		return
	}
	c.settleThrough(idx)
	c.cur = idx
	c.steps[idx].state, c.steps[idx].began, c.steps[idx].printed = stepRunning, time.Now(), false
	c.latest, c.watch = "", watchState{}
	switch c.mode {
	case conPlain:
		fmt.Fprintf(c.w, "==> %s\n", c.steps[idx].label)
	case conVerbose:
		fmt.Fprintln(c.w)
		fmt.Fprintln(c.w, c.brand("==> ")+c.bold(c.steps[idx].label))
	}
}

// piecesOpen replaces the running step spinner with one permanent source-build
// header. The publisher calls without its lock held.
func (c *console) piecesOpen(v pieceView) {
	if c == nil || c.mode == conVerbose {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	i := c.index(v.Step)
	if i < 0 || c.steps[i].open {
		return
	}
	s := &c.steps[i]
	s.open = true
	if c.mode != conLive {
		return
	}
	right := i18n.T("building from source")
	if !v.First {
		right = fmt.Sprintf(i18n.T("%d pieces · usually %s"), len(v.Pieces), human(time.Duration(v.Typical)*time.Millisecond))
	}
	l, r, gap := span(s.label, right, c.inner()-4)
	c.println("  " + c.brand("◆") + "  " + c.bold(l) + pad(gap) + c.dim(r))
	// The first source build is the slow one. Said here, under the header,
	// it is read before the first bar moves; as a note it would surface
	// only when the step settles.
	if v.First {
		for _, line := range wrap(firstBuildExplainer(), c.inner()-9) {
			c.println("     " + c.dim("│  "+line))
		}
	}
}

// wrap breaks s into lines of at most n runes on word boundaries; a word
// longer than n stands on its own line.
func wrap(s string, n int) []string {
	if n < 10 {
		n = 10
	}
	var lines []string
	line := ""
	for _, word := range strings.Fields(s) {
		switch {
		case line == "":
			line = word
		case utf8.RuneCountInString(line)+1+utf8.RuneCountInString(word) <= n:
			line += " " + word
		default:
			lines = append(lines, line)
			line = word
		}
	}
	if line != "" {
		lines = append(lines, line)
	}
	return lines
}

// pieceSettled makes completed compiler work permanent above the live region.
// The publisher calls without its lock held.
func (c *console) pieceSettled(p piece) {
	if c == nil || c.mode == conVerbose {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.mode == conPlain {
		fmt.Fprintf(c.w, "    %s: %s\n", p.Label, human(time.Duration(p.Took)*time.Millisecond))
		return
	}
	if c.cur < 0 || !c.steps[c.cur].open {
		return
	}
	s := &c.steps[c.cur]
	if p.State == stepDone {
		s.pieces++
	}
	s.pieceLabel = p.Label
	right := human(time.Duration(p.Took) * time.Millisecond)
	glyph := c.green("✓")
	switch p.State {
	case stepSkipped:
		glyph = c.dim("–")
		right = i18n.T("skipped")
	case stepFailed:
		glyph = c.red("✗")
	}
	line := layoutPieceLine("├─", "✓", p.Label, right, c.inner())
	label := line.label
	if p.State == stepSkipped {
		label = c.dim(label)
	}
	c.println("     " + c.dim(line.branch+" ") + glyph + "  " + label + pad(line.gap) + c.dim(line.right))
}

func (c *console) skip(key string) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if i := c.index(key); i >= 0 {
		c.steps[i].state = stepSkipped
	}
}

func (c *console) snapshot(id string) {
	if c == nil || id == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if i := c.index("snapshot"); i >= 0 {
		c.steps[i].meta = "#" + id
	}
}

// note keeps a line under the running step (deduplicated, capped).
func (c *console) note(kind noteKind, text string) {
	if c == nil {
		fmt.Println(sys.Brand("▸") + " " + text)
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	switch c.mode {
	case conVerbose:
		fmt.Fprintln(c.w, c.brand("▸")+" "+text)
		return
	case conPlain:
		if !c.seen[text] {
			c.seen[text] = true
			prefix := "    "
			if kind == noteWarn {
				prefix = "    ! "
			} else if kind == noteErr {
				prefix = "    x "
			}
			fmt.Fprintln(c.w, prefix+text)
		}
		return
	}
	if c.seen[text] {
		return
	}
	c.seen[text] = true
	if c.cur < 0 {
		c.println("  " + c.dim("· ") + c.dim(text))
		return
	}
	c.latest = text
	if len(c.notes) >= noteCap {
		c.hidden++
		return
	}
	c.notes = append(c.notes, conNote{kind, text})
}

// loose prints narration made outside an update run (`ryoku track`).
func (c *console) loose(line string) {
	if c == nil || c.mode == conVerbose {
		fmt.Println(sys.Brand("▸") + " " + line)
		return
	}
	c.note(noteInfo, line)
}

// activity sets the live line without keeping it; with -v, where everything
// streams, it prints like the rest of the narrative.
func (c *console) activity(line string) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.latest = line
	if c.mode == conVerbose {
		fmt.Fprintln(c.w, c.dim("▸ "+line))
	}
}

func (c *console) watchUpdate(ws watchState) {
	if c == nil {
		return
	}
	c.mu.Lock()
	c.watch = ws
	c.mu.Unlock()
}

// captured is one line the run's output gained, from the capture tail. Our own
// narrative is mirrored into the log with a "▸ " mark and is skipped here; the
// rest feeds the live line, the run-state, the failure tail, and -- for the
// handful of shapes that matter -- the step's notes.
func (c *console) captured(line string) {
	if strings.HasPrefix(line, "▸ ") {
		return
	}
	marker := strings.HasPrefix(line, "::piece:: ")
	progress.observe(line)
	if marker {
		return
	}
	c.mu.Lock()
	c.tail = append(c.tail, line)
	if len(c.tail) > 8 {
		c.tail = c.tail[len(c.tail)-8:]
	}
	key := ""
	if c.cur >= 0 {
		key = c.steps[c.cur].key
	}
	c.latest = line
	c.mu.Unlock()
	if kind, text, ok := classifyCaptured(key, line); ok {
		c.note(kind, text)
	}
}

// classifyCaptured picks out the captured lines worth a note: a tool's own
// "error:", "warning:" and "note:" lines, a .pacnew left behind, the packages
// pacman names when it refuses a transaction (pacmanDetail), and, while the
// doctor runs, its findings. Everything else stays in the log. The doctor
// speaks its own format (a glyph, the check's name, then indented detail), so
// its output is read only that way: a finding's detail mentioning a .pacnew is
// part of the finding already on screen, not a second one. pure.
func classifyCaptured(step, line string) (noteKind, string, bool) {
	if step == "doctor" {
		switch {
		case strings.HasPrefix(line, "! "):
			return noteWarn, line[2:], true
		case strings.HasPrefix(line, "✗ "):
			return noteErr, strings.TrimPrefix(line, "✗ "), true
		case line == "✓ all checks passed":
			return noteOK, strings.TrimPrefix(line, "✓ "), true
		case strings.HasPrefix(line, "✓ ") && strings.HasSuffix(line, "(fixed)"):
			return noteOK, strings.TrimPrefix(line, "✓ "), true
		}
		return 0, "", false
	}
	low := strings.ToLower(line)
	switch {
	case strings.HasPrefix(low, "error:"):
		return noteErr, strings.TrimSpace(line[len("error:"):]), true
	case strings.HasPrefix(low, "warning:"):
		if strings.Contains(low, " is newer than ") {
			return 0, "", false
		}
		return noteWarn, strings.TrimSpace(line[len("warning:"):]), true
	case strings.HasPrefix(low, "note:"):
		return noteInfo, strings.TrimSpace(line[len("note:"):]), true
	case strings.Contains(low, ".pacnew"), strings.Contains(low, ".pacsave"):
		return noteWarn, line, true
	}
	if detail := pacmanDetail(line); detail != "" {
		return noteErr, detail, true
	}
	return 0, "", false
}

// hold stops the animation for the rest of the run: something we did not draw
// (a sudo prompt after the credential lapsed) may be waiting on the terminal.
func (c *console) hold() {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.mode == conLive && !c.held {
		c.clearLive()
		c.held = true
		fmt.Fprintln(c.w, "  "+c.amber("!")+"  "+i18n.T("sudo may ask for your password again below"))
	}
}

// ask puts a yes/no question on the terminal and returns the typed answer.
func (c *console) ask(question string) string {
	if c == nil || c.mode == conVerbose {
		fmt.Print(question + " ")
		return readAnswer()
	}
	c.mu.Lock()
	c.paused = true
	c.clearLive()
	fmt.Fprint(c.w, "\033[?25h  "+c.brand("?")+"  "+question+" ")
	c.mu.Unlock()
	answer := readAnswer()
	c.mu.Lock()
	if c.mode == conLive {
		fmt.Fprint(c.w, "\033[?25l")
	}
	c.paused = false
	c.mu.Unlock()
	return answer
}

func readAnswer() string {
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	return strings.ToLower(strings.TrimSpace(line))
}

// finish settles every step and prints the closing card.
func (c *console) finish() {
	if c == nil {
		return
	}
	c.cap.flush()
	c.mu.Lock()
	defer c.mu.Unlock()
	c.settleThrough(len(c.steps))
	c.clearLive()
	total := human(time.Since(c.started))
	what := ""
	if c.footer != nil {
		what = c.footer()
	}
	if c.mode == conPlain {
		fmt.Fprintf(c.w, "Update complete in %s. %s\nLog: %s\n", total, what, updateLogPath())
		return
	}
	in := c.inner()
	fmt.Fprintln(c.w)
	fmt.Fprintln(c.w, "  "+c.dim(strings.Repeat("─", in)))
	l, r, gap := span(i18n.T("Ryoku is up to date"), total, in-4)
	fmt.Fprintln(c.w, "  "+c.green("✓")+"  "+c.bold(l)+pad(gap)+c.dim(r))
	if what != "" {
		fmt.Fprintln(c.w, "     "+c.brand(clip(what, in-5)))
	}
	fmt.Fprintln(c.w, "     "+c.dim(i18n.T("log")+"  "+tildePath(updateLogPath())))
	fmt.Fprintln(c.w)
}

// fail settles the failed step and prints what broke, the last lines the work
// printed before it did, and the way back.
func (c *console) fail(err error, snap string) {
	if c == nil {
		return
	}
	c.cap.flush()
	c.mu.Lock()
	defer c.mu.Unlock()
	c.failed = true
	where := ""
	if c.cur >= 0 {
		s := &c.steps[c.cur]
		where = s.label
		c.settleThrough(c.cur)
		if !s.printed {
			if !s.began.IsZero() {
				s.took = time.Since(s.began)
			}
			s.state = stepFailed
			c.printStep(s, true)
			c.printNotes()
		}
	}
	c.clearLive()
	stopped := errors.Is(err, errStopped)
	if c.mode == conPlain {
		if stopped {
			fmt.Fprintf(c.w, "Update stopped.\nLog: %s\n", updateLogPath())
		} else {
			fmt.Fprintf(c.w, "Update failed: %v\nLog: %s\n", err, updateLogPath())
		}
		return
	}
	in := c.inner()
	total := human(time.Since(c.started))
	fmt.Fprintln(c.w)
	fmt.Fprintln(c.w, "  "+c.dim(strings.Repeat("─", in)))
	title, glyph := i18n.T("Update failed"), c.red("✗")
	if stopped {
		title, glyph = i18n.T("Update stopped"), c.amber("■")
	} else if where != "" {
		title = fmt.Sprintf(i18n.T("Update failed while %s"), strings.ToLower(where[:1])+where[1:])
	}
	l, r, gap := span(title, total, in-4)
	fmt.Fprintln(c.w, "  "+glyph+"  "+c.bold(l)+pad(gap)+c.dim(r))
	if !stopped {
		for _, ln := range strings.Split(sys.Wrap(err.Error(), in-5, ""), "\n") {
			fmt.Fprintln(c.w, "     "+ln)
		}
		if len(c.tail) > 0 && c.mode == conLive {
			fmt.Fprintln(c.w)
			fmt.Fprintln(c.w, "     "+c.dim(i18n.T("last output")))
			for _, ln := range c.tail {
				fmt.Fprintln(c.w, "     "+c.dim("│ "+clip(ln, in-7)))
			}
		}
	}
	fmt.Fprintln(c.w)
	fmt.Fprintln(c.w, "     "+c.dim(i18n.T("log")+"   ")+tildePath(updateLogPath()))
	if snap != "" {
		fmt.Fprintln(c.w, "     "+c.dim(i18n.T("undo")+"  ")+c.brand("ryoku rollback "+snap))
	}
	fmt.Fprintln(c.w)
}

// handoff ends this process's share of the view before the exec into the
// freshly installed binary: the step in flight settles on screen, and the
// terminal gets its descriptors back so stage2 can capture anew.
func (c *console) handoff() {
	if c == nil {
		return
	}
	c.cap.flush()
	c.mu.Lock()
	last := -1
	for i, s := range c.steps {
		if s.state != stepPending {
			last = i
		}
	}
	c.settleThrough(last + 1)
	c.mu.Unlock()
	c.close()
}

// reported says whether the closing failure card is on screen.
func (c *console) reported() bool {
	if c == nil {
		return false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.failed
}

// close stops the animation and returns the terminal. Safe to call twice.
func (c *console) close() {
	if c == nil {
		return
	}
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return
	}
	c.closed = true
	if c.mode == conLive {
		c.clearLive()
		fmt.Fprint(c.w, "\033[?25h")
	}
	c.mu.Unlock()
	if c.stop != nil {
		close(c.stop)
		<-c.done
	}
	c.cap.release()
}

// reportedError is an update failure the console already showed in full;
// main exits non-zero without repeating it.
type reportedError struct{ error }

func (reportedError) Reported() bool { return true }

func (e reportedError) Unwrap() error { return e.error }
