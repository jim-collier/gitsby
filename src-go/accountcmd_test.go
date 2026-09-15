// The includeIf ordering, which is the whole reason 'account apply' exists: git
// takes the LAST rule that matches and gitsby takes the most specific, so the two
// only agree if the plan runs least specific to most.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

func planFor(t *testing.T, body string) *config {
	t.Helper()
	cfg := writeConfig(t, body)
	return cfg
}

func TestAccountApplyPlanOrder(t *testing.T) {
	cfg := planFor(t, driveFixture(`
account.inner.path = /srv/code/client
account.outer.path = /srv/code
account.anywhere.pathContains = a/b
account.broad.pathContains = b
`))
	plan := cfg.accountApplyPlan()
	var conds []string
	for _, r := range plan {
		conds = append(conds, strings.TrimSuffix(strings.TrimPrefix(r.cond, "includeIf.gitdir/i:"), ".path"))
	}
	want := []string{"**/b/**", "**/a/b/**", driveRule("/srv/code") + "/", driveRule("/srv/code/client") + "/"}
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
	cfg := planFor(t, driveFixture("account.work.path = /srv/work\n"))
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

// However the accounts file is named, the fragments go in the folder holding it.
// Joined with backslashes on Windows, or named with no folder, they went under
// the file itself and apply refused.
func TestIncludeDir(t *testing.T) {
	dir := t.TempDir()
	t.Chdir(dir)
	want := filepath.ToSlash(dir) + "/accounts"
	for _, file := range []string{filepath.Join(dir, "wl.shcl"), filepath.ToSlash(dir) + "/wl.shcl", "wl.shcl"} {
		if got := (&config{file: file}).includeDir(); got != want {
			t.Errorf("includeDir for %q = %q, want %q", file, got, want)
		}
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
	cfg := planFor(t, driveFixture(`
account.abe.path = /srv/shared
account.zed.path = /srv/shared
`))
	plan := cfg.accountApplyPlan()
	if len(plan) != 2 {
		t.Fatalf("plan = %v", plan)
	}
	lastWins := plan[len(plan)-1].target
	want := cfg.includeDir() + "/" + cfg.accountForDir(driveFolder("/srv/shared/x")) + ".gitconfig"
	if lastWins != want {
		t.Errorf("git would keep %q, gitsby resolves to %q", lastWins, want)
	}
}

// Two accounts on one folder is a mistake with no right answer, so it gets said
// out loud rather than settled silently.
func TestContestedRules(t *testing.T) {
	cfg := planFor(t, driveFixture(`
account.abe.path = /srv/shared
account.zed.path = /srv/shared
account.abe.pathContains = w/x
account.zed.pathContains = w/x
account.solo.path = /srv/mine
`))
	got := cfg.contestedRules()
	want := []string{driveRule("/srv/shared") + ": abe, zed", "w/x: abe, zed"}
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
	folder := driveFolder("/srv/work")
	a.cmd = command{name: "account-set", arg: "work", arg2: "path", arg3: folder, mutating: true}
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	file := defaultConfigFile()
	got := readBack(t, file)
	block := "\naccount: work\n\tpath: /srv/work\n"
	if isWindows() {
		block = "\naccount: work\n\tpath: \"C:/srv/work\"\n" // the format quotes a drive path
	}
	for _, want := range []string{"# " + meName + " accounts", block} {
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
	if cfg.accountForDir(driveFolder("/srv/work/x")) != "work" {
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
	// A drive path is a folder on Windows alone; anywhere else it is listed as ignored.
	if isWindows() {
		if got := cfg.foldersOf("work"); len(got) != 1 || got[0] != "c:/work" {
			t.Errorf("folders = %v", got)
		}
		return
	}
	if got := cfg.foldersOf("work"); len(got) != 0 {
		t.Errorf("folders = %v, want none off Windows", got)
	}
	if want := "account[work].path (not an absolute folder: C:/work)"; !slices.Contains(cfg.unknown, want) {
		t.Errorf("unknown = %q, missing %q", cfg.unknown, want)
	}
}

// A relative path on the command line means the folder the command runs in, as
// it does for any command. The file can never say that later, so it is written
// absolute, and the plan shows that value.
func TestAccountSetResolvesARelativePath(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	dir := t.TempDir()
	t.Chdir(dir)
	want, err := filepath.Abs(".")
	if err != nil {
		t.Fatal(err)
	}
	want = filepath.ToSlash(want)
	abs := filepath.ToSlash(t.TempDir())
	cases := map[string]string{
		".":      want,
		"sub/..": want,
		"sub":    want + "/sub",
		"~/dev":  "~/dev",
		abs:      abs,
		"":       "",
	}
	for in, out := range cases {
		a, _ := setApp(t, "", "work", "path", in)
		plan, err := a.accountSetPlan()
		if err != nil {
			t.Errorf("plan for %q: %v", in, err)
			continue
		}
		if plan.value != out {
			t.Errorf("plan for %q writes %q, want %q", in, plan.value, out)
		}
	}
	a, file := setApp(t, "", "work", "path", ".")
	if err := a.cmdAccountSet(); err != nil {
		t.Fatalf("set: %v", err)
	}
	if got := readBack(t, file); !strings.Contains(got, "path: "+shclValue(want)) {
		t.Errorf("file does not hold the absolute folder %q:\n%s", want, got)
	}
}

// gitsby expands only a bare '~' and git expands another user's too, so the two
// would read such a rule differently. Refused before anything is written.
func TestAccountSetRefusesAnotherUsersHome(t *testing.T) {
	body := "account: work\n\temail: w@example.com\n"
	a, file := setApp(t, body, "work", "path", "~nobody/x")
	if err := a.cmdAccountSet(); err == nil || !strings.Contains(err.Error(), "another user's home folder") {
		t.Errorf("err = %v, want a refusal naming another user's home folder", err)
	}
	if got := readBack(t, file); got != body {
		t.Errorf("file changed:\n%s", got)
	}
	if isWindows() {
		return
	}
	t.Setenv("HOME", "")
	a, file = setApp(t, body, "work", "path", "~/x")
	if err := a.cmdAccountSet(); err == nil || !strings.Contains(err.Error(), "names no home folder") {
		t.Errorf("err = %v, want a refusal naming no home folder", err)
	}
	if got := readBack(t, file); got != body {
		t.Errorf("file changed:\n%s", got)
	}
}

func TestManagedIncludePattern(t *testing.T) {
	cases := []struct {
		key, want string
		ok        bool
	}{
		{"includeIf.gitdir/i:./.path", "./", true},
		{"includeIf.gitdir:dev/work/.path", "dev/work/", true},
		{"includeIf.gitdir/i:**/a/b/**.path", "**/a/b/**", true},
		{"includeIf.gitdir/i:/srv/a.b/.path", "/srv/a.b/", true},
		{"includeif.GITDIR/I:/Srv/X/.PATH", "/Srv/X/", true},
		{"includeIf.onbranch:main.path", "", false},
	}
	for _, tc := range cases {
		got, ok := managedIncludePattern(tc.key)
		if got != tc.want || ok != tc.ok {
			t.Errorf("managedIncludePattern(%q) = %q, %v; want %q, %v", tc.key, got, ok, tc.want, tc.ok)
		}
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

const keptBody = "account: work\n\tghaccount: keepme\n"

// createApp is a run with no accounts file anywhere it looks, about to create one.
// Nothing is loaded, so a test can put something in the way first.
func createApp(t *testing.T, out *printer) *app {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", "")
	t.Setenv("APPDATA", "")
	t.Setenv("GITSBY_CONFIG", "")
	a := newApp(out)
	a.opt.quiet = true
	a.cmd = command{name: "account-set", arg: "work", arg2: "email", arg3: "x@example.com", mutating: true}
	return a
}

// putDefaultConfig writes body where a new accounts file would go.
func putDefaultConfig(t *testing.T, body string) string {
	t.Helper()
	file := defaultConfigFile()
	if err := os.MkdirAll(filepath.Dir(file), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return file
}

// The create opens so it cannot replace anything: a file already there keeps every
// byte, and a missing one is made 0600 with the text in it.
func TestCreateAccountsFileNeverReplaces(t *testing.T) {
	file := filepath.Join(t.TempDir(), "config.shcl")
	if err := os.WriteFile(file, []byte(keptBody), 0o600); err != nil {
		t.Fatal(err)
	}
	opened, err := createAccountsFile(file, "new")
	if opened || !errors.Is(err, fs.ErrExist) {
		t.Errorf("over a file: opened = %v, err = %v, want not opened and an exists error", opened, err)
	}
	if got := readBack(t, file); got != keptBody {
		t.Errorf("the file already there changed:\n%q", got)
	}
	fresh := filepath.Join(t.TempDir(), "fresh.shcl")
	if opened, err = createAccountsFile(fresh, "new"); !opened || err != nil {
		t.Errorf("where nothing is: opened = %v, err = %v, want opened and no error", opened, err)
	}
	if got := readBack(t, fresh); got != "new" {
		t.Errorf("created file holds %q, want %q", got, "new")
	}
	if fi, err := os.Stat(fresh); err == nil && !isWindows() && fi.Mode().Perm() != 0o600 {
		t.Errorf("mode = %v, want 0600", fi.Mode().Perm())
	}
}

// The item's case: a discovered file this user can write and can't read. Reads
// pass over it, and the create refuses by name instead of truncating it.
func TestAccountSetRefusesAnUnreadableFile(t *testing.T) {
	if isWindows() || os.Geteuid() == 0 {
		t.Skip("needs a file this user can't read: Windows has no 0200, and root reads through one")
	}
	a := createApp(t, newPrinter())
	file := putDefaultConfig(t, keptBody)
	if err := os.Chmod(file, 0o200); err != nil {
		t.Fatal(err)
	}
	// Put back so nothing left over is unreadable; a failed restore changes no result.
	t.Cleanup(func() { _ = os.Chmod(file, 0o600) })
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	if a.cfg.file != "" {
		t.Errorf("reads took up the unreadable file: %q", a.cfg.file)
	}
	if _, err := a.accountSetPlan(); err == nil || !strings.HasPrefix(err.Error(), "An accounts file is already there, and it can't be read.") {
		t.Errorf("plan: err = %v, want the unreadable refusal", err)
	}
	err := a.cmdAccountSet()
	if err == nil {
		t.Fatal("set: no refusal")
	}
	for _, want := range []string{"File: " + displayPath(file), "permission denied", "Kept: Nothing was written.", "chmod u+r '" + file + "'"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal is missing %q:\n%s", want, err)
		}
	}
	if err := os.Chmod(file, 0o600); err != nil {
		t.Fatal(err)
	}
	if got := readBack(t, file); got != keptBody {
		t.Errorf("the unreadable file changed:\n%q", got)
	}
}

// A place reads look in that can't be looked in may hold an accounts file, and a
// new one ahead of it would hide it from every later command.
func TestAccountSetRefusesAPlaceItCantLookIn(t *testing.T) {
	if isWindows() || os.Geteuid() == 0 {
		t.Skip("needs a folder this user can't search: Windows has no mode bits for it, and root searches through one")
	}
	a := createApp(t, newPrinter())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	c := configCandidates()
	if len(c) < 2 {
		t.Skip("this platform looks in one place only")
	}
	hidden := c[1]
	dir := filepath.Dir(hidden)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(hidden, []byte(keptBody), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o600); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o700) })
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	err := a.cmdAccountSet()
	if err == nil {
		t.Fatal("set: no refusal")
	}
	for _, want := range []string{"File: " + displayPath(hidden), "permission denied", "Kept: Nothing was written.", "chmod u+x '" + dir + "'"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal is missing %q:\n%s", want, err)
		}
	}
	if _, err := os.Lstat(c[0]); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("a file was made ahead of it: %v", err)
	}
}

// A file that opens and then fails to read. Named, it is refused like one that
// won't open. Found, reads pass over it and 'account set' refuses it. It was
// recorded before the read, and the edit then worked from no document at all.
func TestConfigThatFailsToRead(t *testing.T) {
	const mem = "/proc/self/mem"
	if !isRegularFile(mem) {
		t.Skip("needs a file that opens and then fails to read, which " + mem + " is on Linux")
	}
	named := createApp(t, newPrinter())
	t.Setenv("GITSBY_CONFIG", mem)
	if err := named.cfg.load(named.opt); err == nil || !strings.Contains(err.Error(), "can't be read") {
		t.Errorf("named: load err = %v, want the can't-be-read refusal", err)
	}
	found := createApp(t, newPrinter())
	file := defaultConfigFile()
	if err := os.MkdirAll(filepath.Dir(file), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(mem, file); err != nil {
		t.Skipf("no symlink here: %v", err)
	}
	if err := found.cfg.load(found.opt); err != nil {
		t.Fatalf("found: load: %v", err)
	}
	if found.cfg.file != "" {
		t.Fatalf("reads took up a file that fails to read: %q", found.cfg.file)
	}
	if _, err := found.accountSetPlan(); err == nil || !strings.HasPrefix(err.Error(), "An accounts file is already there, and it can't be read.") {
		t.Errorf("found: plan err = %v, want the unreadable refusal", err)
	}
}

// A file that arrives between the load and the write is refused and kept, not
// replaced by the one this run planned from nothing.
func TestAccountSetRefusesAFileThatAppeared(t *testing.T) {
	a := createApp(t, newPrinter())
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	file := putDefaultConfig(t, keptBody)
	if err := a.cmdAccountSet(); err == nil || !strings.Contains(err.Error(), "turned up while this ran") {
		t.Errorf("set: err = %v, want the turned-up refusal", err)
	}
	if got := readBack(t, file); got != keptBody {
		t.Errorf("the file that turned up changed:\n%q", got)
	}
}

// A link to a missing file is refused, and nothing is made where it points: that
// is often a synced or unmounted folder that will come back.
func TestAccountSetRefusesALinkToNothing(t *testing.T) {
	a := createApp(t, newPrinter())
	file := defaultConfigFile()
	target := filepath.Join(homeDir(), "dot", "config.shcl")
	for _, dir := range []string{filepath.Dir(file), filepath.Dir(target)} {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(target, file); err != nil {
		t.Skipf("no symlink here: %v", err)
	}
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	err := a.cmdAccountSet()
	if err == nil {
		t.Fatal("set: no refusal")
	}
	for _, want := range []string{"is a link to something that isn't there", "Link: "} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal is missing %q:\n%s", want, err)
		}
	}
	if _, err := os.Lstat(target); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("something was made where the link points: %v", err)
	}
}

// A folder where the file goes is named as a folder, not blamed on permissions.
func TestAccountSetRefusesSomethingElseInTheWay(t *testing.T) {
	a := createApp(t, newPrinter())
	if err := os.MkdirAll(defaultConfigFile(), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	_, err := a.accountSetPlan()
	if err == nil {
		t.Fatal("plan: no refusal")
	}
	for _, want := range []string{"isn't a file", "It is a folder"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal is missing %q:\n%s", want, err)
		}
	}
}

func TestUnreadableFix(t *testing.T) {
	tests := []struct {
		goos, file string
		cause      error
		want       []string
	}{
		{"linux", "/h/c.shcl", fs.ErrPermission, []string{"Make it readable, then run this again:", "  chmod u+r '/h/c.shcl'"}},
		{"linux", "/h/it's.shcl", fs.ErrPermission, []string{"Make it readable, then run this again."}},
		{"windows", "C:/c.shcl", fs.ErrPermission, []string{"Give your account read access to it, then run this again."}},
		{"linux", "/h/c.shcl", errors.New("input/output error"), []string{"Run this again once it can be read."}},
	}
	for _, tt := range tests {
		if got := unreadableFix(tt.goos, tt.file, tt.cause); !slices.Equal(got, tt.want) {
			t.Errorf("unreadableFix(%q, %q, %v) = %q, want %q", tt.goos, tt.file, tt.cause, got, tt.want)
		}
	}
}

// The plan prints a refusal inside a parenthesis, where a labeled block would come
// out broken, so it shows the first line and the command prints the rest.
func TestAccountSetPreviewShowsTheRefusalsFirstLine(t *testing.T) {
	p, out, _ := testPrinter()
	a := createApp(t, p)
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	putDefaultConfig(t, keptBody)
	a.preview("account-set")
	if !strings.Contains(out.String(), "(nothing: An accounts file turned up while this ran.)") {
		t.Errorf("plan does not show the refusal's first line:\n%s", out)
	}
	for _, line := range strings.Split(out.String(), "\n") {
		if strings.HasPrefix(line, "  File:") {
			t.Errorf("plan shows the refusal's labels:\n%s", out)
		}
	}
}

func TestLookupFix(t *testing.T) {
	tests := []struct {
		goos, file string
		cause      error
		want       string
	}{
		{"linux", "/h/c.shcl", errors.New("input/output error"), "Run this again once it can be looked up."},
		{"windows", "C:/h/c.shcl", fs.ErrPermission, "Give your account access to the folder it is in, then run this again."},
		{"linux", "/h/it's/c.shcl", fs.ErrPermission, "Make the folder it is in searchable, then run this again."},
		{"linux", "/nonexistent-top/h/c.shcl", fs.ErrPermission, "Make the folders above it searchable, then run this again."},
	}
	for _, tc := range tests {
		if got := lookupFix(tc.goos, tc.file, tc.cause); len(got) != 1 || got[0] != tc.want {
			t.Errorf("lookupFix(%s, %s, %v) = %q, want %q", tc.goos, tc.file, tc.cause, got, tc.want)
		}
	}
}

// The item's case: two edits of one file at once, each saving the file whole. A
// run that says it wrote keeps its key, and at most one of the two refuses.
func TestAccountSetKeepsBothOfTwoEditsAtOnce(t *testing.T) {
	for try := range 20 {
		first, file := setApp(t, keptBody, "work", "email", "x@example.com")
		second := newApp(newPrinter())
		second.opt = first.opt
		if err := second.cfg.load(second.opt); err != nil {
			t.Fatalf("load: %v", err)
		}
		second.cmd = command{name: "account-set", arg: "work", arg2: "name", arg3: "Ada", mutating: true}
		errs := make([]error, 2)
		var wg sync.WaitGroup
		for i, a := range []*app{first, second} {
			wg.Go(func() { errs[i] = a.cmdAccountSet() })
		}
		wg.Wait()
		got := readBack(t, file)
		if errs[0] != nil && errs[1] != nil {
			t.Fatalf("try %d: both refused: %v; %v", try, errs[0], errs[1])
		}
		for i, want := range []string{"email: x@example.com", "name: Ada"} {
			switch {
			case errs[i] == nil && !strings.Contains(got, want):
				t.Fatalf("try %d: a run wrote %q and the file lacks it:\n%s", try, want, got)
			case errs[i] != nil && !strings.HasPrefix(errs[i].Error(), "The accounts file changed while this ran."):
				t.Fatalf("try %d: err = %v, want the changed refusal", try, errs[i])
			}
		}
	}
}

// A file written after the load is refused and kept, not saved over with what the
// plan read. The lock goes with the run.
func TestAccountSetRefusesAFileThatChanged(t *testing.T) {
	a, file := setApp(t, keptBody, "work", "email", "x@example.com")
	const since = "account: work\n\tghaccount: keepme\n\tname: Ada\n"
	if err := os.WriteFile(file, []byte(since), 0o600); err != nil {
		t.Fatal(err)
	}
	err := a.cmdAccountSet()
	if err == nil {
		t.Fatal("set: no refusal")
	}
	for _, want := range []string{"The accounts file changed while this ran.", "File: " + displayPath(file), "Kept: Nothing was written."} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal is missing %q:\n%s", want, err)
		}
	}
	if got := readBack(t, file); got != since {
		t.Errorf("the changed file was saved over:\n%q", got)
	}
	if _, err := os.Lstat(file + ".lock"); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("the lock was left behind: %v", err)
	}
}

// A held lock is waited on and then refused by name. Unlocking removes this run's
// own lock, and leaves alone one another run made in its place.
func TestLockAccountsFile(t *testing.T) {
	file := filepath.Join(t.TempDir(), "config.shcl")
	lock := file + ".lock"
	unlock, err := lockAccountsFile(file, 0)
	if err != nil {
		t.Fatalf("lock: %v", err)
	}
	if _, err := lockAccountsFile(file, 60*time.Millisecond); err == nil || !strings.Contains(err.Error(), "Lock: "+displayPath(lock)) {
		t.Errorf("second lock: err = %v, want the refusal naming the lock", err)
	}
	unlock()
	if _, err := os.Lstat(lock); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("unlock left the lock: %v", err)
	}
	if unlock, err = lockAccountsFile(file, 0); err != nil {
		t.Fatalf("relock: %v", err)
	}
	if err := os.Remove(lock); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(lock, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	unlock()
	if _, err := os.Lstat(lock); err != nil {
		t.Errorf("unlock removed a lock it didn't make: %v", err)
	}
}

func TestLockFix(t *testing.T) {
	tests := []struct {
		goos, lock string
		want       []string
	}{
		{"linux", "/h/c.shcl.lock", []string{"If no other gitsby is running, a run that was stopped left it behind. Remove it, then run this again:", "  rm '/h/c.shcl.lock'"}},
		{"windows", "C:/h/c.shcl.lock", []string{"If no other gitsby is running, a run that was stopped left it behind. Remove it, then run this again."}},
		{"linux", "/h/it's/c.shcl.lock", []string{"If no other gitsby is running, a run that was stopped left it behind. Remove it, then run this again."}},
	}
	for _, tc := range tests {
		if got := lockFix(tc.goos, tc.lock); !slices.Equal(got, tc.want) {
			t.Errorf("lockFix(%s, %s) = %q, want %q", tc.goos, tc.lock, got, tc.want)
		}
	}
}
