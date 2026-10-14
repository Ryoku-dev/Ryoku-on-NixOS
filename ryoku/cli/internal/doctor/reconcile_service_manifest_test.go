package doctor

import (
	"testing"

	"ryoku-cli/internal/host"
)

func withServiceManifestFake(t *testing.T, fn func(bool) int) {
	t.Helper()
	old := serviceManifestReconcile
	serviceManifestReconcile = fn
	t.Cleanup(func() { serviceManifestReconcile = old })
}

func TestReconcileServiceManifestAlreadyConverged(t *testing.T) {
	withServiceManifestFake(t, func(check bool) int {
		if !check {
			t.Fatal("converged manifest was changed")
		}
		return host.ExitOK
	})
	if result := reconcileServiceManifest(false); result.status != recOK {
		t.Fatalf("result = %#v", result)
	}
}

func TestReconcileServiceManifestCheckOnlyReportsDrift(t *testing.T) {
	withServiceManifestFake(t, func(check bool) int { return host.ExitFalse })
	result := reconcileServiceManifest(true)
	if result.status != recWouldFix || result.remedy == "" {
		t.Fatalf("result = %#v", result)
	}
}

func TestReconcileServiceManifestRepairsDrift(t *testing.T) {
	var calls []bool
	withServiceManifestFake(t, func(check bool) int {
		calls = append(calls, check)
		if check {
			return host.ExitFalse
		}
		return host.ExitOK
	})
	result := reconcileServiceManifest(false)
	if result.status != recFixed {
		t.Fatalf("result = %#v", result)
	}
	if len(calls) != 2 || !calls[0] || calls[1] {
		t.Fatalf("calls = %v", calls)
	}
}
