package host

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const appCommandNotFound = 127

var quickshellCrashEnvironment = [...]string{
	"__QUICKSHELL_CRASH_INFO_FD",
	"__QUICKSHELL_CRASH_DUMP_PID",
	"__QUICKSHELL_CRASH_DUMP_FD",
	"__QUICKSHELL_CRASH_LOG_FD",
	"__QUICKSHELL_CRASH_SIGNAL",
}

type appOptions struct {
	cwd     string
	label   string
	command []string
}

type appEnvironmentValue struct {
	value   string
	present bool
}

func parseApp(args []string) (appOptions, bool) {
	var out appOptions
	for len(args) > 0 {
		switch args[0] {
		case "--":
			out.command = args[1:]
			return out, len(out.command) > 0
		case "--cwd":
			if len(args) < 2 || args[1] == "" {
				return out, false
			}
			out.cwd, args = args[1], args[2:]
		case "--label":
			if len(args) < 2 || args[1] == "" {
				return out, false
			}
			out.label, args = args[1], args[2:]
		default:
			return out, false
		}
	}
	return out, false
}

func sanitizeAppLabel(label string) string {
	var out strings.Builder
	out.Grow(len(label))
	separator := false
	for _, char := range label {
		value := byte(0)
		switch {
		case char >= 'A' && char <= 'Z':
			value = byte(char + ('a' - 'A'))
		case char >= 'a' && char <= 'z', char >= '0' && char <= '9':
			value = byte(char)
		default:
			if out.Len() > 0 {
				separator = true
			}
			continue
		}
		if separator && out.Len() < 80 {
			out.WriteByte('-')
		}
		if out.Len() == 80 {
			break
		}
		out.WriteByte(value)
		separator = false
		if out.Len() == 80 {
			break
		}
	}
	label = strings.Trim(out.String(), "-")
	if label == "" {
		return "app"
	}
	return label
}

func appScopeLabel(opts appOptions) string {
	label := opts.label
	if label == "" {
		label = filepath.Base(opts.command[0])
	}
	return sanitizeAppLabel(label)
}

func appScopeSuffix() (string, error) {
	var value [6]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(value[:]), nil
}

func systemdAppArgs(opts appOptions, suffix string) []string {
	unit := "app-ryoku-" + appScopeLabel(opts) + "-" + suffix + ".scope"
	args := make([]string, 0, 9+len(opts.command))
	args = append(args,
		"--user",
		"--scope",
		"--collect",
		"--quiet",
		"--slice=app.slice",
		"--unit="+unit,
	)
	if opts.cwd != "" {
		args = append(args, "--working-directory="+opts.cwd)
	}
	args = append(args, "--")
	return append(args, opts.command...)
}

func scrubAppEnvironment() [len(quickshellCrashEnvironment)]appEnvironmentValue {
	var saved [len(quickshellCrashEnvironment)]appEnvironmentValue
	for i, name := range quickshellCrashEnvironment {
		saved[i].value, saved[i].present = os.LookupEnv(name)
		_ = os.Unsetenv(name)
	}
	return saved
}

func restoreAppEnvironment(saved [len(quickshellCrashEnvironment)]appEnvironmentValue) {
	for i, name := range quickshellCrashEnvironment {
		if saved[i].present {
			_ = os.Setenv(name, saved[i].value)
		} else {
			_ = os.Unsetenv(name)
		}
	}
}

func (a *App) runRunitApp(opts appOptions) int {
	previousDir := ""
	if opts.cwd != "" {
		var err error
		previousDir, err = os.Getwd()
		if err != nil {
			return a.failf("get current directory: %v", err)
		}
		if err := os.Chdir(opts.cwd); err != nil {
			return a.failf("change directory to %s: %v", opts.cwd, err)
		}
	}
	result := a.cfg.Runner.Run(Command{
		Name:     opts.command[0],
		Args:     opts.command[1:],
		Detached: true,
	})
	if previousDir != "" {
		_ = os.Chdir(previousDir)
	}
	return commandExit(result)
}

func (a *App) App(args []string) int {
	opts, ok := parseApp(args)
	if !ok {
		return ExitUsage
	}
	if !a.cfg.Runner.LookPath(opts.command[0]) {
		fmt.Fprintf(a.cfg.Stderr, "ryoku-host: %s: command not found\n", opts.command[0])
		return appCommandNotFound
	}
	init, err := a.Init()
	if err != nil {
		return a.failf("%v", err)
	}

	savedEnvironment := scrubAppEnvironment()
	if init == Systemd {
		suffix, err := appScopeSuffix()
		if err != nil {
			restoreAppEnvironment(savedEnvironment)
			return a.failf("create application scope name: %v", err)
		}
		result := a.runSystemd(true, systemdAppArgs(opts, suffix)...)
		restoreAppEnvironment(savedEnvironment)
		return commandExit(result)
	}
	code := a.runRunitApp(opts)
	restoreAppEnvironment(savedEnvironment)
	return code
}
