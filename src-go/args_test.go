// Argument parsing, on its own. None of it touches a repo, which is the point:
// the shapes that used to need a throwaway repo and a built binary to exercise
// are settled here in microseconds.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import "testing"

func TestParseArgsPositionals(t *testing.T) {
	opt, cmd, help, err := parseArgs([]string{"repo", "clone", "https://x/y.git", "dir"})
	if err != nil || help {
		t.Fatalf("err=%v help=%v", err, help)
	}
	if cmd.name != "repo" || cmd.arg != "clone" || cmd.arg2 != "https://x/y.git" || cmd.arg3 != "dir" {
		t.Errorf("positionals landed wrong: %+v", cmd)
	}
	if !opt.fetch || opt.visibility != "private" {
		t.Errorf("defaults not applied: %+v", opt)
	}
}

func TestParseArgsOptions(t *testing.T) {
	tests := []struct {
		name string
		argv []string
		want func(options) bool
	}{
		{"quiet long", []string{"-q"}, func(o options) bool { return o.quiet }},
		{"quiet as yes", []string{"--yes"}, func(o options) bool { return o.quiet }},
		{"no-fetch", []string{"--no-fetch"}, func(o options) bool { return !o.fetch }},
		{"nofetch", []string{"--nofetch"}, func(o options) bool { return !o.fetch }},
		{"public", []string{"--public"}, func(o options) bool { return o.visibility == "public" && o.sawPublic }},
		{"message split", []string{"-m", "hi there"}, func(o options) bool { return o.message == "hi there" }},
		{"message joined", []string{"--message=hi"}, func(o options) bool { return o.message == "hi" }},
		{"config joined keeps case", []string{"--config=/A/b"}, func(o options) bool { return o.configFile == "/A/b" && o.configGiven }},
		{"any-identity", []string{"--anyidentity"}, func(o options) bool { return o.anyIdentity }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			opt, _, _, err := parseArgs(tc.argv)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !tc.want(opt) {
				t.Errorf("options not as expected: %+v", opt)
			}
		})
	}
}

// A value we are already waiting for wins over the option test - there is no
// other way to write a commit message that starts with a dash.
func TestParseArgsMessageMayLookLikeAnOption(t *testing.T) {
	opt, cmd, _, err := parseArgs([]string{"pullcom", "-m", "-Wall added"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if opt.message != "-Wall added" {
		t.Errorf("message = %q", opt.message)
	}
	if cmd.name != "pullcom" {
		t.Errorf("command = %q", cmd.name)
	}
}

func TestParseArgsRefusals(t *testing.T) {
	for _, argv := range [][]string{
		{"--offline"},
		{"--nonsense"},
		{"-m"},
		{"a", "b", "c", "d", "e", "f"},
	} {
		if _, _, _, err := parseArgs(argv); err == nil {
			t.Errorf("%v was accepted", argv)
		}
	}
}

// The tokenizer takes five positionals for 'account set <name> <key> <value>'
// alone. Every other command has to keep rejecting the fifth, which is now
// sortCommand's job rather than the tokenizer's - and the tail that does it was
// only ever checking the fourth.
func TestSortCommandRefusesFifthPositional(t *testing.T) {
	_, cmd, _, err := parseArgs([]string{"repo", "clone", "url", "dir", "extra"})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	cmd, err = collapseCommand(cmd)
	if err != nil {
		t.Fatalf("collapse: %v", err)
	}
	opt := defaultOptions()
	if _, err := sortCommand(cmd, &opt); err == nil {
		t.Error("a fifth positional was accepted on 'repo clone'")
	}
}

// 'account set' is the one command that keeps all three of its shifted
// positionals, and the tail that rejects a third must not eat its value.
func TestSortCommandAccountSet(t *testing.T) {
	_, cmd, _, err := parseArgs([]string{"account", "set", "work", "host", "gitea.com"})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	cmd, err = collapseCommand(cmd)
	if err != nil {
		t.Fatalf("collapse: %v", err)
	}
	opt := defaultOptions()
	got, err := sortCommand(cmd, &opt)
	if err != nil {
		t.Fatalf("sort: %v", err)
	}
	if got.name != "account-set" || got.arg != "work" || got.arg2 != "host" || got.arg3 != "gitea.com" {
		t.Errorf("got %q %q/%q/%q", got.name, got.arg, got.arg2, got.arg3)
	}
	if !got.mutating {
		t.Error("account set must be a mutating command")
	}
}

func TestParseArgsHelpFromAnyPosition(t *testing.T) {
	for _, argv := range [][]string{{"--help"}, {"br", "create", "--help"}, {"-h"}} {
		if _, _, help, err := parseArgs(argv); !help || err != nil {
			t.Errorf("%v: help=%v err=%v", argv, help, err)
		}
	}
}

func TestCollapseCommand(t *testing.T) {
	tests := []struct {
		argv []string
		want string
	}{
		{[]string{"br", "list"}, "br-list"},
		{[]string{"br"}, "br-list"},
		{[]string{"branch", "land"}, "br-merge"},
		{[]string{"br", "merge"}, "br-merge"},
		{[]string{"br", "clean"}, "br-prune"},
		{[]string{"account"}, "account-list"},
		{[]string{"acct", "apply"}, "account-apply"},
		{[]string{"repository", "new"}, "repo-create"},
		{[]string{"update"}, "pullcom"},
		{[]string{"pullc"}, "pullcom"},
		{[]string{"PULL"}, "pullcom"},
		{[]string{"whoami"}, "whoami"},
		{[]string{"who"}, "whoami"},
		{[]string{"identity"}, "whoami"},
		{[]string{"status"}, "status"},
	}
	for _, tc := range tests {
		t.Run(tc.want+"/"+tc.argv[0], func(t *testing.T) {
			_, cmd, _, err := parseArgs(tc.argv)
			if err != nil {
				t.Fatalf("parse: %v", err)
			}
			got, err := collapseCommand(cmd)
			if err != nil {
				t.Fatalf("collapse: %v", err)
			}
			if got.name != tc.want {
				t.Errorf("got %q, want %q", got.name, tc.want)
			}
		})
	}
}

// The internal tokens carry a hyphen precisely so they cannot be typed.
func TestCollapseCommandRefusesInternalTokens(t *testing.T) {
	for _, name := range []string{"br-merge", "repo-clone", "account-apply"} {
		if _, err := collapseCommand(command{name: name}); err == nil {
			t.Errorf("%q was accepted as typed", name)
		}
	}
}

// The noun shift is what makes 'br list extra' complain about the extra rather
// than about 'list'.
func TestSortCommandShiftedPositionals(t *testing.T) {
	_, cmd, _, err := parseArgs([]string{"br", "list", "extra"})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	cmd, err = collapseCommand(cmd)
	if err != nil {
		t.Fatalf("collapse: %v", err)
	}
	opt := defaultOptions()
	if _, err := sortCommand(cmd, &opt); err == nil {
		t.Error("'br list extra' was accepted")
	}
}

func TestSortCommandMutating(t *testing.T) {
	tests := []struct {
		argv     []string
		mutating bool
	}{
		{[]string{"status"}, false},
		{[]string{"whoami"}, false},
		{[]string{"br", "list"}, false},
		{[]string{"account", "list"}, false},
		{[]string{"repo", "url"}, false},
		{[]string{"repo", "url", "https"}, true},
		{[]string{"pr"}, false},
		{[]string{"pr", "7"}, false},
		{[]string{"pr", "create"}, true},
		{[]string{"pr", "ok", "7"}, true},
		{[]string{"pullcom"}, true},
		{[]string{"br", "prune"}, true},
		{[]string{"account", "apply"}, true},
	}
	for _, tc := range tests {
		t.Run(tc.argv[0]+"/"+joinArgs(tc.argv[1:]), func(t *testing.T) {
			opt, cmd, _, err := parseArgs(tc.argv)
			if err != nil {
				t.Fatalf("parse: %v", err)
			}
			if cmd, err = collapseCommand(cmd); err != nil {
				t.Fatalf("collapse: %v", err)
			}
			cmd, err = sortCommand(cmd, &opt)
			if err != nil {
				t.Fatalf("sort: %v", err)
			}
			if cmd.mutating != tc.mutating {
				t.Errorf("mutating = %v, want %v", cmd.mutating, tc.mutating)
			}
		})
	}
}

// A bare positional is the commit message when no -m was given, and -m wins when
// both are.
func TestSortCommandPositionalMessage(t *testing.T) {
	opt, cmd, _, _ := parseArgs([]string{"pullcom", "typed here"})
	cmd, _ = collapseCommand(cmd)
	if _, err := sortCommand(cmd, &opt); err != nil {
		t.Fatalf("sort: %v", err)
	}
	if opt.message != "typed here" {
		t.Errorf("message = %q", opt.message)
	}

	opt, cmd, _, _ = parseArgs([]string{"pullcom", "positional", "-m", "flag"})
	cmd, _ = collapseCommand(cmd)
	if _, err := sortCommand(cmd, &opt); err != nil {
		t.Fatalf("sort: %v", err)
	}
	if opt.message != "flag" {
		t.Errorf("-m did not win: %q", opt.message)
	}
}

func TestScanPassthrough(t *testing.T) {
	tests := []struct {
		name     string
		argv     []string
		tool     string
		args     []string
		wantErr  bool
		wantQuie bool
	}{
		{name: "plain", argv: []string{"raw", "git", "status", "-s"}, tool: "git", args: []string{"status", "-s"}},
		{name: "gh", argv: []string{"raw", "gh", "pr", "list"}, tool: "gh", args: []string{"pr", "list"}},
		{name: "our options first", argv: []string{"-q", "raw", "git", "log"}, tool: "git", args: []string{"log"}, wantQuie: true},
		{name: "tool's own -q is the tool's", argv: []string{"raw", "git", "commit", "-q"}, tool: "git", args: []string{"commit", "-q"}},
		{name: "no raw at all", argv: []string{"status"}},
		{name: "option after raw is ours arriving late", argv: []string{"raw", "-q", "git"}, wantErr: true},
		{name: "unknown tool", argv: []string{"raw", "svn"}, wantErr: true},
		{name: "raw with nothing after it", argv: []string{"raw"}, wantErr: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			opt := defaultOptions()
			tool, args, err := scanPassthrough(tc.argv, &opt)
			if (err != nil) != tc.wantErr {
				t.Fatalf("err = %v, wantErr %v", err, tc.wantErr)
			}
			if tc.wantErr {
				return
			}
			if tool != tc.tool {
				t.Errorf("tool = %q, want %q", tool, tc.tool)
			}
			if joinArgs(args) != joinArgs(tc.args) {
				t.Errorf("args = %v, want %v", args, tc.args)
			}
			if opt.quiet != tc.wantQuie {
				t.Errorf("quiet = %v, want %v", opt.quiet, tc.wantQuie)
			}
		})
	}
}

func joinArgs(args []string) string {
	out := ""
	for _, a := range args {
		out += a + "\x00"
	}
	return out
}
