package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestStateChangingRoutesRejectForeignOrigins(t *testing.T) {
	hub := newChatHub(askLane())
	for _, test := range []struct {
		name        string
		path        string
		contentType string
		body        string
		handler     http.HandlerFunc
	}{
		{name: "index", path: "/api/index", contentType: "application/json", body: `{}`, handler: handleReindex},
		{name: "quick", path: "/api/quick", contentType: "application/json", body: `{"route":"auto"}`, handler: handleSetQuickRoute},
		{name: "ask", path: "/api/ask?q=hello", handler: hub.handleAsk},
		{name: "ask cancel", path: "/api/ask/cancel", handler: hub.handleAskCancel},
		{name: "term", path: "/api/term", contentType: "application/json", body: `{"q":"hello"}`, handler: hub.handleTerm},
		{name: "term cancel", path: "/api/term/cancel?id=t1", handler: hub.handleTermCancel},
		{name: "term ran", path: "/api/term/ran", contentType: "application/json", body: `{"proposed":"x","ran":"x"}`, handler: hub.handleTermRan},
	} {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, test.path, strings.NewReader(test.body))
			request.Header.Set("Origin", "https://example.com")
			if test.contentType != "" {
				request.Header.Set("Content-Type", test.contentType)
			}
			response := httptest.NewRecorder()
			test.handler(response, request)
			if response.Code != http.StatusForbidden {
				t.Fatalf("status = %d body=%q", response.Code, response.Body.String())
			}
		})
	}
}

func TestMutationGuardAcceptsCLIAndConsoleRequestShapes(t *testing.T) {
	for _, test := range []struct {
		name        string
		requireJSON bool
		origin      string
		host        string
		contentType string
		client      string
		want        bool
	}{
		{name: "ask CLI", host: "127.0.0.1:3600", want: true},
		{name: "ask console", origin: "http://127.0.0.1:3600", host: "127.0.0.1:3600", want: true},
		{name: "term CLI", requireJSON: true, host: "127.0.0.1:3600", contentType: "application/json", want: true},
		{name: "quick console", requireJSON: true, origin: "http://127.0.0.1:3600", host: "127.0.0.1:3600", contentType: "application/json", want: true},
		{name: "console marker", requireJSON: true, origin: "http://127.0.0.1:3600", host: "127.0.0.1:3600", client: "console", want: true},
		{name: "other loopback console", origin: "http://127.0.0.1:9999", host: "127.0.0.1:3600"},
		{name: "simple JSON mutation", requireJSON: true, origin: "http://127.0.0.1:3600", host: "127.0.0.1:3600", contentType: "text/plain"},
	} {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "/", nil)
			request.Host = test.host
			request.Header.Set("Origin", test.origin)
			request.Header.Set("Content-Type", test.contentType)
			request.Header.Set("X-Rashin-Client", test.client)
			response := httptest.NewRecorder()
			if got := allowLocalMutation(response, request, test.requireJSON); got != test.want {
				t.Fatalf("allowed = %v, want %v; status=%d", got, test.want, response.Code)
			}
		})
	}
}
