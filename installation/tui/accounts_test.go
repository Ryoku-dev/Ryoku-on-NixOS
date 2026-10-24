package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAccountEnvExportsPrimaryRootAndExtraUsers(t *testing.T) {
	oldRuntime := accountsRuntimeDir
	accountsRuntimeDir = t.TempDir()
	t.Cleanup(func() { accountsRuntimeDir = oldRuntime })

	adminHash := sha512Crypt("admin password", "adminsalt")
	rootHash := sha512Crypt("root password", "rootsalt")
	alexHash := sha512Crypt("alex password", "alexsalt")
	joHash := sha512Crypt("jo password", "josalt")
	m := model{
		picks: map[string]string{
			"username": "owner",
			"keyboard": "us",
			"disk":     "whole",
		},
		pwHash: adminHash,
		accounts: accountsState{
			adminFullName: "Owner Person",
			rootMode:      rootModePassword,
			rootHash:      rootHash,
			people: []installerAccount{
				{Name: "alex", FullName: "Alex Person", Role: accountRoleAdmin, Permissions: []string{"devices", "virtualization"}, PasswordHash: alexHash, LimitBytes: 4096},
				{Name: "jo", Role: accountRoleStandard, PasswordHash: joHash},
			},
			defaultHomeLimit: 8192,
		},
	}

	env, err := m.installEnvChecked()
	if err != nil {
		t.Fatalf("installEnvChecked: %v", err)
	}
	for key, want := range map[string]string{
		"RYOKU_USERNAME":           "owner",
		"RYOKU_PASSWORD_HASH":      adminHash,
		"RYOKU_FULLNAME":           "Owner Person",
		"RYOKU_ROOT_MODE":          rootModePassword,
		"RYOKU_ROOT_PASSWORD_HASH": rootHash,
		"RYOKU_HOME_LIMIT_BYTES":   "8192",
	} {
		if got := accountEnvValue(env, key); got != want {
			t.Errorf("%s = %q, want %q", key, got, want)
		}
	}

	path := accountEnvValue(env, "RYOKU_EXTRA_USERS_FILE")
	if path != filepath.Join(accountsRuntimeDir, "extra-users.tsv") {
		t.Fatalf("RYOKU_EXTRA_USERS_FILE = %q", path)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read extra users: %v", err)
	}
	wantTSV := strings.Join([]string{
		"alex\tAlex Person\tadmin\tdevices,virtualization\t" + alexHash + "\t4096",
		"jo\t\tstandard\tdevices\t" + joHash + "\t0",
		"",
	}, "\n")
	if string(data) != wantTSV {
		t.Fatalf("extra users TSV:\n%s\nwant:\n%s", data, wantTSV)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat extra users: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("extra users mode = %#o, want 0600", info.Mode().Perm())
	}
}

func TestAccountEnvLocksRootAndOmitsOptionalValues(t *testing.T) {
	oldRuntime := accountsRuntimeDir
	accountsRuntimeDir = t.TempDir()
	t.Cleanup(func() { accountsRuntimeDir = oldRuntime })

	m := model{
		picks:    map[string]string{"username": "owner"},
		pwHash:   sha512Crypt("password", "ownersalt"),
		accounts: accountsState{rootMode: rootModeLocked},
	}
	env, err := m.accountsEnv()
	if err != nil {
		t.Fatalf("accountsEnv: %v", err)
	}
	if got := accountEnvValue(env, "RYOKU_ROOT_MODE"); got != rootModeLocked {
		t.Fatalf("RYOKU_ROOT_MODE = %q", got)
	}
	for _, key := range []string{"RYOKU_FULLNAME", "RYOKU_ROOT_PASSWORD_HASH", "RYOKU_EXTRA_USERS_FILE", "RYOKU_HOME_LIMIT_BYTES"} {
		if got := accountEnvValue(env, key); got != "" {
			t.Errorf("optional %s unexpectedly exported as %q", key, got)
		}
	}
}

func TestValidateAccountNameRejectsBadDuplicateAndReservedNames(t *testing.T) {
	for _, name := range []string{"", "Nero", "9nero", "has space", "has.dot", strings.Repeat("a", 33)} {
		if err := validateAccountName(name, nil); err == nil {
			t.Errorf("bad account name %q was accepted", name)
		}
	}
	for _, name := range []string{"root", "nobody", "nogroup", "daemon", "http", "systemd-network", "systemd-anything", "sddm"} {
		if err := validateAccountName(name, nil); err == nil {
			t.Errorf("reserved account name %q was accepted", name)
		}
	}
	if err := validateAccountName("nero", []string{"owner", "nero"}); err == nil {
		t.Fatal("duplicate account name was accepted")
	}
	for _, name := range []string{"nero", "_setup", "mary-jane", "person_2"} {
		if err := validateAccountName(name, nil); err != nil {
			t.Errorf("valid account name %q was rejected: %v", name, err)
		}
	}
}

func TestExtraUsersTSVRejectsDuplicateAndReservedNames(t *testing.T) {
	hash := sha512Crypt("password", "testsalt")
	for name, people := range map[string][]installerAccount{
		"primary duplicate": {{Name: "owner", Role: accountRoleStandard, PasswordHash: hash}},
		"extra duplicate": {
			{Name: "alex", Role: accountRoleStandard, PasswordHash: hash},
			{Name: "alex", Role: accountRoleAdmin, PasswordHash: hash},
		},
		"reserved": {{Name: "root", Role: accountRoleAdmin, PasswordHash: hash}},
	} {
		if _, err := extraUsersTSV("owner", people); err == nil {
			t.Errorf("%s was accepted", name)
		}
	}
}

func accountEnvValue(env []string, key string) string {
	prefix := key + "="
	for _, value := range env {
		if found, ok := strings.CutPrefix(value, prefix); ok {
			return found
		}
	}
	return ""
}
