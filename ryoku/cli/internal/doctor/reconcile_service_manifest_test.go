package doctor

import (
	"testing"

	"ryoku-cli/internal/host"
)

func withServiceManifestFake(t *testing.T, fn func(bool) int) {
	t.Helper()
	old := serviceManifestReconcile
	oldSystemCheck := serviceManifestSystemCheck
	oldSystemReconcile := serviceManifestSystemReconcile
	serviceManifestReconcile = fn
	serviceManifestSystemCheck = func() int { return host.ExitOK }
	serviceManifestSystemReconcile = func() error { return nil }
	t.Cleanup(func() {
		serviceManifestReconcile = old
		serviceManifestSystemCheck = oldSystemCheck
		serviceManifestSystemReconcile = oldSystemReconcile
	})
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

func TestReconcileServiceManifestRepairsSystemWideDrift(t *testing.T) {
	withServiceManifestFake(t, func(bool) int { return host.ExitOK })
	serviceManifestSystemCheck = func() int { return host.ExitFalse }
	called := false
	serviceManifestSystemReconcile = func() error {
		called = true
		return nil
	}

	result := reconcileServiceManifest(false)
	if result.status != recFixed || !called {
		t.Fatalf("result = %#v, system reconcile called = %v", result, called)
	}
}
