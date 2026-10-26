package wm

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"testing"
)

func TestQMLEmptyCapsMatchesAllCapabilities(t *testing.T) {
	path := filepath.Join("..", "ui", "Singletons", "Wm.qml")
	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}

	blockPattern := regexp.MustCompile(`(?s)readonly property var emptyCaps:\s*\(\{(.*?)\}\)`)
	match := blockPattern.FindSubmatch(source)
	if match == nil {
		t.Fatalf("%s has no emptyCaps object", path)
	}

	keyPattern := regexp.MustCompile(`(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:`)
	qmlCaps := make(map[string]struct{})
	for _, key := range keyPattern.FindAllSubmatch(match[1], -1) {
		qmlCaps[string(key[1])] = struct{}{}
	}

	allCaps := make(map[string]struct{}, len(All()))
	for _, capability := range All() {
		allCaps[string(capability)] = struct{}{}
	}

	var missingInQML []string
	for capability := range allCaps {
		if _, ok := qmlCaps[capability]; !ok {
			missingInQML = append(missingInQML, capability)
		}
	}
	var unknownInQML []string
	for capability := range qmlCaps {
		if _, ok := allCaps[capability]; !ok {
			unknownInQML = append(unknownInQML, capability)
		}
	}
	sort.Strings(missingInQML)
	sort.Strings(unknownInQML)

	if len(missingInQML) != 0 || len(unknownInQML) != 0 {
		t.Fatalf("emptyCaps drift: missing in QML: %v; unknown in QML: %v", missingInQML, unknownInQML)
	}
}
