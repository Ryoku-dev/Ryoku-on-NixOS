package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAMDGPUVitalsUsesLargestActiveRadeon(t *testing.T) {
	root := t.TempDir()
	writeGPUFixture(t, root, "card0", "0x1002", "12", "1048576", "2147483648", "active")
	writeGPUFixture(t, root, "card1", "0x1002", "37", "4294967296", "17179869184", "active")
	writeGPUFixture(t, root, "card2", "0x1002", "99", "1", "34359738368", "suspended")
	writeGPUFixture(t, root, "card3", "0x10de", "88", "1", "68719476736", "active")
	if err := os.Mkdir(filepath.Join(root, "card1-DP-1"), 0o755); err != nil {
		t.Fatal(err)
	}

	got := amdGPUVitals(root)
	if got == nil {
		t.Fatal("AMD GPU was not detected")
	}
	if got.Name != "AMD Radeon" || got.Percent != 37 || got.VRAMUsed != 4294967296 || got.VRAMTotal != 17179869184 {
		t.Fatalf("AMD GPU = %+v", got)
	}
}

func TestAMDGPUVitalsReturnsNilWithoutRadeon(t *testing.T) {
	root := t.TempDir()
	writeGPUFixture(t, root, "card0", "0x10de", "40", "1", "2", "active")
	if got := amdGPUVitals(root); got != nil {
		t.Fatalf("GPU = %+v, want nil", got)
	}
}

func writeGPUFixture(t *testing.T, root, card, vendor, busy, used, total, status string) {
	t.Helper()
	device := filepath.Join(root, card, "device")
	if err := os.MkdirAll(filepath.Join(device, "power"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, value := range map[string]string{
		"vendor":              vendor,
		"gpu_busy_percent":    busy,
		"mem_info_vram_used":  used,
		"mem_info_vram_total": total,
	} {
		if err := os.WriteFile(filepath.Join(device, name), []byte(value+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(device, "power", "runtime_status"), []byte(status+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}
