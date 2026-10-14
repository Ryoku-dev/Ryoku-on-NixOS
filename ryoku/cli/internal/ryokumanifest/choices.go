package ryokumanifest

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

const choiceFieldCount = 12

// ChoicePackages returns every package owned by an installer choice.
func ChoicePackages(path string) (map[string]bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	defer f.Close()

	packages := map[string]bool{}
	seenHeader := false
	seenChoice := false
	scanner := bufio.NewScanner(f)
	for lineNo := 1; scanner.Scan(); lineNo++ {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if !seenHeader {
			seenHeader = true
			if len(fields) != choiceFieldCount || fields[0] != "record" || fields[1] != "kind" || fields[2] != "id" || fields[4] != "packages" {
				return nil, fmt.Errorf("installer choices line %d has an invalid header", lineNo)
			}
			continue
		}
		if len(fields) != choiceFieldCount {
			return nil, fmt.Errorf("installer choices line %d must have twelve tab-separated columns", lineNo)
		}
		switch fields[0] {
		case "choice":
			seenChoice = true
			list := strings.TrimSpace(fields[4])
			if list == "-" {
				continue
			}
			if list == "" {
				return nil, fmt.Errorf("installer choices line %d has no packages", lineNo)
			}
			for _, name := range strings.Split(list, ",") {
				name = strings.TrimSpace(name)
				if name == "" {
					return nil, fmt.Errorf("installer choices line %d has an empty package", lineNo)
				}
				packages[name] = true
			}
		case "policy":
		default:
			return nil, fmt.Errorf("installer choices line %d has unknown record type %q", lineNo, fields[0])
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if !seenHeader {
		return nil, fmt.Errorf("installer choices have no header")
	}
	if !seenChoice {
		return nil, fmt.Errorf("installer choices define no choices")
	}
	return packages, nil
}
