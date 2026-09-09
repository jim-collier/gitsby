// Coverage-guided fuzzing of the pure parsers - the functions that read text this
// program did not write: remote URLs, forge-table output, tags, config lines. Each
// asserts the cheap invariants; mostly they exist so a malformed input panics here
// rather than in someone's terminal. The seed corpus runs under plain 'go test';
// stage 3 of the pipeline hunts briefly past it with -fuzz.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"strings"
	"testing"
	"unicode"
)

func FuzzSplitRemoteURL(f *testing.F) {
	for _, seed := range []string{
		"git@github.com:owner/name.git",
		"https://github.com/owner/name",
		"ssh://git@gitea.example:2222/owner/name.git",
		"C:\\repos\\name",
		"host:path",
		"://", ":", "",
	} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, url string) {
		host, _, _ := splitRemoteURL(url)
		// The host is matched against config rules and account hosts; one carrying
		// the separators it was split on would mean the split misfired.
		if strings.ContainsFunc(host, unicode.IsSpace) {
			t.Errorf("splitRemoteURL(%q) host %q carries whitespace", url, host)
		}
	})
}

func FuzzParseForgeTable(f *testing.F) {
	f.Add("Index\tTitle\tState\n1\tFix the thing\topen\n")
	f.Add("a\tb\nx\n\n")
	f.Add("")
	f.Fuzz(func(t *testing.T, out string) {
		records := parseForgeTable(out)
		if len(records) > len(splitLines(out)) {
			t.Errorf("parseForgeTable made %d records from %d lines", len(records), len(splitLines(out)))
		}
	})
}

var fuzzVersionRE = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`)

func FuzzNextVersion(f *testing.F) {
	for _, seed := range []string{"v2.1.0", "v2.0.0-rc1", "v1.2", "v2020", "nonsense", ""} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, latest string) {
		version, _ := nextVersion(latest)
		// Whatever the tag looked like, what comes out is a plain three-part version:
		// it lands in the next tag name and in the release plan.
		if !fuzzVersionRE.MatchString(version) {
			t.Errorf("nextVersion(%q) = %q, not a three-part version", latest, version)
		}
	})
}

func FuzzMaskURL(f *testing.F) {
	f.Add("https://user:token@github.com/owner/name")
	f.Add("https://x-access-token:ghp_abc@github.com/o/n.git")
	f.Add("git@github.com:owner/name.git")
	f.Fuzz(func(t *testing.T, url string) {
		masked := maskURL(url)
		// The mask exists so a credential in a remote URL never reaches a screen or
		// a transcript: whenever something was masked, the secret half is gone.
		if masked != url && strings.Contains(masked, "://") {
			rest := masked[strings.Index(masked, "://")+3:]
			if at := strings.Index(rest, "@"); at >= 0 && rest[:at] != "***" && !strings.HasSuffix(rest[:at], ":***") {
				t.Errorf("maskURL(%q) = %q left userinfo unmasked", url, masked)
			}
		}
	})
}

func FuzzConfigKeyValue(f *testing.F) {
	f.Add("account.work.ghAccount", "my-login")
	f.Add("account.a.b.c", "  spaced  ")
	f.Add("", "\"quoted\"")
	f.Fuzz(func(t *testing.T, key, value string) {
		if acct, field, ok := splitAccountKey(key); ok && (acct == "" || field == "") {
			t.Errorf("splitAccountKey(%q) said ok with empty parts (%q, %q)", key, acct, field)
		}
		parseConfigValue(value)
	})
}
