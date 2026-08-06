#!/usr/bin/env bash

#  shellcheck disable=2317  ## 'Can't reach.' False hits on functions invoked indirectly.

##	Purpose:
##		- Regression tests for bin/gitsby (and bin/gitsby.ps1 when pwsh is
##		  installed - same suite, run once per implementation).
##		- Run by cicd.bash stage 2, or standalone.
##		- Builds throwaway repos (a bare 'origin' + two clones) under mktemp;
##		  never touches the real repo or network.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-test.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

## Keep test commits hermetic (no reliance on the user's git config).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

declare -i pass=0 fail=0
fOk(){   pass=$((pass+1)); echo "  ok: $*"; }
fFail(){ fail=$((fail+1)); echo "  FAIL: $*"; }
## Assert the command succeeds / fails (output discarded; -q keeps gitsby promptless).
fAssert(){     local desc="$1"; shift; if   "$@" >/dev/null 2>&1; then fOk "$desc"; else fFail "$desc"; fi; }
fAssertFail(){ local desc="$1"; shift; if ! "$@" >/dev/null 2>&1; then fOk "$desc"; else fFail "$desc"; fi; }
## Assert the command's output matches an extended regex (for the pre-flight display).
## Capture rather than pipe: 'grep -q' would close the pipe early and pipefail would call that a failure.
fAssertOut(){  local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if grep -qE "$pat" <<< "${out}"; then fOk "$desc"; else fFail "$desc"; fi; }
fAssertNotOut(){ local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if ! grep -qE "$pat" <<< "${out}"; then fOk "$desc"; else fFail "$desc"; fi; }
## Matches against the PLAN only, not the whole run. Every "plans X" assertion against full
## output is also satisfied by the execution echo of the same command, so it cannot tell a
## preview that lists a step from one that silently stopped listing it. Plan lines are indented
## under "Going to do"; the first execution line starts at column 0 with '[', in both ports.
fPlanOf(){ awk '/Going to do/{p=1;next} p&&/^\[/{exit} p' ;}
## Runs PowerShell source TEXT the way the documented one-liners do (iex / scriptblock), with no
## controlling terminal and stdin at EOF so a confirmation prompt refuses instead of blocking.
fPwshText(){ setsid pwsh -NoProfile -Command "$1" </dev/null 2>&1 ;}
fAssertPlan(){    local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if     grep -qE "$pat" <<< "$(fPlanOf <<< "${out}")"; then fOk "$desc"; else fFail "$desc"; fi; }
fAssertNotPlan(){ local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if ! grep -qE "$pat" <<< "$(fPlanOf <<< "${out}")"; then fOk "$desc"; else fFail "$desc"; fi; }

## Fixture: bare origin with an initial commit on main, plus two clones.
fMakeFixture(){
	local -r fixDir="$1"
	mkdir -p "${fixDir}"
	origin="${fixDir}/origin.git"; cloneA="${fixDir}/a"; cloneB="${fixDir}/b"
	git init --quiet --bare -b main "${origin}"
	git clone --quiet "${origin}" "${cloneA}" 2>/dev/null
	(
		cd "${cloneA}"
		echo one > file1.txt
		git add --all; git commit --quiet -m "initial"
		git push --quiet -u origin main
	)
	git clone --quiet "${origin}" "${cloneB}"
}

## The whole suite, against whatever ${gitsby} points at.
fRunSuite(){
	echo "suite: $1 (${gitsby})"

	## Help + bad input surface
	fAssert     "help exits 0"                 "${gitsby}" --help
	fAssert     "version exits 0"              "${gitsby}" -v
	fAssert     "bare 'help' word works"       "${gitsby}" help
	fAssert     "bare 'version' word works"    "${gitsby}" version
	fAssertOut  "help keeps the pull-then-commit order" 'sync .*: Pull, commit, and push' "${gitsby}" --help
	fAssertOut  "help doesn't promise a bare patch bump" 'release .*: .*next after latest tag' "${gitsby}" --help
	fAssertOut  "help doesn't overpromise br create"    'br create .*: .*carried or parked'   "${gitsby}" --help
	## Asking for help after a command is the reflex every git user has, and both builds must
	## answer it the same way. -v is the opposite case: alongside a command it used to make the
	## PowerShell build print the version and exit 0, doing none of the work it was asked for.
	fAssert     "--help works after a command"     "${gitsby}" update --help
	fAssert     "--help works after noun and verb" "${gitsby}" br create --help
	fAssert     "-h works after a command"         "${gitsby}" update -h
	fAssertFail "-v after a command is refused"    bash -c "cd '${cloneA}' && '${gitsby}' -q update -v"
	fAssertOut  "and says which option"            'Unexpected option'  bash -c "cd '${cloneA}' && '${gitsby}' -q update -v 2>&1"
	fAssert     "-y alias accepted"            bash -c "cd '${cloneA}' && '${gitsby}' -y status"
	fAssertFail "no args exits nonzero"        "${gitsby}"
	fAssertFail "unknown command rejected"     bash -c "cd '${cloneA}' && '${gitsby}' -q frobnicate"
	fAssertFail "unknown option rejected"      bash -c "cd '${cloneA}' && '${gitsby}' -q status --bogus"
	fAssertOut  "--public with --private refused"  'mutually exclusive'  bash -c "cd '${cloneA}' && '${gitsby}' -q --public --private repo create me/x 2>&1"
	fAssertFail "outside a repo rejected"      bash -c "cd '${work}' && '${gitsby}' -q status"
	## Read-only commands used to ignore trailing arguments while everything else rejected them,
	## which makes a typo look like it did what you meant.
	fAssertFail "status with a trailing argument rejected"   bash -c "cd '${cloneA}' && '${gitsby}' -q status extra"
	fAssertFail "br list with a trailing argument rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q br list extra"
	fAssertOut  "and says what takes no arguments"  'takes no arguments'  bash -c "cd '${cloneA}' && '${gitsby}' -q status extra 2>&1"
	## An option or positional typo is a usage error, not a crash - no internal stack dump.
	fAssertNotOut "option typo prints no call stack"  'Reverse call stack'  bash -c "cd '${cloneA}' && '${gitsby}' -q status --bogus 2>&1"

	## Grouped-noun grammar: spelled-out nouns, hidden verb aliases, and refusals
	fAssert     "'branch' spells out 'br'"        bash -c "cd '${cloneA}' && '${gitsby}' -q branch list"
	fAssert     "'br new' aliases 'br create'"    bash -c "cd '${cloneA}' && '${gitsby}' -q br new grammar1 && git -C '${cloneA}' branch --show-current | grep -qx grammar1"
	fAssert     "'br go' aliases 'br switch'"     bash -c "cd '${cloneA}' && '${gitsby}' -q br go main && git -C '${cloneA}' branch --show-current | grep -qx main"
	fAssertFail "unknown br subcommand rejected"   bash -c "cd '${cloneA}' && '${gitsby}' -q br frobnicate"
	fAssertFail "unknown repo subcommand rejected" bash -c "cd '${cloneA}' && '${gitsby}' -q repo frobnicate"
	fAssertFail "bare 'repo' rejected"             bash -c "cd '${cloneA}' && '${gitsby}' -q repo"
	fAssertFail "internal token not typeable"      bash -c "cd '${cloneA}' && '${gitsby}' -q br-create nope"
	fAssertFail "extra positional rejected"        bash -c "cd '${cloneA}' && '${gitsby}' -q br switch main extra"
	( cd "${cloneA}" && git branch -D grammar1 >/dev/null 2>&1; git push --quiet origin --delete grammar1 2>/dev/null || true )

	## Read-only commands
	fAssert "status runs"  bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssert "br list runs"  bash -c "cd '${cloneA}' && '${gitsby}' -q br list"
	fAssertFail "dropped v1 alias 'list' rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q list"

	## Pre-flight display: who we act as, and a compact list of what changes
	fAssertOut "status names the commit author"  'Author \.+:'            bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "clean worktree says so"          '\(working tree clean\)' bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	( cd "${cloneA}" && echo probe > probe.txt )
	fAssertOut "changed file listed"             '\?\? probe\.txt'        bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "mutating command previews first" 'Going to do'            bash -c "cd '${cloneA}' && '${gitsby}' -q update 'probe'"
	( cd "${cloneA}" && git reset --quiet --hard HEAD~1 )

	## update: commits everything and pulls; idempotent when clean. There is no bare
	## 'commit' or 'pull' any more - both would leave you in a state gitsby exists to avoid.
	( cd "${cloneA}" && echo two > file2.txt )
	fAssert "update commits new file"         bash -c "cd '${cloneA}' && '${gitsby}' -q update 'add file2'"
	fAssert "worktree clean after update"     bash -c "cd '${cloneA}' && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssert "update message recorded"         bash -c "cd '${cloneA}' && git log -1 --format=%s | grep -qx 'add file2'"
	fAssert "update again (nothing to do) ok" bash -c "cd '${cloneA}' && '${gitsby}' -q update 'noop'"
	## sync takes its message positionally like update, and nothing checked that it lands - the
	## message could quietly be replaced by the auto-generated timestamp with the suite still green.
	( cd "${cloneA}" && echo s > s.txt )
	fAssert "sync records the message it was given"  bash -c "cd '${cloneA}' && '${gitsby}' -q sync 'synced by name' && git log -1 --format=%s | grep -qx 'synced by name'"
	fAssertFail "dropped 'commit' command rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit 'no such command'"
	fAssertFail "dropped 'pull' command rejected"    bash -c "cd '${cloneA}' && '${gitsby}' -q pull"
	( cd "${cloneA}" && echo alias > alias.txt )
	fAssertFail "dropped v1 alias 'scommit' rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q scommit 'via alias'"
	( cd "${cloneA}" && echo upd > upd.txt )
	fAssert "update sweeps in leftover work"  bash -c "cd '${cloneA}' && '${gitsby}' -q update 'add upd'"
	fAssertFail "dropped v1 alias 'saveup' rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q saveup"

	## sync: publishes; remote matches local
	fAssert "sync runs"            bash -c "cd '${cloneA}' && '${gitsby}' -q sync 'push file2'"
	fAssert "remote main matches"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"

	## remote moved ahead + local dirty -> update commits the local work, then fast-forwards
	(
		cd "${cloneB}"
		git pull --quiet --ff-only
		echo bee > fileB.txt
		git add --all; git commit --quiet -m "from B"
		git push --quiet
	)
	( cd "${cloneA}" && echo dirty >> file1.txt )
	fAssertOut "behind count on the branch line"  'behind 1'   bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "incoming changes previewed"       'Incoming'   bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "incoming file named"              'fileB\.txt' bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssert "update with dirty tree + remote ahead"  bash -c "cd '${cloneA}' && '${gitsby}' -q update 'local edit'"
	fAssert "remote commit arrived"                  bash -c "cd '${cloneA}' && [[ -f fileB.txt ]]"
	fAssert "local edit survived, committed"         bash -c "cd '${cloneA}' && grep -q dirty file1.txt && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssert "and it sits on top of the remote work"  bash -c "cd '${cloneA}' && git merge-base --is-ancestor origin/main HEAD"
	fAssert "nothing stranded in the stash"          bash -c "cd '${cloneA}' && [[ -z \"\$(git stash list)\" ]]"

	## br create: branches off default, publishes with upstream; dirty work on the
	## protected base is carried to the new branch, never committed to the base
	## update now commits, so main sits ahead of origin here; pin its sha instead of
	## comparing to origin, and assert the WIP never landed on it.
	( cd "${cloneA}" && echo dirty2 >> file1.txt && git rev-parse main > "${work}/$1-mainsha" )
	fAssert "br create feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q br create feat"
	fAssert "now on feat"            bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssert "feat has upstream"      bash -c "cd '${cloneA}' && git rev-parse --abbrev-ref 'feat@{u}' >/dev/null"
	fAssert "dirty edit carried uncommitted"  bash -c "cd '${cloneA}' && grep -q dirty2 file1.txt && ! git diff --quiet"
	fAssert "no WIP commit on main"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(cat '${work}/$1-mainsha')\" ]] && ! git show main:file1.txt | grep -q dirty2"
	( cd "${cloneA}" && git add --all && git commit --quiet -m "carried" )
	fAssertFail "br create existing name rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q br create feat"
	fAssertFail "br create bad name rejected"       bash -c "cd '${cloneA}' && '${gitsby}' -q br create 'bad name'"
	fAssertFail "br create no name rejected"        bash -c "cd '${cloneA}' && '${gitsby}' -q br create"
	fAssertNotOut "bad branch arg dies before the preview"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q br create 'bad name'"

	## gobr: switch back and forth; bogus target rejected
	fAssert "br switch (default: main)"  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch"
	fAssert "now on main"           bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "br switch feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q br switch feat"
	fAssert "back on feat"          bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssertFail "br switch nonexistent rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch nosuch"

	## gobr refuses to auto-commit WIP sitting on a protected branch, before showing a plan
	( cd "${cloneA}" && git checkout --quiet main && echo wip >> file2.txt )
	fAssertFail   "br switch from dirty main refuses"           bash -c "cd '${cloneA}' && '${gitsby}' -q br switch feat"
	fAssertNotOut "and dies before the preview"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch feat"
	## The way out it offers has to be a command that still exists (it named the dropped 'commit')
	fAssertOut    "and points at a real command"  'deliberately \(.*update\) first'  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch feat"
	fAssert "wip left uncommitted on main"      bash -c "cd '${cloneA}' && ! git diff --quiet && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"
	## newbr carries that same tree instead, so its plan must not promise a commit on main
	fAssertNotPlan "br create from main previews no commit"  'git add --all'  bash -c "cd '${cloneA}' && '${gitsby}' -q br create wipcarry"
	fAssert "wip carried to the new branch"  bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == wipcarry ]] && ! git diff --quiet"
	( cd "${cloneA}" && git checkout --quiet -- file2.txt && git checkout --quiet feat
	  git branch --quiet -D wipcarry && git push --quiet origin --delete wipcarry )

	## land: merge feat into main --no-ff, then delete it local + remote
	( cd "${cloneA}" && echo feat > feat.txt )
	fAssert "br land merges feat into main"  bash -c "cd '${cloneA}' && '${gitsby}' -q br land 'merge feat work'"
	fAssert "now on main after land"      bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "merge commit is --no-ff"     bash -c "cd '${cloneA}' && git log -1 --merges --format=%s | grep -qx 'merge feat work'"
	fAssert "feat deleted locally"        bash -c "cd '${cloneA}' && ! git show-ref --verify --quiet refs/heads/feat"
	fAssert "feat deleted on origin"      bash -c "cd '${origin}' && ! git show-ref --verify --quiet refs/heads/feat"
	fAssert "main pushed after land"      bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"
	fAssertFail "br land from main rejected" bash -c "cd '${cloneA}' && '${gitsby}' -q br land"

	## dev-aware targeting: with a dev branch, newbr bases off dev and land merges to dev
	( cd "${cloneA}" && git checkout --quiet -b dev && git push --quiet -u origin dev )
	fAssert "br create feat2 bases off dev"   bash -c "cd '${cloneA}' && '${gitsby}' -q br create feat2 && [[ \"\$(git merge-base feat2 dev)\" == \"\$(git rev-parse dev)\" ]]"
	( cd "${cloneA}" && echo feat2 > feat2.txt )
	fAssert "br land merges feat2 into dev"  bash -c "cd '${cloneA}' && '${gitsby}' -q br land 'merge feat2 work'"
	fAssert "now on dev after land"       bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert "feat2 landed on dev not main"  bash -c "cd '${cloneA}' && [[ -f feat2.txt ]] && ! git ls-tree --name-only main | grep -qx feat2.txt"
	fAssert "br switch with no arg goes to dev"  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch main && '${gitsby}' -q br switch && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssertFail "br land from dev rejected"    bash -c "cd '${cloneA}' && '${gitsby}' -q br land"
	fAssertFail "br land from main rejected (dev repo)"  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch main && '${gitsby}' -q br land; rc=\$?; git checkout --quiet dev; exit \$rc"
	## Landing ends in a branch delete, so a protected branch must be refused before the plan is
	## shown - not after the user has confirmed 'git branch -d main'.
	fAssertNotOut "and refuses before showing a plan that deletes it"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch main >/dev/null && '${gitsby}' -q br land 2>&1; git checkout --quiet dev"

	## release: merge dev into main, tag, push; then auto-bump patch on the next one
	fAssert "release 1.2.3 runs"        bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssert "tag v1.2.3 on main"        bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse v1.2.3^{commit})\" == \"\$(git rev-parse main)\" ]]"
	fAssert "release merged dev to main"  bash -c "cd '${cloneA}' && git ls-tree --name-only main | grep -qx feat2.txt"
	fAssert "main pushed with tag"      bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]] && git ls-remote --tags origin | grep -q 'refs/tags/v1.2.3'"
	fAssert "back on dev after release"  bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert "dev fast-forwarded to the release"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse dev)\" == \"\$(git rev-parse main)\" ]]"
	fAssert "dev pushed after release"           bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse dev)\" == \"\$(git rev-parse origin/dev)\" ]]"
	fAssertFail   "release same version rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssertNotOut "duplicate tag dies before the preview"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssertFail "release bad version rejected"   bash -c "cd '${cloneA}' && '${gitsby}' -q release bogus"
	( cd "${cloneA}" && echo more > more.txt )
	fAssert "release with no version bumps patch"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.2.4 >/dev/null"

	## A candidate's own version is what comes next, and once it's cut the bump resumes from it
	( cd "${cloneA}" && git tag -a v1.3.0-rc1 -m rc1 && echo cand > cand.txt )
	fAssert "release after a candidate takes the candidate's version"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.3.0 >/dev/null"
	fAssert "it did not skip past to a later patch"                    bash -c "cd '${cloneA}' && ! git rev-parse -q --verify refs/tags/v1.3.1 >/dev/null"
	( cd "${cloneA}" && echo post > post.txt )
	fAssert "the next release bumps off the full version, not the candidate"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.3.1 >/dev/null"

	## An invented version with nothing to release is a tag for no release, and re-running after
	## a failed push would cut a second one on the same commit, stranding the first forever.
	fAssertFail "bare release refuses when there is nothing new"  bash -c "cd '${cloneA}' && '${gitsby}' -q release"
	fAssertOut  "and names the tag to push if it never landed"  'Nothing new to release since v1\.3\.1'  bash -c "cd '${cloneA}' && '${gitsby}' -q release 2>&1"
	fAssert     "and cut no tag doing so"  bash -c "cd '${cloneA}' && ! git rev-parse -q --verify refs/tags/v1.3.2 >/dev/null"
	## A version you typed is deliberate, so it still works on an already-released commit.
	fAssert     "an explicit version still releases the same commit"  bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.4.0 && git rev-parse -q --verify refs/tags/v1.4.0 >/dev/null"

	## release started from a feature branch returns there; slash branch names work
	fAssert "br create relfeat"  bash -c "cd '${cloneA}' && '${gitsby}' -q br create relfeat"
	( cd "${cloneA}" && echo rel > rel.txt )
	fAssert "release from a feature branch runs"  bash -c "cd '${cloneA}' && '${gitsby}' -q release"
	fAssert "returns to the feature branch"       bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == relfeat ]]"
	fAssert "br create with a slash name"  bash -c "cd '${cloneA}' && '${gitsby}' -q br create feat/x && [[ \"\$(git branch --show-current)\" == feat/x ]]"
	fAssert "br switch back to dev"         bash -c "cd '${cloneA}' && '${gitsby}' -q br switch && [[ \"\$(git branch --show-current)\" == dev ]]"
	## Already on the target: no checkout and no park happen, so the plan must not list them.
	( cd "${cloneA}" && echo swp > swp.txt )
	fAssertNotPlan "br switch onto the current branch plans no commit"  'git commit'  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch dev"
	fAssertPlan   "and still plans the pull"  'git pull --ff-only'                   bash -c "cd '${cloneA}' && '${gitsby}' -q br switch dev"

	## Detached HEAD guard
	fAssertFail "mutating command on detached HEAD rejected"  bash -c "cd '${cloneA}' && git checkout --quiet HEAD~0 --detach && '${gitsby}' -q update x"
	( cd "${cloneA}" && git checkout --quiet dev )

	## Messages with quotes pass through unmangled (no eval, no curly-quote games)
	( cd "${cloneA}" && echo q > q.txt )
	fAssert "message with quotes survives"  bash -c "cd '${cloneA}' && '${gitsby}' -q update \"don't \\\"quote\\\" me\" && git log -1 --format=%s | grep -qx \"don't \\\"quote\\\" me\""

	## Message handling: -m and -m= forms; option-like words stay words; extra bare word rejected
	( cd "${cloneA}" && echo m1 > m1.txt )
	fAssert "update -m flag form"     bash -c "cd '${cloneA}' && '${gitsby}' -q update -m 'via -m flag' && git log -1 --format=%s | grep -qx 'via -m flag'"
	if [[ "$1" == "bash" ]]; then  ## -m=MSG is bash-only; pwsh binding has no -param=value form
		( cd "${cloneA}" && echo m2 > m2.txt )
		fAssert "update -m= joined form"  bash -c "cd '${cloneA}' && '${gitsby}' -q update -m='via -m= flag' && git log -1 --format=%s | grep -qx 'via -m= flag'"
	fi
	( cd "${cloneA}" && echo m3 > m3.txt )
	fAssert "message containing -v commits"           bash -c "cd '${cloneA}' && '${gitsby}' -q update 'add -v flag' && git log -1 --format=%s | grep -qx 'add -v flag'"
	## A message that STARTS with a dash: '-m' is waiting for a value, so the next token is that
	## value whatever it looks like. There is no other way to write one, and the ports disagreed.
	( cd "${cloneA}" && echo m4 > m4.txt )
	fAssert "message starting with a dash commits"    bash -c "cd '${cloneA}' && '${gitsby}' -q update -m '-Wall added to CFLAGS' && git log -1 --format=%s | grep -qx -- '-Wall added to CFLAGS'"
	fAssertFail "unquoted two-word message rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q update Fixed bug"

	## Non-tty: mutating commands fail closed without -q; read-only ones just go quiet
	( cd "${cloneA}" && echo nt > nt.txt )
	fAssertFail "mutating without -q and no tty refuses"  bash -c "cd '${cloneA}' && '${gitsby}' update ntmsg < /dev/null"
	fAssert "file left uncommitted"                       bash -c "cd '${cloneA}' && git status --porcelain | grep -q nt.txt"
	fAssert "read-only without -q still runs non-tty"     bash -c "cd '${cloneA}' && '${gitsby}' status < /dev/null"
	( cd "${cloneA}" && "${gitsby}" -q update "nt cleanup" >/dev/null 2>&1 )

	## Credentialed remote URLs display masked (-NoFetch keeps it off the network; also lowercases to bash --nofetch)
	( cd "${cloneA}" && git remote set-url origin 'https://user:sekrit@127.0.0.1:1/x.git' )
	fAssertNotOut "no-fetch skips the fetch"           '\[ git fetch' bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	fAssertOut    "remote URL masks credentials"       '\*\*\*@127\.0\.0\.1' bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	fAssertNotOut "credential itself never shown"      'sekrit' bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	( cd "${cloneA}" && git remote set-url origin "${origin}" )

	## pr needs gh; syntax errors surface without it doing anything
	fAssertFail "pr with bad number rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q pr bogus"
	fAssertFail "pr ok with no number rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q pr ok"

	## land with an upstream-less target: the merge must reach origin before the remote work branch dies
	local fx2="${work}/$1-land2"
	local o2="${fx2}/origin.git"; local c2="${fx2}/a"; local c3="${fx2}/b"
	mkdir -p "${fx2}"
	git init --quiet --bare -b main "${o2}"
	git clone --quiet "${o2}" "${c2}" 2>/dev/null
	(
		cd "${c2}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev  ## local-only dev: no upstream
		git checkout --quiet -b feat9; git push --quiet -u origin feat9
		echo work > w.txt; git add --all; git commit --quiet -m "work"; git push --quiet
	)
	fAssert "br land with upstream-less dev runs"      bash -c "cd '${c2}' && '${gitsby}' -q br land 'merge feat9'"
	fAssert "merge reached origin (dev published)"  bash -c "cd '${o2}' && git show-ref --verify --quiet refs/heads/dev && git ls-tree --name-only dev | grep -qx w.txt"
	fAssert "feat9 deleted on origin after publish" bash -c "cd '${o2}' && ! git show-ref --verify --quiet refs/heads/feat9"

	## release with an upstream-less main: the branch must reach origin, not just the tag
	local fx3="${work}/$1-rel2"
	local o5="${fx3}/origin.git"; local c5="${fx3}/a"
	mkdir -p "${fx3}"
	git init --quiet --bare -b main "${o5}"
	git clone --quiet "${o5}" "${c5}" 2>/dev/null
	(
		cd "${c5}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev; git push --quiet -u origin dev
		echo d > d.txt; git add --all; git commit --quiet -m "dev work"; git push --quiet
		git branch --unset-upstream main  ## however it got lost, main now tracks nothing
	)
	fAssert "release with an upstream-less main runs"  bash -c "cd '${c5}' && '${gitsby}' -q release 9.0.0"
	fAssert "origin main advanced, not just the tag"   bash -c "cd '${o5}' && git ls-tree --name-only main | grep -qx d.txt"
	fAssert "tag reached origin too"                   bash -c "cd '${c5}' && git ls-remote --tags origin | grep -q 'refs/tags/v9.0.0'"

	## diverged pull with a dirty tree: fails, but work stays in the tree and out of the stash
	git clone --quiet "${o2}" "${c3}"
	( cd "${c3}" && git checkout --quiet dev && echo remote >> f.txt && git add --all && git commit --quiet -m "remote side" && git push --quiet )
	( cd "${c2}" && echo localc > localc.txt && git add --all && git commit --quiet -m "local side" && echo precious >> w.txt )
	fAssertFail "diverged update fails"      bash -c "cd '${c2}' && '${gitsby}' -q update 'local work'"
	fAssert "the work is still there"        bash -c "cd '${c2}' && grep -q precious w.txt"
	fAssert "nothing stranded in the stash"  bash -c "cd '${c2}' && [[ -z \"\$(git stash list)\" ]]"
	fAssertOut    "pull failure reads plainly"   'failed \(exit' bash -c "cd '${c2}' && '${gitsby}' -q update"
	fAssertNotOut "no trap dump on git failure"  'Signal \.'     bash -c "cd '${c2}' && '${gitsby}' -q update"

	## An unreachable remote must not turn a good commit into a failed command - update is the
	## only way to commit now. A bogus local path fails instantly, so this needs no network.
	local off="${work}/$1-offline"
	git clone --quiet "${origin}" "${off}" 2>/dev/null
	( cd "${off}" && git remote set-url origin "${work}/nosuch-remote.git" && echo offline > off.txt )
	fAssert    "update succeeds with an unreachable remote"  bash -c "cd '${off}' && '${gitsby}' -q update 'offline work'"
	fAssert    "the work was committed anyway"               bash -c "cd '${off}' && git log -1 --format=%s | grep -qx 'offline work'"
	fAssertOut "and it says why it skipped the pull"  'remote unreachable' bash -c "cd '${off}' && echo more > more.txt && '${gitsby}' -q update 'more offline work'"
	## --no-fetch means offline on purpose: commit, and don't reach for the network at all
	## -NoFetch, not --no-fetch: pwsh has no such parameter and would fail, and the old pattern
	## matched its complaint about the flag - green for the wrong reason. Bash takes either.
	fAssertOut "no-fetch skips the pull too"  'Skipping the pull' bash -c "cd '${off}' && echo nf > nf.txt && '${gitsby}' -q -NoFetch update 'no-fetch work'"

	## A command that still means something locally runs offline and says what it skipped; a
	## command that exists to publish refuses up front, before the plan promises a push.
	## Same bogus-path trick, on its own clone so the shared fixture keeps its history.
	## Own throwaway origin: by this point the shared one has a dev branch and release history, so
	## the merge target would not be main and these checks would be reading a different repo shape.
	## 'offland' is made and published while the remote still works, so the land below has a real
	## origin copy to leave alone; everything after the set-url is offline.
	local offOrigin="${work}/$1-offo.git"; local offb="${work}/$1-offlinebr"
	git init --quiet --bare -b main "${offOrigin}"
	git clone --quiet "${offOrigin}" "${offb}" 2>/dev/null
	(
		cd "${offb}"
		echo one > f.txt && git add --all && git commit --quiet -m "initial" && git push --quiet -u origin main
		git checkout --quiet -b offland && echo ol > ol.txt && git add --all && git commit --quiet -m "off work" && git push --quiet -u origin offland
		git checkout --quiet main && git remote set-url origin "${work}/nosuch-remote.git"
	)
	fAssert    "br create succeeds with an unreachable remote"  bash -c "cd '${offb}' && '${gitsby}' -q br create offfeat && [[ \"\$(git branch --show-current)\" == offfeat ]]"
	fAssertOut "and says the branch is local only"  "'offfeat2' is local only"  bash -c "cd '${offb}' && '${gitsby}' -q br create offfeat2 2>&1"
	fAssertOut "and warns once, above the prompt"   'nothing will be pushed'   bash -c "cd '${offb}' && '${gitsby}' -q br switch offfeat 2>&1"
	fAssert    "br switch succeeds with an unreachable remote"  bash -c "cd '${offb}' && '${gitsby}' -q br switch main && [[ \"\$(git branch --show-current)\" == main ]]"
	## The publishing commands refuse instead, and name what to do about it. Checked before the
	## land below, since that one leaves the tree clean and 'sync' needs something to refuse over.
	fAssertFail "sync refuses with an unreachable remote"   bash -c "cd '${offb}' && echo s > s.txt && '${gitsby}' -q sync 'nope'"
	fAssertOut  "and points at update"  "Commit locally with '[^']*update'"   bash -c "cd '${offb}' && '${gitsby}' -q sync 'nope' 2>&1"
	fAssert     "and it refused before committing anything"  bash -c "cd '${offb}' && git status --porcelain | grep -q 's.txt' && rm -f '${offb}/s.txt'"
	fAssertFail "release refuses with an unreachable remote"  bash -c "cd '${offb}' && '${gitsby}' -q release v9.9.9"
	fAssertOut  "and says so before cutting a tag"  "'release' has nothing left to do"  bash -c "cd '${offb}' && '${gitsby}' -q release v9.9.9 2>&1"
	fAssert     "and no tag was cut"  bash -c "cd '${offb}' && ! git rev-parse -q --verify refs/tags/v9.9.9 >/dev/null"
	fAssertFail "pr create refuses with an unreachable remote"  bash -c "cd '${offb}' && '${gitsby}' -q br switch offfeat >/dev/null 2>&1; '${gitsby}' -q pr create 'T'"
	fAssertOut  "and says which command needs origin"  "'pr create' has nothing left to do"  bash -c "cd '${offb}' && '${gitsby}' -q pr create 'T' 2>&1"
	## land offline: the merge lands locally, and origin's copy of the branch has to survive -
	## with the merge unpushed it is the only ref origin holds to that work.
	fAssertOut "br land leaves origin's copy of the branch alone"  "Leaving origin's 'offland' alone"  bash -c "cd '${offb}' && '${gitsby}' -q br switch offland >/dev/null 2>&1; '${gitsby}' -q br land 'Off land' 2>&1"
	fAssert    "and the merge landed locally"     bash -c "cd '${offb}' && git log -1 --format=%s main | grep -q 'Off land'"
	fAssert    "and the remote-tracking ref survived"  bash -c "cd '${offb}' && git show-ref --verify --quiet refs/remotes/origin/offland"

	## Offline messages have to be true. A park with nothing to push says so instead of claiming
	## committed work awaits; the warning names the branch it means, since the command may move
	## off it next and a 'sync' from wherever you land would publish that branch instead; and a
	## hotfix land names the recovery that publishes the default branch - a bare 'sync' runs
	## from dev after the back-merge and would leave origin's default branch stale.
	local om="${work}/$1-offmsg.git"; local omw="${work}/$1-offmsgw"
	git init --quiet --bare -b main "${om}"
	git clone --quiet "${om}" "${omw}" 2>/dev/null
	(
		cd "${omw}"
		echo one > f.txt && git add --all && git commit --quiet -m "initial" && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b b1 && git push --quiet -u origin b1
		git remote set-url origin "${work}/nosuch-remote.git"
	)
	fAssertOut    "an in-sync branch parks offline with nothing to push"  'Nothing to push'    bash -c "cd '${omw}' && '${gitsby}' -q br switch dev 2>&1"
	fAssertNotOut "and no warning claims work awaits publishing"         'skipping the push'  bash -c "cd '${omw}' && git checkout --quiet b1 && '${gitsby}' -q br switch dev 2>&1"
	fAssertOut    "an ahead branch's park warning names the branch"      "stays local on 'b1'"  bash -c "cd '${omw}' && git checkout --quiet b1 && echo w >> f.txt && '${gitsby}' -q br switch dev 2>&1"
	fAssert    "br hotfix works offline"  bash -c "cd '${omw}' && git checkout --quiet main && '${gitsby}' -q br hotfix hx1 && [[ \"\$(git branch --show-current)\" == hotfix/hx1 ]]"
	fAssertOut "an offline hotfix land names the branch its merge is stuck on"  "the merge to 'main' is local only - once online"  bash -c "cd '${omw}' && echo h >> f.txt && '${gitsby}' -q br land 'Hot fix' 2>&1"
	fAssert    "and the back-merge still carried it to dev"  bash -c "cd '${omw}' && [[ \"\$(git branch --show-current)\" == dev ]] && git merge-base --is-ancestor main dev"

	## ... and offline has to mean the same thing inside a compound command, or the flag saves
	## nothing there. Own throwaway origin, so the shared one keeps its history for later checks.
	local nfOrigin="${work}/$1-nfo.git"; local nfPeer="${work}/$1-nfa"; local nfWork="${work}/$1-nfb"
	git init --quiet --bare -b main "${nfOrigin}"
	git clone --quiet "${nfOrigin}" "${nfPeer}" 2>/dev/null
	( cd "${nfPeer}" && echo one > f.txt && git add --all && git commit --quiet -m "initial" && git push --quiet -u origin main )
	git clone --quiet "${nfOrigin}" "${nfWork}" 2>/dev/null
	( cd "${nfPeer}" && echo two >> f.txt && git commit --quiet -a -m "peer work" && git push --quiet )
	( cd "${nfWork}" && git rev-parse main > "${work}/$1-nfsha" )
	fAssert "br switch -NoFetch skips its pull"    bash -c "cd '${nfWork}' && '${gitsby}' -q -NoFetch br switch main && [[ \"\$(git rev-parse main)\" == \"\$(cat '${work}/$1-nfsha')\" ]]"
	fAssert "the same switch pulls when online"    bash -c "cd '${nfWork}' && '${gitsby}' -q br switch main && [[ \"\$(git rev-parse main)\" != \"\$(cat '${work}/$1-nfsha')\" ]]"

	## br prune: drops what's already landed, keeps everything else. Own throwaway origin, since
	## it deletes branches wholesale and the shared fixture still needs its history.
	local prOrigin="${work}/$1-pro.git"; local prWork="${work}/$1-prw"
	git init --quiet --bare -b main "${prOrigin}"
	git clone --quiet "${prOrigin}" "${prWork}" 2>/dev/null
	(
		cd "${prWork}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev; git push --quiet -u origin dev
		for b in landed abandoned; do
			git checkout --quiet -b "${b}" dev; echo "${b}" > "${b}.txt"; git add --all
			git commit --quiet -m "${b}"; git push --quiet -u origin "${b}"
		done
		git checkout --quiet -b wip dev; echo wip > wip.txt; git add --all
		git commit --quiet -m wip; git push --quiet -u origin wip
		git checkout --quiet dev
		git merge --quiet --no-ff landed    -m "merge landed"
		git merge --quiet --no-ff abandoned -m "merge abandoned"
		git push --quiet
	)
	fAssertPlan "br prune plans the merged branches"  'git branch -D landed'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	fAssert     "merged branch gone locally"       bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/landed"
	fAssert     "the other merged one too"         bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/abandoned"
	fAssert     "merged branch gone on origin"     bash -c "cd '${prOrigin}' && ! git show-ref --verify --quiet refs/heads/landed"
	fAssert     "unmerged branch kept locally"     bash -c "cd '${prWork}' && git show-ref --verify --quiet refs/heads/wip"
	fAssert     "unmerged branch kept on origin"   bash -c "cd '${prOrigin}' && git show-ref --verify --quiet refs/heads/wip"
	fAssert     "protected branches kept"          bash -c "cd '${prWork}' && git show-ref --verify --quiet refs/heads/dev && git show-ref --verify --quiet refs/heads/main"
	fAssertOut  "and it says what it kept"  'Keeping \(not merged yet\): wip'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	fAssertOut  "nothing left to prune is a no-op"  'Nothing to prune'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	fAssert     "br clean aliases br prune"        bash -c "cd '${prWork}' && '${gitsby}' -q br clean"
	fAssertFail "br prune with an argument rejected"  bash -c "cd '${prWork}' && '${gitsby}' -q br prune wip"
	fAssertFail "the internal br-prune token rejected"  bash -c "cd '${prWork}' && '${gitsby}' -q br-prune"
	## The branch you're standing on can't be deleted out from under you, merged or not.
	( cd "${prWork}" && git checkout --quiet -b standing dev && git push --quiet -u origin standing )
	fAssert     "current branch survives its own prune"  bash -c "cd '${prWork}' && '${gitsby}' -q br prune; git -C '${prWork}' show-ref --verify --quiet refs/heads/standing"
	## And it must say WHY nothing happened - "no branch is merged" would be false here.
	fAssertOut  "and the output says why"  "switch off it to prune it"  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	## A merge that hasn't reached origin means origin still holds the only ref to that work:
	## the local branch may go, the remote copy may not.
	(
		cd "${prWork}"
		git checkout --quiet dev
		git checkout --quiet -b unpushed dev; echo u > u.txt; git add --all
		git commit --quiet -m unpushed; git push --quiet -u origin unpushed
		git checkout --quiet dev; git merge --quiet --no-ff unpushed -m "merge unpushed"
	)
	fAssert "local branch pruned on an unpushed merge"  bash -c "cd '${prWork}' && '${gitsby}' -q -NoFetch br prune && ! git show-ref --verify --quiet refs/heads/unpushed"
	fAssert "but origin keeps its copy"                bash -c "cd '${prOrigin}' && git show-ref --verify --quiet refs/heads/unpushed"
	## A branch that was never pushed has no upstream, so 'git branch -d' checks it against HEAD
	## and refuses from anywhere else, however merged it is. Standing off the target on purpose.
	(
		cd "${prWork}"
		git checkout --quiet dev
		git checkout --quiet -b localonly dev; echo lo > lo.txt; git add --all; git commit --quiet -m localonly
		git checkout --quiet dev; git merge --quiet --no-ff localonly -m "merge localonly"; git push --quiet
		git checkout --quiet wip
	)
	fAssertOut "merged local-only branch pruned, and counted"  'Pruned 1 local, 0 on origin'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	fAssert    "the local-only branch is gone"          bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/localonly"
	fAssert    "pruned from a branch that doesn't contain it"  bash -c "cd '${prWork}' && [[ \"\$(git branch --show-current)\" == wip ]]"

	## clone: derives the dir, checks out dev when the repo has one, no-op re-run, collision guards
	local cl="${work}/$1-clone"
	mkdir -p "${cl}"
	fAssert "repo clone runs"                bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${origin}' cl1"
	fAssert "repo clone checked out dev"     bash -c "cd '${cl}/cl1' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert "repo clone again (already cloned) ok"  bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${origin}' cl1"
	fAssert "repo clone derives dir from url"       bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${origin}' && [[ -d origin/.git ]]"
	fAssertFail "repo clone into non-empty dir rejected"  bash -c "cd '${cl}' && mkdir -p other && touch other/x && '${gitsby}' -q repo clone '${origin}' other"
	fAssertFail "repo clone with no url rejected"         bash -c "cd '${cl}' && '${gitsby}' -q repo clone"
	## a repo without dev stays on the default branch; a pre-existing empty dir is fine; a clone of a different url is refused
	local o3="${cl}/nodev.git"
	git init --quiet --bare -b main "${o3}"
	git clone --quiet "${o3}" "${cl}/nodev-seed" 2>/dev/null
	( cd "${cl}/nodev-seed" && echo n > n.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main )
	fAssert "repo clone of a no-dev repo stays on default"  bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${o3}' nd && [[ \"\$(cd nd && git branch --show-current)\" == main ]]"
	fAssert "repo clone into a pre-existing empty dir"      bash -c "cd '${cl}' && mkdir -p pre && '${gitsby}' -q repo clone '${origin}' pre && [[ -d pre/.git ]]"
	fAssertFail "repo clone over a different-url clone refused"  bash -c "cd '${cl}' && '${gitsby}' -q repo clone '${o3}' cl1"

	## connect: publish a local-only repo to a fresh empty remote; idempotent; guards
	local cn="${work}/$1-connect"
	mkdir -p "${cn}"
	git init --quiet --bare -b main "${cn}/remote.git"
	git init --quiet -b main "${cn}/proj"
	( cd "${cn}/proj" && echo hi > hi.txt && git add --all && git commit --quiet -m "init" )
	fAssert "repo connect pushes to an empty remote"  bash -c "cd '${cn}/proj' && '${gitsby}' -q repo connect '${cn}/remote.git'"
	fAssert "remote got the commit"              bash -c "cd '${cn}/remote.git' && git ls-tree --name-only main | grep -qx hi.txt"
	fAssert "repo connect set the upstream"           bash -c "cd '${cn}/proj' && git rev-parse --abbrev-ref '@{u}' >/dev/null"
	fAssert "repo connect again (nothing to do) ok"   bash -c "cd '${cn}/proj' && '${gitsby}' -q repo connect"
	fAssert "repo connect commits then pushes new work"  bash -c "cd '${cn}/proj' && echo more > more.txt && '${gitsby}' -q repo connect && cd '${cn}/remote.git' && git ls-tree --name-only main | grep -qx more.txt"
	fAssertFail "repo connect different url rejected"    bash -c "cd '${cn}/proj' && '${gitsby}' -q repo connect '${cn}/other.git'"

	## connect from a plain directory: init + commit + push in one
	git init --quiet --bare -b main "${cn}/remote2.git"
	mkdir -p "${cn}/plain"; echo data > "${cn}/plain/data.txt"
	fAssert "repo connect from a non-repo dir"  bash -c "cd '${cn}/plain' && '${gitsby}' -q repo connect '${cn}/remote2.git'"
	fAssert "plain dir now a pushed repo"  bash -c "cd '${cn}/plain' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"

	## The one command that hands a whole directory over has to say what is in it first, and the
	## list has to be git's answer, not a directory walk - anything else names files 'git add --all'
	## will skip. Own TMPDIR so the throwaway git dir it asks through can be shown to be cleaned up
	## (both builds honor TMPDIR for their temp path).
	git init --quiet --bare -b main "${cn}/remote3.git"
	local pubDir="${cn}/publish"; local pubTmp="${cn}/publish-tmp"
	mkdir -p "${pubDir}/sub" "${pubDir}/skipdir" "${pubTmp}"
	echo keep    > "${pubDir}/keep.txt"
	echo TOKEN=x > "${pubDir}/.env"
	echo nested  > "${pubDir}/sub/nested.txt"
	echo noise   > "${pubDir}/skipme.log"
	echo noise   > "${pubDir}/skipdir/thing.js"
	printf '*.log\nskipdir/\n' > "${pubDir}/.gitignore"
	fAssertOut    "repo connect lists the files it will publish"  'Files to publish:'  bash -c "cd '${pubDir}' && TMPDIR='${pubTmp}' '${gitsby}' -q repo connect '${cn}/remote3.git' 2>&1"
	fAssert       "the listing probe cleaned up after itself"     bash -c "[[ -z \"\$(ls -A '${pubTmp}')\" ]]"
	fAssert       "and the dotfile went up, as the listing said"  bash -c "cd '${cn}/remote3.git' && git ls-tree -r --name-only main | grep -qx '\.env'"
	fAssert       "and the ignored file did not"                  bash -c "cd '${cn}/remote3.git' && ! git ls-tree -r --name-only main | grep -q 'skipme.log'"
	## The list itself, line by line, on a fresh copy of the same tree: the stray dotfile is the
	## point of the feature, and an ignored file appearing would make the whole list untrustworthy.
	local pub2="${cn}/publish2"
	mkdir -p "${pub2}"; cp -r "${pubDir}/." "${pub2}/"; rm -rf "${pub2}/.git"
	git init --quiet --bare -b main "${cn}/remote4.git"
	fAssertOut    "the listing names a stray dotfile"  '^    \.env$'  bash -c "cd '${pub2}' && '${gitsby}' -q repo connect '${cn}/remote4.git' 2>&1"
	local pub3="${cn}/publish3"
	mkdir -p "${pub3}"; cp -r "${pubDir}/." "${pub3}/"; rm -rf "${pub3}/.git"
	git init --quiet --bare -b main "${cn}/remote5.git"
	fAssertNotOut "the listing honors .gitignore"  'skipme\.log|skipdir'  bash -c "cd '${pub3}' && '${gitsby}' -q repo connect '${cn}/remote5.git' 2>&1"

	## connect refuses remotes with history, unreachable remotes, and empty dirs
	git init --quiet -b main "${cn}/proj2"
	( cd "${cn}/proj2" && echo x > x.txt && git add --all && git commit --quiet -m "x" )
	fAssertFail "repo connect to nonempty remote rejected"  bash -c "cd '${cn}/proj2' && '${gitsby}' -q repo connect '${cn}/remote2.git'"
	fAssertFail "repo connect to missing remote rejected"   bash -c "cd '${cn}/proj2' && '${gitsby}' -q repo connect '${cn}/nosuch.git'"
	fAssertFail "repo connect in an empty dir rejected"     bash -c "mkdir -p '${cn}/empty' && cd '${cn}/empty' && '${gitsby}' -q repo connect '${cn}/remote.git'"
	## an inited repo with no commit and no files is nothing to connect; a matching explicit url re-connects fine (push mode)
	git init --quiet -b main "${cn}/bare-repo"
	fAssertFail "repo connect an empty inited repo rejected"  bash -c "cd '${cn}/bare-repo' && '${gitsby}' -q repo connect '${cn}/remote.git'"
	fAssert "repo connect accepts a matching explicit url"    bash -c "cd '${cn}/proj' && '${gitsby}' -q repo connect '${cn}/remote.git'"

	## The SSH identity line. Every other check here uses a local-path origin, which has no ssh
	## identity at all - so this whole line went out untested and shipped naming the OS login.
	## A fake ssh gives it an scp-like origin to read without leaving the box: -G defaults 'user'
	## to the OS login when the target carries none (the real behaviour, and the whole bug),
	## -T greets as the key's account, and anything else fails so git's own fetch reports offline.
	local sid="${work}/$1-sshid"
	mkdir -p "${sid}/bin"
	cat > "${sid}/bin/ssh" <<-'EOF'
		#!/usr/bin/env bash
		[[ -n "${FAKE_SSH_LOG:-}" ]] && echo "$*" >> "${FAKE_SSH_LOG}"
		target="${*: -1}"
		case "$1" in
			-G) if [[ "${target}" == *@* ]]; then printf 'user %s\n' "${target%%@*}"; else printf 'user %s\n' "osuser"; fi
			    printf 'hostname %s\n' "${FAKE_SSH_HOSTNAME:-github.com}"
			    printf 'identityfile %s\n' "${FAKE_SSH_KEY:-/etc/hostname}"
			    exit 0 ;;
			-T) echo "Hi ${FAKE_SSH_LOGIN:-acmedev}! You've successfully authenticated, but GitHub does not provide shell access." >&2; exit 1 ;;
		esac
		exit 255
	EOF
	chmod +x "${sid}/bin/ssh"
	local sidp="${sid}/bin:${PATH}"
	git init --quiet -b main "${sid}/proj"
	( cd "${sid}/proj" && echo s > s.txt && git add --all && git commit --quiet -m init && git remote add origin git@github.com:acme/api.git )
	local sidRun="cd '${sid}/proj' && PATH='${sidp}'"
	## The account the key authenticates as is the question this line exists to answer, so it
	## leads. The old line answered with the OS login, which is neither that nor the connect user.
	fAssertOut    "ssh line names the account the key authenticates as"  "SSH \.+: acmedev \("  bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	## Anchored to the SSH line: a bare 'git@github.com' also matches the Remote line right above
	## it, so the loose form was satisfied by the broken output too.
	fAssertOut    "ssh line names the user git actually connects as"     "SSH \.+: .*\(git@github\.com,"  bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	fAssertNotOut "ssh line never reports the OS login"                  'osuser'               bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	fAssertOut    "the key is still reported"                            'key /etc/hostname'    bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	fAssertOut    "a mutating pre-flight names the account too"          "SSH \.+: acmedev \("  bash -c "${sidRun} '${gitsby}' -q -NoFetch update 'ssh id probe' 2>&1"
	## A host alias is the case the line was added for: ~/.ssh/config hides the real host and key.
	git -C "${sid}/proj" remote set-url origin git@gh-acme:acme/api.git
	fAssertOut "an ssh config alias is named alongside the real host"  "via alias 'gh-acme'"  bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	git -C "${sid}/proj" remote set-url origin git@github.com:acme/api.git
	## Offline (the fetch failed): say we don't know rather than guess, and don't spend the
	## round trip finding out. Asserting the log is what proves the probe was actually skipped.
	fAssertOut "an unreachable remote leaves the account unknown"  "SSH \.+: unknown \(git@github\.com"  bash -c "${sidRun} '${gitsby}' -q status"
	fAssert    "and no identity round trip was attempted"  bash -c "${sidRun} FAKE_SSH_LOG='${sid}/log' '${gitsby}' -q status >/dev/null 2>&1; ! grep -q -- '-T' '${sid}/log'"

	## The pre-command fetch must never sit and ask for credentials: it runs before any of our
	## own checks, so an https remote you can't authenticate to would block every command.
	## A git shim records the env the fetch actually got - the only way to see this without a tty.
	local tp="${work}/$1-tprompt"
	mkdir -p "${tp}/bin"
	cat > "${tp}/bin/git" <<-EOF
		#!/usr/bin/env bash
		[[ "\$1" == "fetch" ]] && echo "\${GIT_TERMINAL_PROMPT-UNSET}" >> "\${TPROMPT_LOG}"
		exec "$(command -v git)" "\$@"
	EOF
	chmod +x "${tp}/bin/git"
	git init --quiet -b main "${tp}/proj"
	## Origin is a dead local path, not an https URL: the assert reads the env the fetch got,
	## so it needs no real server, and the suite stays off the network.
	( cd "${tp}/proj" && echo t > t.txt && git add --all && git commit --quiet -m init && git remote add origin "${tp}/nosuch.git" )
	fAssert "the pre-command fetch disables credential prompts"  bash -c "cd '${tp}/proj' && TPROMPT_LOG='${tp}/log' PATH='${tp}/bin:${PATH}' '${gitsby}' -q status >/dev/null 2>&1; grep -qx 0 '${tp}/log'"

	## owner/name targets: the gh path, driven by a deterministic fake gh (no network). Covers
	## 'repo create' (repo absent), 'repo connect' remote-add (present but empty, https + ssh),
	## the refuse-nonempty guard, and the create/connect division of labour. Add-mode github URLs are rewritten onto a local bare via insteadOf so
	## the push lands offline; create-mode wiring is done inside the stub.
	local gh="${work}/$1-gh"
	mkdir -p "${gh}/bin"
	cat > "${gh}/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
## Test stub: deterministic gh, no network. Behavior driven by FAKE_GH_* env.
## GH_TOKEN is logged too: that is how a check sees which account the run picked for the remote.
[[ -n "${FAKE_GH_LOG:-}" ]] && echo "$* [GH_TOKEN=${GH_TOKEN:-}]" >> "${FAKE_GH_LOG}"
case "$1 $2" in
	"api user")    echo "${FAKE_GH_LOGIN:-ghuser}" ;;  ## whose token gh is holding
	"auth token")  ## accounts gh holds, space separated; exit 1 for anyone else, like the real thing
	               case " ${FAKE_GH_ACCOUNTS:-} " in *" $4 "*) echo "tok_$4" ;; *) exit 1 ;; esac ;;
	"repo view")   case "${FAKE_GH_VIEW:-}" in notfound) exit 1 ;; empty) echo true ;; nonempty) echo false ;; esac ;;
	"config get")  echo "${FAKE_GH_PROTO:-https}" ;;
	"pr list")     echo "${FAKE_GH_EXISTING:-}" ;;  ## an already-open PR number for this branch, or nothing
	"pr create")   echo "https://github.com/me/proj/pull/${FAKE_GH_NEWPR:-1}" ;;
	"pr review")   : ;;  ## gitsby treats approval as best-effort; nothing to fake
	"pr view")     echo "${FAKE_GH_HEAD:-$(git branch --show-current)}" ;;  ## the PR's own head branch
	"pr merge")    ## Land the branch on the base, then drop it from the remote. Real gh does the delete
	               ## over the API, so the caller's origin/* copy survives it - restore the ref to match.
	               ## FAKE_GH_HEAD lets a check merge a PR whose branch isn't the one we're standing on.
	               ## It merges what ORIGIN holds, not the local branch - the whole point of the
	               ## unpushed-commit guard - and deletes the local copy too, with -D, like gh does.
	               prBranch="${FAKE_GH_HEAD:-$(git branch --show-current)}"
	               prKeep="$(git rev-parse "refs/remotes/origin/${prBranch}")"
	               git push --quiet origin "${prKeep}:refs/heads/${FAKE_GH_BASE:-dev}"
	               git push --quiet origin --delete "${prBranch}"
	               git update-ref "refs/remotes/origin/${prBranch}" "${prKeep}"
	               [[ "${prBranch}" != "$(git branch --show-current)" ]] && git branch -D "${prBranch}" >/dev/null
	               : ;;
	"repo create") git init --quiet --bare -b main "${FAKE_GH_REMOTE}"
	               git remote add origin "${FAKE_GH_REMOTE}"
	               git push --quiet -u origin HEAD ;;
	*) echo "fake gh: unhandled: $*" >&2; exit 2 ;;
esac
GHEOF
	chmod +x "${gh}/bin/gh"
	## An ssh-protocol connect now probes the identity of the url it is about to set, so this dir
	## needs an ssh too - otherwise the suite would ask the real github.com who we are. Answers with
	## the same login the fake gh reports, so these checks see a match and carry on.
	cat > "${gh}/bin/ssh" <<-'EOF'
		#!/usr/bin/env bash
		## Scan rather than index $1: the probe now prefixes git's own core.sshCommand arguments,
		## so -T is not necessarily first. A keyed probe answers as that key's owner, which is how
		## a check proves the configured key was the one used.
		mode=""; key=""
		while [[ $# -gt 0 ]]; do
			case "$1" in
				-G) mode=G ;;
				-T) mode=T ;;
				-i) key="$2"; shift ;;
			esac
			shift
		done
		[[ "${mode}" == "G" ]] && { printf 'user git\nhostname github.com\n'; exit 0; }
		if [[ "${mode}" == "T" ]]; then
			login="${FAKE_SSH_LOGIN:-${FAKE_GH_LOGIN:-ghuser}}"
			[[ -n "${key}" ]] && login="$(basename "${key}")"
			echo "Hi ${login}! You've successfully authenticated, but GitHub does not provide shell access."
			exit 1
		fi
		exit 0
	EOF
	chmod +x "${gh}/bin/ssh"
	local ghp="${gh}/bin:${PATH}"

	## create: repo doesn't exist yet -> gitsby inits + commits, the stub creates and pushes
	mkdir -p "${gh}/create"; echo c > "${gh}/create/c.txt"
	fAssert "repo create makes a missing repo"  bash -c "cd '${gh}/create' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/created.git' FAKE_GH_LOG='${gh}/create.log' '${gitsby}' -q repo create me/proj"
	fAssert "created repo got the commit"                bash -c "cd '${gh}/created.git' && git ls-tree --name-only main | grep -qx c.txt"
	fAssert "create defaulted to a private repo"         bash -c "grep -q -- '--private' '${gh}/create.log'"
	mkdir -p "${gh}/pub"; echo p > "${gh}/pub/p.txt"
	if [[ "$1" == "bash" ]]; then  ## visibility flag spelled per implementation
		fAssert "repo create --public makes a public repo"  bash -c "cd '${gh}/pub' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/pub.git' FAKE_GH_LOG='${gh}/pub.log' '${gitsby}' -q --public repo create me/proj && grep -q -- '--public' '${gh}/pub.log'"
	else
		fAssert "repo create -Public makes a public repo"   bash -c "cd '${gh}/pub' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/pub.git' FAKE_GH_LOG='${gh}/pub.log' '${gitsby}' -q -Public repo create me/proj && grep -q -- '--public' '${gh}/pub.log'"
	fi

	## add: repo exists but is empty -> gitsby builds the URL from git_protocol and pushes to it
	git init --quiet --bare -b main "${gh}/backing-https.git"
	printf '[url "%s"]\n\tinsteadOf = https://github.com/me/proj.git\n' "${gh}/backing-https.git" > "${gh}/gc-https"
	mkdir -p "${gh}/add-https"; ( cd "${gh}/add-https" && git init --quiet -b main && echo h > h.txt && git add --all && git commit --quiet -m init )
	fAssert "repo connect owner/name adds an https remote to an empty repo"  bash -c "cd '${gh}/add-https' && PATH='${ghp}' FAKE_GH_VIEW=empty FAKE_GH_PROTO=https GIT_CONFIG_GLOBAL='${gh}/gc-https' '${gitsby}' -q repo connect me/proj"
	fAssert "https url recorded as origin"  bash -c "cd '${gh}/add-https' && [[ \"\$(git remote get-url origin)\" == 'https://github.com/me/proj.git' ]]"
	fAssert "empty repo received the push"  bash -c "cd '${gh}/backing-https.git' && git ls-tree --name-only main | grep -qx h.txt"
	git init --quiet --bare -b main "${gh}/backing-ssh.git"
	printf '[url "%s"]\n\tinsteadOf = git@github.com:me/proj.git\n' "${gh}/backing-ssh.git" > "${gh}/gc-ssh"
	mkdir -p "${gh}/add-ssh"; ( cd "${gh}/add-ssh" && git init --quiet -b main && echo s > s.txt && git add --all && git commit --quiet -m init )
	fAssert "ssh protocol builds an scp-style origin url"  bash -c "cd '${gh}/add-ssh' && PATH='${ghp}' FAKE_GH_VIEW=empty FAKE_GH_PROTO=ssh GIT_CONFIG_GLOBAL='${gh}/gc-ssh' '${gitsby}' -q repo connect me/proj && [[ \"\$(git remote get-url origin)\" == 'git@github.com:me/proj.git' ]]"

	## reject: repo already has commits
	mkdir -p "${gh}/reject"; ( cd "${gh}/reject" && git init --quiet -b main && echo r > r.txt && git add --all && git commit --quiet -m init )
	fAssertFail "repo connect owner/name refuses a nonempty repo"  bash -c "cd '${gh}/reject' && PATH='${ghp}' FAKE_GH_VIEW=nonempty '${gitsby}' -q repo connect me/proj"
	fAssertFail "repo create refuses a nonempty repo"              bash -c "cd '${gh}/reject' && PATH='${ghp}' FAKE_GH_VIEW=nonempty '${gitsby}' -q repo create me/proj"

	## the division of labour: connect never creates, create never adopts something that already exists
	mkdir -p "${gh}/split"; ( cd "${gh}/split" && git init --quiet -b main && echo x > x.txt && git add --all && git commit --quiet -m init )
	fAssertFail "repo connect refuses a target that doesn't exist yet"  bash -c "cd '${gh}/split' && PATH='${ghp}' FAKE_GH_VIEW=notfound '${gitsby}' -q repo connect me/proj"
	fAssertOut  "and points at repo create"  'repo create me/proj'      bash -c "cd '${gh}/split' && PATH='${ghp}' FAKE_GH_VIEW=notfound '${gitsby}' -q repo connect me/proj 2>&1 || true"
	fAssertFail "repo create refuses an existing empty repo"            bash -c "cd '${gh}/split' && PATH='${ghp}' FAKE_GH_VIEW=empty '${gitsby}' -q repo create me/proj"
	fAssertOut  "and points at repo connect"  'repo connect me/proj'    bash -c "cd '${gh}/split' && PATH='${ghp}' FAKE_GH_VIEW=empty '${gitsby}' -q repo create me/proj 2>&1 || true"
	fAssertFail "repo create refuses a plain url"                       bash -c "cd '${gh}/split' && PATH='${ghp}' '${gitsby}' -q repo create '${gh}/backing-https.git'"
	## Keep the insteadOf rewrite: this dir's origin is a real github.com URL, and the
	## pre-command fetch runs before the refusal we're testing for.
	fAssertFail "repo create refuses when origin is already set"        bash -c "cd '${gh}/add-https' && PATH='${ghp}' GIT_CONFIG_GLOBAL='${gh}/gc-https' '${gitsby}' -q repo create me/proj"
	fAssertFail "repo create with no target rejected"                   bash -c "cd '${gh}/split' && PATH='${ghp}' '${gitsby}' -q repo create"

	## pr ok run from the PR's own branch: gh deletes the branch on the remote but leaves our
	## origin/* copy, so the upstream still looks alive and pulling it can only fail.
	mkdir -p "${gh}/prok"
	git init --quiet --bare -b main "${gh}/prok/origin.git"
	local prc="${gh}/prok/c"
	git clone --quiet "${gh}/prok/origin.git" "${prc}" 2>/dev/null
	(
		cd "${prc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b prfeat && echo work > work.txt && git add --all && git commit --quiet -m work
		git push --quiet -u origin prfeat
	)
	fAssertPlan "pr ok plans the branch switch"  'git checkout dev'  bash -c "cd '${prc}' && PATH='${ghp}' FAKE_GH_BASE=dev '${gitsby}' -q pr ok 7"
	fAssert    "pr ok landed on the merge target"  bash -c "cd '${prc}' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert    "pr ok pulled the merged work"      bash -c "cd '${prc}' && git ls-tree --name-only dev | grep -qx work.txt"
	fAssert    "the merged branch is gone from origin"  bash -c "cd '${prc}' && ! git ls-remote --heads origin prfeat | grep -q prfeat"

	## 'pr ok <n>' from dev is the routine case, and gh deletes the PR's branch with 'branch -D'
	## either way - so unpushed commits on it have to be caught even when we aren't standing there.
	mkdir -p "${gh}/prx"
	git init --quiet --bare -b main "${gh}/prx/origin.git"
	local prx="${gh}/prx/c"
	git clone --quiet "${gh}/prx/origin.git" "${prx}" 2>/dev/null
	(
		cd "${prx}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b xfeat && echo work > work.txt && git add --all && git commit --quiet -m work
		git push --quiet -u origin xfeat
		echo more >> work.txt && git add --all && git commit --quiet -m "never pushed"
		git checkout --quiet dev
		## Local-only branch, no origin copy at all: the PR can hold none of it.
		git checkout --quiet -b xlocal && echo solo > solo.txt && git add --all && git commit --quiet -m solo
		git checkout --quiet dev
	)
	local prxEnv="PATH='${ghp}' FAKE_GH_BASE=dev FAKE_GH_HEAD=xfeat"
	fAssertFail "pr ok refuses unpushed commits on the PR's branch"  bash -c "cd '${prx}' && ${prxEnv} '${gitsby}' -q pr ok 7"
	## Assert the reason: the plan prints the branch name either way, so matching 'xfeat' alone
	## would pass against a build with no guard at all.
	fAssertOut  "and names that branch, not the current one"  "'xfeat' has commits that never reached origin"  bash -c "cd '${prx}' && ${prxEnv} '${gitsby}' -q pr ok 7 2>&1 || true"
	fAssert     "and leaves the branch alone"  bash -c "cd '${prx}' && git show-ref --verify --quiet refs/heads/xfeat"
	fAssert     "and keeps the unpushed commit reachable"  bash -c "cd '${prx}' && git log -1 --pretty=%s xfeat | grep -qx 'never pushed'"
	fAssertFail "pr ok refuses a branch origin has never seen"  bash -c "cd '${prx}' && PATH='${ghp}' FAKE_GH_BASE=dev FAKE_GH_HEAD=xlocal '${gitsby}' -q pr ok 8"
	## Same fixture, once the work is pushed: the guard must not stand in the way of the real thing.
	fAssert "pr ok accepts a fully pushed branch from dev"  bash -c "cd '${prx}' && git push --quiet origin xfeat && ${prxEnv} '${gitsby}' -q pr ok 7"
	fAssert "and merged what origin held"  bash -c "cd '${prx}' && git ls-tree --name-only dev | grep -qx work.txt"

	## pr create: parks the work, then opens the PR against the merge target. Same fake gh.
	mkdir -p "${gh}/prnew"
	git init --quiet --bare -b main "${gh}/prnew/origin.git"
	local pnc="${gh}/prnew/c"
	git clone --quiet "${gh}/prnew/origin.git" "${pnc}" 2>/dev/null
	(
		cd "${pnc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b pnfeat && echo work > work.txt && git add --all && git commit --quiet -m "Teach it to retry"
	)
	fAssertFail "pr create refuses from the merge target"  bash -c "cd '${pnc}' && git checkout --quiet dev && PATH='${ghp}' '${gitsby}' -q pr create 'nope'"
	fAssertFail "pr create refuses an already-open PR"     bash -c "cd '${pnc}' && git checkout --quiet pnfeat && PATH='${ghp}' FAKE_GH_EXISTING=99 '${gitsby}' -q pr create"
	fAssert     "pr create opens the PR"                   bash -c "cd '${pnc}' && PATH='${ghp}' FAKE_GH_LOG='${gh}/prnew.log' '${gitsby}' -q pr create"
	fAssert     "pr create pushed the branch first"        bash -c "cd '${pnc}' && git ls-remote --heads origin pnfeat | grep -q pnfeat"
	fAssert     "pr create based the PR on the merge target"  bash -c "grep -q -- '--base dev' '${gh}/prnew.log'"
	fAssert     "pr create titled it from the last commit" bash -c "grep -q -- '--title Teach it to retry' '${gh}/prnew.log'"
	## An explicit title wins over the commit subject.
	(
		cd "${pnc}" || exit 1
		git checkout --quiet -b pnfeat2 && echo more > more.txt && git add --all && git commit --quiet -m "Commit subject"
	)
	fAssert "pr create takes an explicit title"  bash -c "cd '${pnc}' && PATH='${ghp}' FAKE_GH_LOG='${gh}/prnew2.log' '${gitsby}' -q pr create 'Explicit title' && grep -q -- '--title Explicit title' '${gh}/prnew2.log'"

	## Identity: which account a remote-touching command acts as. gh keeps one active account for the
	## whole host, so against a remote owned by somebody else it acts as the wrong one.
	## The origin really is a github.com url here, because the owner is parsed from what
	## 'git remote get-url' returns and that applies url.*.insteadOf - pointing it at a local bare to
	## stay offline would hand gitsby a local path and test nothing. --no-fetch keeps it off the
	## network instead: gh is stubbed, and a read never probes ssh, so nothing reaches github.com.
	local idn="${gh}/ident"
	mkdir -p "${idn}"
	git init --quiet --bare -b main "${idn}/backing.git"
	git clone --quiet "${idn}/backing.git" "${idn}/c" 2>/dev/null
	(
		cd "${idn}/c" || exit 1
		echo i > i.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git remote set-url origin git@github.com:acme/proj.git
	)
	local idEnv="PATH='${ghp}' FAKE_GH_LOGIN=someoneelse"
	fAssert "gh acts as the remote's owner when it holds that account" \
		bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/held.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=tok_acme' '${idn}/held.log'"
	## A fork or an org we have no account for is ordinary - it must not be touched, and must not refuse.
	fAssert "gh is left alone when it has no account for the owner" \
		bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/unheld.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/unheld.log'"
	## -NoFetch is spelled the same to both ports (bash normalises it), so these need no branch.
	if [[ "$1" == "bash" ]]; then  ## the identity flag IS spelled per implementation
		fAssert "--any-identity leaves gh's active account alone" \
			bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/any.log' '${gitsby}' -q -NoFetch --any-identity pr && grep -q 'GH_TOKEN=\]' '${idn}/any.log'"
	else
		fAssert "-AnyIdentity leaves gh's active account alone" \
			bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/any.log' '${gitsby}' -q -NoFetch -AnyIdentity pr && grep -q 'GH_TOKEN=\]' '${idn}/any.log'"
	fi
	## A remote we can't name an owner for gets no opinion at all.
	git clone --quiet "${idn}/backing.git" "${idn}/local" 2>/dev/null
	fAssert "a non-GitHub remote picks no account" \
		bash -c "cd '${idn}/local' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/plain.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/plain.log'"
	## The probe must ask as the key git would push with, not as ssh's default: a per-repo
	## core.sshCommand is exactly how two accounts are kept apart on one machine, and a probe that
	## ignores it reports the wrong account confidently. The fake ssh answers as the key's basename.
	git clone --quiet "${idn}/backing.git" "${idn}/keyed" 2>/dev/null
	(
		cd "${idn}/keyed" || exit 1
		git remote set-url origin git@github.com:acme/proj.git
		git config core.sshCommand 'ssh -i /keys/keyowner -o IdentitiesOnly=yes'
	)
	fAssertOut "the ssh probe asks as the key git pushes with" 'SSH \.+: keyowner' \
		bash -c "cd '${idn}/keyed' && ${idEnv} '${gitsby}' -NoFetch status"
	fAssertOut "and the key it names is that one, not ssh's default" 'key /keys/keyowner' \
		bash -c "cd '${idn}/keyed' && ${idEnv} '${gitsby}' -NoFetch status"

	## Hotfix branches target the default branch instead of dev, because they correct what is
	## already published. Landing one must also carry it back to dev, or the next release undoes it.
	local hf="${work}/$1-hotfix"
	git init --quiet --bare -b main "${hf}/origin.git"
	git clone --quiet "${hf}/origin.git" "${hf}/c" 2>/dev/null
	local hfc="${hf}/c"
	(
		cd "${hfc}" || exit 1
		echo "readme v1" > README.md && mkdir -p bin && echo shipped > bin/tool
		git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
	)
	fAssert    "br hotfix creates the branch"  bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix wording"
	fAssert    "and prefixes it"               bash -c "cd '${hfc}' && [[ \"\$(git branch --show-current)\" == 'hotfix/wording' ]]"
	fAssert    "off the default branch, not dev"  bash -c "cd '${hfc}' && git merge-base --is-ancestor origin/main HEAD"
	## -q still prints the plan, it only skips the prompt - so one run proves both.
	## (Non-quiet can't be used here: with no tty gitsby fails closed before printing anything.)
	fAssertPlan "br land plans and lands it on the default branch"  'git checkout main' \
		bash -c "cd '${hfc}' && echo 'readme v2' > README.md && '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1; '${gitsby}' -q -NoFetch br land 'Reword' 2>&1"
	fAssert    "it reached the default branch" bash -c "cd '${hfc}' && [[ \"\$(git show origin/main:README.md)\" == 'readme v2' ]]"
	fAssert    "and was carried back to dev"   bash -c "cd '${hfc}' && [[ \"\$(git show origin/dev:README.md)\" == 'readme v2' ]]"
	fAssert    "the branch is gone both sides" bash -c "cd '${hfc}' && [[ -z \"\$(git branch --list 'hotfix/*')\" ]] && [[ -z \"\$(git ls-remote --heads origin 'hotfix/*')\" ]]"
	## A hotfix that changes shipped code leaves main ahead of every tag - say so.
	fAssertOut "a hotfix touching bin/ warns about the release"  'changes shipped code' \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix code >/dev/null 2>&1; echo v2 > '${hfc}/bin/tool'; '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1; '${gitsby}' -q -NoFetch br land 'Fix' 2>&1"
	## The warning reads the branch tip, and 'br land' is what commits the working tree - so an
	## uncommitted bin/ edit (the ordinary way of making one) has to be checked for after that.
	fAssertOut "a hotfix warns about shipped code even when the edit is uncommitted"  'changes shipped code' \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix uncommitted >/dev/null 2>&1; echo v3 > '${hfc}/bin/tool'; '${gitsby}' -q -NoFetch br land 'Fix uncommitted' 2>&1"
	fAssert    "a docs-only hotfix says nothing about releases"  \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix docs >/dev/null 2>&1; echo 'readme v3' > README.md; '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1; out=\"\$('${gitsby}' -q -NoFetch br land 'Docs' 2>&1)\"; ! grep -q 'changes shipped code' <<< \"\${out}\""
	## A back-merge conflict must leave dev untouched and the tree clean, not half-merged.
	fAssert    "a conflicting back-merge leaves dev alone"  \
		bash -c "cd '${hfc}' && git checkout --quiet dev && echo devtext > README.md && git commit --quiet -am devtext && git push --quiet && '${gitsby}' -q -NoFetch br hotfix clash >/dev/null 2>&1 && echo hftext > README.md && '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1 && '${gitsby}' -q -NoFetch br land Clash >/dev/null 2>&1; [[ \"\$(git show origin/main:README.md)\" == hftext && \"\$(git show origin/dev:README.md)\" == devtext ]]"
	fAssert    "and the tree is not left mid-merge"  bash -c "cd '${hfc}' && [[ ! -e .git/MERGE_HEAD ]] && [[ -z \"\$(git status --porcelain)\" ]]"
	## Feature branches must be untouched by all of this.
	fAssert    "br create still branches off dev"  \
		bash -c "cd '${hfc}' && git checkout --quiet dev && git checkout --quiet -- . 2>/dev/null; '${gitsby}' -q -NoFetch br create feat1 && git merge-base --is-ancestor origin/dev HEAD"
	fAssertOut "and br land still targets dev for them"  'git checkout dev' \
		bash -c "cd '${hfc}' && echo feat > feat.txt && '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1; '${gitsby}' -q -NoFetch br land 'Feat' 2>&1"
	fAssertFail "br hotfix with no name rejected"  bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix"
	fAssertFail "the internal token stays untypeable"  bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br-hotfix x"

	## The current-branch line says where you ARE, and nothing used to connect that to where the new
	## branch comes off: it read 'dev' while the plan below it checked out main.
	## -q still prints the whole block; it only skips the prompt.
	fAssertOut "br hotfix names the branch it will make, and its base"  '^New branch \.+: main :: hotfix/base1$' \
		bash -c "cd '${hfc}' && git checkout --quiet dev && '${gitsby}' -q -NoFetch br hotfix base1 2>&1"
	fAssertOut "and still reports the branch you're standing on"  '^Current branch: dev' \
		bash -c "cd '${hfc}' && git checkout --quiet dev && '${gitsby}' -q -NoFetch br hotfix base2 2>&1"
	fAssertOut "br create names dev as the base"  '^New branch \.+: dev :: base3$' \
		bash -c "cd '${hfc}' && git checkout --quiet dev && '${gitsby}' -q -NoFetch br create base3 2>&1"
	## Said once, in the pre-flight. The after-shot would be claiming a branch that already exists.
	fAssert "and says it once, not again after the run"  \
		bash -c "cd '${hfc}' && git checkout --quiet dev && [[ \"\$('${gitsby}' -q -NoFetch br create base4 2>&1 | grep -c 'New branch')\" == 1 ]]"
	fAssertNotOut "status claims no new branch at all"  'New branch' \
		bash -c "cd '${hfc}' && '${gitsby}' -q status 2>&1"

	## A work branch is shown against what it lands on; main/master/dev are off nothing, so they
	## stay bare - "dev :: dev" would be noise, and "main :: dev" is only true at release time.
	fAssertOut "a feature branch shows the base it lands on"  '^Current branch: dev :: base3' \
		bash -c "cd '${hfc}' && git checkout --quiet base3 && '${gitsby}' -q status 2>&1"
	fAssertOut "a hotfix branch shows the default branch instead"  '^Current branch: main :: hotfix/base1' \
		bash -c "cd '${hfc}' && git checkout --quiet hotfix/base1 && '${gitsby}' -q status 2>&1"
	fAssertNotOut "dev is shown bare"  '^Current branch: [^ ]+ :: dev' \
		bash -c "cd '${hfc}' && git checkout --quiet dev && '${gitsby}' -q status 2>&1"

	## The default branch is its own line now, not a parenthetical tacked onto the branch line.
	fAssertOut "the default branch gets its own line"  '^Default branch: main$' \
		bash -c "cd '${hfc}' && '${gitsby}' -q status 2>&1"
	fAssertNotOut "and is no longer tacked onto the branch line"  'repo default:' \
		bash -c "cd '${hfc}' && '${gitsby}' -q status 2>&1"
	## br list never said what the default was, which is half of what a listing is for.
	fAssertOut "br list says what the default branch is"  '^Default branch: main$' \
		bash -c "cd '${hfc}' && '${gitsby}' -q br list 2>&1"

	## gh writes act as gh's own account, not the ssh key git pushes with. A difference BOTH sides
	## know about is refused unattended; unknown (no agent, https remote, deploy key) never blocks,
	## or every CI runner breaks. A fake ssh answers the greeting GitHub really sends.
	local id="${work}/$1-ident"
	mkdir -p "${id}/bin"
	cp "${gh}/bin/gh" "${id}/bin/gh"
	## insteadOf is no good here: 'git remote get-url' returns the REWRITTEN url, so there would be
	## no ssh url left to probe. Instead the stub doubles as the transport, so origin stays an
	## scp-style url while every push and fetch lands in a local bare.
	cat > "${id}/bin/ssh" <<-'EOF'
		#!/usr/bin/env bash
		[[ "$1" == "-G" ]] && { printf 'user git\nhostname github.com\n'; exit 0; }
		if [[ "$1" == "-T" ]]; then
			## No FAKE_SSH_LOGIN = no usable key, which is the 'unknown' case.
			[[ -n "${FAKE_SSH_LOGIN:-}" ]] || { echo "git@github.com: Permission denied (publickey)." >&2; exit 255; }
			## Real ssh often writes a line or two of its own before the greeting; we capture stderr too.
			[[ -n "${FAKE_SSH_NOISE:-}" ]] && echo "Warning: Permanently added 'github.com' (ED25519) to the list of known hosts." >&2
			echo "Hi ${FAKE_SSH_LOGIN}! You've successfully authenticated, but GitHub does not provide shell access."
			exit 1   ## GitHub always exits 1 here; the greeting is the answer, not the status
		fi
		## Otherwise git is driving us as its transport: point the pack program at the local bare.
		for arg in "$@"; do
			case "${arg}" in
				git-upload-pack*|git-receive-pack*|git-upload-archive*)
					exec "${arg%% *}" "${FAKE_SSH_REPO}" ;;
			esac
		done
		exit 0
	EOF
	chmod +x "${id}/bin/ssh"
	local -r idp="${id}/bin:${PATH}"
	git init --quiet --bare -b main "${id}/origin.git"
	local idc="${id}/c"
	git clone --quiet "${id}/origin.git" "${idc}" 2>/dev/null
	(
		cd "${idc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b idfeat && echo w > w.txt && git add --all && git commit --quiet -m "Work"
		git remote set-url origin git@github_test:x/y.git
	)
	local idEnv="PATH='${idp}' FAKE_SSH_REPO='${id}/origin.git'"
	fAssertFail "gh/ssh identity mismatch refused unattended" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "and the refusal names both accounts"  "acts as 'alice'.*authenticates as 'bob'" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T' 2>&1 || true"
	fAssertFail "the mismatch refusal happens before anything runs" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T'; git -C '${idc}' ls-remote --heads origin idfeat | grep -q idfeat"
	fAssert     "unknown ssh identity does not block"  \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "and says there was nothing to compare"  'no ssh identity to compare' \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice '${gitsby}' -q -NoFetch pr create 'T' 2>&1"
	fAssert     "matching identities proceed"  \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=same FAKE_SSH_LOGIN=same '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "the identity block names the gh account"  'GitHub \(gh\) [.]*: same' \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=same FAKE_SSH_LOGIN=same '${gitsby}' -q -NoFetch pr create 'T' 2>&1"
	## The override flag is spelled per implementation, like --public/-Public.
	local anyIdFlag="--any-identity"; [[ "$1" == "bash" ]] || anyIdFlag="-AnyIdentity"
	fAssert     "the override flag proceeds through a mismatch"  \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch ${anyIdFlag} pr create 'T'"
	fAssertOut  "and the mismatch is still on the identity line"  "NOT the ssh key's account" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch ${anyIdFlag} pr create 'T' 2>&1"
	## Read-only pr never pays for the ssh probe, so a mismatch can't block looking.
	fAssert     "a mismatch does not block read-only pr"  \
		bash -c "cd '${idc}' && ${idEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr"
	## ssh writes host-key and missing-identity warnings ahead of the greeting, and we read both
	## streams - so the greeting is not reliably the first line. Anchoring to the whole output
	## answered 'unknown' for exactly the multi-key setups this check exists for.
	fAssertFail "a warning line before the greeting still resolves the ssh identity" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_SSH_NOISE=1 FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "and it still names both accounts"  "acts as 'alice'.*authenticates as 'bob'" \
		bash -c "cd '${idc}' && ${idEnv} FAKE_SSH_NOISE=1 FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob '${gitsby}' -q -NoFetch pr create 'T' 2>&1 || true"

	## repo create has no origin yet, but the one gh is about to set IS knowable - gh never uses a
	## host alias, so it is 'git@github.com:owner/name.git'. Check it before creating anything.
	## Note this runs from a plain directory, where the preceding repo probe fails: the gh login
	## must not be read from a stale exit status (the PowerShell port got this wrong once).
	## ssh protocol, or gh would hand git an https url and there would be no ssh identity at all.
	local rcEnv="PATH='${idp}' FAKE_GH_VIEW=notfound FAKE_GH_PROTO=ssh"
	mkdir -p "${id}/rc-bad"; echo x > "${id}/rc-bad/x.txt"
	fAssertFail "repo create refuses a mismatched identity before creating anything" \
		bash -c "cd '${id}/rc-bad' && ${rcEnv} FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob FAKE_GH_REMOTE='${id}/rc-bad.git' '${gitsby}' -q repo create me/proj"
	fAssert     "and it neither created the remote nor inited the directory" \
		bash -c "[[ ! -e '${id}/rc-bad.git' && ! -e '${id}/rc-bad/.git' ]]"
	mkdir -p "${id}/rc-ok"; echo x > "${id}/rc-ok/x.txt"
	fAssertOut  "repo create resolves gh's account from a plain directory"  'GitHub \(gh\) [.]*: same' \
		bash -c "cd '${id}/rc-ok' && ${rcEnv} FAKE_GH_LOGIN=same FAKE_SSH_LOGIN=same FAKE_GH_REMOTE='${id}/rc-ok.git' '${gitsby}' -q repo create me/proj 2>&1"
	mkdir -p "${id}/rc-https"; echo x > "${id}/rc-https/x.txt"
	fAssert     "an https protocol leaves nothing to compare, so it proceeds" \
		bash -c "cd '${id}/rc-https' && ${rcEnv} FAKE_GH_PROTO=https FAKE_GH_LOGIN=alice FAKE_SSH_LOGIN=bob FAKE_GH_REMOTE='${id}/rc-https.git' '${gitsby}' -q repo create me/proj"

	## pr ok refuses to merge while work is still only local: gh merges what origin has, then
	## deletes the branch, so anything unpushed would be outside both the PR and the merge.
	mkdir -p "${gh}/prguard"
	git init --quiet --bare -b main "${gh}/prguard/origin.git"
	local pgc="${gh}/prguard/c"
	git clone --quiet "${gh}/prguard/origin.git" "${pgc}" 2>/dev/null
	(
		cd "${pgc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b pgfeat && echo w > w.txt && git add --all && git commit --quiet -m work
		git push --quiet -u origin pgfeat
	)
	fAssertFail "pr ok refuses a dirty tree"  bash -c "cd '${pgc}' && echo dirt > dirt.txt && PATH='${ghp}' '${gitsby}' -q pr ok 7"
	fAssert     "pr ok left the dirty work alone"  bash -c "cd '${pgc}' && [[ -f dirt.txt ]] && [[ \"\$(git branch --show-current)\" == pgfeat ]]"
	fAssertFail "pr ok refuses unpushed commits"  bash -c "cd '${pgc}' && rm -f dirt.txt && echo u > u.txt && git add --all && git commit --quiet -m unpushed && PATH='${ghp}' '${gitsby}' -q pr ok 7"
	fAssert     "pr ok kept the unpushed commit"  bash -c "cd '${pgc}' && git log -1 --pretty=%s | grep -qx unpushed"
	fAssert     "pr ok proceeds once synced"  bash -c "cd '${pgc}' && git push --quiet && PATH='${ghp}' FAKE_GH_BASE=dev '${gitsby}' -q pr ok 7"

	## Which branch a PR lands on, and whether it's a hotfix, belong to the PR - not to wherever
	## you happen to be standing. 'pr ok <n>' is routinely run from dev, on someone else's branch.
	local pk="${gh}/prhead"
	git init --quiet --bare -b main "${pk}/origin.git"
	local pkc="${pk}/c"
	git clone --quiet "${pk}/origin.git" "${pkc}" 2>/dev/null
	(
		cd "${pkc}" || exit 1
		echo base > base.txt && echo "readme v1" > README.md
		git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet main && git checkout --quiet -b hotfix/api
		echo "readme v2" > README.md && git commit --quiet -am "Fix wording" && git push --quiet -u origin hotfix/api
		git checkout --quiet dev
	)
	fAssertPlan "pr ok plans the back-merge for a hotfix PR accepted from dev"  'git merge origin/main' \
		bash -c "cd '${pkc}' && PATH='${ghp}' FAKE_GH_HEAD=hotfix/api FAKE_GH_BASE=main '${gitsby}' -q pr ok 7 2>&1"
	fAssert    "and the hotfix reached the default branch"  bash -c "cd '${pkc}' && [[ \"\$(git show origin/main:README.md)\" == 'readme v2' ]]"
	fAssert    "and was carried back to dev"               bash -c "cd '${pkc}' && [[ \"\$(git show origin/dev:README.md)\" == 'readme v2' ]]"
	## The converse: standing on a hotfix branch must not make someone else's feature PR one.
	(
		cd "${pkc}" || exit 1
		git checkout --quiet dev && git checkout --quiet -b pkfeat && echo f > f.txt
		git add --all && git commit --quiet -m feat && git push --quiet -u origin pkfeat
		git checkout --quiet -b hotfix/standing && git push --quiet -u origin hotfix/standing
	)
	fAssertNotPlan "a feature PR accepted from a hotfix branch plans no back-merge"  'git merge origin/main' \
		bash -c "cd '${pkc}' && PATH='${ghp}' FAKE_GH_HEAD=pkfeat FAKE_GH_BASE=dev '${gitsby}' -q pr ok 8 2>&1"

	## The bash version gate. Bash build only - the PowerShell one needs no bash at all.
	if [[ "$1" == "bash" ]]; then
		local vg="${work}/vgate"
		mkdir -p "${vg}/bin"
		## Raise the floor past any real bash so the gate fires on this one. Everything below the
		## gate is 4.x syntax, so a clean refusal also proves nothing below it was reached.
		sed 's/-lt 4 \]\]/-lt 99 ]]/' "${root}/bin/gitsby" > "${vg}/gitsby"
		chmod +x "${vg}/gitsby"
		local vgRun="PATH='${vg}/bin:${PATH}' '${vg}/gitsby' status"
		printf '#!/usr/bin/env bash\necho Linux\n' > "${vg}/bin/uname"; chmod +x "${vg}/bin/uname"
		fAssertFail   "too old a bash is refused"                 bash -c "${vgRun}"
		fAssertOut    "and the refusal names the requirement"     'needs bash 4.4 or newer'  bash -c "${vgRun}"
		fAssertNotOut "and raises no shell error of its own"      'bad substitution|invalid shell option|syntax error'  bash -c "${vgRun}"
		## A fake uname picks the platform arm, so all three can be checked from one box.
		local spec="" plat="" pat=""
		for spec in "Darwin:brew install bash" "FreeBSD:pkg install bash" "Linux:package manager"; do
			plat="${spec%%:*}"; pat="${spec#*:}"
			printf '#!/usr/bin/env bash\necho %s\n' "${plat}" > "${vg}/bin/uname"; chmod +x "${vg}/bin/uname"
			fAssertOut "and tells ${plat} users what to install"  "${pat}"  bash -c "${vgRun}"
		done
		## macOS pins /bin/bash at 3.2 forever, so installing a newer one only helps via PATH.
		fAssert "gitsby resolves bash through PATH, not /bin/bash"  bash -c "head -1 '${root}/bin/gitsby' | grep -qx '#!/usr/bin/env bash'"

		## Installer options. These run once, not per implementation, and never reach the network:
		## every check either exits during argument parsing, or uses --release (which names the ref
		## outright, so no latest-release lookup) and stops at the confirmation.
		local inst="${root}/install.bash"
		fAssert     "installer --help works"                    bash -c "bash '${inst}' --help"
		fAssertOut  "and documents --release"                   '\-\-release dev\|stable'   bash -c "bash '${inst}' --help"
		fAssertOut  "and documents --target"                    '\-\-target user\|system'   bash -c "bash '${inst}' --help"
		fAssertOut  "and documents --arch"                      '\-\-arch x64\|amd64\|arm64' bash -c "bash '${inst}' --help"
		## Assert the reason, not just the failure: an installer that never heard of --target also
		## exits nonzero here, so a bare exit-code check would pass with the option missing entirely.
		fAssertFail "installer exits nonzero on a bad --target"  bash -c "bash '${inst}' --target bogus"
		fAssertOut  "installer refuses a bad --target"           "\-\-target takes"          bash -c "bash '${inst}' --target bogus"
		fAssertOut  "installer refuses a bad --arch"             "\-\-arch takes"            bash -c "bash '${inst}' --arch sparc"
		fAssertOut  "installer refuses a bad --release"          "\-\-release takes"         bash -c "bash '${inst}' --release beta"
		fAssertOut  "installer refuses --release with --ref"     'Use --release or --ref'    bash -c "bash '${inst}' --release dev --ref main"
		fAssertOut  "installer refuses a valueless --target"     "\-\-target needs a value"  bash -c "bash '${inst}' --target"
		## A ref is interpolated into a download URL, so a path-shaped one installs a script from
		## some other repo while the printed plan still names this one.
		fAssertOut  "installer refuses a path-shaped --ref"      'not a path'                bash -c "bash '${inst}' -y --ref '../../evil/repo/main'"
		fAssertOut  "installer refuses an absolute --ref"        'not a path'                bash -c "bash '${inst}' -y --ref '/etc/passwd'"
		fAssertOut  "installer refuses a shell-shaped --ref"     "aren't valid in a git ref" bash -c "bash '${inst}' -y --ref 'a b;id'"
		## Reading the printed plan needs the confirmation to refuse rather than block, which means
		## no controlling terminal. Without setsid there is no safe way to ask, so skip rather than hang.
		if command -v setsid >/dev/null 2>&1; then
			local iHome="${work}/insthome"; mkdir -p "${iHome}"
			local iRun="setsid env HOME='${iHome}' bash '${inst}' --release dev"
			fAssertOut "--target user installs under HOME"      "insthome/\.local/bin/gitsby"  bash -c "${iRun} --target user </dev/null"
			fAssertOut "--target system installs system-wide"   '/usr/local/bin/gitsby'        bash -c "${iRun} --target system </dev/null"
			fAssertOut "-s still means --target system"         '/usr/local/bin/gitsby'        bash -c "${iRun} -s </dev/null"
			fAssertOut "--arch is taken but reported inert"     'Ignore --arch arm64'          bash -c "${iRun} --arch arm64 </dev/null"
		fi
		## The PowerShell installer's ValidateSet does the same job as the case arms above.
		if command -v pwsh >/dev/null 2>&1; then
			local instPs="${root}/install.ps1"
			fAssertFail "ps installer refuses a bad -Target"      pwsh -NoProfile -File "${instPs}" -Target bogus
			fAssertFail "ps installer refuses a bad -Arch"        pwsh -NoProfile -File "${instPs}" -Arch sparc
			fAssertFail "ps installer refuses a bad -Release"     pwsh -NoProfile -File "${instPs}" -Release beta
			fAssertFail "ps installer refuses -Release with -Ref" pwsh -NoProfile -File "${instPs}" -Release dev -Ref main
			fAssertOut  "ps installer refuses a path-shaped -Ref"  'not a path'  pwsh -NoProfile -File "${instPs}" -Yes -Ref '../../evil/repo/main'
			fAssertOut  "ps installer refuses an absolute -Ref"    'not a path'  pwsh -NoProfile -File "${instPs}" -Yes -Ref '/etc/passwd'
			## The documented one-liners are 'iex' and a scriptblock, neither of which is a script
			## file - so -File coverage alone says nothing about them. Both must bind their
			## parameters, refuse without a tty, and leave the calling session alive and unaltered.
			## These reach the confirmation prompt, so it has to REFUSE rather than wait: no
			## controlling terminal (setsid) and stdin at EOF, the same way the bash plan checks
			## above do it. Without that, Read-Host blocks and the whole suite hangs.
			if command -v setsid >/dev/null 2>&1; then
				local instDev="${root}/install-dev.ps1"
				## Decode the bytes ourselves rather than Get-Content, which quietly drops a BOM.
				## irm doesn't, so a BOM'd file reaches iex with U+FEFF glued to the shebang and
				## the first line stops being a comment - which is how a BOM sat here undetected.
				local readInst="\$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes('${instPs}'))"
				fAssertOut "iex form reaches the plan"          'gitsby installer'  fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
				fAssertOut "and refuses without a tty"          'CAUGHT: Aborted'   fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
				fAssertOut "and leaves the session alive"       'HOST ALIVE'        fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
				fAssertOut "scriptblock form binds its options" '/usr/local/bin'    fPwshText "${readInst}; try { & ([scriptblock]::Create(\$t)) -Ref main -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
				fAssertOut "and leaves the session alive too"   'HOST ALIVE'        fPwshText "${readInst}; try { & ([scriptblock]::Create(\$t)) -Ref main -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
				fAssertOut "installer leaks no StrictMode"      'strict stayed off' fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { }; try { \$q = \$neverSet; 'strict stayed off' } catch { 'STRICT LEAKED' }"
				fAssertOut "installer leaks no ErrorAction"     'EAP=Continue'      fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { }; \"EAP=\$ErrorActionPreference\""
				fAssertOut "dev setup's iex form asks first"    'CAUGHT: Aborted'   fPwshText "\$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes('${instDev}')); try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }"
			fi
			## Byte 0 must be the shebang: a BOM ahead of it means the kernel won't run the
			## file directly either, which the one-liner checks above can't see.
			local psFile=""
			for psFile in "${root}/bin/gitsby.ps1" "${root}/install.ps1" "${root}/install-dev.ps1"; do
				fAssert "$(basename "${psFile}") starts with a shebang, no BOM" \
					bash -c "[[ \"\$(head -c2 '${psFile}')\" == '#!' ]]"
			done
			## GitHub serves SHA256SUMS as octet-stream, and Invoke-WebRequest hands back bytes
			## for that, so reading the body as text found no checksum and skipped verification
			## while reporting there was none. Reaching the real asset needs the network, so this
			## pins the decode in the source rather than exercising it.
			fAssert "install.ps1 decodes the SHA256SUMS body from bytes" \
				bash -c "grep -q 'byte\[\]' '${instPs}'"
		fi
	fi

	## PowerShell only. Set-Location moves PowerShell's own location, not the process cwd, so a
	## script that starts git itself must pass the working directory or reads and writes land in
	## different repos. Every other check cds in bash before starting pwsh, which hides it.
	if [[ "$1" == "pwsh" ]]; then
		local cw="${work}/cwdsplit"
		mkdir -p "${cw}"
		git init --quiet -b main "${cw}/launch"
		( cd "${cw}/launch" && echo x > f.txt && git add --all && git commit --quiet -m "init launch" && echo a > only-in-launch.txt )
		git init --quiet -b main "${cw}/target"
		( cd "${cw}/target" && echo y > f.txt && git add --all && git commit --quiet -m "init target" && echo b > only-in-target.txt )
		## Start pwsh in one repo, move to the other inside the session, then commit.
		( cd "${cw}/launch" && pwsh -NoProfile -Command "Set-Location '${cw}/target'; & '${root}/bin/gitsby.ps1' -q update 'from target'" ) >/dev/null 2>&1 || true
		fAssert "pwsh commits where Set-Location points"  bash -c "cd '${cw}/target' && [[ \"\$(git log -1 --pretty=%s)\" == 'from target' ]]"
		fAssert "and commits that repo's own file"        bash -c "cd '${cw}/target' && git show --stat --pretty=format: HEAD | grep -q only-in-target"
		fAssert "and leaves the launch repo alone"        bash -c "cd '${cw}/launch' && [[ \"\$(git log -1 --pretty=%s)\" == 'init launch' ]] && [[ -n \"\$(git status --porcelain)\" ]]"
	fi

	## A pull whose autostash reapply conflicts still exits 0, so nothing downstream noticed and
	## 'git add --all' marked the conflict resolved - committing the markers and pushing them.
	## The everyday case: local edits to the same lines a teammate already pushed.
	local cf="${work}/$1-conflict"
	mkdir -p "${cf}"
	git init --quiet --bare -b main "${cf}/origin.git"
	git clone --quiet "${cf}/origin.git" "${cf}/mine" 2>/dev/null
	( cd "${cf}/mine" && printf 'line1\nline2\nline3\n' > shared.txt && git add --all && git commit --quiet -m "initial" && git push --quiet -u origin main )
	git clone --quiet "${cf}/origin.git" "${cf}/theirs"
	( cd "${cf}/theirs" && printf 'line1\nTHEIRS\nline3\n' > shared.txt && git add --all && git commit --quiet -m "their edit" && git push --quiet origin main )
	( cd "${cf}/mine" && printf 'line1\nMINE\nline3\n' > shared.txt )
	fAssertFail "update refuses a conflicted autostash reapply"  bash -c "cd '${cf}/mine' && '${gitsby}' -q update 'mine'"
	fAssertOut  "and names the conflicted file"  'shared\.txt'  bash -c "cd '${cf}/mine' && '${gitsby}' -q update 'mine' 2>&1"
	fAssert     "and commits no conflict markers"  bash -c "cd '${cf}/mine' && ! git log -p | grep -q '<<<<<<<'"
	fAssert     "and leaves the merge unresolved for the user"  bash -c "cd '${cf}/mine' && [[ -n \"\$(git diff --name-only --diff-filter=U)\" ]]"

	## no-remote repo: everything still works locally
	local nr="${work}/$1-noremote"
	git init --quiet -b main "${nr}"
	( cd "${nr}" && echo a > a.txt && git add --all && git commit --quiet -m "initial" )
	fAssert "sync with no remote"   bash -c "cd '${nr}' && '${gitsby}' -q sync 'msg'"
	fAssert "br create with no remote"  bash -c "cd '${nr}' && '${gitsby}' -q br create nb && [[ \"\$(git branch --show-current)\" == nb ]]"
	( cd "${nr}" && echo b > b.txt )
	fAssert "br land with no remote"   bash -c "cd '${nr}' && '${gitsby}' -q br land 'merge nb'"
	fAssert "landed on main"        bash -c "cd '${nr}' && [[ \"\$(git branch --show-current)\" == main ]] && [[ -f b.txt ]]"

	## A default branch that is neither main nor master. Nothing may fall back to the literal
	## 'main' here: that branch doesn't exist, so it would be checked out, protected and merged
	## into as a name - after the WIP commit the wrong protected-branch answer already made.
	local tk="${work}/$1-trunk"
	git init --quiet -b trunk "${tk}"
	( cd "${tk}" && echo a > a.txt && git add --all && git commit --quiet -m init && echo wip >> a.txt )
	fAssertOut "status names the real default branch"  'Default branch: trunk'  bash -c "cd '${tk}' && '${gitsby}' -q status"
	fAssert    "br create works on a trunk-default repo"  bash -c "cd '${tk}' && '${gitsby}' -q br create tfeat && [[ \"\$(git branch --show-current)\" == tfeat ]]"
	fAssert    "and left no WIP commit on trunk"  bash -c "cd '${tk}' && [[ \"\$(git rev-list --count trunk)\" == 1 ]]"
	fAssert    "and carried the dirty work over"  bash -c "cd '${tk}' && grep -qx wip a.txt"
	fAssert    "update works there too"  bash -c "cd '${tk}' && '${gitsby}' -q update 'tw'"
	fAssert    "br land targets trunk, not a fabricated main"  bash -c "cd '${tk}' && '${gitsby}' -q br land 'landed' && [[ \"\$(git branch --show-current)\" == trunk ]] && ! git show-ref --verify --quiet refs/heads/main"

	## Same shape, but nothing conventional to go on and no origin/HEAD to ask: refuse rather
	## than guess, and refuse before anything is committed.
	local tu="${work}/$1-trunkambig"
	git init --quiet -b mainline "${tu}"
	( cd "${tu}" && echo a > a.txt && git add --all && git commit --quiet -m init && git branch other && echo wip >> a.txt )
	fAssertFail "br create refuses when the default branch can't be told"  bash -c "cd '${tu}' && '${gitsby}' -q br create x"
	fAssertOut  "and says so"  "Can't tell this repo's default branch"     bash -c "cd '${tu}' && '${gitsby}' -q br create x 2>&1"
	fAssert     "and committed nothing"  bash -c "cd '${tu}' && [[ \"\$(git rev-list --count mainline)\" == 1 ]]"
	## status is the command you run to find out what is wrong, so it must still work - and must
	## not print a name it couldn't resolve.
	fAssertOut  "status still runs and admits it doesn't know"  'Default branch: unknown'  bash -c "cd '${tu}' && '${gitsby}' -q status"
	fAssert     "br list still runs there too"  bash -c "cd '${tu}' && '${gitsby}' -q br list >/dev/null 2>&1"
	fAssertOut  "and lists the branches with the same admission"  'Default branch: unknown'  bash -c "cd '${tu}' && '${gitsby}' -q br list"
	fAssertOut  "including the ambiguous ones"  '(^|[ /])other'  bash -c "cd '${tu}' && '${gitsby}' -q br list"
}

echo "gitsby regression tests (fixture: ${work})"

gitsby="${root}/bin/gitsby"
fMakeFixture "${work}/bash"
fRunSuite "bash"

## Same suite against the PowerShell port, when pwsh is available. The shim keeps
## ${gitsby} a plain single path so the bash -c interpolation above stays as-is.
if command -v pwsh >/dev/null 2>&1; then
	gitsby="${work}/gitsby-pwsh"
	printf '#!/usr/bin/env bash\nexec pwsh -NoProfile -File "%s" "$@"\n' "${root}/bin/gitsby.ps1" > "${gitsby}"
	chmod +x "${gitsby}"
	fMakeFixture "${work}/pwsh"
	fRunSuite "pwsh"
else
	echo "suite: pwsh skipped (pwsh not installed)"
fi

echo "passed: ${pass}, failed: ${fail}"
((fail == 0)) || exit 1


##	History:
##		- 20260722 JC: Created, alongside the bin/gitsby refactor.
##		- 20260722 JC: Run the suite per implementation; added the pwsh leg.
##		- 20260723 JC: Checks for the update command (and its old name), and for dev fast-forwarding after a release.
##		- 20260724 JC: clone and connect checks (dev checkout, no-op re-runs, plain-dir connect, nonempty/missing-remote and collision guards).
##		- 20260724 JC: exhaustive clone/connect coverage - no-dev/empty-dir/different-url clone edges, empty-repo + matching-url connect, and the gh owner/name paths (create, add https/ssh, nonempty-refuse) via a hermetic fake gh.
##		- 20260725 JC: Release-candidate version checks, and pr ok from the merged branch - the fake gh grew a pr merge that restores the stale origin ref, since that is what makes the real failure reproduce.
##		- 20260726 JC: Offline coverage inside a compound command, and the protected-branch refusal now has to name a command that still exists. The old offline check spelled the flag --no-fetch, which pwsh rejects, and matched the rejection - green for the wrong reason.
##		- 20260727 JC: Installer option coverage (--release/--target/--arch, both implementations). The refusal checks assert the reason rather than the exit code, since an installer that never heard of --target also exits nonzero. Plan checks need the confirmation to refuse instead of block, so they run under setsid and skip where it is absent.
##		- 20260728 JC: Offline push coverage (branch commands degrade and say so, publishing commands refuse, br land keeps origin's copy of the branch until the merge is pushed), and the file list 'repo connect' shows before a first publication. The offline block gets its own origin: by that point in the suite the shared one has a dev branch, so the merge target was not what the checks assumed.
##		- 20260730 JC: SSH identity coverage. Every other check uses a local-path origin, which has no ssh identity, so the whole line had shipped untested; a fake ssh reproduces the -G user defaulting that caused the bug.
##		- 20260730 JC: Offline message coverage: an in-sync park says "Nothing to push.", the skip warning names its branch, and an offline hotfix land names the recovery that publishes the default branch. Four of the six checks fail against the prior code; the hotfix-runs and back-merge checks are regression guards.
