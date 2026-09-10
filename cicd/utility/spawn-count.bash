#!/usr/bin/env bash

##	Purpose:
##		- Counts the processes gitsby spawns per command, and fails when a count grows.
##		- This is the profiling step, and it is deliberately not a sampling profiler: the
##		  program spends its whole life blocked waiting on git, so a flamegraph is a flat
##		  wall of Execve and Wait with no self-time in it and no leaders. What costs
##		  anything here is how many times we fork git, so that is what gets measured.
##		- Each command runs against a pristine throwaway repo with its own bare origin.
##		  The work tree AND the origin are restored between runs: prune deletes branches
##		  on both sides, and leaving either behind makes the next command's count a
##		  different question.
##		- Baseline is the newest previous run in the artifact dir, GFS-rotated like the
##		  lint logs. No baseline yet means the first run records one and passes.
##	Syntax:
##		cicd/utility/spawn-count.bash [-q|--quiet] [--record]
##		  --record   Write the counts even when they regressed (accept a deliberate rise).
##	Requires:
##		- strace. Linux only; the step self-skips anywhere else, which is the same
##		  treatment every other probe-gated tool gets.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"; root="$(cd "${root}/.." && pwd)"
# shellcheck source=/dev/null
source "${root}/cicd/config.bash"
# shellcheck source=/dev/null
source "${here}/include/gfs-rotate.bash"

declare -i quiet=0 record=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		-q|--quiet) quiet=1; shift ;;
		--record)   record=1; shift ;;
		-h|--help)  sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
		*)          echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
done

fEcho_Clean(){ echo "$*"; }

command -v strace >/dev/null 2>&1 || { echo "  spawn counts skipped (no strace)"; exit 0; }
exe="${root}/${GO_MODULE_DIR}/${EXE_NAME}"
[[ -x "${exe}" ]] || { echo "no build at ${GO_MODULE_DIR}/${EXE_NAME} - run cicd.bash stage 2, or 'go build' there" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-spawn.XXXXXX")"
trap 'rm -rf -- "${work:?}"' EXIT

## Hermetic, for the same reasons the suites are: an inherited config decides which account a
## command acts as, and that changes how many processes it starts.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=spawn GIT_AUTHOR_EMAIL=spawn@test
export GIT_COMMITTER_NAME=spawn GIT_COMMITTER_EMAIL=spawn@test
export GITSBY_CONFIG="${work}/no-accounts.shcl"; : > "${GITSBY_CONFIG}"
for ((i = 0; i < ${GIT_CONFIG_COUNT:-0}; i++)); do unset "GIT_CONFIG_KEY_${i}" "GIT_CONFIG_VALUE_${i}"; done
unset GIT_CONFIG_COUNT
unset GH_TOKEN GITHUB_TOKEN GITSBY_ACCOUNT

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The world: a bare origin and a clone, with a merged branch and an unmerged one, so prune
## has something to survey and merge has something to leave alone.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
pristine="${work}/pristine"
mkdir -p "${pristine}"
git init --quiet --bare -b main "${pristine}/origin.git"
git clone --quiet "${pristine}/origin.git" "${pristine}/repo" 2>/dev/null
(
	cd "${pristine}/repo"
	echo one > file.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
	git checkout --quiet -b dev && git push --quiet -u origin dev
	git checkout --quiet -b landed && echo two >> file.txt && git add --all && git commit --quiet -m landed
	git push --quiet -u origin landed
	git checkout --quiet dev && git merge --quiet --no-ff landed -m merge && git push --quiet
	git checkout --quiet -b open-work && echo three >> file.txt && git add --all && git commit --quiet -m wip
	git push --quiet -u origin open-work
	git checkout --quiet dev
)

fRestore(){
	rm -rf -- "${work:?}/live"
	mkdir -p "${work}/live"
	cp -a "${pristine}/origin.git" "${work}/live/origin.git"
	cp -a "${pristine}/repo" "${work}/live/repo"
}

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The measurement. -f follows the children, so a git that forks its own helper is counted
## where it happens; execve is the event that costs, since that is a new program image.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
declare -a labels=() counts=()
fMeasure(){
	local label="$1"; shift
	fRestore
	local traceFile="${work}/trace.out"
	## --no-fetch throughout: a fetch against a local bare origin is a real round trip whose
	## cost belongs to git rather than to us, and it varies with what the last command left.
	( cd "${work}/live/repo" && strace -f -e trace=execve -o "${traceFile}" "${exe}" "$@" ) >/dev/null 2>&1 || true
	local n=0
	n="$(grep -c 'execve(' "${traceFile}" 2>/dev/null || true)"
	labels+=("${label}")
	counts+=("${n}")
	((quiet)) || fEcho_Clean "  ${n}	${label}"
}

((quiet)) || fEcho_Clean "spawn counts (${exe})"
fMeasure "status"         -q --no-fetch status
fMeasure "whoami"         -q --no-fetch whoami
fMeasure "br list"        -q --no-fetch br list
fMeasure "account list"   -q --no-fetch account list
fMeasure "repo url"       -q --no-fetch repo url
fMeasure "pullcom"        -q --no-fetch pullcom "spawn count"
fMeasure "br switch"      -q --no-fetch br switch main
fMeasure "br prune"       -q --no-fetch br prune

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Compare with the newest previous run, then record this one.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
countDir="${root}/${SPAWN_COUNT_DIR}"
mkdir -p "${countDir}"
baseline=""
for f in "${countDir}"/spawn_*.tsv; do [[ -f "${f}" ]] && baseline="${f}"; done

declare -i regressed=0
if [[ -z "${baseline}" ]]; then
	((quiet)) || fEcho_Clean "  (no baseline yet - recording this run as one)"
else
	((quiet)) || fEcho_Clean "  baseline: $(basename "${baseline}")"
	for ((i = 0; i < ${#labels[@]}; i++)); do
		was="$(awk -F'\t' -v k="${labels[i]}" '$1==k{print $2}' "${baseline}" || true)"
		[[ -n "${was}" ]] || { ((quiet)) || fEcho_Clean "  NEW    ${labels[i]} (${counts[i]})"; continue; }
		## A tolerance, because a git version can add or drop a helper of its own: two more
		## processes, or a tenth again, whichever is larger.
		local_allow=$(( was / 10 )); (( local_allow < 2 )) && local_allow=2
		if (( counts[i] > was + local_allow )); then
			fEcho_Clean "  REGRESSED  ${labels[i]}: ${was} -> ${counts[i]}"
			regressed=1
		elif (( counts[i] < was )); then
			((quiet)) || fEcho_Clean "  improved   ${labels[i]}: ${was} -> ${counts[i]}"
		fi
	done
fi

if ((regressed)) && ((! record)); then
	echo "spawn counts regressed against $(basename "${baseline}"); nothing recorded." >&2
	echo "  Re-run with --record to accept the new counts as the baseline." >&2
	exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
out="${countDir}/spawn_${stamp}.tsv"
: > "${out}"
for ((i = 0; i < ${#labels[@]}; i++)); do printf '%s\t%s\n' "${labels[i]}" "${counts[i]}" >> "${out}"; done
gfs_rotate "${countDir}" spawn tsv >/dev/null 2>&1 || true
((quiet)) || fEcho_Clean "  recorded $(basename "${out}")"


##	History:
##		- 20260819 JC: Created. The profiling step, as spawn counting rather than as a sampling
##		  profile: this program is blocked on git for effectively all of its wall clock, so a
##		  flamegraph has no leaders in it. Each command is measured against a restored fixture,
##		  origin included - prune deletes on both sides, and a leftover makes the next count a
##		  different question.
