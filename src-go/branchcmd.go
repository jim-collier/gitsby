// The branch writers: create, hotfix, switch and merge. Every one of them parks
// whatever is in the tree before it moves, so changing where you stand can't
// strand work - and merge carries a hotfix on to dev, because the next release
// would otherwise undo it.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"runtime"
	"strings"
)

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
	// By full ref: git merge reads a tag of the same name ahead of the branch, and the
	// remote delete below is leased on the branch's tip.
	if err := a.step("git", "merge", "--no-ff", "refs/heads/"+workBranch, "-m", mergeMessage); err != nil {
		return a.backOutMerge(err, workBranch, targetBranch, workBranch,
			"git merge "+targetBranch+", then '"+meName+" br merge'")
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
	// Read before the local delete: whether origin has a copy, and the tip that was
	// merged, which is all origin's copy may hold when it goes.
	mergedTip, tracked := "", false
	for _, line := range runLines("git", "for-each-ref", "--format=%(objectname) %(refname)", "refs/heads/"+workBranch, "refs/remotes/origin/"+workBranch) {
		object, ref, _ := strings.Cut(line, " ")
		switch ref {
		case "refs/heads/" + workBranch:
			mergedTip = object
		case "refs/remotes/origin/" + workBranch:
			tracked = true
		}
	}
	if tracked && !mergePublished {
		// The same rule as above, from the other side: with the merge still
		// unpublished, origin's copy of the branch is its only ref to those commits.
		// The branch stays here too, since br prune looks for what to clear among
		// local branches.
		a.out.status("Leaving origin's '" + workBranch + "' alone until the merge is pushed, and the branch here with it; '" + meName + " br prune' deletes both after that.")
	} else {
		if err := a.step("git", "branch", "-d", workBranch); err != nil {
			return err
		}
		if tracked {
			a.mergeDeleteRemote(workBranch, mergedTip)
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

// mergeDeleteRemote deletes origin's copy of the branch br merge just merged, the
// way br prune does. With --no-fetch the pull before the merge is skipped, and
// anyone can push while the prompt waits, so origin may hold commits the merge
// doesn't have. It is asked first, and the delete is leased on the merged tip.
func (a *app) mergeDeleteRemote(branch, mergedTip string) {
	tested := map[string]string{branch: mergedTip}
	onOrigin, asked := a.askOriginHeads()
	if !asked {
		a.out.status("WARNING: couldn't ask origin about its '" + branch + "'; left it alone.")
		a.out.clean("  Once origin can be reached, this deletes it. It stops if that branch has moved:")
		a.out.clean(pad + leaseDeleteLine(branch, mergedTip, runtime.GOOS))
		return
	}
	send, changed, gone := sortRemoteDeletes([]string{branch}, tested, onOrigin)
	switch {
	case len(gone) > 0:
		a.out.status("Already gone from origin: " + branch + ".")
	case len(changed) > 0:
		fetch := ""
		if !a.opt.fetch {
			fetch = " without --no-fetch"
		}
		a.out.status("WARNING: origin's '" + branch + "' has commits this merge doesn't; left it alone - '" + meName + " br switch " + typedArg(branch, runtime.GOOS) + "'" + fetch + ", then '" + meName + " br merge', brings them in.")
	case len(send) > 0:
		a.out.clean("")
		a.out.status("git push --force-with-lease origin --delete " + branch + " ...")
		// Non-fatal: the lease can still refuse, if the branch moved after the ask.
		if !a.inheritOK("git", leaseDeleteBatches(send, tested, leasePushBudget)[0]...) {
			a.out.status("WARNING: couldn't delete origin's '" + branch + "'; left it alone.")
		}
		a.out.resetBlank()
	}
}

// backOutMerge answers a merge step that failed. One stopped by conflicts is
// aborted, so the tree isn't left mid-merge, and the run goes back to where it
// started. Settling the conflict is raw git's, so the refusal names the commands.
// Any other failure is returned as it came.
func (a *app) backOutMerge(stepErr error, from, into, returnTo, settle string) error {
	if !runOK("git", "rev-parse", "-q", "--verify", "MERGE_HEAD") {
		return stepErr
	}
	_ = runOK("git", "merge", "--abort")
	a.out.resetBlank()
	a.out.status("Backed out: '" + from + "' would not merge cleanly into '" + into + "', which is as it was.")
	if returnTo != "" && returnTo != a.currentBranch() {
		if err := a.checkout(returnTo); err != nil {
			return err
		}
	}
	return usagef("Stopped with nothing merged. Settle the conflict by hand, then run it again: %s", settle)
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
	// By full ref, so a tag of the same name isn't merged in its place.
	fullRef := "refs/heads/" + mergeRef
	if remote, ok := strings.CutPrefix(mergeRef, "origin/"); ok {
		fullRef = "refs/remotes/origin/" + remote
	}
	if a.inheritOK("git", "merge", fullRef, "-m", "Merge "+mainBranch) {
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
