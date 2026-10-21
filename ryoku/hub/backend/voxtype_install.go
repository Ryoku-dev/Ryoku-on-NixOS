package main

import (
	"context"
	"embed"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

//go:embed assets/redux/setup.py assets/redux/adapter.py assets/redux/LICENSE assets/redux/UPSTREAM.md
var reduxAssets embed.FS

// Cancellation belongs to the command, including all download/build descendants.
func runCancelableInstall(cmd *exec.Cmd) error {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		return err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		return err
	case <-ctx.Done():
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		select {
		case <-done:
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		case <-time.After(2 * time.Second):
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
			<-done
		}
		return fmt.Errorf("installation canceled")
	}
}

func runReduxSetup(action string) error {
	if !hostUsesSystemd() {
		return fmt.Errorf("the Redux adapter currently requires a systemd user session")
	}
	cache, err := os.UserCacheDir()
	if err != nil {
		return err
	}
	root := filepath.Join(cache, "ryoku")
	if err := os.MkdirAll(root, 0o700); err != nil {
		return err
	}
	stage, err := os.MkdirTemp(root, "redux-install-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(stage)
	for _, name := range []string{"setup.py", "adapter.py", "LICENSE", "UPSTREAM.md"} {
		data, err := reduxAssets.ReadFile("assets/redux/" + name)
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(stage, name), data, 0o600); err != nil {
			return err
		}
	}
	cmd := exec.Command("python3", filepath.Join(stage, "setup.py"), action)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	return runCancelableInstall(cmd)
}

func reduxReceiptPath() string { return filepath.Join(dataHome(), "voxtype-redux", "hub-install.json") }

func removeRedux() error {
	if err := runReduxSetup("check-remove"); err != nil {
		return err
	}
	if selectedPreset(readFileString(voxtypeConfigPath())) == reduxPresetKey {
		// Do not leave a running daemon pointing at the model being removed.
		if err := voxtypeSet(`{"preset":"whisper-fast","enabled":false}`); err != nil {
			return err
		}
	} else {
		if err := configureReduxService(false, false); err != nil {
			return err
		}
		if err := userService("disable", "--now", "voxtype-redux"); err != nil {
			return err
		}
	}
	if err := runReduxSetup("remove"); err != nil {
		return err
	}
	if err := userService("daemon-reload"); err != nil {
		return err
	}
	fmt.Println("ok")
	return nil
}
