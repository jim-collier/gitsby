#!/usr/bin/env bash

##	Purpose:
##		- Downloads and installs the latest gitsby release, after showing the plan
##		  and asking first. Meant for one-liner use:
##		      curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install.bash | bash
##		  Flags go after 'bash -s --', e.g.:
##		      ... | bash -s -- --system -y
##		- Runs on bash 3.2+ (stock macOS bash), so no bash-4/5 features in here.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -eu; set -o pipefail

repo="jim-collier/gitsby"
doSystem=0; doYes=0; ref=""; isRelease=1
releaseChannel=""; targetScope=""; arch=""

fEcho(){  echo "[ $* ]"; }
fErr(){   echo "Error: $*" >&2; exit 1; }
fLower(){ printf '%s' "${1}" | tr '[:upper:]' '[:lower:]'; }
fSyntax(){
	cat <<-EOF
	Usage: install.bash [OPTIONS]
	Downloads and installs gitsby (with confirmation).
	Options:
	  --release dev|stable   Latest release (default), or the tip of the dev branch.
	  --target user|system   Install for you (~/.local/bin, default) or everyone (/usr/local/bin).
	  --arch x64|amd64|arm64 Accepted for consistency with other installers, and has no effect
	                         here: gitsby is a shell script, so one file runs everywhere.
	  -r, --ref REF          A specific branch, tag, or commit. Skips checksum verification.
	  -y, --yes              Don't ask for confirmation.
	  -h, --help             This.
	EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--release)   [[ $# -ge 2 ]] || fErr "--release needs a value (dev or stable)."; releaseChannel="$(fLower "$2")"; shift ;;
		--target)    [[ $# -ge 2 ]] || fErr "--target needs a value (user or system)."; targetScope="$(fLower "$2")"; shift ;;
		--arch)      [[ $# -ge 2 ]] || fErr "--arch needs a value (x64, amd64 or arm64)."; arch="$(fLower "$2")"; shift ;;
		-s|--system) targetScope="system" ;;
		-y|--yes)    doYes=1 ;;
		-r|--ref)    [[ $# -ge 2 ]] || fErr "--ref needs a value."; ref="$2"; shift ;;
		-h|--help)   fSyntax; exit 0 ;;
		*)           fErr "Unknown option: '$1' (try --help)." ;;
	esac
	shift
done

case "${targetScope}" in
	""|user) doSystem=0 ;;
	system)  doSystem=1 ;;
	*)       fErr "--target takes 'user' or 'system' (got '${targetScope}')." ;;
esac

## Named for parity with installers that fetch a per-architecture binary. Validate it
## anyway - a typo here means the caller believes something about the install that isn't true.
case "${arch}" in
	""|x64|x86_64|amd64|arm64|aarch64) : ;;
	*) fErr "--arch takes 'x64', 'amd64' or 'arm64' (got '${arch}')." ;;
esac

## --release is the friendly spelling; --ref is the escape hatch. Both at once is ambiguous.
[[ -n "${releaseChannel}" && -n "${ref}" ]] && fErr "Use --release or --ref, not both."
case "${releaseChannel}" in
	""|stable) : ;;
	dev)       ref="dev" ;;
	*)         fErr "--release takes 'dev' or 'stable' (got '${releaseChannel}')." ;;
esac

## The ref lands in a download URL, so a path-shaped one walks out of this repo and installs
## somebody else's script while the plan on screen still names ours. Reads as a harmless
## branch selector, which is exactly why the confirm prompt is no protection here.
case "${ref}" in
	""|*/../*|../*|*/..|..|/*|*//*) [[ -z "${ref}" ]] || fErr "--ref names a branch, tag or commit, not a path (got '${ref}')." ;;
esac
[[ -z "${ref}" || "${ref}" =~ ^[A-Za-z0-9._/-]+$ ]] || fErr "--ref has characters that aren't valid in a git ref (got '${ref}')."

## gitsby itself needs bash 4.4+ (it sets inherit_errexit); this installer deliberately
## doesn't. Check before downloading rather than after: both run through 'env bash', so
## the bash running us is the one that would run gitsby. Stock macOS is 3.2 and stays 3.2
## no matter what you install, so the fix there is a PATH change, not just a package.
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]] || { [[ "${BASH_VERSINFO[0]}" -eq 4 ]] && [[ "${BASH_VERSINFO[1]}" -lt 4 ]]; }; then
	echo "Error: gitsby needs bash 4.4 or newer; this is bash ${BASH_VERSION}." >&2
	case "$(uname -s 2>/dev/null)" in
		Darwin)
			echo "  macOS still ships bash 3.2, and never replaces it. Install a current one:" >&2
			echo "    brew install bash        (Homebrew)" >&2
			echo "    sudo port install bash   (MacPorts)" >&2
			echo "  Both install alongside /bin/bash rather than over it, so make sure the new" >&2
			echo "  one comes first on your PATH, then re-run this installer." >&2 ;;
		*BSD|DragonFly)
			echo "  Install bash from packages or ports, then re-run this installer:" >&2
			echo "    pkg install bash         (FreeBSD)" >&2
			echo "    pkg_add bash             (OpenBSD)" >&2 ;;
		*)
			echo "  Install bash 4.4 or newer with your package manager, then re-run this installer." >&2 ;;
	esac
	echo "  Or install the PowerShell build with install.ps1, which needs no bash at all." >&2
	exit 1
fi

## Downloader: curl or wget, whichever exists.
if   command -v curl >/dev/null 2>&1; then fFetch(){ curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then fFetch(){ wget -qO- "$1"; }
else fErr "Need curl or wget."
fi

## No --ref: resolve the latest release tag from the releases/latest redirect (no auth,
## no API rate limit); unauthenticated API scrape only as fallback (60 req/hr per IP).
if [[ -z "${ref}" ]]; then
	if command -v curl >/dev/null 2>&1; then
		ref="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null | sed -n 's|.*/releases/tag/||p')"
	elif command -v wget >/dev/null 2>&1; then
		ref="$(wget -q --max-redirect=0 -S -O /dev/null "https://github.com/${repo}/releases/latest" 2>&1 | sed -n 's|.*[Ll]ocation: .*/releases/tag/\([^[:space:]]*\).*|\1|p' | head -n 1)"
	fi
	[[ -n "${ref}" ]] || ref="$(fFetch "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
	[[ -n "${ref}" ]] || fErr "Couldn't determine the latest release; try '--release dev'. (GitHub may be rate-limiting; try again later.)"
	## Scraped from a redirect header, so check it the same way as a typed one before it reaches a URL.
	[[ "${ref}" =~ ^[A-Za-z0-9._/-]+$ ]] || fErr "The resolved release tag ('${ref}') isn't a plain git ref; aborting."
else
	isRelease=0
fi

destDir="${HOME}/.local/bin"; needSudo=0
if [[ ${doSystem} -eq 1 ]]; then
	destDir="/usr/local/bin"
	[[ -w "${destDir}" ]] || needSudo=1
fi

echo
fEcho "gitsby installer"
echo "This will:"
echo "  - Download gitsby (${ref}) from github.com/${repo}"
[[ -n "${arch}" ]] && echo "  - Ignore --arch ${arch}: gitsby is a shell script, so the same file runs on every architecture"
echo "  - Install it to ${destDir}/gitsby"
[[ -d "${destDir}" ]] || echo "  - Create ${destDir} (it doesn't exist yet)"
[[ ${needSudo} -eq 1 ]] && echo "  - Use sudo for the install step (you may be prompted for your password)"
## Whether the download gets checked is the one thing worth knowing BEFORE agreeing to it.
## It used to be reported afterwards, and on the dev path not at all.
if [[ ${isRelease} -eq 1 ]]; then
	echo "  - Verify the download against the release's published SHA256SUMS"
else
	echo "  - NOT verify the download: ${ref} is a branch or tag, which has no published checksum"
fi
echo "  - Run 'gitsby --version' to verify"
if [[ ${doYes} -eq 0 ]]; then
	answer=""
	## When piped (curl | bash) stdin is the script, so confirm via the terminal.
	## (-r /dev/tty isn't enough - it can exist yet fail to open with no
	## controlling terminal - so test with a real open.)
	if   [[ -t 0 ]];                  then read -r -p "Continue? [y/N] " answer
	elif { : </dev/tty; } 2>/dev/null; then read -r -p "Continue? [y/N] " answer </dev/tty
	else fErr "No terminal to confirm on; re-run with -y (e.g. '| bash -s -- -y')."
	fi
	case "${answer}" in y|Y|yes|Yes|YES) ;; *) echo "Aborted."; exit 1 ;; esac
fi

tmpFile="$(mktemp "${TMPDIR:-/tmp}/gitsby-install.XXXXXX")"
trap 'rm -f -- "${tmpFile:?}"' EXIT

echo
fEcho "Downloading ..."
## Prefer the release asset; fall back to the file in the tagged tree.
fromReleaseAsset=0
if [[ ${isRelease} -eq 1 ]] && fFetch "https://github.com/${repo}/releases/download/${ref}/gitsby" > "${tmpFile}" 2>/dev/null; then
	fromReleaseAsset=1
elif fFetch "https://raw.githubusercontent.com/${repo}/${ref}/bin/gitsby" > "${tmpFile}" 2>/dev/null; then
	## Only the release asset can be checked against SHA256SUMS, so falling back to the tree
	## here would quietly deliver the unverified copy the plan promised to check. Asking for a
	## release and getting that is not what was agreed, so it stops instead.
	[[ ${isRelease} -eq 1 ]] && fErr "Release ${ref} publishes no gitsby asset, so only an unverified copy of the tagged tree is available. Re-run with '--ref ${ref}' to take it."
else
	fErr "Couldn't download gitsby at '${ref}'. (Releases before v2 predate the current layout; try '--release dev'.)"
fi
head -n 1 "${tmpFile}" | grep -q '^#!/' || fErr "Downloaded file doesn't look like a script; aborting."

## Verify against the release's SHA256SUMS when there is one. Only the release-asset
## path can be verified; --ref installs pull straight from the tree, unverified.
if [[ ${fromReleaseAsset} -eq 1 ]]; then
	if   command -v sha256sum >/dev/null 2>&1; then fSha256(){ sha256sum "$1" | cut -d' ' -f1; }
	elif command -v shasum    >/dev/null 2>&1; then fSha256(){ shasum -a 256 "$1" | cut -d' ' -f1; }  ## macOS
	else fSha256(){ :; }
	fi
	sums="$(fFetch "https://github.com/${repo}/releases/download/${ref}/SHA256SUMS" 2>/dev/null || true)"
	want="$(printf '%s\n' "${sums}" | sed -n 's/^\([0-9a-f]\{64\}\)[[:space:]]*\*\{0,1\}gitsby$/\1/p' | head -n 1)"
	got="$(fSha256 "${tmpFile}")"
	if [[ -n "${want}" && -n "${got}" ]]; then
		[[ "${got}" = "${want}" ]] || fErr "Checksum mismatch for the downloaded gitsby; aborting. (Corrupted download or tampering.)"
		fEcho "Checksum verified."
	## The plan said this download would be checked, so not checking it is a broken promise
	## rather than a note in passing. Stop, name which half is missing, and leave the way to
	## take it unverified an explicit choice rather than the quiet default.
	elif [[ -z "${got}" ]]; then
		fErr "No sha256 tool here (need sha256sum or shasum), so the download can't be verified. Install one, or re-run with '--ref ${ref}' to take it unverified."
	else
		fErr "Release ${ref} publishes no SHA256SUMS entry for gitsby, so the download can't be verified. Re-run with '--ref ${ref}' to take it unverified."
	fi
fi

fEcho "Installing to ${destDir}/gitsby ..."
if [[ ${needSudo} -eq 1 ]]; then
	## mkdir -p, not 'install -d': on a directory that already exists, install resets its mode,
	## and this branch is reached whenever /usr/local/bin exists but isn't writable by us.
	sudo mkdir -p "${destDir}"
	sudo install -m 755 "${tmpFile}" "${destDir}/gitsby"
else
	mkdir -p "${destDir}"
	install -m 755 "${tmpFile}" "${destDir}/gitsby"
fi

fEcho "Verifying ..."
"${destDir}/gitsby" --version
case ":${PATH}:" in
	*":${destDir}:"*) ;;
	*) echo "Note: ${destDir} isn't on your PATH; add it in your shell profile." ;;
esac
echo
fEcho "Done."
echo


##	History:
##		- 20260722 JC: Created.
##		- 20260724 JC: Latest-release lookup via the releases/latest redirect (API scrape is now the rate-limited fallback); release-asset downloads verify against a SHA256SUMS asset when published; trailing blank line.
##		- 20260727 JC: Options now spelled --release, --target and --arch, to match the other installers. -s/--system and --ref still work.
##		- 20260812 JC: The plan says whether the download will be checked, before it is agreed to. It was reported only afterwards, and on the --release dev path not at all - so the one route that installs an unverified file was the quiet one.
