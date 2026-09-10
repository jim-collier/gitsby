#!/usr/bin/env bash

##	Purpose:
##		- Keeps timestamped copies of the built binary, and runs one of them, so a
##		  behavior change can be bisected against a build that predates it.
##		- Worth less here than in the projects this comes from: gitsby exits
##		  immediately, so nothing is ever held open and there is nothing to run
##		  "alongside" in the usual sense. What it is actually for is having last
##		  week's binary to hand when something answers differently than it used to.
##		- Archived copies are GFS-rotated, so the set stays bounded on its own.
##	Syntax:
##		cicd/utility/keep-build.bash                     Archive the current build.
##		cicd/utility/keep-build.bash --list              What is kept, newest last.
##		cicd/utility/keep-build.bash --run N [args ...]  Run kept build N (1 = newest).
##		cicd/utility/keep-build.bash --diff N [args ...] Run N and the current build on
##		                                                 the same arguments, and diff.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
# shellcheck source=/dev/null
source "${root}/cicd/config.bash"
# shellcheck source=/dev/null
source "${here}/include/gfs-rotate.bash"

keepDir="${root}/${KEEP_BUILD_DIR}"
exe="${root}/${GO_MODULE_DIR}/${EXE_NAME}"

fDie(){ echo "keep-build: $*" >&2; exit 1; }

## Newest last, which is what the GFS naming already sorts to.
fKept(){ ls -1 "${keepDir}"/build_*."${EXE_NAME}" 2>/dev/null || true; }

fNth(){
	local -i want="$1"
	local -a kept=()
	mapfile -t kept < <(fKept)
	((${#kept[@]})) || fDie "nothing kept yet in ${KEEP_BUILD_DIR}; run this with no arguments first."
	(( want >= 1 && want <= ${#kept[@]} )) || fDie "no kept build ${want}; there are ${#kept[@]} (1 is the newest)."
	## 1 is the NEWEST, which is the end of a chronological listing.
	printf '%s' "${kept[$(( ${#kept[@]} - want ))]}"
}

case "${1:-}" in
	--list)
		mapfile -t kept < <(fKept)
		((${#kept[@]})) || { echo "nothing kept yet."; exit 0; }
		for (( i = ${#kept[@]} - 1, n = 1; i >= 0; i--, n++ )); do
			printf '%2d  %s  %s\n' "${n}" "$(basename "${kept[i]}")" "$("${kept[i]}" --version 2>/dev/null | sed -n '2p' || true)"
		done
		;;
	--run)
		[[ $# -ge 2 ]] || fDie "--run needs a number (see --list)."
		which="$(fNth "$2")"; shift 2
		exec "${which}" "$@"
		;;
	--diff)
		[[ $# -ge 2 ]] || fDie "--diff needs a number (see --list)."
		which="$(fNth "$2")"; shift 2
		[[ -x "${exe}" ]] || fDie "no current build at ${GO_MODULE_DIR}/${EXE_NAME}."
		tmp="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-keep.XXXXXX")"
		trap 'rm -rf -- "${tmp:?}"' EXIT
		"${which}" "$@" > "${tmp}/old" 2>&1 || true
		"${exe}"   "$@" > "${tmp}/new" 2>&1 || true
		## diff exits 1 on a difference, and this script runs under -e - so the status is
		## taken deliberately rather than allowed to end the run at the first finding.
		if diff -u --label "$(basename "${which}")" "${tmp}/old" --label "current" "${tmp}/new"; then
			echo "identical"
		fi
		;;
	""|--keep)
		[[ -x "${exe}" ]] || fDie "no build at ${GO_MODULE_DIR}/${EXE_NAME} - run cicd.bash, or 'go build' there."
		mkdir -p "${keepDir}"
		cp -f "${exe}" "${keepDir}/build_$(date +%Y%m%d-%H%M%S).${EXE_NAME}"
		gfs_rotate "${keepDir}" build "${EXE_NAME}" >/dev/null 2>&1 || true
		echo "kept $(fKept | tail -n 1 | xargs -r basename)"
		;;
	-h|--help)
		sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'
		;;
	*)
		fDie "unknown option: $1 (try --help)."
		;;
esac


##	History:
##		- 20260819 JC: Created. The bisecting half of the profiling directive: gitsby exits
##		  immediately, so there is nothing to run alongside anything - what is actually
##		  wanted is last week's binary, and a diff of the two on the same arguments.
