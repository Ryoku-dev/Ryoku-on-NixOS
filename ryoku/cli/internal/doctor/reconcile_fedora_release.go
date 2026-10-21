package doctor

import (
	"fmt"

	"ryoku-cli/internal/host"

	i18n "ryoku-i18n"
)

var doctorFedoraReleaseStatus = func() (host.FedoraReleaseStatus, error) {
	return host.Default().FedoraReleaseStatus()
}

func reconcileFedoraRelease(_ bool) recResult {
	manager, err := doctorPackageManager()
	if err != nil || manager != host.DNF {
		return okRes(i18n.T("Fedora release checks are not applicable on this host"))
	}

	status, checkErr := doctorFedoraReleaseStatus()
	if !status.RepositoryChecked {
		if checkErr == nil {
			checkErr = fmt.Errorf("repository did not answer")
		}
		return warnRes(i18n.T("could not check whether Ryoku publishes Fedora %s: %v"), status.Version, checkErr)
	}
	if status.Published {
		return okRes(i18n.T("Ryoku publishes packages for Fedora %s"), status.Version)
	}
	return warnRes("%s", status.UnpublishedNotice())
}
