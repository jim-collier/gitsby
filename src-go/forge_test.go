// Host detection and the forge CLIs' vocabulary. What these cover is the seam
// where a GitHub-only program learned there are other hosts: getting it wrong
// means running a GitHub client against somebody else's forge, or refusing work
// that never needed a forge client at all.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import "testing"

// Only spellings that need no ssh_config lookup: an alias would send this to a
// real ssh, and what the box outside answers is not this test's business.
func TestParseRemote(t *testing.T) {
	tests := []struct {
		url, host, owner, name string
	}{
		{"https://github.com/octocat/hello.git", "github.com", "octocat", "hello"},
		{"https://github.com/octocat/hello", "github.com", "octocat", "hello"},
		{"https://user:token@github.com/octocat/hello.git", "github.com", "octocat", "hello"},
		{"git@github.com:octocat/hello.git", "github.com", "octocat", "hello"},
		{"https://git.example.com/octocat/hello.git", "git.example.com", "octocat", "hello"},
		{"https://git.example.com:3000/octocat/hello.git", "git.example.com", "octocat", "hello"},
		// A Gitea served under a subpath: the owner is the segment above the repo,
		// and the instance routing above that says nothing about who owns it.
		{"https://git.example.com/gitea/octocat/hello.git", "git.example.com", "octocat", "hello"},
		// A host with no repo under it still names the host - which is what decides
		// whether a forge CLI is the right tool, independently of the repo.
		{"https://git.example.com/octocat", "git.example.com", "", ""},
		{"/srv/local/repo.git", "", "", ""},
		{`C:\srv\repo`, "", "", ""},
		{"C:/srv/repo", "", "", ""},
		{"", "", "", ""},
	}
	for _, tc := range tests {
		got := parseRemote(tc.url)
		if got.host != tc.host || got.owner != tc.owner || got.name != tc.name {
			t.Errorf("parseRemote(%q) = {%q %q %q}, want {%q %q %q}",
				tc.url, got.host, got.owner, got.name, tc.host, tc.owner, tc.name)
		}
	}
}

// GH_HOST is how gh itself is pointed at an Enterprise instance. Reading it here
// is what keeps an Enterprise user out of the "not GitHub, so no pull requests"
// path they don't belong in.
func TestIsGitHubHost(t *testing.T) {
	tests := []struct {
		host, ghHost string
		want         bool
	}{
		{"github.com", "", true},
		{"GitHub.com", "", true}, // hostnames don't care about case
		{"git.example.com", "", false},
		{"", "", false},
		{"github.example.com", "github.example.com", true},
		{"github.com", "github.example.com", true}, // GH_HOST adds a host, never removes one
		{"git.example.com", "github.example.com", false},
	}
	for _, tc := range tests {
		t.Setenv("GH_HOST", tc.ghHost)
		if got := isGitHubHost(tc.host); got != tc.want {
			t.Errorf("isGitHubHost(%q) with GH_HOST=%q = %v, want %v", tc.host, tc.ghHost, got, tc.want)
		}
	}
}

func TestForgeURL(t *testing.T) {
	tests := []struct{ host, target, proto, want string }{
		{"github.com", "octocat/hello", "https", "https://github.com/octocat/hello.git"},
		{"github.com", "octocat/hello", "ssh", "git@github.com:octocat/hello.git"},
		{"git.example.com", "octocat/hello", "https", "https://git.example.com/octocat/hello.git"},
		{"git.example.com", "octocat/hello", "ssh", "git@git.example.com:octocat/hello.git"},
		{"", "octocat/hello", "https", ""},
		{"github.com", "", "https", ""},
	}
	for _, tc := range tests {
		if got := forgeURL(tc.host, tc.target, tc.proto); got != tc.want {
			t.Errorf("forgeURL(%q, %q, %q) = %q, want %q", tc.host, tc.target, tc.proto, got, tc.want)
		}
	}
}

// tea's tsv writer quotes every cell, header names included. Left quoted, every
// lookup misses and every value carries the quotes into whatever it is compared
// against - which reads as "no such pull request" rather than as a parse problem.
func TestParseForgeTable(t *testing.T) {
	out := "\"index\"\t\"head\"\t\"state\"\n\"7\"\t\"feature-x\"\t\"open\"\n\"9\"\t\"acct:forked\"\t\"closed\"\n"
	records := parseForgeTable(out)
	if len(records) != 2 {
		t.Fatalf("parseForgeTable gave %d records, want 2", len(records))
	}
	if records[0]["index"] != "7" || records[0]["head"] != "feature-x" || records[0]["state"] != "open" {
		t.Errorf("first record = %v", records[0])
	}
	if records[1]["state"] != "closed" {
		t.Errorf("second record state = %q, want \"closed\"", records[1]["state"])
	}
	// A header with no rows under it is not a record, and neither is nothing at all.
	// Both have to read as "couldn't tell" rather than as "no such thing".
	for _, empty := range []string{"", "\"index\"\t\"head\"\n", "\n"} {
		if got := parseForgeTable(empty); len(got) != 0 {
			t.Errorf("parseForgeTable(%q) = %v, want none", empty, got)
		}
	}
}

// A head branch on a fork is spelled 'owner:branch'. What we compare against, and
// later hand to git, is the branch on its own.
func TestHeadBranchName(t *testing.T) {
	tests := []struct{ head, want string }{
		{"feature-x", "feature-x"},
		{"acct:feature-x", "feature-x"},
		{"acct:feature/x", "feature/x"},
		{"", ""},
	}
	for _, tc := range tests {
		if got := headBranchName(tc.head); got != tc.want {
			t.Errorf("headBranchName(%q) = %q, want %q", tc.head, got, tc.want)
		}
	}
}

// An account's credentials are only credentials where that account banks. A config
// that never mentions a host means github.com, because that is all there was when
// every such config was written.
func TestAccountServesHost(t *testing.T) {
	tests := []struct {
		name, configured, host string
		want                   bool
	}{
		{"unstated host is github.com", "", "github.com", true},
		{"unstated host is not somebody else's", "", "git.example.com", false},
		{"stated host matches", "git.example.com", "git.example.com", true},
		{"stated host is not github.com", "git.example.com", "github.com", false},
		{"hostnames don't care about case", "Git.Example.com", "git.example.com", true},
		{"no host at all serves nothing", "", "", false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			a := newApp(newPrinter())
			a.acct.name = "work"
			a.cfg.values = map[string]string{}
			if tc.configured != "" {
				a.cfg.values["account.work.host"] = tc.configured
			}
			if got := a.accountServesHost(tc.host); got != tc.want {
				t.Errorf("accountServesHost(%q) with host=%q = %v, want %v",
					tc.host, tc.configured, got, tc.want)
			}
		})
	}
}

// The variable a token is exported under. A Gitea token must never land in
// GH_TOKEN: gh reads that one, and every child process would inherit a credential
// for a host gh will happily try to use it on.
func TestTokenEnvVar(t *testing.T) {
	if got := tokenEnvVar("github.com"); got != "GH_TOKEN" {
		t.Errorf("tokenEnvVar(github.com) = %q, want GH_TOKEN", got)
	}
	if got := tokenEnvVar("git.example.com"); got == "GH_TOKEN" {
		t.Errorf("tokenEnvVar(git.example.com) = %q, which gh would pick up", got)
	}
}

// The pull-request vocabulary per tool. These are what both the preview and the
// command read, so a disagreement here is a plan promising something else.
func TestPrArgsPerTool(t *testing.T) {
	for _, tc := range []struct {
		tool  forgeTool
		first string
	}{
		{toolGh, "pr"},
		{toolTea, "pulls"},
	} {
		a := newApp(newPrinter())
		a.pr.tool, a.pr.num = tc.tool, "7"
		for label, args := range map[string][]string{
			"list":    a.prListArgs(),
			"approve": a.prApproveArgs(),
			"merge":   a.prMergeArgs(),
		} {
			if len(args) == 0 || args[0] != tc.first {
				t.Errorf("%v %s args = %v, want first word %q", tc.tool, label, args, tc.first)
			}
		}
	}
	// gh deletes the merged branch as part of its own merge; tea does not, so the
	// sweep is a separate call there and must not be invented for gh.
	gh := newApp(newPrinter())
	gh.pr.tool, gh.pr.num = toolGh, "7"
	if got := gh.prCleanArgs(); got != nil {
		t.Errorf("gh prCleanArgs = %v, want none - its merge already deletes the branch", got)
	}
	tea := newApp(newPrinter())
	tea.pr.tool, tea.pr.num = toolTea, "7"
	if got := tea.prCleanArgs(); len(got) == 0 {
		t.Error("tea prCleanArgs is empty, so 'pr ok' would merge and leave the branch standing")
	}
}

// Which login the identity gate compares against. 'ghAccount' is a GitHub login and
// says nothing about who you are anywhere else, so keying the gate on it alone left
// every non-GitHub account uncompared - which is a gate that quietly stopped
// guarding rather than one that said it could not.
func TestAccountWho(t *testing.T) {
	tests := []struct {
		name, ghAccount, user, host, want string
	}{
		{"ghAccount answers for GitHub", "alice", "", "github.com", "alice"},
		{"and for nowhere else", "alice", "", "git.example.test", ""},
		{"user answers for any host", "", "gitfriend", "git.example.test", "gitfriend"},
		{"user wins where both are given", "alice", "gitfriend", "github.com", "gitfriend"},
		{"nothing named is no claim to check", "", "", "git.example.test", ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			a := newApp(newPrinter())
			a.acct.name, a.acct.ghWho = "work", tc.ghAccount
			a.cfg.values = map[string]string{}
			if tc.user != "" {
				a.cfg.values["account.work.user"] = tc.user
			}
			if got := a.accountWho(tc.host); got != tc.want {
				t.Errorf("accountWho(%q) = %q, want %q", tc.host, got, tc.want)
			}
		})
	}
}

// The write gate reads whichever CLI this run goes through. Unknown must stay
// unknown: a tea with no login for the host has said nothing about who you are, and
// refusing on that would refuse every machine that never configured one.
func TestForgeCLIWho(t *testing.T) {
	none := newApp(newPrinter())
	none.gh.tool = toolNone
	if got := none.forgeCLIWho(); got != "?" {
		t.Errorf("forgeCLIWho with no tool = %q, want ?", got)
	}
	// A tea that answers nothing is '?', not the empty string - the mismatch test
	// reads '?' as "couldn't tell" and an empty name would too, but only one of them
	// survives being concatenated into a message.
	tea := newApp(newPrinter())
	tea.gh.tool, tea.gh.cli = toolTea, "tea"
	tea.forge.login.set("")
	if got := tea.forgeCLIWho(); got != "?" {
		t.Errorf("forgeCLIWho with no tea login = %q, want ?", got)
	}
	tea.forge.login.set("gitfriend")
	if got := tea.forgeCLIWho(); got != "gitfriend" {
		t.Errorf("forgeCLIWho = %q, want gitfriend", got)
	}
}
