// Cutting a release: work out the version, refuse the ones that would strand a
// tag, then merge dev into the default branch, tag it, and push both. The version
// settles up front so the plan and the command can't disagree about it.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"strconv"
	"strings"
)

// releasePlan is the version this run cuts, and whether we invented it - the
// guards below only speak for the invented ones.
type releasePlan struct {
	tag    string
	bumped bool
}

var (
	releaseVerRE = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$`)
	releaseTagRE = regexp.MustCompile(`^v?([0-9]+)(\.([0-9]+))?(\.([0-9]+))?(.*)$`)
)

// nextVersion is the version that follows a tag. A candidate's own version is
// what comes next: v2.0.0-rc1 -> v2.0.0, not v2.0.1 - promoting a candidate is a
// deliberate version rather than an invented one, and the bool says which. Short
// tags like v1.2 or v2020 pad out, and an unreadable one starts the numbering.
func nextVersion(latest string) (version string, bumped bool) {
	m := releaseTagRE.FindStringSubmatch(latest)
	if m == nil {
		return "0.1.0", true // first release ever, or an unreadable tag
	}
	major, minor := m[1], m[3]
	if minor == "" {
		minor = "0"
	}
	// m[5] already matched [0-9]+, so Atoi only fails on overflow - it answers
	// with the clamped max, which the bump below would wrap negative; 0 starts over.
	patch, err := strconv.Atoi(m[5])
	if err != nil {
		patch = 0
	}
	bumped = m[6] == ""
	if bumped {
		patch++
	}
	return major + "." + minor + "." + strconv.Itoa(patch), bumped
}

// resolveRelease settles the tag this run cuts, from the argument or from the
// latest tag in the repo.
func (a *app) resolveRelease() error {
	if ver := strings.TrimPrefix(a.cmd.arg, "v"); ver != "" {
		if !releaseVerRE.MatchString(ver) {
			return usagef("'%s' is not a version (want X.Y.Z, optional -suffix). Syntax: %s release [version]", ver, meName)
		}
		a.rel.tag = "v" + ver
		return nil
	}
	latest := ""
	// versionsort.suffix=- ranks v2.0.0 above its own v2.0.0-rc1; the default sort
	// inverts them.
	if tags := runLines("git", "-c", "versionsort.suffix=-", "tag", "--list", "v[0-9]*", "--sort=-v:refname"); len(tags) > 0 {
		latest = tags[0]
	}
	ver, bumped := nextVersion(latest)
	a.rel.tag, a.rel.bumped = "v"+ver, bumped
	return nil
}

// releasePreflight refuses up front rather than mid-command: by the time
// cmdRelease runs it has already committed and pushed.
func (a *app) releasePreflight() error {
	if runOK("git", "rev-parse", "-q", "--verify", "refs/tags/"+a.rel.tag) {
		return usagef("Tag '%s' already exists.", a.rel.tag)
	}
	// An invented version on a target that would gain nothing cuts a tag for no
	// release, and the natural re-run after a failed push cuts a second one on the
	// same commit - so the first is stranded forever. A version you typed, and
	// promoting a candidate, are deliberate and stay allowed. Fails open: if we
	// can't tell, the release goes ahead. 'release' parks first, so uncommitted work
	// or unpushed commits ARE something to release even when the branches currently
	// look level - the guard only speaks for a settled repo.
	if !a.rel.bumped || runOut("git", "status", "--porcelain") != "" || isAhead() {
		return nil
	}
	relMain := a.defaultBranch()
	relTarget := relMain
	if !branchExistsLocal(relMain) {
		relTarget = "origin/" + relMain
	}
	// The local branch is what gets tagged and pushed, so it is what "nothing new"
	// is about. Stand down if origin holds commits we don't: the pull would bring
	// them in.
	if relTarget == relMain && branchExistsRemote(relMain) {
		if !runOK("git", "merge-base", "--is-ancestor", "origin/"+relMain, relMain) {
			return nil
		}
	}
	relSource := ""
	if branchExistsRemote("dev") {
		relSource = "origin/dev"
	} else if branchExistsLocal("dev") {
		relSource = "dev"
	}
	if relSource != "" && !runOK("git", "merge-base", "--is-ancestor", relSource, relTarget) {
		return nil
	}
	if relExisting := runOut("git", "describe", "--exact-match", "--tags", relTarget); relExisting != "" {
		a.out.status("Nothing new to release since " + relExisting + ".")
		a.out.clean("  If that tag never reached origin, push it: git push origin " + relExisting)
		a.out.clean("")
		return errDone
	}
	return nil
}

// cmdRelease merges dev into main/master --no-ff (if the repo has a dev), tags,
// and pushes both.
func (a *app) cmdRelease() error {
	mainBranch := a.defaultBranch()
	devBranch := ""
	if branchExistsLocal("dev") || branchExistsRemote("dev") {
		devBranch = "dev"
	}
	startBranch := a.currentBranch()
	if err := a.cmdPush(); err != nil { // park current work safely first
		return err
	}
	if devBranch != "" && a.currentBranch() != devBranch {
		// Freshen dev so the release has all of it.
		if err := a.checkout(devBranch); err != nil {
			return err
		}
		if err := a.pullIfOnline(); err != nil {
			return err
		}
	}
	if a.currentBranch() != mainBranch {
		if err := a.checkout(mainBranch); err != nil {
			return err
		}
	}
	if err := a.pullIfOnline(); err != nil {
		return err
	}
	if devBranch != "" {
		mergeMessage := a.opt.message
		if mergeMessage == "" {
			mergeMessage = "Release " + a.rel.tag
		}
		if err := a.step("git", "merge", "--no-ff", devBranch, "-m", mergeMessage); err != nil {
			return err
		}
	}
	if err := a.step("git", "tag", "-a", a.rel.tag, "-m", a.rel.tag); err != nil {
		return err
	}
	// The branch has to reach origin, not just the tag - otherwise origin gets the
	// commits as tag payload while its main still points at the old release. Same
	// trap as merge's.
	if a.hasOrigin() {
		push := []string{"push"}
		if !a.hasUpstream() {
			push = []string{"push", "-u", "origin", "HEAD"}
		}
		if err := a.step("git", push...); err != nil {
			return err
		}
		if err := a.step("git", "push", "origin", a.rel.tag); err != nil {
			return err
		}
	}
	// Fast-forward dev to include the release merge and tag, so dev isn't left a
	// commit behind. ff-only (not branch -f): if dev moved mid-release, skip rather
	// than discard work.
	if devBranch != "" {
		if !runOK("git", "merge-base", "--is-ancestor", devBranch, mainBranch) {
			a.out.status("WARNING: '" + devBranch + "' gained commits during the release; leaving it as-is.")
		} else {
			if err := a.checkout(devBranch); err != nil {
				return err
			}
			if err := a.step("git", "merge", "--ff-only", mainBranch); err != nil {
				return err
			}
			if a.hasUpstream() {
				if err := a.step("git", "push"); err != nil {
					return err
				}
			}
		}
	}
	// Don't leave the user parked on main.
	if startBranch != "" && startBranch != a.currentBranch() && startBranch != mainBranch {
		return a.checkout(startBranch)
	}
	return nil
}
