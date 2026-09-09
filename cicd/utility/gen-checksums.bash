#!/usr/bin/env bash

##	Purpose:
##		- Writes SHA256SUMS for a directory of release assets, named as the assets are
##		  named on the release, to stdout or a given file.
##		- Operates on the current directory, so it works the same for a release the
##		  pipeline built and for one assembled by hand:
##		      cd <asset dir> && cicd/utility/gen-checksums.bash SHA256SUMS
##		      gh release upload vX.Y.Z ./*
##		  Any existing SHA256SUMS is left out of its own listing.
##	History: At bottom of script.

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -eu; set -o pipefail

fEcho(){ echo "[ $* ]"; }

outFile="${1:-}"

fSums(){
	local -a files=()
	local f=""
	for f in *; do
		[[ -f "${f}" ]] || continue
		[[ "${f}" == "SHA256SUMS" ]] && continue
		files+=("${f}")
	done
	((${#files[@]})) || { echo "no files to checksum in $(pwd)" >&2; return 1; }
	sha256sum -- "${files[@]}"
}

if [[ -n "${outFile}" ]]; then
	fSums > "${outFile}"
	fEcho "Wrote ${outFile}"
else
	fSums
fi


##	History:
##		- 20260724: Created.
##		- 20260818: Checksums the directory it is run in rather than a hard-coded bin/ holding two scripts. A release is now one binary per platform, and the set changes with the target list.
