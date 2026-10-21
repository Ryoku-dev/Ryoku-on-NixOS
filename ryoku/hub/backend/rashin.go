package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// ryoku-hub rashin is the Rashin page's master switch. Rashin is an optional
// app on every edition, so the switch owns the package as well as the agent:
// `on` installs ryoku-rashin when it is absent and starts the agent with the
// desktop; `off` stops the agent and removes the package. Either way the
// compositor config is re-authored afterwards, which is what takes the Ask and
// Rashin window chords away with the package and gives them back with it, and
// the choice is written to the provisioning ledger so the doctor never delivers
// Rashin a second time.

const rashinPackage = "ryoku-rashin"

type rashinStatus struct {
	Installed bool `json:"installed"`
}

func runRashin(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("rashin needs status|on|off")
	}
	switch args[0] {
	case "status":
		b, err := json.Marshal(rashinStatus{Installed: rashinInstalled()})
		if err != nil {
			return err
		}
		fmt.Println(string(b))
		return nil
	case "on":
		return rashinOn()
	case "off":
		return rashinOff()
	}
	return fmt.Errorf("unknown rashin command: %s", args[0])
}

func rashinInstalled() bool {
	_, err := exec.LookPath(rashinPackage)
	return err == nil
}

// privileged runs a ryoku-host verb as root through pkexec, so the polkit agent
// asks for the password the way every other privileged Hub action does. Its
// output goes to stderr: stdout is the page's JSON channel.
func privileged(args ...string) error {
	if nixManagedHost() {
		return fmt.Errorf("packages and phone system setup are managed declaratively on NixOS")
	}
	cmd := exec.Command("pkexec", append([]string{"ryoku-host"}, args...)...)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	if err := cmd.Run(); err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) && (exit.ExitCode() == 126 || exit.ExitCode() == 127) {
			return fmt.Errorf("the password prompt was dismissed")
		}
		return fmt.Errorf("ryoku-host %s: %w", strings.Join(args, " "), err)
	}
	return nil
}

func rashinOn() error {
	if !rashinInstalled() {
		if nixManagedHost() {
			return fmt.Errorf("Rashin is supplied by the Ryoku NixOS module; rebuild the system to restore it")
		}
		if err := privileged("pkg", "install", rashinPackage); err != nil {
			return err
		}
		if !rashinInstalled() {
			return fmt.Errorf("%s did not land", rashinPackage)
		}
	}
	if err := recordProvisioned(rashinPackage); err != nil {
		return err
	}
	if out, err := exec.Command(rashinPackage, "enable").CombinedOutput(); err != nil {
		return fmt.Errorf("%s enable: %s", rashinPackage, strings.TrimSpace(string(out)))
	}
	return applyDesktop()
}

// rashinOff stops the agent, then removes the package. A stop that fails (a
// wedged daemon that will not exit) is reported, not obeyed: the user asked for
// Rashin gone, the config already records it off, and leaving the package
// behind because one process hung would make the switch lie about what is
// installed.
func rashinOff() error {
	var stopErr error
	if rashinInstalled() {
		if out, err := exec.Command(rashinPackage, "disable").CombinedOutput(); err != nil {
			stopErr = fmt.Errorf("the running agent did not stop (%s); it ends with the session", strings.TrimSpace(string(out)))
		}
		if err := privileged("pkg", "remove", rashinPackage); err != nil {
			return err
		}
	}
	if err := recordProvisioned(rashinPackage); err != nil {
		return err
	}
	if err := applyDesktop(); err != nil {
		return err
	}
	return stopErr
}

// recordProvisioned appends a package name to the doctor's deliver-once ledger
// (one name per line), so a package that is absent afterwards reads as the
// user's removal and is never reinstalled by a later update.
func recordProvisioned(pkg string) error {
	if nixManagedHost() {
		return nil
	}
	path := filepath.Join(stateHome(), "ryoku", "provisioned")
	if f, err := os.Open(path); err == nil {
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			if strings.TrimSpace(scanner.Text()) == pkg {
				f.Close()
				return nil
			}
		}
		f.Close()
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.WriteString(pkg + "\n")
	return err
}
