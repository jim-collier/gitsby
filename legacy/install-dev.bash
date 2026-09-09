#!/usr/bin/env bash

##	Purpose:
##		- Sets up a gitsby development environment: clones the repo, checks out the
##		  'dev' branch, and checks (optionally installs) the dev tooling. Shows the
##		  plan and asks first. Meant for one-liner use:
##		      curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.bash | bash
##		  Flags go after 'bash -s --', e.g.:
##		      ... | bash -s -- ~/dev/gitsby -y
##		- Runs on bash 3.2+ (stock macOS bash), so no bash-4/5 features in here.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -eu; set -o pipefail

repo="jim-collier/gitsby"
destDir=""; doYes=0

fEcho(){ echo "[ $* ]"; }
fErr(){  echo "Error: $*" >&2; exit 1; }
fSyntax(){
	cat <<-EOF
	Usage: install-dev.bash [OPTIONS] [DIR]
	Clones the gitsby repo for development (dev branch) and checks the tooling.
	Arguments:
	  DIR              Where to clone to (default: ./gitsby).
	Options:
	  -y, --yes        Don't ask for confirmation.
	  -h, --help       This.
	EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-y|--yes)  doYes=1 ;;
		-h|--help) fSyntax; exit 0 ;;
		-*)        fErr "Unknown option: '$1' (try --help)." ;;
		*)         [[ -z "${destDir}" ]] || fErr "Only one DIR argument allowed."; destDir="$1" ;;
	esac
	shift
done
[[ -n "${destDir}" ]] || destDir="./gitsby"
[[ -e "${destDir}" ]] && fErr "'${destDir}' already exists; pick another DIR or remove it."

command -v git >/dev/null 2>&1 || fErr "git is required; install it first."

## Tooling used by the local cicd pipeline (cicd/cicd.bash). Only bash 4.4+ and git
## are required to run/hack on gitsby itself; the rest gate the pipeline stages.
missingPkgs=""; notes=""
## 4.4 is the floor: bin/gitsby sets inherit_errexit, which older bash rejects.
if [[ "${BASH_VERSINFO[0]}" -gt 4 || ( "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -ge 4 ) ]]; then :; else
	## macOS never replaces its 3.2, so name the fix instead of just the requirement.
	case "$(uname -s 2>/dev/null)" in
		Darwin)        bashHint=" - 'brew install bash', and put it ahead of /bin/bash on your PATH" ;;
		*BSD|DragonFly) bashHint=" - 'pkg install bash' (FreeBSD) or 'pkg_add bash' (OpenBSD)" ;;
		*)             bashHint="" ;;
	esac
	notes="${notes}  - bash 4.4+ (gitsby itself needs it; this installer doesn't)${bashHint}\n"
fi
command -v shellcheck >/dev/null 2>&1    || missingPkgs="${missingPkgs} shellcheck"
command -v python3    >/dev/null 2>&1    || missingPkgs="${missingPkgs} python3"
command -v markdownlint >/dev/null 2>&1  || notes="${notes}  - markdownlint (npm install -g markdownlint-cli)\n"

## Package manager for the optional auto-install (brew doesn't want sudo).
pkgCmd=""; pkgSudo="sudo"
if   command -v apt-get >/dev/null 2>&1; then pkgCmd="apt-get install -y"
elif command -v dnf     >/dev/null 2>&1; then pkgCmd="dnf install -y"
elif command -v pacman  >/dev/null 2>&1; then pkgCmd="pacman -S --noconfirm"
elif command -v zypper  >/dev/null 2>&1; then pkgCmd="zypper install -y"
elif command -v brew    >/dev/null 2>&1; then pkgCmd="brew install"; pkgSudo=""
fi

echo
fEcho "gitsby dev setup"
echo "This will:"
echo "  - Clone github.com/${repo} into '${destDir}' and check out the 'dev' branch"
if [[ -n "${missingPkgs}" ]]; then
	if [[ -n "${pkgCmd}" ]]; then
		echo "  - Offer to install missing dev tooling (${pkgSudo:+sudo }${pkgCmd}${missingPkgs})"
	else
		echo "  - Note missing dev tooling:${missingPkgs} (no known package manager found; install by hand)"
	fi
fi
[[ -n "${notes}" ]] && { echo "  - Also missing (install by hand if you want the full pipeline):"; printf "%b" "${notes}"; }
if [[ ${doYes} -eq 0 ]]; then
	answer=""
	## Same /dev/tty open-test as install.bash: -r isn't enough with no controlling terminal.
	if   [[ -t 0 ]];                  then read -r -p "Continue? [y/N] " answer
	elif { : </dev/tty; } 2>/dev/null; then read -r -p "Continue? [y/N] " answer </dev/tty
	else fErr "No terminal to confirm on; re-run with -y (e.g. '| bash -s -- -y')."
	fi
	case "${answer}" in y|Y|yes|Yes|YES) ;; *) echo "Aborted."; exit 1 ;; esac
fi

if [[ -n "${missingPkgs}" && -n "${pkgCmd}" ]]; then
	echo
	fEcho "Installing:${missingPkgs} ..."
	#  shellcheck disable=2086  ## Word-splitting of pkgCmd/missingPkgs is intended.
	${pkgSudo} ${pkgCmd} ${missingPkgs}
fi

echo
fEcho "Cloning ..."
git clone "https://github.com/${repo}.git" "${destDir}"
cd "${destDir}"
git checkout dev 2>/dev/null || echo "Note: no 'dev' branch on origin; staying on the default branch."

echo
fEcho "Verifying ..."
bin/gitsby --version

echo
fEcho "Done."
echo "Next steps:"
echo "  - Read contributing.md and style-guide.md"
echo "  - Run the local pipeline: cicd/cicd.bash --quick"
echo "  - Work on a short-named feature branch off 'dev'; PRs merge back to 'dev'"
echo


##	History:
##		- 20260722 JC: Created.
##		- 20260724 JC: Trailing blank line.
