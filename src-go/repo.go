// The repo lifecycle commands: clone, create, connect, url. Everything they need
// settles before the plan is shown - which remote, which directory, which mode -
// so a bad argument or an unreachable target refuses up front, and the preview
// promises only what will actually run.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"bytes"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

// repoTarget is what create, connect, clone and url settled about the remote
// before their plan was printed.
type repoTarget struct {
	cloneURL    string
	cloneDir    string
	connectMode string // "create" | "add" | "push"; what create and connect disagree about
	connectURL  string
	ghTarget    string // 'owner/name' when gh is the one doing the creating or answering
}

// repoExistence is what we could establish about a remote. Unknown is its own
// answer, not a synonym for missing: gh exits nonzero for a name that resolves to
// nothing and for a network that is down alike, and stating the first when it was
// the second sends you off to create something you already have.
type repoExistence int

const (
	repoUnknown repoExistence = iota
	repoMissing
	repoEmpty
	repoNonEmpty
)

var ownerNameRE = regexp.MustCompile(`^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)

// isLocalPath: a remote that is a directory on this machine, rather than
// something to connect to.
func isLocalPath(url string) bool {
	if url == "" {
		return false
	}
	if isDrivePath(url) { // a Windows drive path is not 'host:path'
		return true
	}
	if strings.Contains(url, "://") {
		return false
	}
	if strings.Index(url, ":") >= 1 { // scp-like host:path, with or without a user
		return false
	}
	return true
}

// sameRemote: whether two remote URLs name the same place. Text settles it for a
// real URL, but git rewrites a local path into the platform's own spelling when
// it stores one - hand it '/c/tmp/x' on Windows and it gives back 'C:/tmp/x' -
// so comparing our own argument against git's copy said "different" for the same
// directory, and a re-run of 'repo clone' refused itself.
func sameRemote(a, b string) bool {
	if a == "" || b == "" {
		return false
	}
	if a == b {
		return true
	}
	if !isLocalPath(a) || !isLocalPath(b) {
		return false
	}
	return canonPath(a) == canonPath(b)
}

// probeRemote is one network round-trip: does the remote exist, and does it have
// history? No auth prompts - a bad https URL would otherwise stop and ask for
// credentials mid-run - and the timeout composes onto git's own ssh command, so
// a per-repo core.sshCommand still probes as the key git actually pushes with.
func (a *app) probeRemote(url string) repoExistence {
	probe := exec.Command("git", "ls-remote", url)
	probe.Env = a.remoteEnv()
	out, err := probe.Output()
	if err != nil {
		return repoMissing
	}
	if strings.TrimRight(string(out), "\r\n") != "" {
		return repoNonEmpty
	}
	return repoEmpty
}

// ghRepoState asks gh what exists at 'owner/name', plus the reason gh gave when
// it could not say. These two commands skip the pre-command fetch (they have no
// origin yet), so this is the only place either can discover a network that is down.
func ghRepoState(target string) (repoExistence, string) {
	cmd := exec.Command("gh", "repo", "view", target, "--json", "isEmpty", "--jq", ".isEmpty")
	var errText bytes.Buffer
	cmd.Stderr = &errText
	out, err := cmd.Output()
	if err == nil {
		if strings.TrimRight(string(out), "\r\n") == "true" {
			return repoEmpty, ""
		}
		return repoNonEmpty, ""
	}
	said := errText.String()
	// What gh says, and only what gh says, when the name resolves to nothing.
	if strings.Contains(said, "Could not resolve to a Repository") || strings.Contains(said, "404") {
		return repoMissing, ""
	}
	for _, line := range splitLines(said) {
		if line != "" {
			return repoUnknown, line
		}
	}
	return repoUnknown, "gh gave no reason"
}

// settleRepoURL refuses a bad argument or an unconvertible remote before a plan
// promises anything. True means the answer was "nothing to do" and main is done.
func (a *app) settleRepoURL() (bool, error) {
	a.cmd.arg = strings.ToLower(a.cmd.arg)
	if a.cmd.arg != "" && a.cmd.arg != "https" && a.cmd.arg != "ssh" {
		return false, usagef("Syntax: %s repo url [https|ssh]", meName)
	}
	// Exempt from the repo gate with its 'repo-' siblings, but unlike them it has
	// nothing to say outside one - it re-spells a remote a repo has to already have.
	if !a.inRepo {
		return false, usagef("Not inside a git repository. Change to a git project directory first.")
	}
	current := a.originURL()
	if current == "" {
		return false, usagef("No origin to re-spell. Connect one first: %s repo connect <url | owner/name>", meName)
	}
	if a.cmd.arg != "" {
		// Any host, not just github.com: re-spelling a remote is text work that the
		// host never hears about, and refusing it anywhere else was the parser's limit
		// showing through as a rule. A local path still has nothing to re-spell.
		if remoteTarget(current) == "" || a.originHost() == "" {
			return false, usagef("origin (%s) has no host and 'owner/name' to re-spell, so there is no other spelling of it to switch to.", maskURL(current))
		}
		if forgeURL(a.originHost(), remoteTarget(current), a.cmd.arg) == current {
			a.out.status("origin already uses " + a.cmd.arg + "; nothing to do.")
			a.out.clean("")
			return true, nil
		}
	}
	return false, nil
}

// cloneDestDir names where a clone will land, from the arguments alone. Asked
// before the account is resolved as well as when the clone is settled: the folder
// rules that pick the account are the destination's, and nothing has touched the
// disk by then. Empty means the URL carried no name to derive one from.
func cloneDestDir(url, dir string) string {
	if dir != "" {
		return dir
	}
	d := strings.TrimSuffix(url, "/")
	d = strings.TrimSuffix(d, ".git")
	d = d[strings.LastIndex(d, "/")+1:]
	return d[strings.LastIndex(d, ":")+1:]
}

func (a *app) cloneDestDir() string { return cloneDestDir(a.cmd.arg, a.cmd.arg2) }

// settleRepoClone derives the target dir, and makes re-runs a no-op instead of
// an error. True means main is done.
func (a *app) settleRepoClone() (bool, error) {
	if a.cmd.arg == "" {
		return false, usagef("No URL given. Syntax: %s repo clone <url> [directory]", meName)
	}
	// 'owner/name' is what create and connect take; refusing it here only after
	// the plan was confirmed is the surprise.
	// 'owner/name' has only ever meant github.com, so the transport question is
	// about github.com too - not about whichever host the directory we are standing
	// in happens to use.
	if ownerNameRE.MatchString(a.cmd.arg) && !pathExists(a.cmd.arg) {
		a.cmd.arg = githubURL(a.cmd.arg, a.protocolFor("github.com"))
	}
	a.tgt.cloneURL, a.tgt.cloneDir = a.cmd.arg, a.cloneDestDir()
	if a.tgt.cloneDir == "" {
		return false, usagef("Can't derive a directory name from '%s'; give one explicitly.", maskURL(a.tgt.cloneURL))
	}
	if pathExists(a.tgt.cloneDir) {
		existingURL := runOut("git", "-C", a.tgt.cloneDir, "remote", "get-url", "origin")
		if pathExists(a.tgt.cloneDir+"/.git") && sameRemote(existingURL, a.tgt.cloneURL) {
			a.out.status("'" + a.tgt.cloneDir + "' is already a clone of that URL; nothing to do.")
			a.out.clean("")
			return true, nil
		}
		// An empty dir is fine (git allows it); anything else would clobber.
		if !isDir(a.tgt.cloneDir) || !dirEmpty(a.tgt.cloneDir) {
			return false, usagef("'%s' already exists and isn't a clone of that URL.", a.tgt.cloneDir)
		}
	}
	return false, nil
}

// settleRepoConnect resolves what create/connect are publishing to before the
// preview, so the plan is real. Same machinery, one difference - only 'create'
// will bring a remote into existence.
func (a *app) settleRepoConnect() error {
	wantCreate := a.cmd.name == "repo-create"
	hasWork := false
	if a.inRepo {
		hasWork = runOK("git", "rev-parse", "-q", "--verify", "HEAD") || runOut("git", "status", "--porcelain") != ""
	} else {
		hasWork = !dirEmpty(".")
	}
	if !hasWork {
		return usagef("Nothing to publish here: no commits and no files.")
	}
	existingOrigin := ""
	if a.inRepo {
		existingOrigin = a.originURL()
	}
	switch {
	case existingOrigin != "":
		if wantCreate {
			return usagef("origin is already set to '%s', so there is no repo left to create. Push what you have with: %s repo connect", maskURL(existingOrigin), meName)
		}
		if a.cmd.arg != "" && !sameRemote(a.cmd.arg, existingOrigin) {
			return usagef("origin is already set to '%s'; changing remotes is raw-git territory.", maskURL(existingOrigin))
		}
		a.tgt.connectMode, a.tgt.connectURL = "push", existingOrigin
		return nil
	case wantCreate:
		return a.settleRepoCreate()
	default:
		return a.settleRepoConnectTo()
	}
}

func (a *app) settleRepoCreate() error {
	if a.cmd.arg == "" {
		return usagef("No target given. Syntax: %s repo create <owner/name>", meName)
	}
	if !ownerNameRE.MatchString(a.cmd.arg) || pathExists(a.cmd.arg) {
		return usagef("'%s' isn't a GitHub 'owner/name'; only GitHub repos can be created from here. For a remote that already exists: %s repo connect %s", a.cmd.arg, meName, a.cmd.arg)
	}
	if err := mustBeInPath("gh"); err != nil {
		return err
	}
	a.tgt.ghTarget = a.cmd.arg
	switch state, reason := ghRepoState(a.tgt.ghTarget); state {
	case repoUnknown:
		return usagef("Couldn't ask GitHub about %s, so there is no telling whether it exists: %s", a.tgt.ghTarget, reason)
	case repoMissing:
		a.tgt.connectMode = "create"
		return nil
	case repoEmpty:
		return usagef("github.com/%s already exists and is empty; connect to it instead: %s repo connect %s", a.tgt.ghTarget, meName, a.tgt.ghTarget)
	default:
		return usagef("github.com/%s already has commits; clone it instead (%s repo clone), or reconcile with raw git.", a.tgt.ghTarget, meName)
	}
}

func (a *app) settleRepoConnectTo() error {
	if a.cmd.arg == "" {
		return usagef("No remote configured and no target given. Syntax: %s repo connect <url | owner/name>", meName)
	}
	if !ownerNameRE.MatchString(a.cmd.arg) || pathExists(a.cmd.arg) {
		switch a.probeRemote(a.cmd.arg) {
		case repoMissing:
			return usagef("Can't reach '%s' (doesn't exist, or no access). Create it first, or on GitHub: %s repo create <owner/name>", maskURL(a.cmd.arg), meName)
		case repoNonEmpty:
			return usagef("'%s' already has history; clone it instead (%s repo clone %s), or reconcile with raw git.", maskURL(a.cmd.arg), meName, maskURL(a.cmd.arg))
		default:
			a.tgt.connectMode, a.tgt.connectURL = "add", a.cmd.arg
			return nil
		}
	}
	// owner/name shorthand: gh can say whether it exists and whether it's empty.
	if err := mustBeInPath("gh"); err != nil {
		return err
	}
	a.tgt.ghTarget = a.cmd.arg
	switch state, reason := ghRepoState(a.tgt.ghTarget); state {
	case repoUnknown:
		return usagef("Couldn't ask GitHub about %s, so there is no telling whether it exists: %s", a.tgt.ghTarget, reason)
	case repoMissing:
		return usagef("github.com/%s doesn't exist, or you can't see it. To create it: %s repo create %s", a.tgt.ghTarget, meName, a.tgt.ghTarget)
	case repoEmpty:
		// gh never uses a host alias, so this is the canonical url. We build this one
		// ourselves, so the config's transport applies - unlike 'repo create', where gh
		// adds the remote and only gh's own git_protocol decides.
		a.tgt.connectURL = githubURL(a.tgt.ghTarget, a.protocolFor("github.com"))
		a.tgt.connectMode = "add"
		return nil
	default:
		return usagef("github.com/%s already has commits; clone it instead (%s repo clone), or reconcile with raw git.", a.tgt.ghTarget, meName)
	}
}

func (a *app) cmdClone() error {
	if err := a.step("git", "clone", a.tgt.cloneURL, a.tgt.cloneDir); err != nil {
		return err
	}
	// Opinionated: if the repo works dev-first, start there.
	if runOK("git", "-C", a.tgt.cloneDir, "show-ref", "--verify", "--quiet", "refs/remotes/origin/dev") {
		return a.step("git", "-C", a.tgt.cloneDir, "checkout", "dev")
	}
	return nil
}

// cmdConnect serves both 'repo create' and 'repo connect'; connectMode is what
// they disagree about.
func (a *app) cmdConnect() error {
	if !a.inRepo {
		if err := a.step("git", "init", "-b", "main"); err != nil {
			return err
		}
	}
	if err := a.cmdCommit(); err != nil { // publish everything as-is; no-op when clean
		return err
	}
	switch a.tgt.connectMode {
	case "create":
		return a.step("gh", "repo", "create", a.tgt.ghTarget, "--"+a.opt.visibility, "--source", ".", "--push", "--remote", "origin")
	case "add":
		if err := a.step("git", "remote", "add", "origin", a.tgt.connectURL); err != nil {
			return err
		}
		return a.step("git", "push", "-u", "origin", "HEAD")
	case "push":
		// origin already set - just make sure everything is published
		switch {
		case !a.hasUpstream():
			return a.step("git", "push", "-u", "origin", "HEAD")
		case isAhead():
			return a.step("git", "push")
		default:
			a.out.status("Nothing to push; already connected and current.")
		}
	}
	return nil
}

// cmdRepoURL re-spells origin in the other transport. Nothing else about the
// repo changes: same remote, same history, same name - only how git
// authenticates to it.
func (a *app) cmdRepoURL() error {
	url := a.originURL()
	return a.step("git", "remote", "set-url", "origin", forgeURL(a.originHost(), remoteTarget(url), a.cmd.arg))
}

// cmdRepoURLShow is the bare, read-only form: what origin is now, and its other
// spelling if it has one.
func (a *app) cmdRepoURLShow() {
	urlNow := a.originURL()
	urlTarget := remoteTarget(urlNow)
	host := a.originHost()
	a.out.clean("")
	a.out.clean("origin .......: " + maskURL(urlNow))
	if urlTarget == "" || host == "" {
		a.out.clean("No host and 'owner/name' to re-spell, so there is no other spelling of it.")
		return
	}
	a.out.clean("as https .....: " + forgeURL(host, urlTarget, "https"))
	a.out.clean("as ssh .......: " + forgeURL(host, urlTarget, "ssh"))
	a.out.clean("Switch with '" + meName + " repo url <https|ssh>'.")
}

// showFilesToPublish: every in-repo command shows what it is about to touch; this
// is the one that publishes a whole directory for the first time, possibly to a
// public repo, so it owes the same. Asked through a throwaway git dir OUTSIDE the
// work tree: that way .gitignore and core.excludesFile are honored exactly as the
// real 'git add --all' will honor them (listing files git would skip is its own
// kind of wrong), and answering 'n' leaves the directory as it was found.
func (a *app) showFilesToPublish() {
	probeDir, err := os.MkdirTemp("", "")
	if err != nil {
		return
	}
	// Ours, made two lines up, and nothing outside this function ever names it.
	defer func() { _ = os.RemoveAll(probeDir) }()
	// A cwd nothing can name makes the probe list nothing; the confirm then shows an
	// empty list instead of dying, on a machine already in deeper trouble.
	wd, _ := os.Getwd()
	env := append(os.Environ(), "GIT_DIR="+probeDir, "GIT_WORK_TREE="+wd)
	initCmd := exec.Command("git", "init", "--quiet")
	initCmd.Env = env
	_ = initCmd.Run()
	a.out.clean("")
	a.out.clean("Files to publish:")
	ls := exec.Command("git", "ls-files", "--others", "--exclude-standard")
	ls.Env = env
	var outLines []string
	if out, _ := ls.Output(); len(out) > 0 {
		outLines = strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	}
	a.showLines(outLines)
	if a.lastListCount == 0 {
		a.out.clean("    (nothing - the directory is empty, or everything in it is ignored)")
	}
}
