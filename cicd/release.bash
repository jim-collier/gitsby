#!/usr/bin/env bash

#  shellcheck disable=1091  ## 'source is valid here, but shellcheck doesn't know the path to it.'

##	Purpose:
##		- Cuts a release end to end, so the steps that have been forgotten by hand
##		  cannot be. 'gitsby release' already does the git half well; this is
##		  everything around it.
##		- Three phases, so a failure never leaves a half-cut release:
##		   1. Prepare and verify. Runs the pipeline and cross-builds every release
##		      binary. Changes nothing outside the working tree, and nothing here
##		      needs undoing if it stops.
##		   2. Land. Writes the version, lands it through a PR, and calls
##		      'gitsby release'. The only phase that pushes.
##		   3. Publish and prove. Creates the GitHub release, uploads the binaries
##		      built in phase 1 and their checksums, then fetches one back and runs
##		      it - the result as a user would meet it.
##	Syntax:
##		cicd/release.bash [VERSION] [options]
##		  VERSION          e.g. v2.1.0. Omitted, the changelog's vNEXT heading and
##		                   'gitsby release' decide between them.
##		  -n, --dry-run    Say what each phase would do, change nothing. Use this.
##		  -y, --yes        Don't ask before phase 2.
##		  -q, --quiet      -y, and the pipeline run in phase 1 runs quiet too.
##		  -h, --help       This.
##	Notes:
##		- Refuses unless the tree is clean and you are on the merge target.
##		- The version lives in the tag and nowhere else. The binary carries it
##		  because the release build injects it, so there is no in-source version
##		  to bump and nothing that can disagree with the tag.
##		- Guards that have caught real mistakes: the harnesses must carry a
##		  history-footer entry newer than the last release tag, and the changelog
##		  must have a real vNEXT section rather than the decoy template heading.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/config.bash"      ## RELEASE_TARGETS, GO_MODULE_DIR, EXE_NAME
cd "${root}"

version=""; dryRun=0; assumeYes=0; quiet=0
while (($#)); do case "$1" in
	-n|--dry-run) dryRun=1; shift ;;
	-y|--yes)     assumeYes=1; shift ;;
	-q|--quiet)   quiet=1; assumeYes=1; shift ;;
	-h|--help)    sed -n '/^##	- Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	-*)           echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
	*)            version="$1"; shift ;;
esac; done

fEcho(){       echo "[ $* ]"; }
fEcho_Clean(){ echo "$*"; }
fDie(){        echo "FAILED: $*" >&2; exit 1; }
fWould(){      ((dryRun)) && { echo "   would: $*"; return 0; }; return 1; }

## Cross-build every release target into ${assets} and checksum them. Called twice: in phase 1
## as a compile gate, where a target that stopped building costs nothing, and again in phase 3
## from the tagged commit - that second run produces the bytes that get uploaded. Two runs
## because the build number comes from the commit's own date, and the tag does not exist yet
## when phase 1 runs. Anyone checking out the tag and building gets the published bytes back.
fpCrossBuild(){
	local epoch="$1" t asset
	crossBuildFailed=""
	for t in "${RELEASE_TARGETS[@]}"; do
		asset="${EXE_NAME}-${t%%/*}-${t##*/}"; [[ "${t}" == windows/* ]] && asset="${asset}.exe"
		( cd "${root}/${GO_MODULE_DIR}" && CGO_ENABLED=0 GOTOOLCHAIN="${GO_RELEASE_TOOLCHAIN}" GOOS="${t%%/*}" GOARCH="${t##*/}" \
			go build "${GO_BUILD_FLAGS[@]}" -p "${BUILD_JOBS}" \
			-ldflags "${GO_LDFLAGS_COMMON} -X main.version=${version#v} -X main.buildEpoch=${epoch}" \
			-o "${assets}/${asset}" . ) \
			|| { crossBuildFailed="${t}"; return 1 ;}
	done
	( cd "${assets}" && "${here}/utility/gen-checksums.bash" > SHA256SUMS )
}

## The build this release publishes, and the tool this script drives git and gh with. The
## pipeline in phase 1 rebuilds it; it has to exist before that, since phase 1 uses it too.
gitsby="${root}/${GO_MODULE_DIR}/${EXE_NAME}"; [[ -x "${gitsby}" ]] || gitsby="${gitsby}.exe"
changelog="${root}/changelog.md"

## changelog.md opens with a commented-out template whose headings are shaped exactly like real
## ones, so a first-match search finds the decoy and not the section it meant. That has caused
## three separate bugs here, the last of which would have retitled the template, published an
## empty release body and warned about none of it. Two independent guards now: the template's
## heading is spelled TEMPLATE_vNEXT, and everything below starts reading past the '-->'.
fpChangelogStart(){
	## First line of the real changelog, just past the commented-out template.
	## awk rather than grep piped into head - a pipe would leave pipefail at the mercy of SIGPIPE.
	local -i end=0
	end="$(awk '/^-->/{print NR; exit}' "${changelog}")"
	echo $((end + 1))
:;}

fpChangelogVnext(){
	## Line the real '## vNEXT' heading sits on, or nothing at all.
	local -i start; start="$(fpChangelogStart)"
	awk -v start="${start}" 'NR>=start && /^## vNEXT/{print NR; exit}' "${changelog}"
:;}

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Phase 1: prepare and verify. Nothing here changes anything outside the working tree, so a
## failure costs nothing and needs no undoing.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
fEcho "Phase 1: prepare and verify"

[[ -x "${gitsby}" ]] || fDie "no build at ${GO_MODULE_DIR}/${EXE_NAME} - run cicd/cicd.bash, or 'go build' there."
command -v go >/dev/null 2>&1 || fDie "the go toolchain is needed to build the release assets."
command -v gh >/dev/null 2>&1 || fDie "gh is needed to publish the release."
## The Windows resource is regenerated for the version being cut, so the tool is required here
## rather than probe-gated the way the pipeline has it. Refusing now costs nothing; discovering
## it in phase 2 would leave a pushed bump behind a .exe still claiming the old version.
winres=("${here}/utility/gen-winres.bash"); winresStatus=0
"${winres[@]}" --check -q >/dev/null 2>&1 || winresStatus=$?
## 3 is "no goversioninfo". A stale resource is 1, which is fine here - phase 2 regenerates it.
((winresStatus != 3)) || fDie "goversioninfo is needed to stamp the Windows binaries (see ${winres[0]##*/} --help)."

## The last release, for the guards below. The version itself comes from the tag this cuts, not
## from anything in the tree - there is no longer a string in a source file that can disagree.
lastTag="$(git -c versionsort.suffix=- tag --sort=-v:refname --list 'v*' | head -n 1)"

## The changelog has to have something to release. 'vNEXT' is this project's convention for
## "landed but not cut", and releasing with no such section means the notes would be empty.
[[ -n "$(fpChangelogVnext)" ]] || fDie "changelog has no '## vNEXT' section, so there is nothing to release."

## Where the version comes from: the argument, else the same bump 'gitsby release' would choose.
if [[ -z "${version}" ]]; then
	[[ -n "${lastTag}" ]] || fDie "no v* tag to bump from; pass a version explicitly."
	if [[ "${lastTag}" == *-* ]]; then
		## A candidate promotes to its own plain version rather than bumping past it.
		version="${lastTag%%-*}"
	else
		IFS='.' read -r major minor patch <<< "${lastTag#v}"
		version="v${major}.${minor}.$((patch + 1))"
	fi
	fEcho_Clean "no version given; the next one after ${lastTag} is ${version}"
fi
[[ "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([A-Za-z0-9.-]+)?$ ]] || fDie "'${version}' is not a vX.Y.Z version."
git rev-parse -q --verify "refs/tags/${version}" >/dev/null && fDie "tag ${version} already exists."

## The history footers are maintained by hand and are missed most rounds, so check rather than
## trust. The two builds that used to carry one are frozen; what is left is the harnesses.
lastTagForFooter="${lastTag}"
if [[ -n "${lastTagForFooter}" ]]; then
	for f in "${here}/test.bash" "${here}/fuzz.bash"; do
		newest="$(grep -oE '^##[[:space:]]+- 20[0-9]{6}' "${f}" | grep -oE '20[0-9]{6}' | sort | tail -n 1)"
		tagDate="$(git log -1 --format=%cd --date=format:%Y%m%d "${lastTagForFooter}" 2>/dev/null || echo 0)"
		[[ -n "${newest}" && "${newest}" -ge "${tagDate}" ]] \
			|| fEcho_Clean "WARNING: ${f##*/} has no history entry since ${lastTagForFooter} (${tagDate}); add one before releasing."
	done
fi

## State: clean tree, on the merge target, nothing unpushed.
[[ -z "$(git status --porcelain)" ]] || fDie "working tree isn't clean."
branch="$(git rev-parse --abbrev-ref HEAD)"
target="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
[[ -n "${target}" ]] || fDie "branch '${branch}' has no upstream."
[[ -z "$(git log '@{u}..HEAD' --oneline)" ]] || fDie "branch '${branch}' has unpushed commits."

## One pipeline, everywhere. It used to be two engines picked by platform; the Windows one was a
## port of this file rather than a wrapper around it, and it retired with the scripts it mirrored.
pipeline=("${here}/cicd.bash" --no-publish -y -m "pre-release check")
((quiet)) && pipeline=("${here}/cicd.bash" --no-publish -q -m "pre-release check")
pipelineName="cicd/cicd.bash --no-publish"

## The whole pipeline, against the tree as it stands. This is the gate.
if ! fWould "run ${pipelineName}"; then
	fEcho_Clean "running the full pipeline before touching anything ..."
	"${pipeline[@]}" || fDie "the pipeline did not pass; nothing was changed."
fi

## Every release target, compiled here as a gate. A target that stopped building is a phase 1
## failure, which costs nothing; discovered in phase 3 it would leave a pushed tag with no
## release behind it. These are not the bytes that get published - phase 3 rebuilds them from
## the tagged commit, whose date the build number is taken from.
assets="$(mktemp -d)"
if ! fWould "cross-build ${#RELEASE_TARGETS[@]} targets at ${version}"; then
	fEcho_Clean "cross-building ${#RELEASE_TARGETS[@]} targets with ${GO_RELEASE_TOOLCHAIN} ..."
	## The .exe files have to carry ${version}, and the committed resource still says the last
	## one. Stamp it, build, then restore - phase 1 is the phase that changes nothing, and phase
	## 2 regenerates it for real, on the release branch, next to the changelog edit.
	"${winres[@]}" -q "${version}" || fDie "couldn't stamp the Windows resource; nothing has been changed."
	built=0
	fpCrossBuild "$(git -C "${root}" log -1 --format=%ct)" || built=$?
	## Put the stamp back whether that worked or not, so 'nothing has been changed' stays true
	## of the failure path as well.
	git -C "${root}" checkout -q -- "${GO_MODULE_DIR}"/*.syso || fDie "couldn't restore the Windows resource; check 'git status'."
	((built == 0)) || fDie "couldn't build or checksum ${crossBuildFailed:-the release assets}; nothing has been changed."
	fEcho_Clean "built: $(cd "${assets}" && echo *)"
fi

fEcho "Phase 1 OK: ${lastTag:-(no previous tag)} -> ${version}"

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Phase 2: land. The only phase that pushes.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
fEcho "Phase 2: land ${version}"
if ((! dryRun)) && ((! assumeYes)); then
	read -r -p "Cut ${version}? This pushes. [y/N] " answer < /dev/tty || answer=""
	[[ "${answer}" =~ ^([yY]|[yY][eE][sS])$ ]] || fDie "Aborted."
fi

today="$(date +%Y-%m-%d)"
relBranch="rel-${version#v}"
## The version bump goes in through a branch and a pull request, like everything else. Committing
## it straight to the merge target would be the one place this project pushes its own work there -
## exactly what the tool refuses to do for you, so the thing that cuts the release must not do it
## either. 'gitsby release' below is the only push to the default branch, and that push IS the
## release rather than a shortcut around one.
if ! fWould "branch ${relBranch}, retitle the changelog's vNEXT as '${version} - ${today}', and land it through a PR"; then
	"${gitsby}" -q br create "${relBranch}" || fDie "couldn't create ${relBranch}."
	## The changelog heading is the whole of it. Nothing in the tree records the version any more -
	## the build injects it from the tag - so this is the only file a release edits.
	## By line number, so the substitution cannot wander to a heading somewhere else in the file.
	clLine="$(fpChangelogVnext)"
	[[ -n "${clLine}" ]] || fDie "the changelog's '## vNEXT' heading went missing after phase 1."
	sed -i "${clLine}s/^## vNEXT.*$/## ${version} - ${today}/" "${changelog}"
	## And the Windows resource, which is the other thing in the tree that names a version. It
	## goes in the same commit, so the tag it is reachable from is the one it claims.
	"${winres[@]}" -q "${version}" || fDie "couldn't stamp the Windows resource; the branch is created but nothing is pushed."
	## gitsby's own 'pr create' rather than gh directly: it already knows this repo's merge target,
	## which is the one thing a hand-written --base can get wrong.
	prOut="$("${gitsby}" -q pr create "${version}" 2>&1)" || { echo "${prOut}" >&2; fDie "couldn't open the version-bump PR."; }
	prNum="$(printf '%s\n' "${prOut}" | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -n 1)"
	prNum="${prNum##*/}"
	[[ "${prNum}" =~ ^[0-9]+$ ]] || { echo "${prOut}" >&2; fDie "couldn't read a PR number out of 'pr create' output."; }
	fEcho_Clean "opened PR #${prNum} for the version bump"
	"${gitsby}" -q pr ok "${prNum}" || fDie "couldn't merge PR #${prNum}; the bump is pushed but nothing is tagged."
fi
if ! fWould "gitsby release ${version}"; then
	"${gitsby}" -q release "${version}" || fDie "'gitsby release' failed; the version commit is pushed but no tag was cut."
fi
fEcho "Phase 2 OK: ${version} tagged and pushed"

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Phase 3: publish and prove. A failure here is recoverable by hand and corrupts nothing.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
fEcho "Phase 3: publish and prove"

## The bytes people download, rebuilt now that the tag exists - their build number is the tagged
## commit's date, so checking out ${version} and building reproduces them.
if ! fWould "rebuild ${#RELEASE_TARGETS[@]} targets from the ${version} commit"; then
	fEcho_Clean "rebuilding ${#RELEASE_TARGETS[@]} targets from ${version} ..."
	fpCrossBuild "$(git -C "${root}" log -1 --format=%ct "${version}^{commit}")" \
		|| fDie "couldn't rebuild or checksum ${crossBuildFailed:-the release assets}; the tag is pushed but nothing is published."
	fEcho_Clean "built: $(cd "${assets}" && echo *)"
fi

## The release body is the changelog section, verbatim - the same words the repo already carries,
## plus the line the binary itself prints, so the notes and the download cannot disagree.
notes="$(mktemp)"; trap 'rm -f -- "${notes:?}"; rm -rf -- "${assets:?}"' EXIT
awk -v ver="## ${version} " -v start="$(fpChangelogStart)" \
	'NR>=start && index($0, ver)==1 {f=1; next} f && /^## /{exit} f' "${changelog}" > "${notes}" || true
[[ -s "${notes}" ]] || fEcho_Clean "WARNING: no changelog section found for ${version}; the release body will be empty."
nativeAsset="${EXE_NAME}-$(go env GOOS)-$(go env GOARCH)"; [[ "$(go env GOOS)" == windows ]] && nativeAsset="${nativeAsset}.exe"
buildLine=""
[[ -x "${assets}/${nativeAsset}" ]] && buildLine="$("${assets}/${nativeAsset}" --version 2>/dev/null | sed -n 's/^\('"${EXE_NAME}"' v[^,]*\),.*/\1/p')"
if [[ -n "${buildLine}" ]]; then
	printf '\n---\n\n%s\n' "${buildLine}" >> "${notes}"
else
	fEcho_Clean "WARNING: couldn't read a build number out of ${nativeAsset}; the notes will not name one."
fi

if ! fWould "gh release create ${version} with ${#RELEASE_TARGETS[@]} binaries and SHA256SUMS"; then
	"${gitsby}" -q raw gh release create "${version}" --title "${version}" --notes-file "${notes}" \
		"${assets}"/* || fDie "publishing the release failed; the tag is pushed, so re-run 'gh release create ${version}' by hand."
fi

## Prove it the way a user meets it, not by trusting the steps above: fetch the asset for THIS
## platform back off the published release, check it against the published SHA256SUMS, and run it.
## That is the whole contract - a download whose checksum matches and whose --version is right.
if ! fWould "verify releases/latest, then download and run this platform's published binary"; then
	latest="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/jim-collier/gitsby/releases/latest" 2>/dev/null | sed -n 's|.*/releases/tag/||p')"
	[[ "${latest}" == "${version}" ]] || fEcho_Clean "WARNING: releases/latest resolves to '${latest}', not ${version}."
	## Seconds after publication GitHub serves the tag but not yet the assets, and the installers
	## stop rather than quietly skip verification when SHA256SUMS can't be fetched - so a first
	## attempt can fail against a release that is perfectly good. It did on v2.1.0: the same check
	## passed unchanged minutes later, with elapsed time the only difference. Retry before saying
	## anything, or the one warning that would mean a broken release is the one nobody believes.
	## Whichever asset belongs to the machine running this.
	proveOs="$(go env GOOS)"; proveArch="$(go env GOARCH)"
	proveAsset="${EXE_NAME}-${proveOs}-${proveArch}"; [[ "${proveOs}" == windows ]] && proveAsset="${proveAsset}.exe"
	base="https://github.com/jim-collier/gitsby/releases/download/${version}"
	proved=0
	for attempt in 1 2 3; do
		((attempt > 1)) && { fEcho_Clean "not downloadable yet; giving GitHub a moment to serve the assets (attempt ${attempt}) ..."; sleep 20; }
		proveDir="$(mktemp -d)"
		if curl -fsSL -o "${proveDir}/${proveAsset}" "${base}/${proveAsset}" \
			&& curl -fsSL -o "${proveDir}/SHA256SUMS" "${base}/SHA256SUMS" \
			&& ( cd "${proveDir}" && grep -F " ${proveAsset}" SHA256SUMS | sha256sum --check --status ) \
			&& chmod +x "${proveDir}/${proveAsset}" \
			&& "${proveDir}/${proveAsset}" --version 2>/dev/null | grep -q "v${version#v}"; then
			proved=1
		fi
		rm -rf -- "${proveDir:?}"
		((proved)) && break
	done
	if ((proved)); then
		fEcho_Clean "${proveAsset}: downloaded, checksum verified, and reports ${version}"
	else
		fEcho_Clean "WARNING: ${proveAsset} did not download-verify-run as ${version} from the published release."
	fi
fi

echo
fEcho "Released ${version}"
echo

##	History:
##		- 20260812 JC: Created, to the three-phase shape in project/design.md. The version bump, the
##		  changelog heading, the release body, the assets and the after-the-fact verification were
##		  all by hand, and each has been missed at least once. Both guards here exist because the
##		  thing they check has already gone wrong: the two builds' version strings drifting, and the
##		  in-script history footers going a whole release without an entry.
##		- 20260818 JC: The release binaries are built in phase 1, with the pipeline, rather than after the tag is pushed. A target that stops compiling now fails where nothing has been changed; found in phase 3 it would have left a pushed tag with no release behind it.
##		- 20260819 JC: The Windows resource is stamped with the version being cut - for the phase 1 build, then restored, and again in phase 2 where it lands in the bump commit. It is the only file left in the tree that names a version.
##		- 20260818 JC: Go. The version lives in the tag alone now - the build injects it - so phase 2 no longer bumps a string in two source files and phase 1 no longer has two of them to disagree. Phase 3 cross-builds the whole target matrix and publishes one binary per platform. The proof stopped being 'run both installers': there is one implementation, and what a user actually meets is a download, its checksum, and whether the thing runs.
##		- 20260813 JC: All three readings of the changelog start below the commented-out template.
##		  Each took the first match, so each found the template's decoy heading instead: the guard
##		  passed with nothing to release, the retitle rewrote the template and left the real section
##		  saying vNEXT, and the release body came out as the empty template plus a stray '-->' -
##		  non-empty, so the warning that exists for this never fired. The retitle is line-addressed
##		  now, and the template's heading is spelled TEMPLATE_vNEXT so either guard would do alone.
##		- 20260814 JC: Runs the pipeline engine that belongs to the platform. It always ran the Bash
##		  one, which knows nothing about Windows, so the gate a release most depends on would have
##		  been the wrong pipeline on half the machines this project supports.
##		- 20260814 JC: The installer proof retries. Cutting v2.1.0 warned that the release wasn't
##		  installable when it was - GitHub was still serving the tag without its assets, and the
##		  installer stops rather than skip verification. A warning that fires on a good release is
##		  worse than none, because the next one is read the same way.
