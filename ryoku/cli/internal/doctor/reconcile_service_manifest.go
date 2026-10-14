package doctor

import (
	"io"

	"ryoku-cli/internal/host"

	i18n "ryoku-i18n"
)

var serviceManifestReconcile = func(checkOnly bool) int {
	args := []string{"reconcile", "--user"}
	if checkOnly {
		args = append(args, "--check")
	}
	return host.New(host.Config{Stdout: io.Discard, Stderr: io.Discard}).Service(args)
}

func reconcileServiceManifest(checkOnly bool) recResult {
	code := serviceManifestReconcile(true)
	if code == host.ExitOK {
		return okRes(i18n.T("user services match the activation manifest"))
	}
	fix := i18n.T("ryoku-host svc reconcile --user")
	if code != host.ExitFalse {
		return warnRes(i18n.T("could not inspect the user service activation manifest (exit %d)"), code).withFix(fix)
	}
	if checkOnly {
		return wouldRes(i18n.T("user service activation needs reconciliation")).withFix(fix)
	}
	if code := serviceManifestReconcile(false); code != host.ExitOK {
		return failRes(i18n.T("could not reconcile user service activation (exit %d)"), code).withFix(fix)
	}
	return fixedRes(i18n.T("reconciled user services from the activation manifest"))
}
