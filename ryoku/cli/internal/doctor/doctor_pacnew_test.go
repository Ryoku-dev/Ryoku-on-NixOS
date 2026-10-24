package doctor

import (
	"testing"
	"time"
)

// classifyPacnew must auto-resolve only the provably safe cases: bytes identical
// to the live file, or a pacman.conf whose sole difference is the [ryoku] repo
// stanza the installer appends. everything else is a genuine conflict.
func TestClassifyPacnew(t *testing.T) {
	const stockPacman = "[options]\nHoldPkg = pacman glibc\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n"
	liveWithRyoku := stockPacman + "\n[ryoku]\nSigLevel = Required\nServer = https://repo.ryoku.dev/stable/$arch\n"

	cases := []struct {
		name   string
		path   string
		live   string
		pacnew string
		want   pacnewOutcome
	}{
		{"identical bytes", "/etc/foo.conf", "a=1\n", "a=1\n", pacnewIdentical},
		{"pacman.conf only ryoku stanza", "/etc/pacman.conf", liveWithRyoku, stockPacman, pacnewRyokuOnly},
		{"pacman.conf with a real [options] edit", "/etc/pacman.conf", "[options]\nParallelDownloads = 5\nHoldPkg = pacman glibc\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[ryoku]\nSigLevel = Required\nServer = x\n", stockPacman, pacnewConflict},
		{"non-pacman modified file", "/etc/hosts", "127.0.1.1 box\n", "# stock\n", pacnewConflict},
		{"pacman.conf real base change", "/etc/pacman.conf", liveWithRyoku, stockPacman + "[extra]\nInclude = /etc/pacman.d/mirrorlist\n", pacnewConflict},
		{"locale.gen configured, template re-shipped with a new locale", "/etc/locale.gen",
			"# header\n#af_ZA.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n",
			"# header\n#af_ZA.UTF-8 UTF-8\n#en_US.UTF-8 UTF-8\n#hrx_BR.UTF-8 UTF-8\n", pacnewLocaleGen},
		{"locale.gen with nothing active is left for review", "/etc/locale.gen",
			"# header\n#en_US.UTF-8 UTF-8\n", "# header\n#en_US.UTF-8 UTF-8\n#hrx_BR.UTF-8 UTF-8\n", pacnewConflict},
	}
	for _, c := range cases {
		if got := classifyPacnew(c.path, []byte(c.live), []byte(c.pacnew)); got != c.want {
			t.Errorf("%s: classifyPacnew = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestStripRyokuRepoStanza(t *testing.T) {
	const base = "[options]\nHoldPkg = pacman\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n"
	// appended at EOF (the installer's shape): the whole stanza plus its blank
	// separator must go, leaving the base untouched.
	appended := base + "\n[ryoku]\nSigLevel = Required\nServer = https://repo.ryoku.dev/stable/$arch\n"
	if got := string(trimTrailing(stripRyokuRepoStanza([]byte(appended)))); got != string(trimTrailing([]byte(base))) {
		t.Errorf("appended stanza not stripped cleanly:\n%q", got)
	}
	// a section after [ryoku] survives (only the stanza's own lines are removed).
	withTail := base + "\n[ryoku]\nSigLevel = Required\nServer = x\n[custom]\nServer = y\n"
	wantTail := base + "[custom]\nServer = y\n"
	if got := string(trimTrailing(stripRyokuRepoStanza([]byte(withTail)))); got != string(trimTrailing([]byte(wantTail))) {
		t.Errorf("section after [ryoku] not preserved:\n%q", got)
	}
}

// A config is replaced by its .pacnew only when nothing on this box has
// written it: older than the box's first pacman transaction.
func TestUntouchedSinceInstall(t *testing.T) {
	installed := time.Date(2026, 6, 17, 16, 10, 8, 0, time.UTC)
	cases := []struct {
		name  string
		mtime time.Time
		at    time.Time
		want  bool
	}{
		{"shipped by an older package", time.Date(2024, 9, 13, 21, 29, 0, 0, time.UTC), installed, true},
		{"written by the installer", installed.Add(3 * time.Minute), installed, false},
		{"edited later", time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC), installed, false},
		{"install time unknown", time.Date(2024, 9, 13, 0, 0, 0, 0, time.UTC), time.Time{}, false},
	}
	for _, c := range cases {
		if got := untouchedSinceInstall(c.mtime, c.at); got != c.want {
			t.Errorf("%s: untouchedSinceInstall = %v, want %v", c.name, got, c.want)
		}
	}
}
