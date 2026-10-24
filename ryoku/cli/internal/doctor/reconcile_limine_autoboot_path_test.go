package doctor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLimineDropFlatWritesStandaloneKernelPath(t *testing.T) {
	conf := "timeout: 3\n" +
		"default_entry: 1\n" +
		"/Ryoku Linux\n" +
		"    protocol: linux\n" +
		"    kernel_path: boot():/vmlinuz-linux\n" +
		"/+Ryoku\n" +
		"//linux (UKI)\n" +
		"    protocol: efi\n"

	got, changed := limineDropFlat(conf)
	if !changed {
		t.Fatal("flat placeholder and numeric default must be migrated")
	}
	if !strings.Contains(got, "default_entry: Ryoku/linux (UKI)") {
		t.Fatalf("default entry did not select the nested kernel path:\n%s", got)
	}
	if strings.Contains(got, "default_entry: 1") || strings.Contains(got, "default_entry: 2") {
		t.Fatalf("nested menu retained a numeric default:\n%s", got)
	}
	if _, changed := limineDropFlat(got); changed {
		t.Fatal("kernel-path migration must be idempotent")
	}
}

// A legacy numeric default on an already promoted menu is the autoboot
// reconciler's to rewrite (it reads the menu Limine's way); the placeholder
// promotion must not report it as flat clutter.
func TestLimineDropFlatLeavesLegacyNumericToAutoboot(t *testing.T) {
	conf := "default_entry: 2\n" +
		"/Ryoku Linux\n" +
		"    kernel_path: boot():/vmlinuz-linux\n" +
		"  //linux\n" +
		"  protocol: efi\n" +
		"     //Snapshots\n"

	got, changed := limineDropFlat(conf)
	if changed {
		t.Fatalf("promoted menu with a numeric default must be left alone:\n%s", got)
	}
	if got != conf {
		t.Fatalf("menu was rewritten:\n%s", got)
	}
}

func TestLimineDropFlatKeepsOneForFlatMenu(t *testing.T) {
	conf := "default_entry: 1\n/Ryoku Linux\n    protocol: linux\n"
	got, changed := limineDropFlat(conf)
	if changed {
		t.Fatalf("flat menu should remain unchanged:\n%s", got)
	}
	if !strings.Contains(got, "default_entry: 1") {
		t.Fatalf("flat menu lost its first-entry fallback:\n%s", got)
	}
}

func stubLimineRememberedEntryClear(t *testing.T) *int {
	t.Helper()
	oldUEFI := limineUEFIBoot
	oldClear := clearLimineLastBootedEntry
	oldRootWrite := limineWriteRootFile
	oldBootWrite := limineWriteBootFile
	cleared := 0
	limineUEFIBoot = func() bool { return true }
	clearLimineLastBootedEntry = func() error {
		cleared++
		return nil
	}
	limineWriteRootFile = func(path, contents, _ string) error {
		return os.WriteFile(path, []byte(contents), 0o644)
	}
	limineWriteBootFile = func(path, contents string) error {
		return os.WriteFile(path, []byte(contents), 0o644)
	}
	t.Cleanup(func() {
		limineUEFIBoot = oldUEFI
		clearLimineLastBootedEntry = oldClear
		limineWriteRootFile = oldRootWrite
		limineWriteBootFile = oldBootWrite
	})
	return &cleared
}

const rememberedDirectoryConf = `timeout: 3
default_entry: 1
remember_last_entry: yes

/Ryoku Linux
  //linux
    protocol: efi
`

func TestReconcileLimineAutobootClearsRememberedDirectory(t *testing.T) {
	stubLimineBootGates(t)
	cleared := stubLimineRememberedEntryClear(t)
	oldESP := limineESPConf
	t.Cleanup(func() { limineESPConf = oldESP })
	limineESPConf = filepath.Join(t.TempDir(), "limine.conf")
	if err := os.WriteFile(limineESPConf, []byte(rememberedDirectoryConf), 0o644); err != nil {
		t.Fatal(err)
	}

	result := reconcileLimineAutoboot(false)
	if result.status != recFixed {
		t.Fatalf("result = %+v, want fixed", result)
	}
	if *cleared != 1 {
		t.Fatalf("remembered entry cleared %d times, want once", *cleared)
	}
	fixed, err := os.ReadFile(limineESPConf)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(fixed), "default_entry: Ryoku Linux/linux") {
		t.Fatalf("default did not move to the bootable kernel path:\n%s", fixed)
	}
}

func TestMigrateLimineLayoutClearsRememberedDirectory(t *testing.T) {
	cleared := stubLimineRememberedEntryClear(t)
	t.Setenv("PATH", t.TempDir())
	oldESP := limineESPConf
	t.Cleanup(func() { limineESPConf = oldESP })
	limineESPConf = filepath.Join(t.TempDir(), "limine.conf")

	result := migrateLimineLayout(limineLayoutState{
		limineInstalled: true,
		espConf:         rememberedDirectoryConf,
		espConfReadable: true,
	})
	if result.status != recFixed {
		t.Fatalf("result = %+v, want fixed", result)
	}
	if *cleared != 1 {
		t.Fatalf("layout migration cleared remembered entry %d times, want once", *cleared)
	}
}

func TestRememberedEntryClearRequiresUEFIAndEnabledSetting(t *testing.T) {
	oldUEFI := limineUEFIBoot
	oldClear := clearLimineLastBootedEntry
	t.Cleanup(func() {
		limineUEFIBoot = oldUEFI
		clearLimineLastBootedEntry = oldClear
	})

	for _, test := range []struct {
		name string
		conf string
		uefi bool
		want int
	}{
		{name: "enabled UEFI", conf: "remember_last_entry: yes\n", uefi: true, want: 1},
		{name: "disabled setting", conf: "remember_last_entry: no\n", uefi: true, want: 0},
		{name: "legacy BIOS", conf: "remember_last_entry: yes\n", uefi: false, want: 0},
	} {
		t.Run(test.name, func(t *testing.T) {
			cleared := 0
			limineUEFIBoot = func() bool { return test.uefi }
			clearLimineLastBootedEntry = func() error {
				cleared++
				return nil
			}
			if err := clearRememberedLimineEntry(test.conf); err != nil {
				t.Fatal(err)
			}
			if cleared != test.want {
				t.Fatalf("clear count = %d, want %d", cleared, test.want)
			}
		})
	}
}

func TestReconcileLimineAutobootDoesNotClearUnmanagedBoot(t *testing.T) {
	oldManaged := limineManagedBoot
	oldClear := clearLimineLastBootedEntry
	t.Cleanup(func() {
		limineManagedBoot = oldManaged
		clearLimineLastBootedEntry = oldClear
	})
	limineManagedBoot = func() bool { return false }
	cleared := false
	clearLimineLastBootedEntry = func() error {
		cleared = true
		return nil
	}

	if result := reconcileLimineAutoboot(false); result.status != recOK {
		t.Fatalf("result = %+v, want ok", result)
	}
	if cleared {
		t.Fatal("non-Limine boot touched Limine's EFI variable")
	}
}

func TestReconcileLimineUKITreeClearsRememberedFlatEntry(t *testing.T) {
	stubLimineBootGates(t)
	cleared := stubLimineRememberedEntryClear(t)
	t.Setenv("PATH", t.TempDir())
	oldESP, oldDefaults := limineESPConf, limineDefaultsPath
	t.Cleanup(func() {
		limineESPConf = oldESP
		limineDefaultsPath = oldDefaults
	})
	dir := t.TempDir()
	limineESPConf = filepath.Join(dir, "limine.conf")
	limineDefaultsPath = filepath.Join(dir, "limine.defaults")
	const conf = `timeout: 3
default_entry: 1
remember_last_entry: yes

/Ryoku Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-linux
/+Ryoku
//linux
    protocol: efi
`
	if err := os.WriteFile(limineESPConf, []byte(conf), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(limineDefaultsPath, []byte("ENABLE_UKI=yes\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	result := reconcileLimineUKITree(false)
	if result.status != recFixed {
		t.Fatalf("result = %+v, want fixed", result)
	}
	if *cleared != 1 {
		t.Fatalf("flat-entry promotion cleared remembered entry %d times, want once", *cleared)
	}
	fixed, err := os.ReadFile(limineESPConf)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(fixed), "\n/Ryoku Linux\n") {
		t.Fatalf("flat placeholder survived promotion:\n%s", fixed)
	}
	if !strings.Contains(string(fixed), "default_entry: Ryoku/linux") {
		t.Fatalf("default did not move into the UKI tree:\n%s", fixed)
	}
}
