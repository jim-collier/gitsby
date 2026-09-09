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
