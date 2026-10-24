package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const defaultPreferences = `{"spotify":{"neutralStyle":false,"accentStrength":100,"surfaceTint":5,"neutralText":true,"removeGradients":true,"surfaceBrightness":50,"sidebarTint":100,"playerTint":100,"cardTint":100,"accentButtons":true,"accentProgress":true,"accentLinks":true}}`

func TestPreferencesDefaultsToggleAndInvalidUpdates(t *testing.T) {
	path := filepath.Join(t.TempDir(), "ryogami.json")
	hub := newPreferencesHub()
	if got := string(hub.snapshot().data); got != defaultPreferences {
		t.Fatalf("defaults = %s", got)
	}
	if err := hub.readFile(path); err != nil {
		t.Fatal(err)
	}
	data := `{"unrelated":{"private":"secret"},"paletteBridge":{"spotify":{"neutralStyle":true,"accentStrength":40,"surfaceTint":12,"neutralText":false,"removeGradients":false}}}`
	if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := hub.readFile(path); err != nil {
		t.Fatal(err)
	}
	want := `{"spotify":{"neutralStyle":true,"accentStrength":40,"surfaceTint":12,"neutralText":false,"removeGradients":false,"surfaceBrightness":50,"sidebarTint":100,"playerTint":100,"cardTint":100,"accentButtons":true,"accentProgress":true,"accentLinks":true}}`
	if got := string(hub.snapshot().data); got != want {
		t.Fatalf("preferences = %s", got)
	}
	for _, invalid := range []string{`{`, `null`, `[]`, `{"paletteBridge":{"spotify":true}}`, `{"paletteBridge":{"spotify":{"neutralStyle":"true"}}}`, `{"paletteBridge":{"spotify":{"neutralText":null}}}`, `{"paletteBridge":{"spotify":{"accentStrength":101}}}`, `{"paletteBridge":{"spotify":{"accentStrength":-1}}}`, `{"paletteBridge":{"spotify":{"surfaceTint":21}}}`, `{"paletteBridge":{"spotify":{"surfaceTint":-1}}}`} {
		if err := os.WriteFile(path, []byte(invalid), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := hub.readFile(path); err == nil {
			t.Errorf("accepted %s", invalid)
		}
		if got := string(hub.snapshot().data); got != want {
			t.Fatalf("invalid update replaced last valid: %s", got)
		}
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := hub.readFile(path); err != nil {
		t.Fatal(err)
	}
	if got := string(hub.snapshot().data); got != defaultPreferences {
		t.Fatalf("removed file = %s", got)
	}
}

func TestPreferencesReadOnlyEndpoint(t *testing.T) {
	hub := newPreferencesHub()
	for _, method := range []string{http.MethodGet, http.MethodPost, http.MethodOptions} {
		recorder := httptest.NewRecorder()
		hub.paletteHandler(recorder, httptest.NewRequest(method, "/v1/preferences", nil))
		want := map[string]int{http.MethodGet: 200, http.MethodPost: 405, http.MethodOptions: 204}[method]
		if recorder.Code != want {
			t.Fatalf("%s status = %d", method, recorder.Code)
		}
		if method == http.MethodGet && strings.TrimSpace(recorder.Body.String()) != defaultPreferences {
			t.Fatalf("body = %s", recorder.Body.String())
		}
	}
}

func TestPreferencesSSEToggleReconnectAndPaletteIsolation(t *testing.T) {
	preferences := newPreferencesHub()
	palette := newPaletteHub()
	colors := `{"primary":"#112233","surface":"#445566","onSurface":"#ffffff"}`
	if err := palette.publish([]byte(colors)); err != nil {
		t.Fatal(err)
	}
	paletteClient := make(chan snapshot, 1)
	palette.clients[paletteClient] = struct{}{}
	server := httptest.NewServer(http.HandlerFunc(preferences.eventsHandler))
	defer server.Close()
	readEvent := func(reader *bufio.Reader) string {
		t.Helper()
		for {
			line, err := reader.ReadString('\n')
			if err != nil {
				t.Fatal(err)
			}
			if strings.HasPrefix(line, "data: ") {
				return strings.TrimSpace(strings.TrimPrefix(line, "data: "))
			}
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	request, _ := http.NewRequestWithContext(ctx, http.MethodGet, server.URL, nil)
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	reader := bufio.NewReader(response.Body)
	if got := readEvent(reader); got != defaultPreferences {
		t.Fatalf("initial event = %s", got)
	}
	path := filepath.Join(t.TempDir(), "ryogami.json")
	if err := os.WriteFile(path, []byte(`{"paletteBridge":{"spotify":{"neutralStyle":true}}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := preferences.readFile(path); err != nil {
		t.Fatal(err)
	}
	updated := readEvent(reader)
	var payload struct {
		Spotify struct {
			NeutralStyle bool `json:"neutralStyle"`
		} `json:"spotify"`
	}
	if err := json.Unmarshal([]byte(updated), &payload); err != nil || !payload.Spotify.NeutralStyle {
		t.Fatalf("toggle = %s (%v)", updated, err)
	}
	response.Body.Close()
	response, err = http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if got := readEvent(bufio.NewReader(response.Body)); got != updated {
		t.Fatalf("reconnect = %s", got)
	}
	if got := string(palette.snapshot().data); got != colors {
		t.Fatalf("palette changed: %s", got)
	}
	select {
	case <-paletteClient:
		t.Fatal("preferences leaked to palette SSE queue")
	default:
	}
	if err := palette.publish([]byte(updated)); err == nil {
		t.Fatal("palette validation accepted preferences")
	}
}

func TestPreferencesWatcherReadsExistingConfigAndResetsAfterRemoval(t *testing.T) {
	path := filepath.Join(t.TempDir(), "ryogami.json")
	if err := os.WriteFile(path, []byte(`{"paletteBridge":{"spotify":{"neutralStyle":true}}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	hub := newPreferencesHub()
	updates := make(chan error, 16)
	go func() {
		err := watchPalette(path, func() error {
			err := hub.readFile(path)
			select {
			case updates <- err:
			default:
			}
			return err
		})
		select {
		case updates <- err:
		default:
		}
	}()
	await := func(wantError bool) {
		t.Helper()
		select {
		case err := <-updates:
			if (err != nil) != wantError {
				t.Fatalf("reload error = %v, wantError %v", err, wantError)
			}
		case <-time.After(3 * time.Second):
			t.Fatal("watcher missed config change")
		}
	}
	await(false)
	if !strings.Contains(string(hub.snapshot().data), `"neutralStyle":true`) {
		t.Fatal("post-attach read missed existing file")
	}
	prior := string(hub.snapshot().data)
	if err := os.WriteFile(path, []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	await(true)
	if got := string(hub.snapshot().data); got != prior {
		t.Fatalf("invalid update replaced valid preferences: %s", got)
	}
	tmp := path + ".new"
	if err := os.WriteFile(tmp, []byte(`{"paletteBridge":{"spotify":{"neutralStyle":true,"surfaceTint":20}}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(tmp, path); err != nil {
		t.Fatal(err)
	}
	await(false)
	if !strings.Contains(string(hub.snapshot().data), `"surfaceTint":20`) {
		t.Fatal("atomic replacement missed")
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	await(false)
	if got := string(hub.snapshot().data); got != defaultPreferences {
		t.Fatalf("removed config = %s", got)
	}
}

func TestPreferencesReadFailureRetainsDefaultsAndLastValid(t *testing.T) {
	hub := newPreferencesHub()
	unreadable := t.TempDir()
	if err := hub.readFile(unreadable); err == nil {
		t.Fatal("reading a directory succeeded")
	}
	if got := string(hub.snapshot().data); got != defaultPreferences {
		t.Fatalf("startup error changed defaults: %s", got)
	}
	path := filepath.Join(t.TempDir(), "ryogami.json")
	if err := os.WriteFile(path, []byte(`{"paletteBridge":{"spotify":{"neutralStyle":true}}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := hub.readFile(path); err != nil {
		t.Fatal(err)
	}
	prior := string(hub.snapshot().data)
	if err := hub.readFile(unreadable); err == nil {
		t.Fatal("reading a directory succeeded")
	}
	if got := string(hub.snapshot().data); got != prior {
		t.Fatalf("read error changed last valid preferences: %s", got)
	}
}

func TestPreferencesGranularControls(t *testing.T) {
	for _, field := range []string{"surfaceBrightness", "sidebarTint", "playerTint", "cardTint"} {
		for _, value := range []string{"0", "42.5", "100"} {
			data, err := decodePreferences([]byte(fmt.Sprintf(`{"paletteBridge":{"spotify":{"%s":%s}}}`, field, value)))
			if err != nil {
				t.Fatalf("%s=%s: %v", field, value, err)
			}
			var output map[string]map[string]json.RawMessage
			if err := json.Unmarshal(data, &output); err != nil {
				t.Fatal(err)
			}
			if got := string(output["spotify"][field]); got != value {
				t.Fatalf("%s = %s, want %s", field, got, value)
			}
		}
		for _, value := range []string{"-1", "101", `"50"`, "true", "null"} {
			if _, err := decodePreferences([]byte(fmt.Sprintf(`{"paletteBridge":{"spotify":{"%s":%s}}}`, field, value))); err == nil {
				t.Fatalf("accepted %s=%s", field, value)
			}
		}
	}
	for _, field := range []string{"accentButtons", "accentProgress", "accentLinks"} {
		for _, value := range []string{"true", "false"} {
			data, err := decodePreferences([]byte(fmt.Sprintf(`{"paletteBridge":{"spotify":{"%s":%s}}}`, field, value)))
			if err != nil {
				t.Fatalf("%s=%s: %v", field, value, err)
			}
			if !strings.Contains(string(data), fmt.Sprintf(`"%s":%s`, field, value)) {
				t.Fatalf("toggle missing from %s", data)
			}
		}
		for _, value := range []string{"0", `"true"`, "null"} {
			if _, err := decodePreferences([]byte(fmt.Sprintf(`{"paletteBridge":{"spotify":{"%s":%s}}}`, field, value))); err == nil {
				t.Fatalf("accepted %s=%s", field, value)
			}
		}
	}
}
