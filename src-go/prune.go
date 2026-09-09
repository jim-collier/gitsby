// br prune's survey and plan. All read-only: the survey decides, the plan shows
// every branch by name, and the deleting half lands with the other writers.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import "strings"

// prunePlan is what the survey decided, settled before anything is shown so the
// plan can name every branch.
type prunePlan struct {
	targetRefs    []string
	local         []string
	remote        []string
	keep          []string
	currentMerged string
}

func (p prunePlan) empty() bool { return len(p.local) == 0 && len(p.remote) == 0 }

// resolvePrune sorts local branches into what's already landed and what isn't.
// Ancestry is an exact test here only because gitsby always lands with a real
// merge commit - a squash- or rebase-landed branch never looks contained, and is
// kept rather than guessed at.
func (a *app) resolvePrune() error {
	target := a.mergeTarget()
	targetRemoteRef := "refs/remotes/origin/" + target
	if branchExistsLocal(target) {
		a.prune.targetRefs = append(a.prune.targetRefs, "refs/heads/"+target)
	}
	haveTargetRemote := branchExistsRemote(target)
	if haveTargetRemote {
		a.prune.targetRefs = append(a.prune.targetRefs, targetRemoteRef)
	}
	current := a.currentBranch()
	// Ask once per target ref, not once per branch: 'for-each-ref --merged' answers
	// "which branches are contained in this ref" for all of them in a single call.
	// The delete-time per-branch re-check stays with the deleting half, deliberately:
	// the confirmation prompt can sit a while, and that one is the safety net rather
	// than the survey.
	mergedLocal := map[string]bool{}
	for _, ref := range a.prune.targetRefs {
		for _, branch := range runLines("git", "for-each-ref", "--format=%(refname:short)", "--merged", ref, "refs/heads/") {
			mergedLocal[branch] = true
		}
	}
	mergedRemote := map[string]bool{}
	if haveTargetRemote {
		for _, branch := range runLines("git", "for-each-ref", "--format=%(refname:short)", "--merged", targetRemoteRef, "refs/remotes/origin/") {
			mergedRemote[branch] = true
		}
	}
	for _, branch := range runLines("git", "for-each-ref", "--format=%(refname:short)", "refs/heads/") {
		// The branch we're standing on can't be deleted, and protected ones never are.
		// But if it WOULD have qualified, say so - otherwise it just vanishes from
		// every list.
		if branch == current {
			if !a.isProtectedBranch(branch) && mergedLocal[branch] {
				a.prune.currentMerged = branch
			}
			continue
		}
		if a.isProtectedBranch(branch) {
			continue
		}
		if !mergedLocal[branch] {
			a.prune.keep = append(a.prune.keep, branch)
			continue
		}
		// 'git branch -D' would read a dash-led name as options. Only the ones we are
		// about to hand git: a kept branch is printed and nothing more.
		if err := refuseOptionShapedRefs(branch); err != nil {
			return err
		}
		a.prune.local = append(a.prune.local, branch)
		// The remote copy goes only when origin has the merge too: a landing that
		// hasn't been pushed yet leaves origin holding the only ref to that work.
		// The map was built by listing refs/remotes/origin, so being in it already
		// says the remote branch is there - no second ref lookup per branch.
		if mergedRemote["origin/"+branch] {
			a.prune.remote = append(a.prune.remote, branch)
		}
	}
	return nil
}

// pruneNothingToDo says WHY the plan is empty - "no branch is merged" would be a
// lie when the merged one is the branch we're standing on.
func (a *app) pruneNothingToDo() {
	if a.prune.currentMerged != "" {
		a.out.status("Nothing to prune from here.")
		a.out.clean("  Current branch '" + a.prune.currentMerged + "' is merged, but you're on it; switch off it to prune it.")
	} else {
		a.out.status("Nothing to prune; no branch is fully merged into '" + a.mergeTarget() + "' yet.")
	}
	if len(a.prune.keep) > 0 {
		a.out.clean("  Keeping (not merged yet): " + strings.Join(a.prune.keep, ", "))
	}
	a.out.clean("")
}

// prunePreview is br prune's slice of the plan display.
func (a *app) prunePreview() {
	// -D is what runs, so -D is what the plan says. The line above it is the reason
	// that's safe: gitsby checks containment itself, against the branch that matters.
	a.out.clean(pad + "(each verified contained in " + a.mergeTarget() + ", and re-checked at delete time)")
	// One line per call, and there is one call - which is what the command runs.
	if len(a.prune.local) > 0 {
		a.out.clean(pad + "git branch -D " + strings.Join(a.prune.local, " "))
	}
	if len(a.prune.remote) > 0 {
		a.out.clean(pad + "git push origin --delete " + strings.Join(a.prune.remote, " "))
	}
	if a.prune.currentMerged != "" {
		a.out.clean(pad + "Keeping '" + a.prune.currentMerged + "' - merged, but it's the current branch.")
	}
	if len(a.prune.keep) > 0 {
		a.out.clean(pad + "Keeping (not merged yet): " + strings.Join(a.prune.keep, ", "))
	}
}
