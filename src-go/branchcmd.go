// The branch writers: create, hotfix, switch and merge. Every one of them parks
// whatever is in the tree before it moves, so changing where you stand can't
// strand work - and merge carries a hotfix on to dev, because the next release
// would otherwise undo it.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

// Where the code that becomes a release asset lives. The release builds every
// binary from here, so a hotfix that touches it is the kind the warning below is
// about; documentation is not. It was 'bin/' when the deliverable was a script,
// and went on watching a folder that no longer existed.
//
// ':(top)' anchors it at the repo root. A bare path is read relative to the
// current directory, so run from anywhere but the top the pathspec matched
// nothing, git exited 0 with no output, and the warning silently never fired.
const shippedCodeDir = ":(top)src-go/"

// checkNewBranchName vets the name given to br create/hotfix. Git owns the rules
// for what a ref may be called, so ask git rather than keep a second copy of them.
func checkNewBranchName(name string) error {
	if !runOK("git", "check-ref-format", "--branch", name) {
		return usagef("'%s' is not a valid branch name.", name)
	}
	if branchExistsLocal(name) {
		return usagef("Branch '%s' already exists; use: %s br switch %s", name, meName, name)
	}
	if branchExistsRemote(name) {
		return usagef("Branch '%s' already exists on origin; use: %s br switch %s", name, meName, name)
	}
	return nil
}

// cmdNewBranch is both 'br create' and 'br hotfix' - one recipe, different base.
// A hotfix comes off the default branch because it corrects what is already
// published; feature work still goes through dev. Branch-name validation already
// happened up front in main.
func (a *app) cmdNewBranch(newBranch, baseBranch string) error {
	if a.isProtectedBranch("") {
		// Don't commit WIP to main/dev; a dirty tree survives checkout -b, so carry it
		// to the new branch.
		if a.currentBranch() != baseBranch {
			if err := a.checkout(baseBranch); err != nil {
				return err
			}
		}
		if err := a.pullIfOnline("--autostash"); err != nil {
			return err
		}
	} else {
		if err := a.cmdPush(); err != nil { // park current work safely first
			return err
		}
		if err := a.checkout(baseBranch); err != nil {
			return err
		}
		if err := a.pullIfOnline(); err != nil {
			return err
		}
	}
	if err := a.step("git", "checkout", "-b", newBranch); err != nil {
		return err
	}
	return a.publishBranch(newBranch)
}

func (a *app) cmdGoBranch(targetBranch string) error {
	if targetBranch == "" {
		targetBranch = a.mergeTarget()
	}
	if a.currentBranch() == targetBranch {
		a.out.status("Already on '" + targetBranch + "'.")
		return a.pullIfOnline()
	}
	// The dirty-protected-branch refusal happens up front in main, before the plan
	// is shown.
	if err := a.cmdPush(); err != nil { // park current work safely first
		return err
	}
	if err := a.checkout(targetBranch); err != nil {
		return err
	}
	return a.pullIfOnline()
}

// cmdMerge merges the current branch into dev (or main/master) - backwards from
// 'git merge', but it saves a step.
func (a *app) cmdMerge() error {
	workBranch := a.currentBranch()
	targetBranch := a.branchTarget(workBranch)
	if workBranch == targetBranch {
		return usagef("Already on '%s'. Run this from the branch to merge in: %s br switch <branch>, then %s br merge", targetBranch, meName, meName)
	}
	if workBranch == a.defaultBranch() {
		return usagef("'%s' is the default branch; landing it on '%s' is backwards. To cut a release: %s release", workBranch, targetBranch, meName)
	}
	mergeMessage := a.opt.message
	if mergeMessage == "" {
		mergeMessage = "Merge " + workBranch
	}
	wasHotfix := a.isHotfixBranch(workBranch)
	if err := a.cmdPush(); err != nil {
		return err
	}
	// After the push, not before: the warning reads the branch tip, and uncommitted
	// work only becomes part of it here. Checking first missed a hotfix whose
	// shipped-code edit was still in the working tree - the ordinary way of doing one.
	if wasHotfix {
		a.warnHotfixTouchedCode(workBranch, targetBranch)
	}
	if err := a.checkout(targetBranch); err != nil {
		return err
	}
	if err := a.pullIfOnline(); err != nil {
		return err
	}
	if err := a.step("git", "merge", "--no-ff", workBranch, "-m", mergeMessage); err != nil {
		return err
	}
	// The merge must reach origin before the remote work branch goes away, or origin
	// loses its only ref to those commits. Publish an upstream-less target first.
	mergePublished := false
	switch {
	case !a.hasOrigin():
	case a.isOffline():
		// A hotfix ends on dev after the back-merge, so a bare 'sync' from there would
		// publish dev and leave the default branch - the branch the hotfix exists to fix
		// - stale on origin. The switch's park push publishes dev on the way, so two
		// commands cover both.
		if wasHotfix {
			a.out.status("WARNING: remote unreachable; the merge to '" + targetBranch + "' is local only - once online, '" + meName + " br switch " + targetBranch + "' then '" + meName + " sync' publishes it.")
		} else {
			a.out.status("WARNING: remote unreachable; the merge to '" + targetBranch + "' is local only - '" + meName + " sync' publishes it.")
		}
	default:
		push := []string{"push"}
		if !a.hasUpstream() {
			push = []string{"push", "-u", "origin", "HEAD"}
		}
		if err := a.step("git", push...); err != nil {
			return err
		}
		mergePublished = true
	}
	if err := a.step("git", "branch", "-d", workBranch); err != nil {
		return err
	}
	if branchExistsRemote(workBranch) {
		if !mergePublished {
			// The same rule as above, from the other side: with the merge still
			// unpublished, origin's copy of the branch is its only ref to those commits.
			a.out.status("Leaving origin's '" + workBranch + "' alone until the merge is pushed; '" + meName + " br prune' clears it later.")
		} else {
			// Non-fatal: someone (a PR merge, another clone) may have deleted it already.
			a.out.clean("")
			a.out.status("git push origin --delete " + workBranch + " ...")
			if !a.inheritOK("git", "push", "origin", "--delete", workBranch) {
				a.out.status("WARNING: couldn't delete the remote branch (already gone?); continuing.")
			}
			a.out.resetBlank()
		}
	}
	if err := a.pullIfOnline(); err != nil {
		return err
	}
	// The hotfix now has to reach dev too, or the next release undoes it.
	if wasHotfix {
		return a.backMergeToDev()
	}
	return nil
}

// backMergeRef is what the back-merge actually merges. 'pr ok' lands the hotfix on
// the server, so the LOCAL default branch never sees it and merging that is a
// silent no-op; the fetched remote-tracking ref is the one holding it. After 'br
// merge' the two are the same commit, so this is right either way - and it falls
// back to the local branch when there's no remote at all. Offline flips it back:
// merge's push was skipped, so origin's copy is the stale one, and merging it would
// carry the hotfix nowhere. ('pr ok' can't run offline at all.)
func (a *app) backMergeRef() string {
	mainBranch := a.defaultBranch()
	if !a.isOffline() && runOK("git", "rev-parse", "--verify", "--quiet", "refs/remotes/origin/"+mainBranch) {
		return "origin/" + mainBranch
	}
	return mainBranch
}

// backMergeToDev: after a hotfix lands on the default branch, dev has to receive
// it. Skipping this is how the next release conflicts on the same file, or quietly
// reinstates the text the hotfix replaced. A conflict here is raw-git territory:
// abort so the tree is left clean, and say so plainly.
func (a *app) backMergeToDev() error {
	mainBranch := a.defaultBranch()
	devBranch := a.mergeTarget()
	if devBranch == mainBranch { // no dev in this repo: nothing to carry back
		return nil
	}
	if !branchExistsLocal(devBranch) && !branchExistsRemote(devBranch) {
		return nil
	}
	mergeRef := a.backMergeRef()
	a.out.clean("")
	if err := a.checkout(devBranch); err != nil {
		return err
	}
	if err := a.pullIfOnline(); err != nil {
		return err
	}
	a.out.status("git merge " + mergeRef + " ...")
	if a.inheritOK("git", "merge", mergeRef, "-m", "Merge "+mainBranch) {
		a.out.resetBlank()
		return a.pushIfOnline()
	}
	_ = runOK("git", "merge", "--abort")
	a.out.resetBlank()
	a.out.status("WARNING: '" + mainBranch + "' would not merge cleanly into '" + devBranch + "'; left '" + devBranch + "' untouched.")
	a.out.clean("  The hotfix landed on '" + mainBranch + "' - that part is done.")
	a.out.clean("  Carry it across by hand: git checkout " + devBranch + " && git merge " + mergeRef)
	return nil
}

// warnHotfixTouchedCode: a hotfix that changes shipped code leaves the default
// branch carrying something no tag contains, so the latest release's assets stop
// matching it. Documentation does not.
func (a *app) warnHotfixTouchedCode(workBranch, targetBranch string) {
	if runOut("git", "diff", "--name-only", targetBranch+"..."+workBranch, "--", shippedCodeDir) == "" {
		return
	}
	a.out.clean("")
	a.out.status("NOTE: this hotfix changes shipped code, not just documentation.")
	a.out.clean("  '" + targetBranch + "' will carry code that no tag contains, so the latest release's")
	a.out.clean("  downloads no longer match it. Cut a patch release when you're ready: " + meName + " release")
}
