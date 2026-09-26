// The account commands: 'list' shows what is configured and which rule this
// folder matches - the command you run when a push went out as the wrong person
// and you want to know why - and 'apply' teaches plain git the same folder
// rules, so a bare 'git push' in one of these folders behaves the same as it
// does through us.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"cmp"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"time"

	shcl "github.com/yottacore/shcl/source/go/v2"
)

// accountNames: every account the config file defines, in the order it defines
// them. An account can be declared by its keys alone, with no folder rule - it is
// then only reachable by name, through GITSBY_ACCOUNT, which is a legitimate way
// to use one.
// anyHostStated: whether any account in this config names a git host. What makes the
// host worth a line in the listing - with one git host configured there is nothing to
// compare, and a machine that only ever talks to github.com should not have the
// key advertised at it.
func (c *config) anyHostStated() bool {
	for key, value := range c.values {
		if strings.HasSuffix(key, ".host") && value != "" {
			return true
		}
	}
	return false
}

func (c *config) accountNames() []string {
	var seen []string
	add := func(name string) {
		if !slices.Contains(seen, name) {
			seen = append(seen, name)
		}
	}
	for _, r := range c.paths {
		add(r.acct)
	}
	for _, r := range c.segments {
		add(r.acct)
	}
	for _, name := range c.order {
		add(name)
	}
	return seen
}

// foldersOf: the folder rules belonging to one account, as canonical paths.
func (c *config) foldersOf(name string) []string {
	return matchesOf(c.paths, name)
}

// segmentsOf: the 'pathContains' rules belonging to one account. Kept apart from
// the folder rules because they are a different claim: those name a tree on this
// machine, these name a run of folder names on any machine, which is what lets one
// config file be synced between them.
func (c *config) segmentsOf(name string) []string {
	return matchesOf(c.segments, name)
}

// rulesOf is matchesOf with the whole rule, for a caller that prints one.
func rulesOf(rules []acctRule, name string) []acctRule {
	var out []acctRule
	for _, r := range rules {
		if r.acct == name && r.match != "" {
			out = append(out, r)
		}
	}
	return out
}

func matchesOf(rules []acctRule, name string) []string {
	var out []string
	for _, r := range rules {
		if r.acct == name && r.match != "" {
			out = append(out, r.match)
		}
	}
	return out
}

// includeDir: where the per-account git config fragments live - beside the config
// file that describes them, so the two travel together and 'account apply' has an
// unambiguous set of files it owns. A cut at the last '/' found none in a Windows
// path typed with backslashes, or in a bare file name, and put the folder under
// the file. Absolute, since git reads a relative include from its own config's
// folder.
func (c *config) includeDir() string {
	if c.file == "" {
		return ""
	}
	dir, err := filepath.Abs(filepath.Dir(c.file))
	if err != nil {
		dir = filepath.Dir(c.file)
	}
	// A root comes back with its slash on, 'C:/' or '/'.
	return strings.TrimSuffix(filepath.ToSlash(dir), "/") + "/accounts"
}

// git's exit status for "the key you asked me to unset isn't there".
const gitConfigNothingToUnset = 5

type includeRule struct{ cond, target string }

// includeCandidate is one folder rule on its way to becoming an includeIf: how
// specific it is, where it was declared, the pattern git will match on, and the
// account it selects.
type includeCandidate struct {
	weight  int // path length, or folder-name count
	order   int // position in the config file, which is how gitsby breaks a tie
	pattern string
	account string
}

// sortIncludes orders candidates the way the two matchers have to agree: git takes
// the LAST rule that matches and gitsby the most specific, so least specific comes
// first. Equal specificity is the case that used to disagree - gitsby keeps the
// FIRST rule declared, so that one has to be written LAST for git to keep it too,
// which is why the order runs backwards here.
func sortIncludes(list []includeCandidate) {
	slices.SortFunc(list, func(x, y includeCandidate) int {
		return cmp.Or(
			cmp.Compare(x.weight, y.weight),
			cmp.Compare(y.order, x.order),
		)
	})
}

// accountApplyPlan: the includeIf conditions 'account apply' would write.
// gitdir/i, not gitdir: a path compares case-insensitively on Windows and macOS,
// and a rule that silently misses because of a capital letter is worse than no
// rule. 'pathContains' maps onto git's own gitdir globbing, so plain git gets the
// same rule rather than an approximation of it. Fewest folder names
// first, and all of them ahead of the absolute rules; within the absolute rules,
// shortest path first, so a tree nested inside another account's tree lands last.
func (c *config) accountApplyPlan() []includeRule {
	dir := c.includeDir()
	if dir == "" {
		return nil
	}
	// Straight off the rule lists, so the index IS the declaration order that
	// accountForDir breaks its own ties by.
	var paths, segments []includeCandidate
	for i, r := range c.paths {
		if r.match == "" {
			continue
		}
		// The trailing slash is what makes git apply it to everything below the
		// folder too.
		paths = append(paths, includeCandidate{len(r.match), i, globLiteral(r.match) + "/", r.acct})
	}
	for i, r := range c.segments {
		if r.match == "" {
			continue
		}
		segments = append(segments, includeCandidate{strings.Count(r.match, "/") + 1, i, "**/" + globLiteral(r.match) + "/**", r.acct})
	}
	if len(paths)+len(segments) == 0 {
		return nil
	}
	sortIncludes(segments)
	sortIncludes(paths)
	plan := make([]includeRule, 0, len(segments)+len(paths))
	for _, cand := range slices.Concat(segments, paths) {
		plan = append(plan, includeRule{"includeIf.gitdir/i:" + cand.pattern + ".path", dir + "/" + cand.account + ".gitconfig"})
	}
	return plan
}

// globLiteral escapes what git's gitdir match reads as a pattern. gitsby matches a
// rule as plain text, so 'path: ~/d*' bound '~/dev' in plain git and nothing in
// gitsby, and 'pathcontains: **' bound every repo on the disk.
func globLiteral(s string) string {
	var b strings.Builder
	for _, r := range s {
		if strings.ContainsRune(`*?[\`, r) {
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	return b.String()
}

// accountManagedIncludes: every includeIf already in the global config that
// points into the directory we own. Those are ours to replace; anything else in
// there was written by hand and is left alone.
func (c *config) accountManagedIncludes() []string {
	dir := c.includeDir()
	if dir == "" {
		return nil
	}
	canonDir := canonPath(dir)
	var keys []string
	// --null, not the plain form: that one separates the key from the value with a
	// space, and the key holds a folder path which can contain one. Every such rule
	// came back truncated, so it was never recognized as ours - which made each
	// re-run append a duplicate, and left a rule dropped from the config file
	// applying forever. -z ends each record with a NUL and the key with a newline.
	for _, record := range strings.Split(runOut("git", "config", "--global", "--get-regexp", "--null", `^includeIf\..*\.path$`), "\x00") {
		key, value, found := strings.Cut(record, "\n")
		if !found {
			continue
		}
		// git prints the section and variable lower-cased and the subsection
		// verbatim, so match the key that way and hand it straight back to
		// --unset-all.
		lower := strings.ToLower(key)
		if !strings.HasPrefix(lower, "includeif.") || !strings.HasSuffix(lower, ".path") {
			continue
		}
		// Canonical, not textual: git stores a path in the platform's own spelling,
		// so ours comes back as 'C:/...' where we wrote '/c/...' - and a prefix test
		// on the raw text never fires, which quietly turns every re-run into a
		// duplicate rather than a refresh.
		if !strings.HasPrefix(canonPath(value), canonDir+"/") {
			continue
		}
		// --unset-all takes every entry under a key at once, so a key listed twice
		// (two accounts claiming one folder produce the same one) is removed by the
		// first pass and absent for the second.
		if !slices.Contains(keys, key) {
			keys = append(keys, key)
		}
	}
	return keys
}

func (a *app) cmdAccountList() {
	a.out.clean("")
	configDisp := nativePath(a.cfg.file)
	if configDisp == "" {
		configDisp = "(none found)"
	}
	a.out.clean("Config file ..: " + configDisp)
	a.out.clean(dirLabel + nativePath(a.contextDir()))
	hereAccount := a.cfg.accountForDir(a.contextDir())
	// An account that resolved and simply names no login is not the same as no
	// account at all - reported as "nothing configured" it contradicted the source
	// printed in the same sentence. Named as "(no login named)" it said nothing
	// anybody could act on either: the account is what the reader has to go and
	// edit, so name that instead.
	resolvedLine := a.accountWho(a.accountHost())
	switch {
	case resolvedLine != "":
		if a.acct.source != "" {
			resolvedLine += " (from " + a.accountSourceText(false) + ")"
		}
	case a.acct.name != "":
		resolvedLine = "'" + a.acct.name + "' - it names no login" + a.accountFallbackNote()
	default:
		// Nothing beyond that: this says what gitsby is configured to do here, and
		// whatever git and the git host CLI fall back to is their own business.
		resolvedLine = "(nothing configured)"
	}
	// Status's label for the same answer. "Resolves to" named no actor, so the first
	// question it raised was who was doing the resolving.
	a.out.clean(acctLabel + resolvedLine)
	if len(a.cfg.unknown) > 0 {
		a.out.clean("Ignored keys .: " + strings.Join(a.cfg.unknown, ", "))
	}
	// Here and nowhere else: this is the command the docs send you to when something
	// went out as the wrong person, and asking git costs every other command a process.
	stale := a.cfg.relativeManagedIncludes()
	warnStale := func() {
		for _, pattern := range stale {
			a.out.clean("")
			a.out.clean("WARNING: your global git config still has the rule 'gitdir/i:" + pattern + "' from an earlier 'account apply'. " +
				"Its folder isn't absolute, so plain git can apply that account far from where it was typed. Run '" + meName + " account apply' to remove it.")
		}
	}
	names := a.cfg.accountNames()
	if len(names) == 0 {
		a.out.clean("")
		a.out.clean("No accounts defined. '" + meName + " account set' adds one; run it with no arguments for the keys it takes.")
		warnStale()
		return
	}
	a.out.clean("")
	a.out.clean("Accounts:")
	for _, name := range names {
		a.showAccount(name, name == hereAccount)
	}
	for _, contested := range a.cfg.contestedRules() {
		a.out.clean("")
		a.out.clean("WARNING: more than one account claims " + contested + " - only the first is used.")
	}
	warnStale()
}

// contestedRules names the folder rules more than one account claims. There is no
// right answer to one: gitsby keeps the first declared, git keeps the last written,
// and 'account apply' can only make them agree about which mistake to make.
func (c *config) contestedRules() []string {
	var out []string
	for _, rules := range [][]acctRule{c.paths, c.segments} {
		byMatch := map[string][]string{}
		written := map[string]string{}
		var order []string
		for _, r := range rules {
			if r.match == "" || slices.Contains(byMatch[r.match], r.acct) {
				continue
			}
			if len(byMatch[r.match]) == 0 {
				order = append(order, r.match)
				// The first spelling, since two that match alike can be written apart.
				written[r.match] = r.written
			}
			byMatch[r.match] = append(byMatch[r.match], r.acct)
		}
		for _, match := range order {
			if len(byMatch[match]) > 1 {
				out = append(out, written[match]+": "+strings.Join(byMatch[match], ", "))
			}
		}
	}
	return out
}

func (a *app) showAccount(name string, isHere bool) {
	marker := "  "
	if isHere {
		marker = "->"
	}
	a.out.clean(marker + " " + name)
	// The host leads, because it decides whether anything under it applies at all.
	// Leaving the deciding field off the listing made 'account list' - the command
	// that always says - silent about the one key that had refused an account.
	// Shown only once some account names a git host, and then for every account,
	// including the ones that never said: it is the comparison that answers "why did
	// this one apply and that one not", and it is meaningless where every account is
	// on the same host. A config with one git host in it reads exactly as it always did.
	if host := a.cfg.value(name, "host"); host != "" {
		a.out.clean("     host ....: " + host)
	} else if a.cfg.anyHostStated() {
		a.out.clean("     host ....: github.com  (default)")
	}
	ghWho := a.cfg.value(name, "ghAccount")
	ghDisp := ghWho
	if ghDisp == "" {
		ghDisp = "(none)"
	}
	a.out.clean("     github ..: " + ghDisp)
	// The host-neutral login, and on a non-GitHub account the only one there is.
	if user := a.cfg.value(name, "user"); user != "" {
		a.out.clean("     login ...: " + user)
	}
	// Say where a token would come from, never what it is.
	tokenFrom := "(none)"
	if ghWho != "" && a.ghTokenFor(ghWho) != "" {
		tokenFrom = "gh's own store"
	} else if readTokenFile(a.cfg.value(name, "tokenFile")) != "" {
		tokenFrom = a.cfg.value(name, "tokenFile")
	}
	a.out.clean("     token ...: " + tokenFrom)
	if sshKey := a.cfg.value(name, "sshKey"); sshKey != "" {
		a.out.clean("     ssh key .: " + sshKey)
	}
	acctUser := a.cfg.value(name, "name")
	acctEmail := a.cfg.value(name, "email")
	if acctUser+acctEmail != "" {
		if acctUser == "" {
			acctUser = "?"
		}
		if acctEmail == "" {
			acctEmail = "?"
		}
		a.out.clean("     commits .: " + acctUser + " <" + acctEmail + ">")
	}
	if proto := a.cfg.value(name, "protocol"); proto != "" {
		a.out.clean("     protocol : " + proto)
	}
	// Each rule as the file writes it. The canonical form is lower case on Windows
	// with every link resolved, so printing that named a folder nobody had typed.
	for _, r := range rulesOf(a.cfg.paths, name) {
		// A rule pointing at nothing matches nothing, and reads exactly like no rule
		// at all - which is how you end up acting as the wrong account while believing
		// you configured it. Usually a typo; on Windows it is also how a shell-only
		// path spelling such as '/tmp/...' looks, since only the shell build can
		// resolve one.
		if isDir(r.match) {
			a.out.clean("     folder ..: " + r.written)
		} else {
			a.out.clean("     folder ..: " + r.written + "  (no such directory - this rule can never match)")
		}
	}
	// No existence check on these: naming no machine in particular is the point.
	for _, r := range rulesOf(a.cfg.segments, name) {
		a.out.clean("     anywhere : .../" + strings.Trim(r.written, `/\`) + "/...")
	}
}

// cmdAccountApply writes one fragment per account, and an includeIf per folder
// rule pointing at it - with 'git config', never by editing the file ourselves,
// so git's own parser decides what a valid entry looks like. The directory is
// checked BEFORE writing anything: left to mkdir and the redirect, a blocked
// path surfaced as a raw tooling error part way through the run, which reads as
// a crash rather than as something you can act on.
func (a *app) cmdAccountApply() error {
	dir := a.cfg.includeDir()
	if dir == "" {
		return usagef("No config file, so there is nowhere to write the account fragments.")
	}
	if pathExists(dir) && !isDir(dir) {
		return usagef("'%s' is where the account fragments go, and it isn't a directory. Move or remove it, then re-run.", nativePath(dir))
	}
	// 0700, not 0777-and-hope-for-umask: these fragments name your accounts and
	// point at your token file, and they sit under your own config directory.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return usagef("Couldn't create '%s' for the account fragments. Check permissions on '%s'.", nativePath(dir), nativePath(filepath.Dir(dir)))
	}
	for _, name := range a.cfg.accountNames() {
		if err := a.writeAccountFragment(dir, name); err != nil {
			return err
		}
	}
	// Drop ours before adding, so a folder rule that was removed from the config
	// file stops applying. Each key was just listed out of the config, so a failure
	// to remove one is real - and leaving it means the old rule keeps applying
	// beside the new one.
	for _, key := range a.cfg.accountManagedIncludes() {
		// git exits 5 for "there was nothing to remove", which is the end state this
		// loop is asking for. Only a real failure is one - reading 5 as one left the
		// config with no rules at all and the command reporting an error.
		if rc := a.inheritRC("git", "config", "--global", "--unset-all", key); rc != 0 && rc != gitConfigNothingToUnset {
			return usagef("Couldn't remove the old rule '%s' from your global git config; nothing further was applied.", key)
		}
	}
	for _, rule := range a.cfg.accountApplyPlan() {
		if !a.inheritOK("git", "config", "--global", "--add", rule.cond, rule.target) {
			return usagef("Couldn't add '%s' to your global git config.", rule.cond)
		}
		a.out.status("git config --global --add " + rule.cond)
	}
	return nil
}

// writeAccountFragment writes one account's git config fragment. Every write is
// checked and every failure stops the run: this is the one command that writes
// outside the repo you are standing in, so it is the one place where a discarded
// exit code turns into a silent no-op - it said "Wrote" and exited 0 whatever
// happened.
func (a *app) writeAccountFragment(dir, name string) error {
	fragment := dir + "/" + name + ".gitconfig"
	if err := os.WriteFile(fragment, nil, 0o600); err != nil {
		return usagef("Couldn't write '%s'. Check permissions on '%s'.", fragment, dir)
	}
	// WriteFile only applies its mode when it creates the file, so a fragment left
	// world-readable by an earlier run - or by a umask - stays that way through
	// every re-apply. It names the account and points at the token file.
	if err := os.Chmod(fragment, 0o600); err != nil && !isWindows() {
		return usagef("Couldn't set permissions on '%s'; it names your account and points at your token file.", fragment)
	}
	write := func(key, value string) error {
		if !a.inheritOK("git", "config", "--file", fragment, key, value) {
			return usagef("Couldn't write %s into '%s'; it is incomplete, and nothing further was applied.", key, fragment)
		}
		return nil
	}
	entries := []struct{ key, value string }{
		{"user.name", a.cfg.value(name, "name")},
		{"user.email", a.cfg.value(name, "email")},
		{"gitsby.ghAccount", a.cfg.value(name, "ghAccount")},
		// Which account plain git should ASK for over https. Without it the fragment
		// covered the ssh half and left the https half to whichever credential the
		// helper happened to hold first - so a bare 'git push' in a configured folder
		// could still go out as someone else, which is the gap 'apply' exists to close.
		// Naming the user is what makes a credential manager look up that account's
		// entry rather than any entry for the host.
		{"credential.https://github.com.username", a.cfg.value(name, "ghAccount")},
		// Expanded, since git knows none of the home spellings the accounts file takes.
		{"gitsby.ghTokenFile", expandHome(a.cfg.value(name, "tokenFile"))},
	}
	for _, e := range entries {
		if e.value == "" {
			continue
		}
		if err := write(e.key, e.value); err != nil {
			return err
		}
	}
	if sshKey := a.cfg.value(name, "sshKey"); sshKey != "" {
		if err := write("core.sshCommand", "ssh -i "+sshKeyArg(sshKey)+" -o IdentitiesOnly=yes"); err != nil {
			return err
		}
	}
	a.out.status("Wrote " + fragment)
	return nil
}

// accountSetFields: the per-account keys 'account set' will write, spelled the way
// the file spells them. The format folds key names to lower case on every
// rewrite, so lower case is the one spelling a file ever settles on, and the help
// and the docs say it that way too rather than teach one the file won't keep.
var accountSetFields = []string{"path", "pathcontains", "ghaccount", "tokenfile", "sshkey", "name", "email", "protocol", "host", "user"}

// The block nests by indent rather than lining up under the 'gitsby: ' prefix: the
// prefix is on one line only, so hanging everything off its width buries the
// structure. Placeholders sit two levels in, with a description column past the
// widest of them, and the examples one level deeper again.
const (
	accountSetIndent = "  "
	accountSetPad    = accountSetIndent + accountSetIndent
	accountSetCont   = "               "
)

// accountSetUsage spells out the three words 'account set' takes, and what each one
// is. A reader being told the syntax is a reader who did not know it, so the closed
// list of keys belongs here rather than one command further on, and the examples
// use one account name twice - that repetition IS what '<account>' means. The value
// forms are the ones the matcher reads: 'pathContains' is a run of folder names, not
// a glob, so an example with '*' in it would teach a rule that never fires.
func accountSetUsage() error {
	lines := []string{
		"Syntax: " + meName + " account set <account> <key> <value>",
		accountSetIndent + "Writes '<key>: <value>' into the <account> block of the accounts file.",
		accountSetPad + "<account>  A string you define for one login; e.g. 'work', 'personal'.",
	}
	key := wrapWords("The setting to change. One of: "+strings.Join(accountSetFields, ", ")+".", 57)
	lines = append(lines, accountSetPad+"<key>      "+key[0])
	for _, rest := range key[1:] {
		lines = append(lines, accountSetCont+rest)
	}
	lines = append(lines,
		accountSetPad+"<value>    What to set it to. Quote it if it has spaces.",
		accountSetIndent+"Examples:",
		accountSetPad+"Bind an account to one folder, and the login to use there:",
		accountSetPad+accountSetIndent+meName+" account set work path ~/dev/work",
		accountSetPad+accountSetIndent+meName+" account set work ghaccount my-work-login",
		accountSetPad+"Or by a run of folder names the project's path contains:",
		accountSetPad+accountSetIndent+meName+" account set work pathcontains my-employer/github")
	return usagef("%s", strings.Join(lines, "\n"))
}

// canonAccountField maps whatever casing was typed onto the documented spelling,
// or empty for a key nothing reads. Refusing an unknown key is the point: the
// loader only lists one as ignored, which is a warning nobody reads until the
// account silently fails to apply.
func canonAccountField(field string) string {
	for _, known := range accountSetFields {
		if strings.EqualFold(known, field) {
			return known
		}
	}
	return ""
}

// absPathValue is the 'path', 'tokenfile' or 'sshkey' value 'account set' writes;
// what is "folder" or "file", for the refusal. A relative one means the folder the
// command runs in, as it would for any command, and the file can never say that
// later - so it goes in absolute. Spelled the way the platform spells it rather
// than in canonical form, since the file is edited by hand, and with forward
// slashes, since a backslash in a bare value is an escape. A value starting at
// home is written as typed, so one file still works where home differs.
func absPathValue(value, what string) (string, error) {
	// filepath.Abs("") is the current directory, which nobody typed.
	if value == "" {
		return value, nil
	}
	switch folderRuleProblem(value) {
	case "":
		return value, nil
	case ruleNoHome:
		return "", usagef("'%s' starts at the home folder, and this machine names none. Give the full path.", value)
	case ruleOtherHome:
		return "", usagef("'%s' names another user's home folder, and only a bare '~' is expanded. Give the full path.", value)
	case ruleOtherVar:
		return "", usagef("'%s' starts with a variable %s doesn't expand. Only '~', '${HOME}' and '%%USERPROFILE%%' are, or give the full path.", value, meName)
	}
	abs, err := filepath.Abs(value)
	if err == nil {
		abs = filepath.ToSlash(abs)
	}
	if err != nil || folderRuleProblem(abs) != "" {
		return "", usagef("Couldn't work out which %s '%s' is from here. Give the full path.", what, value)
	}
	return abs, nil
}

// managedIncludePattern takes the folder pattern back out of an includeIf key as
// accountManagedIncludes lists it: 'includeIf.gitdir/i:./.path' gives './'. git
// hands the section and variable back lower-cased and the pattern as written.
func managedIncludePattern(key string) (string, bool) {
	const suffix = ".path"
	for _, prefix := range []string{"includeif.gitdir/i:", "includeif.gitdir:"} {
		if len(key) < len(prefix)+len(suffix) {
			continue
		}
		if strings.EqualFold(key[:len(prefix)], prefix) && strings.EqualFold(key[len(key)-len(suffix):], suffix) {
			return key[len(prefix) : len(key)-len(suffix)], true
		}
	}
	return "", false
}

// relativeManagedIncludes names our includeIf patterns in the global git config
// whose folder is not absolute. An 'account apply' from before such a rule was
// ignored wrote them, and plain git goes on reading one far from where it was
// typed until the next apply removes it. A '**/' pattern is a 'pathcontains' rule,
// which names no folder by design.
func (c *config) relativeManagedIncludes() []string {
	var out []string
	for _, key := range c.accountManagedIncludes() {
		pattern, ok := managedIncludePattern(key)
		if !ok || strings.HasPrefix(pattern, "**/") || slices.Contains(out, pattern) {
			continue
		}
		if folderRuleProblem(strings.TrimSuffix(pattern, "/")) != "" {
			out = append(out, pattern)
		}
	}
	return out
}

// accountSetTarget is what 'account set' would write, and where. Everything the
// write needs is settled here, off ONE read of the file, so the plan on screen and
// the edit that follows cannot describe two different files.
type accountSetTarget struct {
	file     string
	doc      *shcl.Document
	base     string // the account block's lookup path
	disp     string // the block as the plan names it: account[work]
	field    string
	value    string
	exists   bool   // the key is in the block already
	lineNum  int    // the line it is on now, where the file keeps its shape
	old      string // its value now, as typed
	creates  bool   // the file itself does not exist yet
	converts bool   // the file is in the old flat layout, and comes out in the current one
	reshapes bool   // the save changes more of the file than the key: spacing, key case, line ends
	read     string // the file as the plan read it; the save refuses once it holds anything else
}

func (t accountSetTarget) path() string { return t.base + "." + t.field }

// configInTheWay refuses a create while anything is at a place an accounts file
// can live. Reads pass over such a file as if it were not there, and a create
// taking that at its word would replace it, or go in ahead of it and hide it from
// every later command. Every candidate counts, not only the one written.
func (a *app) configInTheWay() error {
	for _, c := range configCandidates() {
		if state, fi, err := probeConfigCandidate(c); state != candidateAbsent {
			return configRefusal(c, state, fi, err)
		}
	}
	return nil
}

// configRefusal says why a create was refused, by what is at the path. The fix
// differs for each, so they don't share one message. Absent and usable both mean
// a file arrived after the load: absent is reached only when the exclusive open
// said something was there, and it has gone again since.
func configRefusal(file string, state candidateState, fi os.FileInfo, cause error) error {
	kept := noteLines("Kept", "Nothing was written.")
	var head string
	var notes [][]string
	switch state {
	case candidateUnreadable:
		head = "An accounts file is already there, and it can't be read."
		notes = [][]string{
			noteLines("File", nativePath(file)),
			noteLines("Why", "A new file here would replace it. Opening it failed with: "+causeText(cause)+"."),
			kept,
			noteLines("Fix", unreadableFix(runtime.GOOS, file, cause)...),
		}
	case candidateBrokenLink:
		head = "The accounts file is a link to something that isn't there."
		notes = [][]string{noteLines("File", nativePath(file))}
		if target, err := os.Readlink(file); err == nil {
			notes = append(notes, noteLines("Link", target))
		}
		notes = append(notes,
			noteLines("Why", "Writing through it would create a new file where it points, and whatever belongs there is missing right now."),
			kept,
			noteLines("Fix", "Put back what the link points to, or remove the link, then run this again."),
		)
	case candidateNotFile:
		kind := "special file"
		if fi != nil && fi.IsDir() {
			kind = "folder"
		}
		head = "Something that isn't a file is where the accounts file goes."
		notes = [][]string{
			noteLines("File", nativePath(file)),
			noteLines("Why", "It is a "+kind+", and the accounts file has to go in its place."),
			kept,
			noteLines("Fix", "Move it out of the way, then run this again."),
		}
	case candidateUnknown:
		head = "Couldn't look for an accounts file where one can be."
		why := "Looking there failed with: " + causeText(cause) + ", so there is no telling whether one is there."
		if file != defaultConfigFile() {
			why += " A new file would go in ahead of it and hide it."
		}
		notes = [][]string{
			noteLines("File", nativePath(file)),
			noteLines("Why", why),
			kept,
			noteLines("Fix", lookupFix(runtime.GOOS, file, cause)...),
		}
	default:
		head = "An accounts file turned up while this ran."
		notes = [][]string{
			noteLines("File", nativePath(file)),
			noteLines("Why", "This command read the accounts before the file was there, so its edit would replace what the file holds now."),
			kept,
			noteLines("Fix", "Run this again. It will edit the file that is there now."),
		}
	}
	return refusalBlock(head, notes, cause)
}

// refusalBlock lays a refusal out as its first line with the labeled notes under it.
func refusalBlock(head string, notes [][]string, cause error) error {
	lines := []string{head}
	for _, note := range notes {
		for _, l := range note {
			lines = append(lines, "  "+l)
		}
	}
	return &usageError{msg: strings.Join(lines, "\n"), cause: cause}
}

// causeText is the OS's reason alone. The path is already on its own line, and a
// PathError repeats it.
func causeText(err error) string {
	if err == nil {
		return "no reason given"
	}
	var pe *fs.PathError
	text := err.Error()
	if errors.As(err, &pe) {
		text = pe.Err.Error()
	}
	return strings.TrimSuffix(text, ".")
}

// unreadableFix is the Fix for a file that can't be read. A command only where the
// answer is known: gitsby makes this file 0600 as you, so off Windows a missing
// read bit is the usual cause, and chmod says so itself when the file is somebody
// else's. On Windows it is an ACL entry or a program holding the file, and no one
// command is right. Takes the platform, so both are testable from either.
func unreadableFix(goos, file string, cause error) []string {
	switch {
	case !errors.Is(cause, fs.ErrPermission):
		return []string{"Run this again once it can be read."}
	case goos == "windows":
		return []string{"Give your account read access to it, then run this again."}
	case strings.Contains(file, "'"):
		return []string{"Make it readable, then run this again."}
	}
	// A leading space makes it a literal line: indented, never wrapped.
	return []string{"Make it readable, then run this again:", "  chmod u+r '" + file + "'"}
}

// lookupFix is the Fix for a place that couldn't be looked in. The command is given
// only when the folder the file sits in is the one that can't be searched, which
// looking up that folder itself proves. A folder further up is left to the reader.
func lookupFix(goos, file string, cause error) []string {
	dir := filepath.Dir(file)
	switch {
	case !errors.Is(cause, fs.ErrPermission):
		return []string{"Run this again once it can be looked up."}
	case goos == "windows":
		return []string{"Give your account access to the folder it is in, then run this again."}
	case strings.Contains(dir, "'"):
		return []string{"Make the folder it is in searchable, then run this again."}
	}
	if _, err := os.Lstat(dir); err != nil {
		return []string{"Make the folders above it searchable, then run this again."}
	}
	// A leading space makes it a literal line: indented, never wrapped.
	return []string{"Make the folder it is in searchable, then run this again:", "  chmod u+x '" + dir + "'"}
}

// createAccountsFile makes the file and writes it through one handle. The open
// fails on anything already at the path, a link included, so it can never
// truncate - and writing through that same handle means no empty file sits there
// for another run to load in between. opened says whether the file now exists
// because of this call, which a failed write leaves in place: removing it by name
// could delete a file another run has since renamed over it.
func createAccountsFile(file, text string) (opened bool, err error) {
	f, err := os.OpenFile(file, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return false, err
	}
	_, err = f.WriteString(text)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	return true, err
}

// A run holds the lock only from its re-read to its save, which is milliseconds.
const accountLockWait = 3 * time.Second

// lockAccountsFile keeps two runs from saving over each other. Each reads the
// whole file and saves it whole, so the later save dropped what the earlier one
// wrote. The lock goes beside the file, not on it: the save renames a new file
// over the name, and a lock on the old one guards nothing. An exclusive create is
// the one lock every platform has. The func it returns removes the lock, but only
// while it is still the one this run made.
func lockAccountsFile(file string, wait time.Duration) (func(), error) {
	// The save writes through a link, so two names for one file take one lock.
	target := file
	if resolved, err := filepath.EvalSymlinks(file); err == nil {
		target = resolved
	}
	lock := target + ".lock"
	deadline := time.Now().Add(wait)
	for {
		f, err := os.OpenFile(lock, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if err == nil {
			mine, serr := f.Stat()
			_ = f.Close()
			return func() {
				if now, err := os.Lstat(lock); serr != nil || (err == nil && os.SameFile(mine, now)) {
					_ = os.Remove(lock)
				}
			}, nil
		}
		// Windows refuses a create over a file whose delete is still pending, which is
		// what another run's lock is for a moment after it lets go.
		held := errors.Is(err, fs.ErrExist)
		pending := runtime.GOOS == "windows" && errors.Is(err, fs.ErrPermission)
		switch {
		case !held && (!pending || time.Now().After(deadline)):
			return nil, usagef("Couldn't make the lock '%s' beside the accounts file, so nothing was written. Check permissions on the folder it is in.", nativePath(lock))
		case time.Now().After(deadline):
			return nil, refusalBlock("Another run is editing the accounts file.", [][]string{
				noteLines("File", nativePath(file)),
				noteLines("Lock", nativePath(lock)),
				noteLines("Why", "Edits go in one at a time, and the lock beside the file was still there after waiting for it."),
				noteLines("Kept", "Nothing was written."),
				noteLines("Fix", lockFix(runtime.GOOS, lock)...),
			}, nil)
		}
		time.Sleep(25 * time.Millisecond)
	}
}

// lockFix is the Fix for a lock that stayed put. Takes the platform, so both are
// testable from either.
func lockFix(goos, lock string) []string {
	const stale = "If no other " + meName + " is running, a run that was stopped left it behind. Remove it, then run this again"
	if goos == "windows" || strings.Contains(lock, "'") {
		return []string{stale + "."}
	}
	// A leading space makes it a literal line: indented, never wrapped.
	return []string{stale + ":", "  rm '" + lock + "'"}
}

// changedRefusal: the file no longer holds what the plan read. Saving would put
// back what it held then, and drop whatever went in since.
func changedRefusal(file string, cause error) error {
	why := "Something wrote it after this command read it, and saving now would undo that."
	if cause != nil {
		why = "Reading it again before the save failed with: " + causeText(cause) + "."
	}
	return refusalBlock("The accounts file changed while this ran.", [][]string{
		noteLines("File", nativePath(file)),
		noteLines("Why", why),
		noteLines("Kept", "Nothing was written."),
		noteLines("Fix", "Run this again. It will edit the file as it is now."),
	}, cause)
}

// accountSetPlan resolves what 'account set' would do without doing any of it.
// The value is validated here rather than at write time, so a refusal happens
// before the plan is shown rather than after it has been agreed to.
func (a *app) accountSetPlan() (accountSetTarget, error) {
	var t accountSetTarget
	name := strings.ToLower(a.cmd.arg)
	if !acctNameOK.MatchString(name) {
		return t, usagef("'%s' isn't a usable account name; letters, digits, '.', '_' and '-' only.", a.cmd.arg)
	}
	t.field = canonAccountField(a.cmd.arg2)
	if t.field == "" {
		return t, usagef("'%s' isn't an account key %s reads. One of: %s.", a.cmd.arg2, meName, strings.Join(accountSetFields, ", "))
	}
	t.value, t.disp = a.cmd.arg3, "account["+name+"]"
	var err error
	switch t.field {
	case "path":
		t.value, err = absPathValue(t.value, "folder")
	case "tokenfile", "sshkey":
		t.value, err = absPathValue(t.value, "file")
	}
	if err != nil {
		return t, err
	}
	// The same checks the loader makes, made here where they can still be answered.
	// Written past them the line lands in the file and is then dropped on every
	// read, so the file says one thing and every command does another. The key is
	// checked as it will be written, since the folder a relative one was typed in
	// can carry a space.
	if t.field == "sshkey" && strings.ContainsAny(sshKeyArg(t.value), sshKeyShellChars) {
		return t, usagef("git hands a key path to a shell, so one carrying whitespace or a shell character is re-parsed rather than used. Move the key somewhere plainer.")
	}
	if (t.field == "host" || t.field == "user") && !hostWordOK.MatchString(t.value) {
		return t, usagef("'%s' isn't a plain %s name; letters, digits, '.', '_' and '-' only.", t.value, t.field)
	}
	if t.field == "protocol" {
		if !protocolOK(t.value) {
			return t, usagef("'%s' isn't a protocol %s uses. One of: https, ssh.", t.value, meName)
		}
		t.value = strings.ToLower(t.value)
	}
	switch {
	case a.cfg.file == "":
		if t.file = defaultConfigFile(); t.file == "" {
			return t, usagef("There is nowhere to put an accounts file: this machine names no home directory. Set HOME, or name a file with --config.")
		}
		if err := a.configInTheWay(); err != nil {
			return t, err
		}
		t.creates = true
		// The block goes in as text, ahead of the key: a header comment attaches to
		// the first setting after it, and with nothing there yet it would trail the
		// file as a footer instead.
		t.doc = shcl.Parse(configHeader + "\naccount: " + name + "\n\n" + shcl.GenBanner)
	case a.cfg.flat:
		// Converted whole, comments and all, rather than refused: the file was
		// written for the scripted builds, and this is the command that moves it on.
		data, err := os.ReadFile(a.cfg.file)
		if err != nil {
			return t, usagef("Couldn't read '%s'.", nativePath(a.cfg.file))
		}
		t.file, t.converts, t.read = a.cfg.file, true, string(data)
		t.doc = shcl.Parse(flatToSHCL(strings.TrimPrefix(string(data), utf8BOM)))
	default:
		t.file, t.doc, t.read = a.cfg.file, a.cfg.doc, a.cfg.raw
	}
	// A line the read dropped can't be kept, so the save would be a whole-file
	// rewrite that loses it, and the module refuses one. Said here, before the plan,
	// rather than after the confirmation.
	if lost := t.doc.LostCount(); lost > 0 {
		return t, usagef("%d line(s) of %s couldn't be read, and a rewrite would drop them. Edit it by hand.", lost, nativePath(t.file))
	}
	// Taken before the edit, so only what the save changes besides the key counts.
	tidy := t.doc.ToCanonical() == t.read
	blocks, _ := acctBlocks(t.doc)
	for _, b := range blocks {
		if b.name == name {
			t.base = b.path
			break
		}
	}
	if t.base == "" {
		// Quoted, so a name that happens to be a number is not read as an index.
		t.base = `account["` + name + `"]`
	}
	// 'path' and 'pathcontains' are repeatable by design, and any key at all can be
	// in there twice by accident. Replacing the first and leaving the rest would
	// look like it worked and change nothing, so say so rather than guess.
	if n := t.doc.Count(t.path()); n > 1 {
		return t, usagef("'%s' is in %s %d times. Edit it by hand - there is no telling which one you meant.", t.disp+"."+t.field, nativePath(t.file), n)
	}
	if read := t.doc.ReadString(t.path()); read.Status != shcl.NotFound {
		t.exists, t.lineNum = true, read.Line
		if read.Raw != nil {
			t.old = *read.Raw
		}
	}
	// Made here rather than at the save, so a key the file can't hold is refused
	// before the plan, and the plan knows whether the rest of the file comes back
	// as written. A few edits can't keep it, such as a key added under a dotted
	// line; those save the whole file in the module's own layout.
	if !t.doc.SetString(t.path(), t.value) {
		return t, usagef("'%s' isn't a setting the file can hold (%s).", t.disp+"."+t.field, t.doc.WriteReason(t.path()))
	}
	if _, kept := t.doc.ToTextKeepLines(); !kept && !tidy && !t.creates && !t.converts {
		t.reshapes = true
	}
	return t, nil
}

// cmdAccountSet writes one key into one account block of the accounts file and
// saves it through the module. Every line the edit didn't touch comes back as it
// was. Where the module can't manage that, it writes the whole file in its own
// layout - tabs, lower-case keys, one blank line at most between blocks - and the
// plan has said so.
func (a *app) cmdAccountSet() error {
	if a.set == nil {
		t, err := a.accountSetPlan()
		if err != nil {
			return err
		}
		a.set = &t
	}
	t := *a.set
	if t.creates {
		dir := filepath.Dir(t.file)
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return usagef("Couldn't create '%s' to put the accounts file in.", nativePath(dir))
		}
	}
	// Over a create too: one between its open and its write holds an empty file,
	// which an edit would read and save over.
	unlock, err := lockAccountsFile(t.file, accountLockWait)
	if err != nil {
		return err
	}
	defer unlock()
	if t.creates {
		// 0600 from the first byte: this file names your accounts and points at your
		// token files. Opened so it cannot replace anything, since a file already
		// there - even one this run could not read - holds someone's accounts.
		opened, err := createAccountsFile(t.file, t.doc.ToCanonical())
		switch {
		case err == nil:
			a.out.status("Wrote " + nativePath(t.file))
			return nil
		case opened:
			return usagef("Couldn't finish writing '%s', so it may be incomplete. Check the disk it is on before running this again.", nativePath(t.file))
		case errors.Is(err, fs.ErrExist):
			state, fi, perr := probeConfigCandidate(t.file)
			return configRefusal(t.file, state, fi, perr)
		}
		return usagef("Couldn't write '%s'. Check permissions on it.", nativePath(t.file))
	}
	if now, err := os.ReadFile(t.file); err != nil || string(now) != t.read {
		return changedRefusal(t.file, err)
	}
	if _, err := t.doc.SaveFileKeepLines(t.file); err != nil {
		var refused *shcl.SaveRefused
		if errors.As(err, &refused) {
			return usagef("%d line(s) of %s couldn't be read, and a rewrite would drop them. Edit it by hand.", refused.Lost, nativePath(t.file))
		}
		return usagef("Couldn't write '%s'. Check permissions on it.", nativePath(t.file))
	}
	a.out.status("Wrote " + nativePath(t.file))
	return nil
}
