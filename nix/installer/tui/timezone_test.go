
package main

import (
	"reflect"
	"testing"
)

func TestFilterTimezones(t *testing.T) {
	zones := []string{
		"UTC",
		"America/Sao_Paulo",
		"America/Fortaleza",
		"Europe/London",
	}

	tests := []struct {
		name     string
		query    string
		expected []string
	}{
		{
			name:     "search with spaces",
			query:    "sao paulo",
			expected: []string{"America/Sao_Paulo"},
		},
		{
			name:     "search with underscores",
			query:    "Sao_Paulo",
			expected: []string{"America/Sao_Paulo"},
		},
		{
			name:     "search by region",
			query:    "Europe",
			expected: []string{"Europe/London"},
		},
		{
			name:  "empty search returns everything",
			query: "",
			expected: zones,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := filterTimezones(zones, tt.query)

			if !reflect.DeepEqual(got, tt.expected) {
				t.Fatalf("got %v, expected %v", got, tt.expected)
			}
		})
	}
}
