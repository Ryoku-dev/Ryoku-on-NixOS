package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"

	i18n "ryoku-i18n"
)

// Recordings land in one directory. The shell and the Hub both resolve the Hub's
// `directory` setting; this keeps the parts that are not config in step with it,
// so a user's clips are never split across folders: the target directory exists,
// and a sink another recorder wrote is surfaced with the command to merge it
// rather than left as a silent second pile.

// recordingsDir resolves the one directory, in the same order as
// ryoku-cmd-record's recordings_dir() and Ryoku.Ui.Singletons.Paths.
func recordingsDir() string {
	if v := strings.TrimSpace(os.Getenv("RYOKU_SHELL_RECORDINGS_DIR")); v != "" {
		return v
	}
	if v := configuredRecordingsDir(); v != "" {
		return v
	}
	return filepath.Join(videosDir(), "Recordings")
}

func configuredRecordingsDir() string {
	b, err := os.ReadFile(filepath.Join(configHome(), "ryoku", "recording.json"))
	if err != nil {
		return ""
	}
	var doc struct {
		Directory string `json:"directory"`
	}
	if json.Unmarshal(b, &doc) != nil {
		return ""
	}
	d := strings.TrimSpace(doc.Directory)
	if strings.HasPrefix(d, "~/") {
		d = filepath.Join(homeDir(), d[2:])
	}
	return d
}

func videosDir() string {
	if v := strings.TrimSpace(os.Getenv("XDG_VIDEOS_DIR")); v != "" {
		return v
	}
	return filepath.Join(homeDir(), "Videos")
}

func homeDir() string { return os.Getenv("HOME") }

func configHome() string {
	if v := os.Getenv("XDG_CONFIG_HOME"); v != "" {
		return v
	}
	return filepath.Join(homeDir(), ".config")
}

// reconcileRecordingsDir keeps the one directory real. A directory that is not
// ours is only reported, since a user may be running that recorder deliberately.
func reconcileRecordingsDir(checkOnly bool) recResult {
	home := homeDir()
	if home == "" {
		return okRes(i18n.T("no HOME; nothing to reconcile"))
	}
	dir := recordingsDir()

	var did []string

	// The target has to exist before anything resolves against it.
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		if checkOnly {
			return wouldRes(i18n.T("recordings directory %s is missing"), tildeOf(dir))
		}
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return failRes(i18n.T("could not create %s: %v"), tildeOf(dir), err)
		}
		did = append(did, i18n.Tf("created %s", tildeOf(dir)))
	}

	// Someone else's directory. On the dev box this is the reference shell's
	// convention, which Ryoku explicitly refused (see MenuCapture.qml), but on a
	// user's machine it could be any recorder they run on purpose. Reported with
	// the command to merge it, never migrated: moving files Ryoku did not write
	// is the user's call.
	stray := filepath.Join(videosDir(), "ScreenRecordings")
	if entries, err := os.ReadDir(stray); err == nil && len(entries) > 0 {
		return noteRes(i18n.T("%d recording(s) from another recorder sit in %s, outside %s"),
			len(entries), tildeOf(stray), tildeOf(dir)).
			withFix("mv " + tildeOf(stray) + "/* " + tildeOf(dir) + "/ && rmdir " + tildeOf(stray))
	}

	if len(did) > 0 {
		return fixedRes("%s", strings.Join(did, "; "))
	}
	return okRes(i18n.T("everything records into %s"), tildeOf(dir))
}

// tildeOf shortens a path under HOME for the report.
func tildeOf(p string) string {
	if h := homeDir(); h != "" && strings.HasPrefix(p, h+"/") {
		return "~" + p[len(h):]
	}
	return p
}
