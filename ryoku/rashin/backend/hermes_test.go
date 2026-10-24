package main

import (
	"os"
	"path/filepath"
	"testing"
)

func writeHermesConfig(t *testing.T, content string) {
	t.Helper()
	dir := filepath.Join(home(), ".hermes")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "config.yaml"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestHermesOnboardedTemplateIsNotConfigured(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	if hermesOnboarded() {
		t.Fatal("missing config.yaml must not count as onboarded")
	}
	// The installer's template: a model key with no value.
	writeHermesConfig(t, "# hermes config\nmodel:\nterminal:\n  backend: local\n")
	if hermesOnboarded() {
		t.Fatal("template config with empty model must not count as onboarded")
	}
}

func TestHermesOnboardedChosenModelIsConfigured(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	writeHermesConfig(t, "model: openrouter/anthropic/claude-sonnet-4.5\n")
	if !hermesOnboarded() {
		t.Fatal("a chosen model means onboarding happened")
	}
}

func TestHermesOnboardedMappingForm(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	writeHermesConfig(t, "model:\n  provider: openai-codex\n  base_url: https://x\n  default: gpt-5.5\nterminal:\n  backend: local\n")
	if !hermesOnboarded() {
		t.Fatal("mapping-form model must count as onboarded")
	}
	p, m, ok := hermesModel()
	if !ok || p != "openai-codex" || m != "gpt-5.5" {
		t.Fatalf("hermesModel = %q %q %v", p, m, ok)
	}
}

func TestHermesModelStopsAtBlockEnd(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	writeHermesConfig(t, "model:\nterminal:\n  backend: local\n  provider: bogus\n")
	if hermesOnboarded() {
		t.Fatal("empty mapping followed by another block must not count")
	}
}

func TestHermesStatusUsesItsProviderScopedModelPick(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("RYOKU_STATE_PATH", t.TempDir())
	t.Setenv("RYOKU_CONFIG_BASE", filepath.Join(t.TempDir(), "absent"))
	t.Setenv("PATH", filepath.Join(t.TempDir(), "bin"))
	writeHermesConfig(t, "model:\n  provider: openrouter\n  default: z-ai/glm-5.3\n")
	cfg := defaultConfig()
	cfg.ChatAgent = "claude"
	if err := SaveConfig(cfg); err != nil {
		t.Fatal(err)
	}
	if err := setModelPick("claude", "anthropic:claude-opus"); err != nil {
		t.Fatal(err)
	}
	if err := setModelPick("hermes", "openai-codex:gpt-6-luna"); err != nil {
		t.Fatal(err)
	}
	got := HermesStatus()
	if got.Provider != "openai-codex" || got.Model != "gpt-6-luna" {
		t.Fatalf("status provider/model = %q / %q", got.Provider, got.Model)
	}

	if err := setModelPick("hermes", "unscoped-model"); err != nil {
		t.Fatal(err)
	}
	got = HermesStatus()
	if got.Provider != "openrouter" || got.Model != "z-ai/glm-5.3" {
		t.Fatalf("unscoped pick changed config default to %q / %q", got.Provider, got.Model)
	}
}
