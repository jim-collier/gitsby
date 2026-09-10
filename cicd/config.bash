#!/usr/bin/env bash

#  shellcheck disable=2034  ## 'variable appears unused.' Everything here is consumed by cicd.bash after sourcing.

##	Purpose:
##		- Project-specific CI/CD settings for gitsby.
##		- The engine (cicd.bash) stays generic; everything project-specific lives here.
##		- To reuse the pipeline elsewhere, copy the cicd/ directory and edit this file.
##		- All paths are relative to the repo root; the engine cds there first.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


## Only allow running 'sourced'.
declare -i isSourced_t6wqf=0; [[ "${BASH_SOURCE[0]}" == "${0}" ]] || isSourced_t6wqf=1
((isSourced_t6wqf)) || { echo -e "\nError in $(basename "${BASH_SOURCE[0]}"): This script is meant to be 'sourced' from within another script.\n"; exit 1; }


## Identity
APP_NAME="gitsby"
EXE_NAME="gitsby"

## The Go module. Everything the pipeline builds and tests comes from here; the frozen
## script builds under legacy/ are reference only and no stage touches them except parity.
GO_MODULE_DIR="src-go"

## Build flags, in one place because four build sites have to agree on them.
##   -trimpath      keeps the build machine's directory names out of the binary.
##   -buildvcs=false keeps the repository's revision and dirty flag out of it. Without this
##                  the published assets carry whatever commit preceded the tag they claim -
##                  so nobody, including us, can rebuild them to the checksums we publish.
##   -buildid=      drops the last input-derived stamp, so identical source gives identical
##                  bytes on any machine with the same toolchain (pinned in go.mod).
##   -s -w          no symbol table, no DWARF: smaller is one of the two things that matter.
## CGO_ENABLED=0 goes with them, on the native build as well as the cross-builds, so every
## artifact the pipeline produces is the same kind of thing.
GO_BUILD_FLAGS=(-trimpath -buildvcs=false)
GO_LDFLAGS_COMMON="-s -w -buildid="
## The toolchain that builds the published assets. Two compiler versions produce different
## bytes from the same source, so reproducing a release means naming the one that cut it -
## and go.mod's 'go' line is a minimum, not a pin. Release builds only: a dev build should
## follow whatever is installed.
GO_RELEASE_TOOLCHAIN="go1.26.2"

## The versions the Go tools were at when this pipeline last gated a green run. Recorded,
## compared and warned about - never installed and never enforced. Which version passed
## something is worth knowing: a finding that appears out of nowhere on an unchanged tree
## is usually a tool that moved rather than code that did, and a machine two years behind
## reports clean for the opposite reason. Read with 'go version -m', which answers for any
## Go-built binary - the four of them spell '--version' four different ways, and one has no
## such flag at all. The toolchain itself is GO_RELEASE_TOOLCHAIN above.
GO_TOOL_VERSIONS=(
	"staticcheck=v0.7.0"
	"golangci-lint=v2.12.2"
	"govulncheck=v1.5.0"
	"goversioninfo=v1.5.0"
)

## Half the cores, rounded up. The compiler takes all of them by default, in every build and
## in the eight-target release loop, which makes the machine unusable for the duration.
BUILD_JOBS=$(( ( $( nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2 ) + 1 ) / 2 ))

## Stage 1: lint. Go first (gofmt is the arbiter of format, vet and staticcheck gate),
## then every first-party shell file (globs, expanded by the engine). shellcheck is
## gating; there is deliberately NO bash formatter stage - the pipeline's own scripts are
## hand-formatted on purpose. Markdown is probe-gated (markdownlint if installed); the .py
## just gets a compile check. legacy/ is deliberately absent from every glob: it is frozen,
## so a newer shellcheck finding there is noise nobody is allowed to fix.
SHELL_LINT_GLOBS=(
	"install.bash"
	"cicd/*.bash"
	"cicd/utility/*.bash"
	"cicd/utility/n8git_backup-and-publish"
	"cicd/utility/include/*.bash"
	"cicd/utility/demo/*.bash"
)
## Report-only (findings warn, never gate). Empty since the bin/gitsby refactor.
SHELL_LINT_WARN_GLOBS=()
MD_LINT_GLOBS=(
	"*.md"
	"legacy/*.md"
	"project/*.md"
	"project/design_docs/*.md"
)
PY_LINT_FILES=(
	"cicd/utility/demo/gen-demo-gif.py"
)
## PowerShell (probe-gated: needs pwsh + the PSScriptAnalyzer module). Back after the
## scripted build was frozen: the installer is the one piece of PowerShell that still
## ships, because it is the only shell every Windows box already has.
PS_LINT_GLOBS=(
	"install.ps1"
)

## Stage 1: the committed Windows resource (icon + version details), checked rather than built.
## It is linked into the .exe files we publish checksums for, so it lives in the tree the same
## way the source does - see the script's header for why it can't be generated at build time.
## Probe-gated on goversioninfo; release.bash regenerates it with the version bump.
WINRES_CMD=(cicd/utility/gen-winres.bash)

## Stage 1: backlog rules. Open review items carry an "Origin:" line, and a suite check
## removed on the branch is named in the backlog. See the script's header for why.
BACKLOG_CHECK_CMD=(cicd/utility/backlog-check.bash)

## Stage 2: build + regression tests. The suite runs against the compiled binary and gates.
TEST_CMD=(cicd/test.bash)

## Stage 3: fuzz + security (adversarial input against gitsby's own command/option/
## arg surface, with an injection canary). Skipped by --quick.
FUZZ_CMD=(cicd/fuzz.bash)

## Stage 3b: backwards compatibility. Same input to the Go build and to the frozen v2.1.0
## script under legacy/, answers compared byte for byte wherever the two still claim to be
## the same command. Skipped by --quick; self-skips when legacy/ is gone.
PARITY_CMD=(cicd/parity.bash)

## Full run output is tee'd here (gitignored) so warnings from any stage can be
## reviewed after the fact with utility/lint-report.bash. GFS-rotated: keeps ~30 -
## first + newest-per-hour/day/week/month/year + last 10 (GFS_KEEP_* to tune).
LINT_LOG_DIR="cicd/artifacts/lint"          # relative to repo root; created if missing (gitignored)

## Stage 3b: spawn counts. One row per command, GFS-rotated the same way; the newest previous
## run is the baseline the next one is compared against.
SPAWN_COUNT_DIR="cicd/artifacts/spawn"      # relative to repo root; created if missing (gitignored)
SPAWN_COUNT_CMD=(cicd/utility/spawn-count.bash)

## Where a kept build is archived, for bisecting a behavior change against an older one.
KEEP_BUILD_DIR="cicd/artifacts/builds"      # relative to repo root; created if missing (gitignored)

## Stage 4: dogfood. Build each target and copy it to the first existing, writable dir in
## that target's list. Cross-building is free here - the module is pure stdlib with no cgo -
## so every target is built every run rather than on a cadence. Destination arrays are found
## by name: DOGFOOD_DESTS_<GOOS>_<GOARCH>, upper-cased.
DOGFOOD_TARGETS=(
	"linux/amd64"
	"windows/amd64"
	"darwin/arm64"
)
## What --quick narrows the list above to. Cross-building the other two is the slow part of
## a run; this one is the binary the next hand-run picks up, so it stays.
DOGFOOD_NATIVE_TARGET="linux/amd64"
DOGFOOD_DESTS_LINUX_AMD64=(
	"${HOME}/synced/0-0/common/exec/util/linux/bin"
)
## Two spellings of one share: the path as this box mounts it, and the path Windows mounts
## it at. Whichever exists is the one running. cli, not gui - gitsby is a terminal program.
DOGFOOD_DESTS_WINDOWS_AMD64=(
	"${HOME}/synced/0-0/common/exec/util/mswin/cli/by-self/win64"
	"C:/opt/0-0/common/exec/synced/util/mswin/cli/by-self/win64"
)
## One macOS slot, so one target: arm64. A universal binary would need lipo, which only
## exists on a Mac, and there is no second destination to justify it. The share mounts at
## the same spelling from Linux and from macOS, so one entry covers both.
DOGFOOD_DESTS_DARWIN_ARM64=(
	"${HOME}/synced/0-0/common/exec/util/macos/bin"
)

## Last resort when none of the shared dirs above exist - the same dir install.bash uses by
## default. Only appended to the target that matches the box doing the build: a .exe has no
## business in a Linux ~/.local/bin, and it would match there every time.
DOGFOOD_FALLBACK_DIR="${HOME}/.local/bin"

## Release assets (cicd/release.bash). Every platform the module cross-builds to, which is
## every platform Go targets - the tree is pure stdlib with no cgo, so nothing here needs an
## SDK or a machine of its own. Published as gitsby-<goos>-<goarch>, with .exe on Windows,
## alongside a SHA256SUMS over the set.
RELEASE_TARGETS=(
	"linux/amd64"
	"linux/arm64"
	"windows/amd64"
	"windows/arm64"
	"darwin/amd64"
	"darwin/arm64"
	"freebsd/amd64"
	"freebsd/arm64"
)

## Stage 5: demo gif. Types the scenario's command into a fake terminal, runs it
## against the dogfooded binary (in a throwaway anonymized repo the scenario
## builds), renders the 960x540 animated loop (hard-cut boundary). Seeded + pinned
## commit dates, so an unchanged binary + scenario reproduces the same file byte
## for byte (the optimizer below is deterministic too, though its version counts).
## Skipped by --quick / --no-demogif; self-skips if the scenario is absent.
DO_DEMOGIF=1
DEMOGIF_SCENARIO="cicd/utility/demo/demo-scenario.toml"
DEMOGIF_CMD=(cicd/utility/demo/gen-demo-gif.py --scenario "${DEMOGIF_SCENARIO}")
DEMOGIF_OUT="assets/demo.gif"                # in-repo copy the README embeds
DEMOGIF_ARCHIVE_DIR="../private/demo/gif"    # out-of-tree originals, GFS-rotated
## Lossless squeeze, when the tool is around; skipped silently if not. Worth
## about 9% - the renderer already crops each frame to what changed, so most of
## the win is banked. Stays before the compare, so the committed file is the
## optimized one. Lossy modes buy almost nothing on a 35-color text demo.
DEMOGIF_OPT_CMD=(gifsicle -O3)

## Stage 6: backup + publish to git (runs from repo root). The engine always
## passes --quiet (it already gave the message prompt) and, when it has one,
## -m MESSAGE.
GIT_PUBLISH=(cicd/utility/n8git_backup-and-publish)

## Set a non-empty commit message to publish hands-off (suppresses the prompt and
## supplies the message so `git commit` won't open an editor). Left empty, publish
## prompts once at preflight unless -m/--message or -q is given (see cicd.bash).
PUBLISH_AUTO_MESSAGE=""


##	History:
##		- 2026-07-22 JC: Created.
##		- 2026-08-18 JC: Go-specific. The scripts moved to legacy/ and left the lint globs with them; dogfood builds three targets instead of copying one script; parity became a stage, comparing the Go build against the frozen one.
##		- 2026-08-19 JC: WINRES_CMD: the Windows resource check joins stage 1, and release.bash regenerates the resource with the version bump.
##		- 2026-08-19 JC: GO_TOOL_VERSIONS: the lint and audit tools ran at whatever version the box had, so a finding could appear or vanish with no change to the tree. Recorded and compared in stage 1, as a warning.
##		- 2026-08-19 JC: The installer is back at the repo root, so its two files are linted again - the root install.bash under shellcheck, install.ps1 under a restored PSScriptAnalyzer glob. FreeBSD joins the release matrix, since it cross-builds for free and the installer would otherwise have nothing to offer a BSD.
##		- 2026-09-10 JC: BACKLOG_CHECK_CMD joins stage 1.
