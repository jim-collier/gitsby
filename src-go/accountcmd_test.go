// The includeIf ordering, which is the whole reason 'account apply' exists: git
// takes the LAST rule that matches and gitsby takes the most specific, so the two
// only agree if the plan runs least specific to most.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func planFor(t *testing.T, body string) *config {
	t.Helper()
	cfg := writeConfig(t, body)
	return cfg
}

func TestAccountApplyPlanOrder(t *testing.T) {
	cfg := planFor(t, `
account.inner.path = /srv/code/client
account.outer.path = /srv/code
account.anywhere.pathContains = a/b
account.broad.pathContains = b
`)
	plan := cfg.accountApplyPlan()
	var conds []string
	for _, r := range plan {
		conds = append(conds, strings.TrimSuffix(strings.TrimPrefix(r.cond, "includeIf.gitdir/i:"), ".path"))
	}
	want := []string{"**/b/**", "**/a/b/**", "/srv/code/", "/srv/code/client/"}
	if len(conds) != len(want) {
		t.Fatalf("plan = %v, want %v", conds, want)
	}
	for i := range want {
		if conds[i] != want[i] {
			t.Fatalf("plan = %v, want %v", conds, want)
		}
	}
}

// Every rule points at the fragment for its own account, beside the config file
// that declared it.
func TestAccountApplyPlanTargets(t *testing.T) {
	cfg := planFor(t, "account.work.path = /srv/work\n")
	plan := cfg.accountApplyPlan()
	if len(plan) != 1 {
		t.Fatalf("plan = %v", plan)
	}
	if want := cfg.includeDir() + "/work.gitconfig"; plan[0].target != want {
		t.Errorf("target = %q, want %q", plan[0].target, want)
	}
	if !strings.HasSuffix(cfg.includeDir(), "/accounts") {
		t.Errorf("includeDir = %q", cfg.includeDir())
	}
}

// An account declared by its keys alone has no folder rule, so there is nothing
// to teach plain git.
func TestAccountApplyPlanEmptyWithoutFolderRules(t *testing.T) {
	cfg := planFor(t, "account.work.ghAccount = octocat\n")
	if plan := cfg.accountApplyPlan(); plan != nil {
		t.Errorf("plan = %v, want none", plan)
	}
}

// Least specific first, and equal specificity backwards: gitsby keeps the FIRST
// rule declared, so that one has to be written LAST for git to keep it too.
func TestSortIncludesTieBreaks(t *testing.T) {
	list := []includeCandidate{
		{weight: 2, order: 0, pattern: "/same/", account: "first"},
		{weight: 1, order: 1, pattern: "/short/", account: "second"},
		{weight: 2, order: 2, pattern: "/same/", account: "third"},
	}
	sortIncludes(list)
	want := []string{"second", "third", "first"}
	for i, name := range want {
		if list[i].account != name {
			t.Fatalf("sorted = %v, want accounts %v", list, want)
		}
	}
}

// The tie-break that matters: whichever account gitsby resolves a folder to has to
// be the one git resolves it to, and git takes the last rule written.
func TestAccountApplyPlanAgreesWithAccountForDir(t *testing.T) {
	cfg := planFor(t, `
account.abe.path = /srv/shared
account.zed.path = /srv/shared
`)
	plan := cfg.accountApplyPlan()
	if len(plan) != 2 {
		t.Fatalf("plan = %v", plan)
	}
	lastWins := plan[len(plan)-1].target
	want := cfg.includeDir() + "/" + cfg.accountForDir("/srv/shared/x") + ".gitconfig"
	if lastWins != want {
		t.Errorf("git would keep %q, gitsby resolves to %q", lastWins, want)
	}
}

// Two accounts on one folder is a mistake with no right answer, so it gets said
// out loud rather than settled silently.
func TestContestedRules(t *testing.T) {
	cfg := planFor(t, `
account.abe.path = /srv/shared
account.zed.path = /srv/shared
account.abe.pathContains = w/x
account.zed.pathContains = w/x
account.solo.path = /srv/mine
`)
	got := cfg.contestedRules()
	want := []string{"/srv/shared: abe, zed", "w/x: abe, zed"}
	if len(got) != len(want) {
		t.Fatalf("contestedRules = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("contestedRules = %v, want %v", got, want)
		}
	}
}

// What 'account list' says about an account, which is where you go when a command
// did not act as the one you expected. The host key decides whether any of the
// credentials below it apply at all, so leaving it off the listing meant the
// command that always says was silent about the only field that had refused.
func TestAccountListNamesTheHost(t *testing.T) {
	a := newApp(newPrinter())
	var buf strings.Builder
	a.out.out = &buf
	a.cfg = writeConfig(t, `
account.gitea.host = git.example.test
account.gitea.user = giteauser
account.hub.ghAccount = hublogin
`)
	a.showAccount("gitea", false)
	a.showAccount("hub", false)
	got := buf.String()
	for _, want := range []string{
		"host ....: git.example.test",      // stated
		"login ...: giteauser",             // the host-neutral login, shown where there is one
		"host ....: github.com  (default)", // unstated, and marked as the assumption it is
	} {
		if !strings.Contains(got, want) {
			t.Errorf("account list is missing %q:\n%s", want, got)
		}
	}
	// 'login' is the 'user' key, not a second spelling of the GitHub one - printing it
	// for an account that never set it would invent a login for every existing config.
	if strings.Contains(got, "login ...: hublogin") {
		t.Errorf("the GitHub login was printed as 'login':\n%s", got)
	}
}

// The host line is a comparison, so it appears only where there is something to
// compare. A machine that only ever talks to github.com reads exactly as it did
// before the key existed - the same rule the Account status line follows, which
// stays quiet unless an account was explicitly selected.
func TestAccountListHidesTheHostOnOneForge(t *testing.T) {
	a := newApp(newPrinter())
	var buf strings.Builder
	a.out.out = &buf
	a.cfg = writeConfig(t, `
account.work.ghAccount = worklogin
account.home.ghAccount = homelogin
`)
	a.showAccount("work", false)
	if strings.Contains(buf.String(), "host") {
		t.Errorf("a single-forge config was shown the host key:\n%s", buf.String())
	}
}

// setApp builds a run pointed at a real accounts file, for the writer below.
func setApp(t *testing.T, body, name, key, value string) (*app, string) {
	t.Helper()
	file := filepath.Join(t.TempDir(), "config.shcl")
	if err := os.WriteFile(file, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	a := newApp(newPrinter())
	a.opt.configFile, a.opt.configGiven, a.opt.quiet = file, true, true
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	a.cmd = command{name: "account-set", arg: name, arg2: key, arg3: value, mutating: true}
	return a, file
}

func readBack(t *testing.T, file string) string {
	t.Helper()
	got, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	return string(got)
}

// A file that isn't there yet is created with a header naming the keys, the one
// block asked for, and the footer naming the format - and closed to everyone
// else, since it names accounts and points at token files.
func TestAccountSetCreatesTheFile(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", "")
	t.Setenv("APPDATA", "")
	a := newApp(newPrinter())
	a.opt.quiet = true
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	a.cmd = command{name: "account-set", arg: "work", arg2: "path", arg3: "/srv/work", mutating: true}
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	file := defaultConfigFile()
	got := readBack(t, file)
	for _, want := range []string{"# " + meName + " accounts", "\naccount: work\n\tpath: /srv/work\n"} {
		if !strings.Contains(got, want) {
			t.Errorf("created file is missing %q:\n%s", want, got)
		}
	}
	if !strings.HasSuffix(got, "\n\n"+shclBanner) {
		t.Errorf("created file does not end with the format footer:\n%s", got)
	}
	if !strings.HasPrefix(got, "#") {
		t.Errorf("the header is not at the top:\n%s", got)
	}
	if fi, err := os.Stat(file); err == nil && !isWindows() && fi.Mode().Perm() != 0o600 {
		t.Errorf("mode = %v, want 0600", fi.Mode().Perm())
	}
	cfg := writeConfig(t, got)
	if cfg.accountForDir("/srv/work/x") != "work" {
		t.Errorf("the created file does not read back: %+v", cfg)
	}
}

// One key changes; the comments, the other keys and the footer stay where they
// were. The spacing is the format's own, which is the one thing a rewrite through
// the module changes.
func TestAccountSetReplacesOneKey(t *testing.T) {
	body := "# mine\n\naccount: work\n\tpath: /srv/work   # the tree\n\thost: github.com\n\temail: a@b.c\n\n" + shclBanner
	a, file := setApp(t, body, "work", "host", "gitea.com")
	plan, err := a.accountSetPlan()
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if !plan.exists || plan.lineNum != 5 || plan.old != "github.com" {
		t.Errorf("plan = %+v, want the existing key on line 5", plan)
	}
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	want := "# mine\n\naccount: work\n\tpath: /srv/work  # the tree\n\thost: gitea.com\n\temail: a@b.c\n\n" + shclBanner
	if got := readBack(t, file); got != want {
		t.Errorf("got:\n%q\nwant:\n%q", got, want)
	}
}

// A key the block doesn't have goes on the end of it; an account the file doesn't
// have gets a block of its own.
func TestAccountSetAddsKeysAndBlocks(t *testing.T) {
	a, file := setApp(t, "account: work\n\tpath: /srv/work\n", "work", "host", "gitea.com")
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	if got, want := readBack(t, file), "account: work\n\tpath: /srv/work\n\thost: gitea.com\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
	a, file = setApp(t, "account: work\n\tpath: /srv/work\n", "home", "ghaccount", "homelogin")
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	if got := readBack(t, file); !strings.Contains(got, "\naccount: home\n\tghaccount: homelogin\n") {
		t.Errorf("got %q", got)
	}
}

// The dotted spelling is what a hand conversion of the old layout produces, and a
// key set into such an account has to go into that block, not open a second one.
func TestAccountSetKeepsTheDottedForm(t *testing.T) {
	a, file := setApp(t, "account.work.path: /srv/work\n", "work", "host", "gitea.com")
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	got := readBack(t, file)
	if strings.Count(got, "\twork:\n") != 1 || strings.Contains(got, "account: work") || !strings.Contains(got, "\t\thost: gitea.com\n") {
		t.Errorf("got %q", got)
	}
}

// A file in the old layout is rewritten in the current one on its first edit,
// comments and all. The mark a Windows editor wrote and its line endings go, since
// the module writes one shape.
func TestAccountSetConvertsAFlatFile(t *testing.T) {
	body := utf8BOM + "# mine\r\naccount.work.path = C:/work   # tree\r\naccount.work.ghAccount = \"a#b\"\r\nprotocol = https\r\n"
	a, file := setApp(t, body, "work", "host", "gitea.com")
	plan, err := a.accountSetPlan()
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if !plan.converts || plan.exists {
		t.Errorf("plan = %+v, want a conversion adding a key", plan)
	}
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	got := readBack(t, file)
	if strings.Contains(got, utf8BOM) || strings.Contains(got, "\r") || strings.Contains(got, " = ") {
		t.Errorf("the old layout is still in there: %q", got)
	}
	for _, want := range []string{"# mine\n\naccount: work\n", "  # tree\n", "\thost: gitea.com\n", "\nprotocol: https\n", shclBanner} {
		if !strings.Contains(got, want) {
			t.Errorf("converted file is missing %q:\n%s", want, got)
		}
	}
	cfg := writeConfig(t, got)
	if cfg.flat || cfg.value("work", "host") != "gitea.com" || cfg.value("work", "ghAccount") != "a#b" || cfg.values["protocol"] != "https" {
		t.Errorf("read back wrong: %+v", cfg.values)
	}
	if got := cfg.foldersOf("work"); len(got) != 1 || got[0] != "C:/work" {
		t.Errorf("folders = %v", got)
	}
}

// 'path' is repeatable by design and any key can be in there twice by accident.
// Replacing the first and leaving the rest looks like it worked and changes
// nothing that is read. Both layouts.
func TestAccountSetRefusesADuplicatedKey(t *testing.T) {
	for _, body := range []string{"account.work.path = /a\naccount.work.path = /b\n", "account: work\n\tpath: /a\n\tpath: /b\n"} {
		a, _ := setApp(t, body, "work", "path", "/c")
		if err := a.cmdAccountSet(); err == nil {
			t.Errorf("a key present twice was written anyway: %q", body)
		}
	}
}

// A key the loader ignores, written past this command, lands in the file and is
// dropped on every read: the file says one thing and every command does another.
func TestAccountSetRefusesAKeyNothingReads(t *testing.T) {
	a, _ := setApp(t, "account: work\n\tpath: /a\n", "work", "hostname", "gitea.com")
	if err := a.cmdAccountSet(); err == nil {
		t.Error("an unread key was accepted")
	}
}

// 'host' and 'user' are interpolated into the credential helper, which git hands
// to a shell. The loader drops one carrying a shell character; refusing to WRITE
// it is what stops the file and the behavior disagreeing.
func TestAccountSetRefusesAShellCharacterInHost(t *testing.T) {
	a, _ := setApp(t, "account: work\n\tpath: /a\n", "work", "host", "gitea.com; id")
	if err := a.cmdAccountSet(); err == nil {
		t.Error("a shell character reached the file")
	}
}

// The casing typed is not the casing written: the format folds key names to lower
// case, so that is the spelling every file settles on.
func TestAccountSetWritesTheDocumentedSpelling(t *testing.T) {
	a, file := setApp(t, "account: work\n\tpath: /a\n", "WORK", "TOKENFILE", "/t")
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	if got := readBack(t, file); !strings.Contains(got, "\ttokenfile: /t\n") {
		t.Errorf("got %q", got)
	}
}

// A value carrying ' #' is a comment from that point on when it is read back, so
// it has to go in quoted or the account silently gets a truncated value.
func TestAccountSetQuotesAValueThatWouldBeReparsed(t *testing.T) {
	a, file := setApp(t, "account: work\n\tpath: /a\n", "work", "name", "Ada #1")
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	got := readBack(t, file)
	if !strings.Contains(got, "\tname: \"Ada #1\"\n") {
		t.Fatalf("got %q", got)
	}
	// The round trip is the actual claim: it has to read back as what was typed.
	cfg := writeConfig(t, got)
	if cfg.value("work", "name") != "Ada #1" {
		t.Errorf("read back as %q", cfg.value("work", "name"))
	}
}
