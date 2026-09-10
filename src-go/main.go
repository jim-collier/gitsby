// gitsby, compiled. Built out against cicd/test.bash from the first commit, and now
// carrying the whole command surface. Argument parsing, the gates every command passes
// through, and the state -> plan -> confirm -> run -> state frame the mutating ones share.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"errors"
	"os"
	"strings"
	"time"
)

const meName = "gitsby"

// For help text, before we know we're in a repo.
const mergeTargetLabel = "dev/main"

// Set at build time: -ldflags "-X main.version=x.y.z". The bare default marks a
// hand-run 'go build' apart from a pipeline build.
var version = "0.0.0-dev"

const (
	copyrightYear = "2014-2026"
	author        = "Jim Collier"
	homeURL       = "https://github.com/jim-collier/gitsby"
	donateURL     = "https://github.com/sponsors/jim-collier"
)

func main() {
	out := newPrinter()
	if err := run(out, os.Args[1:]); err != nil {
		os.Exit(reportExit(out, err))
	}
}

// reportExit turns whatever came back into the framing and the status that go
// with it. Anything that does not know how it ends is a fault in here rather than
// a mistake out there, and reads as a plain refusal.
func reportExit(out *printer, err error) int {
	if errors.Is(err, errDone) {
		return 0
	}
	var reporter exitReporter
	if errors.As(err, &reporter) {
		return reporter.report(out)
	}
	return (&usageError{msg: err.Error()}).report(out)
}

func run(out *printer, argv []string) error {
	a := newApp(out)

	// Only the command slot counts for help and the version - scanning the whole
	// argv would make a message like "add -v flag" silently short-circuit.
	if len(argv) == 0 {
		a.printHelp()
		// The scripts' exit trap adds one more blank on any nonzero path.
		out.forceClean("")
		return silentExit(1)
	}
	switch strings.ToLower(argv[0]) {
	case "-h", "--help", "help":
		a.printHelp()
		return nil
	case "-v", "--ver", "--version", "version":
		a.printCopyright()
		return nil
	case "--about", "about":
		a.printAbout()
		return nil
	case "--donate", "donate":
		a.printDonate()
		return nil
	}

	// 'raw git|gh' hands everything after the tool to the real thing, verbatim, as
	// the account this folder belongs to. Scanned ahead of the main parser and of
	// the git PATH check - 'raw gh' must work without git installed.
	tool, ptArgs, err := scanPassthrough(argv, &a.opt)
	if err != nil {
		return err
	}
	if tool != "" {
		return a.cmdPassthrough(tool, ptArgs)
	}

	// Breathing room after the shell prompt (the matching trailing blank is at each
	// exit path). After the passthrough, which owns its own output.
	out.clean("")

	if err := mustBeInPath("git"); err != nil {
		return err
	}
	if err := a.settleCommand(argv); err != nil {
		return err
	}
	if a.cmd.name == "" { // help was asked for, and printed
		return nil
	}
	a.printBanner()
	if err := a.enterRepo(); err != nil {
		return err
	}
	if err := a.settleAccount(); err != nil {
		return err
	}
	a.freshenRemote()
	if err := a.settleBranchNames(); err != nil {
		return err
	}
	if err := a.preflight(); err != nil {
		return err
	}
	done, err := a.settleTarget()
	if err != nil || done {
		return err
	}
	if err := a.settleGh(); err != nil {
		return err
	}
	mismatch, err := a.identityGate()
	if err != nil {
		return err
	}
	if !a.cmd.mutating {
		return a.runReadOnly()
	}
	return a.runMutating(mismatch)
}

// settleCommand parses the argument list and settles which command this is: the
// flat name, its arguments, and whether it mutates anything. An empty command
// name on return means help was asked for and has already printed.
func (a *app) settleCommand(argv []string) error {
	opt, cmd, help, err := parseArgs(argv)
	if err != nil {
		return err
	}
	a.opt, a.cmd = opt, cmd
	if help {
		a.printHelp()
		a.out.clean("")
		a.cmd.name = ""
		return nil
	}
	// Both visibilities given is a contradiction, not a precedence question - and
	// silently picking one would publish a repo the caller believes is the other.
	if a.opt.sawPublic && a.opt.sawPrivate {
		return usagef("--public and --private are mutually exclusive; pick one.")
	}
	// Options and no command asks the same thing no arguments at all asks.
	if a.cmd.name == "" {
		a.printHelp()
		a.out.forceClean("")
		return silentExit(1)
	}
	if a.cmd, err = collapseCommand(a.cmd); err != nil {
		return err
	}
	if a.cmd, err = sortCommand(a.cmd, &a.opt); err != nil {
		return err
	}
	// Whether -q was typed, captured before the rule below writes the same field -
	// otherwise every piped run looks like it asked for quiet.
	a.opt.sawQuiet = a.opt.quiet
	// No tty = nobody to answer a prompt. Read-only commands just go quiet;
	// mutating ones fail closed (require an explicit -q) so piped/cron input can't
	// silently auto-confirm.
	if !isTTY(os.Stdin) {
		if a.cmd.mutating && !a.opt.quiet {
			return usagef("No terminal to confirm on; re-run with -q to proceed without prompts.")
		}
		a.opt.quiet = true
	}
	// pr's own shape, ahead of the repo gate like the scripts: a malformed pr call
	// is wrong anywhere, in a repo or not.
	if a.cmd.name == "pr" {
		return a.sortPr()
	}
	return nil
}

// enterRepo settles whether we are inside a work tree, and refuses the commands
// that need one. Every command does - except the repo ones: clone works anywhere,
// and create/connect exist precisely to turn a plain directory into one.
// 'whoami' too: which account a folder belongs to is worth asking before there
// is a repo in it.
func (a *app) enterRepo() error {
	// One call, three answers. The exit code is no use here: rev-parse answers all
	// of these in text and exits zero either way, so success says only that we are
	// somewhere git understands - which a bare repo and the .git directory itself
	// both are, and neither is a place where any of this means anything. A bare one
	// answers true to --is-inside-git-dir as well, so it has to be named first.
	answers := runLines("git", "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir", "--is-bare-repository")
	if len(answers) == 3 {
		if answers[2] == "true" {
			return usagef("This is a bare repository: no working tree, so there is nothing here to commit, switch or push. Work in a clone of it instead.")
		}
		if answers[1] == "true" {
			return usagef("This is the '.git' directory itself, not the work tree. Change up out of it first.")
		}
	}
	a.inRepo = len(answers) == 3 && answers[0] == "true"
	if a.inRepo || a.cmd.name == "whoami" ||
		strings.HasPrefix(a.cmd.name, "repo-") || strings.HasPrefix(a.cmd.name, "account-") {
		return nil
	}
	return usagef("Not inside a git repository. Change to a git project directory first.")
}

// settleAccount points this run at the account whose folder this is, before
// anything reaches the network: the fetch afterwards authenticates, so getting
// this wrong here gets it wrong for the whole command. It also validates
// --config/GITSBY_CONFIG, so it stays ahead of every other refusal - the same
// contract the scripts keep.
func (a *app) settleAccount() error {
	acctDir, acctURL := a.contextDir(), a.originURL()
	switch {
	case a.cmd.name == "repo-clone":
		// The clone lands somewhere else, and it is that folder's rules that pick the
		// account - not the rules for whatever repo the cwd happens to sit inside.
		// Nothing stands in for them here: the owner of the repo being cloned is no
		// evidence it is ours, which is the whole difference between fetching a copy
		// of something and owning it. Unresolved leaves gh on its own account.
		acctDir, acctURL = absDir(a.cloneDestDir()), ""
	case acctURL == "" && (a.cmd.name == "repo-create" || a.cmd.name == "repo-connect") && a.cmd.arg != "":
		// These have no origin to read an owner from, but the repo they are about to
		// publish to is on the command line - and it is that repo's owner whose account
		// should do the publishing. Resolved here rather than after their own
		// validation, because the validation itself talks to gh.
		if ownerNameRE.MatchString(a.cmd.arg) && !pathExists(a.cmd.arg) {
			acctURL = githubURL(a.cmd.arg, "https")
		} else {
			acctURL = a.cmd.arg
		}
	}
	if err := a.resolveAccount(acctDir, acctURL); err != nil {
		return err
	}
	// The probe inside it only feeds the identity block, so a run that prints none
	// skips a live round trip.
	return a.selectAccount(!a.identityWillPrint())
}

// freshenRemote updates remote refs so status/ahead-behind info is current. Never
// fatal - offline still works locally. clone skips it: cwd may sit inside some
// unrelated repo, and the clone doesn't care about it.
func (a *app) freshenRemote() {
	if !a.opt.fetch || a.cmd.name == "repo-clone" || strings.HasPrefix(a.cmd.name, "account-") || !a.hasOrigin() {
		return
	}
	a.out.status("git fetch ...")
	a.fetchRemote()
}

// settleBranchNames resolves the two branch names every command downstream hands
// git. They can't change mid-command, so they settle once, post-fetch so
// origin/HEAD is fresh. status, whoami and br list run without a resolvable
// default branch on purpose: they mutate nothing and are the commands you run to
// see what is wrong, so they report "unknown" instead of refusing.
func (a *app) settleBranchNames() error {
	if !a.inRepo {
		return nil
	}
	dflt, target := a.defaultBranch(), a.mergeTarget()
	if !a.needsConfirmableBranch() || !runOK("git", "rev-parse", "-q", "--verify", "HEAD") {
		return nil
	}
	// These are the names every command downstream hands git in a leading argument
	// position.
	if err := refuseOptionShapedRefs(a.currentBranch(), dflt, target); err != nil {
		return err
	}
	if dflt == "" {
		return usagef("Can't tell this repo's default branch. Set it with 'git remote set-head origin --auto', or create a main/master.")
	}
	if !branchExistsLocal(dflt) && !branchExistsRemote(dflt) {
		return usagef("This repo's default branch resolves to '%s', which exists neither here nor on origin. Fix it with 'git remote set-head origin --auto'.", dflt)
	}
	return nil
}

// needsConfirmableBranch: every branch command checks the default branch out,
// protects it, or merges into it, so a name we can't confirm has to stop things
// before a preview promises it. The three read-only state commands are exempt for
// the reason above.
func (a *app) needsConfirmableBranch() bool {
	switch a.cmd.name {
	case "status", "whoami", "br-list":
		return false
	}
	return !strings.HasPrefix(a.cmd.name, "repo-") && !strings.HasPrefix(a.cmd.name, "account-")
}

// preflight is every refusal that has to land before a plan is shown: the
// commands that exist to publish and can't, the ones whose argument is wrong, and
// the ones whose work is decided up front.
func (a *app) preflight() error {
	// Commands that exist to publish, refused here rather than halfway through on
	// raw git text - and far better than "succeeding" having sent nothing. The rest
	// degrade instead: they mean something locally, so they run and say what they
	// skipped.
	// Which forge this repo lives on, and which CLI can speak to it - settled before
	// any pr refusal, so the reason a pr command can't run is the real one rather
	// than whichever tool happened to be missing.
	if a.cmd.name == "pr" {
		if err := a.settlePrTool(); err != nil {
			return err
		}
	}
	switch a.cmd.name {
	case "sync":
		if err := a.requireOnline("sync", "Offline, '"+meName+" pullcom' skips the pull and just commits; run '"+meName+" sync' when you are back online."); err != nil {
			return err
		}
	case "release":
		// With no remote at all the check below never trips - there is nothing to find
		// unreachable - and the tag would be cut, pushed nowhere, and reported as done.
		if !a.hasOrigin() {
			return usagef("No 'origin' remote, and a release nobody can fetch isn't one. Connect one first: %s repo connect <url | owner/name>", meName)
		}
		if err := a.requireOnline("release", "A release nobody can fetch isn't one."); err != nil {
			return err
		}
	case "pr":
		if a.pr.sub != "" {
			if err := a.requireOnline("pr "+a.pr.sub, "The pull request lives on GitHub; there is no local half to do first."); err != nil {
				return err
			}
		}
	}
	// The release version resolves up front so the preview and the command agree,
	// and so bad input dies early.
	if a.cmd.name == "release" {
		if err := a.resolveRelease(); err != nil {
			return err
		}
		if err := a.releasePreflight(); err != nil {
			return err
		}
	}
	// The mutating pr subcommands check here too, so nothing can fail after the plan
	// was confirmed.
	if a.pr.sub != "" {
		if err := a.prPreflight(); err != nil {
			return err
		}
	}
	return a.preflightBranch()
}

// preflightBranch validates branch arguments up front, so a bad name can't
// survive to a nonsense preview.
func (a *app) preflightBranch() error {
	switch a.cmd.name {
	case "br-create":
		if a.cmd.arg == "" {
			return usagef("No branch name given. Syntax: %s br create <new branch name>", meName)
		}
		return checkNewBranchName(a.cmd.arg)
	case "br-hotfix":
		if a.cmd.arg == "" {
			return usagef("No name given. Syntax: %s br hotfix <name>", meName)
		}
		// The prefix is the marker, so put it on ourselves - and accept it if the user
		// typed it.
		a.cmd.arg = "hotfix/" + strings.TrimPrefix(a.cmd.arg, "hotfix/")
		return checkNewBranchName(a.cmd.arg)
	case "br-merge":
		// Merging ends in 'git branch -d', so a leftover main/master must be refused
		// here for the same reason br prune never lists one - and up front, not after a
		// destructive plan was shown.
		if a.isProtectedBranch("") {
			return usagef("'%s' is a protected branch; landing it would delete it. Run this from a work branch instead.", a.currentBranch())
		}
	case "br-switch":
		if a.cmd.arg != "" && !branchExistsLocal(a.cmd.arg) && !branchExistsRemote(a.cmd.arg) {
			return usagef("No branch '%s' locally or on origin. To create it: %s br create %s", a.cmd.arg, meName, a.cmd.arg)
		}
		// Refusing a dirty protected branch belongs here too, before the plan is shown
		// and confirmed.
		switchTarget := a.cmd.arg
		if switchTarget == "" {
			switchTarget = a.mergeTarget()
		}
		if a.currentBranch() != switchTarget && a.isProtectedBranch("") && runOut("git", "status", "--porcelain") != "" {
			return usagef("Working tree has changes on '%s'; won't auto-commit to a protected branch. Carry them to a new branch (%s br create <name>), or commit them here deliberately (%s pullcom) first.", a.currentBranch(), meName, meName)
		}
	}
	return nil
}

// settleTarget resolves what each remaining command is about to act on, before
// anything is shown. True means the answer was "nothing to do" and the run is over.
func (a *app) settleTarget() (bool, error) {
	switch a.cmd.name {
	case "repo-url":
		// Everything it needs to know settles here, so a bad argument or an
		// unconvertible remote is refused before a plan promises anything.
		return a.settleRepoURL()
	case "br-prune":
		// Work out what goes before anything is shown, so the plan names every branch
		// by name. An empty plan is a plain read-only answer.
		if a.currentBranch() == "" {
			return false, usagef("Detached HEAD (no current branch); resolve that manually first.")
		}
		if err := a.resolvePrune(); err != nil {
			return false, err
		}
		if a.prune.empty() {
			a.pruneNothingToDo()
			a.out.clean("")
			return true, nil
		}
	case "repo-clone":
		// Derive the target dir, and make re-runs a no-op instead of an error.
		return a.settleRepoClone()
	case "repo-create", "repo-connect":
		// Resolve what we're publishing to before the preview, so the plan is real.
		return false, a.settleRepoConnect()
	}
	return false, nil
}

// settleGh works out which commands go through gh, which of those WRITE through
// it, and which url the ssh identity should be read from. For pr that's the origin
// we already have. repo create and connect have no origin yet - but the one they
// are about to set is knowable, because gh never uses a host alias: it builds
// 'git@github.com:owner/name.git' from its own protocol setting. So the identity
// that repo will live with afterward can be checked before we start.
func (a *app) settleGh() error {
	switch a.cmd.name {
	case "whoami":
		// Reads the forge, writes nothing: the whole point of the command is to name
		// every account involved. gh answers for a GitHub remote and for no remote at
		// all - with nothing to take a host from, its account is still the only one
		// that can be asked. Any other host is the Git host line's business.
		if a.onGitHub() || !a.hasOrigin() {
			a.gh.tool, a.gh.cli, a.gh.isCommand = toolGh, "gh", true
		} else {
			a.gh.tool, a.gh.cli = a.originTool()
			a.gh.isCommand = a.gh.tool != toolNone
		}
	case "pr":
		a.gh.tool, a.gh.cli = a.pr.tool, a.pr.cli
		a.gh.isCommand = a.pr.tool != toolNone
		// A write is a write whichever CLI makes it: 'pr create' and 'pr ok' act as
		// the forge account while git pushes as the key, and those two disagreeing is
		// the same wrong-account mistake on any host.
		if a.pr.sub != "" && a.gh.isCommand {
			a.gh.isWrite = true
			a.gh.probeURL = a.originURL()
		}
	case "repo-create":
		a.gh.isCommand, a.gh.isWrite = true, true
		a.gh.tool, a.gh.cli = toolGh, "gh"
		// 'repo create' is a GitHub command by definition - gh is what creates the
		// repo - so the host it asks about is github.com, not whatever origin the
		// directory we happen to be standing in points at.
		if a.ghProtocol("github.com") == "ssh" {
			a.gh.probeURL = "git@github.com:" + a.tgt.ghTarget + ".git"
		}
	case "repo-connect":
		if a.tgt.ghTarget != "" {
			a.gh.isCommand, a.gh.isWrite = true, true
			a.gh.tool, a.gh.cli = toolGh, "gh"
			// connectURL is the url we resolved ourselves, so probe that rather than
			// guess.
			if at := strings.Index(a.tgt.connectURL, "@"); at >= 0 && strings.Contains(a.tgt.connectURL[at:], ":") {
				a.gh.probeURL = a.tgt.connectURL
			}
		}
	}
	// Prime the probe caches here, like the scripts prime them in-shell: every later
	// use would otherwise repeat the round trip. Only where the answer is read: the
	// identity block names gh's account, and a write compares against it. A bare
	// 'pr' or 'pr <n>' prints neither.
	if a.gh.isCommand && (a.gh.isWrite || a.identityWillPrint()) {
		_ = a.forgeCLIWho()
	}
	if a.gh.isWrite {
		_ = a.sshLogin(a.gh.probeURL)
	}
	return nil
}

// identityMismatch is what the two identity gates found, and which of them found
// it. Empty text means they agree, or that one side couldn't say.
type identityMismatch struct {
	text  string
	viaGh bool
}

// forgeCLIWho names the account the CLI this run goes through acts as, or '?' when
// it cannot be told. Unknown is deliberately not a mismatch: a tea with no login for
// this host, or a gh that is offline, has said nothing about who you are, and
// refusing on that would refuse every unconfigured machine.
func (a *app) forgeCLIWho() string {
	switch a.gh.tool {
	case toolGh:
		return a.ghLogin()
	case toolTea:
		if who := a.forgeLogin(a.gh.cli, a.originHost()); who != "" {
			return who
		}
	}
	return "?"
}

// identityGate: a forge write acting as a different account than the key git pushes
// with is a wrong-account mistake waiting to happen, and it is outward-facing.
// Refuse it unattended (nobody is there to read a warning); warn interactively,
// right before the prompt. --any-identity means the difference is intended.
func (a *app) identityGate() (identityMismatch, error) {
	var found identityMismatch
	if a.gh.isWrite && !a.opt.anyIdentity {
		found.text = identityMismatchText(a.gh.cli, a.forgeCLIWho(), a.sshLogin(a.gh.probeURL))
		found.viaGh = found.text != ""
		// Up front, like every other refusal: don't show a plan we won't run.
		if found.text != "" && a.opt.quiet {
			return found, usagef("%s Nothing was done. Re-run with --any-identity if that is intended.", found.text)
		}
	}
	// The same question for the commands that push with git rather than write
	// through a forge CLI - 'sync' above all, which sends your work to a remote and
	// compared nothing at all. Asked of the account's login ON THIS HOST: 'ghAccount'
	// is a GitHub login and says nothing about who you are anywhere else, so keying
	// this on it alone left every non-GitHub account uncompared. Only for an account
	// that was CONFIGURED or asked for: one inferred from the remote's owner says
	// nothing about who you are, and would fire for every single-account user cloning
	// somebody else's repo.
	acctWho := a.accountWho(a.originHost())
	if !a.pushesToRemote() || a.opt.anyIdentity || found.text != "" ||
		acctWho == "" || (!a.acct.explicit && a.acct.name == "") {
		return found, nil
	}
	pushLogin := a.sshLogin(a.originURL())
	if pushLogin == "" || pushLogin == "?" || pushLogin == acctWho {
		return found, nil
	}
	found.text = "This folder's account is '" + acctWho + "', but origin's key authenticates as '" + pushLogin + "'."
	if a.opt.quiet {
		return found, usagef("%s Nothing was done. Re-run with --any-identity if that is intended.", found.text)
	}
	return found, nil
}

func (a *app) runReadOnly() error {
	var err error
	switch a.cmd.name {
	case "status":
		a.showStatus(true)
	case "whoami":
		a.cmdWhoami()
	case "account-list":
		a.cmdAccountList()
	case "repo-url":
		a.cmdRepoURLShow()
	case "br-list":
		a.cmdBrList()
	case "pr":
		err = a.cmdPrView()
	}
	if err != nil {
		return err
	}
	a.out.clean("")
	return nil
}

// runMutating is the frame every mutating command shares: show state and plan,
// confirm, execute, show state again.
func (a *app) runMutating(mismatch identityMismatch) error {
	if err := a.showBeforeState(); err != nil {
		return err
	}
	a.out.clean("")
	a.out.clean("Going to do (steps marked * only if needed, based on repo state):")
	a.preview(a.cmd.name)
	// Said once here, where you can still say no, and again by each step as it
	// skips. repo-* has no park push to skip - it probes its own remote and fails
	// on its own terms.
	if !strings.HasPrefix(a.cmd.name, "repo-") && a.isOffline() {
		a.out.clean("")
		a.out.clean("WARNING: remote unreachable - nothing will be pushed; the work stays local.")
	}
	// Last thing before the prompt, so it can't scroll away above the plan.
	if mismatch.text != "" {
		a.out.clean("")
		a.out.status("*** WRONG ACCOUNT? ***")
		a.out.clean("  " + mismatch.text)
		// Only where gh is the one acting: the other gate is about the key git pushes
		// with, on commands gh has nothing to do with - and it can reach here with no
		// gh at all to name.
		if mismatch.viaGh {
			a.out.clean("  gh does the GitHub side of this, so it happens as '" + a.ghLogin() + "'.")
		}
		a.out.clean("  Continue only if that is what you mean. (--any-identity silences this.)")
	}
	if !a.opt.quiet {
		a.out.clean("")
		if !a.out.confirm("Continue? (y|n): ") {
			a.out.status("User aborted.")
			a.out.clean("")
			return silentExit(1)
		}
	}
	if err := a.dispatch(); err != nil {
		return err
	}
	a.out.clean("")
	switch a.cmd.name {
	case "account-apply", "account-set":
		// every file it wrote was named as it was written; a repo status would add
		// nothing
	case "repo-clone":
		// the after-status would show the wrong (current) directory
		a.out.status("Cloned into '" + a.tgt.cloneDir + "'.")
	default:
		a.showStatus(false)
	}
	a.out.status("")
	a.out.status("Done.")
	a.out.clean("")
	return nil
}

// showBeforeState leads the plan with what the repo looks like now. clone, and
// create/connect from a plain dir, have no repo state to show; a smaller header
// stands in.
func (a *app) showBeforeState() error {
	switch {
	case a.cmd.name == "account-apply" || a.cmd.name == "account-set":
		// Nothing about a repo is involved: these write config files, and showing
		// branch state here would suggest they do something to the repo you happen
		// to be standing in.
		a.cmdAccountList()
	case a.cmd.name == "repo-clone":
		// As in the show printers: an unnameable cwd prints as empty.
		wd, _ := os.Getwd()
		a.out.clean("")
		a.out.clean(dirLabel + wd)
		a.out.clean("Remote .......: " + maskURL(a.tgt.cloneURL))
		a.showIdentity(a.tgt.cloneURL)
		a.out.clean("Clone into ...: " + a.tgt.cloneDir)
	case !a.inRepo:
		remoteDisp := a.tgt.connectURL
		if remoteDisp != "" {
			remoteDisp = maskURL(remoteDisp)
		} else {
			remoteDisp = "github.com/" + a.tgt.ghTarget + " (to be created)"
		}
		// As in the show printers: an unnameable cwd prints as empty.
		wd, _ := os.Getwd()
		a.out.clean("")
		a.out.clean(dirLabel + wd)
		a.out.clean("Remote .......: " + remoteDisp)
		a.showIdentity(a.tgt.connectURL)
		a.out.clean("Current branch: (not a git repository yet)")
		a.showFilesToPublish()
	default:
		if a.currentBranch() == "" {
			return usagef("Detached HEAD (no current branch); resolve that manually first.")
		}
		a.showStatus(true)
	}
	return nil
}

func (a *app) dispatch() error {
	switch a.cmd.name {
	case "pullcom":
		return a.cmdCommitPull()
	case "sync":
		return a.cmdPush()
	case "br-create":
		return a.cmdNewBranch(a.cmd.arg, a.mergeTarget())
	case "br-hotfix":
		return a.cmdNewBranch(a.cmd.arg, a.defaultBranch())
	case "br-switch":
		return a.cmdGoBranch(a.cmd.arg)
	case "br-merge":
		return a.cmdMerge()
	case "br-prune":
		return a.cmdPrune()
	case "pr":
		if a.pr.sub == "create" {
			return a.cmdPrCreate()
		}
		return a.cmdPrAccept()
	case "release":
		return a.cmdRelease()
	case "repo-clone":
		return a.cmdClone()
	case "repo-create", "repo-connect":
		return a.cmdConnect()
	case "repo-url":
		return a.cmdRepoURL()
	case "account-apply":
		return a.cmdAccountApply()
	case "account-set":
		return a.cmdAccountSet()
	}
	return nil
}

// cmdPassthrough runs the real tool as the account this folder belongs to, then
// gets out of its way entirely. No preview, no confirmation, no fetch: this is
// somebody else's command run under the right identity, and a script piping its
// output must get that output and nothing else.
func (a *app) cmdPassthrough(tool string, args []string) error {
	if err := mustBeInPath(tool); err != nil {
		return err
	}
	if err := a.resolveAccount(a.contextDir(), a.originURL()); err != nil {
		return err
	}
	if err := a.selectAccount(true); err != nil {
		return err
	}
	// One line, on stderr, so a pipeline reading stdout sees only the tool.
	// Silence is what '-q' is for.
	// The same test the identity block uses: a name inferred from the remote's owner
	// is not a claim that we act as them, and saying so tells a single-account user
	// about a feature they never asked for.
	if !a.opt.quiet && a.acct.ghWho != "" && a.accountDecidedSomething() {
		a.out.errorf("acting as %s (from %s)", a.acct.ghWho, a.accountSourceText(false))
	}
	return a.handover(tool, args)
}

func (a *app) cmdBrList() {
	dflt := a.defaultBranch()
	if dflt == "" {
		dflt = "unknown"
	}
	a.out.clean("")
	a.out.clean("Default branch: " + dflt)
	a.out.status("git branch -a -vv")
	a.inherit("git", "branch", "-a", "-vv")
	a.out.resetBlank()
}

// stampNow is the serial a quiet commit falls back to when it has no message and
// no editor.
func stampNow() string { return time.Now().Format("20060102-150405") }
