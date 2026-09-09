// The plan display. A static per-command recipe; the command functions do the
// real state checks at run time, which is what the '*' marks. 'commit' and 'pull'
// are not commands of their own - they stay here as the fragments the real ones
// compose their plans from.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"strconv"
)

const pad = "    "

func (a *app) preview(what string) {
	switch what {
	case "commit":
		msgDisp := "git commit"
		if a.opt.message != "" {
			msgDisp = `git commit -m "` + a.opt.message + `"`
		}
		a.out.clean(pad + "git add --all")
		a.out.clean(pad + msgDisp + " *")
	case "pull":
		a.out.clean(pad + "git pull --ff-only --autostash *")
	case "pullcom":
		a.preview("pull")
		a.preview("commit")
	case "sync":
		a.preview("pullcom")
		a.out.clean(pad + "git push (branch '" + a.currentBranch() + "') *")
	case "br-create":
		// From main/dev the dirty tree rides along to the new branch, so there's no
		// commit here.
		a.previewNewBranch(a.mergeTarget())
	case "br-hotfix":
		// Off the default branch, not dev: this corrects what is already published.
		a.previewNewBranch(a.defaultBranch())
	case "br-switch":
		// Already on the target: nothing is parked and no checkout happens, so the plan
		// must not promise an add/commit/push it will not do.
		target := a.cmd.arg
		if target == "" {
			target = a.mergeTarget()
		}
		if a.currentBranch() != target {
			a.preview("sync")
			a.out.clean(pad + a.checkoutDisp(target))
		}
		a.out.clean(pad + "git pull --ff-only *")
	case "br-merge":
		a.preview("sync")
		a.out.clean(pad + a.checkoutDisp(a.branchTarget("")))
		a.out.clean(pad + "git pull --ff-only *")
		a.out.clean(pad + "git merge --no-ff " + a.currentBranch())
		a.out.clean(pad + "git push *")
		a.out.clean(pad + "git branch -d " + a.currentBranch())
		a.out.clean(pad + "git push origin --delete " + a.currentBranch() + " *")
		a.out.clean(pad + "git pull --ff-only *")
		// A hotfix owes dev the same change, or the next release undoes it.
		if a.isHotfixBranch("") {
			a.previewBackMerge()
		}
	case "br-prune":
		a.prunePreview()
	case "pr":
		a.previewPr()
	case "release":
		a.previewRelease()
	case "repo-clone":
		a.out.clean(pad + "git clone " + maskURL(a.tgt.cloneURL) + " " + a.tgt.cloneDir)
		a.out.clean(pad + "git -C " + a.tgt.cloneDir + " checkout dev *")
	case "repo-url":
		a.out.clean(pad + "git remote set-url origin " + githubURL(remoteTarget(a.originURL()), a.cmd.arg))
	case "account-set":
		// Names the file and both versions of the line, because this is the one
		// command that edits the accounts file for you - and a config file you did
		// not type yourself is only trustworthy if it showed you the edit first.
		t, err := a.accountSetPlan()
		if err != nil {
			// Nothing here can refuse - the plan is display. Whatever is wrong with
			// the arguments is reported by the command itself, a moment later.
			a.out.clean(pad + "(nothing: " + err.Error() + ")")
			return
		}
		switch {
		case t.creates:
			a.out.clean(pad + "create " + displayPath(t.file))
		case t.converts:
			// The whole file changes shape, so no line number: the one it has now
			// is not the one the key ends up on.
			a.out.clean(pad + "rewrite " + displayPath(t.file) + " in the current layout - it is in the old flat one")
		case t.lineNum > 0:
			a.out.clean(pad + "edit " + displayPath(t.file) + ", line " + strconv.Itoa(t.lineNum))
		default:
			a.out.clean(pad + "edit " + displayPath(t.file))
		}
		if t.exists {
			a.out.clean(pad + "  was:     " + t.field + ": " + t.old)
			a.out.clean(pad + "  becomes: " + t.field + ": " + shclValue(t.value))
		} else {
			a.out.clean(pad + "  add:     " + t.disp + "." + t.field + ": " + shclValue(t.value))
		}
	case "account-apply":
		// Names every file and every condition, because this is the one command
		// that writes outside the repo you are standing in - into your own global
		// git config.
		applyDir := a.cfg.includeDir()
		for _, name := range a.cfg.accountNames() {
			a.out.clean(pad + "write " + applyDir + "/" + name + ".gitconfig")
		}
		for _, key := range a.cfg.accountManagedIncludes() {
			a.out.clean(pad + "git config --global --unset-all " + key)
		}
		for _, rule := range a.cfg.accountApplyPlan() {
			a.out.clean(pad + "git config --global --add " + rule.cond + " " + rule.target)
		}
	case "repo-create", "repo-connect":
		if !a.inRepo {
			a.out.clean(pad + "git init -b main")
		}
		a.preview("commit")
		switch a.tgt.connectMode {
		case "create":
			a.out.clean(pad + "gh repo create " + a.tgt.ghTarget + " --" + a.opt.visibility + " --source . --push --remote origin")
		case "add":
			a.out.clean(pad + "git remote add origin " + maskURL(a.tgt.connectURL))
			a.out.clean(pad + "git push -u origin HEAD")
		case "push":
			a.out.clean(pad + "git push -u origin HEAD *")
		}
	}
}

// previewNewBranch is br create and br hotfix - the same recipe off a different
// base.
func (a *app) previewNewBranch(baseBranch string) {
	if a.isProtectedBranch("") {
		a.out.clean(pad + a.checkoutDisp(baseBranch) + " *")
		a.out.clean(pad + "git pull --ff-only --autostash *")
	} else {
		a.preview("sync")
		a.out.clean(pad + a.checkoutDisp(baseBranch) + " *")
		a.out.clean(pad + "git pull --ff-only *")
	}
	a.out.clean(pad + "git checkout -b " + a.cmd.arg)
	a.out.clean(pad + "git push -u origin " + a.cmd.arg + " *")
}

// previewBackMerge is the tail every hotfix path shares: dev has to receive what
// landed on the default branch.
func (a *app) previewBackMerge() {
	a.out.clean(pad + a.checkoutDisp(a.mergeTarget()))
	a.out.clean(pad + "git merge " + a.backMergeRef())
	a.out.clean(pad + "git push *")
}

// previewPr reads the same spellings the commands run, so a plan on a Gitea host
// names tea's vocabulary rather than promising gh commands that were never going
// to be the ones issued.
func (a *app) previewPr() {
	if a.pr.sub == "create" {
		a.preview("sync")
		a.out.clean(pad + a.prCreateDisp(a.branchTarget("")))
		return
	}
	a.out.clean(pad + a.prDisp(a.prApproveArgs()) + " *")
	a.out.clean(pad + a.prDisp(a.prMergeArgs()))
	if clean := a.prCleanArgs(); clean != nil {
		a.out.clean(pad + a.prDisp(clean) + " *")
	}
	a.out.clean(pad + a.checkoutDisp(a.branchTarget(a.pr.headBranch)) + " *")
	a.out.clean(pad + "git pull --ff-only *")
	if a.isHotfixBranch(a.pr.headBranch) {
		a.previewBackMerge()
	}
}

func (a *app) previewRelease() {
	a.preview("sync")
	hasDev := a.mergeTarget() == "dev"
	if hasDev {
		a.out.clean(pad + a.checkoutDisp("dev") + " *")
		a.out.clean(pad + "git pull --ff-only *")
	}
	a.out.clean(pad + a.checkoutDisp(a.defaultBranch()) + " *")
	a.out.clean(pad + "git pull --ff-only *")
	if hasDev {
		a.out.clean(pad + "git merge --no-ff dev")
	}
	a.out.clean(pad + "git tag -a " + a.rel.tag)
	a.out.clean(pad + "git push *")
	a.out.clean(pad + "git push origin " + a.rel.tag + " *")
	if hasDev {
		a.out.clean(pad + a.checkoutDisp("dev") + " *")
		a.out.clean(pad + "git merge --ff-only " + a.defaultBranch() + " *")
		a.out.clean(pad + "git push *")
	}
	a.out.clean(pad + a.checkoutDisp(a.currentBranch()) + " *")
}
