// The writing half: the commit/pull/push core that pullcom, sync and the branch
// commands compose their own recipes from, plus prune's executor. Every step
// re-asks the repo what state it is in, so a plan that sat at a prompt still
// skips whatever no longer applies.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"strconv"
	"strings"
)

func (a *app) cmdCommit() error {
	// Never stage a conflicted tree. 'git add --all' marks a conflicted file
	// resolved, so the markers themselves would be committed, and then pushed by
	// sync. Ordinary use reaches this: a pull whose autostash reapply conflicts
	// still exits 0, so nothing upstream of here notices.
	if conflicted := runLines("git", "diff", "--name-only", "--diff-filter=U"); len(conflicted) > 0 {
		a.out.clean("")
		a.out.status("Unresolved conflicts; nothing was committed:")
		a.showLines(conflicted)
		return usagef("Resolve those, then run '%s pullcom' again. Git also kept your pre-pull tree - see 'git stash list'.", meName)
	}
	if err := a.step("git", "add", "--all"); err != nil {
		return err
	}
	switch {
	case runOut("git", "status", "--porcelain") == "":
		a.out.status("Nothing to commit.")
		return nil
	case a.opt.message != "":
		return a.step("git", "commit", "-m", a.opt.message)
	case a.opt.quiet:
		return a.step("git", "commit", "-m", meName+" "+a.stamp) // quiet mode can't open an editor
	default:
		return a.step("git", "commit")
	}
}

func (a *app) cmdPull() error {
	// --autostash instead of a manual stash push/pop: a failed pull (diverged,
	// offline) leaves the tree intact instead of stranding work in the stash.
	// Skipping beats failing when the remote is simply out of reach: pullcom is the
	// only way to commit, so being offline must not turn a good commit into a
	// failed command. A reachable remote that can't fast-forward is a real problem
	// and still fails hard.
	switch {
	case !a.opt.fetch:
		a.out.status("Skipping the pull (--no-fetch).")
	case !a.gh.reachable:
		a.out.status("WARNING: remote unreachable; skipping the pull. Local changes still get committed.")
	case a.hasUpstream():
		return a.step("git", "pull", "--ff-only", "--autostash")
	default:
		a.out.status("No upstream configured for this branch; nothing to pull.")
	}
	return nil
}

// pullIfOnline is the pull inside a multi-step command. Same offline rule as
// cmdPull, quietly: --no-fetch and an unreachable remote both mean skip. Extra
// arguments go through to git pull.
func (a *app) pullIfOnline(extra ...string) error {
	if a.opt.fetch && a.gh.reachable && a.hasUpstream() {
		return a.step("git", append([]string{"pull", "--ff-only"}, extra...)...)
	}
	return nil
}

// pushIfOnline is the park push, for a command that still means something without
// it. The commands that exist to publish never get here - they are refused up
// front - so nothing reports success having sent nothing. Silence would read as
// published, hence the note, which names the branch: the command may move off it
// next (br switch, merge), and a 'sync' from wherever you end up would publish
// that branch, not this one.
func (a *app) pushIfOnline() error {
	if !a.hasOrigin() {
		a.out.status("No 'origin' remote; nothing to push.")
		return nil
	}
	switch {
	case a.hasUpstream() && !isAhead():
		// True offline too: nothing local is ahead of the last-known origin.
		a.out.status("Nothing to push.")
	case a.isOffline():
		a.out.status("WARNING: remote unreachable; skipping the push. The work stays local on '" + a.currentBranch() + "' - '" + meName + " sync' from it publishes it.")
	case !a.hasUpstream():
		return a.step("git", "push", "-u", "origin", "HEAD") // first publish of this branch
	default:
		return a.step("git", "push")
	}
	return nil
}

// pushesToRemote: whether this command sends anything to origin. The identity
// comparison keyed off it costs a live ssh probe and refuses the run outright, so
// it must not fire for a command whose whole job is local - a mismatched key has
// nothing to do with a commit that never leaves the machine. Named by exception,
// so a mutating command added later is covered until it says otherwise.
func (a *app) pushesToRemote() bool {
	switch a.cmd.name {
	case "pullcom", "repo-clone", "repo-url", "account-apply", "account-set":
		return false
	}
	return a.cmd.mutating
}

// requireOnline: cmd as typed, and what to do instead.
func (a *app) requireOnline(cmd, instead string) error {
	if a.isOffline() {
		return usagef("Can't reach origin, and '%s' has nothing left to do without it. %s", cmd, instead)
	}
	return nil
}

// publishBranch is a new branch's own first push, which is separate from the park
// push above it.
func (a *app) publishBranch(branch string) error {
	if !a.hasOrigin() {
		return nil
	}
	if a.isOffline() {
		a.out.status("WARNING: remote unreachable; '" + branch + "' is local only for now - '" + meName + " sync' publishes it.")
		return nil
	}
	return a.step("git", "push", "-u", "origin", branch)
}

// cmdCommitPull pulls BEFORE committing. Committing first mints a local commit,
// so a remote that merely moved ahead is now diverged and --ff-only refuses -
// which is the everyday case, not an edge one. Pulling first fast-forwards (the
// dirty tree rides over on --autostash) and the commit lands on top, so history
// stays linear and --ff-only stays satisfiable.
func (a *app) cmdCommitPull() error {
	if err := a.cmdPull(); err != nil {
		return err
	}
	return a.cmdCommit()
}

func (a *app) cmdPush() error {
	if err := a.cmdCommitPull(); err != nil {
		return err
	}
	return a.pushIfOnline()
}

// cmdPrune deletes exactly what the plan listed - resolvePrune did all the
// deciding, up front.
func (a *app) cmdPrune() error {
	doneLocal, doneRemote := 0, 0
	heldBack := map[string]bool{}
	// -D with our own gate, not -d. 'git branch -d' asks whether the branch is contained in
	// its upstream, or in HEAD when it has none - neither of which is the question here, and
	// the second one refuses a genuinely-merged local-only branch from any other branch.
	// Re-checked right now rather than trusting the plan - the prompt may have sat a while -
	// but surveyed the way resolvePrune surveys: one 'for-each-ref --merged' per target ref
	// answers containment for every branch at once, instead of a merge-base fork per branch.
	// A branch deleted since the plan drops out of the survey, which reads as not-contained
	// and holds it (and its remote copy) back, same as the per-branch ask did.
	stillMerged := map[string]bool{}
	unconfirmed := func() bool {
		for _, branch := range a.prune.local {
			if !stillMerged[branch] {
				return true
			}
		}
		return false
	}
	for _, ref := range a.prune.targetRefs {
		// Later refs are asked only while a candidate is still unconfirmed, so the
		// common case - everything merged through the first ref - costs one call.
		if !unconfirmed() {
			break
		}
		for _, branch := range runLines("git", "for-each-ref", "--format=%(refname:short)", "--merged", ref, "refs/heads/") {
			stillMerged[branch] = true
		}
	}
	var deleteLocal []string
	for _, branch := range a.prune.local {
		if !stillMerged[branch] {
			a.out.status("'" + branch + "' is no longer contained in " + a.mergeTarget() + "; leaving it alone.")
			heldBack[branch] = true
			continue
		}
		deleteLocal = append(deleteLocal, branch)
	}
	// One call, not one per branch. Each fork of git costs a process and takes its own
	// helpers with it, and this is the command most likely to be handed eight branches at
	// once - which was two thirds of everything it spawned.
	if len(deleteLocal) > 0 {
		a.out.clean("")
		a.out.status("git branch -D " + strings.Join(deleteLocal, " ") + " ...")
		// Non-fatal, the same way the remote half below is. git deletes the branches it
		// can and exits nonzero for the rest - one checked out in another worktree, most
		// often - and returning that ended the run with those deletions already done,
		// origin untouched, and no count printed at all.
		if a.inheritOK("git", append([]string{"branch", "-D"}, deleteLocal...)...) {
			doneLocal = len(deleteLocal)
		} else {
			var stillHere []string
			for _, branch := range deleteLocal {
				if branchExistsLocal(branch) {
					stillHere = append(stillHere, branch)
					// Its remote copy stays too: deleting that would leave a branch here
					// with nothing on origin behind it.
					heldBack[branch] = true
				} else {
					doneLocal++
				}
			}
			if len(stillHere) > 0 {
				a.out.status("WARNING: couldn't delete " + strings.Join(stillHere, ", ") + " here (checked out in another worktree?); continuing.")
			}
		}
		a.out.resetBlank()
	}
	var deleteRemote []string
	for _, branch := range a.prune.remote {
		// "Leaving it alone" has to mean the remote copy too, or the message is a lie.
		if !heldBack[branch] {
			deleteRemote = append(deleteRemote, branch)
		}
	}
	if len(deleteRemote) > 0 && a.isOffline() {
		// Same rule br merge keeps: nothing goes out while origin is unreachable. The push
		// would fail and be reported as "already gone", blaming the branch for a network
		// problem, and the count at the end would read as if it had finished.
		a.out.status("WARNING: remote unreachable; left origin's copies of " + strings.Join(deleteRemote, ", ") + " alone - '" + meName + " br prune' again once online.")
		deleteRemote = nil
	}
	if len(deleteRemote) > 0 {
		// Non-fatal, same as br merge: someone else may have deleted one already.
		a.out.clean("")
		a.out.status("git push origin --delete " + strings.Join(deleteRemote, " ") + " ...")
		if a.inheritOK("git", append([]string{"push", "origin", "--delete"}, deleteRemote...)...) {
			doneRemote = len(deleteRemote)
		} else {
			// One refspec failing does not stop the others, so count what actually went
			// rather than writing the whole batch off. A delete that succeeded takes the
			// remote-tracking ref with it, which is a local lookup.
			var stillThere []string
			for _, branch := range deleteRemote {
				if branchExistsRemote(branch) {
					stillThere = append(stillThere, branch)
				} else {
					doneRemote++
				}
			}
			if len(stillThere) > 0 {
				a.out.status("WARNING: couldn't delete " + strings.Join(stillThere, ", ") + " on origin (already gone?); continuing.")
			}
		}
		a.out.resetBlank()
	}
	// Close with the count, so a wall of git output still ends in a plain answer.
	a.out.clean("")
	a.out.status("Pruned " + strconv.Itoa(doneLocal) + " local, " + strconv.Itoa(doneRemote) + " on origin.")
	if a.prune.currentMerged != "" {
		a.out.status("Kept '" + a.prune.currentMerged + "' - merged, but it's the current branch.")
	}
	if len(a.prune.keep) > 0 {
		a.out.status("Kept " + strings.Join(a.prune.keep, ", ") + " - not merged into " + a.mergeTarget() + " yet.")
	}
	return nil
}
