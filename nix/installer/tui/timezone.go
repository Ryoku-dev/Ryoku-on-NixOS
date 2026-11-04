
package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode"
)

func loadTimezones(zoneinfoDir string) ([]string, error) {
	if zoneinfoDir == "" {
		zoneinfoDir = os.Getenv("RYOKU_ZONEINFO_DIR")
	}

	if zoneinfoDir == "" {
		return nil, fmt.Errorf("RYOKU_ZONEINFO_DIR is not configured")
	}

	var file *os.File
	var openErr error

	for _, name := range []string{"zone1970.tab", "zone.tab"} {
		file, openErr = os.Open(filepath.Join(zoneinfoDir, name))
		if openErr == nil {
			break
		}
	}

	if file == nil {
		return nil, fmt.Errorf(
			"could not find zone1970.tab or zone.tab in %s: %w",
			zoneinfoDir,
			openErr,
		)
	}
	defer file.Close()

	found := make(map[string]struct{})

	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 4096), 1024*1024)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 3 {
			continue
		}

		zone := fields[2]
		clean := filepath.Clean(zone)

		if filepath.IsAbs(zone) ||
			clean == "." ||
			clean == ".." ||
			strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
			continue
		}

		if _, err := os.Stat(filepath.Join(zoneinfoDir, clean)); err != nil {
			continue
		}

		found[zone] = struct{}{}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("could not read timezone database: %w", err)
	}

	for _, zone := range []string{"UTC", "Etc/UTC", "Etc/GMT"} {
		if _, err := os.Stat(filepath.Join(zoneinfoDir, zone)); err == nil {
			found[zone] = struct{}{}
		}
	}

	zones := make([]string, 0, len(found))

	for zone := range found {
		zones = append(zones, zone)
	}

	sort.Slice(zones, func(i, j int) bool {
		if zones[i] == "UTC" {
			return true
		}
		if zones[j] == "UTC" {
			return false
		}
		return zones[i] < zones[j]
	})

	if len(zones) == 0 {
		return nil, fmt.Errorf("timezone database contains no usable entries")
	}

	return zones, nil
}

func timezoneSearchKey(value string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return unicode.ToLower(r)
		}
		return -1
	}, value)
}

func filterTimezones(zones []string, query string) []string {
	query = timezoneSearchKey(query)

	if query == "" {
		return zones
	}

	var matches []string

	for _, zone := range zones {
		if strings.Contains(timezoneSearchKey(zone), query) {
			matches = append(matches, zone)
		}
	}

	return matches
}
