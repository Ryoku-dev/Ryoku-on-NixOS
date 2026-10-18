package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

type quickGatewayJSON struct {
	URL     string `json:"url"`
	Running bool   `json:"running"`
}

type quickInfoJSON struct {
	Route   string           `json:"route"`
	Label   string           `json:"label"`
	Routes  []quickRouteJSON `json:"routes"`
	Gateway quickGatewayJSON `json:"gateway"`
	Ready   bool             `json:"ready"`
	Reason  string           `json:"reason,omitempty"`
}

func quickInfo(ctx context.Context, cfg Config) quickInfoJSON {
	configured := strings.ToLower(strings.TrimSpace(cfg.Quick.Route))
	if configured == "" {
		configured = "auto"
	}
	agentRoute := quickAgentRoute(cfg)
	info := quickInfoJSON{
		Route:   configured,
		Label:   configured,
		Routes:  []quickRouteJSON{agentRoute},
		Gateway: quickGatewayJSON{URL: prowlGatewayBase()},
	}
	_, agentReady := resolveChatBackend(cfg)
	routing, routingErr := gatewayRouting(ctx)
	prowlReady := routingErr == nil && routing.Routable
	if routingErr == nil {
		info.Gateway.Running = true
	}
	if prowlReady {
		routes, err := quickRoutes(ctx)
		info.Routes = append(info.Routes, routes...)
		if err != nil {
			info.Reason = quickGatewayError(err).Error()
		}
	} else if configured != "agent" {
		info.Route = "agent"
	}
	if info.Route == "agent" {
		info.Ready = agentReady
	} else {
		info.Ready = prowlReady
	}
	if !info.Ready {
		info.Reason = "Ask needs an agent harness with an ACP adapter or a connected Prowl provider."
	} else if routingErr != nil && configured != "agent" {
		info.Reason = quickGatewayError(routingErr).Error()
	} else if !routing.Routable && configured != "agent" {
		info.Reason = "Prowl has no provider connected; using the Agent model"
	}
	for _, candidate := range info.Routes {
		if candidate.ID == info.Route {
			info.Label = candidate.Label
			break
		}
	}
	return info
}

func quickAgentRoute(cfg Config) quickRouteJSON {
	id := activeChatAgentID(cfg)
	name := id
	if backend, ok := lookupChatBackend(id); ok {
		name = backend.Name
	}
	model := modelPick(id)
	if model == "" {
		for _, def := range harnessDefs() {
			if def.id == id {
				model, _ = harnessModelChoice(id, def.home())
				break
			}
		}
	}
	if model == "" {
		model = "Default"
	}
	return quickRouteJSON{ID: "agent", Label: "Agent model", Sub: name + " · " + model}
}

func cmdBackend(args []string) error {
	cfg := LoadConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if len(args) == 1 && (args[0] == "--json" || args[0] == "-j") {
		return json.NewEncoder(os.Stdout).Encode(quickInfo(ctx, cfg))
	}
	if len(args) == 0 {
		printBackend(ctx, cfg)
		return nil
	}
	if len(args) != 1 {
		return fmt.Errorf("usage: ryoku-rashin backend [--json|<route>]")
	}
	if err := setQuickRoute(ctx, args[0]); err != nil {
		return err
	}
	fmt.Printf("fast lane route set to %s\n", strings.ToLower(strings.TrimSpace(args[0])))
	printBackend(ctx, LoadConfig())
	return nil
}

func printBackend(ctx context.Context, cfg Config) {
	info := quickInfo(ctx, cfg)
	fmt.Printf("fast lane: %s (%s)\n", info.Label, info.Route)
	fmt.Printf("  gateway: %s\n", info.Gateway.URL)
	if !info.Ready {
		fmt.Printf("  unavailable: %s\n", info.Reason)
	}
	ids := make([]string, 0, len(info.Routes))
	for _, route := range info.Routes {
		ids = append(ids, route.ID)
	}
	fmt.Printf("routes: %s\n", strings.Join(ids, ", "))
	fmt.Println("set with: ryoku-rashin backend <route>")
}
