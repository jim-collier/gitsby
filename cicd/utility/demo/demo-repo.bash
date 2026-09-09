#!/usr/bin/env bash

##	Purpose:
##		- Builds a throwaway, fully anonymized world for the demo gif: two git repos in
##		  two separate folder trees, a local bare "origin", and a gitsby config file that
##		  gives each tree its own GitHub account. The scenario beside this file drives
##		  real gitsby commands against it, so nothing about the demo can go stale.
##		- Everything is generic: a /tmp path with no username, a fake HOME + gitconfig,
##		  a made-up author, and pinned commit dates. Pinned dates keep commit hashes (and
##		  thus gitsby's output, and thus the gif bytes) identical run to run, so cicd only
##		  regenerates the gif when the demo actually changes.
##		- Writes "$root/demo.env" holding the env the scenario steps source before each
##		  gitsby call.
##	Syntax: demo-repo.bash [ROOT]   (ROOT default: /tmp/gitsby-demo)
##	History: At bottom of script.

##	Copyright (c) 2026 Bubbles
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -eu; set -o pipefail

root="${1:-/tmp/gitsby-demo}"

##	HOME is the root itself, so the paths the demo prints and the "~/..." in its prompt
##	are the same place - the folder rules below are the point of the demo, and they read
##	as a lie if the two disagree.
##	The two trees differ from the first folder down ("dev" vs "code"). That is deliberate:
##	the account rules match on "github.com/<owner>" alone, so a demo whose trees shared a
##	root would not show that the match is a run of folder names anywhere in the path.
work="${root}/dev/github.com/acme-corp/acme-api"
side="${root}/code/github.com/mika-rivers/dotfiles"
bare="${root}/acme-api-origin.git"

##	Generic identity + fixed dates. Same values for every commit -> reproducible hashes.
##	A local-path remote means gitsby never runs ssh -G, so no real ssh/login identity
##	can leak into the rendered output.
export HOME="${root}"
export XDG_CONFIG_HOME="${root}/.config"
export GIT_CONFIG_GLOBAL="${root}/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_DATE="2026-01-15T10:00:00 +0000"
export GIT_COMMITTER_DATE="2026-01-15T10:00:00 +0000"

##	Who each tree's account commits as. The demo's whole claim is that the folder picks
##	these, so they must NOT be exported into the scenario's environment - see demo.env
##	at the bottom, which deliberately unsets them.
acmeName="Mika Rivers";  acmeEmail="mika@acme.example"
sideName="Mika Rivers";  sideEmail="mika@example.com"

##	ROOT is the only caller-supplied path in the tree that gets removed recursively, so it has to
##	prove it is ours first. The stamp is written below, right after the directory is made, so any
##	run that got far enough to create anything is recognized on the next one. A mistyped or
##	inherited ROOT costs an error message instead of whatever was living there.
stamp="${root}/.gitsby-demo-root"
[[ -n "${root}" && "${root}" == /* && "${root}" != "/" && "${root}" != */.. && "${root}" != *..* ]] \
	|| { echo "demo-repo: ROOT must be a plain absolute path below the filesystem root; got '${root}'." >&2; exit 1; }
if [[ -e "${root}" ]]; then
	##	A root built before the stamp existed is still recognizably ours - nothing else puts a
	##	demo.env beside an acme-api-origin.git. Without that second reading, the first run after
	##	this guard landed would refuse the directory the previous run had made itself.
	ours=0
	if [[ -d "${root}" && ! -L "${root}" ]]; then
		if   [[ -f "${stamp}" ]]; then                             ours=1
		elif [[ -f "${root}/demo.env" && -d "${bare}" ]]; then      ours=1
		fi
	fi
	if ((ours == 0)); then
		echo "demo-repo: '${root}' exists and this script did not build it; remove it by hand if that is what you meant." >&2
		exit 1
	fi
	rm -rf -- "${root:?}"
fi
mkdir -p "${root}" "${work}" "${side}" "${XDG_CONFIG_HOME}/gitsby"
: > "${stamp}"

##	The global identity is the fallback the account rules override. It matches the personal
##	account on purpose: the work tree's author line then differs only because the folder said so.
cat > "${GIT_CONFIG_GLOBAL}" <<-EOF
	[user]
		name = ${sideName}
		email = ${sideEmail}
	[init]
		defaultBranch = main
	[advice]
		detachedHead = false
EOF

##	Fake tokens. Their content is never read by anything the demo runs - a local-path remote
##	needs no credentials - but their presence is what makes gitsby report the account as
##	APPLIED rather than merely resolved, which is the state a real user would be in.
printf 'gho_demo000000000000000000000000000000000\n' > "${XDG_CONFIG_HOME}/gitsby/acme.token"
printf 'gho_demo111111111111111111111111111111111\n' > "${XDG_CONFIG_HOME}/gitsby/personal.token"
##	0600, because gitsby warns about a token anyone else can read and the demo would otherwise
##	spend a line of every scene saying so about its own fixture.
chmod 600 "${XDG_CONFIG_HOME}/gitsby"/*.token

##	A stub gh, first on PATH. Two reasons, and the second is the important one:
##	  - gitsby asks GitHub whose token a tokenFile holds. A made-up token gets no answer, so
##	    every scene carried a line saying the token could not be checked.
##	  - the real gh would have answered as whoever is logged in on the rendering machine, which
##	    is a real name in a deliberately anonymized demo.
##	It answers only the two calls the scenario reaches and fails everything else, so a command
##	that grew a new gh call shows up as a visible failure rather than a plausible fake answer.
mkdir -p "${root}/bin"
cat > "${root}/bin/gh" <<-'EOF'
	#!/usr/bin/env bash
	case "$*" in
		"api user --jq .login")
			case "${GH_TOKEN:-}" in
				gho_demo000*) echo "mika-at-acme" ;;
				gho_demo111*) echo "mika-rivers"  ;;
				*)            exit 1 ;;
			esac ;;
		"config get -h github.com git_protocol") echo https ;;
		*) echo "demo gh stub: no answer for 'gh $*'" >&2; exit 1 ;;
	esac
EOF
chmod 755 "${root}/bin/gh"

##	The file the demo cats on camera. Kept short enough to read in one screen, and using
##	'pathcontains' rather than 'path' because a run of folder names is the thing being shown.
##	Spaces for the nesting: '<<-' strips every leading tab, the block structure with them.
cat > "${XDG_CONFIG_HOME}/gitsby/config.shcl" <<-EOF
	protocol: https

	account: acme
	    pathcontains: github.com/acme-corp
	    ghaccount: mika-at-acme
	    tokenfile: ~/.config/gitsby/acme.token
	    name: ${acmeName}
	    email: ${acmeEmail}

	account: personal
	    pathcontains: github.com/mika-rivers
	    ghaccount: mika-rivers
	    tokenfile: ~/.config/gitsby/personal.token
	    name: ${sideName}
	    email: ${sideEmail}
EOF

git init -q --bare "${bare}"

cd "${work}"
git init -q
printf 'name: acme-api\nport: 8080\n'          > config.yml
printf '# Acme API\n\nA small service.\n'       > README.md
git add -A
GIT_AUTHOR_NAME="${acmeName}" GIT_AUTHOR_EMAIL="${acmeEmail}" \
GIT_COMMITTER_NAME="${acmeName}" GIT_COMMITTER_EMAIL="${acmeEmail}" \
	git commit -qm "Initial commit"
git remote add origin "${bare}"
git push -q -u origin main

##	Leave one pending edit so `status` (and the branch/land flow) has something to show.
printf 'retries: 3\n' >> config.yml

##	The second tree. It only ever has `account` run in it, so one commit is enough - what
##	matters is that it is a real repo sitting under a different root.
cd "${side}"
git init -q
printf 'set -o vi\nalias gs="gitsby status"\n' > .bashrc-extra
git add -A
GIT_AUTHOR_NAME="${sideName}" GIT_AUTHOR_EMAIL="${sideEmail}" \
GIT_COMMITTER_NAME="${sideName}" GIT_COMMITTER_EMAIL="${sideEmail}" \
	git commit -qm "Initial commit"

##	Env the scenario steps source before each gitsby call. The unsets matter as much as the
##	exports: an inherited GIT_CONFIG_COUNT outranks every config file, an inherited GH_TOKEN
##	changes which account gitsby reports, and an inherited GIT_AUTHOR_* would silently supply
##	the identity the demo claims the folder rules are supplying.
##	The single quotes below are the point: these lines are written verbatim into demo.env and
##	expanded when the scenario sources it, not here.
# shellcheck disable=SC2016
{
	echo "export PATH='${root}/bin':\"\${PATH}\""
	echo "export HOME='${HOME}'"
	echo "export XDG_CONFIG_HOME='${XDG_CONFIG_HOME}'"
	echo "export GIT_CONFIG_GLOBAL='${GIT_CONFIG_GLOBAL}'"
	echo "export GIT_CONFIG_SYSTEM=/dev/null"
	echo "export GIT_TERMINAL_PROMPT=0"
	echo "export GIT_AUTHOR_DATE='${GIT_AUTHOR_DATE}'"
	echo "export GIT_COMMITTER_DATE='${GIT_COMMITTER_DATE}'"
	echo 'for i in $(seq 0 "${GIT_CONFIG_COUNT:-0}"); do unset "GIT_CONFIG_KEY_${i}" "GIT_CONFIG_VALUE_${i}"; done'
	echo 'unset i GIT_CONFIG_COUNT GH_TOKEN GH_CONFIG_DIR GITSBY_CONFIG GITSBY_ACCOUNT'
	echo 'unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_SSH_COMMAND'
} > "${root}/demo.env"


##	History:
##		- 20260724: v1.0. Anonymized offline repo builder for the demo gif.
##		- 20260814: Moved into cicd/utility/demo/, beside the scenario, the renderer and script.txt.
##		- 20260814: Builds two trees and a gitsby config, so the demo can show a folder deciding which account acts. HOME is the root, the trees differ from their first folder down, and demo.env now unsets the identity and config variables that would otherwise supply what the folder rules are meant to be supplying.
##		- 20260819: The fake tokens are 0600 and a stub gh goes first on PATH. Both were showing on camera: the permission warning on every scene, and the real gh answering as whoever is logged in on the machine doing the rendering.
##		- 20260813: ROOT is checked before it is removed. It was taken on trust and wiped first thing, so a mistyped or inherited argument cost whatever was there. Directories this script builds are stamped, and only a stamped one is removed.
