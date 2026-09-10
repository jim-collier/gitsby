// The build number. What matters is that it never invents one from a clock and
// never quietly reports zero for a stamp it could not read.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"strings"
	"testing"
)

func TestCrockfordBase32(t *testing.T) {
	tests := []struct {
		n    int64
		want string
	}{
		{0, "0"},
		{1, "1"},
		{9, "9"},
		{10, "a"},
		{17, "h"},
		{18, "j"}, // I is skipped
		{19, "k"},
		{20, "m"}, // L is skipped
		{31, "z"},
		{32, "10"},
		{14018084, "dbsh4"},
		{52596000, "1j5390"}, // year 2100
	}
	for _, tc := range tests {
		if got := crockfordBase32(tc.n); got != tc.want {
			t.Errorf("crockfordBase32(%d) = %q, want %q", tc.n, got, tc.want)
		}
	}
}

func TestCrockfordAlphabetOmitsAmbiguousLetters(t *testing.T) {
	if len(crockford32) != 32 {
		t.Fatalf("alphabet is %d characters, want 32", len(crockford32))
	}
	for _, c := range "ilou" {
		if strings.ContainsRune(crockford32, c) {
			t.Errorf("alphabet contains %q, which Crockford leaves out", c)
		}
	}
}

func TestBuildNumber(t *testing.T) {
	tests := []struct {
		stamp string
		want  string
	}{
		{"", ""},                     // a hand-run 'go build'
		{"not a number", ""},         //
		{"946684800", "0"},           // the epoch itself
		{"946684859", "0"},           // seconds round down
		{"946684860", "1"},           //
		{"0", ""},                    // before 2000: no answer, not zero
		{"-1", ""},                   //
		{"1787000000", "dbd05"},      //
		{"99999999999999999999", ""}, // overflows int64
	}
	saved := buildEpoch
	defer func() { buildEpoch = saved }()
	for _, tc := range tests {
		buildEpoch = tc.stamp
		if got := buildNumber(); got != tc.want {
			t.Errorf("buildNumber() with stamp %q = %q, want %q", tc.stamp, got, tc.want)
		}
	}
}

func TestVersionTextOmitsAnUnstampedBuild(t *testing.T) {
	savedEpoch, savedVer := buildEpoch, version
	defer func() { buildEpoch, version = savedEpoch, savedVer }()
	version = "2.1.0"

	buildEpoch = ""
	if got := versionText(); got != "v2.1.0" {
		t.Errorf("unstamped versionText() = %q, want %q", got, "v2.1.0")
	}
	buildEpoch = "1787000000"
	if got := versionText(); got != "v2.1.0 build dbd05" {
		t.Errorf("stamped versionText() = %q, want %q", got, "v2.1.0 build dbd05")
	}
}
