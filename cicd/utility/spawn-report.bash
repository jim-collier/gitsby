#!/usr/bin/env bash

##	Purpose:
##		Surface the newest recorded spawn counts, the profiling counterpart to
##		lint-report.bash. spawn-count.bash records one spawn_<ts>.tsv per cicd run
##		(gitignored, GFS-rotated); this prints the newest one, with the deltas
##		against the run before it. Two modes: plain (always print) and --check
##		(print only when the newest tsv is newer than the one last recorded in a
##		local marker, then record it - meant for a per-session startup look that
##		is a no-op until a new cicd run has happened).
##	Syntax:
##		spawn-report.bash [--check] [--force] [--no-mark] [--dir DIR]
##		  --check     gate on the .spawn-seen marker; print SEEN and stop if not newer
##		  --force     with --check, report even if already seen
##		  --no-mark   with --check, do not update the marker
##		  --dir DIR   tsv directory (default: cicd/artifacts/spawn next to this script)
##	Exit: 0 normal, 2 skip (no dir / no recordings).
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

meDir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dir="${meDir}/../artifacts/spawn"
check=0; force=0; noMark=0

fEcho_Clean(){ echo "$*"; }

while (($#)); do case "$1" in
	--check)   check=1; shift ;;
	--force)   force=1; shift ;;
	--no-mark) noMark=1; shift ;;
	--dir)     dir="${2:-}"; shift 2 ;;
	-h|--help) grep -E '^##' "$0" | sed 's/^##\t\?//'; exit 0 ;;
	*) echo "spawn-report: unknown option: $1" >&2; exit 2 ;;
esac; done

fSkip(){ echo "spawn-report: $1" >&2; exit 2; }

##	Newest two spawn_<ts>[_role].tsv by timestamp - a gfs role suffix is ignored,
##	the timestamp is stable.
fNewestTwo(){
	local d="$1" f b t
	for f in "$d"/spawn_*.tsv; do
		[[ -e "$f" ]] || continue
		b="$(basename "$f")"; t="${b#spawn_}"; t="${t%%_*}"; t="${t%.tsv}"
		printf '%s\t%s\n' "$t" "$f"
	done | sort -r | head -n 2
}

[[ -d "$dir" ]] || fSkip "no spawn dir: $dir"
newestTwo="$(fNewestTwo "$dir")"
[[ -n "$newestTwo" ]] || fSkip "no recordings in $dir"
ts="$(printf '%s\n' "$newestTwo" | sed -n '1p' | cut -f1)"
newest="$(printf '%s\n' "$newestTwo" | sed -n '1p' | cut -f2)"
prev="$(printf '%s\n' "$newestTwo" | sed -n '2p' | cut -f2)"

marker="${dir}/.spawn-seen"
if ((check)) && ((! force)); then
	seen=""; [[ -f "$marker" ]] && seen="$(tr -d '[:space:]' < "$marker" 2>/dev/null)"
	if [[ -n "$ts" && -n "$seen" && ! "$ts" > "$seen" ]]; then
		fEcho_Clean "SEEN $(basename "$newest")  (nothing newer than $seen)"; exit 0
	fi
fi

##	Record before printing, same as lint-report: a caller that closes stdout early
##	still records the look.
if ((check)) && ((! noMark)) && [[ -n "$ts" ]]; then
	printf '%s\n' "$ts" > "$marker" 2>/dev/null || echo "spawn-report: could not write marker: $marker" >&2
fi

tag="COUNTS"; ((check)) && tag="NEW"
fEcho_Clean "${tag} $(basename "$newest")$( [[ -n "$prev" ]] && echo "  (vs $(basename "$prev"))" )"
while IFS=$'\t' read -r label count; do
	[[ -n "$label" ]] || continue
	delta=""
	if [[ -n "$prev" ]]; then
		was="$(awk -F'\t' -v k="$label" '$1==k{print $2}' "$prev")"
		if   [[ -z "$was" ]];              then delta="  (new)"
		elif (( count > was ));            then delta="  (was ${was})"
		elif (( count < was ));            then delta="  (was ${was})"
		fi
	fi
	fEcho_Clean "  ${count}	${label}${delta}"
done < "$newest"


##	History:
##		- 20260821 JC: Created. The lint-report --check pattern, pointed at the spawn
##		  recordings, so the startup look at profiler output has a tool to call.
