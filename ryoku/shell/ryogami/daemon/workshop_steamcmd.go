package main

import (
	"bufio"
	"context"
	"errors"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var (
	workshopDownloadStallTimeout   = 3 * time.Minute
	workshopDownloadOverallTimeout = 6 * time.Hour
	steamcmdCommandContext         = exec.CommandContext
)

func scanWorkshopCommand(
	ctx context.Context,
	cancel context.CancelFunc,
	cmd *exec.Cmd,
	sc *bufio.Scanner,
	onLine func([]byte),
) (bool, error, error) {
	activity := make(chan struct{}, 1)
	stalled := make(chan struct{})
	commandDone := make(chan struct{})
	watchdogDone := make(chan struct{})
	go func() {
		defer close(watchdogDone)
		timer := time.NewTimer(workshopDownloadStallTimeout)
		defer timer.Stop()
		for {
			select {
			case <-activity:
				if !timer.Stop() {
					select {
					case <-timer.C:
					default:
					}
				}
				timer.Reset(workshopDownloadStallTimeout)
			case <-timer.C:
				close(stalled)
				cancel()
				return
			case <-ctx.Done():
				return
			case <-commandDone:
				return
			}
		}
	}()

	for sc.Scan() {
		select {
		case activity <- struct{}{}:
		default:
		}
		onLine(sc.Bytes())
	}
	waitErr := cmd.Wait()
	close(commandDone)
	<-watchdogDone
	select {
	case <-stalled:
		return true, waitErr, sc.Err()
	default:
		return false, waitErr, sc.Err()
	}
}

// Helpers may spawn updaters; kill the group so an inherited pipe cannot hold the download open.
func prepareWorkshopCommand(cmd *exec.Cmd) {
	if cmd.SysProcAttr == nil {
		cmd.SysProcAttr = &syscall.SysProcAttr{}
	}
	cmd.SysProcAttr.Setpgid = true
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		if errors.Is(err, syscall.ESRCH) {
			return nil
		}
		return err
	}
}

func steamcmdInstalled() bool {
	_, err := exec.LookPath("steamcmd")
	return err == nil
}

func steamcmdArgs(username, installDir string, ids []string) []string {
	var args []string
	if installDir != "" {
		args = append(args, "+force_install_dir", installDir)
	}
	args = append(args, "+login")
	if username == "" {
		args = append(args, "anonymous")
	} else {
		args = append(args, username)
	}
	for _, id := range ids {
		args = append(args, "+workshop_download_item", workshopAppID, id)
	}
	args = append(args, "+quit")
	return args
}

// Installs alongside the existing library so the result reconciles in place.
func (w *workshopLib) steamInstallRoot() string {
	we := filepath.ToSlash(w.workshopDir())
	if strings.HasSuffix(we, "steamapps/workshop/content/"+workshopAppID) {
		root := w.workshopDir()
		for i := 0; i < 4; i++ {
			root = filepath.Dir(root)
		}
		return root
	}
	return w.steamRoot()
}

func (w *workshopLib) steamcmdDownload(item, requested string) error {
	d := w.d
	username := wkString(d.setting("steam.username"))
	installRoot := w.steamInstallRoot()

	ctx, cancel := context.WithTimeout(context.Background(), workshopDownloadOverallTimeout)
	defer cancel()
	cmd := steamcmdCommandContext(ctx, "steamcmd", steamcmdArgs(username, installRoot, []string{item})...)
	cmd.Stdin = nil
	prepareWorkshopCommand(cmd)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return workshopFetchFailure("error", "steamcmd output could not be read")
	}
	cmd.Stderr = cmd.Stdout
	if err := cmd.Start(); err != nil {
		return workshopFetchFailure("error", "steamcmd not found - install it, or open the item in Steam")
	}

	authError := false
	workshopFailure := false
	sc := bufio.NewScanner(stdout)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	stalled, waitErr, scanErr := scanWorkshopCommand(ctx, cancel, cmd, sc, func(raw []byte) {
		line := string(raw)
		if pct, ok := extractPercent(line); ok {
			msg := ""
			if item != requested {
				msg = "Downloading required Workshop item " + item
			}
			d.emitWorkshopDownload(requested, "downloading", pct, msg, "")
		}
		if isAuthError(line) {
			authError = true
		}
		if isSteamcmdWorkshopFailure(line) {
			workshopFailure = true
		}
	})

	dest := filepath.Join(installRoot, "steamapps", "workshop", "content", workshopAppID, item)
	reconcileWeItem(w.workshopDir(), item, dest)
	if dirExists(filepath.Join(w.workshopDir(), item)) {
		return nil
	}
	switch {
	case stalled:
		return workshopFetchFailure("error",
			"steamcmd stopped responding and was stopped - run "+steamcmdLoginCommand(username)+" once in a terminal, then retry")
	case errors.Is(ctx.Err(), context.DeadlineExceeded):
		return workshopFetchFailure("error", "steamcmd exceeded the six-hour download limit and was stopped")
	case authError || workshopFailure || username == "":
		return workshopFetchFailure("auth_error", steamcmdOwnershipMessage(username))
	case scanErr != nil:
		return workshopFetchFailure("error", "steamcmd output could not be read: "+scanErr.Error())
	case waitErr != nil:
		return workshopFetchFailure("error",
			"steamcmd exited before installing the item - run "+steamcmdLoginCommand(username)+" once in a terminal, then retry")
	default:
		return workshopFetchFailure("error", "steamcmd finished without installing the Workshop item")
	}
}

func steamcmdLoginCommand(username string) string {
	if username == "" {
		username = "<your-steam-username>"
	}
	return "steamcmd +login " + username + " +quit"
}

func steamcmdOwnershipMessage(username string) string {
	return "Wallpaper Engine Workshop downloads require a Steam account that owns Wallpaper Engine (app 431960). Set your Steam username in the picker's settings, then run " +
		steamcmdLoginCommand(username) + " once in a terminal"
}

func isSteamcmdWorkshopFailure(line string) bool {
	line = strings.ToLower(line)
	return strings.Contains(line, "download item ") && strings.Contains(line, " failed (")
}

func extractPercent(line string) (float64, bool) {
	pct := strings.IndexByte(line, '%')
	if pct < 0 {
		return 0, false
	}
	before := strings.TrimRight(line[:pct], " ")
	start := 0
	for i := len(before) - 1; i >= 0; i-- {
		c := before[i]
		if (c < '0' || c > '9') && c != '.' {
			start = i + 1
			break
		}
	}
	f, err := strconv.ParseFloat(before[start:], 64)
	if err != nil {
		return 0, false
	}
	return f / 100.0, true
}

func isAuthError(line string) bool {
	return strings.Contains(line, "Cached credentials not found") || strings.Contains(line, "Login Failure")
}
