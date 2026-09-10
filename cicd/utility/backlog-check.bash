#!/usr/bin/env bash

##	Purpose:
##		Two backlog rules that review rounds kept leaking through, checked in cicd
##		stage 1 instead of by hand:
##		1. Every open code-review item (not ✅ ✋ 🚫) carries an "Origin:" sub-bullet -
##		   the commit or round that introduced it, whether an earlier round saw it,
##		   and Confirmed (reproduced) or Plausible (read only).
##		2. A suite check removed on this branch, against the integration branch, is
##		   named in the backlog. Two decisions were reversed by deleting the check
##		   that encoded them, with nothing written down; this makes that a stop.
##		The removed-check match is a fixed-string grep for the check's label, so a
##		label carrying a shell variable has to be quoted in the backlog as written.
##	Syntax:
##		backlog-check.bash [-q] [--base REF] [--backlog FILE]
##		  -q              print findings only
##		  --base REF      branch to diff the suites against (default: first of gover, dev, main that exists)
##		  --backlog FILE  backlog to read (default: project/backlog.md at the repo root)
##	Exit: 0 clean, 1 findings, 2 cannot run (no backlog, not a git repo).
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

meDir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "${meDir}/../.." && pwd)"
backlog="${root}/project/backlog.md"
base=""; quiet=0
suites=(cicd/test.bash cicd/parity.bash cicd/fuzz.bash)

while [[ $# -gt 0 ]]; do
	case "$1" in
		-q)        quiet=1 ;;
		--base)    base="${2:?--base needs a ref}"; shift ;;
		--backlog) backlog="${2:?--backlog needs a file}"; shift ;;
		-h|--help) grep -E '^##' "$0" | sed 's/^##\t\?//'; exit 0 ;;
		*)         echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
	shift
done

fEcho_Clean(){ ((quiet)) || echo "$*"; }
[[ -r "${backlog}" ]] || { echo "backlog-check: no backlog at ${backlog}" >&2; exit 2; }
git -C "${root}" rev-parse --git-dir >/dev/null 2>&1 || { echo "backlog-check: ${root} is not a git repo" >&2; exit 2; }

findings=0

## 1. Open review items without an Origin line. An item runs from its "\t- " line to
## the next line at that depth or shallower; its sub-bullets sit at two tabs.
noOrigin="$(awk '
	/^\t- / || /^- / || /^#/ { if (cur != "" && !found) print cur; cur = ""; found = 0 }
	/^\t- / && /Code Review [0-9]+ (item|enhancement) [0-9]+:/ && !/(✅|✋|🚫)/ {
		cur = $0; sub(/:.*/, "", cur); sub(/^\t- [^ ]+ /, "", cur)
	}
	/^\t\t- Origin:/ { found = 1 }
	END { if (cur != "" && !found) print cur }
' "${backlog}")"
openCount="$(grep -cE '^\t- .*Code Review [0-9]+ (item|enhancement) [0-9]+:' "${backlog}" || true)"
if [[ -n "${noOrigin}" ]]; then
	echo "backlog-check: open review items with no 'Origin:' sub-bullet:"
	while IFS= read -r line; do echo "  ${line}"; done <<< "${noOrigin}"
	findings=1
else
	fEcho_Clean "backlog-check: Origin: present on every open review item (${openCount} listed)"
fi

## 2. Suite checks removed since the merge base. Compares the working tree, not HEAD,
## so it sees the branch as it is about to be committed. A label that was removed
## and added back is an edit, not a removal.
if [[ -z "${base}" ]]; then
	for c in gover dev main; do
		if git -C "${root}" rev-parse --verify -q "refs/heads/${c}" >/dev/null; then base="${c}"; break; fi
	done
fi
if [[ -z "${base}" ]]; then
	fEcho_Clean "backlog-check: no integration branch found; removed-check test skipped"
else
	mergeBase="$(git -C "${root}" merge-base HEAD "${base}" 2>/dev/null || true)"
	if [[ -z "${mergeBase}" ]]; then
		fEcho_Clean "backlog-check: no merge base with ${base}; removed-check test skipped"
	else
		labelRE='^[-+][[:space:]]*f(Assert[A-Za-z]*|Same[A-Za-z]*|Ok)[[:space:]]+"([^"]*)"'
		diffOut="$(git -C "${root}" diff "${mergeBase}" -- "${suites[@]}" || true)"
		removed="$(printf '%s\n' "${diffOut}" | sed -nE "/^-/ s/${labelRE}.*/\2/p" | sort -u)"
		added="$(printf '%s\n' "${diffOut}" | sed -nE "/^\+/ s/${labelRE}.*/\2/p" | sort -u)"
		unnamed=""
		while IFS= read -r label; do
			[[ -n "${label}" ]] || continue
			grep -qxF -- "${label}" <<< "${added}" && continue
			grep -qF -- "${label}" "${backlog}" || unnamed+="${label}"$'\n'
		done <<< "${removed}"
		if [[ -n "${unnamed}" ]]; then
			echo "backlog-check: suite checks removed since ${base} and not named in the backlog:"
			while IFS= read -r line; do [[ -n "${line}" ]] && echo "  \"${line}\""; done <<< "${unnamed}"
			echo "  Name each one in the backlog, with the decision it encoded and why that changed."
			findings=1
		else
			n=0; [[ -n "${removed}" ]] && n="$(grep -c . <<< "${removed}")"
			fEcho_Clean "backlog-check: removed suite checks all named in the backlog (${n} removed since ${base})"
		fi
	fi
fi

exit "${findings}"


##	History:
##		- 20260910 JC: Created. The review-round audit found the refill came from
##		  deferred notes and silently deleted checks, not from fixes undoing fixes.
