package doctor

import (
	"io"

	"ryoku-cli/internal/host"
	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

var serviceManifestReconcile = func(checkOnly bool) int {
	args := []string{"reconcile", "--user"}
	if checkOnly {
		args = append(args, "--check")
	}
	return host.New(host.Config{Stdout: io.Discard, Stderr: io.Discard}).Service(args)
}

var serviceManifestSystemCheck = func() int {
	return host.New(host.Config{Stdout: io.Discard, Stderr: io.Discard}).
		Service([]string{"reconcile", "--system", "--check"})
}

var serviceManifestSystemReconcile = func() error {
	return sys.Sudo("ryoku-host", "svc", "reconcile", "--system")
}

func reconcileServiceManifest(checkOnly bool) recResult {
	userCode := serviceManifestReconcile(true)
	systemCode := serviceManifestSystemCheck()
	if userCode == host.ExitOK && systemCode == host.ExitOK {
		return okRes(i18n.T("user and system-wide services match the activation manifest"))
	}
	fix := i18n.T("sudo ryoku-host svc reconcile --system && ryoku-host svc reconcile --user")
	if userCode != host.ExitOK && userCode != host.ExitFalse {
		return warnRes(i18n.T("could not inspect the user service activation manifest (exit %d)"), userCode).withFix(fix)
	}
	if systemCode != host.ExitOK && systemCode != host.ExitFalse {
		return warnRes(i18n.T("could not inspect system-wide service activation (exit %d)"), systemCode).withFix(fix)
	}
	if checkOnly {
		return wouldRes(i18n.T("user or system-wide service activation needs reconciliation")).withFix(fix)
	}
	if systemCode == host.ExitFalse {
		if err := serviceManifestSystemReconcile(); err != nil {
			return failRes(i18n.T("could not reconcile system-wide service activation: %v"), err).withFix(fix)
		}
	}
	if userCode == host.ExitFalse {
		if code := serviceManifestReconcile(false); code != host.ExitOK {
			return failRes(i18n.T("could not reconcile user service activation (exit %d)"), code).withFix(fix)
		}
	}
	return fixedRes(i18n.T("reconciled user and system-wide services from the activation manifest"))
}
