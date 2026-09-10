// The build number: minutes elapsed since 2000-01-01 UTC, Crockford base32, lower
// case. Five characters until 2063. Stamped at build time from the source commit's
// date rather than the clock, so the same commit always builds to the same bytes.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import "strconv"

// Set at build time: -ldflags "-X main.buildEpoch=<unix seconds>". Empty on a hand
// -run 'go build', which then reports no build number at all rather than inventing
// one - a number that moved every minute would say the opposite of what it means.
var buildEpoch = ""

// 2000-01-01T00:00:00Z as unix seconds.
const epoch2000 = 946684800

// Crockford's alphabet: no I, L, O or U, so nothing in a build number can be
// misread aloud or retyped as something else.
const crockford32 = "0123456789abcdefghjkmnpqrstvwxyz"

// buildNumber is the stamped seconds as minutes since 2000, base32. Anything before
// 2000, unparseable, or unstamped gives "", which every caller reads as "no build
// number" rather than as zero.
func buildNumber() string {
	if buildEpoch == "" {
		return ""
	}
	secs, err := strconv.ParseInt(buildEpoch, 10, 64)
	if err != nil || secs < epoch2000 {
		return ""
	}
	return crockfordBase32((secs - epoch2000) / 60)
}

func crockfordBase32(n int64) string {
	if n == 0 {
		return "0"
	}
	var digits []byte
	for n > 0 {
		digits = append(digits, crockford32[n%32])
		n /= 32
	}
	// Built least significant first.
	for i, j := 0, len(digits)-1; i < j; i, j = i+1, j-1 {
		digits[i], digits[j] = digits[j], digits[i]
	}
	return string(digits)
}

// versionText is "v2.1.0 build dbrk8", or just the version where nothing stamped a build.
func versionText() string {
	if b := buildNumber(); b != "" {
		return "v" + version + " build " + b
	}
	return "v" + version
}
