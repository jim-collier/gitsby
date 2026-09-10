// pr's argument shape, the read-only views, and the two writers. What a PR lands
// on - and whether it is a hotfix - are properties of the PR, not of the branch
// you happen to be standing on, so 'pr ok' asks gh rather than reading HEAD.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"strings"
)

// prRequest is which pull request this run is about, settled before any plan is
// shown.
type prRequest struct {
	sub        string // "create" or "ok"; empty for the bare list and the numeric view
	num        string
	title      string
	headBranch string
	tool       forgeTool // which CLI answers for this repo's host
	cli        string    // that tool as this machine spells it
}

var prNumRE = regexp.MustCompile(`^[0-9]+$`)

// sortPr validates pr's own arguments - before the repo gate, same as the
// scripts: a malformed pr call is wrong anywhere, in a repo or not.
func (a *app) sortPr() error {
	// Shape only. Which tool can answer used to be settled here, as 'is gh
	// installed' - but that is a question about the HOST, and the host is not known
	// until we are in a repo with a remote. Asked here it told a Gitea user to
	// install a GitHub client, and told a GitHub user with no gh that their
	// perfectly well-formed command was a syntax problem.
	switch strings.ToLower(a.cmd.arg) {
	case "ok":
		a.pr.sub, a.pr.num = "ok", a.cmd.arg2
		if !prNumRE.MatchString(a.pr.num) {
			return usagef("Syntax: %s pr ok <number>", meName)
		}
	case "create", "new":
		a.pr.sub = "create"
		a.pr.title = a.opt.message // -m wins, same as everywhere else
		if a.pr.title == "" {
			a.pr.title = a.cmd.arg2
		}
	case "":
	default:
		a.pr.num = a.cmd.arg
		if !prNumRE.MatchString(a.pr.num) {
			return usagef("Syntax: %s pr [create [title] | <number> | ok <number>]", meName)
		}
	}
	return nil
}

// settlePrTool works out which CLI can answer for this repo, and refuses with the
// real reason when none can. Ordered deliberately - host first, tool second: asked
// the other way round, a Gitea repo was told to install a GitHub client it would
// never use, and the answer never mentioned the host that decided it.
func (a *app) settlePrTool() error {
	if !a.hasOrigin() {
		return usagef("No 'origin' remote, so there is nowhere to open a pull request. Connect one first: %s repo connect <url | owner/name>", meName)
	}
	a.pr.tool, a.pr.cli = a.originTool()
	if a.pr.tool != toolNone {
		return nil
	}
	// A host we could name, and nothing here that speaks to it.
	if host := a.originHost(); host != "" {
		return usagef("Nothing installed here can talk to %s. %s", host, a.forgeCLIHint())
	}
	// No host to name at all - a local path, or a URL shape we don't parse. Not a
	// refusal: this codebase's standing rule is that a remote we don't understand
	// never triggers one, because "we couldn't tell" and "it definitely isn't a
	// forge" are different answers and only one of them is ours to assert. gh gets
	// the last word, exactly as it did before any of this existed, and explains
	// itself in its own words if the remote turns out not to be one it serves.
	if inPath("gh") {
		a.pr.tool, a.pr.cli = toolGh, "gh"
		return nil
	}
	return usagef("Can't tell which git host '%s' is, and no CLI for one is installed to ask. %s",
		maskURL(a.originURL()), a.forgeCLIHint())
}

// The pull-request vocabulary, per tool. Every caller - the preview and the
// command alike - spells its operation through these, so the plan and the run
// cannot describe different things.

// teaDetailFields is what 'pr <n>' shows on Gitea. gh answers the same question
// with two commands, view then diff; tea carries the diff as a field of the detail
// view, so one call covers both.
const teaDetailFields = "index,title,state,author,base,head,url,body,diff"

func (a *app) prListArgs() []string {
	if a.pr.tool == toolTea {
		return []string{"pulls", "list"}
	}
	return []string{"pr", "list"}
}

// prViewArgs is a list of calls, not one: what gh needs two commands for, tea does
// in a single detail view.
func (a *app) prViewArgs() [][]string {
	if a.pr.tool == toolTea {
		return [][]string{{"pulls", a.pr.num, "--fields", teaDetailFields}}
	}
	return [][]string{{"pr", "view", a.pr.num}, {"pr", "diff", a.pr.num}}
}

func (a *app) prCreateArgs(base string) []string {
	if a.pr.tool == toolTea {
		return []string{"pulls", "create", "--base", base, "--head", a.currentBranch(), "--title", a.pr.title}
	}
	return []string{"pr", "create", "--base", base, "--head", a.currentBranch(), "--title", a.pr.title, "--body", ""}
}

func (a *app) prApproveArgs() []string {
	if a.pr.tool == toolTea {
		return []string{"pulls", "approve", a.pr.num}
	}
	return []string{"pr", "review", a.pr.num, "--approve"}
}

func (a *app) prMergeArgs() []string {
	if a.pr.tool == toolTea {
		return []string{"pulls", "merge", a.pr.num, "--style", "merge"}
	}
	return []string{"pr", "merge", a.pr.num, "--merge", "--delete-branch"}
}

// prCleanArgs is the branch delete gh folds into its own merge and tea does not.
// Without it 'pr ok' merges and leaves both feature branches standing on a Gitea
// host - the same command tidying up on one forge and not the other.
func (a *app) prCleanArgs() []string {
	if a.pr.tool == toolTea {
		return []string{"pulls", "clean", a.pr.num}
	}
	return nil
}

// prDisp is one call written out the way the preview shows it.
func (a *app) prDisp(args []string) string { return a.pr.cli + " " + strings.Join(args, " ") }

// parseForgeTable reads tea's tabular output: one header line naming the fields,
// then a row per record. Anything that doesn't have both comes back empty, and
// every caller treats empty as "couldn't tell" rather than as "no such thing" -
// the two are not the same answer, and acting on the wrong one is how a plan ends
// up confidently about a pull request nobody asked for.
func parseForgeTable(out string) []map[string]string {
	lines := splitLines(out)
	if len(lines) < 2 {
		return nil
	}
	header := strings.Split(lines[0], "\t")
	records := make([]map[string]string, 0, len(lines)-1)
	for _, line := range lines[1:] {
		if strings.TrimSpace(line) == "" {
			continue
		}
		cells := strings.Split(line, "\t")
		record := map[string]string{}
		for i, name := range header {
			if i < len(cells) {
				record[strings.ToLower(unquoteCell(name))] = unquoteCell(cells[i])
			}
		}
		records = append(records, record)
	}
	return records
}

// unquoteCell strips the double quotes tea's tsv writer puts around every field,
// header names included. Left on, every lookup misses and every value carries them
// into whatever it was compared against.
func unquoteCell(cell string) string {
	cell = strings.TrimSpace(cell)
	if len(cell) >= 2 && strings.HasPrefix(cell, `"`) && strings.HasSuffix(cell, `"`) {
		cell = cell[1 : len(cell)-1]
	}
	return strings.TrimSpace(cell)
}

// headBranchName drops the 'owner:' a forge puts in front of a head branch that
// lives on a fork. What we compare against, and later hand git, is the branch.
func headBranchName(head string) string {
	if colon := strings.LastIndex(head, ":"); colon >= 0 {
		return head[colon+1:]
	}
	return head
}

// prPreflight is everything the writers need settled before a plan is shown, so
// nothing can fail after it was confirmed.
func (a *app) prPreflight() error {
	prBranch := a.currentBranch()
	if prBranch == "" {
		return usagef("Detached HEAD (no current branch); resolve that manually first.")
	}
	if a.pr.sub == "ok" {
		return a.prAcceptPreflight(prBranch)
	}
	if prBranch == a.mergeTarget() || prBranch == a.defaultBranch() {
		return usagef("'%s' is what pull requests merge into; there is nothing to propose. Start a branch first: %s br create <name>", prBranch, meName)
	}
	// No title given: the last commit subject is what the work is called already.
	if a.pr.title == "" {
		a.pr.title = runOut("git", "log", "-1", "--pretty=%s")
	}
	if a.pr.title == "" {
		return usagef("No commits on '%s' yet; nothing to propose.", prBranch)
	}
	// An open PR for this branch already is the answer to 'pr create' - say so
	// instead of letting the forge error.
	if existing := a.openPrForBranch(prBranch); existing != "" {
		return usagef("PR #%s is already open for '%s'. View it: %s pr %s", existing, prBranch, meName, existing)
	}
	return nil
}

// openPrForBranch is the number of the open PR proposing this branch, or nothing -
// which covers both "there isn't one" and "we couldn't ask". Only a courtesy
// message hangs off it, so the two collapsing into one answer costs nothing.
func (a *app) openPrForBranch(prBranch string) string {
	if a.pr.tool == toolTea {
		out, ok := runOutOK(a.pr.cli, "pulls", "list", "--state", "open", "--fields", "index,head", "--output", "tsv")
		if !ok {
			return ""
		}
		for _, record := range parseForgeTable(out) {
			if headBranchName(record["head"]) == prBranch {
				return record["index"]
			}
		}
		return ""
	}
	return runOut("gh", "pr", "list", "--head", prBranch, "--state", "open", "--json", "number", "--jq", ".[0].number // empty")
}

// readPr asks the forge which branch a PR proposes and whether it is still open.
// The bool is "we got an answer", kept apart from the answer itself: a tool that
// cannot say must not be read as saying the PR is closed, or as agreeing with
// whatever branch we happen to be standing on. The caller refuses on !ok, which is
// the whole reason this is settled before a plan rather than during one.
func (a *app) readPr() (head, state string, ok bool) {
	if a.pr.tool == toolTea {
		out, ran := runOutOK(a.pr.cli, "pulls", a.pr.num, "--fields", "index,head,state", "--output", "tsv")
		if !ran {
			return "", "", false
		}
		records := parseForgeTable(out)
		if len(records) != 1 {
			return "", "", false
		}
		return headBranchName(records[0]["head"]), records[0]["state"], true
	}
	info, ran := runOutOK("gh", "pr", "view", a.pr.num, "--json", "headRefName,state", "--jq", ".headRefName, .state")
	fields := splitLines(info)
	if !ran || len(fields) != 2 {
		return "", "", false
	}
	return fields[0], fields[1], true
}

// prAcceptPreflight is 'pr ok <n>', which can be run from anywhere: ask gh which
// branch the PR proposes and whether it is still open. A gh that cannot answer
// used to fall back to the current branch, which made the plan confidently about
// the wrong thing and killed the run after it was confirmed - the exact shape
// preflight exists to prevent.
func (a *app) prAcceptPreflight(prBranch string) error {
	head, state, ok := a.readPr()
	if !ok || head == "" {
		return usagef("Can't read PR #%s; check the number, and that %s can see this repo.", a.pr.num, a.pr.cli)
	}
	a.pr.headBranch = head
	// Case-insensitively: gh answers 'OPEN' and tea answers 'open', and comparing
	// against one spelling makes every PR on the other forge read as already closed.
	if !strings.EqualFold(state, "open") {
		return usagef("PR #%s is %s, not open; there is nothing to accept.", a.pr.num, strings.ToLower(state))
	}
	if err := refuseOptionShapedRefs(a.pr.headBranch); err != nil {
		return err
	}
	// gh merges what origin already has, then deletes the branch local and remote.
	// Work that never reached origin is outside the PR and outside the merge -
	// refuse, don't lose it.
	if runOut("git", "status", "--porcelain") != "" || isAhead() {
		if prBranch == a.pr.headBranch {
			return usagef("'%s' has changes that aren't on origin, so PR #%s can't include them. Run '%s sync' first.", prBranch, a.pr.num, meName)
		}
		return usagef("'%s' has changes that aren't on origin. Park them first: %s sync", prBranch, meName)
	}
	// Asked of the PR's own branch by name, wherever we are standing: gh deletes it
	// with 'branch -D' either way, and '@{u}' above answers nothing at all for a
	// branch that was pushed without -u - so standing on that one, the guard passed
	// and the commits went with the branch.
	if branchExistsLocal(a.pr.headBranch) {
		if !branchExistsRemote(a.pr.headBranch) {
			return usagef("'%s' is here but not on origin, so PR #%s holds none of it - and it would be deleted. Push it first: git push -u origin %s", a.pr.headBranch, a.pr.num, a.pr.headBranch)
		}
		if branchHasUnpushed(a.pr.headBranch) {
			return usagef("'%s' has commits that never reached origin, so PR #%s can't include them - and it would be deleted. Push them first: git push origin %s", a.pr.headBranch, a.pr.num, a.pr.headBranch)
		}
	}
	return nil
}

// cmdPrView: bare lists open PRs; a number views one plus its diff.
func (a *app) cmdPrView() error {
	if a.pr.num == "" {
		return a.step(a.pr.cli, a.prListArgs()...)
	}
	for _, call := range a.prViewArgs() {
		if err := a.step(a.pr.cli, call...); err != nil {
			return err
		}
	}
	return nil
}

func (a *app) cmdPrCreate() error {
	// GitHub can only diff what origin has, so park the work first - same as br merge
	// and release do.
	if err := a.cmdPush(); err != nil {
		return err
	}
	// Announced by hand rather than through step, like the approve below: step would
	// print --head and --body too, which the preview doesn't, so the two lines would
	// disagree.
	base := a.branchTarget("")
	return a.stepAs(a.prCreateDisp(base), a.pr.cli+" pr create", a.pr.cli, a.prCreateArgs(base)...)
}

// prCreateDisp is the one line the preview and the run both show for a create -
// the title and the base, without the flags neither of them promised.
func (a *app) prCreateDisp(base string) string {
	verb := "pr create"
	if a.pr.tool == toolTea {
		verb = "pulls create"
	}
	return a.pr.cli + " " + verb + " --base " + base + " --title \"" + a.pr.title + "\""
}

func (a *app) cmdPrAccept() error {
	// Resolve both before gh deletes the branch out from under us, and off the PR's
	// own head branch (resolved up front) rather than the current one - they need not
	// be the same.
	targetBranch := a.branchTarget(a.pr.headBranch)
	wasHotfixPr := a.isHotfixBranch(a.pr.headBranch)
	a.out.clean("")
	approve := a.prApproveArgs()
	a.out.status(a.prDisp(approve) + " ...")
	// Best-effort: both forges refuse to approve your own PR; merging is the part
	// that matters.
	if !a.inheritOK(a.pr.cli, approve...) {
		a.out.status("Could not approve (own PR?); merging anyway.")
	}
	a.out.resetBlank()
	if err := a.step(a.pr.cli, a.prMergeArgs()...); err != nil {
		return err
	}
	// The branch delete gh folds into its merge, for the tool that doesn't. Best
	// effort: the merge is what was asked for, and a branch somebody already removed
	// is not a failure worth ending the run on.
	if clean := a.prCleanArgs(); clean != nil {
		a.out.status(a.prDisp(clean) + " ...")
		if !a.inheritOK(a.pr.cli, clean...) {
			a.out.status("Could not delete the merged branch; it may already be gone.")
		}
		a.out.resetBlank()
	}
	// The merge removes the PR's branch on the remote but leaves our origin/* copy
	// behind, so an upstream still looks present. Prune first; if ours is the branch
	// that just went away, pulling it can only fail - land on the merge target instead.
	a.fetchRemote()
	if !a.hasUpstream() {
		if err := a.checkout(targetBranch); err != nil {
			return err
		}
	}
	if err := a.pullIfOnline(); err != nil {
		return err
	}
	// Same rule as merge: a hotfix that reached the default branch still owes dev a
	// merge.
	if wasHotfixPr {
		return a.backMergeToDev()
	}
	return nil
}
