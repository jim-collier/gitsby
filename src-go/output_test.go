// The blank-line rhythm and the framing each ending prints. Both are contracts:
// the suite compares whole transcripts, so a blank that collapses where it used
// to land is a visible change.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"errors"
	"slices"
	"strings"
	"testing"
)

func testPrinter() (*printer, *strings.Builder, *strings.Builder) {
	var out, err strings.Builder
	return &printer{out: &out, err: &err}, &out, &err
}

func TestPrinterCollapsesRepeatedBlanks(t *testing.T) {
	p, out, _ := testPrinter()
	p.clean("")
	p.clean("")
	p.clean("one")
	p.clean("")
	p.clean("")
	p.clean("two")
	if got, want := out.String(), "\none\n\ntwo\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// forceClean is for the framing that has to be a fixed number of lines rather
// than a rhythm.
func TestPrinterForceClean(t *testing.T) {
	p, out, _ := testPrinter()
	p.clean("")
	p.forceClean("")
	p.forceClean("")
	if got, want := out.String(), "\n\n\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestPrinterStatus(t *testing.T) {
	p, out, _ := testPrinter()
	p.status("Done.")
	p.status("")
	if got, want := out.String(), "[ Done. ]\n\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// Only 'y' or 'yes' is yes: a typo, a stray newline, or an EOF is a no, because
// the fallback has to be the harmless answer.
func TestPrinterConfirm(t *testing.T) {
	for _, tc := range []struct {
		answer string
		want   bool
	}{
		{"y\n", true}, {"Y\n", true}, {"yes\n", true}, {" YES \n", true},
		{"n\n", false}, {"\n", false}, {"", false}, {"yep\n", false}, {"ya\n", false},
	} {
		p, _, _ := testPrinter()
		p.in = strings.NewReader(tc.answer)
		if got := p.confirm("Continue? (y|n): "); got != tc.want {
			t.Errorf("confirm(%q) = %v, want %v", tc.answer, got, tc.want)
		}
	}
}

// An error ends with two blanks where success ends with one; the message itself
// goes to stderr.
func TestUsageErrorFraming(t *testing.T) {
	p, out, errOut := testPrinter()
	code := reportExit(p, usagef("no such thing: '%s'.", "x"))
	if code != 1 {
		t.Errorf("exit code = %d, want 1", code)
	}
	if got, want := out.String(), "\n\n\n"; got != want {
		t.Errorf("stdout = %q, want %q", got, want)
	}
	if got, want := errOut.String(), "gitsby: no such thing: 'x'.\n"; got != want {
		t.Errorf("stderr = %q, want %q", got, want)
	}
}

// The errors the scripts raise inside a command substitution land with one
// trailing blank, because the subshell swallowed the wrapping ones.
func TestUsageSubErrorFraming(t *testing.T) {
	p, out, errOut := testPrinter()
	if code := reportExit(p, usageSubf("bad config.")); code != 1 {
		t.Errorf("exit code = %d, want 1", code)
	}
	if got, want := out.String(), "\n"; got != want {
		t.Errorf("stdout = %q, want %q", got, want)
	}
	if got, want := errOut.String(), "gitsby: bad config.\n"; got != want {
		t.Errorf("stderr = %q, want %q", got, want)
	}
}

// Nothing to do is a success everywhere here; a nonzero exit would tell a calling
// script the opposite.
func TestErrDoneExitsZeroAndSilently(t *testing.T) {
	p, out, errOut := testPrinter()
	if code := reportExit(p, errDone); code != 0 {
		t.Errorf("exit code = %d, want 0", code)
	}
	if out.String() != "" || errOut.String() != "" {
		t.Errorf("errDone printed something: %q / %q", out.String(), errOut.String())
	}
}

func TestStepErrorFraming(t *testing.T) {
	p, out, errOut := testPrinter()
	if code := reportExit(p, &stepError{disp: "git push", code: 128}); code != 1 {
		t.Errorf("exit code = %d, want 1", code)
	}
	if got, want := out.String(), "\n\n"; got != want {
		t.Errorf("stdout = %q, want %q", got, want)
	}
	if got, want := errOut.String(), "gitsby: 'git push' failed (exit 128).\n"; got != want {
		t.Errorf("stderr = %q, want %q", got, want)
	}
}

func TestSilentExitSaysNothing(t *testing.T) {
	p, out, errOut := testPrinter()
	if code := reportExit(p, silentExit(3)); code != 3 {
		t.Errorf("exit code = %d, want 3", code)
	}
	if out.String() != "" || errOut.String() != "" {
		t.Errorf("silentExit printed something: %q / %q", out.String(), errOut.String())
	}
}

// A wrapped error still has to be recognized as the ending it is.
func TestWrappedErrorsKeepTheirFraming(t *testing.T) {
	p, _, _ := testPrinter()
	if code := reportExit(p, errors.Join(errDone)); code != 0 {
		t.Errorf("wrapped errDone gave %d, want 0", code)
	}
}

// cached is what keeps "not asked yet" apart from "asked, and the answer is
// nothing" - the difference between one lookup and the same five over and over.
func TestCachedRemembersAnEmptyAnswer(t *testing.T) {
	var c cached[string]
	asked := 0
	ask := func() string { asked++; return "" }
	for range 3 {
		if got := c.get(ask); got != "" {
			t.Fatalf("get = %q", got)
		}
	}
	if asked != 1 {
		t.Errorf("asked %d times, want 1", asked)
	}
	c.forget()
	c.get(ask)
	if asked != 2 {
		t.Errorf("forget did not take: asked %d times", asked)
	}
}

// A capture read as a whole and then split kept the interior carriage returns:
// only the very end of the string had been trimmed. 'pr ok' read the PR's head
// branch out of a two-line answer that way, so on a host that writes CRLF the
// branch name carried one and matched no ref anywhere.
func TestSplitLines(t *testing.T) {
	tests := []struct {
		in   string
		want []string
	}{
		{"one\r\ntwo", []string{"one", "two"}},
		{"one\ntwo", []string{"one", "two"}},
		{"", []string{""}},
		{"only\r", []string{"only"}},
	}
	for _, tc := range tests {
		got := splitLines(tc.in)
		if !slices.Equal(got, tc.want) {
			t.Errorf("splitLines(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
