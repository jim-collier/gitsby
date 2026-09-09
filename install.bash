#!/usr/bin/env bash

##	Purpose:
##		- Downloads and installs the gitsby binary for this platform, after showing the
##		  plan and asking first. Meant for one-liner use:
##		      curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install.bash | bash
##		  Flags go after 'bash -s --', e.g.:
##		      ... | bash -s -- --system -y
##		- Runs on bash 3.2+ (stock macOS bash), so no bash-4/5 features in here. What it
##		  installs is a static binary and needs no shell at all.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -eu; set -o pipefail

repo="jim-collier/gitsby"
doSystem=0; doYes=0; tag=""
releaseChannel=""; targetScope=""; arch=""

fEcho(){  echo "[ $* ]"; }
fErr(){   { echo; echo "Error: $*"; echo; } >&2; exit 1; }
fLower(){ printf '%s' "${1}" | tr '[:upper:]' '[:lower:]'; }
fSyntax(){
	echo
	cat <<-EOF
	Usage: install.bash [OPTIONS]
	Downloads and installs gitsby (with confirmation).
	Options:
	  --target user|system   Install for you (~/.local/bin, default) or everyone (/usr/local/bin).
	  -s, --system           The same thing as --target system.
	  --arch amd64|arm64     Which binary to fetch. Detected from this machine by default.
	  -t, --tag TAG          A published release tag (default: the latest release).
	  -y, --yes              Don't ask for confirmation.
	  -h, --help             This.
	  --release              Took 'dev' or 'stable' when gitsby was a script; takes neither now.
	EOF
	echo
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		## Both spellings of every option that takes a value. The joined form is what anyone
		## used to long options types, and refusing it as unknown reads as the option itself
		## not existing.
		--release)   [[ $# -ge 2 ]] || fErr "--release needs a value."; releaseChannel="$(fLower "$2")"; shift ;;
		--release=*) releaseChannel="$(fLower "${1#*=}")" ;;
		--target)    [[ $# -ge 2 ]] || fErr "--target needs a value (user or system)."; targetScope="$(fLower "$2")"; shift ;;
		--target=*)  targetScope="$(fLower "${1#*=}")" ;;
		--arch)      [[ $# -ge 2 ]] || fErr "--arch needs a value (amd64 or arm64)."; arch="$(fLower "$2")"; shift ;;
		--arch=*)    arch="$(fLower "${1#*=}")" ;;
		-s|--system) targetScope="system" ;;
		-y|--yes)    doYes=1 ;;
		-t|--tag|-r|--ref) [[ $# -ge 2 ]] || fErr "--tag needs a value."; tag="$2"; shift ;;
		--tag=*|--ref=*)   tag="${1#*=}" ;;
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

## --arch used to be accepted and ignored, back when the product was one shell script that
## ran everywhere. It picks the binary now, so spell the two the release actually publishes.
case "${arch}" in
	"")                 : ;;
	x64|x86_64|amd64)   arch="amd64" ;;
	arm64|aarch64)      arch="arm64" ;;
	*) fErr "--arch takes 'amd64' or 'arm64' (got '${arch}')." ;;
esac

## '--release dev' installed the tip of a branch, which meant downloading a script. There is
## no script to download now, and a branch has no build behind it - so name what happened
## rather than letting a familiar flag fail as an unknown option.
case "${releaseChannel}" in
	"") : ;;
	stable) : ;;
	dev) fErr "There is no '--release dev' any more: gitsby is a compiled binary, and a branch has no published build. Take a release with '--tag TAG', or build the tip yourself: git clone https://github.com/${repo}.git && cd gitsby/src-go && go build -o gitsby ." ;;
	*)   fErr "--release only ever took 'dev' or 'stable', and now takes neither; use '--tag TAG' for a specific release." ;;
esac

## The tag lands in a download URL, so a path-shaped one walks out of this repo and installs
## somebody else's binary while the plan on screen still names ours. Reads as a harmless
## version selector, which is exactly why the confirm prompt is no protection here.
case "${tag}" in
	""|*/../*|../*|*/..|..|/*|*//*) [[ -z "${tag}" ]] || fErr "--tag names a published release, not a path (got '${tag}')." ;;
esac
[[ -z "${tag}" || "${tag}" =~ ^[A-Za-z0-9._/-]+$ ]] || fErr "--tag has characters that aren't valid in a git tag (got '${tag}')."

## Downloader: curl or wget, whichever exists.
if   command -v curl >/dev/null 2>&1; then fFetch(){ curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then fFetch(){ wget -qO- "$1"; }
else fErr "Need curl or wget."
fi

## Which asset belongs to this machine. Go's own spelling, since that is what the release
## is named by. Anything else falls through to the SHA256SUMS lookup below, which is the
## authority on what this release actually published.
goOs="$(fLower "$(uname -s 2>/dev/null || echo unknown)")"
case "${goOs}" in
	linux)   : ;;
	darwin)  : ;;
	freebsd) : ;;
	## Under Git Bash or Cygwin the destination is a Windows one, and nothing there puts it
	## on PATH. install.ps1 does both, so send Windows to the installer that finishes the job.
	mingw*|msys*|cygwin*|windows*)
		fErr "On Windows, use the PowerShell installer, which also puts the install directory on your PATH: irm https://raw.githubusercontent.com/${repo}/main/install.ps1 | iex" ;;
esac
if [[ -z "${arch}" ]]; then
	case "$(uname -m 2>/dev/null || echo unknown)" in
		x86_64|amd64)  arch="amd64" ;;
		aarch64|arm64) arch="arm64" ;;
		*)             arch="$(fLower "$(uname -m 2>/dev/null || echo unknown)")" ;;
	esac
fi
asset="gitsby-${goOs}-${arch}"

## No --tag: resolve the latest release from the releases/latest redirect (no auth, no API
## rate limit); unauthenticated API scrape only as fallback (60 req/hr per IP).
if [[ -z "${tag}" ]]; then
	## Every lookup here needs '|| true': under 'set -e' an assignment carries its command's
	## status, so a failed one takes the whole run out silently - past the fallback below and
	## past the message that explains it. wget is the surprising one: it answers a declined
	## redirect with exit 8 even though the header it was sent for is right there in the output.
	if command -v curl >/dev/null 2>&1; then
		tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null | sed -n 's|.*/releases/tag/||p' || true)"
	elif command -v wget >/dev/null 2>&1; then
		tag="$(wget -q --max-redirect=0 -S -O /dev/null "https://github.com/${repo}/releases/latest" 2>&1 | sed -n 's|.*[Ll]ocation: .*/releases/tag/\([^[:space:]]*\).*|\1|p' | head -n 1 || true)"
	fi
	## 'releases/latest' is defined as the newest release that is NOT a pre-release, so a repo
	## whose newest publication is one has nothing there to redirect to. That is the case this
	## fallback exists for - and it used to ask the same endpoint again over the API, which
	## fails identically. The list endpoint comes back newest-first, so the first entry marked
	## 'prerelease: false' is what the redirect would have found.
	if [[ -z "${tag}" ]]; then
		releaseList="$(fFetch "https://api.github.com/repos/${repo}/releases" 2>/dev/null || true)"
		## Commas and braces become newlines first, so every key sits on its own line whether
		## GitHub pretty-prints or packs the JSON on one line. Neither character can appear in
		## a tag name (checked below) or a boolean. Two BRE substitutions rather than one
		## alternation: '\|' is a GNU extension and this has to run under the sed macOS ships.
		#  shellcheck disable=2020  ## 'tr replaces sets of chars' - the duplicate newlines are deliberate: all three go to newline.
		releaseFacts="$(printf '%s\n' "${releaseList}" | tr ',{[' '\n\n\n' \
			| sed -n -e 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/T \1/p' \
			         -e 's/^[[:space:]]*"prerelease":[[:space:]]*\([a-z]*\).*/P \1/p' || true)"
		## Highest version wins, not newest-listed: the list is ordered by publish date, so a
		## backported fix cut after a newer release would otherwise resolve as latest. The
		## first three numeric fields decide; a tie keeps the earlier-listed (newer) entry.
		fPickTag(){
			awk -v wantPre="$1" '
				function vkey(t,  v,n,a,i,k) { v=t; sub(/^[vV]/,"",v); n=split(v,a,"[._-]"); k=""
					for (i=1;i<=3;i++) k = k sprintf("%09d", a[i]+0)
					return k }
				$1=="T"{t=$2}
				$1=="P" && t!="" && (wantPre=="any" || $2==wantPre) {
					if (vkey(t)>best) { best=vkey(t); bestT=t } }
				END{ if (bestT!="") print bestT }'
		}
		tag="$(printf '%s\n' "${releaseFacts}" | fPickTag false || true)"
		if [[ -z "${tag}" ]]; then
			tag="$(printf '%s\n' "${releaseFacts}" | fPickTag any || true)"
			[[ -z "${tag}" ]] || fEcho "No full release yet; taking the newest pre-release, ${tag}."
		fi
	fi
	[[ -n "${tag}" ]] || fErr "Couldn't work out the latest release of ${repo}. GitHub may be unreachable, or rate-limiting this address (60 requests an hour, unauthenticated). A specific release always works: --tag TAG."
	## Scraped from a redirect header, so check it the same way as a typed one before it reaches a URL.
	[[ "${tag}" =~ ^[A-Za-z0-9._/-]+$ ]] || fErr "The resolved release tag ('${tag}') isn't a plain git tag; aborting."
fi

## sha256 tool, before anything is promised. Every install path here is a release asset, so
## every one of them is verified - there is no unverified route to fall back to, and finding
## the tool missing after the plan has been agreed to would be finding it too late.
if   command -v sha256sum >/dev/null 2>&1; then fSha256(){ sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum    >/dev/null 2>&1; then fSha256(){ shasum -a 256 "$1" | cut -d' ' -f1; }   ## macOS
elif command -v openssl   >/dev/null 2>&1; then fSha256(){ openssl dgst -sha256 "$1" | sed 's/.*= *//'; }
else fErr "No sha256 tool here (need sha256sum, shasum or openssl), so the download can't be verified. Install one and re-run."
fi

## SHA256SUMS decides two things at once, and it is a few hundred bytes: whether this release
## publishes a binary for this platform, and what that binary should hash to. Fetching it up
## front means the plan can promise a specific file, before anything large is downloaded.
base="https://github.com/${repo}/releases/download/${tag}"
sums="$(fFetch "${base}/SHA256SUMS" 2>/dev/null || true)"
[[ -n "${sums}" ]] || fErr "Release ${tag} publishes no SHA256SUMS, so nothing here can be verified. (A release published seconds ago may not be servable yet; try again shortly.)"
want="$(printf '%s\n' "${sums}" | sed -n "s/^\([0-9a-f]\{64\}\)[[:space:]]*\*\{0,1\}${asset}\$/\1/p" | head -n 1)"
if [[ -z "${want}" ]]; then
	echo "Error: release ${tag} publishes no gitsby binary for ${goOs}/${arch}." >&2
	published="$(printf '%s\n' "${sums}" | sed -n 's/^[0-9a-f]\{64\}[[:space:]]*\*\{0,1\}gitsby-//p' | sed 's/\.exe$//' | paste -sd, - | sed 's/,/, /g')"
	[[ -n "${published}" ]] && echo "  It publishes: ${published}" >&2
	echo "  Build it for yours instead - the module is pure Go with no dependencies:" >&2
	echo "    git clone https://github.com/${repo}.git && cd gitsby/src-go && go build -o gitsby ." >&2
	exit 1
fi

destDir="${HOME}/.local/bin"; needSudo=0
if [[ ${doSystem} -eq 1 ]]; then
	destDir="/usr/local/bin"
	[[ -w "${destDir}" ]] || needSudo=1
fi

echo
fEcho "gitsby installer"
echo "This will:"
echo "  - Download ${asset} (${tag}) from github.com/${repo}"
echo "  - Verify it against the release's published SHA256SUMS"
echo "  - Install it to ${destDir}/gitsby"
[[ -d "${destDir}" ]] || echo "  - Create ${destDir} (it doesn't exist yet)"
[[ ${needSudo} -eq 1 ]] && echo "  - Use sudo for the install step (you may be prompted for your password)"
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
staged=""
trap 'rm -f -- "${tmpFile:?}"; [[ -z "${staged}" ]] || rm -f -- "${staged:?}" 2>/dev/null || true' EXIT

echo
fEcho "Downloading ..."
fFetch "${base}/${asset}" > "${tmpFile}" || fErr "Couldn't download ${asset} from release ${tag}."
[[ -s "${tmpFile}" ]] || fErr "Downloaded ${asset} is empty; aborting."
## A captive portal or a proxy answers with a page, not a binary. It would fail the checksum
## anyway, but as tampering rather than as the network problem it is.
case "$(head -c 1 "${tmpFile}")" in
	'<') fErr "The download came back as a web page, not a binary - something between here and GitHub is intercepting it." ;;
esac

got="$(fSha256 "${tmpFile}")"
[[ "${got}" = "${want}" ]] || fErr "Checksum mismatch for ${asset}; aborting. (Corrupted download or tampering.)"
fEcho "Checksum verified."

echo
fEcho "Installing to ${destDir}/gitsby ..."
## Staged beside the target and renamed over it, never written in place. Two things that
## buys: an interrupt mid-copy leaves the staged file half-written rather than the real one,
## and a rename replaces a copy that is currently running, where a write to it fails. The
## staging file has to be in the destination directory - a rename is only atomic within one
## filesystem, and the temp dir is usually on another.
staged="${destDir}/.gitsby.install.$$"
if [[ ${needSudo} -eq 1 ]]; then
	## mkdir -p, not 'install -d': on a directory that already exists, install resets its mode,
	## and this branch is reached whenever /usr/local/bin exists but isn't writable by us.
	sudo mkdir -p "${destDir}"
	sudo install -m 755 "${tmpFile}" "${staged}"
	sudo mv -f "${staged}" "${destDir}/gitsby"
else
	mkdir -p "${destDir}"
	install -m 755 "${tmpFile}" "${staged}"
	mv -f "${staged}" "${destDir}/gitsby"
fi
staged=""

echo
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
##		- 20260819 JC: Installs the binary for this platform. --arch is real (it picks the asset) and --target is unchanged; --release is gone, since a branch has no build behind it. Every route is a release asset now, so every route is verified and the unverified branch of the plan no longer exists. SHA256SUMS is fetched before the plan is printed, because it is what says whether this platform has a binary at all. Windows is sent to install.ps1, which is the one that also handles PATH.
##		- 20260819 JC: The release lookup no longer takes the run out with it. Under 'set -e' an assignment carries its command's status, so a curl that failed - or a wget that answered a declined redirect with exit 8, having already printed the very header it was sent for - ended the install silently, past the fallback and past the message that explains it.
##		- 20260819 JC: The release fallback is one. Both routes asked releases/latest, which GitHub defines as the newest release that is NOT a pre-release - so on a repo whose newest publication is one, the fallback failed in exactly the way the primary had, and blamed rate limiting for it. The list endpoint answers instead, newest first, preferring a full release and saying so when only a candidate exists.
##		- 20260819 JC: The binary is staged in the destination directory and renamed over the target. Written in place, an interrupt mid-copy left a truncated executable that had passed its checksum under another name, and re-installing over a copy that was running failed outright. --help lists every option the parser accepts.
