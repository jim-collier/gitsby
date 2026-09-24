#!/usr/bin/env bash

##	Purpose:
##		The git pre-push hook for this repo, and its installer.
##		- --install writes a small hook into the repo's hooks directory that runs this
##		  script on every push. It never sets core.hooksPath, and never replaces a hook
##		  it did not write.
##		- As the hook, a commit pushed to main gets cicd/cicd.bash --gate, run in a detached
##		  worktree at <git common dir>/gitsby-gate. The commit is checked as committed, never
##		  the working tree. A failure refuses the whole push.
##		- Other branches, deletes and tags are not gated. A commit whose cicd.bash has no
##		  --gate, and a box other than Linux, push with a note.
##	Syntax:
##		pre-push.bash --install
##		pre-push.bash <remote-name> <remote-url>   (as the hook: git's ref lines on stdin)
##	Exit: --install: 0 installed or already current, 1 refused, 2 usage.
##	      As the hook: 0 the push may go ahead, 1 refused.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

meDir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "${meDir}/../.." && pwd)"

## git hands a hook the checkout it is pushing from: GIT_DIR from a linked worktree or a
## --git-dir push, GIT_WORK_TREE beside it, GIT_PREFIX from a subdirectory. Left in place, a
## git command aimed at the gate worktree acts on that checkout instead - it detaches its HEAD
## and writes its index - and the unit tests' throwaway repos resolve to the real one. Every
## git call here names its directory, and the gate should see what a hand run sees.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX

## Unindented on purpose: a <<- heredoc would strip the tab inside the if.
marker="## gitsby pre-push gate - installed by cicd/cicd.bash --install-hook"
IFS= read -r -d '' shimText <<'EOF' || true
#!/usr/bin/env bash
## gitsby pre-push gate - installed by cicd/cicd.bash --install-hook
## A push from a subdirectory starts this at the top of the work tree, and GIT_PREFIX says so.
## A relative GIT_WORK_TREE still points from the subdirectory then, so git would name the wrong top.
if [[ -n "${GIT_PREFIX:-}" ]]; then top="${PWD}"; else top="$(git rev-parse --show-toplevel)" || exit 1; fi
hook="${top}/cicd/utility/pre-push.bash"
if [[ ! -x "${hook}" ]]; then
	printf '%s\n' "pre-push: this checkout has no cicd/utility/pre-push.bash, so this push is not gated." >&2
	exit 0
fi
exec "${hook}" "$@"
EOF

declare -i _wasLastEchoBlank=0
fEcho_Clean(){ if [[ -n "${1:-}" ]]; then printf '%s\n' "$*"; _wasLastEchoBlank=0; elif [[ $_wasLastEchoBlank -eq 0 ]] && echo; then _wasLastEchoBlank=1; fi; }
fEcho(){       if [[ -n "$*"     ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }

fUsage(){ fEcho_Clean "$1 (try --help)" >&2; exit 2; }

fInstall(){
	local hp line target verb="installed" tmp
	if [[ "$(uname -s)" != Linux ]]; then
		fEcho_Clean "pre-push: the gate runs on Linux only, like the rest of cicd/. No hook installed." >&2
		exit 1
	fi
	if [[ "$(git -C "${root}" rev-parse --is-inside-work-tree 2>/dev/null || true)" != true ]]; then
		fEcho_Clean "pre-push: ${root} is not a git work tree. No hook installed." >&2
		exit 1
	fi
	## A set core.hooksPath means git never looks in the directory we would write to, and
	## taking that setting over would switch off whatever hooks it points at.
	hp="$(git -C "${root}" config --show-origin --get-all core.hooksPath 2>/dev/null || true)"
	if [[ -n "${hp}" ]]; then
		{
			fEcho_Clean "pre-push: core.hooksPath is set, so git does not run hooks from this repo's hooks directory."
			while IFS= read -r line; do fEcho_Clean "From: ${line}"; done <<< "${hp}"
			fEcho_Clean "No hook installed. To gate pushes anyway, have the pre-push hook in that directory run:"
			fEcho_Clean "  ${root}/cicd/utility/pre-push.bash \"\$@\""
		} >&2
		exit 1
	fi
	target="$(git -C "${root}" rev-parse --path-format=absolute --git-path hooks/pre-push)"
	## git init --template= leaves no hooks directory at all.
	mkdir -p -- "$(dirname -- "${target}")"
	if [[ -e "${target}" || -L "${target}" ]]; then
		if cmp -s -- "${target}" <(printf '%s' "${shimText}"); then
			fEcho_Clean "pre-push: already installed: ${target}"
			exit 0
		fi
		if ! grep -qxF -- "${marker}" "${target}" 2>/dev/null; then
			{
				fEcho_Clean "pre-push: ${target} already exists and was not written by this script. Left as it is."
				fEcho_Clean "To add the gate to it, have it run: ${root}/cicd/utility/pre-push.bash \"\$@\""
			} >&2
			exit 1
		fi
		verb="updated"
	fi
	tmp="$(mktemp -- "${target}.XXXXXX")"
	printf '%s' "${shimText}" > "${tmp}"
	chmod 0755 -- "${tmp}"
	mv -f -- "${tmp}" "${target}"
	fEcho_Clean "pre-push: ${verb} ${target}"
	fEcho_Clean "Every push to main now runs cicd/cicd.bash --gate on the pushed commit first. git push --no-verify skips it once."
	exit 0
}

## Refuses unless ${snap} is the gate worktree of this repo: registered here, its own top level,
## and sharing this repo's git dir. Called right before anything is forced or removed there.
fProveGateWorktree(){
	local list top gcd
	list="$(git -C "${root}" worktree list --porcelain)"
	top="$(git -C "${snap}" rev-parse --show-toplevel 2>/dev/null || true)"
	gcd="$(git -C "${snap}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
	if grep -qxF -- "worktree ${snap}" <<< "${list}" && [[ "${top}" == "${snap}" && "${gcd}" == "${common}" ]]; then
		return 0
	fi
	fEcho_Clean "pre-push: ${snap} is not this repo's gate worktree. Left as it is; move it aside and push again." >&2
	exit 1
}

## Puts the gate worktree at $1. One fixed path, so the Go build, test and lint caches, which
## key on the directory, stay warm between pushes. No rm here: git removes only a worktree it
## has registered.
fSnapshot(){
	local commit="$1" list
	list="$(git -C "${root}" worktree list --porcelain)"
	if grep -qxF -- "worktree ${snap}" <<< "${list}"; then
		if [[ ! -e "${snap}" ]]; then
			git -C "${root}" worktree add --quiet --force --detach "${snap}" "${commit}"
			return 0
		fi
		fProveGateWorktree
		git -C "${snap}" checkout --quiet --detach --force "${commit}"
		## Whatever a previous gate left behind would be checked along with the commit.
		if [[ -n "$(git -C "${snap}" status --porcelain --untracked-files=all)" ]]; then
			fProveGateWorktree
			git -C "${root}" worktree remove --force "${snap}"
			git -C "${root}" worktree add --quiet --detach "${snap}" "${commit}"
		fi
		return 0
	fi
	if [[ -e "${snap}" || -L "${snap}" ]]; then
		fEcho_Clean "pre-push: ${snap} is not this repo's gate worktree. Left as it is; move it aside and push again." >&2
		exit 1
	fi
	git -C "${root}" worktree add --quiet --detach "${snap}" "${commit}"
}

fHook(){
	local line lsha rref commit short branch cicdText rc i
	local -a lines=() commits=() branches=()
	local -A seen=()
	## git ends every line with a newline; the guard costs nothing.
	while IFS= read -r line || [[ -n "${line}" ]]; do lines+=("${line}"); done
	if [[ "$(git -C "${root}" rev-parse --is-inside-work-tree 2>/dev/null || true)" != true ]]; then
		fEcho_Clean "pre-push: ${root} is not a git work tree; this push is not gated."
		exit 0
	fi
	for line in "${lines[@]}"; do
		[[ -n "${line}" ]] || continue
		## <local ref> <local sha> <remote ref> <remote sha>. A delete is "(delete) 000... <ref> <sha>".
		read -r _ lsha rref _ <<< "${line}"
		if [[ ! "${lsha}" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
			fEcho_Clean "pre-push: unexpected line from git: ${line}" >&2
			exit 1
		fi
		if [[ "${lsha}" =~ ^0+$ ]]; then continue; fi
		## Only main. Other branches are work in progress, and a tag points at a commit that
		## was gated when main went out.
		if [[ "${rref}" != refs/heads/main ]]; then
			fEcho_Clean "pre-push: not gated: ${rref} (only main is gated)"
			continue
		fi
		commit="$(git -C "${root}" rev-parse --verify -q "${lsha}^{commit}" || true)"
		[[ -n "${commit}" ]] || continue
		if [[ -z "${seen[${commit}]:-}" ]]; then
			seen["${commit}"]=1
			commits+=("${commit}")
			branches+=("${rref#refs/heads/}")
		fi
	done
	((${#commits[@]})) || exit 0

	if [[ "$(uname -s)" != Linux ]]; then
		fEcho_Clean "pre-push: the gate runs on Linux only; this push is not gated."
		exit 0
	fi
	common="$(git -C "${root}" rev-parse --path-format=absolute --git-common-dir)"
	snap="${common}/gitsby-gate"
	local -r lockFile="${common}/gitsby-gate.lock"
	## Two pushes at once would check out two commits into one worktree. Released on exit.
	exec 9>"${lockFile}"
	if ! flock -n 9; then
		fEcho_Clean "pre-push: another gate is running in this repo; waiting for it (up to 10 minutes)."
		if ! flock -w 600 9; then
			fEcho_Clean "pre-push: gave up waiting for ${lockFile}. Nothing was pushed." >&2
			exit 1
		fi
	fi

	for i in "${!commits[@]}"; do
		commit="${commits[i]}"
		branch="${branches[i]}"
		short="$(git -C "${root}" rev-parse --short "${commit}")"
		## The v2.1.0 tag, and hotfixes cut from it, predate the gate. Refusing them would block
		## every hotfix push.
		cicdText="$(git -C "${root}" show "${commit}:cicd/cicd.bash" 2>/dev/null || true)"
		if [[ "${cicdText}" != *'--gate)'* ]]; then
			fEcho_Clean "pre-push: ${short} (${branch}) predates the gate: its cicd/cicd.bash has no --gate, so it is not gated."
			continue
		fi
		fSnapshot "${commit}"
		fEcho "pre-push gate: ${short} for ${branch}"
		rc=0
		## 9>&- so nothing the gate leaves running can hold the lock after this push is done.
		(cd "${snap}" && ./cicd/cicd.bash --gate </dev/null 9>&-) || rc=$?
		if [[ "${rc}" != 0 ]]; then
			{
				fEcho_Clean
				fEcho_Clean "pre-push: the gate failed on ${short} (${branch}), so nothing was pushed."
				fEcho_Clean "It checked that commit as committed, in ${snap}. To repeat it: (cd ${snap} && cicd/cicd.bash --gate)"
				fEcho_Clean "To push without the gate this once: git push --no-verify"
			} >&2
			exit 1
		fi
	done
	exit 0
}

common=""; snap=""
case "${1:-}" in
	--install) (($# == 1)) || fUsage "--install takes no arguments"; fInstall ;;
	-h|--help) sed -n '/^##\tPurpose:/,/^##\tHistory:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##\t\{0,1\}//'; exit 0 ;;
	-*)        fUsage "unknown option: $1" ;;
	*)         (($# == 2)) || fUsage "expected --install, or the remote name and URL git hands a pre-push hook"; fHook ;;
esac


##	History:
##		- 20260914 JC: Created. It gates the commit being pushed, in a worktree of its own, rather
##		  than the working tree: uncommitted edits are routine here, and a push names a commit.
##		- 20260914 JC: The hook finds its checkout from where git started it when the push came from
##		  a subdirectory. A relative --work-tree had sent it to the directory above, ungated.
##		- 20260924 JC: Only a push to main is gated. Every other branch goes out without it.
