// Which hotfix changes want a release. The names are all there is to go on, so
// this table is the rule.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import "testing"

func TestDocsOnly(t *testing.T) {
	tests := []struct {
		files []string
		want  bool
	}{
		{nil, true},
		{[]string{""}, true},
		{[]string{"README.md", "docs/setup.png", "LICENSE", "Doc/guide.html", "notes.TXT"}, true},
		{[]string{"README.md", "src-go/main.go"}, false},
		{[]string{"lib/tool.py"}, false},
		{[]string{"install.bash"}, false},
		{[]string{"sub/docs/shot.png"}, false}, // only a docs folder at the top
	}
	for _, tc := range tests {
		if got := docsOnly(tc.files); got != tc.want {
			t.Errorf("docsOnly(%q) = %v, want %v", tc.files, got, tc.want)
		}
	}
}
