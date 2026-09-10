#!/usr/bin/env bash

##	Purpose:
##		- Writes the Windows resource (.syso) the Go linker picks up, so the .exe carries an
##		  icon and the version details Explorer's Properties tab reads.
##		- The .syso files are COMMITTED, not built on demand. They are linked into the bytes
##		  we publish checksums for, so a rebuild from the tag has to produce them without
##		  needing a tool installed - the same reason -buildvcs=false is on.
##		- Which means they carry the LAST RELEASED version, not the working tree's describe
##		  output: a resource that changed every commit could not be committed at all.
##		  release.bash regenerates them as part of the version bump, next to the changelog.
##		- --check is what the pipeline runs: regenerate to a temp dir and compare. It catches
##		  an edited icon or description that nobody regenerated, and a release that skipped
##		  the bump.
##	Syntax:
##		cicd/utility/gen-winres.bash [-q] [VERSION]           Write src-go/resource_windows_*.syso.
##		cicd/utility/gen-winres.bash [-q] --check [VERSION]   Compare the committed ones, change nothing.
##		cicd/utility/gen-winres.bash [-q] --icon              Rebuild assets/gitsby.ico from logo.png.
##		  VERSION  e.g. v2.1.0. Omitted, the newest v* tag.
##	Requires:
##		- goversioninfo, for everything except --icon:
##		      go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo@v1.5.0
##		  Absent, --check exits 3 without checking anything and writing refuses, so a caller can
##		  tell "no tool" from "stale" without probing for it.
##		- --icon additionally needs ImageMagick, icoutils and optipng. It is a hand step, run
##		  when the logo changes, and is deliberately not part of any gate: the encoders differ
##		  between versions, so the .ico is a committed asset rather than a reproducible one.
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

## Where 'go install' would have put it, in the order go itself resolves them.
goversioninfo="$(command -v goversioninfo 2>/dev/null || true)"
for goDir in "$(go env GOBIN 2>/dev/null)" "$(go env GOPATH 2>/dev/null)/bin"; do
	[[ -z "${goversioninfo}" && -n "${goDir}" && -x "${goDir}/goversioninfo" ]] || continue
	goversioninfo="${goDir}/goversioninfo"
done
[[ -x "${goversioninfo}" ]] || goversioninfo=""

icon="${root}/assets/gitsby.ico"
logo="${root}/assets/logo.png"

declare -i quiet=0 check=0 iconOnly=0
version=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		-q|--quiet) quiet=1; shift ;;
		--check)    check=1; shift ;;
		--icon)     iconOnly=1; shift ;;
		-h|--help)  sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
		-*)         echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
		*)          version="$1"; shift ;;
	esac
done

fSay(){ ((quiet)) || echo "$@"; }
fDie(){ echo "gen-winres: $*" >&2; exit 1; }


##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## --icon: rebuild the .ico from the logo. Six sizes. 16/32/48 stay BMP because Explorer before
## Windows 10 does not reliably draw a PNG-compressed entry below 256; the three large ones are
## PNG, quantized to 256 colors, which takes the file from 134 KB to 48 KB for a 1.3% RMSE the
## eye cannot find at icon size.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
if ((iconOnly)); then
	for tool in magick icotool optipng; do command -v "${tool}" >/dev/null 2>&1 || fDie "--icon needs ${tool}."; done
	[[ -f "${logo}" ]] || fDie "no logo at assets/$(basename "${logo}")."
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-ico.XXXXXX")"
	trap 'rm -rf -- "${tmp:?}"' EXIT
	## A touch of unsharp on the small ones, or the portrait turns to mush at 16 px.
	for s in 16 32 48; do magick "${logo}" -filter Lanczos -resize "${s}x${s}" -unsharp 0x0.5+0.6+0.02 -strip "${tmp}/i${s}.png"; done
	for s in 64 128 256; do
		magick "${logo}" -filter Lanczos -resize "${s}x${s}" -dither Riemersma -colors 256 -strip "${tmp}/i${s}.png"
		optipng -quiet -o7 -strip all "${tmp}/i${s}.png" 2>/dev/null || true
	done
	icotool -c -o "${icon}" "${tmp}/i16.png" "${tmp}/i32.png" "${tmp}/i48.png" \
		--raw="${tmp}/i64.png" --raw="${tmp}/i128.png" --raw="${tmp}/i256.png" \
		|| fDie "icotool couldn't write ${icon}."
	fSay "wrote assets/$(basename "${icon}") ($(stat -c%s "${icon}") bytes)"
	exit 0
fi


##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Which version the resource claims.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
if [[ -z "${version}" ]]; then
	version="$(git -C "${root}" -c versionsort.suffix=- tag --sort=-v:refname --list 'v*' 2>/dev/null | head -n 1)"
	[[ -n "${version}" ]] || fDie "no v* tag to take a version from; pass one."
fi
[[ "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([A-Za-z0-9.-]+)?$ ]] || fDie "'${version}' is not a vX.Y.Z version."
verStr="${version#v}"
## FIXEDFILEINFO is four numbers and nothing else, so a candidate's suffix survives only in the
## strings Explorer displays.
IFS='.' read -r verMajor verMinor verPatch <<< "${verStr%%-*}"

[[ -f "${icon}" ]] || fDie "no icon at assets/$(basename "${icon}") - run with --icon."

if [[ -z "${goversioninfo}" ]]; then
	## Refused where it would silently ship the wrong bytes. --check answers 3 instead, which is
	## how the callers tell "not installed" from "stale" without probing for the tool themselves.
	((check)) || fDie "goversioninfo isn't installed (see --help)."
	fSay "  windows resource check skipped (no goversioninfo)"
	exit 3
fi

## Everything the resource says, in one place. Written to a temp file rather than committed as a
## versioninfo.json, so the version in it cannot go stale against the one being generated for.
fpWriteJson(){
	cat > "$1" <<-JSON
		{
			"FixedFileInfo": {
				"FileVersion":    { "Major": ${verMajor}, "Minor": ${verMinor}, "Patch": ${verPatch}, "Build": 0 },
				"ProductVersion": { "Major": ${verMajor}, "Minor": ${verMinor}, "Patch": ${verPatch}, "Build": 0 },
				"FileFlagsMask": "3f",
				"FileFlags": "00",
				"FileOS": "040004",
				"FileType": "01",
				"FileSubType": "00"
			},
			"StringFileInfo": {
				"CompanyName": "Jim Collier",
				"FileDescription": "A simple, safe, opinionated Git wrapper for everyday work",
				"FileVersion": "${verStr}",
				"InternalName": "${EXE_NAME}",
				"LegalCopyright": "Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]. Licensed under the MIT License.",
				"OriginalFilename": "${EXE_NAME}.exe",
				"ProductName": "${APP_NAME}",
				"ProductVersion": "${verStr}"
			},
			"VarFileInfo": {
				"Translation": { "LangID": "0409", "CharsetID": "04B0" }
			},
			"IconPath": "${icon}"
		}
	JSON
}

## goversioninfo names the word size and the family, not the GOARCH, so the mapping is by hand.
fpArchFlags(){
	case "$1" in
		amd64) printf '%s' "-64" ;;
		arm64) printf '%s' "-arm -64" ;;
		386)   printf '%s' "" ;;
		arm)   printf '%s' "-arm" ;;
		*)     return 1 ;;
	esac
}

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## One .syso per Windows target we publish. The GOOS_GOARCH suffix is what keeps the Linux and
## macOS builds from ever seeing them - the same file-name rule that applies to .go files.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
declare -a arches=()
for t in "${RELEASE_TARGETS[@]}"; do
	[[ "${t}" == windows/* ]] || continue
	arches+=("${t##*/}")
done
((${#arches[@]})) || fDie "no windows targets in RELEASE_TARGETS."

out="${root}/${GO_MODULE_DIR}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-winres.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT
## --check generates beside nothing and compares; writing generates in place.
work="${out}"; ((check)) && work="${scratch}"

json="${scratch}/versioninfo.json"
fpWriteJson "${json}"

declare -i differed=0
for arch in "${arches[@]}"; do
	flags="$(fpArchFlags "${arch}")" || fDie "no goversioninfo flags known for windows/${arch}."
	name="resource_windows_${arch}.syso"
	# shellcheck disable=2086  ## 'quote to prevent word splitting.' The flag string is meant to split.
	"${goversioninfo}" ${flags} -o "${work}/${name}" "${json}" || fDie "goversioninfo failed for windows/${arch}."
	if ((check)); then
		if ! cmp -s "${work}/${name}" "${out}/${name}"; then
			echo "  ${GO_MODULE_DIR}/${name} is not what ${version} generates - run cicd/utility/gen-winres.bash" >&2
			differed=1
		fi
	else
		fSay "  wrote ${GO_MODULE_DIR}/${name} ($(stat -c%s "${out}/${name}") bytes)"
	fi
done

if ((differed)); then exit 1; fi
if ((check)); then fSay "  windows resources match ${version}"; fi
exit 0


##	History:
##		- 20260819 JC: Created. The Windows builds had no icon and no version details; this writes
##		  the resource that gives them both. Committed rather than generated at build time, so the
##		  published .exe can be rebuilt from its tag without the tool.
