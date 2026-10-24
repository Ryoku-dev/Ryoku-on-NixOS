package limineefi

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestClearLastBootedEntryWithSudoClearsAttributesBeforeRemoval(t *testing.T) {
	path := filepath.Join(t.TempDir(), "LimineLastBootedEntry")
	if err := os.WriteFile(path, []byte("Ryoku Linux"), 0o644); err != nil {
		t.Fatal(err)
	}
	var commands []string
	sudo := func(args ...string) error {
		commands = append(commands, strings.Join(args, " "))
		return nil
	}
	if err := ClearLastBootedEntryWithSudo(path, sudo); err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(commands, "\n"); got != "chattr -i "+path+"\nrm -f "+path {
		t.Fatalf("privileged commands =\n%s\nwant immutable flag cleared before removal", got)
	}
}

func TestClearLastBootedEntryWithSudoIgnoresAbsentVariable(t *testing.T) {
	called := false
	if err := ClearLastBootedEntryWithSudo(filepath.Join(t.TempDir(), "missing"), func(...string) error {
		called = true
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if called {
		t.Fatal("absent EFI variable invoked sudo")
	}
}
