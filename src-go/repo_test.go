// What ls-remote's failures mean, and which answers about a remote connect.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"errors"
	"strings"
	"testing"
)

// What git prints when ls-remote fails, as git printed it. Only the texts for a
// host that answered no are missing. A network that is down, a host key ssh
// refused and a git that never started are unknown, with the line that says why.
func TestLsRemoteFailure(t *testing.T) {
	const advice = "fatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.\n"
	const refused = "fatal: unable to access 'https://127.0.0.1:1/me/proj.git/': Failed to connect to 127.0.0.1 port 1 after 0 ms: Could not connect to server"
	const sshRefused = "ssh: connect to host 127.0.0.1 port 1: Connection refused"
	noGit := errors.New(`exec: "git": executable file not found in $PATH`)
	cases := []struct {
		name   string
		said   string
		err    error
		state  repoExistence
		reason string
	}{
		{"a local path", "fatal: '/srv/nosuch.git' does not appear to be a git repository\n" + advice, nil, repoMissing, ""},
		{"github https", "remote: Repository not found.\nfatal: repository 'https://github.com/me/nosuch.git/' not found\n", nil, repoMissing, ""},
		{"git's own 404 line", "fatal: repository 'https://git.example/me/nosuch.git/' not found\n", nil, repoMissing, ""},
		{"github ssh", "ERROR: Repository not found.\n" + advice, nil, repoMissing, ""},
		{"a username asked for", "fatal: could not read Username for 'https://gitea.com': terminal prompts disabled\n", nil, repoMissing, ""},
		{"a password asked for", "fatal: could not read Password for 'https://someone@gitea.com': terminal prompts disabled\n", nil, repoMissing, ""},
		{"github refused the credential", "remote: Invalid username or token. Password authentication is not supported for Git operations.\nfatal: Authentication failed for 'https://github.com/me/nosuch.git/'\n", nil, repoMissing, ""},
		{"gitea refused the credential", "remote: Failed to authenticate user\nfatal: Authentication failed for 'https://gitea.com/me/nosuch.git/'\n", nil, repoMissing, ""},
		{"https refused", refused + "\n", nil, repoUnknown, refused},
		{"https with no dns", "fatal: unable to access 'https://nosuchhost.invalid/me/proj.git/': Could not resolve host: nosuchhost.invalid\n", nil, repoUnknown, "fatal: unable to access 'https://nosuchhost.invalid/me/proj.git/': Could not resolve host: nosuchhost.invalid"},
		{"ssh refused", sshRefused + "\r\n" + advice, nil, repoUnknown, sshRefused},
		{"ssh with no dns", "ssh: Could not resolve hostname nosuchhost.invalid: Name or service not known\r\n" + advice, nil, repoUnknown, "ssh: Could not resolve hostname nosuchhost.invalid: Name or service not known"},
		{"a known-hosts warning first", "Warning: Permanently added 'h.example' (ED25519) to the list of known hosts.\r\n" + sshRefused + "\r\n" + advice, nil, repoUnknown, sshRefused},
		{"an identity file warning first", "Warning: Identity file /nonexistent/id_x not accessible: No such file or directory.\n" + sshRefused + "\r\n" + advice, nil, repoUnknown, sshRefused},
		{"a hint first", "hint: something to try\n" + refused + "\n", nil, repoUnknown, refused},
		{"a host key refused", "No RSA host key is known for gitea.com and you have requested strict checking.\r\nHost key verification failed.\r\n" + advice, nil, repoUnknown, "No RSA host key is known for gitea.com and you have requested strict checking."},
		{"github https, CRLF", "remote: Repository not found.\r\nfatal: repository 'https://github.com/me/nosuch.git/' not found\r\n", nil, repoMissing, ""},
		{"https refused, CRLF", refused + "\r\n", nil, repoUnknown, refused},
		{"an ssh command that won't start", "fatal: cannot exec '/nonexistent/ssh': No such file or directory\nfatal: ssh variant 'simple' does not support setting port\n", nil, repoUnknown, "fatal: cannot exec '/nonexistent/ssh': No such file or directory"},
		// A loose "not found" would read this one as missing.
		{"ssh not installed", "ssh: command not found\n" + advice, nil, repoUnknown, "ssh: command not found"},
		// The host answered, but before any repo was named, so it says nothing about one.
		{"ssh key refused", "git@github.com: Permission denied (publickey).\r\n" + advice, nil, repoUnknown, "git@github.com: Permission denied (publickey)."},
		{"no git at all", "", noGit, repoUnknown, noGit.Error()},
		{"nothing said", "", nil, repoUnknown, "git gave no reason"},
	}
	for _, tc := range cases {
		state, reason := lsRemoteFailure(tc.said, tc.err)
		if state != tc.state || reason != tc.reason {
			t.Errorf("%s: got %d, %q; want %d, %q", tc.name, state, reason, tc.state, tc.reason)
		}
	}
}

// Only an empty remote is connected to. Unknown, or an answer nobody listed,
// refuses before the plan, and never sends anyone off to create what may exist.
func TestProbedConnectRefusesUnlessEmpty(t *testing.T) {
	const url = "ssh://git@h.example/me/proj.git"
	const reason = "ssh: connect to host h port 22: Network is unreachable"
	if err := probedConnect(url, repoEmpty, ""); err != nil {
		t.Errorf("empty: %v, want it connected", err)
	}
	cases := []struct {
		name       string
		state      repoExistence
		has, lacks []string
	}{
		{"missing", repoMissing, []string{"doesn't exist, or you have no access", "repo create"}, []string{"Can't reach", "no telling"}},
		{"history", repoNonEmpty, []string{"already has history"}, []string{"repo create"}},
		// A refused key reaches this answer too, so it can't claim the host was never reached.
		{"unknown", repoUnknown, []string{"no telling whether it exists", reason}, []string{"repo create", "Couldn't reach"}},
		{"unlisted", repoExistence(99), []string{"no telling whether it exists", reason}, []string{"repo create", "Couldn't reach"}},
	}
	for _, tc := range cases {
		err := probedConnect(url, tc.state, reason)
		if err == nil {
			t.Errorf("%s: connected, want a refusal", tc.name)
			continue
		}
		for _, s := range tc.has {
			if !strings.Contains(err.Error(), s) {
				t.Errorf("%s: %q does not say %q", tc.name, err, s)
			}
		}
		for _, s := range tc.lacks {
			if strings.Contains(err.Error(), s) {
				t.Errorf("%s: %q says %q", tc.name, err, s)
			}
		}
	}
	if err := probedConnect("https://me:tok_s3cret@127.0.0.1:1/me/proj.git", repoUnknown, "x"); err == nil || strings.Contains(err.Error(), "tok_s3cret") {
		t.Errorf("unknown with a credential in the url: %v", err)
	}
}
