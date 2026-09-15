// Version bumping. The suffix cases are the ones that matter: a candidate's own
// version is what follows it, and calling that an invented version would let the
// "nothing new to release" guard refuse a deliberate promotion.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import "testing"

func TestNextVersion(t *testing.T) {
	tests := []struct {
		latest string
		want   string
		bumped bool
	}{
		{"v2.1.0", "2.1.1", true},
		{"2.1.0", "2.1.1", true},
		{"v2.1.9", "2.1.10", true},
		{"v1.2", "1.2.1", true}, // short tags pad out
		{"v2020", "2020.0.1", true},
		{"v2.0.0-rc1", "2.0.0", false}, // promoting a candidate is deliberate
		{"v2.0.0.beta", "2.0.0", false},
		{"", "0.1.0", true}, // first release ever
		{"nonsense", "0.1.0", true},
	}
	for _, tc := range tests {
		got, bumped := nextVersion(tc.latest)
		if got != tc.want || bumped != tc.bumped {
			t.Errorf("nextVersion(%q) = %q,%v; want %q,%v", tc.latest, got, bumped, tc.want, tc.bumped)
		}
	}
}

// The scan only read tags with a 'v', so a repo tagged 1.4.2 started over at 0.1.0,
// and pushed it.
func TestNewestReleaseTag(t *testing.T) {
	tests := []struct {
		sorted []string
		want   string
	}{
		{nil, ""},
		{[]string{"v1.2.0", "v1.1.0"}, "v1.2.0"},
		{[]string{"1.4.2", "1.4.1"}, "1.4.2"},
		{[]string{"v1.0.0", "2.0.0"}, "2.0.0"},
		{[]string{"2.9.9", "v3.0.0"}, "v3.0.0"},
		{[]string{"20260915", "1.0.0"}, "1.0.0"}, // a date is not a version
		{[]string{"20260915"}, ""},
		{[]string{"v2.0.0", "2.0.0-rc1"}, "v2.0.0"},
		{[]string{"v2.0.0-rc1", "2.0.0"}, "2.0.0"},
	}
	for _, tc := range tests {
		if got := newestReleaseTag(tc.sorted); got != tc.want {
			t.Errorf("newestReleaseTag(%q) = %q, want %q", tc.sorted, got, tc.want)
		}
	}
}

// Every new tag used to gain a 'v', so a repo tagged 1.4.2 went on with v1.4.3.
func TestNextReleaseTag(t *testing.T) {
	tests := []struct{ latest, want string }{
		{"", "v0.1.0"},
		{"v1.4.2", "v1.4.3"},
		{"1.4.2", "1.4.3"},
		{"1.3.0-rc1", "1.3.0"},
	}
	for _, tc := range tests {
		if got, _ := nextReleaseTag(tc.latest); got != tc.want {
			t.Errorf("nextReleaseTag(%q) = %q, want %q", tc.latest, got, tc.want)
		}
	}
}

func TestReleaseVersionShape(t *testing.T) {
	for _, ok := range []string{"1.0.0", "10.20.30", "2.0.0-rc1", "2.0.0.beta"} {
		if !releaseVerRE.MatchString(ok) {
			t.Errorf("%q was refused", ok)
		}
	}
	for _, bad := range []string{"1", "1.0", "v1.0.0", "1.0.0 ", "one.two.three", ""} {
		if releaseVerRE.MatchString(bad) {
			t.Errorf("%q was accepted", bad)
		}
	}
}
