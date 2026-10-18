package doctor

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: one launcher entry per app ---------------------------------
//
// Ryoku ships ryoku-nvim.desktop, which opens Neovim in the terminal role, while
// the neovim package ships nvim.desktop under the same name, so every launcher
// and app grid listed Neovim twice. A user-level copy of the package's entry
// with NoDisplay=true hides it everywhere and keeps its MIME handling. The copy
// is written once and ledgered: a user who deletes it gets the package's entry
// back for good.

type supersededLauncher struct {
	upstream string // the distribution package's desktop id
	ryoku    string // the Ryoku entry that replaces it in launchers
}

var supersededLaunchers = []supersededLauncher{
	{upstream: "nvim.desktop", ryoku: "ryoku-nvim.desktop"},
}

func launcherOverrideLedger() string {
	return filepath.Join(sys.StateDir(), "launcher-overrides")
}

// applicationDirs lists the XDG application directories, highest precedence
// first: the user's, then every XDG_DATA_DIRS entry.
func applicationDirs() (user string, system []string) {
	user = filepath.Join(sys.Xdg("XDG_DATA_HOME", ".local/share"), "applications")
	dataDirs := os.Getenv("XDG_DATA_DIRS")
	if dataDirs == "" {
		dataDirs = "/usr/local/share:/usr/share"
	}
	seen := map[string]bool{}
	for _, d := range strings.Split(dataDirs, ":") {
		if d == "" || seen[d] {
			continue
		}
		seen[d] = true
		system = append(system, filepath.Join(d, "applications"))
	}
	return user, system
}

func firstEntry(dirs []string, id string) string {
	for _, d := range dirs {
		if p := filepath.Join(d, id); sys.Exists(p) {
			return p
		}
	}
	return ""
}

func readLedger(path string) map[string]bool {
	ids := map[string]bool{}
	b, err := os.ReadFile(path)
	if err != nil {
		return ids
	}
	for _, ln := range strings.Split(string(b), "\n") {
		if ln = strings.TrimSpace(ln); ln != "" {
			ids[ln] = true
		}
	}
	return ids
}

// hiddenEntry returns the desktop entry with NoDisplay=true set in its
// [Desktop Entry] group and every other line kept.
func hiddenEntry(src []byte) []byte {
	var out bytes.Buffer
	group := ""
	sc := bufio.NewScanner(bytes.NewReader(src))
	for sc.Scan() {
		ln := sc.Text()
		trimmed := strings.TrimSpace(ln)
		if strings.HasPrefix(trimmed, "[") && strings.HasSuffix(trimmed, "]") {
			group = trimmed
			out.WriteString(ln + "\n")
			if group == "[Desktop Entry]" {
				out.WriteString("NoDisplay=true\n")
			}
			continue
		}
		if group == "[Desktop Entry]" && strings.HasPrefix(trimmed, "NoDisplay=") {
			continue
		}
		out.WriteString(ln + "\n")
	}
	return out.Bytes()
}

func reconcileLauncherDuplicates(checkOnly bool) recResult {
	user, system := applicationDirs()
	ledgerPath := launcherOverrideLedger()
	ledger := readLedger(ledgerPath)
	var pending []supersededLauncher
	for _, s := range supersededLaunchers {
		if firstEntry(append([]string{user}, system...), s.ryoku) == "" {
			continue
		}
		if firstEntry(system, s.upstream) == "" || sys.Exists(filepath.Join(user, s.upstream)) || ledger[s.upstream] {
			continue
		}
		pending = append(pending, s)
	}
	if len(pending) == 0 {
		return okRes(i18n.T("every app has one launcher entry"))
	}
	names := make([]string, len(pending))
	for i, s := range pending {
		names[i] = s.upstream
	}
	if checkOnly {
		return wouldRes(i18n.T("launchers list these apps twice: %s"), strings.Join(names, ", ")).
			withFix(i18n.T("ryoku doctor hides the package's duplicate entry"))
	}
	if err := os.MkdirAll(user, 0o755); err != nil {
		return failRes(i18n.T("could not create %s: %v"), tildeOf(user), err)
	}
	var lines []string
	for _, s := range pending {
		src, err := os.ReadFile(firstEntry(system, s.upstream))
		if err != nil {
			return failRes(i18n.T("could not read %s: %v"), s.upstream, err)
		}
		dst := filepath.Join(user, s.upstream)
		if err := os.WriteFile(dst, hiddenEntry(src), 0o644); err != nil {
			return failRes(i18n.T("could not write %s: %v"), tildeOf(dst), err)
		}
		lines = append(lines, s.upstream)
	}
	if err := os.MkdirAll(filepath.Dir(ledgerPath), 0o755); err != nil {
		return failRes(i18n.T("could not create %s: %v"), tildeOf(filepath.Dir(ledgerPath)), err)
	}
	f, err := os.OpenFile(ledgerPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return failRes(i18n.T("could not record %s: %v"), tildeOf(ledgerPath), err)
	}
	defer f.Close()
	for _, id := range lines {
		if _, err := fmt.Fprintln(f, id); err != nil {
			return failRes(i18n.T("could not record %s: %v"), tildeOf(ledgerPath), err)
		}
	}
	return fixedRes(i18n.T("hid the duplicate launcher entries: %s"), strings.Join(names, ", "))
}
