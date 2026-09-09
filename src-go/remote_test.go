// Remote URL parsing. Every shape here is one git accepts, and getting any of
// them wrong means naming the wrong account - or naming one where there is none
// to name, which is worse.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"strings"
	"testing"
)

func TestRemoteOwner(t *testing.T) {
	tests := []struct{ url, want string }{
		{"https://github.com/octocat/hello.git", "octocat"},
		{"https://github.com/octocat/hello", "octocat"},
		{"https://user:token@github.com/octocat/hello.git", "octocat"},
		{"git@github.com:octocat/hello.git", "octocat"},
		{"ssh://git@github.com/octocat/hello.git", "octocat"},
		{"ssh://git@github.com:22/octocat/hello.git", "octocat"},
		{"https://gitlab.com/octocat/hello.git", ""},
		{"/srv/local/repo.git", ""},
		{`C:\srv\repo`, ""},
		{"C:/srv/repo", ""},
		{"", ""},
		{"github.com", ""},
	}
	for _, tc := range tests {
		if got := remoteOwner(tc.url); got != tc.want {
			t.Errorf("remoteOwner(%q) = %q, want %q", tc.url, got, tc.want)
		}
	}
}

// remoteTarget answers for ANY host - it feeds 'repo url', which rewrites text and
// never asks the host anything, so refusing everywhere but github.com was the
// parser's limit showing through as a rule. remoteOwner above is the one that
// stays GitHub-only, because what it feeds is a GitHub login.
func TestRemoteTarget(t *testing.T) {
	tests := []struct{ url, want string }{
		{"https://github.com/octocat/hello.git", "octocat/hello"},
		{"git@github.com:octocat/hello.git", "octocat/hello"},
		{"git@github.com:octocat/hello", "octocat/hello"},
		{"https://gitlab.com/octocat/hello.git", "octocat/hello"},
		{"https://git.example.com/octocat/hello.git", "octocat/hello"},
		{"git@git.example.com:octocat/hello.git", "octocat/hello"},
		// A Gitea instance served under a subpath: the segment above the repo is the
		// owner, and the routing above that is not.
		{"https://git.example.com/gitea/octocat/hello.git", "octocat/hello"},
		{"https://github.com/octocat", ""}, // a host and an owner is not a repo
		{"/srv/local/repo.git", ""},
		{"", ""},
	}
	for _, tc := range tests {
		if got := remoteTarget(tc.url); got != tc.want {
			t.Errorf("remoteTarget(%q) = %q, want %q", tc.url, got, tc.want)
		}
	}
}

func TestSSHTarget(t *testing.T) {
	tests := []struct{ url, want string }{
		{"git@github.com:octocat/hello.git", "github.com"},
		{"github_work:octocat/hello.git", "github_work"},
		{"ssh://git@github.com:22/octocat/hello.git", "github.com"},
		{"https://github.com/octocat/hello.git", ""}, // no ssh identity involved
		{"/srv/local/repo", ""},
		{"C:/srv/repo", ""}, // a drive path is not 'host:path'
		{"", ""},
	}
	for _, tc := range tests {
		if got := sshTarget(tc.url); got != tc.want {
			t.Errorf("sshTarget(%q) = %q, want %q", tc.url, got, tc.want)
		}
	}
}

// sshTarget gives the alias to display; sshConnectTarget gives what to actually
// connect as, so an explicit user in the URL is honored.
func TestSSHConnectTarget(t *testing.T) {
	tests := []struct{ url, want string }{
		{"git@github.com:octocat/hello.git", "git@github.com"},
		{"github_work:octocat/hello.git", "github_work"},
		{"ssh://git@github.com/octocat/hello.git", "git@github.com"},
		{"https://github.com/octocat/hello.git", ""},
	}
	for _, tc := range tests {
		if got := sshConnectTarget(tc.url); got != tc.want {
			t.Errorf("sshConnectTarget(%q) = %q, want %q", tc.url, got, tc.want)
		}
	}
}

// Only a mismatch both sides KNOW about counts: '?' means we couldn't tell, which
// is not the same as being wrong.
func TestIdentityMismatchText(t *testing.T) {
	if identityMismatchText("gh", "a", "b") == "" {
		t.Error("a real mismatch went unreported")
	}
	for _, tc := range [][2]string{{"a", "a"}, {"?", "b"}, {"a", "?"}, {"", "b"}, {"a", ""}} {
		if got := identityMismatchText("gh", tc[0], tc[1]); got != "" {
			t.Errorf("identityMismatchText(%q, %q) = %q, want none", tc[0], tc[1], got)
		}
	}
	// The tool that acts is named, not assumed. A message about gh, printed for a run
	// that went through tea, sends you to check an account that was never involved.
	if got := identityMismatchText("tea", "a", "b"); !strings.HasPrefix(got, "tea acts as") {
		t.Errorf("identityMismatchText for tea = %q, want it to name tea", got)
	}
	// An unnamed tool still has to produce a sentence rather than start with a space.
	if got := identityMismatchText("", "a", "b"); got == "" || strings.HasPrefix(got, " ") {
		t.Errorf("identityMismatchText with no tool name = %q", got)
	}
}

// A credentialed origin would otherwise echo its token on every run.
func TestMaskURL(t *testing.T) {
	tests := []struct{ in, want string }{
		{"https://user:token@github.com/o/n.git", "https://***@github.com/o/n.git"},
		{"https://github.com/o/n.git", "https://github.com/o/n.git"},
		{"git@github.com:o/n.git", "git@github.com:o/n.git"},
		{"", ""},
	}
	for _, tc := range tests {
		if got := maskURL(tc.in); got != tc.want {
			t.Errorf("maskURL(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestGithubURL(t *testing.T) {
	if got := githubURL("o/n", "ssh"); got != "git@github.com:o/n.git" {
		t.Errorf("ssh = %q", got)
	}
	if got := githubURL("o/n", "https"); got != "https://github.com/o/n.git" {
		t.Errorf("https = %q", got)
	}
	if got := githubURL("", "https"); got != "" {
		t.Errorf("empty target = %q", got)
	}
}

func TestIsLocalPathAndSameRemote(t *testing.T) {
	tests := []struct {
		url   string
		local bool
	}{
		{"/srv/repo", true},
		{"C:/srv/repo", true},
		{`C:\srv\repo`, true},
		{"relative/dir", true},
		{"https://github.com/o/n.git", false},
		{"git@github.com:o/n.git", false},
		{"", false},
	}
	for _, tc := range tests {
		if got := isLocalPath(tc.url); got != tc.local {
			t.Errorf("isLocalPath(%q) = %v, want %v", tc.url, got, tc.local)
		}
	}
	if !sameRemote("/srv/repo/", "/srv/repo") {
		t.Error("the same local directory read as two")
	}
	if sameRemote("", "/srv/repo") {
		t.Error("an empty remote matched something")
	}
	if sameRemote("https://github.com/a/b.git", "git@github.com:a/b.git") {
		t.Error("two spellings of one repo are still two different remotes to git")
	}
}

func TestCloneDestDir(t *testing.T) {
	tests := []struct{ url, dir, want string }{
		{"https://github.com/o/hello.git", "", "hello"},
		{"https://github.com/o/hello", "", "hello"},
		{"https://github.com/o/hello/", "", "hello"},
		{"git@github.com:o/hello.git", "", "hello"},
		{"https://github.com/o/hello.git", "elsewhere", "elsewhere"},
	}
	for _, tc := range tests {
		if got := cloneDestDir(tc.url, tc.dir); got != tc.want {
			t.Errorf("cloneDestDir(%q, %q) = %q, want %q", tc.url, tc.dir, got, tc.want)
		}
	}
}

// The connect timeout used to be skipped whenever GIT_SSH_COMMAND was set at all -
// including when the account selector had just set it from a config sshKey. So the
// multi-account setups the timeout was written for were the ones that lost it, and
// an unreachable host hung every command for the full TCP wait.
func TestRemoteEnvKeepsTheConnectTimeoutOnOurOwnSSHCommand(t *testing.T) {
	t.Setenv("GIT_SSH_COMMAND", "ssh -i /keys/work -o IdentitiesOnly=yes")

	ours := &app{}
	want := "GIT_SSH_COMMAND=ssh -i /keys/work -o IdentitiesOnly=yes -o ConnectTimeout=3"
	if !hasEnv(ours.remoteEnv(), want) {
		t.Errorf("remoteEnv() dropped the connect timeout from our own ssh command")
	}

	theirs := &app{userSSHCommand: true}
	for _, entry := range theirs.remoteEnv() {
		if strings.HasPrefix(entry, "GIT_SSH_COMMAND=") && strings.Contains(entry, "ConnectTimeout") {
			t.Errorf("remoteEnv() rewrote a caller's own GIT_SSH_COMMAND: %q", entry)
		}
	}
}

func hasEnv(env []string, want string) bool {
	for _, entry := range env {
		if entry == want {
			return true
		}
	}
	return false
}
