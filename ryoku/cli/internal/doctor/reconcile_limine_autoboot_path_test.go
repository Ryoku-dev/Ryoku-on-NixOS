package doctor

import (
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
