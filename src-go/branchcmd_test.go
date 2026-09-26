// Which hotfix changes want a release. The names are all there is to go on, so
// this table is the rule.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"testing"
)

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

// A repo started with 'git init -b <name>' and never cloned has no origin/HEAD and
// none of the usual names, and guessing "main" there named a branch that did not
// exist. A lone branch is the default by elimination, and an unborn one by the
// name HEAD already carries.
func TestResolveDefaultBranchWithoutOrigin(t *testing.T) {
	if !inPath("git") {
		t.Skip("no git")
	}
	for _, name := range []string{"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS"} {
		t.Setenv(name, "")
		if err := os.Unsetenv(name); err != nil {
			t.Fatal(err)
		}
	}
	for name, value := range map[string]string{
		"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
		"GIT_AUTHOR_NAME": "Ada", "GIT_AUTHOR_EMAIL": "ada@example.test",
		"GIT_COMMITTER_NAME": "Ada", "GIT_COMMITTER_EMAIL": "ada@example.test",
	} {
		t.Setenv(name, value)
	}
	git := func(args ...string) {
		t.Helper()
		if out, err := exec.Command("git", args...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	tests := []struct {
		branch string
		commit bool
	}{
		{"mainline", true},
		{"trunkish", false},
	}
	for _, tc := range tests {
		t.Chdir(t.TempDir())
		git("init", "-q", "-b", tc.branch)
		if tc.commit {
			git("commit", "-q", "--allow-empty", "-m", "first")
		}
		if got := resolveDefaultBranch(); got != tc.branch {
			t.Errorf("resolveDefaultBranch() with commit=%v = %q, want %q", tc.commit, got, tc.branch)
		}
	}
}
