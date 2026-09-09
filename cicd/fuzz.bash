#!/usr/bin/env bash

##	Purpose:
##		- Adversarial fuzz + injection-safety for gitsby's OWN input surface: the
##		  command slot, options, and branch/message/version/pr arguments. Not
##		  upstream git - just what a hostile or fat-fingered user can hand gitsby.
##		- Three invariants, checked per vector:
##		    1. No internal crash - no runtime error dump, exit stays a controlled 0/1.
##		    2. No shell/command injection - a canary side-effect never fires.
##		    3. Inputs that must be refused exit nonzero and leave the repo untouched.
##		- Run by cicd.bash stage 3 against the build from stage 2, or standalone after
##		  a 'go build' in src-go/. Hermetic: throwaway repos, no net.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-fuzz.XXXXXX")"
trap 'rm -rf -- "${work:?}"' EXIT

## Hermetic: no reliance on (or writes to) the user's git config, no prompts.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=fuzz GIT_AUTHOR_EMAIL=fuzz@fuzz
export GIT_COMMITTER_NAME=fuzz GIT_COMMITTER_EMAIL=fuzz@fuzz
export GIT_TERMINAL_PROMPT=0
## gitsby's own config decides which account a command acts as, so pin it the way test.bash does.
export GITSBY_CONFIG="${work}/no-accounts.shcl"; : > "${GITSBY_CONFIG}"

## Pinning the config FILES is not isolation on its own: GIT_CONFIG_COUNT/KEY_n/VALUE_n outrank
## every one of them, and an inherited GH_TOKEN is what the fake gh reports back. Both arrive
## from an ordinary working terminal, and neither shows up as a failure you can act on.
fUnsetInheritedGitConfig(){
	local -i i=0
	for (( i = 0; i < ${GIT_CONFIG_COUNT:-0}; i++ )); do unset "GIT_CONFIG_KEY_${i}" "GIT_CONFIG_VALUE_${i}"; done
	unset GIT_CONFIG_COUNT
}
fUnsetInheritedGitConfig
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_HOST GH_CONFIG_DIR GITSBY_ACCOUNT

## -q silences the per-check line and leaves the header, the failures and the total. A run
## of 600-odd checks buries every stage header in a pipeline log nobody watches live.
declare -i quiet=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		-q|--quiet) quiet=1; shift ;;
		-h|--help)  echo "Usage: $(basename "${BASH_SOURCE[0]}") [-q|--quiet]"; exit 0 ;;
		*)          echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
done

declare -i pass=0 fail=0
fOk(){   pass=$((pass+1)); ((quiet)) || echo "  ok: $*"; }
fFail(){ fail=$((fail+1)); echo "  FAIL: $*"; }

declare -i isWindows=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) isWindows=1 ;; esac

## An internal-error dump from either implementation. A clean validation refusal
## ("gitsby: <msg>", exit 1) matches none of these; an uncaught bash error, a
## non-0/1 exit dump, or a pwsh StrictMode/runtime fault does. The arg parser's
## "Reverse call stack:" line is a deliberate refusal, not a crash, so it's out.
_crashRe='unbound variable|: syntax error|bad substitution|command not found|integer expression expected|not a valid identifier|divide by zero|division by 0|bad array subscript|: line [0-9]+:|At line# |Command# \.\.\.|Err# \.\.\.|cannot be retrieved because it has not been set|Cannot index into a null|Attempted to divide by zero|Method invocation failed|Unable to find type'

_out=""; declare -i _code=0
## Run gitsby in a directory with the given args verbatim (no reshell of the
## vector), capturing merged output and exit code without tripping set -e.
fRun(){
	local -r dir="$1"; shift
	_out="$( { cd "${dir}" && "${gitsby}" "$@"; } </dev/null 2>&1 )" && _code=0 || _code=$?
}
_isCrash(){ grep -qE "${_crashRe}" <<< "${_out}" || ((_code >= 2)); }

## Must survive (accept or refuse - either is fine) without an internal crash.
fSurvive(){ local -r desc="$1"; local -r dir="$2"; shift 2; fRun "${dir}" "$@"
	if _isCrash; then fFail "${desc} (exit ${_code})"; else fOk "${desc}"; fi; }
## Must be ACCEPTED: exit 0, no crash. fSurvive can't say this - it passes on a flat refusal,
## so a valid option spelling that stopped being recognized would look fine.
fAccept(){ local -r desc="$1"; local -r dir="$2"; shift 2; fRun "${dir}" "$@"
	if _isCrash; then fFail "${desc}: crashed (exit ${_code})"
	elif ((_code != 0)); then fFail "${desc}: refused (exit ${_code}), should accept"
	else fOk "${desc}"; fi; }
## Must refuse: nonzero exit, no crash.
fRefuse(){ local -r desc="$1"; local -r dir="$2"; shift 2; fRun "${dir}" "$@"
	if _isCrash; then fFail "${desc}: crashed (exit ${_code})"
	elif ((_code == 0)); then fFail "${desc}: accepted, should refuse"
	else fOk "${desc}"; fi; }
## Commit a message and confirm it lands in the log verbatim - catches a shell
## glob-expanding a bare '*'/'?' message into filenames before git sees it.
fMsgLiteral(){ local -r desc="$1"; local -r dir="$2"; local -r msg="$3"
	echo "chg ${RANDOM}" > "${dir}/seed.txt"
	fRun "${dir}" -q update "${msg}"
	local rec; rec="$(cd "${dir}" && git log -1 --format=%s)"
	if _isCrash;             then fFail "${desc}: crashed (exit ${_code})"
	elif [[ "${rec}" == "${msg}" ]]; then fOk "${desc}"
	else fFail "${desc}: recorded [${rec}], expected [${msg}]"; fi; }

## Confirm a PR title reaches gh verbatim - same class of bug as fMsgLiteral, on the
## other user-controlled value that gets handed to a native command.
## Clone into a glob-shaped directory name: the name must land verbatim, not expand
## against the cwd. Same bug class as fMsgLiteral, one slot deeper.
fDirLiteral(){ local -r desc="$1"; local -r dir="$2"; local -r url="$3"; local -r name="$4"
	rm -rf "${dir:?}/${name}"
	fRun "${dir}" -q repo clone "${url}" "${name}"
	if _isCrash;                         then fFail "${desc}: crashed (exit ${_code})"
	elif [[ -d "${dir}/${name}/.git" ]]; then fOk "${desc}"
	else fFail "${desc}: no clone at [${name}]"; fi; }

fTitleLiteral(){ local -r desc="$1"; local -r dir="$2"; local -r title="$3"
	rm -f -- "${ghLog:?}"
	fRun "${dir}" -q pr create "${title}"
	local rec; rec="$(awk '/^--title$/{getline; print; exit}' "${ghLog}" 2>/dev/null || true)"
	if _isCrash;                   then fFail "${desc}: crashed (exit ${_code})"
	elif [[ "${rec}" == "${title}" ]]; then fOk "${desc}"
	else fFail "${desc}: gh got [${rec}], expected [${title}]"; fi; }

## Fresh repo (bare origin + clone with one commit) under work/<name>.
fMakeRepo(){
	local -r dir="$1"
	git init --quiet --bare -b main "${dir}.git"
	git clone --quiet "${dir}.git" "${dir}" 2>/dev/null
	( cd "${dir}" && echo seed > seed.txt && git add --all \
		&& git commit --quiet -m seed && git push --quiet -u origin main )
}

## Vectors. None of these strings contain a _crashRe keyword, so a vector echoed
## back in gitsby's output can't self-trip the crash check.
## The single quotes are the point: these must reach gitsby as literal text, not
## expand here - that's what proves gitsby keeps them inert.
# shellcheck disable=SC2016
{
## Commands are matched case-insensitively (forgiving by design), so 'STATUS' is a
## valid alias of 'status' and doesn't belong here.
badCommands=( frobnicate status2 '..' './x' '123' 'a b' '-' '--' 'commit extra junk' )
badOptions=( --bogus -x -qx '--no-fetch=1' '--=v' -Z )
## The noun grammar put a second word in play; it gets the same treatment as the first.
badSubcommands=( "${badCommands[@]}" 'creat' 'switchh' 'ok' 'list extra' )
inject=( '$(touch CANARY_A)' '`touch CANARY_B`' ';touch CANARY_C' '&& touch CANARY_D'
         '| touch CANARY_E' '> CANARY_F' '$(touch CANARY_G)tail' '../CANARY_H' )
badBranch=( "${inject[@]}" 'a..b' 'has space' '-leadingdash' 'tilde~x' 'caret^x'
            'colon:x' 'ends.lock' '/leading' 'trailing/' 'back\slash' '?' '*' )
## 'v1.2.3' (leading v stripped) and 'X.Y.Z.W' (matches the optional suffix) are
## valid on purpose, so they belong nowhere near this refuse list.
badVersion=( not.a.version 1 1.2 'v.1.2' '1.2.3-' '-1.0.0' '$(touch CANARY_V)' 'x y' )
badPr=( abc 3.5 '$(touch CANARY_P)' 'x' 'ok' 'ok abc' 'ok 1 2' )
}

## The whole fuzz suite against whatever ${gitsby} points at.
fRunFuzz(){
	echo "fuzz: $1 (${gitsby})"
	local -r base="${work}/$1"
	mkdir -p "${base}"

	## Deterministic gh on PATH: the pr vectors below must not depend on a real gh being
	## installed, and must never reach the network. Logs create-args one per line so the
	## title can be compared byte for byte.
	mkdir -p "${base}/bin"
	## No .cmd sibling here, unlike test.bash: on Windows that would route the stub through cmd.exe,
	## which splits an unquoted '&' or '>' in an argument - turning a vector this suite hands gitsby
	## into a real command, and reporting an injection that gitsby never had. The pwsh leg's gh
	## coverage is skipped on Windows instead (see below), which is the honest answer.
	cat > "${base}/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
case "$1 $2" in
	"pr list")   : ;;  ## no PR open for this branch
	"pr create") printf '%s\n' "$@" > "${FUZZ_GH_LOG}"; echo "https://example.invalid/pull/1" ;;
	*)           : ;;
esac
GHEOF
	chmod +x "${base}/bin/gh"
	PATH="${base}/bin:${PATH}"; export PATH
	ghLog="${base}/gh.log"; export FUZZ_GH_LOG="${ghLog}"

	## Command slot: garbage first tokens are refused, never crash.
	local repo="${base}/cmd"; fMakeRepo "${repo}"
	local c
	for c in "${badCommands[@]}"; do fRefuse "command refused: '${c}'" "${repo}" -q "${c}"; done

	## Subcommand slot: garbage after a valid noun is refused the same way, and never reaches git.
	local sub
	for sub in "${badSubcommands[@]}"; do
		fRefuse "br subcommand refused: '${sub}'"   "${repo}" -q br   "${sub}"
		fRefuse "repo subcommand refused: '${sub}'" "${repo}" -q repo "${sub}"
	done

	## Options: unknown ones refused in either slot; valid combos accepted.
	local o
	for o in "${badOptions[@]}"; do
		fRefuse "option refused (slot 1): '${o}'" "${repo}" -q "${o}" status
		fRefuse "option refused (slot 2): '${o}'" "${repo}" -q status "${o}"
	done
	## -NoFetch is the spelling both ports take; bash also lowercases '--no-fetch', pwsh rejects it.
	fAccept "valid combo -q -y status"          "${repo}" -q -y status
	fAccept "valid combo -q -NoFetch status"    "${repo}" -q -NoFetch status
	fAccept "valid combo -y -q br list"         "${repo}" -y -q br list
	[[ "$1" == "bash" ]] && fAccept "valid combo -q --no-fetch status"  "${repo}" -q --no-fetch status

	## Branch names: injection + malformed refs are refused before any action.
	local b
	for b in "${badBranch[@]}"; do
		fRefuse "br create refuses: '${b}'" "${repo}" -q br create "${b}"
		fRefuse "br switch refuses: '${b}'" "${repo}" -q br switch "${b}"
	done

	## br prune takes no argument at all, so that slot is a refusal - and an injection
	## vector parked there must die at the parser, well before anything is deleted.
	local p
	for p in "${inject[@]}"; do
		fRefuse "br prune refuses an argument: '${p}'" "${repo}" -q br prune "${p}"
	done
	fRefuse "br prune refuses a branch name"     "${repo}" -q br prune main
	fRefuse "internal br-prune token refused"    "${repo}" -q br-prune

	## Commit messages: anything goes in a message, but it stays inert data. Each
	## needs a real change to reach 'git commit'; unique content guarantees one.
	## 'update' is the command that commits - there is no bare 'commit' any more.
	local repo2="${base}/msg"; fMakeRepo "${repo2}"
	local -i i=0 m
	for m in "${!inject[@]}"; do
		echo "change ${i}" > "${repo2}/seed.txt"; i=$((i + 1))
		fSurvive "commit message inert: '${inject[m]}'" "${repo2}" -q update "${inject[m]}"
	done
	## ...and a bare-glob message must land verbatim, not expand to filenames. The
	## repo has files, so '*' and '*.txt' would glob if the message weren't literal.
	local gm
	for gm in '*' '*.txt' '?' 'v*'; do fMsgLiteral "commit message verbatim: '${gm}'" "${repo2}" "${gm}"; done

	## Versions and PR numbers: malformed values refused (release fetches first,
	## which is local here; pr rejects before any network).
	local repo3="${base}/ver"; fMakeRepo "${repo3}"
	local v p
	for v in "${badVersion[@]}"; do fRefuse "release refuses version: '${v}'" "${repo3}" -q release "${v}"; done
	for p in "${badPr[@]}";      do fRefuse "pr refuses: '${p}'"              "${repo3}" -q pr "${p}"; done

	## PR titles: free text like a commit message, and it must reach gh as data, not code.
	## Needs a branch that isn't the merge target, which is what 'pr create' proposes from.
	local repo4="${base}/prnew"; fMakeRepo "${repo4}"
	( cd "${repo4}" && git checkout --quiet -b dev && git push --quiet -u origin dev \
		&& git checkout --quiet -b feat && echo f > f.txt && git add --all && git commit --quiet -m feat )
	local t
	for t in "${inject[@]}"; do fSurvive "pr title inert: '${t}'" "${repo4}" -q pr create "${t}"; done
	## Reading what gh received needs the stub to actually run, which on Windows the PowerShell
	## build can't do - a shebang file is not something it can start, and the .cmd sibling that
	## would fix it re-parses these very arguments. Say so rather than pass on a stub that no-oped.
	if [[ "$1" == "bash" ]] || ((! isWindows)); then
		for t in '*' '*.txt' '?' 'v*'; do fTitleLiteral "pr title verbatim: '${t}'" "${repo4}" "${t}"; done
	else
		echo "  skipped: pr title verbatim (pwsh on Windows can't run the gh stub)"
	fi
	## Proposing from the merge target is nonsense whatever the title says.
	( cd "${repo4}" && git checkout --quiet dev )
	fRefuse "pr create refuses from the merge target" "${repo4}" -q pr create 'anything'
	( cd "${repo4}" && git checkout --quiet feat )

	## Clone url and directory are user values that reach native git. A junk url is refused
	## (none of these is cloneable); a glob-shaped directory has to stay literal.
	local u
	for u in "${inject[@]}"; do fRefuse "clone url refused: '${u}'" "${repo3}" -q repo clone "${u}"; done
	local cd_
	local -a cloneDirs=( '*' '?' 'v*' 'a b' )
	## Win32 forbids '*' and '?' in a path, so native git can't create such a work tree at all
	## ("could not create work tree dir '*': Invalid argument") - the invariant is unprovable
	## there rather than violated. MSYS mkdir happily makes one, which is what makes the first
	## guess wrong. A space is legal, so 'a b' stays.
	if ((isWindows)); then
		cloneDirs=( 'a b' )
		echo "  skipped: clone dir verbatim '*' '?' 'v*' (Win32 forbids those characters in a path)"
	fi
	for cd_ in "${cloneDirs[@]}"; do fDirLiteral "clone dir verbatim: '${cd_}'" "${repo3}" "${repo3}.git" "${cd_}"; done

	## Long and odd input: must not crash. Branch is refused, message accepted.
	local long; long="$(printf 'x%.0s' {1..5000})"
	fRefuse  "long branch refused"  "${repo3}" -q br create "${long}"
	echo odd > "${repo2}/seed.txt"
	fSurvive "long message survives" "${repo2}" -q update "${long}"
	echo odd2 > "${repo2}/seed.txt"
	fSurvive "unicode/emoji message" "${repo2}" -q update $'café \u{1F600} ‮ rtl'

	## The new argument slots. 'raw' fronts exactly two tools, so anything else in that position is
	## refused rather than run - the one place a wrong answer would execute an arbitrary program.
	local rawTool
	for rawTool in "${badCommands[@]}" "${inject[@]}" 'rm' 'sh' 'GIT'; do
		fRefuse "raw tool refused: '${rawTool}'" "${repo3}" -q raw "${rawTool}" --version
	done
	fRefuse "raw with no tool refused" "${repo3}" -q raw
	## Deliberately NOT fuzzed: the arguments after 'git' or 'gh'. Reaching the tool verbatim is
	## the whole contract, so an injection vector there is gitsby doing its job, and the canary
	## would fire on a pass. What is checked above is that nothing but git and gh can be reached.

	## repo url takes one of two words and nothing else.
	local urlArg
	for urlArg in "${badSubcommands[@]}" "${inject[@]}" 'HTTPS ' 'https extra'; do
		fRefuse "repo url arg refused: '${urlArg}'" "${repo3}" -q repo url "${urlArg}"
	done

	## account has two subcommands, and neither takes an argument.
	local acctSub
	for acctSub in "${badSubcommands[@]}" "${inject[@]}"; do
		fRefuse "account subcommand refused: '${acctSub}'" "${repo3}" -q account "${acctSub}"
	done
	fRefuse "account list takes no argument"  "${repo3}" -q account list junk
	fRefuse "account apply takes no argument" "${repo3}" -q account apply junk

	## --config names a file. One that isn't there is refused; the value never reaches a shell.
	local cfg
	for cfg in "${inject[@]}" '/nonexistent/gitsby.shcl' ''; do
		fRefuse "bad --config refused: '${cfg}'" "${repo3}" -q --config "${cfg}" status
	done

	## GITSBY_ACCOUNT reaches 'gh auth token --user' as a value. It must stay inert there, and an
	## account nobody holds a token for is simply not selected - never an error, never a canary.
	local acct
	for acct in "${inject[@]}" '-x' '--user root'; do
		GITSBY_ACCOUNT="${acct}" fSurvive "GITSBY_ACCOUNT inert: '${acct}'" "${repo2}" -q --no-fetch status
	done
	unset GITSBY_ACCOUNT

	## 'pathContains' is a config VALUE that reaches a native command twice over: it is compared
	## against the current path, and 'account apply' builds a git config key out of it. A rule that
	## matches nothing is the ordinary answer for junk, so what is asserted here is that nothing
	## fires and nothing crashes - never that it is refused.
	local segCfg="${work}/seg-fuzz.shcl" seg
	for seg in "${inject[@]}" '../..' '/' '**' '.'; do
		{ printf 'account.f.pathContains = %s\n' "${seg}"; printf 'account.f.ghAccount = fuzzacct\n'; } > "${segCfg}"
		fSurvive "pathContains inert: '${seg}'" "${repo2}" -q --no-fetch --config "${segCfg}" status
		fSurvive "pathContains inert in account: '${seg}'" "${repo2}" -q --no-fetch --config "${segCfg}" account
	done

	## No-mutate: a refused command leaves HEAD and branch exactly as they were.
	local before_head before_branch
	before_head="$(cd "${repo}" && git rev-parse HEAD)"
	before_branch="$(cd "${repo}" && git branch --show-current)"
	fRun "${repo}" -q br create 'bad:name'   ## refused
	if [[ "$(cd "${repo}" && git rev-parse HEAD)" == "${before_head}" \
		&& "$(cd "${repo}" && git branch --show-current)" == "${before_branch}" ]]; then
		fOk "refused command left the repo unchanged"
	else
		fFail "refused command mutated the repo"
	fi
}

echo "gitsby fuzz + security (fixtures: ${work})"

## One implementation. The shim keeps ${gitsby} a single path, so the argument passing
## above is unchanged.
goBin="${root}/src-go/gitsby"; [[ -x "${goBin}" ]] || goBin="${goBin}.exe"
[[ -x "${goBin}" ]] || { echo "no build at src-go/gitsby - run 'go build' there, or cicd.bash stage 2" >&2; exit 1; }
gitsby="${work}/gitsby-go"
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "${goBin}" > "${gitsby}"
chmod +x "${gitsby}"
fRunFuzz "go"

## The credential helper. gitsby writes it as a git config value, and git hands that value to a
## SHELL when a push needs credentials - so anything interpolated into it is a command, not a
## string. The login that goes in there can come from GITSBY_ACCOUNT, from a git config key, or
## from the config file, and none of those is a place to accept shell. Driven with a real
## 'git credential fill', because the string is inert until git actually runs it: reading the
## config value back proves nothing about what happens when it is invoked.
fCredentialHelperVectors(){
	local -r ch="${work}/credhelper"
	mkdir -p "${ch}"
	git init --quiet -b main "${ch}/proj"
	(
		cd "${ch}/proj" || exit 1
		echo a > a.txt && git add --all && git commit --quiet -m init
		git remote add origin https://github.com/acme/proj.git
	)
	echo tok_fuzz > "${ch}/token"; chmod 600 "${ch}/token" 2>/dev/null || true
	local vector=""
	## Single quotes throughout: these are the literal text of an attack, not something to expand.
	# shellcheck disable=SC2016
	for vector in '; touch '"${ch}"'/CANARY-ghaccount; echo x' \
	              '`touch '"${ch}"'/CANARY-backtick`' \
	              '$(touch '"${ch}"'/CANARY-subshell)' \
	              '" ; touch '"${ch}"'/CANARY-quote ; "' ; do
		cat > "${ch}/v.shcl" <<-EOF
			account.v.path      = ${ch}/proj
			account.v.ghAccount = ${vector}
			account.v.tokenFile = ${ch}/token
		EOF
		## 'credential fill' makes git invoke the helper for real.
		( cd "${ch}/proj" && printf 'protocol=https\nhost=github.com\n\n' | \
			"${gitsby}" -q -NoFetch --config "${ch}/v.shcl" raw git credential fill ) >/dev/null 2>&1 || true
	done
	## The helper git holds must carry no login text at all - the name is read from the
	## environment when it runs, the same way the token is.
	local helper=""
	helper="$( cd "${ch}/proj" && "${gitsby}" -q -NoFetch --config "${ch}/v.shcl" raw git config --get credential.https://github.com.helper 2>/dev/null )"
	# shellcheck disable=SC2016  ## matching the literal variable reference, not its value
	if [[ "${helper}" == *'${GITSBY_FORGE_USER}'* && "${helper}" != *touch* ]]; then
		fOk "the credential helper reads its username from the environment"
	else
		fFail "the credential helper carries interpolated text: ${helper}"
	fi
}
fCredentialHelperVectors

## The security assertion: no vector ever caused a side-effect to run.
if [[ -z "$(find "${work}" -name 'CANARY*' -print -quit)" ]]; then
	fOk "no injection canary fired"
else
	fFail "injection canary fired: $(find "${work}" -name 'CANARY*')"
fi

echo "passed: ${pass}, failed: ${fail}"
((fail == 0)) || exit 1


##	History:
##		- 20260724 JC: Created. Adversarial fuzz of the command/option/arg surface
##			with an injection canary, run per implementation like the test harness.
##		- 20260726 JC: Vectors for the noun+verb subcommand slot, and for the clone url and directory.
##		- 20260808 JC: Vectors for the 'raw' tool slot, the 'repo url' argument, the 'account' subcommand, '--config' and GITSBY_ACCOUNT. What follows 'raw git' or 'raw gh' is deliberately not fuzzed - reaching the tool verbatim is the contract, so a vector there would fire the canary on a pass.
##		- 20260810 JC: The glob-shaped clone directories are skipped on Windows. Win32 forbids those characters in a path, so native git cannot create such a work tree at all and the invariant is unprovable there rather than violated - MSYS mkdir happily makes one, which is what makes the first guess wrong.
##		- 20260812 JC: Vectors for the "pathContains" config value. It is compared against the current path and becomes a git config key in "account apply", so it reaches a native command twice; junk there must stay inert rather than be refused, since a rule matching nothing is the ordinary answer.
##		- 20260813 JC: Same environment isolation the behavioral suite grew, plus the gitsby config file this one had never pinned at all.
##		- 20260818 JC: One leg, the compiled build. The scripted ones moved to legacy/ and are no longer a fuzz target - nothing new can reach them.
