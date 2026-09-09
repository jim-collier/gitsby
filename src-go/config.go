// The accounts config: discovery, folder matching, and the reader for the old
// flat 'key = value' layout. The current layout is SHCL, read and written through
// the shcl module in shcl.go; the flat reader stays so a file written for the
// scripted builds keeps working until something rewrites it.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"

	shcl "github.com/jim-collier/shcl/source/go/v2"
)

type acctRule struct {
	match string // canonical folder, or a canonical run of folder names
	acct  string
}

// config is one parsed accounts file. Zero accounts and no file are the ordinary
// single-account case, not an error.
type config struct {
	loaded   bool
	values   map[string]string
	paths    []acctRule     // 'path' rules: absolute folder claims
	segments []acctRule     // 'pathContains' rules: machine-free folder-name runs
	unknown  []string       // named but not understood - reported, never silent
	order    []string       // accounts in declaration order, for ones with keys but no folder rule
	file     string         // named by the identity block when the file held keys nothing reads
	doc      *shcl.Document // the file as parsed, for 'account set' to edit; nil for a flat file or none
	flat     bool           // the old 'key = value' layout: read as it always was, rewritten by the first edit
}

func isWindows() bool { return runtime.GOOS == "windows" }

// homeDir is where '~' points. HOME first, so a shell that sets one wins - on
// Windows that is the MSYS spelling, and the drive-letter fold below only knows
// what to do with the path it is handed. Nothing sets HOME on native Windows,
// where every '~' in a config file was expanding to nothing at all.
func homeDir() string {
	if home := os.Getenv("HOME"); home != "" {
		return home
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return home
}

// expandTilde resolves a leading '~' in a path from the config file. Unresolvable
// is left as typed: a path starting with a literal '~' matches nothing and reads
// as the typo it is, where one starting with '/' would name somewhere real.
func expandTilde(p string) string {
	if p != "~" && !strings.HasPrefix(p, "~/") && !strings.HasPrefix(p, `~\`) {
		return p
	}
	home := homeDir()
	if home == "" {
		return p
	}
	return home + p[1:]
}

var (
	msysDriveRE = regexp.MustCompile(`^/([A-Za-z])(/.*)?$`)
	driveRootRE = regexp.MustCompile(`^[A-Za-z]:/$`)
)

// canonPath gives a directory one spelling, so a config written on one machine
// matches the same tree on another, and so a rule and the folder it claims are
// compared on the same terms.
func canonPath(p string) string {
	if p == "" {
		return ""
	}
	p = strings.ReplaceAll(p, "\\", "/")
	p = expandTilde(p)
	if isWindows() {
		// Fold the drive letter BEFORE asking the filesystem: '/c/x' means nothing
		// to a native build, and asking first is the bug the PowerShell port had.
		if m := msysDriveRE.FindStringSubmatch(p); m != nil {
			tail := m[2]
			if tail == "" {
				tail = "/"
			}
			p = m[1] + ":" + tail
		}
	}
	p = resolveLinks(p)
	if isWindows() {
		p = strings.ToLower(p)
	}
	for strings.HasSuffix(p, "/") && p != "/" && !driveRootRE.MatchString(p) {
		p = strings.TrimSuffix(p, "/")
	}
	return p
}

// resolveLinks settles symlink and junction spellings through the nearest
// ancestor that exists, then puts the rest of the path back on - a clone target
// need not exist yet, which is why it can't just resolve the whole thing.
//
// Every platform, not just Windows. 'git rev-parse --show-toplevel' answers with
// the tree's real path, so a rule written the way you type it - through a
// symlinked home, a synced folder, a stable name pointing at a dated one - was
// compared against the resolved spelling and never matched. Nothing said so
// either: the folder is real, so the "this rule can never match" note stayed
// quiet, and a run acted as the wrong account while the listing looked right.
func resolveLinks(p string) string {
	head, tail := p, ""
	for head != "" && strings.Contains(head, "/") {
		if fi, err := os.Stat(head); err == nil && fi.IsDir() {
			break
		}
		if tail == "" {
			tail = head[strings.LastIndex(head, "/")+1:]
		} else {
			tail = head[strings.LastIndex(head, "/")+1:] + "/" + tail
		}
		head = head[:strings.LastIndex(head, "/")]
	}
	if fi, err := os.Stat(head); err != nil || !fi.IsDir() {
		return p
	}
	resolved, err := filepath.EvalSymlinks(head)
	if err != nil || resolved == "" {
		return p
	}
	resolved = strings.ReplaceAll(resolved, "\\", "/")
	if tail == "" {
		return resolved
	}
	return strings.TrimRight(resolved, "/") + "/" + tail
}

// absDir puts a relative path on the current directory, so a folder rule sees the
// same spelling it would for a folder we were standing in. Folded first, because
// '/c/x' is already absolute on Windows and joining it to the cwd would bury it.
func absDir(p string) string {
	if p = canonPath(p); p == "" {
		return ""
	}
	if !filepath.IsAbs(p) {
		wd, err := os.Getwd()
		if err != nil {
			return p
		}
		p = wd + "/" + p
	}
	// '..' has to go before a rule sees it, or a destination reached by climbing out
	// of one tree still reads as a folder inside it.
	return canonPath(filepath.ToSlash(filepath.Clean(p)))
}

// canonSegment folds a 'pathContains' run of folder names the same way canonPath
// folds a path, so the two are compared on the same terms. No filesystem involved:
// the whole point is that this rule names no machine.
func canonSegment(s string) string {
	if s == "" {
		return ""
	}
	s = strings.ReplaceAll(s, "\\", "/")
	s = strings.Trim(s, "/")
	if isWindows() {
		s = strings.ToLower(s)
	}
	return s
}

// configFile picks the file to read: the first candidate that exists, or nothing.
// A file named explicitly must exist - naming one that isn't there is a typo, not
// a fallback - and it is asked whether the option was TYPED, not whether it has a
// value: '--config ""' falling back to the default file would act as the wrong
// identity, quietly. An empty GITSBY_CONFIG is left alone deliberately - an unset
// environment variable and an empty one are the same thing, unlike a typed option.
func (o options) resolveConfigFile() (string, error) {
	if o.configGiven {
		switch {
		case o.configFile == "":
			return "", usageSubf("--config was given an empty file name.")
		case !pathExists(o.configFile):
			return "", usageSubf("No readable config file at '%s'.", o.configFile)
		case !isRegularFile(o.configFile):
			return "", usageSubf("--config names '%s', which isn't a file.", o.configFile)
		case !isReadableFile(o.configFile):
			return "", usageSubf("No readable config file at '%s'.", o.configFile)
		}
		return o.configFile, nil
	}
	if env := os.Getenv("GITSBY_CONFIG"); env != "" {
		switch {
		case !pathExists(env):
			return "", usageSubf("GITSBY_CONFIG names '%s', which can't be read.", env)
		case !isRegularFile(env):
			return "", usageSubf("GITSBY_CONFIG names '%s', which isn't a file.", env)
		case !isReadableFile(env):
			return "", usageSubf("GITSBY_CONFIG names '%s', which can't be read.", env)
		}
		return env, nil
	}
	for _, c := range configCandidates() {
		// A discovered candidate is skipped rather than refused - unlike one named
		// explicitly, nobody asserted it was there.
		if isRegularFile(c) && isReadableFile(c) {
			return c, nil
		}
	}
	return "", nil
}

// configCandidates lists where an accounts file can live, best first. One list for
// both jobs - the file a run looks for and the file a run creates - so the place
// 'account set' writes is the place the next command finds.
//
// Each platform is asked in its own terms and nobody else's - '~/.config' included,
// which is a Linux spelling and not a Windows or Mac one. XDG_CONFIG_HOME is a
// Linux and BSD variable, set there by a desktop session rather than by the person
// running gitsby, so reading it on Windows let an MSYS shell's leftovers decide
// where a Windows run looks for credentials.
func configCandidates() []string {
	return configCandidatesFor(runtime.GOOS, os.Getenv("XDG_CONFIG_HOME"), os.Getenv("APPDATA"), homeDir())
}

// configCandidatesFor takes its inputs rather than reading them, so the two orders
// this machine can never produce are still testable from it.
func configCandidatesFor(goos, xdgConfigHome, appData, home string) []string {
	var out []string
	switch goos {
	case "windows":
		// %APPDATA% and nothing else. A '.config' folder in a Windows profile is an
		// MSYS habit, not a Windows convention, so it is reached for only where
		// APPDATA is somehow unset - and then as the last thing left to try, same as
		// a Mac with no home directory.
		if appData != "" {
			return []string{appData + "/gitsby/config.shcl"}
		}
	case "darwin":
		// Application Support and nothing else, same rule as Windows. macOS is a Unix
		// underneath, but '~/.config' is a Linux spelling rather than a Mac one.
		if home != "" {
			return []string{home + "/Library/Application Support/gitsby/config.shcl"}
		}
	default:
		if xdgConfigHome != "" {
			out = append(out, xdgConfigHome+"/gitsby/config.shcl")
		}
	}
	if home != "" {
		out = append(out, home+"/.config/gitsby/config.shcl")
	}
	return out
}

// defaultConfigFile is where an accounts file goes when there isn't one yet: the
// first place 'load' would look, so the file this writes is the file the next run
// finds. Empty where the machine offers nowhere at all.
func defaultConfigFile() string {
	if c := configCandidates(); len(c) > 0 {
		return c[0]
	}
	return ""
}

// displayPath writes a path the way somebody would type it, folding a leading home
// directory back to '~'. Only for display: the accounts file is usually under home,
// and its absolute spelling is long enough to be the whole line.
func displayPath(p string) string {
	home := homeDir()
	if home == "" || p == "" {
		return nativePath(p)
	}
	if p == home {
		return "~"
	}
	if rest, found := strings.CutPrefix(p, home+"/"); found {
		return nativePath("~/" + rest)
	}
	return nativePath(p)
}

// nativePath spells a path the way the platform does. Display only, and a no-op
// off Windows. Folder rules are held in one canonical form - lower case, forward
// slashes - so a listing printed them beside a 'Here' line that came straight
// from Windows, and one machine read as two.
func nativePath(p string) string {
	if !isWindows() {
		return p
	}
	return windowsPath(p)
}

// windowsPath is nativePath's conversion on its own, so it can be exercised
// anywhere. The drive letter is folded up as well as the separators: 'c:' beside
// 'C:' reads as a different disk, which is the whole complaint.
func windowsPath(p string) string {
	if p == "" {
		return p
	}
	p = strings.ReplaceAll(p, "/", `\`)
	if len(p) >= 2 && p[1] == ':' {
		p = strings.ToUpper(p[:1]) + p[1:]
	}
	return p
}

func pathExists(p string) bool { _, err := os.Stat(p); return err == nil }

func isDir(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.IsDir()
}

// dirEmpty errs toward "empty": an unreadable directory lists nothing, same as
// the scripts' 'ls -A', and whatever comes next fails on its own terms.
func dirEmpty(p string) bool {
	entries, err := os.ReadDir(p)
	return err != nil || len(entries) == 0
}

func isRegularFile(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.Mode().IsRegular()
}

func isReadableFile(p string) bool {
	f, err := os.Open(p)
	if err != nil {
		return false
	}
	// Opened only to probe readability; nothing was written, so Close has nothing to say.
	_ = f.Close()
	return true
}

// The byte-order mark a Windows editor writes at the top of a file it saves.
const utf8BOM = "\ufeff"

var acctNameOK = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// What a hostname or a forge login may contain. Deliberately narrower than either
// spec allows: these two reach a shell through the credential helper, and nothing
// legitimate is being excluded.
var forgeWordOK = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// Characters a shell would act on rather than pass through as part of a path.
// '~' is deliberately absent: the shell expands it, and '~/.ssh/id_ed25519' is
// how everyone writes a key path.
const sshKeyShellChars = " \t\n\r\"'\\$;&|<>()*?![]{}" + "`"

// load reads the config once. A file that cannot be read at all is the same as no
// file: the caller asserted nothing about it, and every account path degrades to
// gh's own.
func (c *config) load(o options) error {
	if c.loaded {
		return nil
	}
	c.loaded = true
	file, err := o.resolveConfigFile()
	if err != nil {
		return err
	}
	if file == "" {
		return nil
	}
	c.file = file
	data, err := os.ReadFile(file)
	if err != nil {
		return nil
	}
	// The byte-order mark a Windows editor writes by default, off the front of the
	// first line. Left on, it landed on the first key in the file, which then read
	// as one nothing understands - and the line that reports those printed the mark
	// as part of the name, so the one diagnostic meant to explain the loss named a
	// key that looks perfectly valid.
	text := strings.TrimPrefix(string(data), "\ufeff")
	if isFlatConfig(text) {
		c.flat = true
		c.loadFlat(text)
		return nil
	}
	c.loadDoc(shcl.Parse(text))
	return nil
}

// loadFlat reads the old layout: flat 'key = value' lines, '#' comments, blank
// lines ignored. The reader the scripted builds had, kept as it was.
func (c *config) loadFlat(text string) {
	for _, line := range splitLines(text) { // a file written on Windows, read on Linux
		line = strings.TrimLeft(line, " \t")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, rawValue, found := strings.Cut(line, "=")
		if !found {
			c.unknown = append(c.unknown, line)
			continue
		}
		key = strings.ToLower(strings.TrimRight(key, " \t"))
		value := parseConfigValue(strings.TrimLeft(rawValue, " \t"))
		if key == "" {
			continue
		}
		// An account name becomes a file name under the include directory, so hold
		// it to characters that cannot climb out of there. A stray slash is an
		// ordinary typo, and 'account apply' wrote the fragment wherever it pointed.
		acct, field, ok := splitAccountKey(key)
		if !ok {
			if key == "protocol" {
				c.values[key] = value
				continue
			}
			c.unknown = append(c.unknown, key)
			continue
		}
		c.absorb(acct, field, value, key)
	}
}

// absorb takes one per-account setting into the model, from either layout. field
// is lower case; key is the setting as the file spelled it, for the ignored list.
func (c *config) absorb(acct, field, value, key string) {
	switch field {
	case "path":
		if value != "" {
			c.paths = append(c.paths, acctRule{canonPath(value), acct})
		}
	case "pathcontains":
		if value != "" {
			c.segments = append(c.segments, acctRule{canonSegment(value), acct})
		}
	case "ghaccount", "tokenfile", "sshkey", "name", "email", "protocol", "host", "user":
		// git hands GIT_SSH_COMMAND and core.sshCommand to a shell, so a key
		// path carrying whitespace or a shell character is re-parsed there
		// rather than used - and this file is redirectable by flag and by
		// environment variable. Drop it and say so: quietly falling back to
		// whatever key ssh picks is how you push as the wrong person.
		if field == "sshkey" && strings.ContainsAny(value, sshKeyShellChars) {
			c.unknown = append(c.unknown, key+" (shell characters in the path)")
			value = ""
		}
		// 'host' and 'user' are interpolated into the credential helper, which
		// git hands to a shell exactly as it hands one core.sshCommand. Neither
		// has any business carrying a character a shell would act on, so hold
		// them to what a hostname and a login can actually contain rather than
		// trust the file - it is redirectable by flag and by environment variable.
		if (field == "host" || field == "user") && value != "" && !forgeWordOK.MatchString(value) {
			c.unknown = append(c.unknown, key+" (not a plain "+field+" name)")
			value = ""
		}
		c.values["account."+acct+"."+field] = value
		if !contains(c.order, acct) {
			c.order = append(c.order, acct)
		}
	default:
		// Named but not understood. Not fatal - a config from a newer gitsby
		// still has to work - but never silent either: a mistyped key nothing
		// reads is how you act as the wrong account believing you configured it.
		c.unknown = append(c.unknown, key)
	}
}

func contains(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}

// splitAccountKey takes 'account.<name>.<field>' apart, validating the name.
// Anything malformed comes back not-ok, and the caller lists the key as unknown.
func splitAccountKey(key string) (acct, field string, ok bool) {
	rest, found := strings.CutPrefix(key, "account.")
	if !found {
		return "", "", false
	}
	dot := strings.LastIndex(rest, ".")
	if dot < 0 {
		return "", "", false
	}
	acct, field = rest[:dot], rest[dot+1:]
	// An empty field ('account.work.') is not an account key either; the whole line
	// lands with the other ignored ones instead of half-parsing.
	if field == "" || !acctNameOK.MatchString(acct) {
		return "", "", false
	}
	return acct, field, true
}

// parseConfigValue trims a flat-layout value: one optional layer of quotes keeps
// a literal '#' or meaningful trailing space; otherwise a '#' after whitespace
// starts a comment, here as well as at the start of a line. Folding one into the
// value made a folder rule that could never match, which reads exactly like no
// rule at all.
func parseConfigValue(value string) string {
	value, _ = splitFlatValue(value)
	return value
}

// splitFlatValue is parseConfigValue with the trailing comment handed back too,
// so a conversion to the current layout can keep it.
func splitFlatValue(raw string) (value, comment string) {
	if len(raw) >= 2 && (raw[0] == '"' || raw[0] == '\'') {
		if end := strings.IndexByte(raw[1:], raw[0]); end >= 0 {
			if rest := strings.TrimSpace(raw[2+end:]); strings.HasPrefix(rest, "#") {
				comment = "  " + rest
			}
			return raw[1 : 1+end], comment
		}
	}
	for i := 0; i+1 < len(raw); i++ {
		if (raw[i] == ' ' || raw[i] == '\t') && raw[i+1] == '#' {
			return strings.TrimRight(raw[:i], " \t"), "  " + raw[i+1:]
		}
	}
	if strings.HasPrefix(raw, "#") {
		return "", "  " + raw
	}
	return strings.TrimRight(raw, " \t"), ""
}

// accountForDir names the configured account whose folder contains this one.
// An absolute 'path' rule wins over a 'pathContains' when both match: naming the
// machine's own tree is the more specific claim. Within each kind the more
// specific rule wins - the longest path, or the most folder names - so a tree
// nested inside another account's tree belongs to the inner one. First defined
// breaks an exact tie.
func (c *config) accountForDir(dir string) string {
	target := canonPath(dir)
	if target == "" {
		return ""
	}
	best, bestLen := "", 0
	for _, r := range c.paths {
		if r.match == "" {
			continue
		}
		if target != r.match && !strings.HasPrefix(target, r.match+"/") {
			continue
		}
		if len(r.match) > bestLen {
			best, bestLen = r.acct, len(r.match)
		}
	}
	if best != "" {
		return best
	}
	// Whole folder names only, which is what the slashes on both sides buy:
	// 'jim-collier' must not match a directory called 'jim-collier-old'. Wrapping
	// the target in slashes lets the run match at either end as well as the middle.
	bestSegs := 0
	for _, r := range c.segments {
		if r.match == "" {
			continue
		}
		if !strings.Contains("/"+target+"/", "/"+r.match+"/") {
			continue
		}
		segs := strings.Count(r.match, "/") + 1
		if segs > bestSegs {
			best, bestSegs = r.acct, segs
		}
	}
	return best
}

// knowsAccount: whether the file defines this account at all, by any key or any
// folder rule. Deliberately not the same question as whether it names a GitHub
// login - an account can be a commit identity and an ssh key and nothing else,
// which is how you hold a second identity with no gh involved, and what the
// folder rules have always applied.
func (c *config) knowsAccount(name string) bool {
	return name != "" && contains(c.accountNames(), strings.ToLower(name))
}

// value reads one key of one configured account. Both halves lowercased, because
// the loader lowercases the whole key on the way in - leaving the name as typed
// made 'GITSBY_ACCOUNT=Work' miss an account stored as 'work', silently.
func (c *config) value(name, key string) string {
	if name == "" || key == "" {
		return ""
	}
	return c.values["account."+strings.ToLower(name)+"."+strings.ToLower(key)]
}

// contextDir is what "here" means for folder matching: the repo's top level when
// in one, so every subdirectory resolves to the same account, and the working
// directory when not - which is what a fresh 'repo clone' has to go on.
func (a *app) contextDir() string {
	return a.git.contextDir.get(func() string {
		if top := runOut("git", "rev-parse", "--show-toplevel"); top != "" {
			return top
		}
		// A cwd nothing can name leaves the context empty, which reads as "nowhere"
		// to every rule that matches against it.
		wd, _ := os.Getwd()
		return wd
	})
}
