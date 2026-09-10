#!/usr/bin/env bash

#  shellcheck disable=2317  ## 'Can't reach.' False hits on functions invoked indirectly.

##	Purpose:
##		- Regression tests for the compiled build in src-go/.
##		- Run by cicd.bash stage 2, which builds the binary first, or standalone
##		  after a 'go build' by hand.
##		- Carries a second set of checks that are not about the implementation at
##		  all: the installers, the frozen v2.1.0 scripts' own platform gates, and
##		  source pins on this pipeline's files. They used to ride the Bash leg
##		  because that was the leg that always ran; they were never about Bash.
##		- Builds throwaway repos (a bare 'origin' + two clones) under mktemp;
##		  never touches the real repo or network.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-test.XXXXXX")"
trap 'rm -rf -- "${work:?}"' EXIT

## Keep test commits hermetic (no reliance on the user's git config).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

## Same reasoning, for gitsby's own config: whoever runs this may have accounts configured, and
## that file decides which account a command acts as. A single 'protocol = ssh' line in it is
## enough to make the repo commands build a different remote URL than the check expects. The
## account block below sets its own HOME and opts back out of this with an empty value.
export GITSBY_CONFIG="${work}/no-accounts.shcl"; : > "${GITSBY_CONFIG}"

## The blocks that test config DISCOVERY opt out of the pin above and fake HOME instead, so they
## have to neutralize the other two candidates by hand: XDG_CONFIG_HOME is tried before HOME and
## APPDATA after it, and on a machine where either is set it answers for the real user. Emptied
## rather than pointed somewhere, so HOME stays the candidate under test. Without this those
## blocks quietly read whatever accounts the person running the suite had configured, and went
## red the day they configured any.
acNoDiscovery="GITSBY_CONFIG= XDG_CONFIG_HOME= APPDATA="

## Two more inputs the lines above do NOT cover, both of which reach us from an ordinary
## working terminal rather than from a config file:
##   - GIT_CONFIG_COUNT/KEY_n/VALUE_n outrank every config FILE, including a repo-local one
##     and the GIT_CONFIG_GLOBAL set above - so pinning the files is not isolation on its own.
##   - GH_TOKEN and friends are what the fake gh reports back, so an inherited one makes every
##     "gh was left alone" check read as "gh was handed a token".
## Neither shows up as a failure you can act on: the suite just reports checks that were never
## about the thing they name.
fUnsetInheritedGitConfig(){
	local -i i=0
	for (( i = 0; i < ${GIT_CONFIG_COUNT:-0}; i++ )); do unset "GIT_CONFIG_KEY_${i}" "GIT_CONFIG_VALUE_${i}"; done
	unset GIT_CONFIG_COUNT
}
fUnsetInheritedGitConfig
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_HOST GH_CONFIG_DIR GITSBY_ACCOUNT

## -q silences the per-check line and leaves the header, the failures and the total. A run
## of 600-odd checks buries every stage header in a pipeline log nobody watches live.
declare -i quiet=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		-q|--quiet) quiet=1; shift ;;
		-h|--help)  echo "Usage: $(basename "${BASH_SOURCE[0]}") [-q|--quiet]"; exit 0 ;;
		*)          echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
done

declare -i pass=0 fail=0
fOk(){   pass=$((pass+1)); ((quiet)) || echo "  ok: $*"; }
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
## Windows can't start a shebang script by name, and the PowerShell build looks its commands up
## the Windows way - so every stub gets a .cmd sibling that hands the body straight back to bash.
## Without it the pwsh leg finds the stub, runs nothing, and reads the silence as empty output.
isWindows=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) isWindows=1 ;; esac
fStubShim(){ ((isWindows)) && printf '@echo off\r\nbash "%s" %%*\r\n' "$1" > "$1.cmd"; return 0 ;}
## Write a stub from stdin, runnable by both builds.
fStub(){ cat > "$1"; chmod +x "$1"; fStubShim "$1" ;}
## PowerShell and .NET have no MSYS mount table, so '/tmp/x' and '/c/x' resolve against the root
## of the current drive - 'C:\tmp\x', 'C:\c\x'. Any path interpolated into a pwsh command line
## needs the platform's own spelling, or the statement fails and the check reports on nothing.
fWinPath(){ if ((isWindows)); then cygpath -m "$1"; else printf '%s' "$1"; fi ;}

## Checks that reach a confirmation need it to refuse rather than wait: stdin at EOF, and nothing
## for the prompt to fall back to. setsid guarantees that. Windows has no setsid, but PowerShell
## only ever reads redirected stdin, so </dev/null alone is enough there - which is why the pwsh
## one-liners below run either way. install.bash does fall back to /dev/tty, so its plan checks
## additionally need that open to fail.
declare -a noTty=()
canNoTty=0 shNoTty=0
if command -v setsid >/dev/null 2>&1; then noTty=(setsid); canNoTty=1; shNoTty=1
elif ((isWindows));                     then canNoTty=1; { : </dev/tty; } 2>/dev/null || shNoTty=1
fi
## A pty for the two checks that have to ANSWER the prompt rather than have it refuse: the plan
## is only printed to someone who could say yes, and the word accepted there is the point of one
## of them. No 'script' (Windows) means those two are skipped; the no-tty gate covers the rest.
hasPty=0
if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then hasPty=1; fi
fAnswerPrompt(){ local answer="$1"; shift; printf '%s\n' "${answer}" | script -qec "$*" /dev/null 2>&1 || true ;}

## Runs PowerShell source TEXT the way the documented one-liners do (iex / scriptblock), with
## stdin at EOF so a confirmation prompt refuses instead of blocking.
fPwshText(){ "${noTty[@]}" pwsh -NoProfile -Command "$1" </dev/null 2>&1 ;}
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
	## Every run says which build produced it, so a bug report carries that without being asked.
	## Not on the two paths that already print a version line, not under -q, and never on 'raw',
	## which hands its tool's stdout straight back to whatever is reading it.
	fAssertOut    "output names the build it came from"  '^gitsby v[0-9]' \
		bash -c "cd '${cloneA}' && '${gitsby}' -NoFetch status"
	fAssertNotOut "-q leaves it out"                     '^gitsby v[0-9]' \
		bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	fAssertNotOut "'raw' adds nothing to its tool's output"  '^gitsby v[0-9]' \
		bash -c "cd '${cloneA}' && '${gitsby}' raw git rev-parse --abbrev-ref HEAD 2>/dev/null"
	## Said once on the paths that were already saying it, rather than a banner above a copyright
	## line that repeats it.
	fAssert "--version names the build once"  \
		bash -c "[[ \"\$(cd '${cloneA}' && '${gitsby}' --version | grep -cE '^gitsby v[0-9]')\" == 1 ]]"
	fAssert "--help names the build once"     \
		bash -c "[[ \"\$(cd '${cloneA}' && '${gitsby}' --help | grep -cE '^gitsby v[0-9]')\" == 1 ]]"
	## --about and --donate are the two informational flags. Both answer outside a repo, and each
	## exists to hand over one link, so the link is what gets asserted.
	fAssertOut  "--about names the project page"   'github\.com/jim-collier/gitsby' \
		bash -c "cd '${work}' && '${gitsby}' --about"
	fAssertOut  "--donate names the sponsor page"  'github\.com/sponsors/jim-collier' \
		bash -c "cd '${work}' && '${gitsby}' --donate"
	fAssertOut  "--donate names the build"         '^gitsby v[0-9]' \
		bash -c "cd '${work}' && '${gitsby}' --donate"
	fAssert     "bare 'about' word works"          bash -c "cd '${work}' && '${gitsby}' about"
	fAssert     "bare 'donate' word works"         bash -c "cd '${work}' && '${gitsby}' donate"
	fAssertOut  "help lists both of them"          '\-\-about.*\-\-donate'  "${gitsby}" --help
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
	## One label for one thing: status called the current directory "Directory" while 'account
	## list' called it "Here", and both print it from the same tool a few lines apart.
	fAssertOut "status names the current directory"  '^Current dir \.+: '  bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "and whoami uses the same label"      '^Current dir \.+: '  bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch whoami"
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
	## 'pull' went away in v2 because it let you skip the commit. The compiled build takes the
	## word again as a spelling of the command that pulls AND commits, which structurally can't.
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
	fAssertOut    "and points at a real command"  'deliberately \(.*(update|pullcom)\) first'  bash -c "cd '${cloneA}' && '${gitsby}' -q br switch feat"
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
	fAssert     "bare release stands down when there is nothing new"  bash -c "cd '${cloneA}' && '${gitsby}' -q release"
	fAssertOut  "and says so"  'Nothing new to release since v1\.3\.1'  bash -c "cd '${cloneA}' && '${gitsby}' -q release 2>&1"
	fAssertOut  "and names the tag to push if it never landed"  'push it: git push origin v1\.3\.1'  bash -c "cd '${cloneA}' && '${gitsby}' -q release 2>&1"
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
	( cd "${cloneA}" && echo m2 > m2.txt )
	fAssert "update -m= joined form"  bash -c "cd '${cloneA}' && '${gitsby}' -q update -m='via -m= flag' && git log -1 --format=%s | grep -qx 'via -m= flag'"
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
	## Named per implementation: the scripts say 'update', the compiled build says 'pullcom' and
	## adds what offline changes about it - the pull is skipped, so only the commit half runs.
	fAssertOut  "and points at the command that commits"  "'[^']*(update|pullcom)'"   bash -c "cd '${offb}' && '${gitsby}' -q sync 'nope' 2>&1"
	fAssert     "and it refused before committing anything"  bash -c "cd '${offb}' && git status --porcelain | grep -q 's.txt' && rm -f '${offb}/s.txt'"
	fAssertFail "release refuses with an unreachable remote"  bash -c "cd '${offb}' && '${gitsby}' -q release v9.9.9"
	fAssertOut  "and says so before cutting a tag"  "'release' has nothing left to do"  bash -c "cd '${offb}' && '${gitsby}' -q release v9.9.9 2>&1"
	fAssert     "and no tag was cut"  bash -c "cd '${offb}' && ! git rev-parse -q --verify refs/tags/v9.9.9 >/dev/null"
	## A stub gh, because these two are about the offline refusal and nothing else. Without one they
	## depend on the box having gh installed: where it is missing, 'Not found in path: gh' comes
	## first, so the exit-code check passed for a reason that had nothing to do with being offline
	## and the message check failed. The stub never runs - the refusal is reached before it.
	local offBin="${work}/$1-offbin"; mkdir -p "${offBin}"
	fStub "${offBin}/gh" <<-'EOF'
		#!/usr/bin/env bash
		exit 0
	EOF
	fAssertFail "pr create refuses with an unreachable remote"  bash -c "cd '${offb}' && PATH='${offBin}:${PATH}' '${gitsby}' -q br switch offfeat >/dev/null 2>&1; PATH='${offBin}:${PATH}' '${gitsby}' -q pr create 'T'"
	fAssertOut  "and says which command needs origin"  "'pr create' has nothing left to do"  bash -c "cd '${offb}' && PATH='${offBin}:${PATH}' '${gitsby}' -q pr create 'T' 2>&1"
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
	## One call, not one per branch: eight branches were two thirds of everything this command
	## spawned. The plan has to say what the command runs, so both are one line - which is what
	## this asserts, since a per-branch plan would put 'landed' on a line of its own.
	fAssertPlan "br prune plans the merged branches, batched"  'git branch -D abandoned landed'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	fAssert     "merged branch gone locally"       bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/landed"
	fAssert     "the other merged one too"         bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/abandoned"
	fAssert     "merged branch gone on origin"     bash -c "cd '${prOrigin}' && ! git show-ref --verify --quiet refs/heads/landed"
	fAssert     "unmerged branch kept locally"     bash -c "cd '${prWork}' && git show-ref --verify --quiet refs/heads/wip"
	fAssert     "unmerged branch kept on origin"   bash -c "cd '${prOrigin}' && git show-ref --verify --quiet refs/heads/wip"
	fAssert     "protected branches kept"          bash -c "cd '${prWork}' && git show-ref --verify --quiet refs/heads/dev && git show-ref --verify --quiet refs/heads/main"
	fAssertOut  "and it says what it kept"  'Keeping \(not merged yet\): wip'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	fAssertOut  "nothing left to prune is a no-op"  'Nothing to prune'  bash -c "cd '${prWork}' && '${gitsby}' -q br prune"
	## The remote delete is batched too, and its own fixture: the run above pruned the one
	## before it, and a plan check has to actually run the command to see a plan.
	local prOrigin2="${work}/$1-pro2.git"; local prWork2="${work}/$1-prw2"
	git init --quiet --bare -b main "${prOrigin2}"
	git clone --quiet "${prOrigin2}" "${prWork2}" 2>/dev/null
	(
		cd "${prWork2}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev; git push --quiet -u origin dev
		for b in alpha beta; do
			git checkout --quiet -b "${b}" dev; echo "${b}" > "${b}.txt"; git add --all
			git commit --quiet -m "${b}"; git push --quiet -u origin "${b}"
		done
		git checkout --quiet dev
		git merge --quiet --no-ff alpha -m "merge alpha"
		git merge --quiet --no-ff beta  -m "merge beta"
		git push --quiet
	)
	fAssertPlan "and the remote delete is one call too"  'git push origin --delete alpha beta'  bash -c "cd '${prWork2}' && '${gitsby}' -q br prune"
	fAssert     "both went from origin"  bash -c "cd '${prOrigin2}' && ! git show-ref --verify --quiet refs/heads/alpha && ! git show-ref --verify --quiet refs/heads/beta"
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
	## The deletes go in one call, and git deletes what it can and still exits nonzero for the rest -
	## a branch checked out in another worktree, most often. Returning that ended the run with some
	## branches already deleted, origin untouched, and no count printed at all.
	(
		cd "${prWork}"
		git checkout --quiet dev
		for prHeld in held goes; do
			git checkout --quiet -b "${prHeld}" dev; echo "${prHeld}" > "${prHeld}.txt"
			git add --all; git commit --quiet -m "${prHeld}"; git push --quiet -u origin "${prHeld}"
		done
		git checkout --quiet dev
		git merge --quiet --no-ff held -m "merge held"; git merge --quiet --no-ff goes -m "merge goes"
		git push --quiet
		git checkout --quiet wip
		git worktree add --quiet "${work}/$1-prune-held" held
	)
	fAssertOut "a branch git can't delete doesn't stop the prune"  'Pruned 1 local, 1 on origin' \
		bash -c "cd '${prWork}' && '${gitsby}' -q br prune 2>&1"
	fAssertOut "and it names the one it couldn't"  "couldn't delete held here"  bash -c "cd '${prWork}' && '${gitsby}' -q br prune 2>&1"
	fAssert    "the deletable one still went"      bash -c "cd '${prWork}' && ! git show-ref --verify --quiet refs/heads/goes"
	fAssert    "and origin keeps the held branch"  bash -c "cd '${prOrigin}' && git show-ref --verify --quiet refs/heads/held"
	( cd "${prWork}" && git worktree remove --force "${work}/$1-prune-held" >/dev/null 2>&1 || true )

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
	mkdir -p "${pub2}"; cp -r "${pubDir}/." "${pub2}/"; rm -rf -- "${pub2:?}/.git"
	git init --quiet --bare -b main "${cn}/remote4.git"
	fAssertOut    "the listing names a stray dotfile"  '^    \.env$'  bash -c "cd '${pub2}' && '${gitsby}' -q repo connect '${cn}/remote4.git' 2>&1"
	local pub3="${cn}/publish3"
	mkdir -p "${pub3}"; cp -r "${pubDir}/." "${pub3}/"; rm -rf -- "${pub3:?}/.git"
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
	## to the OS login when the target carries none (the real behavior, and the whole bug),
	## -T greets as the key's account, and anything else fails so git's own fetch reports offline.
	local sid="${work}/$1-sshid"
	mkdir -p "${sid}/bin"
	fStub "${sid}/bin/ssh" <<-'EOF'
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
	local sidp="${sid}/bin:${PATH}"
	## Only a key file that exists gets named, so the stub has to nominate a real one - in a form
	## both builds can stat, which on Windows means a drive path, not a POSIX one.
	: > "${sid}/keyfile"
	local sidKey="${sid}/keyfile"
	((isWindows)) && sidKey="$(cygpath -m "${sid}/keyfile")"
	git init --quiet -b main "${sid}/proj"
	( cd "${sid}/proj" && echo s > s.txt && git add --all && git commit --quiet -m init && git remote add origin git@github.com:acme/api.git )
	local sidRun="cd '${sid}/proj' && PATH='${sidp}' FAKE_SSH_KEY='${sidKey}'"
	## The account the key authenticates as is the question this line exists to answer, so it
	## leads. The old line answered with the OS login, which is neither that nor the connect user.
	fAssertOut    "ssh line names the account the key authenticates as"  "SSH \.+: acmedev \("  bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	## Anchored to the SSH line: a bare 'git@github.com' also matches the Remote line right above
	## it, so the loose form was satisfied by the broken output too.
	fAssertOut    "ssh line names the user git actually connects as"     "SSH \.+: .*\(git@github\.com,"  bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	fAssertNotOut "ssh line never reports the OS login"                  'osuser'               bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
	fAssertOut    "the key is still reported"                            "key ${sidKey}"        bash -c "${sidRun} '${gitsby}' -q -NoFetch status"
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
	fStub "${tp}/bin/git" <<-EOF
		#!/usr/bin/env bash
		[[ "\$1" == "fetch" ]] && echo "\${GIT_TERMINAL_PROMPT-UNSET}" >> "\${TPROMPT_LOG}"
		exec "$(command -v git)" "\$@"
	EOF
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
	fStub "${gh}/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
## Test stub: deterministic gh, no network. Behavior driven by FAKE_GH_* env.
## GH_TOKEN is logged too: that is how a check sees which account the run picked for the remote.
[[ -n "${FAKE_GH_LOG:-}" ]] && echo "$* [GH_TOKEN=${GH_TOKEN:-}]" >> "${FAKE_GH_LOG}"
case "$1 $2" in
	"api user")    ## Whose token gh is holding - the exported one when there is one, like the real
	               ## thing. A probe run after the switch can then only ever answer with the account
	               ## it just switched to, which is what the pre-switch probe exists to avoid.
	               if [[ -n "${GH_TOKEN:-}" ]]; then echo "${GH_TOKEN#tok_}"; else echo "${FAKE_GH_LOGIN:-ghuser}"; fi ;;
	"auth token")  ## accounts gh holds, space separated; exit 1 for anyone else, like the real thing
	               case " ${FAKE_GH_ACCOUNTS:-} " in *" $4 "*) echo "tok_$4" ;; *) exit 1 ;; esac ;;
	"repo view")   ## Real gh distinguishes these on stderr, and gitsby now reads it: a name that
	               ## resolves to nothing is not the same answer as an API it couldn't reach.
	               case "${FAKE_GH_VIEW:-}" in
	                 notfound) echo "GraphQL: Could not resolve to a Repository with the name '$3'. (repository)" >&2; exit 1 ;;
	                 offline)  echo "error connecting to api.github.com" >&2; exit 1 ;;
	                 empty)    echo true ;;
	                 nonempty) echo false ;;
	               esac ;;
	"config get")  echo "${FAKE_GH_PROTO:-https}" ;;
	"pr list")     echo "${FAKE_GH_EXISTING:-}" ;;  ## an already-open PR number for this branch, or nothing
	"pr create")   echo "https://github.com/me/proj/pull/${FAKE_GH_NEWPR:-1}" ;;
	"pr review")   : ;;  ## gitsby treats approval as best-effort; nothing to fake
	"pr view")     ## A number gh can't resolve fails, like the real thing - it does not answer with
	               ## nothing and exit 0.
	               [[ "${FAKE_GH_PRVIEW:-}" == fail ]] && { echo "GraphQL: Could not resolve to a PullRequest" >&2; exit 1 ;}
	               echo "${FAKE_GH_HEAD:-$(git branch --show-current)}"     ## the PR's own head branch
	               echo "${FAKE_GH_STATE:-OPEN}" ;;                          ## ... and whether it is still open
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
	## An ssh-protocol connect now probes the identity of the url it is about to set, so this dir
	## needs an ssh too - otherwise the suite would ask the real github.com who we are. Answers with
	## the same login the fake gh reports, so these checks see a match and carry on.
	fStub "${gh}/bin/ssh" <<-'EOF'
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
	local ghp="${gh}/bin:${PATH}"

	## create: repo doesn't exist yet -> gitsby inits + commits, the stub creates and pushes
	mkdir -p "${gh}/create"; echo c > "${gh}/create/c.txt"
	fAssert "repo create makes a missing repo"  bash -c "cd '${gh}/create' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/created.git' FAKE_GH_LOG='${gh}/create.log' '${gitsby}' -q repo create me/proj"
	fAssert "created repo got the commit"                bash -c "cd '${gh}/created.git' && git ls-tree --name-only main | grep -qx c.txt"
	fAssert "create defaulted to a private repo"         bash -c "grep -q -- '--private' '${gh}/create.log'"
	mkdir -p "${gh}/pub"; echo p > "${gh}/pub/p.txt"
	fAssert "repo create --public makes a public repo"  bash -c "cd '${gh}/pub' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/pub.git' FAKE_GH_LOG='${gh}/pub.log' '${gitsby}' -q --public repo create me/proj && grep -q -- '--public' '${gh}/pub.log'"

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
	## gh exits nonzero for a name that resolves to nothing and for an API it can't reach alike.
	## Taking the second as the first sent you off to create a repo you already have - and these two
	## commands skip the pre-command fetch (no origin yet), so this is where offline surfaces.
	## Its own directory: a build that does NOT refuse here would create a remote and set an origin,
	## and every check after it would then be about a connected repo instead.
	mkdir -p "${gh}/offl"; echo x > "${gh}/offl/x.txt"
	fAssertFail "repo create refuses when it can't reach GitHub"   bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo create me/proj"
	fAssertOut  "and says that, not that the repo is missing"  'no telling whether it exists' \
		bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo create me/proj 2>&1"
	fAssertOut  "and repeats what gh said"  'error connecting to api.github.com' \
		bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo create me/proj 2>&1"
	fAssertFail "repo connect refuses when it can't reach GitHub"  bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo connect me/proj"
	fAssertNotOut "and does not point at repo create"  'repo create me/proj' \
		bash -c "cd '${gh}/offl' && PATH='${ghp}' FAKE_GH_VIEW=offline '${gitsby}' -q repo connect me/proj 2>&1"
	fAssertFail "repo create refuses a plain url"                       bash -c "cd '${gh}/split' && PATH='${ghp}' '${gitsby}' -q repo create '${gh}/backing-https.git'"
	## Keep the insteadOf rewrite: this dir's origin is a real github.com URL, and the
	## pre-command fetch runs before the refusal we're testing for.
	## The account is resolved from origin, and these two have none yet - but the repo they are
	## about to publish to is on the command line, and it is that owner's account that should do the
	## publishing. The late re-selection was a no-op behind the already-applied guard, so it went
	## out as gh's own account instead, silently.
	mkdir -p "${gh}/rc-acct"; echo x > "${gh}/rc-acct/x.txt"
	fAssert "repo create publishes as the account that owns the target" \
		bash -c "cd '${gh}/rc-acct' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_PROTO=https FAKE_GH_LOGIN=other FAKE_GH_ACCOUNTS='other acme' FAKE_GH_LOG='${gh}/rc-acct.log' FAKE_GH_REMOTE='${gh}/rc-acct.git' '${gitsby}' -q repo create acme/proj && grep -q 'repo create.*GH_TOKEN=tok_acme' '${gh}/rc-acct.log'"
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
	## A number gh can't resolve used to fall back to the current branch, so the plan was
	## confidently about the wrong thing and the run died after it had been confirmed - the exact
	## shape preflight exists to prevent.
	fAssertFail "pr ok refuses a PR gh can't read"  bash -c "cd '${prx}' && PATH='${ghp}' FAKE_GH_PRVIEW=fail '${gitsby}' -q pr ok 99"
	fAssertOut  "and names the number rather than acting on the current branch"  "Can't read PR #99" \
		bash -c "cd '${prx}' && PATH='${ghp}' FAKE_GH_PRVIEW=fail '${gitsby}' -q pr ok 99 2>&1"
	fAssertFail "pr ok refuses a PR that is no longer open"  bash -c "cd '${prx}' && ${prxEnv} FAKE_GH_STATE=MERGED '${gitsby}' -q pr ok 7"
	fAssertOut  "and says which state it is in"  'is merged, not open' \
		bash -c "cd '${prx}' && ${prxEnv} FAKE_GH_STATE=MERGED '${gitsby}' -q pr ok 7 2>&1"

	## Standing on the PR's own branch, pushed once WITHOUT -u: '@{u}' answers nothing at all, so
	## the ahead check passed and gh's '--delete-branch' took the unpushed commits with it. That is
	## the one arrangement where the guard has to ask about origin's copy by name.
	mkdir -p "${gh}/prnou"
	git init --quiet --bare -b main "${gh}/prnou/origin.git"
	local pnu="${gh}/prnou/c"
	git clone --quiet "${gh}/prnou/origin.git" "${pnu}" 2>/dev/null
	(
		cd "${pnu}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b nofeat && echo work > work.txt && git add --all && git commit --quiet -m work
		git push --quiet origin nofeat   ## no -u: on origin, but nothing here tracks it
		echo more >> work.txt && git add --all && git commit --quiet -m "never pushed"
	)
	local pnuEnv="PATH='${ghp}' FAKE_GH_BASE=dev FAKE_GH_HEAD=nofeat"
	fAssert     "the fixture branch really has no upstream"  bash -c "cd '${pnu}' && ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1"
	fAssertFail "pr ok refuses unpushed commits with no upstream to notice them"  bash -c "cd '${pnu}' && ${pnuEnv} '${gitsby}' -q pr ok 7"
	fAssertOut  "and names the branch"  "'nofeat' has commits that never reached origin" \
		bash -c "cd '${pnu}' && ${pnuEnv} '${gitsby}' -q pr ok 7 2>&1"
	fAssert     "and the commit is still reachable"  bash -c "cd '${pnu}' && git log -1 --pretty=%s nofeat | grep -qx 'never pushed'"

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

	## A branch whose name starts with a dash can't be typed here - the parser reads a leading dash
	## as an option of ours - but a clone brings whatever the remote has, and then git reads it as
	## options too: 'git checkout -evil' answers "unknown switch". There is no separator that
	## rescues it in that position, so it is refused once, up front.
	local dsh="${work}/$1-dash"
	mkdir -p "${dsh}"
	git init --quiet --bare -b main "${dsh}/origin.git"
	git init --quiet -b main "${dsh}/seed"
	(
		cd "${dsh}/seed" || exit 1
		echo d > d.txt && git add --all && git commit --quiet -m init
		git push --quiet "${dsh}/origin.git" 'HEAD:refs/heads/-evil'
	)
	( cd "${dsh}/origin.git" && git symbolic-ref HEAD refs/heads/-evil )
	git clone --quiet "${dsh}/origin.git" "${dsh}/c" 2>/dev/null
	fAssert     "the fixture really checked out a dash-led branch"  bash -c "[[ \"\$(git -C '${dsh}/c' branch --show-current)\" == -evil ]]"
	fAssertFail "a dash-led branch name is refused before it reaches git"  bash -c "cd '${dsh}/c' && '${gitsby}' -q pullcom 'x'"
	fAssertOut  "and says why"  'reads it as an option'  bash -c "cd '${dsh}/c' && '${gitsby}' -q pullcom 'x' 2>&1"
	fAssert     "but status still reports the repo it is wrong about"  bash -c "cd '${dsh}/c' && '${gitsby}' -q status >/dev/null"

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
	## -NoFetch is spelled the same to both ports (bash normalizes it), so these need no branch.
	fAssert "--any-identity leaves gh's active account alone" \
		bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/any.log' '${gitsby}' -q -NoFetch --any-identity pr && grep -q 'GH_TOKEN=\]' '${idn}/any.log'"
	## An account configured for the path wins over the remote's owner, and is the only one of the
	## two that can answer before a remote exists. Set locally here; in practice an includeIf on the
	## repo path supplies it, the same way the ssh key and commit identity already arrive.
	git clone --quiet "${idn}/backing.git" "${idn}/cfg" 2>/dev/null
	(
		cd "${idn}/cfg" || exit 1
		git remote set-url origin git@github.com:acme/proj.git
		git config gitsby.ghAccount configured
	)
	fAssert "a configured account wins over the remote's owner" \
		bash -c "cd '${idn}/cfg' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme configured' FAKE_GH_LOG='${idn}/cfg.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=tok_configured' '${idn}/cfg.log'"
	## No origin at all: nothing to parse an owner from, so only the configured account can answer.
	## Asked through 'raw gh' rather than 'pr': a repo with no remote has nowhere to propose a pull
	## request to, and pr now says so before it selects anything. Which is the right answer, and
	## makes it the wrong vehicle for a question about account selection. 'identity' is no good
	## either - its gh probe deliberately runs BEFORE the token lands, so the log never sees one.
	## 'raw gh' is the documented scripted surface and runs as whatever was selected.
	mkdir -p "${idn}/noremote"
	(
		cd "${idn}/noremote" || exit 1
		git init --quiet -b main . && git commit --quiet --allow-empty -m init
		git config gitsby.ghAccount configured
	)
	fAssert "a configured account applies with no remote at all" \
		bash -c "cd '${idn}/noremote' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse configured' FAKE_GH_LOG='${idn}/nore.log' '${gitsby}' -q -NoFetch raw gh api user && grep -q 'GH_TOKEN=tok_configured' '${idn}/nore.log'"
	## And the refusal itself, which is what makes the line above the right shape.
	fAssertOut "pr refuses outright with no remote to propose to"  'No .origin. remote' \
		bash -c "cd '${idn}/noremote' && ${idEnv} '${gitsby}' -q -NoFetch pr 2>&1"
	## The token file covers a box where that account was never logged in to gh. Absent, unreadable
	## and empty must all fall back to gh's own account rather than fail - a checkout that was never
	## set up this way still has to work.
	## Written into the GLOBAL config, which is where 'account apply' puts it and the only scope
	## gitsby reads it from: the value names any readable file, and its contents go into GH_TOKEN
	## for every child - so a repo you cloned from a stranger does not get to choose it.
	local idnGlobal="${idn}/gcfg"; : > "${idnGlobal}"
	local idTok="GIT_CONFIG_GLOBAL='${idnGlobal}'"
	printf 'tok_fromfile\n' > "${idn}/token.txt"
	fAssert "the token file is used when gh has no such account" \
		bash -c "cd '${idn}/cfg' && ${idTok} git config --global gitsby.ghTokenFile '${idn}/token.txt' && ${idTok} ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/file.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=tok_fromfile' '${idn}/file.log'"
	## The same key set by the repo itself is ignored: it is the one config value that turns into a
	## file read plus an environment variable handed to gh and git.
	fAssert "a repo-local token file is not honored" \
		bash -c "cd '${idn}/cfg' && git config gitsby.ghTokenFile '${idn}/token.txt' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/localtok.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/localtok.log'"
	fAssert "a missing token file falls back instead of failing" \
		bash -c "cd '${idn}/cfg' && ${idTok} git config --global gitsby.ghTokenFile '${idn}/absent.txt' && ${idTok} ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/miss.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/miss.log'"
	: > "${idn}/blank.txt"
	fAssert "an empty token file falls back instead of failing" \
		bash -c "cd '${idn}/cfg' && ${idTok} git config --global gitsby.ghTokenFile '${idn}/blank.txt' && ${idTok} ${idEnv} FAKE_GH_ACCOUNTS='someoneelse' FAKE_GH_LOG='${idn}/blank.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=\]' '${idn}/blank.log'"
	## gh's own store outranks the file, so a rotated login is not shadowed by a stale token on disk.
	fAssert "gh's own account outranks the token file" \
		bash -c "cd '${idn}/cfg' && ${idTok} git config --global gitsby.ghTokenFile '${idn}/token.txt' && ${idTok} ${idEnv} FAKE_GH_ACCOUNTS='someoneelse configured' FAKE_GH_LOG='${idn}/pref.log' '${gitsby}' -q -NoFetch pr && grep -q 'GH_TOKEN=tok_configured' '${idn}/pref.log'"
	( cd "${idn}/cfg" && git config --unset gitsby.ghTokenFile )
	## Naming the account this run replaced has to be asked BEFORE the token lands, or the probe
	## answers as the token just exported and the line can only ever say what it already knows.
	fAssertOut "the identity block names the account gh was on before the switch"  "gh's active account is 'someoneelse'" \
		bash -c "cd '${idn}/cfg' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse configured' '${gitsby}' -q -NoFetch identity 2>&1"

	## The remote's owner is the step that needs no configuration at all, and it is the one step a
	## clone cannot use. The repo being cloned is as likely a stranger's as ours, and the repo we are
	## standing in is not the one being cloned - so asked either way it names an account that has
	## nothing to do with the clone, and quietly authenticates as it.
	: > "${idn}/clone.log"
	fAssert "a clone asks for no token on the strength of the surrounding repo's owner" \
		bash -c "cd '${idn}/c' && ${idEnv} FAKE_GH_ACCOUNTS='someoneelse acme' FAKE_GH_LOG='${idn}/clone.log' '${gitsby}' -q repo clone '${idn}/backing.git' '${idn}/cloned' >/dev/null && ! grep -q -- '--user acme' '${idn}/clone.log'"

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
		echo "readme v1" > README.md && mkdir -p src-go && echo shipped > src-go/main.go
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
	fAssertOut "a hotfix touching the shipped source warns about the release"  'changes shipped code' \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix code >/dev/null 2>&1; echo v2 > '${hfc}/src-go/main.go'; '${gitsby}' -q -NoFetch update wip >/dev/null 2>&1; '${gitsby}' -q -NoFetch br land 'Fix' 2>&1"
	## The warning reads the branch tip, and 'br land' is what commits the working tree - so an
	## uncommitted edit to it (the ordinary way of making one) has to be checked for after that.
	fAssertOut "a hotfix warns about shipped code even when the edit is uncommitted"  'changes shipped code' \
		bash -c "cd '${hfc}' && '${gitsby}' -q -NoFetch br hotfix uncommitted >/dev/null 2>&1; echo v3 > '${hfc}/src-go/main.go'; '${gitsby}' -q -NoFetch br land 'Fix uncommitted' 2>&1"
	## Every other check here runs from the top of the tree. A pathspec is read relative to the
	## current directory, so from anywhere else it matched nothing, git exited 0 with no output,
	## and the warning went missing on exactly the commands you run from wherever you are working.
	mkdir -p "${hfc}/docs"
	fAssertOut "the shipped-code warning survives being run from a subdirectory"  'changes shipped code' \
		bash -c "cd '${hfc}/docs' && '${gitsby}' -q -NoFetch br hotfix subdir >/dev/null 2>&1; echo v4 > '${hfc}/src-go/main.go'; '${gitsby}' -q -NoFetch br land 'Fix from below' 2>&1"
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
	cp "${gh}/bin/gh" "${id}/bin/gh"; fStubShim "${id}/bin/gh"
	## insteadOf is no good here: 'git remote get-url' returns the REWRITTEN url, so there would be
	## no ssh url left to probe. Instead the stub doubles as the transport, so origin stays an
	## scp-style url while every push and fetch lands in a local bare.
	fStub "${id}/bin/ssh" <<-'EOF'
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
	local anyIdFlag="--any-identity"
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

	## 'sync' pushes with git rather than writing through gh, so the comparison above never covered
	## it: the command that sends your work to a remote compared nothing at all. This asks the other
	## half of the same question - is the account this folder resolved to the one origin will
	## actually authenticate as? Last in this block because a passing sync really does push.
	local idCanon="${idc}"; ((isWindows)) && idCanon="$( cd "${idc}" && pwd -W )"
	cat > "${id}/mine.shcl" <<-EOF
		account.mine.path      = ${idCanon}
		account.mine.ghAccount = alice
	EOF
	cat > "${id}/theirs.shcl" <<-EOF
		account.mine.path      = ${idCanon}
		account.mine.ghAccount = bob
	EOF
	local idSync="cd '${idc}' && ${idEnv} GITSBY_CONFIG= FAKE_SSH_LOGIN=bob"
	fAssertFail   "sync refuses when the folder's account is not the key's" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' sync 'W'"
	fAssertOut    "and the refusal names both"  "account is 'alice'.*authenticates as 'bob'" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' sync 'W' 2>&1 || true"
	fAssert       "the refusal happens before the push" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' sync 'W'; ! git -C '${idc}' ls-remote --heads origin idfeat 2>/dev/null | grep -q idfeat"
	fAssertNotOut "--any-identity says the difference is intended"  "authenticates as 'bob'" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --any-identity --config '${id}/mine.shcl' sync 'W' 2>&1 || true"
	## No configured account at all: the owner of the remote is a guess about a repo, not a claim
	## about who you are, so comparing it would fire for every single-account user.
	fAssertNotOut "an unconfigured account is never compared"  'authenticates as' \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config /dev/null sync 'W' 2>&1 || true"
	fAssertNotOut "and a matching account does not fire"  'authenticates as' \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/theirs.shcl' sync 'W' 2>&1 || true"
	## Keyed on pushing, not on mutating: 'pullcom' commits locally and sends nothing, so the key
	## origin would push with is nothing to refuse over - and the refusal paid a live ssh probe for
	## a command that never reaches the network.
	fAssert       "pullcom is not refused over the key origin would push with" \
		bash -c "${idSync} '${gitsby}' -q -NoFetch --config '${id}/mine.shcl' pullcom 'Local only'"

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
	local vg="${work}/vgate"
	mkdir -p "${vg}/bin"
	## Raise the floor past any real bash so the gate fires on this one. Everything below the
	## gate is 4.x syntax, so a clean refusal also proves nothing below it was reached.
	sed 's/-lt 4 \]\]/-lt 99 ]]/' "${root}/legacy/bin/gitsby" > "${vg}/gitsby"
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
	fAssert "gitsby resolves bash through PATH, not /bin/bash"  bash -c "head -1 '${root}/legacy/bin/gitsby' | grep -qx '#!/usr/bin/env bash'"

	## Installer options. These run once, not per implementation, and never reach the network:
	## every check either exits during argument parsing, or uses --release (which names the ref
	## outright, so no latest-release lookup) and stops at the confirmation.
	local inst="${root}/legacy/install.bash"
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
	## Reading the printed plan needs the confirmation to refuse rather than block. install.bash
	## falls back to /dev/tty when stdin is not one, so this needs setsid - or, failing that, a
	## shell that has no /dev/tty to fall back to. Neither, and there is no safe way to ask.
	if ((shNoTty)); then
		local iHome="${work}/insthome"; mkdir -p "${iHome}"
		local iRun="${noTty[*]} env HOME='${iHome}' bash '${inst}' --release dev"
		fAssertOut "--target user installs under HOME"      "insthome/\.local/bin/gitsby"  bash -c "${iRun} --target user </dev/null"
		fAssertOut "--target system installs system-wide"   '/usr/local/bin/gitsby'        bash -c "${iRun} --target system </dev/null"
		fAssertOut "-s still means --target system"         '/usr/local/bin/gitsby'        bash -c "${iRun} -s </dev/null"
		fAssertOut "--arch is taken but reported inert"     'Ignore --arch arm64'          bash -c "${iRun} --arch arm64 </dev/null"
		## Whether the download will be checked belongs in the plan, where it can still be
		## declined. It used to be reported only afterwards, and on the dev path not at all -
		## so the one route that installs an unverified file was the quiet one.
		fAssertOut "the dev plan says it will not verify"   'NOT verify the download'      bash -c "${iRun} --target user </dev/null"
	fi
	## The PowerShell installer's ValidateSet does the same job as the case arms above.
	if command -v pwsh >/dev/null 2>&1; then
		local instPs="${root}/legacy/install.ps1"
		fAssertFail "ps installer refuses a bad -Target"      pwsh -NoProfile -File "${instPs}" -Target bogus
		fAssertFail "ps installer refuses a bad -Arch"        pwsh -NoProfile -File "${instPs}" -Arch sparc
		fAssertFail "ps installer refuses a bad -Release"     pwsh -NoProfile -File "${instPs}" -Release beta
		fAssertFail "ps installer refuses -Release with -Ref" pwsh -NoProfile -File "${instPs}" -Release dev -Ref main
		fAssertOut  "ps installer refuses a path-shaped -Ref"  'not a path'  pwsh -NoProfile -File "${instPs}" -Yes -Ref '../../evil/repo/main'
		## Same as the Bash plan above: state up front whether the download gets checked, and
		## - on Windows - that PATH is about to be changed, since nothing else there puts the
		## install directory on it and the install would otherwise finish uncallable by name.
		fAssertOut  "ps dev plan says it will not verify"  'NOT verify the download' \
			bash -c "pwsh -NoProfile -File '${instPs}' -Release dev </dev/null 2>&1"
		if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
			fAssertOut "ps plan announces the PATH change"  'to your account PATH' \
				bash -c "pwsh -NoProfile -File '${instPs}' -Release dev </dev/null 2>&1"
		fi
		## Git Bash rewrites a unix-absolute argument into a Windows path before the native
		## pwsh sees it, so '/etc/passwd' would arrive as 'C:/Program Files/Git/etc/passwd'
		## and be refused for the space rather than for being a path. Excluding that one
		## prefix keeps the -File path converting as normal. Ignored off Windows.
		fAssertOut  "ps installer refuses an absolute -Ref"    'not a path' \
			env MSYS2_ARG_CONV_EXCL='/etc' pwsh -NoProfile -File "${instPs}" -Yes -Ref '/etc/passwd'
		## The documented one-liners are 'iex' and a scriptblock, neither of which is a script
		## file - so -File coverage alone says nothing about them. Both must bind their
		## parameters, refuse without a tty, and leave the calling session alive and unaltered.
		## These reach the confirmation prompt, so it has to REFUSE rather than wait: stdin at
		## EOF, and nothing to fall back to - setsid where there is one, and on Windows just the
		## redirect, since Read-Host reads that and never reaches for a terminal.
		if ((canNoTty)); then
			local instDev="${root}/legacy/install-dev.ps1"
			## These paths are read by .NET, not by the shell, so they need native spelling.
			local instPsNative="" instDevNative=""
			instPsNative="$(  fWinPath "${instPs}"  )"
			instDevNative="$( fWinPath "${instDev}" )"
			## The system install location is the platform's own, so the plan line that proves
			## -Target bound differs: /usr/local/bin, or Program Files on Windows. Verified it
			## still discriminates - a user-target plan names AppData\Local\Programs instead.
			local sysBinPat='/usr/local/bin'
			((isWindows)) && sysBinPat='Program Files'
			## Decode the bytes ourselves rather than Get-Content, which quietly drops a BOM.
			## irm doesn't, so a BOM'd file reaches iex with U+FEFF glued to the shebang and
			## the first line stops being a comment - which is how a BOM sat here undetected.
			local readInst="\$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes('${instPsNative}'))"
			fAssertOut "iex form reaches the plan"          'gitsby installer'  fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "and refuses without a tty"          'CAUGHT: Aborted'   fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "and leaves the session alive"       'HOST ALIVE'        fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "scriptblock form binds its options" "${sysBinPat}"      fPwshText "${readInst}; try { & ([scriptblock]::Create(\$t)) -Ref main -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "and leaves the session alive too"   'HOST ALIVE'        fPwshText "${readInst}; try { & ([scriptblock]::Create(\$t)) -Ref main -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "installer leaks no StrictMode"      'strict stayed off' fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { }; try { \$q = \$neverSet; 'strict stayed off' } catch { 'STRICT LEAKED' }"
			fAssertOut "installer leaks no ErrorAction"     'EAP=Continue'      fPwshText "${readInst}; try { \$t | Invoke-Expression } catch { }; \"EAP=\$ErrorActionPreference\""
			fAssertOut "dev setup's iex form asks first"    'CAUGHT: Aborted'   fPwshText "\$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes('${instDevNative}')); try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }"
		fi
		## Byte 0 must be the shebang: a BOM ahead of it means the kernel won't run the
		## file directly either, which the one-liner checks above can't see.
		local psFile=""
		for psFile in "${root}"/legacy/bin/gitsby.ps1 "${root}"/legacy/install.ps1 "${root}"/legacy/install-dev.ps1; do
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

	## The shipping installers, at the repo root. What they fetch is a per-platform binary, so
	## everything below the argument parse - the release lookup, SHA256SUMS, the plan - needs the
	## network. These checks stop short of it: parsing, the refusals, and the pins on the parts a
	## live run would have to reach. The download-checksum-run contract itself is proved by
	## release.bash phase 3, against a real published release.
	local goInst="${root}/install.bash"
	fAssert     "go installer --help works"                   bash -c "bash '${goInst}' --help"
	fAssertOut  "and documents --target"                      '\-\-target user\|system'  bash -c "bash '${goInst}' --help"
	fAssertOut  "and documents --arch"                        '\-\-arch amd64\|arm64'    bash -c "bash '${goInst}' --help"
	fAssertOut  "and documents --tag"                         '\-\-tag TAG'               bash -c "bash '${goInst}' --help"
	fAssertOut  "go installer refuses a bad --target"         "\-\-target takes"          bash -c "bash '${goInst}' --target bogus"
	fAssertOut  "go installer refuses a valueless --target"   "\-\-target needs a value"  bash -c "bash '${goInst}' --target"
	## --arch names the asset now rather than being accepted and ignored, so the two spellings
	## the release publishes are the two it takes.
	fAssertOut  "go installer refuses a bad --arch"           "\-\-arch takes"            bash -c "bash '${goInst}' --arch sparc"
	## '--release dev' installed the tip of a branch while the product was a script. A branch has
	## no build behind it now, so the flag is answered by name rather than left to fail as an
	## unknown option - the same treatment --offline got.
	fAssertOut  "go installer names the dropped --release dev" 'no .--release dev. any more' bash -c "bash '${goInst}' --release dev"
	fAssertOut  "and says so before touching the network"      'build the tip yourself'      bash -c "bash '${goInst}' --release dev"
	fAssertOut  "go installer refuses any other --release"     'now takes neither'           bash -c "bash '${goInst}' --release beta"
	## A tag is interpolated into a download URL, so a path-shaped one installs a binary from
	## some other repo while the printed plan still names this one.
	fAssertOut  "go installer refuses a path-shaped --tag"     'not a path'                  bash -c "bash '${goInst}' -y --tag '../../evil/repo/main'"
	fAssertOut  "go installer refuses an absolute --tag"       'not a path'                  bash -c "bash '${goInst}' -y --tag '/etc/passwd'"
	fAssertOut  "go installer refuses a shell-shaped --tag"    "aren't valid in a git tag"   bash -c "bash '${goInst}' -y --tag 'a b;id'"
	## --ref was this option's name for two releases. Every published spelling is permanent.
	fAssertOut  "--ref still binds as --tag"                   'not a path'                  bash -c "bash '${goInst}' -y --ref '../x'"
	## Under Git Bash the destination is a Windows one and nothing there puts it on PATH, so the
	## Bash installer hands Windows to the one that finishes the job. A fake uname reaches the
	## arm from any box; it fires during detection, so no network either.
	local wg="${work}/wininst"; mkdir -p "${wg}/bin"
	printf '#!/usr/bin/env bash\necho MINGW64_NT-10.0-22631\n' > "${wg}/bin/uname"; chmod +x "${wg}/bin/uname"
	fAssertOut  "go installer sends Windows to install.ps1"    'use the PowerShell installer' \
		bash -c "PATH='${wg}/bin:${PATH}' bash '${goInst}' -y"
	## The release lookup, with the network stood in for. Under 'set -e' an assignment carries
	## its command's status, so both of these used to end the run silently at the lookup - no
	## message, no fallback, and an exit code straight from curl or wget.
	local lk="${work}/lookup"; mkdir -p "${lk}/bin"
	printf '#!/usr/bin/env bash\nexit 6\n' > "${lk}/bin/curl"; chmod +x "${lk}/bin/curl"
	fAssertOut  "go installer survives a failing curl"        'work out the latest release' \
		bash -c "PATH='${lk}/bin:${PATH}' bash '${goInst}' -y"
	## wget-only box: wget answers a declined redirect with exit 8 even though the header it was
	## sent for is right there, so success looked like failure. curl has to be genuinely absent
	## to reach that arm, hence a PATH of just the tools the installer gets that far on.
	local farm="${work}/nocurl"; mkdir -p "${farm}"
	local farmTool="" farmPath=""
	for farmTool in bash uname tr sed head cut cat mktemp rm paste sha256sum shasum openssl; do
		farmPath="$( command -v "${farmTool}" 2>/dev/null || true )"
		if [[ -n "${farmPath}" ]]; then ln -sf "${farmPath}" "${farm}/${farmTool}"; fi
	done
	# shellcheck disable=SC2016  ## the stub's own text; the inner shell does the expanding.
	printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in */releases/latest) echo "  Location: https://github.com/jim-collier/gitsby/releases/tag/v9.9.9" >&2; exit 8 ;; esac; done\nexit 1\n' > "${farm}/wget"
	chmod +x "${farm}/wget"
	fAssertOut  "go installer reads a tag out of wget's exit 8" 'v9\.9\.9' \
		bash -c "PATH='${farm}' '${farm}/bash' '${goInst}' -y"
	## Pins on what a live run reaches. Every route is a release asset now, so every route is
	## verified - there is no unverified branch of the plan left to promise around.
	fAssert     "go installer installs to the documented dirs" \
		bash -c "grep -q 'HOME}/.local/bin' '${goInst}' && grep -q '/usr/local/bin' '${goInst}'"
	fAssert     "go installer fetches the per-platform asset"  \
		bash -c "grep -q 'asset=\"gitsby-' '${goInst}'"
	fAssert     "go installer promises no unverified route"   bash -c "! grep -q 'NOT verify' '${goInst}'"

	## 'releases/latest' is the newest release that is NOT a pre-release, so a repo whose newest
	## publication is one has nothing there - and the fallback asked the same endpoint again.
	## A stub curl answers the list endpoint and nothing else, which is exactly that repo.
	local prl="${work}/prerel"; mkdir -p "${prl}/bin"
	fStub "${prl}/bin/curl" <<-'CURLEOF'
		#!/usr/bin/env bash
		url=""
		for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
		case "${url}" in
			*/repos/*/releases) printf '[\n  {\n    "tag_name": "v9.9.9-rc1",\n    "prerelease": true\n  }\n]\n'; exit 0 ;;
		esac
		exit 22
	CURLEOF
	fAssertOut "go installer falls back to a pre-release when that is all there is"  'v9\.9\.9-rc1' \
		bash -c "PATH='${prl}/bin:${PATH}' bash '${goInst}' -y 2>&1"
	fAssertOut "and says that is what it did"  'No full release yet' \
		bash -c "PATH='${prl}/bin:${PATH}' bash '${goInst}' -y 2>&1"

	## The list endpoint is ordered by publish date, so a backported fix cut after a newer
	## release lists first: the fallback has to version-sort rather than take the head. The
	## payload here is also packed on one line, which is the other half of the same check -
	## the scrape must not depend on GitHub pretty-printing the JSON.
	local vsort="${work}/vsort"; mkdir -p "${vsort}/bin"
	fStub "${vsort}/bin/curl" <<-'CURLEOF'
		#!/usr/bin/env bash
		url=""
		for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
		case "${url}" in
			*/repos/*/releases) printf '[{"tag_name":"v2.1.1","prerelease":false},{"tag_name":"v3.0.0","prerelease":false}]'; exit 0 ;;
		esac
		exit 22
	CURLEOF
	fAssertOut "go installer takes the highest version from the fallback, not the newest-listed" 'v3\.0\.0' \
		bash -c "PATH='${vsort}/bin:${PATH}' bash '${goInst}' -y 2>&1"

	## A whole install, with the network stood in for: resolve, verify, place, run. What this
	## proves is that the staged-and-renamed path works end to end; the pin below it is what
	## discriminates, since writing in place would pass this too.
	local ei="${work}/instend"; mkdir -p "${ei}/bin" "${ei}/home"
	printf '#!/usr/bin/env bash\necho "gitsby v1.2.3 (stand-in)"\n' > "${ei}/asset"
	local eiHash=""; eiHash="$( sha256sum "${ei}/asset" | cut -d' ' -f1 )"
	: > "${ei}/SHA256SUMS"
	local eiOs="" eiArch=""
	for eiOs in linux darwin freebsd; do
		for eiArch in amd64 arm64; do echo "${eiHash}  gitsby-${eiOs}-${eiArch}" >> "${ei}/SHA256SUMS"; done
	done
	fStub "${ei}/bin/curl" <<-'CURLEOF'
		#!/usr/bin/env bash
		url=""
		for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
		case "${url}" in
			*/releases/latest)            printf 'https://github.com/jim-collier/gitsby/releases/tag/v1.2.3'; exit 0 ;;
			*/download/v1.2.3/SHA256SUMS) cat "${FAKE_SUMS}"; exit 0 ;;
			*/download/v1.2.3/gitsby-*)   cat "${FAKE_ASSET}"; exit 0 ;;
		esac
		exit 22
	CURLEOF
	local eiEnv="HOME='${ei}/home' PATH='${ei}/bin:${PATH}' FAKE_SUMS='${ei}/SHA256SUMS' FAKE_ASSET='${ei}/asset'"
	fAssertOut "go installer installs, verifies and runs the binary"  'gitsby v1\.2\.3 \(stand-in\)' \
		bash -c "env ${eiEnv} bash '${goInst}' -y 2>&1"
	fAssert    "and a re-install replaces it cleanly" \
		bash -c "env ${eiEnv} bash '${goInst}' -y >/dev/null 2>&1 && '${ei}/home/.local/bin/gitsby' --version | grep -q 'stand-in'"
	fAssert    "and leaves no staging file behind" \
		bash -c "! compgen -G '${ei}/home/.local/bin/.gitsby.install.*' >/dev/null"
	## Written straight to the final path, an interrupt mid-copy leaves a truncated executable
	## where the real one should be, and a write over a copy that is running fails outright.
	## Reproducing either needs a signal or a live process, so the staging is pinned here.
	fAssert    "go installer stages beside the target rather than writing in place" \
		bash -c "grep -q 'staged=\"\${destDir}/' '${goInst}' && grep -qE 'mv -f \"\\\$\{staged\}\"' '${goInst}'"
	if command -v pwsh >/dev/null 2>&1; then
		local goInstPs="${root}/install.ps1"
		fAssertFail "go ps installer refuses a bad -Target"    pwsh -NoProfile -File "${goInstPs}" -Target bogus
		fAssertFail "go ps installer refuses a bad -Arch"      pwsh -NoProfile -File "${goInstPs}" -Arch sparc
		fAssertOut  "go ps installer names the dropped -Release dev" 'no .-Release dev. any more' \
			bash -c "pwsh -NoProfile -File '${goInstPs}' -Release dev 2>&1"
		fAssertOut  "go ps installer refuses a path-shaped -Tag" 'not a path' \
			pwsh -NoProfile -File "${goInstPs}" -Yes -Tag '../../evil/repo/main'
		## -Ref named this parameter for two releases, so it stays bound as an alias.
		fAssertOut  "-Ref still binds as -Tag"                  'not a path' \
			pwsh -NoProfile -File "${goInstPs}" -Yes -Ref '../../evil/repo/main'
		## Byte 0 must be the shebang: a BOM ahead of it means the kernel won't run the file
		## directly either, and irm carries it into iex where it stops the first line being a comment.
		fAssert "install.ps1 starts with a shebang, no BOM" \
			bash -c "[[ \"\$(head -c2 '${goInstPs}')\" == '#!' ]]"
		## GitHub serves SHA256SUMS as octet-stream and Invoke-WebRequest hands back bytes for
		## that, so reading the body as text finds no checksum. Reaching the real asset needs the
		## network, so this pins the decode in the source rather than exercising it.
		fAssert "go install.ps1 decodes the SHA256SUMS body from bytes" \
			bash -c "grep -q 'byte\[\]' '${goInstPs}'"
		## Assigning to a parameter re-runs its own ValidateSet/ValidatePattern, so detected
		## values that the set doesn't list - x86, a scraped tag - died in the binder instead of
		## reaching the message written for them. Reproducing that needs the hardware or the
		## network, so it is pinned in the source.
		fAssert "go install.ps1 keeps detection out of its validated parameters" \
			bash -c "! grep -qE '^[[:space:]]*\\\$(Arch|Tag)[[:space:]]*=' '${goInstPs}'"
		## [Environment]::GetEnvironmentVariable hands back an EXPANDED PATH; writing that back
		## bakes %USERPROFILE%-style entries in as literals for good.
		fAssert "go install.ps1 reads PATH raw before rewriting it" \
			bash -c "grep -q 'DoNotExpandEnvironmentNames' '${goInstPs}'"
		## The README documents --help for both installers, and this one had no such parameter -
		## PowerShell's binder could only report it as one nobody had heard of.
		fAssertOut "go ps installer answers --help"  'Usage: install\.ps1' \
			bash -c "pwsh -NoProfile -File '${goInstPs}' --help 2>&1"
		fAssertOut "and -Help too"                   'Usage: install\.ps1' \
			bash -c "pwsh -NoProfile -File '${goInstPs}' -Help 2>&1"
		## A native command's nonzero exit does not trip $ErrorActionPreference, and nothing read
		## $LASTEXITCODE - so a binary that would not run at all was reported as installed.
		## Reaching it needs a real install, so it is pinned in the source.
		fAssert "go install.ps1 reads the verification's exit code" \
			bash -c "grep -q 'LASTEXITCODE' '${goInstPs}'"
		## Move-Item from the system temp is only atomic within one filesystem, and the temp dir
		## and the install dir usually are not the same one.
		fAssert "go install.ps1 stages in the destination directory" \
			bash -c "grep -qF '.gitsby.install.' '${goInstPs}' && grep -q 'ChildPath (.\.gitsby' '${goInstPs}'"
		## 5.1 is what a fresh Windows install has, and the documented one-liner has to work on it.
		fAssert "go install.ps1 does not turn Windows PowerShell 5.1 away" \
			bash -c "! grep -q 'needs PowerShell 7' '${goInstPs}'"
		fAssert "and switches TLS 1.2 on for it"  bash -c "grep -q 'Tls12' '${goInstPs}'"
		fAssert "and asks for basic parsing"      bash -c "grep -q 'UseBasicParsing' '${goInstPs}'"
		## The documented one-liners are 'iex' and a scriptblock, neither of which is a script
		## file - so -File coverage alone says nothing about them. Both must bind their
		## parameters, refuse by throwing rather than exiting, and leave the calling session
		## alive and unaltered. -Release dev is the refusal that lands before any network does.
		if ((canNoTty)); then
			local goInstPsNative=""; goInstPsNative="$( fWinPath "${goInstPs}" )"
			## Decode the bytes ourselves rather than Get-Content, which quietly drops a BOM.
			local goReadInst="\$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes('${goInstPsNative}'))"
			fAssertOut "go iex form binds and refuses"     'CAUGHT:'           fPwshText "${goReadInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "and leaves the session alive"      'HOST ALIVE'        fPwshText "${goReadInst}; try { \$t | Invoke-Expression } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "go scriptblock form binds options" 'no .-Release dev. any more' fPwshText "${goReadInst}; try { & ([scriptblock]::Create(\$t)) -Release dev -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "and leaves the session alive too"  'HOST ALIVE'        fPwshText "${goReadInst}; try { & ([scriptblock]::Create(\$t)) -Release dev -Target system } catch { \"CAUGHT: \$(\$_.Exception.Message)\" }; 'HOST ALIVE'"
			fAssertOut "go installer leaks no StrictMode"  'strict stayed off' fPwshText "${goReadInst}; try { \$t | Invoke-Expression } catch { }; try { \$q = \$neverSet; 'strict stayed off' } catch { 'STRICT LEAKED' }"
			fAssertOut "go installer leaks no ErrorAction" 'EAP=Continue'      fPwshText "${goReadInst}; try { \$t | Invoke-Expression } catch { }; \"EAP=\$ErrorActionPreference\""
		fi
	fi

	## PowerShell only. Set-Location moves PowerShell's own location, not the process cwd, so a
	## script that starts git itself must pass the working directory or reads and writes land in
	## different repos. Every other check cds in bash before starting pwsh, which hides it.

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

	## Folder accounts. Which GitHub account a command acts as is decided by where the repo lives,
	## so the whole block turns on one config file and two directory trees. HOME is faked, and a
	## stub gh holds a token for exactly one of the two accounts - no network, no real credentials.
	## Note on what the checks below can and cannot prove: every "must NOT say X" check passes
	## trivially against a build predating accounts, since that build says nothing at all. Same for
	## a bare exit-code refusal - that build refuses the whole command as unknown. Those are kept as
	## regression guards and each is paired with a check on the message, which is what discriminates.
	local ac="${work}/$1-acct"
	mkdir -p "${ac}/home/.config/gitsby" "${ac}/bin" "${ac}/trees/work" "${ac}/trees/home"
	fStub "${ac}/bin/gh" <<-'EOF'
		#!/usr/bin/env bash
		case "$1 $2" in
			"auth token") [[ "${3:-}" == "--user" && "${4:-}" == "workacct" ]] && { echo "gho_faketoken"; exit 0; }; exit 1 ;;
			"api user")   echo "${FAKE_GH_ACTIVE:-otheracct}"; exit 0 ;;
		esac
		exit 1
	EOF
	## The rules go in written the way a user on this platform would write them. That matters on
	## Windows: '/tmp' is an entry in THIS shell's mount table, so the Bash build resolves it and
	## the PowerShell build - which has no such table - cannot, and never could. A rule spelled
	## that way would match on one leg only, and the block would look like a port bug instead of
	## a fixture that named a path half of it can't see. The drive forms a user would actually
	## type ('C:/x', '/c/x') already resolve the same in both.
	local acCanon="${ac}"
	((isWindows)) && acCanon="$( cd "${ac}" && pwd -W )"
	cat > "${ac}/home/.config/gitsby/config.shcl" <<-EOF
		# folder accounts
		account.work.path      = ${acCanon}/trees/work
		account.work.ghAccount = workacct
		account.work.name      = Work Person
		account.work.email     = work@example.com
		account.home.path      = ${acCanon}/trees/home
		account.home.ghAccount = homeacct
		account.work.notAKey   = ignored
	EOF
	local acWork="${ac}/trees/work/proj"; local acHome="${ac}/trees/home/proj"
	local acAway="${ac}/trees/away/proj"
	local acRepo=""
	for acRepo in "${acWork}" "${acHome}" "${acAway}"; do
		git init --quiet -b main "${acRepo}"
		( cd "${acRepo}" && echo a > a.txt && git add --all && git commit --quiet -m init )
	done
	## Every check runs with the fake HOME and the stub gh in front. GIT_CONFIG_GLOBAL is pointed at
	## a real file rather than /dev/null, because 'account apply' writes to exactly that.
	## PATH is expanded HERE, not left for the inner shell: single quotes are what stop a path with
	## a space in it from splitting when 'bash -c' re-parses the line, and they would equally stop
	## a '${PATH}' left in place from ever expanding - which silently empties PATH and fails every
	## check in this block for want of git.
	## acNoDiscovery empties every config-file input the file scope pinned: this block is where
	## discovery through HOME is the thing under test.
	local acEnv="${acNoDiscovery} HOME='${ac}/home' GIT_CONFIG_GLOBAL='${ac}/home/.gitconfig' PATH='${ac}/bin:${PATH}'"
	## The two identity checks below need one more thing: this file exports GIT_AUTHOR_NAME/EMAIL
	## for hermeticity, and 'git var GIT_AUTHOR_IDENT' - what the Author line reads - takes those
	## over any config, whether it came from the account or from the repo. Left in place they pin
	## the answer to test <test@test> and neither check can ever see what it is asking about.
	local acEnvIdent="-u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL ${acEnv}"
	: > "${ac}/home/.gitconfig"
	fAssertOut "the account comes from the folder"        "Account \.+: workacct"       bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## "account 'work'" was a bare repeat of the name on the line above it, so the one question a
	## first-time reader asks - what IS that string, and where did gitsby get it - had no answer
	## anywhere on screen. Say what kind of thing it is, and which of the several possible sources
	## produced it.
	fAssertOut "and says what that name is"               "From: An account block named 'work'"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## Flattened first: the sentence wraps at a fixed column, so the clause under test straddles two
	## physical lines and no plain grep can see it whole.
	fAssertOut "and which rule chose it"                  'because its folder rule covers this directory' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	## "(from config 'work')" named neither the file nor which config - and there are two in play,
	## since 'gitsby.ghAccount' is a git config key and the account blocks are not. An account that
	## applied cleanly says where to go and look, same as one that didn't.
	## Folded back to '~' as well: it lives under home, and its absolute spelling is long enough to
	## be the whole line.
	fAssertOut "and names the file that rule is written in"  'File: ~/\.config/gitsby/config\.shcl' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertOut "a sibling tree resolves to the other one" "Account \.+: homeacct"       bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertNotOut "and not to the first"                  "workacct"                    bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertNotOut "a folder no rule covers gets no account line"  "Account \.+:"        bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertOut "the commit identity comes from the account too"  'Work Person <work@example\.com>'  bash -c "cd '${acWork}' && env ${acEnvIdent} '${gitsby}' -q -NoFetch status"
	fAssertOut "a key nothing reads is reported, not ignored"    'account\.work\.notakey'           bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## Holding the token is what lets git authenticate over https with no ssh key at all. Only the
	## work account has one in the stub, so only it says so.
	fAssertOut    "the held token is what enables https auth"  'git over https'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	fAssertNotOut "and an account with no token claims nothing" 'git over https' bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## A value typed for one repo specifically outranks a rule about a whole tree. A regression
	## guard, not a discriminating check: code with no accounts at all reads the same repo-local
	## value and passes it too. What it is here to catch is a future account that overrides one.
	( cd "${acWork}" && git config user.email repo@example.com && git config user.name 'Repo Local' )
	fAssertOut "a repo-local identity still wins"  'Repo Local <repo@example\.com>'  bash -c "cd '${acWork}' && env ${acEnvIdent} '${gitsby}' -q -NoFetch status"
	( cd "${acWork}" && git config --unset user.email && git config --unset user.name )
	## Half of one is still a value typed for this repo. These entries reach git the way '-c' does,
	## which outranks the local config, so asking about user.email alone let the account's name
	## replace one the repo had pinned - the exact override the check above exists to forbid.
	( cd "${acWork}" && git config user.name 'Repo Local' )
	fAssertOut "a repo-local name survives an account that names both"  'Repo Local <work@example\.com>' \
		bash -c "cd '${acWork}' && env ${acEnvIdent} '${gitsby}' -q -NoFetch status"
	( cd "${acWork}" && git config --unset user.name && git config user.email repo@example.com )
	fAssertOut "and a repo-local email does the same"  'Work Person <repo@example\.com>' \
		bash -c "cd '${acWork}' && env ${acEnvIdent} '${gitsby}' -q -NoFetch status"
	( cd "${acWork}" && git config --unset user.email )
	## Where the file lives is per-platform now, so which candidate wins is worth pinning. Two more
	## config files, both claiming the same work tree under different account names, so whichever
	## one was read says so on the Account line. The Linux order is all a Linux run can check; the
	## Windows and macOS orders are pinned by TestConfigCandidatesFor in the Go tests.
	mkdir -p "${ac}/xdg/gitsby" "${ac}/appdata/gitsby"
	cat > "${ac}/xdg/gitsby/config.shcl" <<-EOF
		account.xdgacct.path      = ${acCanon}/trees/work
		account.xdgacct.ghAccount = xdgacct
	EOF
	cat > "${ac}/appdata/gitsby/config.shcl" <<-EOF
		account.appdata.path      = ${acCanon}/trees/work
		account.appdata.ghAccount = appdataacct
	EOF
	fAssertOut "XDG_CONFIG_HOME is the config location here, ahead of ~/.config"  'Account \.+: xdgacct' \
		bash -c "cd '${acWork}' && env ${acEnv} XDG_CONFIG_HOME='${ac}/xdg' '${gitsby}' -q -NoFetch status"
	fAssertOut "and with none set, ~/.config is still found"  'Account \.+: workacct' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## APPDATA is Windows' own answer to this question and means nothing anywhere else, just as
	## XDG_CONFIG_HOME means nothing on Windows. Each used to be tried on every platform, which put
	## a variable a Wine or Samba setup can leave lying around on the list of places a Linux run
	## reads credentials from, and let an MSYS shell answer for a Windows one. Asked with a home
	## that holds no config, so the answer is APPDATA's file or nothing - with the usual one still
	## in place both platforms would read that instead and the check could not tell them apart.
	mkdir -p "${ac}/nohome"
	: > "${ac}/nohome/.gitconfig"
	local acAppdataEnv="${acNoDiscovery} HOME='${ac}/nohome' GIT_CONFIG_GLOBAL='${ac}/nohome/.gitconfig'"
	acAppdataEnv+=" PATH='${ac}/bin:${PATH}' APPDATA='${ac}/appdata'"
	if ((isWindows)); then
		fAssertOut "on Windows, %APPDATA% is where the file lives"  'Account \.+: appdataacct' \
			bash -c "cd '${acWork}' && env ${acAppdataEnv} '${gitsby}' -q -NoFetch status"
	else
		fAssertNotOut "off Windows, APPDATA is not a config location at all"  'appdataacct' \
			bash -c "cd '${acWork}' && env ${acAppdataEnv} '${gitsby}' -q -NoFetch status"
	fi
	## A rule written through a symlink - a synced folder, a stable name pointing at a dated one,
	## a home that is itself a link. git answers with the tree's real path, so a rule spelled the
	## way it was typed was compared against the resolved one and matched nothing. Nor did anything
	## say so: the folder exists, so 'account list' printed it without its "can never match" note.
	if ln -s "${ac}/trees/work" "${ac}/linked" 2>/dev/null; then
		local acLinkCanon="${ac}/linked"
		((isWindows)) && acLinkCanon="$( cd "${ac}/linked" && pwd -W )"
		cat > "${ac}/home/.config/gitsby/linked.shcl" <<-EOF
			account.linked.path      = ${acLinkCanon}/proj
			account.linked.ghAccount = linkedacct
		EOF
		fAssertOut "a folder rule spelled through a symlink still claims the folder"  'Account \.+: linkedacct' \
			bash -c "cd '${acWork}' && env ${acEnv} GITSBY_CONFIG='${ac}/home/.config/gitsby/linked.shcl' '${gitsby}' -q -NoFetch status"
		fAssertOut "and 'account list' marks it as the one in force"  '^-> linked' \
			bash -c "cd '${acWork}' && env ${acEnv} GITSBY_CONFIG='${ac}/home/.config/gitsby/linked.shcl' '${gitsby}' account list"
	fi
	## Overrides, both directions.
	fAssertOut "GITSBY_ACCOUNT overrides the folder"  '^Account .*homeacct'  bash -c "cd '${acWork}' && env ${acEnv} GITSBY_ACCOUNT=home '${gitsby}' -q -NoFetch status"
	## A bare login is a documented spelling of GITSBY_ACCOUNT, and 'raw' already reports one on
	## stderr. The identity line asked instead whether some CONFIGURED value had been used, so a
	## bare login named no account, set no key, and printed nothing at all - silence from the one
	## command whose job is to say who a push will go out as.
	fAssertOut "a bare login still gets an identity line"  '^Account .*barelogin' \
		bash -c "cd '${acAway}' && env ${acEnv} GITSBY_ACCOUNT=barelogin '${gitsby}' -q -NoFetch status"
	## An account the file defines but that names no GitHub login of its own - a commit identity
	## and an ssh key and nothing else, which is a whole way of holding a second one. A folder rule
	## has always applied such an account; naming the same one through GITSBY_ACCOUNT read it as a
	## bare login instead, so none of it applied and the ACCOUNT's own name was reported as the
	## GitHub login the run acts as - asking for it by name got you less than not asking.
	cat > "${ac}/keysonly.shcl" <<-EOF
		account.keysonly.name  = Keys Only
		account.keysonly.email = keys@example.com
	EOF
	fAssertOut "an account with no GitHub login still applies when named"  'Keys Only <keys@example\.com>' \
		bash -c "cd '${acAway}' && env ${acEnvIdent} GITSBY_ACCOUNT=keysonly '${gitsby}' -q -NoFetch --config '${ac}/keysonly.shcl' status"
	fAssertNotOut "and its own name is not reported as a GitHub login"  'Account \.+: keysonly' \
		bash -c "cd '${acAway}' && env ${acEnv} GITSBY_ACCOUNT=keysonly '${gitsby}' -q -NoFetch --config '${ac}/keysonly.shcl' status"
	## A byte-order mark is what a Windows editor writes by default. It lands on the first key in
	## the file, which then reads as one nothing understands - and the line reporting those printed
	## the mark along with it, so the only diagnostic named a key that looks exactly right.
	printf '\xef\xbb\xbf' > "${ac}/bom.shcl"
	cat >> "${ac}/bom.shcl" <<-EOF
		account.bom.path      = ${acCanon}/trees/work
		account.bom.ghAccount = bomacct
	EOF
	fAssertOut    "a byte-order mark doesn't eat the config's first key"  'bomacct' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/bom.shcl' status"
	fAssertNotOut "nor get that key reported as one it couldn't read"  'account\.bom\.path' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/bom.shcl' status"
	## ...but only for an account ASKED for. The owner of the remote is a guess about a repo, and a
	## single-account machine must never learn the feature exists.
	( cd "${acAway}" && git remote add origin https://github.com/someone/repo.git )
	fAssertNotOut "the remote's owner alone prints no identity line"  'Account \.'  \
		bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	( cd "${acAway}" && git remote remove origin )
	## Which folder decides, for the one command whose folder is not the one you are standing in. A
	## clone lands somewhere else, and it is the rules for THERE that pick the account; reading the
	## current directory's answered for whatever repo you happened to be sitting inside.
	git init --quiet --bare -b main "${ac}/src.git"
	( cd "${acWork}" && git push --quiet "${ac}/src.git" HEAD:refs/heads/main )
	fAssertOut    "a clone takes the account of the folder it lands in"  "Account \.+: workacct" \
		bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/work/c1'"
	fAssertNotOut "and not the one it was launched from"  'homeacct' \
		bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/work/c2'"
	fAssertOut    "the other direction the same way"  "Account \.+: homeacct" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/home/c3'"
	## Climbing out of one tree into another is the case a rule sees wrong if the '..' survives.
	fAssertOut    "a relative destination is resolved before the rules see it"  "Account \.+: homeacct" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' ../../home/c4"
	## 'gitsby.ghAccount' answers for the repo it is set in. A clone's destination has no config of
	## its own yet, and an includeIf keyed on gitdir cannot be asked about a repo that does not exist
	## - so the value belonging to whatever repo we are standing in must not follow the clone out of it.
	( cd "${acAway}" && git config gitsby.ghAccount awayacct )
	fAssertNotOut "a repo-local account does not follow a clone out of its folder"  'Account \.' \
		bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/away/c5'"
	fAssertOut    "and the destination's rule answers in its place"  "Account \.+: workacct" \
		bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q repo clone '${ac}/src.git' '${ac}/trees/work/c6'"
	( cd "${acAway}" && git config --unset gitsby.ghAccount )
	cat > "${ac}/alt.shcl" <<-EOF
		account.alt.path      = ${acCanon}/trees/work
		account.alt.ghAccount = altacct
	EOF
	fAssertOut "--config reads somewhere else"  'altacct'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/alt.shcl' status"
	## The name is matched the way the file was stored - the loader lowercases the whole key, so
	## the lookup has to as well. Bash lowercased only half of it, so an account typed in another
	## case simply missed, silently, and the run went out as gh's own identity.
	fAssertOut "an account name matches whatever case you type"  'altacct' \
		bash -c "cd '${acWork}' && env ${acEnv} GITSBY_ACCOUNT=ALT '${gitsby}' -q -NoFetch --config '${ac}/alt.shcl' status"
	## A folder rule has to resolve to the same tree whichever build reads it, and whichever way the
	## path was spelled. On Windows the PowerShell build resolved the drive letter only AFTER asking
	## the filesystem - and .NET reads this shell's '/c/...' against the current drive, so nothing
	## resolved, short names and junctions were left as written, and the same rule matched in one
	## build and not the other. Silently: a rule that does not match reads exactly like no rule.
	## Only spellings BOTH builds can express. The harness works under a temp directory, which this
	## shell reaches through its own mount table as '/tmp/...' - a spelling with no meaning to the
	## native build, and none it could be given without depending on Git Bash existing. That is a
	## documented limit, not a defect, and 'account' marks such a rule rather than letting it look
	## like no rule at all. cicd/parity.bash covers the drive-letter spellings across both builds.
	## 'pathContains' names a run of folder names rather than a tree on this machine, so one config
	## file can be synced between machines whose roots differ. Two fake "machines" here, same
	## trailing structure under different roots, and one decoy: whole folder names only, so
	## 'jim-collier' must never match a directory called 'jim-collier-old'.
	local acRoot=""
	for acRoot in mA mB; do
		mkdir -p "${ac}/${acRoot}/github.com/alice/proj"
		git init --quiet -b main "${ac}/${acRoot}/github.com/alice/proj"
	done
	mkdir -p "${ac}/mA/github.com/alice-old/proj"
	git init --quiet -b main "${ac}/mA/github.com/alice-old/proj"
	cat > "${ac}/seg.shcl" <<-EOF
		account.seg.pathContains = github.com/alice
		account.seg.ghAccount    = segacct
	EOF
	for acRoot in mA mB; do
		fAssertOut "pathContains matches under root ${acRoot}"  'segacct' \
			bash -c "cd '${ac}/${acRoot}/github.com/alice/proj' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/seg.shcl' status"
	done
	fAssertNotOut "and matches whole folder names only"  'segacct' \
		bash -c "cd '${ac}/mA/github.com/alice-old/proj' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/seg.shcl' status"
	## Precedence: naming this machine's own tree is the more specific claim, so an absolute 'path'
	## beats a 'pathContains'; among pathContains rules, more folder names beats fewer.
	cat > "${ac}/segprec.shcl" <<-EOF
		account.broad.pathContains  = alice
		account.broad.ghAccount     = broadacct
		account.narrow.pathContains = github.com/alice
		account.narrow.ghAccount    = narrowacct
	EOF
	fAssertOut "more folder names is the more specific rule"  'narrowacct' \
		bash -c "cd '${ac}/mA/github.com/alice/proj' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/segprec.shcl' status"
	cat >> "${ac}/segprec.shcl" <<-EOF
		account.exact.path      = ${acCanon}/mA/github.com/alice
		account.exact.ghAccount = exactacct
	EOF
	fAssertOut "an absolute path beats a pathContains"  'exactacct' \
		bash -c "cd '${ac}/mA/github.com/alice/proj' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/segprec.shcl' status"
	## 'account apply' hands the same rule to git, which globs gitdir natively - so plain git agrees
	## under either root, which is the whole point of a config file you can sync.
	mkdir -p "${ac}/seghome"
	local acSegEnv="${acNoDiscovery} HOME='${ac}/seghome' GIT_CONFIG_GLOBAL='${ac}/seghome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	cat > "${ac}/segapply.shcl" <<-EOF
		account.seg.pathContains = github.com/alice
		account.seg.ghAccount    = segacct
		account.seg.email        = alice@example.com
	EOF
	fAssert "account apply writes a gitdir glob for pathContains" \
		bash -c "cd '${ac}/mA/github.com/alice/proj' && env ${acSegEnv} '${gitsby}' -q -NoFetch --config '${ac}/segapply.shcl' account apply >/dev/null"
	for acRoot in mA mB; do
		fAssertOut "and plain git agrees under root ${acRoot}"  'alice@example\.com' \
			bash -c "cd '${ac}/${acRoot}/github.com/alice/proj' && env ${acSegEnv} git config user.email"
	done
	cat > "${ac}/spell.shcl" <<-EOF
		account.s.path      = ${acCanon}/trees/work/proj
		account.s.ghAccount = spellacct
	EOF
	fAssertOut "a folder rule resolves in the canonical spelling"  'spellacct' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/spell.shcl' status"
	## The identity block used to name the account it RESOLVED, whether or not anything could act as
	## it. With no token found, gh goes on using its own account - so the one command whose job is
	## answering "who does this go out as" gave the wrong name. The stub gh holds no token for this
	## one, so it is the not-applied case.
	cat > "${ac}/notoken.shcl" <<-EOF
		account.nt.path      = ${acCanon}/trees/work
		account.nt.ghAccount = notokenacct
	EOF
	fAssertOut "an account with no token says it was not applied"  'no access token used' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/notoken.shcl' status"
	## These fixtures push to a local bare repo, so there is no host to name - and forgeName() stands
	## in the word "origin" for one, which on this line reads as a host actually called origin.
	fAssertNotOut "and does not invent a host to blame"  'used for origin' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/notoken.shcl' status"
	fAssertNotOut "and an account that WAS applied says no such thing"  'Why:' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## A directory is readable, so it got past the check, loaded nothing, and exited 0 - after the
	## shell had printed its own complaint about reading a directory. Silently no accounts is the
	## answer that acts as the wrong identity.
	fAssertFail "--config naming a directory is refused"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}' status"
	fAssertOut  "and says it isn't a file"  "isn't a file"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}' status 2>&1"
	## 'account apply' writes one fragment per account into a directory beside the config file.
	## Blocked, that surfaced as a raw shell or .NET error - a different one in each build - part
	## way through the run, which reads as a crash rather than as something to act on.
	mkdir -p "${ac}/blocked"
	cat > "${ac}/blocked/config.shcl" <<-EOF
		account.b.path      = ${acCanon}/trees/work
		account.b.ghAccount = bacct
	EOF
	: > "${ac}/blocked/accounts"
	## git applies includes in file order and the LAST match wins; gitsby takes the LONGEST matching
	## folder. Written in declaration order, a tree nested inside another account's tree got
	## whichever account was declared later - so plain git and gitsby disagreed about one directory,
	## which is the whole thing 'apply' exists to prevent. 'outer' is declared second on purpose.
	## A real repo, not just a directory: 'includeIf.gitdir' matches on where the .git is, so in a
	## plain folder no include fires at all and 'git config user.email' answers nothing - which
	## would fail this check for a reason that has nothing to do with rule ordering.
	mkdir -p "${ac}/nesthome"
	git init --quiet -b main "${ac}/trees/work/nested"
	cat > "${ac}/nested.shcl" <<-EOF
		account.inner.path      = ${acCanon}/trees/work/nested
		account.inner.ghAccount = inneracct
		account.inner.email     = inner@example.com

		account.outer.path      = ${acCanon}/trees/work
		account.outer.ghAccount = outeracct
		account.outer.email     = outer@example.com
	EOF
	local acNestEnv="${acNoDiscovery} HOME='${ac}/nesthome' GIT_CONFIG_GLOBAL='${ac}/nesthome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssert "apply writes a nested rule after the tree that contains it" \
		bash -c "cd '${ac}/trees/work/nested' && env ${acNestEnv} '${gitsby}' -q -NoFetch --config '${ac}/nested.shcl' account apply >/dev/null"
	fAssertOut "and plain git then agrees with gitsby about the nested folder"  'inner@example\.com' \
		bash -c "cd '${ac}/trees/work/nested' && env ${acNestEnv} git config user.email"
	fAssertFail "account apply refuses a blocked include directory"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/blocked/config.shcl' account apply"
	fAssertOut  "and names it rather than dumping an OS error"  "isn't a directory" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/blocked/config.shcl' account apply 2>&1"
	## A trailing '# ...' is a comment, not part of the value - the documented example config writes
	## them. Folded in, a path became a rule that could never match any directory, and a rule that
	## never matches reads exactly like no rule at all: the command went out as gh's own account.
	## Ahead of 'account apply' on purpose - that writes gitsby.ghAccount into the repo, which
	## outranks any folder rule, so after it this check can no longer see what it is asking about.
	cat > "${ac}/trailing.shcl" <<-EOF
		account.cmt.path      = ${acCanon}/trees/work   # the tree this one owns
		account.cmt.ghAccount = cmtacct                 # who to act as
	EOF
	fAssertOut "a trailing comment is not part of the value"  "Account \.+: cmtacct" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/trailing.shcl' status"
	## A '#' that was quoted is a literal, and trailing space inside the quotes is kept.
	cat > "${ac}/quoted.shcl" <<-EOF
		account.q.path      = ${acCanon}/trees/work
		account.q.ghAccount = "a#b"                     # quoted, so the hash is part of it
	EOF
	fAssertOut "a quoted hash stays in the value"  "Account \.+: a#b" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/quoted.shcl' status"
	## The current layout: one block per account. Read in every shape a hand-written file takes - a
	## block, the dotted spelling of the old lines, a folder list, a key in camel case - and what it
	## can't read is named by the path that reaches it, so the reader can find the line.
	## Spaces for the nesting: '<<-' strips every leading tab, structure included.
	cat > "${ac}/hier.shcl" <<-EOF
		# blocks
		protocol: https
		account: hw
		    path: ${acCanon}/trees/work, ${acCanon}/trees/away
		    ghAccount: hieracct
		    nonsense: 1
		account.hh.path: ${acCanon}/trees/home
		account.hh.ghaccount: dottedacct
	EOF
	fAssertOut "a block-layout config resolves the folder's account"  "Account \.+: hieracct" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier.shcl' status"
	fAssertOut "and the second folder in the same list"  "Account \.+: hieracct" \
		bash -c "cd '${acAway}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier.shcl' status"
	fAssertOut "and the dotted spelling of the old lines"  "Account \.+: dottedacct" \
		bash -c "cd '${acHome}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier.shcl' status"
	fAssertOut "a key nothing reads is named by the path that reaches it"  'Ignored keys \.+:.*account\[hw\]\.nonsense' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier.shcl' account"
	## 'account set' on a block-layout file edits the block and keeps the rest - comments included -
	## where it was, in the format's own spacing.
	cp "${ac}/hier.shcl" "${ac}/hier-set.shcl"
	fAssertOut "'account set' names the block and the key it adds"  'add: +account\[hw\]\.host: gitea\.example' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier-set.shcl' account set hw host gitea.example 2>&1"
	fAssertOut "and the block now holds it"  '^	host: gitea\.example$'  cat "${ac}/hier-set.shcl"
	fAssertOut "with the comment above it kept"  '^# blocks$'  cat "${ac}/hier-set.shcl"
	fAssertOut "and an existing key is shown before and after"  'was: +ghaccount: hieracct' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/hier-set.shcl' account set hw ghaccount other 2>&1"
	## A file created from nothing carries a header naming the keys and a footer naming the format,
	## and is readable by nobody else: it names accounts and points at token files.
	local acNew="${ac}/newhome"; mkdir -p "${acNew}"
	fAssertOut "'account set' creates the file where the next run looks"  'create ~/.config/gitsby/config.shcl' \
		bash -c "cd '${acWork}' && env ${acNoDiscovery} HOME='${acNew}' PATH='${ac}/bin:${PATH}' '${gitsby}' -q -NoFetch account set fresh ghaccount freshacct 2>&1"
	fAssertOut "and it names the format it is in"  'This config file format is SHCL'  cat "${acNew}/.config/gitsby/config.shcl"
	fAssertOut "and the keys it takes"  '^#   pathcontains '  cat "${acNew}/.config/gitsby/config.shcl"
	fAssertOut "and the next run reads it"  'github \.+: freshacct' \
		bash -c "cd '${acWork}' && env ${acNoDiscovery} HOME='${acNew}' PATH='${ac}/bin:${PATH}' '${gitsby}' -q -NoFetch account 2>&1"
	if ! ((isWindows)); then
		fAssert "and nobody else can read it"  bash -c "[[ \"\$(stat -c '%a' '${acNew}/.config/gitsby/config.shcl')\" == 600 ]]"
	fi
	## A named file that isn't there is a typo, not a reason to fall back silently.
	fAssertFail "a named config that isn't there is refused"        bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/nope.shcl' status"
	fAssertOut  "and says which file"  'No readable config file'    bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/nope.shcl' status 2>&1"
	## An empty value is a mistake too - a script expanding a variable that turned out empty. Falling
	## back to the default file would pick an account nobody asked for, so it is refused by name.
	fAssertFail "--config with an empty value is refused"     bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '' status"
	fAssertOut  "and says the name was empty"  'empty file name' bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '' status 2>&1"
	## The joined spelling splits the two builds, so each is pinned to what it actually does.
	fAssertOut "--config=FILE (joined) works here"  'altacct'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config='${ac}/alt.shcl' status"

	## account list / apply.
	fAssertOut "account list names the accounts"      'workacct'                 bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	fAssertOut "and marks the one this folder uses"   '^-> work$'                bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	fAssertOut "and says where a token would come from, not what it is"  "token \.+: gh's own store"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	fAssertNotOut "never printing the token itself"   'gho_faketoken'            bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	fAssert "account list works outside any repo"     bash -c "cd '${ac}' && env ${acEnv} '${gitsby}' -q account >/dev/null"
	## The header used to say "Here" for the directory status calls "Directory", and "Resolves to"
	## for the answer status labels "Account" - two words each for one thing, on the one screen
	## whose whole job is to line the rules up against where you are standing.
	fAssertOut "account list names the current directory"  '^Current dir \.+: '  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	fAssertOut "and labels the answer the way status does"  '^Account \.+: workacct'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account"
	## An unconfigured folder said "(nothing configured - gh's own account)", which named gh on
	## hosts gh does not serve and answered a question about git's fallback that nobody asked.
	: > "${ac}/none.shcl"
	fAssertOut "an unconfigured folder says only that"  '^Account \.+: \(nothing configured\)$' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/none.shcl' account"
	fAssertNotOut "naming no tool it cannot speak for"  "gh's own account" \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch --config '${ac}/none.shcl' account"
	## An entry written by hand has to survive; ours have to refresh rather than accumulate.
	( cd "${acWork}" && env HOME="${ac}/home" GIT_CONFIG_GLOBAL="${ac}/home/.gitconfig" git config --global includeIf.gitdir:/hand/written/.path /keep/me.gitconfig )
	fAssert "account apply runs"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account apply >/dev/null"
	fAssert "and plain git now uses the account's identity"  bash -c "cd '${acWork}' && env ${acEnv} git config user.email | grep -qx work@example.com"
	fAssert "and the sibling tree gets the other one"        bash -c "cd '${acHome}' && env ${acEnv} git config gitsby.ghAccount | grep -qx homeacct"
	fAssert "re-applying does not duplicate the rules"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q account apply >/dev/null && [[ \"\$(grep -c 'gitsby/accounts' '${ac}/home/.gitconfig')\" == 2 ]]"
	fAssert "and leaves a hand-written includeIf alone"  bash -c "grep -q 'hand/written' '${ac}/home/.gitconfig'"
	## Removing an account from the config has to remove its rule, or it silently keeps applying.
	fAssert "dropping an account drops its rule"  bash -c "cd '${acWork}' && sed -i '/^account\.home\./d' '${ac}/home/.config/gitsby/config.shcl' && env ${acEnv} '${gitsby}' -q account apply >/dev/null && [[ \"\$(grep -c 'gitsby/accounts' '${ac}/home/.gitconfig')\" == 1 ]]"

	## The helper git is handed has to carry the token even when gh is ALREADY that account. The
	## export used to sit inside the "this replaces a different account" branch while the helper
	## install sat outside it, so git got an empty password - and the reset ahead of the helper had
	## already evicted whatever credential manager would otherwise have answered. Every https push
	## by a single-account user went out that way, which is the case needing no configuration.
	fAssertOut "the credential helper carries a token when gh is already that account"  'password=gho_faketoken' \
		bash -c "cd '${acWork}' && printf 'protocol=https\nhost=github.com\n\n' | env FAKE_GH_ACTIVE=workacct ${acEnv} '${gitsby}' -q raw git credential fill"

	## A folder path with a space in it. The managed-includes scan split each config line at the
	## first space, so such a key came back truncated and was never recognized as ours - every
	## re-run appended a duplicate, and a rule dropped from the config file kept applying forever.
	mkdir -p "${ac}/spacehome" "${ac}/my trees/work"
	: > "${ac}/spacehome/.gitconfig"
	local acSpaceCanon="${ac}/my trees/work"; ((isWindows)) && acSpaceCanon="$( cd "${ac}/my trees/work" && pwd -W )"
	cat > "${ac}/spaced.shcl" <<-EOF
		account.sp.path      = ${acSpaceCanon}
		account.sp.ghAccount = spacct
	EOF
	local acSpaceEnv="${acNoDiscovery} HOME='${ac}/spacehome' GIT_CONFIG_GLOBAL='${ac}/spacehome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssert "account apply writes a rule for a folder whose path has a space" \
		bash -c "cd '${ac}/my trees/work' && env ${acSpaceEnv} '${gitsby}' -q -NoFetch --config '${ac}/spaced.shcl' account apply >/dev/null && [[ \"\$(grep -c 'sp\.gitconfig' '${ac}/spacehome/.gitconfig')\" == 1 ]]"
	fAssert "and re-applying refreshes it instead of duplicating it" \
		bash -c "cd '${ac}/my trees/work' && env ${acSpaceEnv} '${gitsby}' -q -NoFetch --config '${ac}/spaced.shcl' account apply >/dev/null && [[ \"\$(grep -c 'sp\.gitconfig' '${ac}/spacehome/.gitconfig')\" == 1 ]]"
	fAssert "and dropping that account drops its rule" \
		bash -c "cd '${ac}/my trees/work' && sed -i '/^account\.sp\./d' '${ac}/spaced.shcl' && env ${acSpaceEnv} '${gitsby}' -q -NoFetch --config '${ac}/spaced.shcl' account apply >/dev/null && ! grep -q 'sp\.gitconfig' '${ac}/spacehome/.gitconfig'"

	## 'apply' is the one command that writes outside the repo you are standing in, and it reported
	## success whatever happened: the truncate error was discarded and every 'git config' exit code
	## ignored. A directory where the fragment file belongs is the cheapest way to fail one write.
	mkdir -p "${ac}/frag/accounts/b.gitconfig" "${ac}/fraghome"
	: > "${ac}/fraghome/.gitconfig"
	cat > "${ac}/frag/config.shcl" <<-EOF
		account.b.path      = ${acCanon}/trees/work
		account.b.ghAccount = bacct
	EOF
	local acFragEnv="${acNoDiscovery} HOME='${ac}/fraghome' GIT_CONFIG_GLOBAL='${ac}/fraghome/.gitconfig' PATH='${ac}/bin:${PATH}'"
	fAssertFail   "account apply fails when a fragment can't be written" \
		bash -c "cd '${acWork}' && env ${acFragEnv} '${gitsby}' -q -NoFetch --config '${ac}/frag/config.shcl' account apply"
	fAssertNotOut "and never says it wrote one"  'Wrote ' \
		bash -c "cd '${acWork}' && env ${acFragEnv} '${gitsby}' -q -NoFetch --config '${ac}/frag/config.shcl' account apply 2>&1"
	fAssert       "and wrote no includeIf rule either"  bash -c "! grep -q 'b\.gitconfig' '${ac}/fraghome/.gitconfig'"

	## The fragment names the account and points at the token file, so it is written 0600 - but
	## os.WriteFile only applies a mode when it CREATES the file, so one left readable by an
	## earlier run stayed that way through every re-apply.
	if ((! isWindows)); then
		fAssert "account apply tightens a fragment left readable by an earlier run" \
			bash -c "chmod 644 '${ac}/home/.config/gitsby/accounts/work.gitconfig' && cd '${acWork}' && env ${acEnv} '${gitsby}' -q account apply >/dev/null && [[ \"\$(stat -c '%a' '${ac}/home/.config/gitsby/accounts/work.gitconfig')\" == 600 ]]"
	fi

	## The sshKey value is concatenated into GIT_SSH_COMMAND and into core.sshCommand, and git hands
	## both to a shell - while the config file itself is redirectable by flag and by environment
	## variable. Dropped and reported, because quietly falling back to whatever key ssh picks is how
	## a push goes out as the wrong person.
	cat > "${ac}/badkey.shcl" <<-EOF
		account.bk.path      = ${acCanon}/trees/work
		account.bk.ghAccount = bkacct
		account.bk.sshKey    = /keys/k; touch ${ac}/pwned
	EOF
	fAssertOut    "an sshKey carrying shell characters is refused"  'Ignored keys \.+:.*sshkey' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/badkey.shcl' account"
	fAssertNotOut "and never becomes this folder's key"  '/keys/k' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/badkey.shcl' account"
	fAssert       "and nothing it named ever ran"  bash -c "[[ ! -e '${ac}/pwned' ]]"

	## An account name becomes a file name under the include directory, so it must not be able to
	## climb out of it. 'account apply' wrote the fragment wherever the name pointed - a name with
	## a couple of '../' in it reached the real '~/.gitconfig' and truncated it.
	cat > "${ac}/traversal.shcl" <<-EOF
		account.ok.path              = ${acCanon}/trees/work
		account.ok.ghAccount         = okacct
		account.../../evil.path      = ${acCanon}/trees/work
		account.../../evil.ghAccount = evilacct
	EOF
	fAssertOut "an account name that climbs out of the include dir is refused"  'Ignored keys \.+:.*evil' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/traversal.shcl' account"
	fAssertNotOut "and never becomes an account"  'evilacct' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q -NoFetch -Config '${ac}/traversal.shcl' account"

	## repo url. A local-path origin has no other spelling, so this needs a github.com one - which
	## is never contacted: every check reads or rewrites the URL and nothing else.
	local ru="${work}/$1-repourl"
	git init --quiet -b main "${ru}"
	( cd "${ru}" && echo a > a.txt && git add --all && git commit --quiet -m init && git remote add origin git@github.com:someone/thing.git )
	fAssertOut "repo url shows the current spelling"  'origin \.+: git@github\.com:someone/thing\.git'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url"
	fAssertOut "and both alternatives"  'as https \.+: https://github\.com/someone/thing\.git'          bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url"
	fAssertPlan "converting plans the set-url"  'git remote set-url origin https://github\.com/someone/thing\.git'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url https"
	fAssert "and does it"  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url https >/dev/null && git -C '${ru}' remote get-url origin | grep -qx 'https://github.com/someone/thing.git'"
	fAssertOut "re-running says there is nothing to do"  'already uses https'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url https"
	fAssert "and back again"  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url ssh >/dev/null && git -C '${ru}' remote get-url origin | grep -qx 'git@github.com:someone/thing.git'"
	## The bare exit code can't tell a refused transport from a build that never heard of 'repo url'
	## - both exit 1 - so the reason is what pins it.
	fAssertFail "a transport that isn't one is refused"  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url ftp"
	## Each build names itself in its own syntax lines, so the pattern has to allow both spellings.
	fAssertOut  "and names the two that are"  'Syntax: gitsby(\.ps1)? repo url'  bash -c "cd '${ru}' && '${gitsby}' -q -NoFetch repo url ftp 2>&1"
	## A remote with no second spelling must say so rather than invent one, and a repo with no
	## remote at all must say that instead of showing an empty one.
	git init --quiet --bare -b main "${ru}-local.git"
	( cd "${acAway}" && git remote add origin "${ru}-local.git" )
	fAssertOut  "a non-github origin has no other spelling"  'no other spelling'  bash -c "cd '${acAway}' && '${gitsby}' -q -NoFetch repo url"
	fAssertFail "and converting it is refused"                                    bash -c "cd '${acAway}' && '${gitsby}' -q -NoFetch repo url https"
	fAssertOut  "for that reason and not another"  'no other spelling'            bash -c "cd '${acAway}' && '${gitsby}' -q -NoFetch repo url https 2>&1"

	## The nudge to convert. It exists to be seen exactly once per situation that warrants it, so
	## what matters as much as showing it is the two cases where it must stay quiet. Needs a
	## github.com remote inside a matched folder - and a stub ssh, or the identity probe would go
	## to the real github.com. Nothing here contacts anything: every check reads or previews.
	fStub "${ac}/bin/ssh" <<-'EOF'
		#!/usr/bin/env bash
		[[ "$1" == "-G" ]] && { printf 'user git\nhostname github.com\n'; exit 0; }
		exit 255
	EOF
	local acSsh="${ac}/trees/work/sshproj"
	git init --quiet -b main "${acSsh}"
	( cd "${acSsh}" && echo a > a.txt && git add --all && git commit --quiet -m init \
		&& git remote add origin git@github.com:workacct/thing.git )
	fAssertOut "an ssh remote whose account holds a token is offered the conversion"  "repo url https' switches it"  bash -c "cd '${acSsh}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## Was written as a check, but it only ran git - it could not fail and said nothing about gitsby.
	( cd "${acSsh}" && git remote set-url origin https://github.com/workacct/thing.git )
	fAssertNotOut "converting it silences the offer"  "repo url https' switches it"  bash -c "cd '${acSsh}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	## Saying you want ssh is an answer, and answered advice must stop.
	( cd "${acSsh}" && git remote set-url origin git@github.com:workacct/thing.git )
	echo "account.work.protocol = ssh" >> "${ac}/home/.config/gitsby/config.shcl"
	fAssertNotOut "and 'protocol = ssh' silences it too"  "repo url https' switches it"  bash -c "cd '${acSsh}' && env ${acEnv} '${gitsby}' -q -NoFetch status"
	sed -i '/^account\.work\.protocol/d' "${ac}/home/.config/gitsby/config.shcl"

	## raw passthrough. The promise is that everything after the tool name reaches it untouched,
	## that stdout is the tool's alone, and that the exit code is the tool's too.
	fAssertOut "raw git returns git's own output"  '^main$'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' raw git rev-parse --abbrev-ref HEAD 2>/dev/null"
	fAssertNotOut "and nothing of ours on stdout"  'Account' bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' raw git rev-parse --abbrev-ref HEAD 2>/dev/null"
	fAssertOut "the identity note goes to stderr"  'acting as workacct'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' raw git rev-parse HEAD 2>&1 >/dev/null"
	fAssertNotOut "-q silences it"  'acting as'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git rev-parse HEAD 2>&1 >/dev/null"
	## The flag most likely to be stolen by our own parser, and the one git uses constantly.
	fAssertOut "an option after the tool belongs to the tool"  'acting as'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' raw git log -q --oneline -1 2>&1"
	## Nonzero alone proves nothing here - a build with no 'raw' at all also exits 1 - so what makes
	## these two mean anything is that the failure is git's own and the refusal is ours.
	fAssertFail "the tool's own failure is our exit code"  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git rev-parse --verify nosuchref"
	fAssertOut  "and the message is git's, not ours"  'Needed a single revision'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git rev-parse --verify nosuchref 2>&1"
	fAssert     "and its success is too"                   bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git rev-parse --verify HEAD >/dev/null"
	fAssertOut  "raw gh reaches gh"  'gho_faketoken'       bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw gh auth token --user workacct"
	fAssertFail "raw with no tool is refused"              bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw"
	fAssertOut  "and says what it wanted"  'Syntax: gitsby(\.ps1)? raw'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw 2>&1"
	fAssertFail "raw with a tool we don't front is refused" bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw rm -rf /"
	fAssertOut  "and names the two it does"  'One of: git, gh'  bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw curl x 2>&1"
	## Only the passthrough's own scan runs before 'raw', so an option it didn't take left the main
	## parser looking at a command called 'raw' - and it reported "Unknown command 'raw'", naming
	## the one token that was not the problem. These are inert here; being taken is the point.
	local rawOpt=""
	for rawOpt in "-NoFetch" "-AnyIdentity" "-Public"; do
		fAssertOut "${rawOpt} before raw is taken, not blamed"  '^main$' \
			bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q ${rawOpt} raw git rev-parse --abbrev-ref HEAD 2>/dev/null"
	done
	## An option that really is unknown must still be refused - and by its own name.
	fAssertOut "an unknown option before raw names itself"  'bogus' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q --bogus raw git status 2>&1"
	## '--' is git's pathspec separator, so 'raw git log -- path' has to work. Bash takes it
	## directly; PowerShell's binder reads a bare '--' as an empty parameter name and dies before
	## the script runs at all, so there it is spelled '`--' and unescaped on the way to git.
	## Asserted against a path that does NOT exist: a separator that was dropped would still list
	## the commit, so only the empty result proves git actually received one.
	local sep="--"
	fAssertOut    "raw passes a pathspec separator through"  '^init$' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git log --format=%s '${sep}' a.txt 2>/dev/null"
	fAssertNotOut "and it really separates - an absent path lists nothing"  'init' \
		bash -c "cd '${acWork}' && env ${acEnv} '${gitsby}' -q raw git log --format=%s '${sep}' nosuchfile.txt 2>/dev/null"

	## How release.bash reads the changelog, which nothing else here reaches. changelog.md opens
	## with a commented-out template whose headings are shaped exactly like real ones, and a
	## first-match search has landed on that decoy three times now. The last one would have
	## retitled the template, left the real section saying vNEXT, published the empty template as
	## the release body, and warned about none of it. Two independent guards, either enough on its
	## own. Pinned in the source because exercising it for real means cutting a release; bash leg
	## only, since neither file belongs to an implementation.
	local relBash="${root}/cicd/release.bash" clMd="${root}/changelog.md"
	fAssertFail "the changelog's template heading can't pass for a real one" \
		grep -qE '^## vNEXT - DATE' "${clMd}"
	fAssert "and the real vNEXT section is still findable below the template" \
		awk '/^-->/{p=1; next} p && /^## vNEXT$/{n=1} END{exit !n}' "${clMd}"
	fAssert "release.bash reads the changelog from past the template" \
		grep -q 'fpChangelogStart' "${relBash}"
	fAssertFail "and retitles by line number, not by first match" \
		grep -qE '0,/\^## vNEXT' "${relBash}"
	## The gate is the one thing a release most depends on. There is one engine now, so what
	## has to hold is simply that the release runs it and stops on a failure.
	fAssert "release.bash runs the pipeline before touching anything" \
		grep -q 'cicd.bash --no-publish' "${relBash}"
	fAssert "and treats a failing pipeline as fatal" \
		grep -q 'the pipeline did not pass' "${relBash}"

	## Recursive removal. demo-repo.bash is the only script here that removes a path someone else
	## named, so it gets real checks; the rest only ever remove what mktemp just handed them, and
	## that is pinned in the source. None of these files belong to an implementation, which is why
	## they outlived the leg they used to ride. A Ctrl-C mid-probe can't be staged on every platform
	## (a native child defers the signal), so the probe's own cleanup is asserted where it lives.
	## The single quotes in the searches below are the point - they look for literal source text,
	## so each one turns off the expansion warning for itself.
	local demoRepo="${root}/cicd/utility/demo/demo-repo.bash" rmWork="${work}/rmsafe"
	mkdir -p "${rmWork}/notmine/keep"; echo keepme > "${rmWork}/notmine/keep/file.txt"
	## On the message, not just the exit code: a build that refuses for some unrelated reason
	## later on exits nonzero too, and two of these passed against the unguarded script on
	## that alone.
	fAssertFail "demo-repo refuses a root it did not build" \
		bash "${demoRepo}" "${rmWork}/notmine"
	fAssertOut  "and says whose directory it is" 'did not build it' \
		bash "${demoRepo}" "${rmWork}/notmine"
	fAssertOut  "and leaves that directory untouched" '^keepme$' \
		cat "${rmWork}/notmine/keep/file.txt"
	fAssertOut  "demo-repo refuses a relative root"      'plain absolute path' \
		bash "${demoRepo}" relative/path
	fAssertOut  "demo-repo refuses a root containing .." 'plain absolute path' \
		bash "${demoRepo}" "${rmWork}/a/../b"
	## Deliberately NOT run: passing '/' to a build that lacks the guard is 'rm -rf /'. It is
	## one clause of the same test the two checks above exercise for real, so it is pinned.
	# shellcheck disable=SC2016
	fAssert "and the same test rejects the filesystem root" \
		grep -qF '"${root}" != "/"' "${demoRepo}"
	fAssert "the publish probe's dir is removed on the way out, not only in the happy path" \
		grep -q '_probeDir' "${root}/legacy/bin/gitsby"
	# shellcheck disable=SC2016
	fAssert "and its pwsh counterpart tests the path before removing it" \
		grep -q 'if ($probeDir) { Remove-Item' "${root}/legacy/bin/gitsby.ps1"
	local rmScript
	for rmScript in cicd/cicd.bash cicd/test.bash cicd/fuzz.bash cicd/parity.bash \
	                cicd/release.bash cicd/utility/demo/demo-repo.bash \
	                legacy/bin/gitsby legacy/install.bash legacy/install-dev.bash; do
		fAssertFail "${rmScript} never removes an unguarded variable path" \
			grep -qE 'rm -[rf]+ +(-- )?"\$\{[a-zA-Z_][a-zA-Z_0-9]*\}' "${root}/${rmScript}"
	done
	## ------------------------------------------------------------------------------------
	## The pipeline itself, after the directive review. Where a check would need a whole run
	## to exercise, it pins the thing in the source and says so.

	## Version-control stamps go into a Go binary by default, and the release builds its assets
	## before it cuts the tag - so the published binaries carried the previous revision and
	## nobody, us included, could rebuild them to the checksums we publish.
	fAssert "the build flags keep version control out of the binary" \
		bash -c "grep -q 'buildvcs=false' '${root}/cicd/config.bash'"
	## Built here rather than read off the suite's own binary: that one may have come from a
	## hand-run 'go build', which legitimately carries the stamps.
	fAssert "and a build with them carries no revision stamp" \
		bash -c "cd '${root}/src-go' && go build -trimpath -buildvcs=false -o '${work}/vcsprobe' . && ! go version -m '${work}/vcsprobe' | grep -q 'vcs\.revision'"
	## The build number is minutes since 2000, Crockford base32, lower case. Built here with a
	## fixed stamp: the suite's own binary carries whatever the last build gave it.
	fAssertOut "a stamped build reports minutes since 2000 in Crockford base32"  'gitsby v9\.9\.9 build dbd05,' \
		bash -c "cd '${root}/src-go' && go build -ldflags '-X main.version=9.9.9 -X main.buildEpoch=1787000000' -o '${work}/bnprobe' . && '${work}/bnprobe' --version"
	## A number invented from the clock would say the opposite of what a build number means, so
	## an unstamped build reports none rather than one that moves every minute.
	fAssertOut "an unstamped build reports no build number"  '^gitsby v9\.9\.9, Copyright' \
		bash -c "cd '${root}/src-go' && go build -ldflags '-X main.version=9.9.9' -o '${work}/bnprobe0' . && '${work}/bnprobe0' --version"
	## Taken from the commit rather than the clock, or a published asset could never be rebuilt
	## to its published checksum - the same reason -buildvcs=false is above.
	fAssert "every build site stamps a build number" \
		bash -c "[[ \"\$(grep -c 'main.buildEpoch=' '${root}/cicd/cicd.bash' '${root}/cicd/release.bash' | awk -F: '{t+=\$2} END{print t}')\" == 3 ]]"
	fAssert "the build number comes from the commit, not the clock" \
		bash -c "grep -q 'log -1 --format=%ct' '${root}/cicd/cicd.bash' '${root}/cicd/release.bash'"
	## Phase 1 proves every target still compiles; phase 3 rebuilds them once the tag exists, and
	## those are the bytes that get uploaded. Without the second build the published build number
	## would belong to a commit the tag does not point at.
	fAssert "the release rebuilds its assets from the tagged commit" \
		bash -c "[[ \"\$(grep -c 'fpCrossBuild ' '${root}/cicd/release.bash')\" == 2 ]]"
	fAssert "and the release notes carry the build number" \
		bash -c "grep -q 'buildLine' '${root}/cicd/release.bash'"
	fAssert "every build site shares one set of flags" \
		bash -c "[[ \"\$(grep -c 'GO_BUILD_FLAGS\[@\]' '${root}/cicd/cicd.bash' '${root}/cicd/release.bash' | awk -F: '{t+=\$2} END{print t}')\" == 3 ]]"
	## The compiler takes every core by default, in every build and in the eight-target
	## release loop, which makes the machine unusable for the duration.
	fAssert "no build step takes every core"  bash -c "grep -q 'BUILD_JOBS=' '${root}/cicd/config.bash'"
	fAssertFail "no go build call is missing -p" \
		bash -c "grep -hE '^[[:space:]]*(go build|.*&& *go build)' '${root}/cicd/cicd.bash' '${root}/cicd/release.bash' | grep -qv 'BUILD_JOBS'"
	## Every dogfood dest is a share path or a $HOME expansion. A literal home dir would name
	## an account, and would resolve to nothing on any other box.
	fAssertFail "no dogfood dest hardcodes a home directory" \
		bash -c "grep -qE '\"(/home/|/Users/|C:/Users/)' '${root}/cicd/config.bash'"
	## A .exe would match a Linux ~/.local/bin every run, so the fallback is per-box.
	fAssert "the dogfood fallback only applies to this box's own target" \
		bash -c "grep -q 'DOGFOOD_FALLBACK_DIR' '${root}/cicd/config.bash' && grep -q 'host_goos' '${root}/cicd/cicd.bash'"
	## --quick skips the fuzz and the gif, which are not the slow part; three cross-builds are.
	fAssert "--quick narrows the cross-builds too" \
		bash -c "grep -q 'quick).*DOGFOOD_TARGETS=' '${root}/cicd/cicd.bash'"
	## With no third-party dependencies the standard library is the only library code there is.
	fAssert "the pipeline checks the standard library for known problems" \
		bash -c "grep -q 'govulncheck' '${root}/cicd/cicd.bash'"
	## The profiling step. A sampling profile would be a flat wall here - this program is
	## blocked on git for all of its wall clock - so what gets measured is how often it forks.
	fAssert "a spawn-count step exists and gates" \
		bash -c "[[ -x '${root}/cicd/utility/spawn-count.bash' ]] && grep -q 'SPAWN_COUNT_CMD' '${root}/cicd/cicd.bash'"
	fAssert "and a kept-build script exists for bisecting against an older one" \
		bash -c "[[ -x '${root}/cicd/utility/keep-build.bash' ]]"
	fAssert "and a pooled-copy runner exists for driving the newest build" \
		bash -c "[[ -x '${root}/cicd/utility/run-latest.ps1' ]]"
	fAssert "and a spawn report exists for the startup look, marker-gated like lint's" \
		bash -c "[[ -x '${root}/cicd/utility/spawn-report.bash' ]] && grep -q 'spawn-seen' '${root}/cicd/utility/spawn-report.bash'"
	## -q reached the publisher and nothing else, so an unattended run still printed every one
	## of 900-odd check lines and buried every stage header.
	local qHarness=""
	for qHarness in test fuzz parity; do
		fAssert "cicd/${qHarness}.bash accepts -q"  bash -c "grep -q -- '-q|--quiet) quiet=1' '${root}/cicd/${qHarness}.bash'"
	done
	fAssert "and the engine hands it on"  bash -c "grep -q 'harness_quiet' '${root}/cicd/cicd.bash'"
	## The lint summary matched the suites' own check labels - several of which contain the
	## words "warning" and "error", because that is what those checks are about.
	local lrLog="${work}/lint-report"; mkdir -p "${lrLog}"
	{
		echo "  ok: and raises no shell error of its own"
		echo "  ok: the offline warning names its branch"
		echo "[ OK: gofmt + go vet clean ]"
		echo "passed: 649, failed: 0"
	} > "${lrLog}/run_20260819-000000.log"
	fAssertOut "the lint summary calls a clean run clean"  'CLEAN' \
		bash -c "'${root}/cicd/utility/lint-report.bash' --file '${lrLog}/run_20260819-000000.log'"
	fAssertOut "and still reports a real finding"  'warning line' \
		bash -c "printf 'file.sh:3:1: SC2086 warning: quote this\n' > '${lrLog}/run_20260819-000001.log'; '${root}/cicd/utility/lint-report.bash' --file '${lrLog}/run_20260819-000001.log'"
	## The demo scenario is what the gif is rendered from, so a command renamed in the product
	## and not there means the next render publishes the old name.
	fAssertFail "the demo scenario names no renamed command" \
		grep -qE '\{(prog|bin)\} (update|br land)' "${root}/cicd/utility/demo/demo-scenario.toml"
	fAssertFail "and the demo notes point at no deleted engine" \
		grep -q 'cicd-win' "${root}/cicd/utility/demo/script.txt"
	## Two things the demo started putting on camera once the binary grew the checks that
	## noticed them: a warning about its own fixture's file permissions, and - by way of the
	## real gh - the name of whoever is logged in on the machine doing the rendering.
	fAssert "the demo's fake tokens are not left world-readable" \
		grep -q 'chmod 600' "${root}/cicd/utility/demo/demo-repo.bash"
	fAssert "and the demo answers gh itself, so no real login reaches the frame" \
		bash -c "grep -q 'bin/gh' '${root}/cicd/utility/demo/demo-repo.bash' && grep -q \"export PATH='\\\${root}/bin'\" '${root}/cicd/utility/demo/demo-repo.bash'"

	## The Windows resource. Built here rather than pinned in the source, because the failure
	## mode is the linker quietly ignoring a .syso whose name does not match the target: the
	## file is present, the build succeeds, and the .exe comes out bare.
	local winExe=""
	for winExe in amd64 arm64; do
		fAssert "windows/${winExe} builds with the resource beside it" \
			bash -c "cd '${root}/src-go' && CGO_ENABLED=0 GOOS=windows GOARCH=${winExe} go build -trimpath -buildvcs=false -o '${work}/winres-${winExe}.exe' ."
		fAssert "and the .exe carries version details" \
			bash -c "grep -aqP 'V\x00S\x00_\x00V\x00E\x00R\x00S\x00I\x00O\x00N\x00_\x00I\x00N\x00F\x00O\x00' '${work}/winres-${winExe}.exe'"
		fAssert "and an icon" \
			bash -c "LC_ALL=C grep -aq \$'\x89PNG' '${work}/winres-${winExe}.exe'"
	done
	## The terminal test is per-platform, and the fallback that answered for everything but Linux
	## and Windows was a character-device test - which passes for /dev/null, the one case the
	## no-terminal rule exists for. macOS and FreeBSD are published targets, so they get the real
	## query. Built rather than pinned: a build constraint that excludes the wrong set compiles
	## two isTTY into one package, or none.
	local bsdTarget=""
	for bsdTarget in darwin/arm64 darwin/amd64 freebsd/amd64; do
		fAssert "${bsdTarget} builds with its own terminal test" \
			bash -c "cd '${root}/src-go' && CGO_ENABLED=0 GOOS='${bsdTarget%%/*}' GOARCH='${bsdTarget##*/}' go build -trimpath -buildvcs=false -o '${work}/tty-${bsdTarget//\//-}' ."
	done
	fAssert "and the character-device fallback covers neither" \
		bash -c "grep -q '^//go:build !linux && !windows && !darwin' '${root}/src-go/tty_other.go'"

	## '~' in a config value used to expand through HOME alone, which nothing sets on native
	## Windows - so every tilde path there resolved to nothing at all, silently. One helper
	## answers it now; a bare lookup anywhere else is the bug coming back.
	fAssert "only one place resolves the home directory" \
		bash -c "[[ \"\$(cat \"${root}\"/src-go/*.go | grep -c 'os.Getenv(\"HOME\")')\" == 1 ]]"

	## vcsprobe above is this same tree built for the host. A resource named without the
	## GOOS_GOARCH suffix would link into every platform, which is a bigger mistake than
	## shipping none at all.
	fAssertFail "nothing but windows picks the resource up" \
		bash -c "grep -aqP 'V\x00S\x00_\x00V\x00E\x00R\x00S\x00I\x00O\x00N\x00_\x00I\x00N\x00F\x00O\x00' '${work}/vcsprobe'"
	## Committed rather than generated at build time: it is linked into bytes we publish
	## checksums for, so rebuilding a release from its tag must not need a tool installed.
	local winArch=""
	for winArch in amd64 arm64; do
		fAssert "the ${winArch} resource is a file in the tree" \
			bash -c "[[ -s '${root}/src-go/resource_windows_${winArch}.syso' ]]"
	done
	fAssertFail "and the two are not one file copied twice" \
		cmp -s "${root}/src-go/resource_windows_amd64.syso" "${root}/src-go/resource_windows_arm64.syso"
	## Six sizes, 16 through 256. Windows synthesizes the rest, badly.
	fAssert "the icon holds the six sizes it is generated with" \
		bash -c "[[ \"\$(head -c 6 '${root}/assets/gitsby.ico' | od -An -tu1 | tr -s ' ')\" == ' 0 0 1 0 6 0' ]]"
	fAssert "the pipeline checks the resource against the newest tag" \
		bash -c "grep -q 'WINRES_CMD' '${root}/cicd/cicd.bash' && grep -q 'WINRES_CMD' '${root}/cicd/config.bash'"
	## Phase 1 builds the assets, phase 2 commits the bump - so the stamp has to happen twice,
	## and phase 1 has to undo its half or it stops being the phase that changes nothing.
	fAssert "a release stamps the resource with the version it cuts" \
		bash -c "[[ \"\$(grep -c 'winres\[@\]' '${root}/cicd/release.bash')\" == 3 ]]"
	fAssert "and phase 1 puts it back afterwards" \
		bash -c "grep -q 'checkout -q -- \"\${GO_MODULE_DIR}\"/\*.syso' '${root}/cicd/release.bash'"

	## Hermeticity, the half that pinning the config FILES does not cover. Two inputs reach a
	## harness from an ordinary working terminal and outrank everything it does set:
	## GIT_CONFIG_COUNT/KEY_n beat every config file including a repo-local one, and an
	## inherited GH_TOKEN is what the fake gh reports back. A run carrying either still reports
	## a count and a list of names - the checks are simply no longer about what they say.
	## The bracketed last letter keeps the pattern from matching this line when the file being
	## searched is this one, which would pass against a harness that dropped the isolation.
	local hermScript
	for hermScript in cicd/test.bash cicd/fuzz.bash cicd/parity.bash; do
		fAssert "${hermScript} drops env-injected git config" \
			grep -qE 'unset GIT_CONFIG_COUN[T]' "${root}/${hermScript}"
		fAssert "${hermScript} drops an inherited gh token" \
			grep -qE 'unset GH_TOKE[N]' "${root}/${hermScript}"
	done
	## Runtime companions to the pins above. Regression guards, not discriminating checks: on a
	## clean machine they pass just as well against a harness that isolates nothing.
	# shellcheck disable=SC2016  ## the inner shell has to do the expanding, not this one.
	fAssert "this run carries no env-injected git config"  bash -c '[[ -z "${GIT_CONFIG_COUNT:-}" ]]'
	# shellcheck disable=SC2016
	fAssert "and no inherited gh token"                    bash -c '[[ -z "${GH_TOKEN:-}" ]]'

	## Go-only: the renamed commands, the aliases that keep every 2.1.0 spelling working, and
	## 'whoami'. The scripts are frozen at the old surface, so asserting the new names on their
	## legs would only prove that a frozen file is frozen.
	local renDir="${work}/rename"
	git clone --quiet "${origin}" "${renDir}"
	fAssertOut "help leads with the new name" 'pullcom \[msg\] \.+: Pull updates'        "${gitsby}" --help
	fAssertOut "and offers br merge"          'br merge \[msg\] \.+: Merge current'      "${gitsby}" --help
	fAssertOut "and lists whoami"             'whoami \.+: Show account, ssh key'        "${gitsby}" --help
	## Every accepted spelling, because a ladder is only worth having if the whole ladder is
	## there - a missing rung reads as a typo the tool refused for no reason.
	local spelling
	for spelling in pullcom update pull pullc pullco pullcomm pullcommit; do
		fAssert "'${spelling}' commits" bash -c "cd '${renDir}' && echo x >> '${spelling}.txt' && '${gitsby}' -q ${spelling} 'via ${spelling}' && git -C '${renDir}' log -1 --pretty=%s | grep -qx 'via ${spelling}'"
	done
	fAssertPlan "'br merge' merges the current branch" 'git merge --no-ff renmerge' \
		bash -c "cd '${renDir}' && '${gitsby}' -q br create renmerge >/dev/null && '${gitsby}' -q br merge 'merged' 2>&1"
	fAssertPlan "'br land' still does the same"        'git merge --no-ff renland' \
		bash -c "cd '${renDir}' && '${gitsby}' -q br create renland >/dev/null && '${gitsby}' -q br land 'landed' 2>&1"
	fAssertOut  "an unknown br subcommand names merge, not land" 'switch, merge, prune' \
		bash -c "cd '${renDir}' && '${gitsby}' -q br frobnicate 2>&1"
	## whoami is the status block's identity half on its own, and the one read-only command
	## that answers outside a repo - which is where you ask it, before cloning anything.
	fAssert     "whoami exits 0"              bash -c "cd '${renDir}' && '${gitsby}' whoami"
	fAssertOut  "and names the commit author" '^Author \.+: test <test@test>' \
		bash -c "cd '${renDir}' && '${gitsby}' whoami 2>&1"
	fAssertNotOut "and leaves out the working-tree state" 'Local changes:' \
		bash -c "cd '${renDir}' && '${gitsby}' whoami 2>&1"
	fAssert     "whoami answers outside a repo" bash -c "cd '${work}' && '${gitsby}' whoami"
	fAssertFail "whoami with a trailing argument rejected" \
		bash -c "cd '${renDir}' && '${gitsby}' whoami extra"
	## Both older spellings are permanent aliases, so neither may quietly become a typo.
	for spelling in who identity; do
		fAssertOut "'${spelling}' answers as whoami" '^Author \.+: test <test@test>' \
			bash -c "cd '${renDir}' && '${gitsby}' ${spelling} 2>&1"
	done

	## --offline was a silent spelling of --no-fetch that never stopped a push. It is refused by
	## name now, so the one thing it promised can't be believed on the strength of the word.
	fAssertOut  "--offline is refused by name"              'no --offline option' \
		bash -c "cd '${renDir}' && '${gitsby}' --offline status 2>&1"
	fAssertOut  "and points at the option that does exist"  'use --no-fetch' \
		bash -c "cd '${renDir}' && '${gitsby}' --offline status 2>&1"
	fAssertFail "--offline ahead of raw is refused, not handed to the tool" \
		bash -c "cd '${renDir}' && '${gitsby}' --offline raw git status"
	fAssert     "--no-fetch still parses"  bash -c "cd '${renDir}' && '${gitsby}' --no-fetch status"
	fAssert     "and so does --nofetch"    bash -c "cd '${renDir}' && '${gitsby}' --nofetch status"

	## Options and no command ask what no arguments ask. -q means no prompts, never no output.
	fAssertOut  "'-q' alone prints the command list"  'Common commands:' \
		bash -c "cd '${renDir}' && '${gitsby}' -q 2>&1"
	fAssertFail "and still exits nonzero"            bash -c "cd '${renDir}' && '${gitsby}' -q"
	fAssertOut  "'-q --help' prints it too"          'Common commands:' \
		bash -c "cd '${renDir}' && '${gitsby}' -q --help 2>&1"

	## pr was the one command that dropped a trailing argument in silence.
	fAssertOut  "'pr <n> extra' names the extra argument"  "Unexpected extra argument 'extra'" \
		bash -c "cd '${renDir}' && '${gitsby}' -q pr 5 extra 2>&1"
	fAssertOut  "'pr create' with an unquoted title says to quote it"  'quote your title' \
		bash -c "cd '${renDir}' && '${gitsby}' -q pr create My title 2>&1"
	fAssertOut  "and a longer unquoted one says so too"  'quote it' \
		bash -c "cd '${renDir}' && '${gitsby}' -q pr create My much longer title 2>&1"

	## Ours come before 'raw', the tool's after it - which is not the same as never having heard
	## of what was typed.
	fAssertOut  "an option between raw and the tool says where ours go"  "options come before 'raw'" \
		bash -c "cd '${renDir}' && '${gitsby}' raw -q git status 2>&1"

	## ------------------------------------------------------------------------------------
	## Directive review 20260819. Every check below fails against the build that preceded it,
	## bar the two marked as follow-up state checks on the run above them.
	local dr="${work}/$1-dirrev"
	mkdir -p "${dr}/bin" "${dr}/home/.config/gitsby" "${dr}/tree"
	local drCanon="${dr}"
	((isWindows)) && drCanon="$( cd "${dr}" && pwd -W )"

	## rev-parse --is-inside-work-tree answers in text and exits zero either way, so the exit
	## code says only that we are somewhere git understands. A bare repo and the .git directory
	## are both that, and neither is a place any of this means anything.
	git init --quiet --bare -b main "${dr}/bare.git"
	git init --quiet -b main "${dr}/wt"
	( cd "${dr}/wt" && echo a > a.txt && git add --all && git commit --quiet -m init )
	fAssertOut "a bare repo is refused by name"       'bare repository' \
		bash -c "cd '${dr}/bare.git' && '${gitsby}' -q -NoFetch status 2>&1"
	fAssertOut "and the .git directory itself too"    "'\.git' directory" \
		bash -c "cd '${dr}/wt/.git' && '${gitsby}' -q -NoFetch status 2>&1"

	## With no remote at all the offline check never trips - there is nothing to find
	## unreachable - so the tag was cut, pushed nowhere, and the run ended on "Done."
	fAssertOut "release with no origin refuses"       "No 'origin' remote, and a release" \
		bash -c "cd '${dr}/wt' && '${gitsby}' -q -NoFetch release 2>&1"
	fAssert    "and cut no tag"                       bash -c "cd '${dr}/wt' && [[ -z \"\$(git tag --list)\" ]]"

	## A bare 'git fetch' follows the current branch's own tracking remote, and every existence
	## check afterwards reads origin. Only a fetch that names origin sees a branch pushed there.
	git init --quiet --bare -b main "${dr}/f-origin.git"
	git init --quiet --bare -b main "${dr}/f-other.git"
	git clone --quiet "${dr}/f-origin.git" "${dr}/fetchr" 2>/dev/null
	(
		cd "${dr}/fetchr" && echo a > a.txt && git add --all && git commit --quiet -m init
		git push --quiet -u origin main
		git remote add other "${dr}/f-other.git" && git push --quiet other main
		git branch --quiet --set-upstream-to=other/main main
	)
	git clone --quiet "${dr}/f-origin.git" "${dr}/pusher" 2>/dev/null
	( cd "${dr}/pusher" && git checkout --quiet -b brandnew && git push --quiet -u origin brandnew )
	fAssert "the pre-command fetch names origin, not the branch's own remote" \
		bash -c "cd '${dr}/fetchr' && '${gitsby}' -q status >/dev/null 2>&1; git -C '${dr}/fetchr' show-ref --verify --quiet refs/remotes/origin/brandnew"

	## br merge holds its remote delete back while origin is unreachable; prune had no such
	## check, so each push failed and was reported as "already gone" - blaming the branch for a
	## network problem, with a summary that read as if it had finished.
	git init --quiet --bare -b main "${dr}/p-origin.git"
	git clone --quiet "${dr}/p-origin.git" "${dr}/prune" 2>/dev/null
	(
		cd "${dr}/prune" && echo a > a.txt && git add --all && git commit --quiet -m init
		git push --quiet -u origin main
		git checkout --quiet -b landed && git push --quiet -u origin landed
		git checkout --quiet main && git merge --quiet --no-ff landed -m merge && git push --quiet
	)
	rm -rf -- "${dr:?}/p-origin.git"
	fAssertOut "br prune offline leaves origin's copies alone"  "left origin's copies" \
		bash -c "cd '${dr}/prune' && '${gitsby}' -q br prune 2>&1"
	fAssert    "but still deletes the local branch"    bash -c "cd '${dr}/prune' && [[ -z \"\$(git branch --list landed)\" ]]"

	## git's DWIM creates a tracking branch from a remote copy only when exactly one remote has
	## it; with two it refuses to guess, and the up-front check never noticed because it only
	## ever looks at origin.
	git init --quiet --bare -b main "${dr}/t-origin.git"
	git init --quiet --bare -b main "${dr}/t-other.git"
	git clone --quiet "${dr}/t-origin.git" "${dr}/two" 2>/dev/null
	(
		cd "${dr}/two" && echo a > a.txt && git add --all && git commit --quiet -m init
		git push --quiet -u origin main
		git checkout --quiet -b feature && git push --quiet -u origin feature
		git checkout --quiet main
		git remote add other "${dr}/t-other.git"
		git push --quiet other main && git push --quiet other feature
		git branch --quiet -D feature && git fetch --quiet --all
	)
	fAssert "br switch works with two remotes carrying the branch" \
		bash -c "cd '${dr}/two' && '${gitsby}' -q -NoFetch br switch feature && [[ \"\$(git branch --show-current)\" == feature ]]"

	## Two accounts claiming one folder produce the same includeIf key twice. --unset-all takes
	## every entry at once, so the second pass found nothing and git's exit 5 was read as a
	## failure: the config was left with no rules at all, and the command reported an error.
	fStub "${dr}/bin/gh" <<-'GHEOF'
		#!/usr/bin/env bash
		case "$1 $2" in
			"auth token") exit 1 ;;
			"api user")   echo "${FAKE_GH_ACTIVE:-someoneelse}"; exit 0 ;;
		esac
		exit 1
	GHEOF
	cat > "${dr}/home/.config/gitsby/config.shcl" <<-CFGEOF
		account.abe.path      = ${drCanon}/tree
		account.abe.ghAccount = abe
		account.abe.name      = Abe Person
		account.abe.email     = abe@example.com
		account.zed.path      = ${drCanon}/tree
		account.zed.ghAccount = zed
	CFGEOF
	: > "${dr}/home/.gitconfig"
	git init --quiet -b main "${dr}/tree/proj"
	( cd "${dr}/tree/proj" && echo a > a.txt && git add --all && git commit --quiet -m init )
	local drEnv="${acNoDiscovery} HOME='${dr}/home' GIT_CONFIG_GLOBAL='${dr}/home/.gitconfig' PATH='${dr}/bin:${PATH}'"
	fAssert "account apply runs with two accounts on one folder" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q account apply >/dev/null"
	fAssert "and a second run leaves the rules in place" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q account apply >/dev/null && grep -q 'gitsby/accounts' '${dr}/home/.gitconfig'"
	fAssertOut "and the contested folder is called out" 'more than one account claims' \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q account 2>&1"
	## The two tie-breaks used to disagree: gitsby keeps the first rule declared, git keeps the
	## last written, and sorting the plan by text put them in opposite orders.
	fAssertOut "gitsby keeps the first rule declared"  'Account \.+: abe' \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q account 2>&1"
	fAssert "and plain git now resolves it the same way" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} git config gitsby.ghAccount | grep -qx abe"

	## Account selection is skipped entirely under --any-identity - the token, the key and the
	## commit author all stay as they were - and the block used to name the account anyway.
	fAssertOut "--any-identity says the account was not applied"  'nothing applied - gitsby was run with --any-identity' \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q -NoFetch --any-identity status 2>&1"

	## Treating a malformed count as zero numbers our entries over the caller's first few and
	## leaves the rest applying - half a config each, and nobody's intent.
	fAssertOut "a GIT_CONFIG_COUNT that isn't a count stops the run"  "isn't a count" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} GIT_CONFIG_COUNT=notanumber '${gitsby}' -q -NoFetch identity 2>&1"

	## A token read from a file says nothing about whose it is: the name came from a config key
	## beside it, so a stale file reports the right name and pushes as the wrong person.
	printf 'gho_stale\n' > "${dr}/token"
	cat > "${dr}/token.shcl" <<-TOKEOF
		account.abe.path      = ${drCanon}/tree
		account.abe.ghAccount = abe
		account.abe.tokenFile = ${drCanon}/token
	TOKEOF
	fAssertOut "a file-sourced token is checked against the account it claims"  "authenticates as 'someoneelse'" \
		bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q -NoFetch --config '${dr}/token.shcl' identity 2>&1"

	## Naming an account for a repo you only cloned tells a single-account user about a feature
	## they never configured, and claims something was applied when nothing was.
	git init --quiet -b main "${dr}/stranger"
	(
		cd "${dr}/stranger" && echo a > a.txt && git add --all && git commit --quiet -m init
		git remote add origin https://github.com/stranger/repo.git
	)
	fAssertNotOut "raw names no account for a repo you only cloned"  'acting as' \
		bash -c "cd '${dr}/stranger' && env ${drEnv} '${gitsby}' raw git status 2>&1"

	## Mode bits, where the platform has any worth reading. A token file everyone can read loads
	## without a word, and the fragment directory was created 0777 and left to umask.
	if ((! isWindows)); then
		chmod 644 "${dr}/token"
		fAssertOut "a token file other users can read is called out"  'readable by other users' \
			bash -c "cd '${dr}/tree/proj' && env ${drEnv} '${gitsby}' -q -NoFetch --config '${dr}/token.shcl' identity 2>&1"
		fAssert "the account fragments are yours alone" \
			bash -c "[[ \"\$(stat -c %a '${dr}/home/.config/gitsby/accounts')\" == 700 ]] && [[ \"\$(stat -c %a '${dr}/home/.config/gitsby/accounts/abe.gitconfig')\" == 600 ]]"
	fi

	##••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
	## Other forges. gitsby was a GitHub program that reached for gh whenever it wanted anything from
	## a remote; most of what it does is git, and git does not care whose server it is. What is
	## covered here is the seam: the host decides the tool, the tool is only reached for once the
	## host is known to be one it serves, and everything that never needed a forge CLI keeps working
	## without one. A '.test' host is reserved and resolves nowhere, so -NoFetch keeps it all local.
	##••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
	local fg="${work}/$1-forge"
	mkdir -p "${fg}/bin" "${fg}/debbin"
	## A deterministic tea. Logs every call the way the gh stub does, so a check can see not just
	## that a pull request was asked for but which vocabulary it was asked in.
	fStub "${fg}/bin/tea" <<'TEAEOF'
#!/usr/bin/env bash
[[ -n "${FAKE_TEA_LOG:-}" ]] && echo "$*" >> "${FAKE_TEA_LOG}"
case "$1 $2" in
"logins list") printf '"Name"\t"URL"\t"SSHHost"\t"User"\t"Default"\n' ;
               printf '"work"\t"https://git.example.test"\t""\t"%s"\t"true"\n' "${FAKE_TEA_USER:-giteauser}" ;;
"pulls list")  printf '"index"\t"head"\n' ; [[ -n "${FAKE_TEA_EXISTING:-}" ]] && printf '"%s"\t"%s"\n' "${FAKE_TEA_EXISTING}" "${FAKE_TEA_HEAD:-feat}" ;;
*)             : ;;
esac
exit 0
TEAEOF
	## The same program under the name Debian ships it as. Looking for one spelling finds it only on
	## the machines that happen to use that one.
	fStub "${fg}/debbin/tea-cli" <<'TEAEOF'
#!/usr/bin/env bash
[[ -n "${FAKE_TEA_LOG:-}" ]] && echo "$*" >> "${FAKE_TEA_LOG}"
exit 0
TEAEOF
	## gh is on the path throughout this block, and must never be the one that answers.
	fStub "${fg}/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
[[ -n "${FAKE_GH_LOG:-}" ]] && echo "$*" >> "${FAKE_GH_LOG}"
exit 0
GHEOF
	cp "${fg}/bin/gh" "${fg}/debbin/gh" 2>/dev/null; fStubShim "${fg}/debbin/gh"
	local fgRepo="${fg}/proj"
	git init --quiet -b main "${fgRepo}"
	(
		cd "${fgRepo}" || exit 1
		echo a > a.txt && git add --all && git commit --quiet -m init
		git remote add origin https://git.example.test/acme/proj.git
	)
	local fgPath="${fg}/bin:${PATH}"
	local fgDeb="${fg}/debbin:${PATH}"
	## A path with git on it and no forge CLI at all. Not an empty directory: that takes git away
	## too, and then 'Not found in path: git' comes first and the refusal under test never runs -
	## the exit-code check passes for a reason that has nothing to do with what it is checking.
	## Linked, not wrapped: a '#!/usr/bin/env bash' wrapper needs bash found on the very PATH we are
	## emptying, so it fails to start and the run reads as "not a git repository" instead.
	mkdir -p "${fg}/gitonly"
	local fgBare="${fg}/gitonly"
	## bash as well as git: ${gitsby} is itself a '#!/usr/bin/env bash' shim, so emptying the PATH of
	## bash stops the binary launching at all - which reads as "not a git repository", not as the
	## refusal under test.
	if ! ln -s "$(command -v bash)" "${fg}/gitonly/bash" 2>/dev/null || ! ln -s "$(command -v git)" "${fg}/gitonly/git" 2>/dev/null; then
		## No symlinks (Windows without developer mode): keep the real path on, minus the stubs.
		fgBare="${PATH}"
	fi

	## The whole point: a Gitea remote is served by tea, and gh - installed, on the path, perfectly
	## willing - is not asked anything at all.
	: > "${fg}/tea.log"; : > "${fg}/gh.log"
	fAssert "a Gitea remote lists pull requests through tea" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' FAKE_TEA_LOG='${fg}/tea.log' FAKE_GH_LOG='${fg}/gh.log' '${gitsby}' -q -NoFetch pr && grep -q '^pulls list' '${fg}/tea.log'"
	fAssert "and gh is never run for it, though it is installed" \
		bash -c "! grep -q . '${fg}/gh.log'"
	## Debian renames the binary because the name was taken. One spelling found is not both found.
	: > "${fg}/deb.log"
	fAssert "tea is found under the 'tea-cli' name too" \
		bash -c "cd '${fgRepo}' && PATH='${fgDeb}' FAKE_TEA_LOG='${fg}/deb.log' '${gitsby}' -q -NoFetch pr && grep -q . '${fg}/deb.log'"

	## No CLI for the host: the refusal has to name the host that decided it and the tool that would
	## serve it. Telling a Gitea user to install a GitHub client is the failure this replaced.
	fAssertFail "a Gitea remote with no forge CLI refuses"  bash -c "cd '${fgRepo}' && PATH='${fgBare}' '${gitsby}' -q -NoFetch pr"
	fAssertOut  "and names the host that decided it"  'git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgBare}' '${gitsby}' -q -NoFetch pr 2>&1"
	fAssertOut  "and points at tea rather than gh"  'tea' \
		bash -c "cd '${fgRepo}' && PATH='${fgBare}' '${gitsby}' -q -NoFetch pr 2>&1"

	## 'repo url' only ever rewrites text - it asks the host nothing - so refusing it anywhere but
	## github.com was the parser's limit showing through as a rule.
	fAssertOut "repo url shows a Gitea remote's ssh spelling"    'git@git\.example\.test:acme/proj\.git' \
		bash -c "cd '${fgRepo}' && '${gitsby}' -q -NoFetch repo url 2>&1"
	fAssertOut "repo url shows its https spelling too"           'https://git\.example\.test/acme/proj\.git' \
		bash -c "cd '${fgRepo}' && '${gitsby}' -q -NoFetch repo url 2>&1"
	fAssert    "repo url converts a Gitea remote to ssh" \
		bash -c "cd '${fgRepo}' && '${gitsby}' -q -NoFetch repo url ssh >/dev/null && git -C '${fgRepo}' remote get-url origin | grep -qx 'git@git.example.test:acme/proj.git'"
	fAssert    "and back to https" \
		bash -c "cd '${fgRepo}' && '${gitsby}' -q -NoFetch repo url https >/dev/null && git -C '${fgRepo}' remote get-url origin | grep -qx 'https://git.example.test/acme/proj.git'"

	## The identity block exists to say who the next command acts as. On a host gh does not serve it
	## had no answer at all - it printed nothing rather than saying it could not tell.
	fAssertOut "the identity block names the git host"  'Git host .*git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch identity 2>&1"
	fAssertOut "and who tea holds a login for there"      'giteauser' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch identity 2>&1"
	fAssertNotOut "and prints no GitHub line for it"      'GitHub .gh.' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch identity 2>&1"

	## A token is a credential for the forge that issued it. An account that banks at github.com must
	## not have its token handed to a Gitea push - and the block has to say why, not report a missing
	## token that would have been the wrong one anyway.
	cat > "${fg}/gh-acct.shcl" <<-EOF
		account.work.path      = $(fWinPath "${fgRepo}")
		account.work.ghAccount = ghonly
		account.work.tokenFile = $(fWinPath "${fg}/token")
	EOF
	echo tok_ghonly > "${fg}/token"
	fAssertOut "a github.com account is not applied to a Gitea remote"  'no access token used for git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/gh-acct.shcl' identity 2>&1"
	fAssertOut "and says it is the host that decided that"  'git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/gh-acct.shcl' identity 2>&1"
	## Declaring the host is what makes the same account apply - and the credential helper is then
	## written for THAT host, never for github.com.
	cat > "${fg}/tea-acct.shcl" <<-EOF
		account.work.path      = $(fWinPath "${fgRepo}")
		account.work.host      = git.example.test
		account.work.user      = giteauser
		account.work.tokenFile = $(fWinPath "${fg}/token")
	EOF
	fAssertNotOut "an account that declares the host IS applied"  'Why:' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/tea-acct.shcl' identity 2>&1"

	## An account that never named a host is TAKEN to be a github.com one, which is right for every
	## config written before the key existed - but it is an assumption, not something the file said.
	## Reported in the same words as a host somebody actually typed, it sends them through the config
	## looking for a line that was never there. This account also names no GitHub login, which is the
	## ordinary shape of a Gitea one: reading 'ghAccount' alone reported it as "(no GitHub account
	## named)" - true, and no answer at all to the question the line asks.
	cat > "${fg}/nohost.shcl" <<-EOF
		account.work.path = $(fWinPath "${fgRepo}")
		account.work.user = giteauser
	EOF
	fAssertOut "an unstated host is reported as unstated, not as one the account set"  "doesn't say which git host it is for" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	## Knowing the fix and printing it as homework is a worse answer than doing it. The advice used
	## to spell out a config line to add by hand - and before that, one the parser doesn't even take,
	## so following it exactly left the account no more applied than before. It names the command
	## that makes the edit now, which cannot be mistyped and cannot name a key nothing reads.
	fAssertOut "and names the command that fixes it"  "gitsby account set work host git\.example\.test" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1"
	## Advice to edit a file that never says WHICH file is not advice. The path is on its own line
	## because it is the one thing here long enough to wreck the wrapping.
	fAssertOut "and names the file to make that edit in"  '^File: .*nohost\.shcl$' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1 | sed 's/^ *: *//'"
	## Anchored on the Account line: 'giteauser' is also what the tea stub answers, so an unanchored
	## match is satisfied by the Git host line and passes whether the Account line names anybody or not.
	fAssertOut "and names the account's own login, not the GitHub field it hasn't got"  '^Account .*giteauser' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1"

	## The ssh key and the commit identity are applied outside the credential decision, so a flat
	## "not applied" contradicted the SSH and Author lines printed directly under it - the reader is
	## looking at a key and an author this very account put there. Say which half went in.
	cat > "${fg}/nohost-id.shcl" <<-EOF
		account.work.path  = $(fWinPath "${fgRepo}")
		account.work.user  = giteauser
		account.work.name  = Gitea User
		account.work.email = giteauser@example.test
	EOF
	fAssertOut "an account whose token did not apply still says what did"  'commit identity still applied' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost-id.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	## Which half, though - it named "the SSH and Author lines" whichever half applied, so an account
	## that only set a commit identity sent the reader looking for an SSH line that is not printed
	## anywhere on screen. That reads as a second thing gone wrong.
	fAssertOut "and names only the lines that are actually printed"  'that is where the Author line below comes from' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost-id.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	fAssertNotOut "not an SSH line it never printed"  'SSH and Author lines' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost-id.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	## GIT_AUTHOR_NAME/EMAIL are exported at the top of this file for hermeticity and outrank every
	## config, so the Author line cannot show an account's identity while they are set.
	fAssertOut "and the Author line under it is that account's"  '^Author .*giteauser@example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL '${gitsby}' -q -NoFetch --config '${fg}/nohost-id.shcl' identity 2>&1"

	## A declared Gitea account with no token applies nothing, and said NOTHING about it. The "no
	## token" case was keyed on 'ghAccount' - a field a Gitea account has no reason to set - so
	## exactly the accounts the host key was added for fell through it in silence, which reads as
	## applied. Nor is gh what acts instead on a host gh does not serve.
	cat > "${fg}/notoken.shcl" <<-EOF
		account.work.path = $(fWinPath "${fgRepo}")
		account.work.host = git.example.test
		account.work.user = giteauser
	EOF
	fAssertOut "a Gitea account with no token says it was not applied"  'no access token used for git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/notoken.shcl' identity 2>&1"
	fAssertOut "and names what authenticates instead"  'Git authenticates however it already would' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/notoken.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"
	fAssertNotOut "rather than gh, which does not serve this host"  'gh goes on acting as' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/notoken.shcl' identity 2>&1 | sed 's/^ *: *//' | tr '\\n' ' ' | tr -s ' '"

	## 'account set': knowing the fix and printing it as homework is the worse half of an answer.
	## The whole round trip, because either half alone proves nothing - the command has to write a
	## line the loader then reads back, and the diagnostic has to stop once it has.
	cp "${fg}/nohost.shcl" "${fg}/fixme.shcl"
	## This fixture is in the old flat layout, so the first edit rewrites it whole in the current one
	## - and says so, since the file comes back a different shape from the one that was typed.
	fAssertOut "'account set' says which file it will edit, and how"  'add: +account\[work\]\.host: git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set work host git.example.test 2>&1"
	fAssertOut "and the file now holds that key, in the block"  '^	host: git\.example\.test$' \
		cat "${fg}/fixme.shcl"
	fAssertOut "and the rest came through the change of layout"  '^	user: giteauser$' \
		cat "${fg}/fixme.shcl"
	fAssertOut "and the footer names the format"  'This config file format is SHCL' \
		cat "${fg}/fixme.shcl"
	## The point of the whole exercise: run what the Fix line said and that complaint is gone. Only
	## that one - this account still has no token, which is a different sentence about a different
	## thing, and asserting no complaint at all would be asserting the wrong fix worked.
	fAssertNotOut "and the account stops being read as a github.com one"  "which git host it is for" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' identity 2>&1"
	## Now in the current layout, an edit names the line it changes and both versions of the key.
	fAssertOut "a second edit names the line and what was there"  'was: +host: git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set work host git.example.org 2>&1"
	## A key the loader ignores, written past this command, lands in the file and is dropped on every
	## read - so the file says one thing and every command does another. Refuse it at the door, and
	## name the keys that ARE read while refusing.
	fAssertOut "a key nothing reads is refused, not written"  "isn't an account key gitsby reads" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set work hostname git.example.test 2>&1"
	## 'host' and 'user' are interpolated into the credential helper, which git hands to a shell. The
	## loader drops one carrying a shell character; refusing to WRITE it is what keeps the file and
	## the behavior from disagreeing.
	fAssertOut "and so is a shell character in a host name"  "isn't a plain host name" \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set work host 'git.example.test; id' 2>&1"
	fAssertNotOut "which never reaches the file"  '; id' \
		cat "${fg}/fixme.shcl"
	## 'path' is repeatable by design, and any key at all can be in there twice by accident.
	## Replacing the first and leaving the rest looks like it worked and changes nothing that is read.
	printf 'account.dup.path = /a\naccount.dup.path = /b\n' > "${fg}/dup.shcl"
	fAssertOut "a key present twice is not guessed at"  'Edit it by hand' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/dup.shcl' account set dup path /c 2>&1"
	## Three placeholders are the whole interface. Naming them without saying what they are answers
	## nothing for the one reader who ever sees this - the one who just typed the command wrong.
	fAssertOut "the syntax block says what '<account>' is"  '<account>  A string you define for one login' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set 2>&1"
	## '<key>' is a closed list, and the command that lists it is this one - a reader sent looking
	## for the keys elsewhere guesses instead, and a guess is refused a command later.
	fAssertOut "and lists the keys it takes"  'One of: path, pathcontains, ghaccount, tokenfile' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set 2>&1 | tr '\\n' ' ' | tr -s ' '"
	## The example is two lines on one account name, because that repetition is what '<account>' is.
	fAssertOut "and its example runs as printed"  'gitsby account set work path ~/dev/work' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set 2>&1"
	## 'pathContains' matches a run of folder names, not a glob. An example with a '*' in it reads
	## as a pattern language that isn't there, and the rule it teaches never matches anything.
	fAssertNotOut "and the pathcontains example is not a glob"  '[*]' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/fixme.shcl' account set 2>&1 | grep pathcontains"
	## The identity block's own vocabulary. "Forge" is a word for people who already knew the answer.
	fAssertOut "the identity block says 'Git host', not 'Forge'"  '^Git host \.+: git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/tea-acct.shcl' identity 2>&1"
	## Narrowed to the labeled notes, not narrowed out of meaning: this fixture's own directory is
	## called '<x>-forge', so every path on screen carries the word and a bare grep for it passes
	## whatever the prose says. The check above proves these lines print at all.
	fAssertNotOut "and the word is gone from the block above it"  'forge' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/nohost.shcl' identity 2>&1 | sed 's/^ *: *//' | grep -E '^(From|Why|Kept|Fix):'"

	## 'account list' is the command that always says, so the field that decides whether anything
	## applies has to be in it - stated or assumed.
	fAssertOut "account list names the host an account is on"  'host \.+: git\.example\.test' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/tea-acct.shcl' account list 2>&1"
	## Shown for every account once one of them names a forge, including the ones that never said -
	## that comparison is what answers "why did this one apply and that one not". A config with a
	## single forge in it has nothing to compare and reads exactly as it did before the key existed.
	cat > "${fg}/mixed.shcl" <<-EOF
		account.tea.path = $(fWinPath "${fgRepo}")
		account.tea.host = git.example.test
		account.hub.pathContains = somewhere-else
		account.hub.ghAccount = ghonly
	EOF
	fAssertOut "and marks an unstated one as the assumption it is"  'host \.+: github\.com  .default.' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/mixed.shcl' account list 2>&1"
	fAssertNotOut "but a config with one forge in it is never shown the key"  'host \.+:' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/gh-acct.shcl' account list 2>&1"
	fAssertOut "and prints the host-neutral login beside the GitHub one"  'login \.+: giteauser' \
		bash -c "cd '${fgRepo}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch --config '${fg}/tea-acct.shcl' account list 2>&1"

	## The identity gate, on a host that is not GitHub. Two accounts disagreeing about who you are is
	## the same outward-facing mistake wherever it happens, and keying the check on 'ghAccount' - a
	## GitHub login, which says nothing about who you are anywhere else - left it silently uncovered.
	## The ssh stub answers with GITEA's greeting, not GitHub's: close enough to look handled by the
	## existing pattern and different enough not to be.
	fStub "${fg}/bin/ssh" <<'SSHEOF'
#!/usr/bin/env bash
mode=""
for a in "$@"; do case "$a" in -G) mode=G ;; -T) mode=T ;; esac; done
if [[ "${mode}" == "G" ]]; then
	printf 'user git
hostname %s
identityfile /etc/hostname
' "${FAKE_SSH_HOSTNAME:-git.example.test}"
	exit 0
fi
if [[ "${mode}" == "T" ]]; then
	echo "Hi there, ${FAKE_SSH_LOGIN:-keyowner}! You've successfully authenticated with the key named k, but Gitea does not provide shell access."
	exit 1
fi
exit 0
SSHEOF
	local fgSsh="${fg}/sshproj"
	git init --quiet -b main "${fgSsh}"
	(
		cd "${fgSsh}" || exit 1
		echo a > a.txt && git add --all && git commit --quiet -m init
		git remote add origin git@git.example.test:acme/proj.git
	)
	## Parsing Gitea's greeting is what makes every check below able to say anything at all.
	fAssertOut "the ssh line names the account a Gitea key authenticates as"  'SSH \.+: keyowner' \
		bash -c "cd '${fgSsh}' && PATH='${fgPath}' '${gitsby}' -q -NoFetch status 2>&1"

	local fgCanon="${fgSsh}"; ((isWindows)) && fgCanon="$( cd "${fgSsh}" && pwd -W )"
	cat > "${fg}/mine.shcl" <<-EOF
		account.mine.path = ${fgCanon}
		account.mine.host = git.example.test
		account.mine.user = gitfriend
	EOF
	cat > "${fg}/theirs.shcl" <<-EOF
		account.mine.path = ${fgCanon}
		account.mine.host = git.example.test
		account.mine.user = keyowner
	EOF
	local fgSync="cd '${fgSsh}' && PATH='${fgPath}' GITSBY_CONFIG="
	fAssertFail   "sync refuses when a Gitea folder's account is not the key's" \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --config '${fg}/mine.shcl' sync 'W'"
	fAssertOut    "and the refusal names both"  "account is 'gitfriend'.*authenticates as 'keyowner'" \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --config '${fg}/mine.shcl' sync 'W' 2>&1 || true"
	fAssertNotOut "--any-identity says the difference is intended"  'authenticates as' \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --any-identity --config '${fg}/mine.shcl' sync 'W' 2>&1 || true"
	fAssertNotOut "and a matching account does not fire"  'authenticates as' \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --config '${fg}/theirs.shcl' sync 'W' 2>&1 || true"
	## An account whose only login is a GitHub one has made no claim about this host, so there is
	## nothing to compare - it must not be read as a match either.
	cat > "${fg}/ghonly.shcl" <<-EOF
		account.mine.path      = ${fgCanon}
		account.mine.ghAccount = alice
	EOF
	fAssertNotOut "a GitHub-only account makes no claim about a Gitea remote"  'authenticates as' \
		bash -c "${fgSync} '${gitsby}' -q -NoFetch --config '${fg}/ghonly.shcl' sync 'W' 2>&1 || true"

	## The other half: a write THROUGH tea, acting as tea's login while git pushes as the key. Same
	## mistake as the gh version of this, and it was reachable only because a tea write now counts
	## as a write at all.
	( cd "${fgSsh}" && git checkout --quiet -b fgfeat && echo w > w.txt && git add --all && git commit --quiet -m "work" )
	fAssertFail "pr create refuses when tea's login is not the key's" \
		bash -c "cd '${fgSsh}' && PATH='${fgPath}' FAKE_TEA_USER=gitfriend FAKE_SSH_LOGIN=keyowner '${gitsby}' -q -NoFetch pr create 'T'"
	fAssertOut  "and the refusal names tea rather than gh"  "tea acts as 'gitfriend'" \
		bash -c "cd '${fgSsh}' && PATH='${fgPath}' FAKE_TEA_USER=gitfriend FAKE_SSH_LOGIN=keyowner '${gitsby}' -q -NoFetch pr create 'T' 2>&1"
	fAssertNotOut "and agreeing logins do not fire"  'acts as' \
		bash -c "cd '${fgSsh}' && PATH='${fgPath}' FAKE_TEA_USER=keyowner FAKE_SSH_LOGIN=keyowner '${gitsby}' -q -NoFetch pr create 'T' 2>&1 || true"
	( cd "${fgSsh}" && git checkout --quiet main )

	## An unparseable remote is not a forge we ruled out - it is one we could not name. The standing
	## rule is that such a remote never triggers a refusal, so gh keeps the last word exactly as before.
	git init --quiet -b main "${fg}/localorigin"
	( cd "${fg}/localorigin" && echo a > a.txt && git add --all && git commit --quiet -m init && git remote add origin "${fg}/bare.git" )
	git init --quiet --bare -b main "${fg}/bare.git"
	: > "${fg}/local-gh.log"
	fAssert "a local-path remote still falls through to gh, as it always did" \
		bash -c "cd '${fg}/localorigin' && PATH='${fgPath}' FAKE_GH_LOG='${fg}/local-gh.log' '${gitsby}' -q -NoFetch pr && grep -q '^pr list' '${fg}/local-gh.log'"

	if ((hasPty)); then
		## Only 'y' was a yes, so the word people actually type aborted.
		( cd "${renDir}" && echo yes >> yesword.txt )
		fAnswerPrompt yes "cd '${renDir}' && '${gitsby}' pullcom 'typed yes'" >/dev/null
		fAssert    "'yes' at the prompt is taken as a yes" \
			bash -c "cd '${renDir}' && git log -1 --pretty=%s | grep -qx 'typed yes'"
		## clone took only a full URL, and said so after the plan was confirmed rather than before.
		fAssertOut "'repo clone owner/name' plans a github URL"  'git clone .*github\.com[:/]octo/demo' \
			fAnswerPrompt n "cd '${work}' && '${gitsby}' repo clone octo/demo"
	fi
}

echo "gitsby regression tests (fixture: ${work})"

## One implementation, and it gates. The shim keeps ${gitsby} a plain single path so the
## 'bash -c' interpolation throughout the suite stays as it is.
goBin="${root}/src-go/gitsby"; [[ -x "${goBin}" ]] || goBin="${goBin}.exe"
[[ -x "${goBin}" ]] || { echo "no build at src-go/gitsby - run 'go build' there, or cicd.bash stage 2" >&2; exit 1; }
gitsby="${work}/gitsby-go"
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "${goBin}" > "${gitsby}"
chmod +x "${gitsby}"
fMakeFixture "${work}/go"
fRunSuite "go"

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
##		- 20260808 JC: Folder-account coverage: a faked HOME, a stub gh holding a token for one of two accounts, and two directory trees. The rules are written in the spelling a user of the running platform would type - '/tmp' is an entry in the Bash build's own mount table and means nothing to the PowerShell one, so a rule spelled that way matches on one leg only and reads as a port bug.
##		- 20260808 JC: The two identity checks run with GIT_AUTHOR_NAME/EMAIL unset. This file exports them for hermeticity, and they outrank every config, so with them in place neither check could see the thing it asks about.
##		- 20260808 JC: Coverage for 'repo url', 'account list|apply', the 'raw' passthrough, and the config-file argument in both builds. The joined '--config=FILE' spelling splits the two, so each leg is pinned to what it actually does.
##		- 20260810 JC: Refusals that only checked the exit code now check the reason too: a build predating these commands also exits 1, so nonzero alone proved nothing. One "check" turned out to run only git and could not fail; it asserts something now.
##		- 20260813 JC: How release.bash reads changelog.md, pinned in the source - proving it for real would mean cutting a release. Three of the four discriminate against the prior code; "the real vNEXT section is still findable" is a regression guard, since that section was always there. Bash leg only: neither file belongs to an implementation.
##		- 20260812 JC: Paths handed to PowerShell go in the platform's spelling, via fWinPath. An MSYS path means nothing to .NET, which reads it against the current drive root, so Set-Location, the script lookup and ReadAllBytes all failed and twelve checks on Windows reported on a fixture nothing had touched - seven red, five green because the thing they forbid also never happened. Also: a unix-absolute argument is rewritten by Git Bash before the native pwsh sees it, and the system install location is the platform's own.
##		- 20260813 JC: Recursive removal. demo-repo.bash is the only script here that removes a path someone else named, so it gets real checks; the rest are pinned to removing only what mktemp handed them. Sixteen of the seventeen discriminate against the prior code; the last is a regression guard on a file that never removed anything. The filesystem-root case is pinned rather than run, because running it against a build without the guard is 'rm -rf /'.
##		- 20260813 JC: Drop the two settings a working terminal carries that outrank everything pinned here - GIT_CONFIG_COUNT with its numbered keys, which beats every config file including a repo-local one, and an inherited GH_TOKEN, which is what the fake gh reports back. Twenty checks had been reporting on the terminal rather than the code. Pinned in all three harnesses; the runtime pair is a regression guard, since a clean machine passes either way.
##		- 20260814 JC: release.bash gates on the pipeline engine belonging to the platform. It always ran the Bash one, which knows nothing about Windows, so the check a release most depends on would have been the wrong pipeline there. Source pins, same reason as the changelog ones above; both discriminate against the prior file.
##		- 20260817 JC: Go leg. Same shim treatment, non-gating: the port is written against this suite, so its failures are the distance left, printed as counts and kept out of the totals. The leg runs without -e - prep commands legitimately die where a command is not ported yet, and the assertions do the judging.
##		- 20260818 JC: The renamed commands, their aliases, and identity - checked on the compiled leg only, since the scripts are frozen at the spelling they shipped with. The offline-sync check now takes either name; it is the one message that had pinned the old one.
##		- 20260818 JC: One leg. The scripted builds moved to legacy/ and their legs went with them, so the compiled build is the subject and it gates. The checks that were never about an implementation - installers, the frozen platform gates, the source pins - stayed, repointed at legacy/; dropping them with the leg they happened to ride would have lost 58 of them silently. The PowerShell-only block went with pwsh, and the per-implementation option spellings collapsed to one.
##		- 20260819 JC: The paper-cut sweep, and a pty for the two checks that have to answer the prompt rather than have it refuse - the plan is only printed to someone who could say yes, and one of them is about the word accepted there. Fourteen checks, all of which discriminate against the prior build; skipped where there is no 'script'.
##		- 20260819 JC: Which folder a clone resolves its account from. The account block grew a bare origin to clone between its two trees, and the identity block one check that the surrounding repo's owner is never asked about - the step that leaves no trace in the output, only in which token the fetch went out with.
##		- 20260819 JC: The shipping installers, at the repo root. Their whole plan is behind the network now - the release lookup and SHA256SUMS both land before it prints - so these checks stop at the argument parse, the refusals, the Windows hand-off, and pins on what a live run reaches. The legacy block stays beside them, still aimed at frozen files. 582 -> 613.
##		- 20260819 JC: A block for the directive-review defects: the bare-repo and .git-directory gates, the fetch naming origin, prune's offline hold-back, br switch with two remotes carrying the branch, the contested-folder tie-break both ways, --any-identity's own line, a file-sourced token checked against the account it claims, and the mode bits. Eighteen of them fail against the build that preceded the fixes; the two mode-bit ones are Linux/macOS only.
##		- 20260826 JC: The accounts file in its block layout: read in every shape, edited in place with the comments kept, created with its header and footer, and a flat file rewritten by its first edit. The old flat fixtures stay as regression guards on the reader that still takes them. 793 -> 808.
##		- 20260819 JC: Installer coverage for the directive-review fixes: the pre-release fallback (a stub curl answering only the list endpoint), a whole install end to end with the network stood in for, and pins on the staging, the verification exit code and the Windows PowerShell 5.1 support. Ten of them fail against the installers that preceded the fixes.
##		- 20260819 JC: Pipeline coverage for the directive review: the reproducible-build flags and a binary built with them, the core cap, --quick's cross-builds, govulncheck, the spawn-count and kept-build scripts, -q reaching the harnesses, the lint summary on a clean log, and the demo scenario's command names. Eleven fail against the pipeline that preceded them.
##		- 20260819 JC: br prune's plan checks follow the batched deletes - one line for the locals and one for the remotes, which is what the command runs. The remote half needed a fixture of its own: a plan check has to run the command to see a plan, and the check before it had already pruned the world it shared.
##		- 20260819 JC: The second adversarial pass. A folder rule spelled through a symlink, checked both by the account line and by which entry 'account list' marks; the shipped-code warning run from a subdirectory, where the pathspec had been reading from the wrong place; and a repo-local commit name or email on its own, each of which the account had been overriding. Five checks, all five failing against the build before them.
##		- 20260819 JC: A config file's discovery inputs are now neutralized in one place. Faking HOME never covered XDG_CONFIG_HOME (tried first) or APPDATA (tried last), so every block that tests discovery read the accounts of whoever was running the suite - thirty checks went red the day this machine had a config of its own. Plus four checks for the two defects found with it: an account named through GITSBY_ACCOUNT that carries no GitHub login, and a config file with a byte-order mark on it.
