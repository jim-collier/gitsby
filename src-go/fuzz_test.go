// Coverage-guided fuzzing of the pure parsers - the functions that read text this
// program did not write: remote URLs, tea's table output, tags, config lines. Each
// asserts the cheap invariants; mostly they exist so a malformed input panics here
// rather than in someone's terminal. The seed corpus runs under plain 'go test';
// stage 3 of the pipeline hunts briefly past it with -fuzz.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"regexp"
	"slices"
	"strings"
	"testing"
	"unicode"

	shcl "github.com/jim-collier/shcl/source/go/v2"
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

func FuzzParseTeaTable(f *testing.F) {
	f.Add("Index\tTitle\tState\n1\tFix the thing\topen\n")
	f.Add("a\tb\nx\n\n")
	f.Add("")
	f.Fuzz(func(t *testing.T, out string) {
		records := parseTeaTable(out)
		if len(records) > len(splitLines(out)) {
			t.Errorf("parseTeaTable made %d records from %d lines", len(records), len(splitLines(out)))
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

// indentLines puts prefix ahead of every line of body.
func indentLines(body, prefix string) string {
	lines := strings.Split(body, "\n")
	for i, line := range lines {
		lines[i] = prefix + line
	}
	return strings.Join(lines, "\n")
}

// Whatever sits under a key gitsby reads is deeper than that key, so the parser
// puts it beneath the key or skips it - except a raw block fence, which SHCL
// reads as the key given again with the block as its value, and the last value
// wins as it does for any repeat. Nothing under the key may reach the model, and
// every name the module holds under any instance of it must be on the ignored list.
func FuzzConfigLoadDoc(f *testing.F) {
	// The refused account name is left out: its body is a block's, not a key's.
	for _, row := range nestedKeyRows[:len(nestedKeyRows)-1] {
		f.Add(row.body[strings.IndexByte(row.body, '\n')+1:])
	}
	f.Fuzz(func(t *testing.T, body string) {
		shapes := []struct {
			doc, key, disp, parent, value string
			accounts                      []string
		}{
			{"account: w\n\temail: e@x\n" + indentLines(body, "\t\t"), "account[#0].email", "account[w].email", "email", "e@x", []string{"w"}},
			{"account.w.email: e@x\n" + indentLines(body, "\t"), "account[#0].w.email", "account.w.email", "email", "e@x", []string{"w"}},
			{"protocol: https\n" + indentLines(body, "\t"), "protocol", "protocol", "protocol", "https", nil},
		}
		for _, s := range shapes {
			cfg := writeConfig(t, s.doc)
			oracle := shcl.Parse(s.doc)
			want := s.value
			if n := oracle.Count(s.key); n != 1 {
				want = oracle.GetStringOr(fmt.Sprintf("%s[#%d]", s.key, n-1), "")
			}
			// A protocol other than the two gitsby uses is listed, not kept.
			if s.accounts == nil && !protocolOK(want) {
				want = ""
			}
			got := cfg.values["protocol"]
			if s.accounts != nil {
				got = cfg.value("w", "email")
			}
			if got != want {
				t.Errorf("%q: %s = %q, want %q", s.doc, s.parent, got, want)
			}
			if len(cfg.paths) != 0 || len(cfg.segments) != 0 || !slices.Equal(cfg.accountNames(), s.accounts) {
				t.Errorf("%q: rules %v %v, accounts %v, want no rules and accounts %v", s.doc, cfg.paths, cfg.segments, cfg.accountNames(), s.accounts)
			}
			for j := range oracle.Count(s.key) {
				for _, name := range oracle.Children(fmt.Sprintf("%s[#%d]", s.key, j)) {
					if entry := s.disp + "." + name + " (indented under " + s.parent + ")"; !slices.Contains(cfg.unknown, entry) {
						t.Errorf("%q: unknown = %q, missing %q", s.doc, cfg.unknown, entry)
					}
				}
			}
		}
	})
}

func FuzzConfigKeyValue(f *testing.F) {
	f.Add("account.work.ghAccount", "my-login")
	f.Add("account.a.b.c", "  spaced  ")
	f.Add("", "\"quoted\"")
	for _, value := range []string{".", "dev/work", "~nobody/x", "C:work", "/srv/work"} {
		f.Add("account.f.path", value)
	}
	f.Fuzz(func(t *testing.T, key, value string) {
		if acct, field, ok := splitAccountKey(key); ok && (acct == "" || field == "") {
			t.Errorf("splitAccountKey(%q) said ok with empty parts (%q, %q)", key, acct, field)
		}
		parseConfigValue(value)
		// A 'path' value is a folder rule or it is listed, never both and never neither,
		// and no rule reaches git that git would measure from somewhere else.
		c := &config{values: map[string]string{}, file: "/cfg/config.shcl"}
		c.absorb("f", "path", value, "account.f.path")
		if value != "" && len(c.paths)+len(c.unknown) != 1 {
			t.Errorf("path %q: %d rules and %d ignored, want exactly one of the two", value, len(c.paths), len(c.unknown))
		}
		for _, r := range c.paths {
			if problem := folderRuleProblem(r.match); problem != "" {
				t.Errorf("path %q kept as %q, which is %s", value, r.match, problem)
			}
		}
		for _, rule := range c.accountApplyPlan() {
			pattern := strings.TrimSuffix(strings.TrimPrefix(rule.cond, "includeIf.gitdir/i:"), ".path")
			if !strings.HasPrefix(pattern, "**/") && folderRuleProblem(strings.TrimSuffix(pattern, "/")) != "" {
				t.Errorf("path %q goes to git as %q, which is not absolute", value, rule.cond)
			}
		}
	})
}
