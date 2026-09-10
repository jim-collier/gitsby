#!/usr/bin/env bash

##	Purpose:
##		- Backwards compatibility. Compares this build against the frozen v2.1.0
##		  script under legacy/, rather than each against a spec. cicd/test.bash
##		  asks "does this behave correctly?" of one build; this asks "does the new
##		  one ANSWER as the shipped one did?" for the same input.
##		- Aimed at the defect class the behavioral suite is blind to by
##		  construction: every port bug that has reached users here was a language
##		  mechanism differing - file encoding, argument parsing, return types,
##		  path resolution, string case - not a rule either build got wrong on
##		  purpose. A check written per implementation passes on both while they
##		  quietly disagree about the same input.
##		- Exits nonzero on any disagreement, so cicd aborts.
##	Syntax:
##		cicd/parity.bash
##	Notes:
##		- The reference is legacy/bin/gitsby, the Bash build. The PowerShell one is
##		  not a third leg: the two scripts were proven identical to each other at
##		  v2.1.0, so agreeing with one is agreeing with both, and a pwsh leg would
##		  only add an interpreter this has to find.
##		- Skips itself once legacy/ is gone: there is then nothing to compare to,
##		  and that is the intended end state, not a failure.
##		- Output is normalized only for the program's own name and for the absolute
##		  path of whichever build produced a line. Commands the new build renamed on
##		  purpose are compared under BOTH spellings, since the old one still has to
##		  work - anything else that differs is a finding.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-parity.XXXXXX")"
trap 'rm -rf -- "${work:?}"' EXIT
## The same directory in the spelling native Windows understands. A folder rule has to be written
## in a spelling BOTH builds can resolve, and an MSYS mount path such as '/tmp/...' is not one:
## only this shell knows its own mount table, and the PowerShell build must not need Git Bash to
## exist. 'account' marks a rule that resolves to no directory, which is what makes that visible
## rather than silent.
workNative="${work}"
command -v cygpath >/dev/null 2>&1 && workNative="$(cygpath -m "${work}")"
workBack="${workNative//\//\\}"

## Same hermeticity as the behavioral suite, and for the same reasons.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
export GITSBY_CONFIG="${work}/no-accounts.shcl"; : > "${GITSBY_CONFIG}"

## Pinning the config FILES is not isolation on its own: GIT_CONFIG_COUNT/KEY_n/VALUE_n outrank
## every one of them, and an inherited GH_TOKEN is what a gh call reports back. Both arrive from
## an ordinary working terminal, and neither shows up as a failure you can act on.
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
fBad(){  fail=$((fail+1)); echo "  DIFFER: $*"; }

## The subject and the reference. 'new' is whatever cicd stage 2 just built; 'ref' is the
## frozen script, read-only and never rebuilt.
newBuild="${root}/src-go/gitsby"; [[ -x "${newBuild}" ]] || newBuild="${newBuild}.exe"
refBuild="${root}/legacy/bin/gitsby"

if [[ ! -x "${newBuild}" ]]; then
	echo "parity: no build at src-go/gitsby - nothing to compare, skipping."
	exit 0
fi
if [[ ! -f "${refBuild}" ]]; then
	echo "parity: no frozen build at legacy/bin/gitsby - nothing to compare against, skipping."
	exit 0
fi

fNormalize(){
	## Only the two things the builds are ENTITLED to differ on: the program's own name, and the
	## absolute path of whichever build produced the line. Everything else is left alone, because
	## everything else differing is the point of this file.
	## Every spelling of the work directory folds to one token: the two shells legitimately echo a
	## path the way their own runtime spells it, and that is not a parity finding.
	sed -e 's/gitsby\.ps1/gitsby/g' -e "s|${root}|<root>|g" \
		-e "s|${workBack}|<work>|gI" -e "s|${workNative}|<work>|gI" -e "s|${work}|<work>|g"
}

fRunNew(){ local -r d="${1}"; shift; ( cd "${d}" || exit 1; "${newBuild}" "${@}" 2>&1 || true ) | fNormalize ;}
fRunRef(){ local -r d="${1}"; shift; ( cd "${d}" || exit 1; bash "${refBuild}" "${@}" 2>&1 || true ) | fNormalize ;}

fSame(){
	## One input, both builds, byte-identical answers after normalization.
	local -r label="${1}"; local -r dir="${2}"; shift 2
	local a="" b=""
	a="$(fRunNew "${dir}" "${@}")"
	b="$(fRunRef "${dir}" "${@}")"
	if [[ "${a}" == "${b}" ]]; then
		fOk "${label}"
	else
		fBad "${label}"
		diff <(printf '%s\n' "${a}") <(printf '%s\n' "${b}") | sed 's/^/      /' | head -12 || true
	fi
}

## Same as fSame, with one deliberate difference removed from both sides first. Used where this
## build says something the frozen one never did and the rest of the line still has to match; the
## removal is spelled out at the call site so it cannot quietly widen.
fSameStripped(){
	local -r label="${1}"; local -r drop="${2}"; local -r dir="${3}"; shift 3
	local a="" b=""
	a="$(fRunNew "${dir}" "${@}" | sed -E "${drop}")"
	b="$(fRunRef "${dir}" "${@}" | sed -E "${drop}")"
	if [[ "${a}" == "${b}" ]]; then
		fOk "${label}"
	else
		fBad "${label}"
		diff <(printf '%s\n' "${a}") <(printf '%s\n' "${b}") | sed 's/^/      /' | head -12 || true
	fi
}

fSameField(){
	## One labeled line out of each build's output, compared. Used where the surrounding block
	## legitimately differs: each runtime echoes a path the way it spells one, and 'C:\x' against
	## '/c/x' is not a finding - what the two must agree on is what they RESOLVED from it.
	local -r label="${1}"; local -r pattern="${2}"; local -r dir="${3}"; shift 3
	local a="" b=""
	a="$(fRunNew "${dir}" "${@}" | grep -E "${pattern}" || true)"
	b="$(fRunRef "${dir}" "${@}" | grep -E "${pattern}" || true)"
	if [[ "${a}" == "${b}" ]]; then
		fOk "${label}"
	else
		fBad "${label}"
		printf '      this build: %s\n      frozen:     %s\n' "${a:-(no such line)}" "${b:-(no such line)}"
	fi
}

fSameLead(){
	## The labeled line with its trailing explanation cut off, compared. Used where what the two
	## builds must agree on is the value the line reports and not the prose after it: the frozen
	## script says where an account came from and why it could not be applied in one long clause on
	## the line, this build says both underneath, and which reads better is not what these ask.
	local -r label="${1}"; local -r pattern="${2}"; local -r dir="${3}"; shift 3
	local a="" b=""
	a="$(fRunNew "${dir}" "${@}" | grep -E "${pattern}" | sed -e 's/ - .*//' -e 's/ (from .*//' || true)"
	b="$(fRunRef "${dir}" "${@}" | grep -E "${pattern}" | sed -e 's/ - .*//' -e 's/ (from .*//' || true)"
	if [[ "${a}" == "${b}" ]]; then
		fOk "${label}"
	else
		fBad "${label}"
		printf '      this build: %s\n      frozen:     %s\n' "${a:-(no such line)}" "${b:-(no such line)}"
	fi
}

fSameExit(){
	## Same accept/reject verdict. Used where the two legitimately word a message differently but
	## must agree on whether the input is valid at all.
	local -r label="${1}"; local -r dir="${2}"; shift 2
	local -i ra=0 rb=0
	( cd "${dir}" && "${newBuild}" "${@}" >/dev/null 2>&1 ) || ra=$?
	( cd "${dir}" && bash "${refBuild}" "${@}" >/dev/null 2>&1 ) || rb=$?
	## Only the verdict, not the code: the two runtimes number their own failures differently.
	if [[ $((ra == 0)) -eq $((rb == 0)) ]]; then fOk "${label}"; else fBad "${label} (this build exit ${ra}, frozen exit ${rb})"; fi
}

echo
echo "[ gitsby parity: this build vs the frozen v2.1.0 script ]"
echo

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Path spelling. The folder rule is the feature most exposed to path handling, and this is where
## the scripted builds diverged for real: one resolved a spelling through the filesystem and the
## other did not, so the same rule matched in one and not the other. Silently, which is the worst
## kind. Go resolves paths its own third way, so the question is live again.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo "-- folder rules, however the path is spelled"
tree="${work}/tree"
mkdir -p "${tree}"
git init --quiet -b main "${tree}"
( cd "${tree}" && echo a > a.txt && git add --all && git commit --quiet -m init )

declare -a spellings=("${workNative}/tree")
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
	winPath="$( cd "${tree}" && pwd -W )"
	spellings+=("${winPath}")
	spellings+=("${winPath//\//\\}")
	spellings+=("${winPath,,}")
fi
for spelling in "${spellings[@]}"; do
	cat > "${work}/spell.shcl" <<-EOF
		account.s.path      = ${spelling}
		account.s.ghAccount = spellacct
	EOF
	fSameLead  "path spelled '${spelling}' resolves the same" '^Account' "${tree}" -q -NoFetch --config "${work}/spell.shcl" status
done

## 'pathContains' names folder names rather than a machine's tree, so it is the one rule meant to
## be identical everywhere - which makes any divergence between the builds worth more here, not less.
echo
echo "-- pathContains rules"
mkdir -p "${work}/mA/github.com/alice/proj" "${work}/mB/github.com/alice/proj" "${work}/mA/github.com/alice-old/proj"
for d in "${work}/mA/github.com/alice/proj" "${work}/mB/github.com/alice/proj" "${work}/mA/github.com/alice-old/proj"; do
	git init --quiet -b main "${d}"
done
cat > "${work}/seg.shcl" <<-EOF
	account.seg.pathContains = github.com/alice
	account.seg.ghAccount    = segacct
EOF
fSameLead  "pathContains resolves the same under root A" '^Account' "${work}/mA/github.com/alice/proj" -q -NoFetch --config "${work}/seg.shcl" status
fSameLead  "pathContains resolves the same under root B" '^Account' "${work}/mB/github.com/alice/proj" -q -NoFetch --config "${work}/seg.shcl" status
fSameLead  "and both agree it is whole folder names"     '^Account' "${work}/mA/github.com/alice-old/proj" -q -NoFetch --config "${work}/seg.shcl" status

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Option binding. Every build parses its own arguments, and that is where the scripted pair
## produced three separate defects: options claimed out of a passthrough, a joined '-Config=FILE'
## binding nothing, and a bare '--' killing the process before any code ran. The Go build parses
## by hand for exactly this reason, which is worth proving rather than assuming.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
echo "-- option forms"
fSame     "an unknown option is refused the same way"     "${tree}" -q --bogus status
fSame     "an option after the command is refused alike"  "${tree}" -q status --bogus
## Both refuse, and that is the whole claim here. The frozen script counted them - "5, for max of
## 4" - because four was all its tokenizer took; this build takes five, for 'account set <account>
## <key> <value>' alone, and every other command rejects the extra a step later, by name. Naming
## the word is the better answer of the two, and test.bash owns that wording.
fSameExit "too many positionals are refused by both"      "${tree}" -q br switch a b c
fSameExit "a spaced --config is accepted by both"         "${tree}" -q -NoFetch --config "${work}/no-accounts.shcl" status
fSameExit "an empty --config is refused by both"          "${tree}" -q -NoFetch --config "" status
fSameExit "a --config naming a directory is refused"      "${tree}" -q -NoFetch --config "${work}" status
fSameExit "a --config naming nothing there is refused"    "${tree}" -q -NoFetch --config "${work}/nope.shcl" status
fSameExit "-q and -y together are accepted by both"       "${tree}" -q -y -NoFetch status
fSameExit "-NoFetch before 'raw' is taken by both"        "${tree}" -q -NoFetch raw git rev-parse HEAD
fSameExit "a bad 'raw' tool is refused by both"           "${tree}" -q raw curl x

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Renamed commands. 'update' became 'pullcom' and 'br land' became 'br merge', and both old
## spellings are permanent aliases - so the rename must have moved the name and nothing else.
## Run outside a repository, where both builds refuse for a reason that has nothing to do with
## the rename: what is being compared is that the old name still ROUTES, and to the same place.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
echo "-- renamed commands, old spellings"
notRepo="${work}/not-a-repo"; mkdir -p "${notRepo}"

## Against the frozen build, which knows only the old names.
fSame "'update' answers as it always did"      "${notRepo}" -q -NoFetch update
fSame "'br land' answers as it always did"     "${notRepo}" -q -NoFetch br land

## Against itself, since the frozen build never heard the new names. Two spellings of one
## command have to be one command, not merely two that are both accepted.
fSameSpelling(){
	local -r label="${1}"; local -r dir="${2}"; local -r old="${3}"; local -r new="${4}"; shift 4
	local a="" b=""
	# shellcheck disable=SC2086  ## deliberate word-split: these carry multi-word commands ('br land').
	a="$(fRunNew "${dir}" -q -NoFetch ${old})"
	# shellcheck disable=SC2086
	b="$(fRunNew "${dir}" -q -NoFetch ${new})"
	if [[ "${a}" == "${b}" ]]; then
		fOk "${label}"
	else
		fBad "${label}"
		diff <(printf '%s\n' "${a}") <(printf '%s\n' "${b}") | sed 's/^/      /' | head -12 || true
	fi
}
fSameSpelling "'pullcom' and 'update' are one command"   "${notRepo}" "update"   "pullcom"
fSameSpelling "'br merge' and 'br land' are one command" "${notRepo}" "br land"  "br merge"

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## String case. Bash folds with '${x,,}'; Go compares byte-exact unless told otherwise. The two
## drift apart wherever one is applied and the other is assumed.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
echo "-- string case"
cat > "${work}/case.shcl" <<-EOF
	account.mixed.path      = ${spellings[0]}
	account.mixed.ghAccount = caseacct
EOF
for name in mixed MIXED MiXeD; do
	## Exported around the call, not named only in the label: both builds have to SEE it. Written
	## the other way this loop ran three identical commands and compared them to each other, which
	## passes whatever either build does with the variable.
	export GITSBY_ACCOUNT="${name}"
	fSameLead  "GITSBY_ACCOUNT='${name}' resolves the same" '^Account' "${tree}" -q -NoFetch --config "${work}/case.shcl" status
	unset GITSBY_ACCOUNT
done

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## File encoding. A BOM is invisible in an editor and in 'Get-Content', and has broken both the
## documented one-liner installs and direct execution of the script. Bytes, not text.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
echo "-- file encoding"
for f in "${root}"/legacy/bin/gitsby "${root}"/legacy/bin/gitsby.ps1 "${root}"/legacy/install*.bash "${root}"/legacy/install*.ps1; do
	[[ -f "${f}" ]] || continue
	if [[ "$(head -c 2 "${f}")" == "#!" ]]; then
		fOk "${f##*/} starts with a shebang, not a BOM"
	else
		fBad "${f##*/} does not start with '#!' - a BOM ahead of it breaks 'irm | iex' and direct execution"
	fi
done

echo
echo "parity passed: ${pass}, differed: ${fail}"
((fail == 0)) || exit 1

##	History:
##		- 20260812 JC: Created. Compares the two builds against each other rather than each against
##		  a spec, for the defect class the behavioral suite cannot see: every port bug that reached
##		  users was a language mechanism differing, not a rule either build got wrong.
##		- 20260813 JC: Same environment isolation the behavioral suite grew: env-injected git config and an inherited gh token.
##		- 20260818 JC: Repointed. The pair used to be the two scripts; it is now this build against the frozen v2.1.0 one under legacy/, which is the question that still has an answer worth having. No pwsh leg: the two scripts were proven identical at v2.1.0, so agreeing with one is agreeing with both. The renamed commands are checked under both spellings, since the old name has to keep working.
##		- 20260819 JC: A difference used to end the run. diff exits 1, and under pipefail with -e that killed the script at the FIRST finding, so every later one went unreported - the totals line never printed either. Also a helper for comparing a line with one deliberate difference removed, spelled out per call so it cannot quietly widen.
