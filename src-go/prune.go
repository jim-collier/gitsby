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
	remoteTip     map[string]string
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
	mergedRemote := map[string]string{}
	if haveTargetRemote {
		mergedRemote = originTips(runLines("git", "for-each-ref", "--format=%(objectname) %(refname)", "--merged", targetRemoteRef, "refs/remotes/origin/"))
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
		// says the remote branch is there - no second ref lookup per branch. The
		// value it tested is kept, since that is what origin must still hold when the
		// delete goes out.
		if tip, ok := mergedRemote[branch]; ok {
			if a.prune.remoteTip == nil {
				a.prune.remoteTip = map[string]string{}
			}
			a.prune.remote = append(a.prune.remote, branch)
			a.prune.remoteTip[branch] = tip
		}
	}
	return nil
}

// originTips reads the remote survey's '<object> <ref>' lines into branch name ->
// the object that was tested. Full ref names rather than :short, which git
// qualifies differently when a name is ambiguous. A ref name cannot hold a space.
func originTips(lines []string) map[string]string {
	tips := make(map[string]string, len(lines))
	for _, line := range lines {
		object, ref, ok := strings.Cut(line, " ")
		if !ok || object == "" {
			continue
		}
		if branch, found := strings.CutPrefix(ref, "refs/remotes/origin/"); found && branch != "" {
			tips[branch] = object
		}
	}
	return tips
}

// parseOriginHeads reads 'git ls-remote' output into full ref name -> object,
// branches only. Callers look up the exact name: a pattern answer can be any ref
// that merely ends in the one asked for.
func parseOriginHeads(out string) map[string]string {
	heads := map[string]string{}
	for _, line := range splitLines(out) {
		object, ref, ok := strings.Cut(line, "\t")
		if !ok || object == "" || !strings.HasPrefix(ref, "refs/heads/") {
			continue
		}
		heads[ref] = object
	}
	return heads
}

// sortRemoteDeletes splits the remote candidates by what origin said just now:
// still at the value the survey tested, moved since, or no longer there. One with
// no tested value counts as moved, which leaves it alone.
func sortRemoteDeletes(branches []string, tested, onOrigin map[string]string) (send, changed, gone []string) {
	for _, branch := range branches {
		now, there := onOrigin["refs/heads/"+branch]
		was, known := tested[branch]
		switch {
		case !there:
			gone = append(gone, branch)
		case !known || now != was:
			changed = append(changed, branch)
		default:
			send = append(send, branch)
		}
	}
	return send, changed, gone
}

// Half of Windows' 32767-character command line. A delete push too long to start
// would come after the local deletes, and prune never lists those branches again.
const leasePushBudget = 16384

// leaseDeleteBatches builds the argument list of each delete push. Every branch is
// leased on the value that was tested, spelled out: a bare --force-with-lease reads
// the tracking ref and follows push.useForceIfIncludes, which refuses a delete once
// the local branch is gone. A batch closes before the next branch would take its
// arguments past budget; a branch too long for any budget still goes, alone.
func leaseDeleteBatches(branches []string, tested map[string]string, budget int) [][]string {
	const fixedLen = len("push") + len("origin") + len("--delete") + 3
	var batches [][]string
	var group []string
	size := fixedLen
	flush := func() {
		if len(group) == 0 {
			return
		}
		args := make([]string, 0, 2*len(group)+3)
		args = append(args, "push")
		for _, branch := range group {
			args = append(args, leaseArg(branch, tested[branch]))
		}
		args = append(args, "origin", "--delete")
		batches = append(batches, append(args, group...))
		group, size = nil, fixedLen
	}
	for _, branch := range branches {
		cost := len(leaseArg(branch, tested[branch])) + 1 + len(branch) + 1
		if len(group) > 0 && size+cost > budget {
			flush()
		}
		group = append(group, branch)
		size += cost
	}
	flush()
	return batches
}

// leaseArg: a ref name cannot hold ':', so git splits this one correctly.
func leaseArg(branch, object string) string {
	return "--force-with-lease=refs/heads/" + branch + ":" + object
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
	// The lease values are left out, and so is a split of a push too long for one
	// command line: neither changes what happens.
	if len(a.prune.local) > 0 {
		a.out.clean(pad + "git branch -D " + strings.Join(a.prune.local, " "))
	}
	if len(a.prune.remote) > 0 {
		a.out.clean(pad + "git push --force-with-lease origin --delete " + strings.Join(a.prune.remote, " "))
	}
	if a.prune.currentMerged != "" {
		a.out.clean(pad + "Keeping '" + a.prune.currentMerged + "' - merged, but it's the current branch.")
	}
	if len(a.prune.keep) > 0 {
		a.out.clean(pad + "Keeping (not merged yet): " + strings.Join(a.prune.keep, ", "))
	}
}
