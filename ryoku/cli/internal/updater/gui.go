package updater

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"

	i18n "ryoku-i18n"
)

// A Hub-driven update runs with no terminal window. `ryoku update --gui`
// returns at once, leaving a detached host that gives the real run a pseudo
// terminal: sudo keys its cached credential to a terminal, so one password,
// typed into the Hub, covers every escalation the run makes (the snapshot,
// pacman, the post snapshot) and the keepalive keeps it warm. Questions and
// that password come back through the run-state (runstate.go); the password
// itself travels over a FIFO, never through a file or an argv.

var nixGUIHostEnv = []string{
	"HOME",
	"USER",
	"LOGNAME",
	"PATH",
	"LANG",
	"LC_ALL",
	"XDG_RUNTIME_DIR",
	"XDG_CONFIG_HOME",
	"XDG_STATE_HOME",
	"XDG_CACHE_HOME",
	"DBUS_SESSION_BUS_ADDRESS",
	"RYOKU_UPDATE_BACKEND",
	"RYOKU_NIX_VERSION",
	"RYOKU_NIX_CHANNEL",
	"RYOKU_NIX_SYSTEM_BRIDGE",
	"RYOKU_NIX_INTEGRATION",
	"RYOKU_NIX_FLAKE",
	"RYOKU_NIX_INPUT",
	"RYOKU_NIX_HOST",
	"RYOKU_NIX_SUDO",
	"RYOKU_CONFIG_BASE",
	"RYOKU_I18N_DIR",
}

func nixGUIHostCommand(self string, args []string) *exec.Cmd {
	runner := strings.TrimSpace(os.Getenv("RYOKU_SYSTEMD_RUN"))
	if runner == "" {
		runner = "systemd-run"
	}

	runArgs := []string{
		"--user",
		"--quiet",
		"--collect",
		fmt.Sprintf("--unit=ryoku-update-gui-%d", os.Getpid()),
		"--service-type=exec",
		"--setenv=RYOKU_UPDATE_UI=hub",
	}

	for _, key := range nixGUIHostEnv {
		if value, ok := os.LookupEnv(key); ok && value != "" {
			runArgs = append(runArgs, "--setenv="+key+"="+value)
		}
	}

	runArgs = append(runArgs, self, "update", "--gui-host")
	runArgs = append(runArgs, args...)
	return exec.Command(runner, runArgs...)
}

func startNixGUIHost(self string, args []string) error {
	cmd := nixGUIHostCommand(self, args)
	out, err := cmd.CombinedOutput()
	if err == nil {
		return nil
	}

	detail := strings.TrimSpace(string(out))
	if detail == "" {
		return fmt.Errorf(i18n.T("could not start the update outside the Ryoku shell service: %w"), err)
	}
	return fmt.Errorf(i18n.T("could not start the update outside the Ryoku shell service: %w: %s"), err, detail)
}

// guiUpdate is `ryoku update --gui [--system]`: start the run in the
// background and return. On NixOS the background host must be a sibling
// transient user service, not a detached child of ryoku-shell.service.
func guiUpdate(args []string) error {
	if lockHeld() {
		return fmt.Errorf(i18n.T("another ryoku update is already running; wait for it to finish"))
	}
	self, err := os.Executable()
	if err != nil {
		return err
	}

	if nixBackend() {
		return startNixGUIHost(self, args)
	}

	null, err := os.OpenFile(os.DevNull, os.O_RDWR, 0)
	if err != nil {
		return err
	}
	defer null.Close()
	cmd := exec.Command(self, append([]string{"update", "--gui-host"}, args...)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = null, null, null
	cmd.Env = append(os.Environ(), "RYOKU_UPDATE_UI=hub")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf(i18n.T("could not start the update: %w"), err)
	}
	return cmd.Process.Release()
}

// lockHeld reports whether a `ryoku update` holds the run lock right now.
func lockHeld() bool {
	f, busy := acquireUpdateLock()
	if f != nil {
		f.Close()
	}
	return busy != nil
}

// guiHost is the detached parent of a Hub-driven run: it gives the run a
// pseudo terminal, drains it, and settles the run-state if the run dies
// without doing so itself (a crash, a kill), so the Hub never sits on a run
// that is gone.
func guiHost(args []string) error {
	master, slave, err := openPTY()
	if err != nil {
		writeState(runState{Phase: "error", PID: os.Getpid(), UI: "hub", Beat: nowMs(),
			Error: fmt.Sprintf(i18n.T("could not open a terminal for the update: %v"), err)})
		return err
	}
	self, err := os.Executable()
	if err != nil {
		return err
	}
	cmd := exec.Command(self, append([]string{"update"}, args...)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = slave, slave, slave
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true, Ctty: 0}
	if err := cmd.Start(); err != nil {
		slave.Close()
		master.Close()
		return err
	}
	slave.Close()
	go func() { _, _ = io.Copy(io.Discard, master) }()
	werr := cmd.Wait()
	master.Close()
	if st, ok := readState(); ok && st.PID == cmd.Process.Pid &&
		(st.Phase == "running" || st.Phase == "prompt" || st.Phase == "auth") {
		why := i18n.T("The update stopped before it finished.")
		if werr != nil {
			why = fmt.Sprintf(i18n.T("The update stopped before it finished (%v)."), werr)
		}
		clearOrphanedRun(st, why)
	}
	return nil
}

// openPTY opens a pseudo terminal pair, 120x40 so the run's output wraps
// sensibly.
func openPTY() (*os.File, *os.File, error) {
	master, err := os.OpenFile("/dev/ptmx", os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, nil, err
	}
	var unlock int32
	if err := ioctl(master.Fd(), syscall.TIOCSPTLCK, uintptr(unsafe.Pointer(&unlock))); err != nil {
		master.Close()
		return nil, nil, err
	}
	var n uint32
	if err := ioctl(master.Fd(), syscall.TIOCGPTN, uintptr(unsafe.Pointer(&n))); err != nil {
		master.Close()
		return nil, nil, err
	}
	slave, err := os.OpenFile(fmt.Sprintf("/dev/pts/%d", n), os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		master.Close()
		return nil, nil, err
	}
	ws := struct{ row, col, x, y uint16 }{40, 120, 0, 0}
	_ = ioctl(slave.Fd(), syscall.TIOCSWINSZ, uintptr(unsafe.Pointer(&ws)))
	return master, slave, nil
}

func ioctl(fd, req, arg uintptr) error {
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, fd, req, arg); e != 0 {
		return e
	}
	return nil
}

// errAuthCancelled ends a Hub-driven run the user declined to authorize.
var errAuthCancelled = errors.New("the update needs your password to install packages; it was not given")

// authorizeGUI caches the sudo credential for a Hub-driven run: a box that
// needs no password (NOPASSWD, a warm credential) is let straight through;
// otherwise the Hub asks, and `sudo -S -v` checks the answer, three tries,
// as sudo itself allows.
func authorizeGUI() error {
	if exec.Command("sudo", "-n", "-v").Run() == nil {
		return nil
	}
	title := i18n.T("Authorize the update")
	detail := i18n.T("Ryoku needs your password to take a snapshot and install packages.")
	if nixBackend() {
		detail = i18n.T("Ryoku needs your password to update the flake and switch the new NixOS generation.")
	}
	refused := ""
	for try := range 3 {
		// a fresh id per attempt, so the Hub can tell a second refusal from the first
		spec := &promptSpec{ID: fmt.Sprintf("sudo-%d", try+1), Kind: "secret", Title: title, Detail: detail, Error: refused}
		secret, ok := askSecret(spec, 15*time.Minute)
		if !ok {
			return errAuthCancelled
		}
		cmd := exec.Command("sudo", "-S", "-p", "", "-v")
		cmd.Stdin = strings.NewReader(secret + "\n")
		if cmd.Run() == nil {
			return nil
		}
		refused = i18n.T("That password was not accepted.")
	}
	return fmt.Errorf(i18n.T("the password was not accepted three times"))
}

func secretPath() string { return filepath.Join(runtimeDir(), "ryoku-update-secret") }

// askSecret publishes a secret prompt and waits for the Hub to answer over the
// FIFO. An empty answer is a cancel; so is the timeout.
func askSecret(spec *promptSpec, timeout time.Duration) (string, bool) {
	path := secretPath()
	_ = os.Remove(path)
	if err := syscall.Mkfifo(path, 0o600); err != nil {
		return "", false
	}
	defer os.Remove(path)
	progress.ask(spec)
	defer progress.resume()
	got := make(chan string, 1)
	go func() {
		f, err := os.OpenFile(path, os.O_RDONLY, 0)
		if err != nil {
			got <- ""
			return
		}
		b, _ := io.ReadAll(io.LimitReader(f, 4096))
		f.Close()
		got <- strings.TrimRight(string(b), "\r\n")
	}()
	select {
	case s := <-got:
		return s, s != ""
	case <-time.After(timeout):
		// open the write end ourselves so the reader's blocked open returns
		if f, err := os.OpenFile(path, os.O_WRONLY|syscall.O_NONBLOCK, 0); err == nil {
			f.Close()
		}
		<-got
		return "", false
	}
}

// deliverSecret is `ryoku update --auth [--cancel]`: hand the password the Hub
// read (one line on stdin) to the run waiting for it. It refuses anything at
// the FIFO path that is not a FIFO this user owns.
func deliverSecret(cancel bool) error {
	path := secretPath()
	var st syscall.Stat_t
	if err := syscall.Lstat(path, &st); err != nil || st.Mode&syscall.S_IFMT != syscall.S_IFIFO || int(st.Uid) != os.Getuid() {
		return fmt.Errorf(i18n.T("no update is waiting for a password"))
	}
	secret := ""
	if !cancel {
		line, err := bufio.NewReader(os.Stdin).ReadString('\n')
		if err != nil && err != io.EOF {
			return err
		}
		secret = strings.TrimRight(line, "\r\n")
	}
	f, err := os.OpenFile(path, os.O_WRONLY|syscall.O_NONBLOCK, 0)
	if err != nil {
		return fmt.Errorf(i18n.T("no update is waiting for a password"))
	}
	defer f.Close()
	_, err = io.WriteString(f, secret)
	return err
}

// reopenHub brings the Hub back on its Updates page after the update replaced
// the desktop under it, so a Hub-driven run finishes where it started.
func reopenHub() {
	if updateUI() != "hub" {
		return
	}
	cmd := exec.Command(pkgBin("ryoku-shell"), "hub", "open", "updates")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if cmd.Start() == nil {
		_ = cmd.Process.Release()
	}
}
