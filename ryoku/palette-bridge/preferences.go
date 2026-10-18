package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
)

type spotifyPreferences struct {
	NeutralStyle      bool    `json:"neutralStyle"`
	AccentStrength    float64 `json:"accentStrength"`
	SurfaceTint       float64 `json:"surfaceTint"`
	NeutralText       bool    `json:"neutralText"`
	RemoveGradients   bool    `json:"removeGradients"`
	SurfaceBrightness float64 `json:"surfaceBrightness"`
	SidebarTint       float64 `json:"sidebarTint"`
	PlayerTint        float64 `json:"playerTint"`
	CardTint          float64 `json:"cardTint"`
	AccentButtons     bool    `json:"accentButtons"`
	AccentProgress    bool    `json:"accentProgress"`
	AccentLinks       bool    `json:"accentLinks"`
}

type bridgePreferences struct {
	Spotify spotifyPreferences `json:"spotify"`
}

type preferencesHub struct{ *paletteHub }

func defaultBridgePreferences() bridgePreferences {
	return bridgePreferences{Spotify: spotifyPreferences{
		NeutralStyle: false, AccentStrength: 100, SurfaceTint: 5, NeutralText: true, RemoveGradients: true,
		SurfaceBrightness: 50, SidebarTint: 100, PlayerTint: 100, CardTint: 100,
		AccentButtons: true, AccentProgress: true, AccentLinks: true,
	}}
}

func newPreferencesHub() *preferencesHub {
	hub := &preferencesHub{newPaletteHub()}
	data, _ := json.Marshal(defaultBridgePreferences())
	hub.publishSnapshot(data)
	return hub
}

func preferencesObject(data []byte) (map[string]json.RawMessage, error) {
	var object map[string]json.RawMessage
	if err := json.Unmarshal(data, &object); err != nil {
		return nil, err
	}
	if object == nil {
		return nil, errors.New("preferences must be an object")
	}
	return object, nil
}

func decodePreferences(data []byte) ([]byte, error) {
	preferences := defaultBridgePreferences()
	object, err := preferencesObject(data)
	if err != nil {
		return nil, err
	}
	if bridge, ok := object["paletteBridge"]; ok {
		object, err = preferencesObject(bridge)
		if err != nil {
			return nil, fmt.Errorf("paletteBridge: %w", err)
		}
		if spotify, ok := object["spotify"]; ok {
			object, err = preferencesObject(spotify)
			if err != nil {
				return nil, fmt.Errorf("paletteBridge.spotify: %w", err)
			}
			fields := map[string]any{
				"neutralStyle":      &preferences.Spotify.NeutralStyle,
				"accentStrength":    &preferences.Spotify.AccentStrength,
				"surfaceTint":       &preferences.Spotify.SurfaceTint,
				"neutralText":       &preferences.Spotify.NeutralText,
				"removeGradients":   &preferences.Spotify.RemoveGradients,
				"surfaceBrightness": &preferences.Spotify.SurfaceBrightness,
				"sidebarTint":       &preferences.Spotify.SidebarTint,
				"playerTint":        &preferences.Spotify.PlayerTint,
				"cardTint":          &preferences.Spotify.CardTint,
				"accentButtons":     &preferences.Spotify.AccentButtons,
				"accentProgress":    &preferences.Spotify.AccentProgress,
				"accentLinks":       &preferences.Spotify.AccentLinks,
			}
			for key, destination := range fields {
				if value, ok := object[key]; ok {
					if bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
						return nil, fmt.Errorf("spotify.%s must not be null", key)
					}
					if err := json.Unmarshal(value, destination); err != nil {
						return nil, fmt.Errorf("spotify.%s: %w", key, err)
					}
				}
			}
		}
	}
	if preferences.Spotify.AccentStrength < 0 || preferences.Spotify.AccentStrength > 100 {
		return nil, errors.New("spotify.accentStrength must be between 0 and 100")
	}
	if preferences.Spotify.SurfaceTint < 0 || preferences.Spotify.SurfaceTint > 20 {
		return nil, errors.New("spotify.surfaceTint must be between 0 and 20")
	}
	for name, value := range map[string]float64{
		"surfaceBrightness": preferences.Spotify.SurfaceBrightness,
		"sidebarTint":       preferences.Spotify.SidebarTint,
		"playerTint":        preferences.Spotify.PlayerTint,
		"cardTint":          preferences.Spotify.CardTint,
	} {
		if value < 0 || value > 100 {
			return nil, fmt.Errorf("spotify.%s must be between 0 and 100", name)
		}
	}
	return json.Marshal(preferences)
}

func (h *preferencesHub) readFile(path string) error {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		data, err = []byte("{}"), nil
	}
	if err != nil {
		return err
	}
	valid, err := decodePreferences(data)
	if err != nil {
		return err
	}
	h.publishSnapshot(valid)
	return nil
}
