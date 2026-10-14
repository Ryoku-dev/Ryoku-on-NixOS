package host

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// pacman.log stamps read 2026-02-04T05:06:07+0000, so the date may run straight
// into a letter; only digits on either side mean it is not a date.
var installedDatePattern = regexp.MustCompile(`(?:^|[^0-9])([0-9]{4})-([0-9]{2})-([0-9]{2})(?:[^0-9]|$)`)

func (a *App) packageInstalledAt(manager PackageManager, archName string) int {
	name, ok := a.translatedPackageName(manager, archName)
	if !ok {
		return ExitNotProvided
	}
	var value string
	switch manager {
	case Pacman:
		body, err := os.ReadFile(a.cfg.PacmanLog)
		if err != nil {
			return ExitFalse
		}
		needle := "[ALPM] installed " + name + " ("
		for _, line := range strings.Split(string(body), "\n") {
			if strings.Contains(line, needle) {
				value = calendarDate(line)
				break
			}
		}
	case DNF:
		result := a.query("rpm", "-q", "--qf", "%{INSTALLTIME}", name)
		if result.Code != 0 {
			return ExitFalse
		}
		seconds, err := strconv.ParseInt(strings.TrimSpace(result.Output), 10, 64)
		if err == nil {
			value = time.Unix(seconds, 0).Format("20060102")
		}
	case XBPS:
		result := a.query("xbps-query", "-p", "install-date", name)
		if result.Code != 0 {
			return ExitFalse
		}
		value = calendarDate(result.Output)
	}
	if value == "" {
		return ExitFalse
	}
	fmt.Fprintln(a.cfg.Stdout, value)
	return ExitOK
}

func (a *App) translatedPackageName(manager PackageManager, archName string) (string, bool) {
	if manager == Pacman {
		return archName, archName != ""
	}
	var (
		table packageTable
		err   error
	)
	if manager == DNF {
		table, err = a.fedoraTable()
	} else {
		table, err = a.xbpsTable()
	}
	if err != nil {
		return "", false
	}
	mapping := translatePackage(table, archName)
	if mapping.Special == "-" || len(mapping.Names) == 0 {
		return "", false
	}
	return mapping.Names[0], true
}

func calendarDate(value string) string {
	match := installedDatePattern.FindStringSubmatch(value)
	if len(match) != 4 {
		return ""
	}
	return match[1] + match[2] + match[3]
}
