package main

import (
	"errors"
	"fmt"
	"os"
	"strings"
)

const fixUsage = `usage: ryoku-rashin fix doctor [finding name]
       ryoku-rashin fix tip <id>
       ryoku-rashin fix app <name> [what happened...]

Opens your agent (the chat agent picked in Rashin, Hermes by default) with the
problem as its first message: right here when run from a terminal, in a new
terminal window otherwise. The agent reads the logs itself, explains the
cause, and asks before it changes anything.`

// fixKinds are the problems Fix with AI knows how to brief.
var fixKinds = map[string]bool{"doctor": true, "tip": true, "app": true}

// parseFixArgs maps the command line onto a fix request.
func parseFixArgs(args []string) (fixRequest, error) {
	var req fixRequest
	if len(args) == 0 {
		return req, errors.New(fixUsage)
	}
	req.Kind = args[0]
	switch req.Kind {
	case "doctor":
		req.Name = strings.Join(args[1:], " ")
	case "tip":
		if len(args) < 2 {
			return req, errors.New(fixUsage)
		}
		req.ID = args[1]
	case "app":
		if len(args) < 2 {
			return req, errors.New(fixUsage)
		}
		req.App = args[1]
		req.Note = strings.Join(args[2:], " ")
	default:
		return req, errors.New(fixUsage)
	}
	return req, nil
}

func cmdFix(args []string) error {
	req, err := parseFixArgs(args)
	if err != nil {
		return err
	}
	display, brief, err := buildFix(req)
	if err != nil {
		return err
	}
	launch, err := planFix(display, brief)
	if err != nil {
		return err
	}
	if onTerminal() {
		fmt.Printf("%s\nOpening %s...\n", display, launch.Harness)
		return runFixHere(launch)
	}
	if err := openFixTerminal(launch); err != nil {
		return err
	}
	fmt.Printf("%s\nOpened %s in a terminal.\n", display, launch.Harness)
	return nil
}

// onTerminal: both ends are a terminal, so the harness can take it over.
func onTerminal() bool {
	for _, f := range []*os.File{os.Stdin, os.Stdout} {
		st, err := f.Stat()
		if err != nil || st.Mode()&os.ModeCharDevice == 0 {
			return false
		}
	}
	return true
}
