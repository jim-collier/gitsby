// br prune's pure halves: what origin answered, how the remote candidates sort
// against it, and how the leased delete push splits.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"reflect"
	"strings"
	"testing"
)

func TestParseOriginHeads(t *testing.T) {
	a40, b40, c64 := strings.Repeat("a", 40), strings.Repeat("b", 40), strings.Repeat("c", 64)
	lf := a40 + "\trefs/heads/foo\n" + b40 + "\trefs/heads/x/refs/heads/foo\n"
	want := map[string]string{"refs/heads/foo": a40, "refs/heads/x/refs/heads/foo": b40}
	for name, out := range map[string]string{"lf": lf, "crlf": strings.ReplaceAll(lf, "\n", "\r\n")} {
		got := parseOriginHeads(out)
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s: parseOriginHeads = %q, want %q", name, got, want)
		}
		// The tail match must not stand in for the branch asked about.
		if got["refs/heads/foo"] != a40 {
			t.Errorf("%s: refs/heads/foo = %q, want %q", name, got["refs/heads/foo"], a40)
		}
	}
	if got := parseOriginHeads(c64 + "\trefs/heads/long\n"); got["refs/heads/long"] != c64 {
		t.Errorf("a SHA-256 object came back as %q", got["refs/heads/long"])
	}
	if got := parseOriginHeads(""); len(got) != 0 {
		t.Errorf("empty output gave %q", got)
	}
	if got := parseOriginHeads(a40 + " refs/heads/spaced\n" + b40 + "\trefs/tags/v1\n\trefs/heads/noobject\n"); len(got) != 0 {
		t.Errorf("lines with no tab, no object or no branch gave %q", got)
	}
}

func TestSortRemoteDeletes(t *testing.T) {
	tested := map[string]string{"a": "1", "b": "2", "c": "3", "d": "4"}
	onOrigin := map[string]string{"refs/heads/a": "1", "refs/heads/b": "9", "refs/heads/d": "4", "refs/heads/e": "5"}
	send, changed, gone := sortRemoteDeletes([]string{"a", "b", "c", "d", "e"}, tested, onOrigin)
	if want := []string{"a", "d"}; !reflect.DeepEqual(send, want) {
		t.Errorf("send = %q, want %q", send, want)
	}
	// e was never tested, so it is left alone rather than sent.
	if want := []string{"b", "e"}; !reflect.DeepEqual(changed, want) {
		t.Errorf("changed = %q, want %q", changed, want)
	}
	if want := []string{"c"}; !reflect.DeepEqual(gone, want) {
		t.Errorf("gone = %q, want %q", gone, want)
	}
}

func argListLen(args []string) int {
	n := 0
	for _, arg := range args {
		n += len(arg) + 1
	}
	return n
}

func TestLeaseDeleteBatches(t *testing.T) {
	got := leaseDeleteBatches([]string{"a", "b"}, map[string]string{"a": "va", "b": "vb"}, leasePushBudget)
	want := [][]string{{"push", "--force-with-lease=refs/heads/a:va", "--force-with-lease=refs/heads/b:vb", "origin", "--delete", "refs/heads/a", "refs/heads/b"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("leaseDeleteBatches = %q, want %q", got, want)
	}

	tested := map[string]string{}
	var names []string
	for _, name := range []string{"b1", "b2", "b3", "b4", "b5"} {
		names = append(names, name)
		tested[name] = strings.Repeat(name[1:], 40)
	}
	// Exactly two of these fit.
	budget := argListLen([]string{"push", leaseArg("b1", tested["b1"]), leaseArg("b2", tested["b2"]), "origin", "--delete", "refs/heads/b1", "refs/heads/b2"})
	checkBatches(t, "five", leaseDeleteBatches(names, tested, budget), tested, budget, [][]string{{"b1", "b2"}, {"b3", "b4"}, {"b5"}}, "")

	long := strings.Repeat("x", budget)
	tested[long] = strings.Repeat("f", 40)
	names = []string{"b1", long, "b2", "b3"}
	checkBatches(t, "long", leaseDeleteBatches(names, tested, budget), tested, budget, [][]string{{"b1"}, {long}, {"b2", "b3"}}, long)
}

// checkBatches holds each batch to its shape: its leases, then origin --delete, then
// the same branches in order, within budget unless it carries the one oversized name.
func checkBatches(t *testing.T, name string, got [][]string, tested map[string]string, budget int, wantBranches [][]string, oversized string) {
	t.Helper()
	if len(got) != len(wantBranches) {
		t.Fatalf("%s: %d batches, want %d: %q", name, len(got), len(wantBranches), got)
	}
	for i, args := range got {
		branches := wantBranches[i]
		want := []string{"push"}
		for _, branch := range branches {
			want = append(want, leaseArg(branch, tested[branch]))
		}
		want = append(want, "origin", "--delete")
		for _, branch := range branches {
			want = append(want, "refs/heads/"+branch)
		}
		if !reflect.DeepEqual(args, want) {
			t.Errorf("%s: batch %d = %q, want %q", name, i, args, want)
		}
		if branches[0] != oversized && argListLen(args) > budget {
			t.Errorf("%s: batch %d is %d bytes, past the budget of %d", name, i, argListLen(args), budget)
		}
	}
}

func TestOriginTips(t *testing.T) {
	got := originTips([]string{"a1 refs/remotes/origin/foo", "b2 refs/remotes/origin/feature/x", "c3 refs/heads/foo", "nospace", ""})
	want := map[string]string{"foo": "a1", "feature/x": "b2"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("originTips = %q, want %q", got, want)
	}
}

func TestTypedArg(t *testing.T) {
	for _, c := range []struct{ word, goos, want string }{
		{"feature/x-1_2", "linux", "feature/x-1_2"},
		{"--force-with-lease=refs/heads/a:0f", "linux", "--force-with-lease=refs/heads/a:0f"},
		{"a;rm", "linux", "'a;rm'"},
		{"$(x)", "darwin", "'$(x)'"},
		{"it's", "linux", `'it'\''s'`},
		{"", "linux", "''"},
		{"a;rm", "windows", "'a;rm'"},
		{"it's", "windows", "'it''s'"},
		{"refs/heads/v1.2", "windows", "refs/heads/v1.2"},
		{"--force-with-lease=refs/heads/v1.2:0f", "windows", "'--force-with-lease=refs/heads/v1.2:0f'"},
		{"--force-with-lease=refs/heads/v1.2:0f", "linux", "--force-with-lease=refs/heads/v1.2:0f"},
	} {
		if got := typedArg(c.word, c.goos); got != c.want {
			t.Errorf("typedArg(%q, %s) = %s, want %s", c.word, c.goos, got, c.want)
		}
	}
}

func TestLeaseDeleteLine(t *testing.T) {
	if got, want := leaseDeleteLine("far", "0f", "linux"), "git push --force-with-lease=refs/heads/far:0f origin --delete refs/heads/far"; got != want {
		t.Errorf("leaseDeleteLine = %s, want %s", got, want)
	}
	if got, want := leaseDeleteLine("a$b", "0f", "linux"), "git push '--force-with-lease=refs/heads/a$b:0f' origin --delete 'refs/heads/a$b'"; got != want {
		t.Errorf("leaseDeleteLine = %s, want %s", got, want)
	}
}
