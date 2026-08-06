<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Requirements

This is a product backlog for the run-up to v2.0.0. After that release, bugs, features, and enhancements move to GitHub Issues.

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Conventions](#conventions)
- [Backlog](#backlog)
	- [Misc to-do](#misc-to-do)
	- [Bugs](#bugs)
	- [Features and enhancements](#features-and-enhancements)
	- [Done](#done)
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
		- [Done - Code review 20260731](#done---code-review-20260731)
		- [Done - Code review 20260730](#done---code-review-20260730)
		- [Done - Code review 20260727b](#done---code-review-20260727b)
		- [Done - Code review 20260727](#done---code-review-20260727)
		- [Done - Code review 20260726](#done---code-review-20260726)
		- [Done - Code reviews 20260725 and 20260723](#done---code-reviews-20260725-and-20260723)
	- [Future and/or deferred](#future-andor-deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

## Backlog

### Misc to-do

### Bugs

### Features and enhancements

- 🔘 Design a way to *fully* automate new releases, end-to-end.

### Done

#### Done - Bugs

- ✅ The identity probe ignored the ssh key git was configured to push with.
	- It ran a bare `ssh`, so a repo selecting its key through `core.sshCommand` was reported as the default key's account. Where that matched gh's account the mismatch check passed with both halves wrong - green in exactly the setup it exists for.
	- Fixed to follow git's own precedence, `GIT_SSH_COMMAND` then `core.sshCommand`. The identity line takes the key file from the same source, so it can't name the right account beside the wrong key.
	- Same override was overriding the key on `fetch` and the remote probe, which made a private repo reachable only via that key look like being offline.

- ✅ gh acted as whatever account was last switched to, regardless of who owns the remote.
	- Now picks the owner's account for the run when gh already holds it, via `GH_TOKEN`, leaving gh's active account alone. Only when the owner can be named and the token is held - an org or someone else's repo is left untouched rather than refused.

- ✅ The PowerShell installer never verified the checksum, and said the release had none.
	- Found by running both documented one-liners against the current release: the Bash one reported the checksum verified, the PowerShell one reported no `SHA256SUMS` for the same release, which does publish one.
	- Cause: GitHub serves that file as binary, and PowerShell returns a response body as raw bytes for anything it doesn't treat as text. Read as lines, bytes match nothing, so no checksum was found and the download was installed unverified.
	- The message made it look settled rather than broken, so the default install had gone unverified since the check was added. The Bash installer was never affected.
	- Fixed: the body is decoded before it is read. Verified against the published release - the checksum is found, compared, and matches the installed file.

- ✅ Every install command in the README 404s, because `main` is still the 2022 tree.
	- `main` holds no `install.bash`, `install.ps1`, `install-dev.*` or `bin/gitsby.ps1`, so all six documented one-liners fail at the download. Reported from the field.
	- Cutting v2.0.0 fixes it outright: the merge to `main` puts the files there, and `releases/latest` stops resolving to the 2022 `v1.0.1`, which is a dead end for the default install path (that tag predates the `bin/` layout).
	- Until then the working incantation is the `dev` URL plus `--release dev` / `-Release dev`. Left undocumented on purpose rather than pointing strangers at `dev`.

- ✅ The SSH identity line named the local login instead of the account being acted as.
	- It asked `ssh -G` about the bare host. With no user in the target, ssh answers with the OS login name, so a push as `t00mietum` displayed as `collierjr@github.com`. Reported from the field.
	- That value is neither of the two real ones: the connect user is `git`, and the account is whatever the key authenticates as. On a personal machine it looks plausible enough to be believed, which is worse than showing nothing.
	- The probe now uses the connect target, so an explicit user in the remote URL is honored the way git honors it. Host alias resolution is unaffected - the user part only overrides `User` in `~/.ssh/config`.
	- The line also leads with the account now, resolved by asking the host. That is what it existed to answer; the connect user is identical for every GitHub account, and the key shown is only ssh's first readable candidate, not necessarily the one that authenticates. Offline it says `unknown` rather than guessing, and skips the round trip.
	- Every other test uses a local-path origin, which has no ssh identity, so the whole line had shipped untested. It now has a fake ssh that reproduces the real defaulting behavior.

- ✅ A byte-order mark on the three PowerShell files broke both installer one-liners and direct execution.
	- `irm` keeps the BOM, so `iex` and `[scriptblock]::Create` saw it glued to the shebang and the first line stopped being a comment. Both documented one-liners failed for every user, on every platform. Reported from the field.
	- The same BOM sat ahead of `#!` in `bin/gitsby.ps1`, so `./gitsby.ps1` fell through to the shell instead of running.
	- `bin/gitsby.ps1` already carried a suppression saying a BOM would break the shebang, so it had been there against the file's own stated intent since the files were written.
	- The tests couldn't see it: they read the source with `Get-Content`, which drops a BOM silently. They now decode the bytes, and each file's first two bytes are checked.
- ✅ `install.ps1` sent a failed download to the Bash installer, which fails the same way.
	- Both resolve the same stale `releases/latest`, so the advice was a loop. It names `-Release dev` now, matching what `install.bash` already said.

- ✅ An unreachable remote did not make the parking push safe.
	- `update` and `sync` degraded properly, but `br create`, `br switch`, `br hotfix`, `pr create` and `release` all failed on `git push` with raw git text.
	- Split by what each command is for. The ones that mean something locally now skip the push and say so, naming the branch and `sync` from it as the way to publish later. The ones that exist to publish - `sync`, `pr create`, `pr ok`, `release` - refuse up front, before the plan promises a push, and name what to do instead.
	- `br land` needed more than a skipped push: with the merge unpublished, origin's copy of the work branch is its only ref to those commits, so the remote delete is held back too. The hotfix back-merge has the same shape - it merges `origin/main` normally, which unpublished is the stale one, so it falls back to the local branch.
	- Decided against making `--no-fetch` mean this. The flag declines the incoming round trip, which is a perfectly good thing to want against a reachable remote, and the suite itself uses it that way throughout. Offline is a state the pre-command fetch discovers, not a flag.

#### Done - Features and enhancements

- ✅ Say what a branch is branched from, wherever a branch is named.
	- Reported against `br hotfix` run from `dev`: the current-branch line read `dev` while the plan directly under it checked out `main`. Both were correct and nothing connected them.
	- Branch names now render as `base :: branch` - `dev :: feature/retries`, `main :: hotfix/readme`. `main`, `master` and `dev` stay bare; they are not off anything you would work from.
	- `br create` and `br hotfix` gained a `New branch` line naming what they will make and its base, so the answer is on screen before the plan is read. Pre-flight only - after the run the branch exists and the question is gone.
	- The repo's default branch moved to its own line instead of riding along in parentheses, and `br list` now states it too.
	- The base shown is where the branch lands. Git records no fork point, and for anything gitsby made the two are the same by construction.

- ✅ Show the file list before first publication (`repo create`, `repo connect` from a plain directory).
	- Every other command shows what it is about to touch; the one that hands a whole directory over for the first time did not.
	- The list is what `git add --all` will really add, asked through a throwaway git dir outside the work tree - so `.gitignore` and `core.excludesFile` are honored, and answering "n" leaves the directory exactly as it was found.

- ✅ `br hotfix <name>`: a branch that targets the default branch instead of `dev`, for corrections to published material.
	- The branching model is written up in `design.md`; this is the command that carries it.
	- Branches off the default branch, pushed as `hotfix/<name>`. The prefix is the marker, so it survives a clone and shows in a branch listing. A name given with the prefix already on it is accepted rather than doubled.
	- `br land`, `pr create`, and `pr ok` recognise a `hotfix/` branch and target the default branch, then merge it back into `dev`. `br create` still comes off `dev`, so feature work is untouched.
	- A back-merge that conflicts aborts and leaves `dev` alone, reporting that the hotfix landed and naming the two commands to finish by hand. Conflict surgery stays raw-git territory.
	- Landing warns when the branch touched `bin/`: the default branch would then carry code no tag contains, so the latest release's downloads no longer match it.
	- Implemented as `fBranchTarget` / `Get-BranchTarget` alongside the existing merge target, rather than by changing `fMergeTarget` - "where new branches come from" and "where this branch lands" are different questions, and only the second one varies.
	- 30 new checks across both implementations. Verified the pre-feature build rejects `br hotfix` outright.

- ✅ Release-prep sweep over the docs and the built-in help.
	- The help still described `sync` as commit-then-pull. That order changed when the bare `pull` command was dropped, and this line was missed. The README already had it right.
	- A regression check pins the wording, so the same drift can't come back quietly.
	- Also two stale references in the project notes: a command name that was renamed, and a description of argument parsing from before the noun grouping.

- ✅ `br prune`: delete branches already merged into the merge target, local + remote.
	- Nothing cleaned up after a PR merged from the web UI or another machine, or after an abandoned branch. `br land` and `pr ok` only ever delete the one branch they just merged.
	- Kept safe by what the tool already enforces: every landing is a real merge commit, so ancestry is an exact test. Unmerged branches are listed and left alone, and there is no `--force`.
	- The remote copy is only deleted once origin's own merge target contains it, so an unpushed landing can't strand work.
	- Verified the safety gates discriminate: a version with the ancestry check removed deletes an unmerged branch, and one without the origin-side check deletes origin's only ref to unpushed work.
	- Deletes with `git branch -D` behind our own check. Deferring to `git branch -d` was tried first and was wrong both ways: it warns about HEAD on every branch when pruning from anywhere but the target, and it flatly refuses a merged branch that was never pushed, so the plan promised a deletion that silently didn't happen.
	- Closes with a count (`Pruned 3 local, 3 on origin`) and names what it kept, so a wall of git output still ends in a plain answer.

- ✅ Drop the bare `commit` and `pull` commands - both work around the opinionated workflow.
	- `commit` alone leaves work committed but unshared. `pull` alone was the only place the tool took upstream changes without parking your own, unlike every other command.
	- Reversible in one direction only: dropping now is free, adding back later breaks nobody, removing later would.

- ✅ `update`/`sync` pull before they commit (bug this exposed, present on dev).
	- Committing first guaranteed divergence whenever the remote had moved, so the ff-only pull refused - in the most ordinary case there is. `pull` had been the accidental workaround.
	- Verified against the pre-fix build: it fails, the fixed one lands the work on top and keeps history linear.

- ✅ An unreachable remote warns and skips the pull instead of failing; `--no-fetch` means offline and skips the pull too.
	- Needed because `update` is now the only way to commit; a genuine non-fast-forward still fails hard.

- ✅ Group the infrequent commands under nouns: `repo clone|create|connect`, `br list|create|switch|land`, `pr create|<n>|ok <n>`.
	- Daily verbs stay one word. The extra word only lands where you type it rarely, and it buys a discoverable set instead of a flat list of abbreviations.
	- One verb across all three nouns (`create`, never `new` in some places). `new` and `go` still work but aren't published.
	- Landed before v2.0.0 on purpose: every name being changed was unreleased, so it cost nothing now and would have cost a permanent alias later.

- ✅ Split the old `connect` into `repo create` and `repo connect`.
	- Creating a remote is the one irreversible, outward-facing step, so it gets its own verb instead of happening as a side effect.
	- Each refuses the other's case and names it, so a wrong guess costs one line of output.

- ✅ Drop every pre-2.0 command alias (`scommit`, `spull`, `scompul`, `saveup`, `spush`, `mkbranch`, `chbranch`, `mtm`, `list`).
	- v2 is a clean break under a new tool name, and not all of the old commands worked. The suite now asserts they're rejected, so none creeps back.

- ✅ `pr new [title]` opens a pull request, so the whole PR round trip lives in gitsby instead of half in `gh`.
	- Pushes the branch first - GitHub can only diff what the remote has.
	- Targets `dev` when the repo has one, else the default branch. Refuses from that branch, since there is nothing to propose.
	- No title given: the last commit subject, which is already a description of the work. The preview shows it before anything happens.
	- An already-open PR for the branch reports its number instead of letting `gh` error.

- ✅ `pr ok <n>` refuses while the current branch has uncommitted changes or unpushed commits.
	- Merging deletes the branch local and remote, so work that never reached origin was outside both the PR and the merge.
	- Every other mutating command already parked work first; this was the one that did not.

- ✅ The installers' default "latest release" lookup skips anything flagged as a pre-release on GitHub.
	- GitHub's `releases/latest` returns the newest full release, so a pre-release-only repo resolves to the last full one - for this repo, the 2022 release.
	- Decided: publish releases as full releases rather than adding a `--pre` flag. The semver suffix still marks a candidate for anyone reading the tag, and the one-liner installs keep working with no extra arguments.
	- `--ref`/`-Ref` remains the way to install a specific tag or branch, and is already documented.

- ✅ CICD process (full spec in private notes):

	- Done: every stage below is live and runs on each publish. The pipeline is local by design - no cloud service, no account to pay for.

	- ✅ `cicd.bash`: `-q|--quiet`, `-m|--msg|--message`, prompt for commit message when neither given (CTRL+C aborts); silkterm output style; `fEcho`/`fParseArgs` conventions.

	- ✅ Linting stage: shellcheck (+ markdownlint), no auto-format for Bash; output GFS-rotated to `cicd/artifacts/lint/`; zero-error goal.
		- Everything gates clean now, including `bin/gitsby` (the refactor cleared its ~80 legacy findings; report-only list emptied). PSScriptAnalyzer gates the three `.ps1` files.

	- ✅ Dogfood install stage: copy to first existing preferred dir (bash + pwsh lists).
		- Both legs live since the pwsh port landed.

	- ✅ Regression tests; keep updated as features/bugs land.
		- `cicd/test.bash`: throwaway repos (bare origin + two clones), every command plus failure guards, run once per implementation - 140 checks.

	- ✅ Adversarial fuzz/security testing (our input surface + what we depend on).
		- Done: `cicd/fuzz.bash` - bombards the command slot, options, and branch/message/version/pr args with malformed + injection vectors, per implementation (bash + pwsh). Asserts three invariants: no internal crash (bash/pwsh error-dump signatures), no shell/command injection (a canary side-effect never fires), and inputs-that-must-refuse exit nonzero leaving the repo unchanged. 191 checks. Found + fixed two real pwsh-port bugs (see next items). Scope is gitsby's own input, not upstream git.
		- Fuzz-found bug (fixed here): the pwsh port passed user-supplied values to native git UNquoted, so PowerShell wildcard-expanded `*`/`?` against the filesystem before git saw them - `newbr '*'` slipped past `check-ref-format` and created a branch named after a file. Quoted the user values in the direct git/gh calls (branch validation, clone-dir, gh target), mirroring the bash port. bash was never affected (always quoted).

	- ✅ pwsh: `Invoke-Git` splatted an argument array (`git @GitArgs`), and PowerShell wildcard-expands any element that is a bare `*`/`?`/`[...]` matching files in the cwd - so a commit message of exactly `*` globbed to filenames.
		- Done: `Invoke-Git` now runs git via `System.Diagnostics.ProcessStartInfo` + `ArgumentList` (a literal argv - no PowerShell reshell or globbing), `UseShellExecute=$false` with no redirection so git output still shows inline. Tried and rejected: quoting splat elements (splat drops quoting), `[WildcardPattern]::Escape` (git receives the backtick), `Start-Process -ArgumentList` (re-splits multi-word elements like a spaced message). Verified messages with `*`, spaces, `?`, `[ab]`, `;$(...)`, quotes, and emoji all land verbatim; exit codes propagate; no injection. Locked with `fMsgLiteral` verbatim-message vectors in `cicd/fuzz.bash` (both implementations). Fuzz 183 -> 191; test.bash still 269/0; PSSA clean.

	- ✅ Automated demo GIF (fake terminal, `--quick` skips); copy `gen-demo-gif.py` from convert-base-v2; embed `assets/demo.gif` in README.
		- Done: scenario `cicd/demo-scenario.toml` + repo builder `cicd/utility/demo-repo.bash`; embedded in README top with a commented YouTube placeholder. Single hero `land` command (state block + full plan + commit/push/merge/cleanup) in an anonymized throwaway repo built offline; runs real gitsby so it can't go stale. 960x540 (the tool's default, a blessed alternative in the private note; not 640x360, and the tool has no fixed-fps knob). Pinned commit dates make it byte-deterministic so cicd only regenerates on real change. 18.4s loop, 823 KiB.
		- Follow-up: one command was too thin a story, so the scenario now runs a whole feature end to end - `status`, `newbr`, `update`, a real edit typed at the prompt, `sync`, `land` - with a short comment line introducing each. Two generator fixes came out of it: stderr now shares the stdout pipe (git writes its progress there, so it was all landing after the program's own output instead of under the step that produced it), and the palette pads to the next power of two rather than a flat 256 (same pixels, ~12% smaller file).
		- Follow-up: the smooth scroll and the cursor glide were never actually running. Both stepped once per 80ms frame, and a line of scroll is 21px, so any scroll rate over ~275 px/s finished a line in a single frame - a hard jump, and the rate knob did nothing (325, 520 and 820 all rendered byte-identical). Frame interval is now 20ms (50 fps) and the cursor glide follows it, so both move as intended. A smooth scroll redraws the whole text block every frame, which is expensive, so a new per-step `clear = true` starts each command on a fresh screen and roughly halves how far the view ever travels. 60.0s loop, still byte-deterministic.
		- Follow-up: cicd now runs the render through `gifsicle -O3` when it is installed, before the compare, so the committed file is the optimized one (`DEMOGIF_OPT_CMD` in config.bash; silently skipped when absent). Worth about 9% - 7.3 -> 6.6 MiB. Less than it sounds like it should be: the renderer already crops each frame to what changed, so most of the win was banked, and the lossy modes buy almost nothing on a 35-colour text demo.

- ✅ New commands for getting connected: `clone` (get an existing repo) and `connect` (publish work that only exists locally to a new or empty remote).
	- `clone <url> [dir]`: derives the dir from the URL, checks out `dev` when the repo has one, re-run is a no-op.
	- `connect [target]`: init if needed, commit, push. URL to an existing empty remote, or `owner/name` creates the GitHub repo via gh (`--public`/`--private`). Refuses remotes with history and won't change an existing origin.
	- Done: both implementations, previewed + confirmed like the rest; tests 207 -> 241.
	- Follow-up: logically validated (no bugs) and exhaustively tested. Closed the "gh paths untested offline" gap with a hermetic fake gh (create / add https+ssh / refuse-nonempty), plus clone edges (no-dev, pre-existing empty dir, different-url refuse) and connect edges (empty inited repo, matching-url re-connect). Tests 241 -> 269, both implementations.

- ✅ Add a PowerShell badge to README.md.
	- Added next to the bash badge in the header block, linking to the PowerShell docs.

- ✅ One-liner installers for Bash and PowerShell: download the release, verify the checksum, install the script. Idempotent, and they state the plan and ask before touching anything. Documented in README under "Installation", including a "Direct" subsection with the commands and the install locations.

	- Done: `install.bash` and `install.ps1` cover it. Checksum verification against a published `SHA256SUMS` landed with code review item 19, and the README "Direct" subsection lists both the commands and the paths each installer uses.

	- Note on the spec's option names: `--arch` doesn't apply, since gitsby is a script rather than a compiled binary. `--release dev|stable` is spelled `--ref`, and `--target user|system` is spelled `--system` (user is the default).

	- Note on install paths: gitsby is a single file, so it goes straight to `~/.local/bin` or `/usr/local/bin` rather than into a program directory with a symlink.

- ✅ Code Review 20260723 item 39: README typos.
	- Line 82 "devoted to to", line 100 "besome", line 218 "cononical".
	- Done: all three fixed.

- ✅ Rename `saveup` to `update`.
	- Done in both implementations; `saveup` stays as a hidden alias like the other old names. Docs and changelog swept.

- ✅ Script output starts and ends with a blank line (breathing room between prompt text).
	- Trailing blanks already existed on every exit path; added the leading one (both implementations). Error paths were already blank-wrapped.

- ✅ After `release` merges dev to main, bring dev up to include the release merge and tag.
	- Done via `git merge --ff-only main` on dev (then push), not `git branch -f dev main`: same result normally, but if dev gained commits mid-release it skips with a warning instead of discarding work. Previews updated; tests cover it.

- ✅ 'git_notes_and_oneliners.md': Move the current commands under a "Bash" section, and add a "PowerShell" section below it, with pwsh v7 parity versions of the same one-liners.
	- Two mirrored sections, same task headings in the same order, so the two are easy to compare side by side.
	- The PowerShell section opens with the three gotchas that bite when translating from Bash: `&&`/`||` need pwsh 7, `@{u}` has to be quoted, and staged-change tests read `$LASTEXITCODE`.
	- Every pwsh one-liner was run against throwaway repos, not just eyeballed. Two spots deviate on purpose: no `less` (git pages its own diff), and `Remove-Item` deletes outright since there is no cross-platform `trash`.
	- Also swapped the stale sister-tool reference in the Bash "push local changes" one-liner for `gitsby update`.

- ✅ All potentially destructive or conflict-producing commands - or anything that will reveal a user identity on the remote - should:
	- Show what's going to change (including a list of changed files, piped through an internal equivalent of `... | less -FX` if necessary)
	- git status without line-breaks, and SSH connection info. And a prompt to continue. All with standard 1 blank line where appropriate.
	- Every mutating command already previewed its plan and prompted; this added the identity and change detail. `status` shows the same block.
	- SSH line resolves the remote URL through `ssh -G`, so a `~/.ssh/config` host alias shows the real host and key behind it - the point being to catch acting as the wrong account before you push. (It later grew the account itself, which is the part that actually answers that; see the bug above.) Author line shows what git will actually stamp on the commit.
	- Changes list one file per line (short form), truncated to the terminal width and capped at 25 with an "and N more" tail - the `less -FX` idea without depending on a pager. Incoming section lists what a pull would change, and the branch line carries ahead/behind.

- ✅ Better command names; dev-aware merging; PR and release commands (both implementations).
	- Renames: scompul->saveup, spush->sync, scommit->commit, spull->pull, mkbranch->newbr, chbranch->gobr, list->listbr, mtm->land. Old names still work as hidden aliases.
	- newbr/gobr/land now branch off / land on dev when the repo has one, else main/master. land refuses to run from the default branch.
	- New: pr (bare = list, n = view + diff, ok n = approve + merge, via gh), release (merge dev into main --no-ff, tag, push; no version = patch bump on the latest v* tag).

- ✅ PowerShell port of gitsby (style guide already covers pwsh; dogfood pwsh leg activates when it lands).
	- `bin/gitsby.ps1`: same commands, checks, and flow as the bash version. Regression suite now runs once per implementation (78 checks total); PSScriptAnalyzer joined the lint stage (gates all three .ps1 files); dogfood pwsh leg live. Not in a release yet - README says to use `-Ref dev` until one is cut.

- ✅ Create a release-install script per platform (`bash` and \[`pwsh` or `cmd`\]), runnable via a single `curl`/`wget` (etc.) and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort. Update README.md with one-liner for both local and system-level installs.
	- `install.bash` + `install.ps1` at repo root; plan-then-confirm, `--system`/`-y`/`--ref`; README Installation one-liners filled in (user + system, curl and wget). Resolves the latest release tag, prefers a release asset, falls back to the tagged tree. The 2022-era releases predate the `bin/` layout so the release path activates for real once a v2 release is cut (`--ref main`/`--ref dev` works today); the pwsh installer says the port hasn't shipped and points at the bash one until then.

	- ✅ Do the same thing for a dev-branch install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort. Update README.md with one-liner for both local and system-level installs.
		- `install-dev.bash` + `install-dev.ps1`: clone, check out `dev`, check tooling (offers package-manager install where one is found), verify, print next steps. Documented in README "How to develop" + contributing.md "Your First Code Contribution". Bash installers run on macOS stock bash 3.2.

- ✅ Get original commands and options working. At some point some just kind of broke (pre-git), and were never fixed.
	- All commands work and are regression-tested; the commit/save/sync/land family takes -m or a positional message, newbr/gobr validate their branch argument.

- ✅ Integrate these rules and ideals: `reference/git.txt` (in this repo), including:
	- Push hygiene (stash / pull --ff-only / stash apply / add / commit / push) is now the core of pull/saveup/sync; branch workflow lives in newbr/gobr/land.
	- Work on feature branches
	- PRs to merge to develop
	- Commit frequently
	- Pull frequently, push infrequently
	- Push hygene:

		~~~bash
		git stash
		git pull --ff-only
		git stash apply
		git add .
		git commit -m ""
		git push
		~~~

- ✅ Make sure everything done with git:
	- Every command verifies state first and is idempotent: stash only if dirty (pop only what was pushed), pull only with an upstream, push only if ahead, commit only if changes; main/master detected from origin HEAD, not hardcoded. All covered by the regression tests.

	- Is done safely. E.g. before stashing, verify safely in a robust way that makes no assumptions, that there is anything to pull. `n8git_backup-and-publish` has examples.

	- Never make assumptions about the local and/or repo state. Verify first for every command, whatever is relevant for the command.

	- Everything must be idempotent.

- ✅ Refactor the bash script:
	- Rewritten 2142 -> ~620 lines on the current template generation (same one as `n8git_backup-and-publish`): strict mode, trap suite, arg parser, minified header trio.

	- ✅ Use newer, easier-to-maintain Bash template/boilerplate/common functions. (E.g. from sister project silkterm.) But even those examples need to be cleaner (don't change anything outside of repo.)

	- ✅ Modernize function and variable naming convention. Be descriptive with names, but not too long. Use of one-letter variables in small loop structures is OK.

	- ✅ Remove dead code.
		- Dropped the unused ~1400-line generic library (ping, symlink, editor pickers, sudo plumbing, glob-permutation engine, platform detection).

	- ✅ Refactor to maximize usefulness of idiomatic Bash 5 features.
		- Argument arrays instead of eval (which also retired the curly-quote message mangling), `[[ -v ]]`, parameter transforms, arithmetic conditionals.

- ✅ Work on dev branch. Push releases to main.

	- ✅ `dev` branch created from `main` and pushed; feature branches now merge to `dev`, `main` is release-only.

- ✅ Create PRs rather than pushing directly (for this project).
	- Feature branches now go up as PRs to `dev` and land via merge commit; direct local merges retired.

- ✅ Delete stale branch from 2020.
	- `20201003-074416_jc_rewrite-in-golang` (abandoned golang rewrite) deleted from origin.

#### Done - Code review 20260731

Delta review of the branch-display and status-label rounds. One finding, both implementations.

- ✅ Code Review 20260731 item 1: `br list` refused to run in a repo whose default branch can't be told.
	- The default-branch gate exempted only `status` and the `repo` commands, so `br list` - read-only, and the other command you'd run to look around - errored out. The `Default branch: unknown` fallback it had just gained could never print.
	- Fixed: `br list` joins the gate exemption. Mutating commands still refuse up front.

#### Done - Code review 20260730

Delta review of what landed since the 20260727b round: the offline handling, the BOM fix, the installer message, and the SSH identity line. Three findings, all in the offline messages, all in both implementations.

- ✅ Code Review 20260730 item 1: an offline hotfix land pointed at a recovery that leaves the hotfix unshipped.
	- The warning said `sync` publishes the merge, but a hotfix land ends on `dev` after the back-merge - `sync` from there publishes `dev` and leaves origin's default branch stale. That is the one branch a hotfix exists to fix, and following the advice would read as success.
	- Fixed: the hotfix warning names both steps, `br switch <default>` then `sync` - the switch's parking push publishes `dev` on the way, so the pair covers both branches. A normal land still just names `sync`, which is right there because the command ends on the target.

- ✅ Code Review 20260730 item 2: parking offline claimed committed work awaits even when there was nothing to push.
	- A clean, in-sync branch got "Your work is committed locally" with no work at all; online, the same state correctly said "Nothing to push."
	- Fixed: nothing ahead of the last-known origin means "Nothing to push.", offline or not.

- ✅ Code Review 20260730 item 3: the skipped-push warning said `sync` publishes it, during commands that then leave that branch.
	- `br switch` and `br land` park the current branch and move off it, so a `sync` from where you end up publishes a different branch.
	- Fixed: the warning names the branch it means, and says `sync` from it.

#### Done - Code review 20260727b

Full pre-release review, run across nine lenses with every finding independently checked before it was accepted. Fifty-three held up; the ones that changed behavior are below. Deep evidence is kept out of the repo.

- ✅ Code Review 20260727b item 1: a conflicted tree was committed, and pushed (both implementations).
	- `git pull --ff-only --autostash` exits 0 even when reapplying the stashed work conflicts - it only warns - and `git add --all` then marks the conflict resolved.
	- So the most ordinary case there is, your edit plus a teammate's push to the same lines, committed the `<<<<<<<` markers, reported "(working tree clean)" and "Done.", and `sync` sent them to origin.
	- Fixed: nothing is staged while any path is unmerged. The conflicted files are listed, and the message points at the stash git kept.

- ✅ Code Review 20260727b item 2: PowerShell read one repository and wrote to another.
	- Git was started without a working directory, so it ran in the directory pwsh was launched from, while `Set-Location` had moved only PowerShell's own idea of where it was.
	- Reading state therefore used the repo you were in and committing used the other one: it reported the right directory and the right changes, then committed an unrelated file from elsewhere and exited 0.
	- The suite could not see it, because every check moves directory in bash before starting pwsh, which makes the two agree.
	- Fixed: git is given the current location explicitly. New checks move location inside the pwsh session instead.

- ✅ Code Review 20260727b item 3: `pr ok <n>` destroyed unpushed commits on the PR's branch (both implementations).
	- The guard asked whether the branch you were standing on had unpushed work. Accepting a PR from `dev` - the way it is normally used - asked about the wrong branch entirely.
	- gh merges what origin holds and then deletes the branch with a force delete, so commits that never reached origin went with it and were reachable from no ref afterwards.
	- Fixed: the PR's own branch is checked, whichever branch you are on, and the advice names it and how to push it from where you are.

- ✅ Code Review 20260727b item 4: a default branch that is neither `main` nor `master` was invented rather than resolved (both implementations).
	- With no `origin/HEAD` to read, the answer fell back to the literal `main`. On a `trunk` repo that named a branch which does not exist, so the branch was judged unprotected, work was auto-committed to it (and pushed, when it had an upstream), and the command then died on a checkout of the invented name.
	- Worse when a stale local `main` existed alongside the real default: `br land` exited 0 having merged into the wrong branch, with no diagnostic at all.
	- Fixed: `trunk` joins the conventional names, a repo with a single local branch resolves to it, and an unborn repo still answers with the name it will get. When it genuinely cannot be told, commands refuse before anything is committed - `status` alone continues, and says "unknown" rather than a name it does not have.

- ✅ Code Review 20260727b item 5: the documented PowerShell install one-liner never worked, and declining it closed your shell.
	- `iex` evaluates a top-level `param()` block in the caller's scope, where the allowed-values attribute is checked against its own empty default and fails immediately - so the install path the README leads with died before printing anything.
	- The other documented form did run, and `exit` inside it ended the calling session; strict mode and the error preference leaked into it on success.
	- A non-tty stdin also proceeded unasked, because the prompt's empty answer at end-of-input is not the empty string.
	- Fixed: both installers are a function that is called, they refuse rather than exit, they check for PowerShell 7 before anything reads a variable that 5.1 lacks, and end-of-input counts as no. Both documented shapes now bind their options.

- ✅ Code Review 20260727b item 6: `--ref` was interpolated into a download URL unchecked (both installers).
	- A path-shaped value walked out of this repository, so a posted one-liner could install somebody else's script - and run it - while the printed plan still named this project. It reads as a harmless branch selector, which is why the confirm prompt was no protection.
	- Fixed: refs must look like refs, in both installers, and the tag resolved from GitHub's redirect is checked the same way before it reaches a URL.

- ✅ Code Review 20260727b item 7: credentialed remote URLs were masked in the plan and printed in full when the command ran.
	- A token in a clone or connect URL reached the terminal, and any log or CI capture of it, on the execution line and again in the failure line.
	- Fixed: the display copy of every argument goes through the existing masking helper; what git receives is untouched. Three messages that echoed the URL raw alongside a masked copy of the same URL were fixed too.

- ✅ Code Review 20260727b item 8: `-v` alongside a command silently did nothing (PowerShell).
	- The switches bind from any position under pwsh, so `update -v` printed the version and exited 0 - a caller or CI step saw success with the work not done.
	- Fixed: `-v` is refused when a command is present, matching Bash. `--help` went the other way on purpose: it now works after a command in both builds, since asking a subcommand for help is the reflex every git user has.

- ✅ Code Review 20260727b item 9: a commit message starting with a dash was impossible in Bash and accepted in PowerShell.
	- Fixed in Bash: a value the parser is already waiting for is that value, whatever it looks like. `-m '-Wall added to CFLAGS'` now commits.

- ✅ Code Review 20260727b item 10: PowerShell handed a remote URL to git unquoted in the pre-flight probe.
	- PowerShell expanded `*` and `?` against the current directory first, so the probe answered about a different target than the one git was later given - a URL that should have been refused was classified as an empty remote, and the working tree was committed and a bogus remote configured before the push failed. Bash refused before touching anything.
	- Third recurrence of that class, so the two display-only ssh probes were quoted at the same time.

- ✅ Code Review 20260727b item 11: PowerShell's `pr ok` used a bare fetch where Bash used the guarded one.
	- No credential-prompt suppression (so it could stop and ask mid-command), no ssh connect timeout, and no `origin/HEAD` heal - and a blip there reported the whole command as failed after the merge had already landed on the server.
	- Fixed: one helper mirrors the Bash version and both fetch sites use it.

- ✅ Code Review 20260727b item 12: `release` was the one command with no undo and no idempotency (both implementations).
	- A version it invented was cut even when the target would gain nothing, so a repeated run quietly added tags all pointing at the same commit.
	- Worse after a failed push: the tag existed locally, and the natural re-run bumped again, so the first version was stranded forever.
	- Fixed: an invented version with nothing new to release refuses, and names the tag to push if a previous one never left the machine. A version you type, and promoting a candidate, are deliberate and still work on an already-released commit. Uncommitted or unpushed work counts as something to release, since `release` parks first.

- ✅ Code Review 20260727b item 13: `br land` would delete a leftover `main` or `master` (both implementations).
	- Landing ends in a branch delete, and the protected-branch rule that `br prune` honors was not applied here.
	- Fixed: refused up front, before a plan containing that delete is shown and confirmed.

- ✅ Code Review 20260727b item 14: `--public` and `--private` together meant opposite things in the two builds.
	- Fixed: refused as a contradiction. Silently picking one would publish a repo the caller believes is the other.

- ✅ Code Review 20260727b item 15: the identity probe caches never took effect in Bash.
	- Every use sits inside a command substitution, so the cache filled there was thrown away and the next call probed again - two `gh api user` calls and two `ssh -T` round trips per command, on a link that may be slow or dead. PowerShell was already correct.
	- Fixed: primed once in the shell that owns the variables.

- ✅ Code Review 20260727b item 16: `install.bash --target system` failed with a raw `install` error when `/usr/local/bin` did not exist.
	- The user branch created the directory and the sudo branch did not.
	- Fixed: both create it, with `mkdir -p` rather than `install -d`, which would reset the mode of a directory that already exists. The plan says when a directory will be created.

- ✅ Code Review 20260727b item 17: `br switch <the branch you are on>` previewed an add, commit and push it then did not do.
	- Nothing is lost, but the confirmed plan said otherwise, which is the one thing the preview exists to prevent.
	- Fixed: that case previews only the pull. Parking was deliberately not added instead - on a protected branch it would auto-commit, which the design forbids.

- ✅ Code Review 20260727b item 18: every check named "plans X" was satisfied by the execution echo instead of the plan.
	- The preview is the product's central promise - it is what you read before answering the prompt - and it could have stopped listing the checkout, the back-merge or the push with the suite still fully green.
	- Fixed: assertions about the plan now match against the plan only, sliced out of the run. Eight checks were pointed at it.

- ✅ Code Review 20260727b item 19: the three fuzz checks whose job is "these option combinations are accepted" passed if the options were refused.
	- They used the survive-any-outcome helper, so a valid spelling that stopped being recognized looked fine.
	- Fixed: a helper that requires exit 0, and the combinations respelled so the shared ones are valid in both ports.

- ✅ Code Review 20260727b item 20a: the stronger fuzz assertion immediately found port drift that had been hidden: `-q -y` together was refused in PowerShell.
	- Both spellings were aliases of one parameter, and PowerShell rejects a parameter given twice. Bash takes either or both.
	- Fixed: `-y` is its own switch that means the same thing, so every combination the Bash build accepts is accepted.

- ✅ Code Review 20260727b item 20: `sync`'s commit message had no coverage.
	- It takes a message positionally like `update`, and could have silently fallen back to the auto-generated timestamp with both suites green.

- ✅ Code Review 20260727b items 21-27: the smaller ones, gathered.
	- PowerShell had no version gate where Bash has one, so a Windows PowerShell 5.1 run failed partway through a command on an undefined variable. It now says what to install, up front.
	- `status`, `br list` and `pr <n>` silently ignored trailing arguments while every other command rejected them - a typo looked like it did what you meant.
	- An option or positional typo printed an internal call stack. That is reserved for real crashes; these are usage errors.
	- `gh pr create` was announced with one command line and run with another. It is now announced by hand, matching both its own preview and the way `gh pr review` is already announced.
	- PowerShell's `pr view` blamed the wrong command on failure, and could not see `gh pr list` fail at all. Each call reports itself now.
	- PowerShell dropped the trailing blank line on error and abort exits that Bash prints on every path.
	- The installers say when they fell back to an unverified copy from the tree, rather than quietly downgrading from a checksum-verified release asset.
	- Two first-party shell files were outside the shellcheck gate and one glob in the list matched nothing; the gate now covers all 13, and shellcheck is clean across them.
	- `cicd.bash` printed with `echo -e`, which would animate backslash escapes and ANSI sequences out of a commit message the user typed. It uses `printf` now, like `bin/gitsby` already did - as does the crash dump, which can carry a filename or message.
	- Template leftovers in the argument parser: an instruction addressed to whoever instantiates the template, non-ASCII markers, a kaomoji, an over-long section rule, and a typo.

- ✅ Code Review 20260727b: perf findings reviewed and deliberately not acted on.
	- Measured rather than assumed, with a counting `git` shim: `br list` is 6 git processes and `status` 13, both constant at 41 branches. Only `br prune` scales - about 5.5 per branch, 264 at 41 branches, and still 0.57s. The second containment check per branch is the deliberate re-check at delete time.
	- Nothing on the everyday path forks per item, so there is no problem to fix here. Noted so the next reader doesn't re-derive it.

#### Done - Code review 20260727

Review of the hotfix branches, the gh/ssh identity check, and the docs pass that went with them.

- ✅ Code Review 20260727 item 1: `pr ok <n>` decided where a PR lands from whatever branch you were standing on (both implementations).
	- Nothing asked gh which branch the PR proposes, so accepting a hotfix PR from `dev` skipped the back-merge that keeps the fix from being undone by the next release.
	- The reverse also happened: accepting an ordinary PR while sitting on a hotfix branch merged the default branch into `dev` for no reason.
	- Fixed: the head branch is read from gh up front and drives both the landing target and the hotfix decision. Falls back to the current branch if gh can't say.

- ✅ Code Review 20260727 item 2: the back-merge merged a stale local default branch (both implementations).
	- Found while testing item 1. `pr ok` lands the hotfix on the server, so the local `main` never receives it and merging that branch did nothing at all - silently.
	- `br land` was unaffected, because it checks `main` out and merges into it itself.
	- Fixed: the back-merge uses the fetched `origin/<default>` when there is one, which is the same commit after `br land` and the correct one after `pr ok`. Previews show the ref that actually gets merged.

- ✅ Code Review 20260727 item 3: the ssh identity was read only when the greeting was the first line (Bash).
	- ssh writes host-key and missing-identity-file warnings ahead of it, and both streams are captured, so a match anchored to the whole output missed the greeting.
	- It failed safe (unknown, proceed) but that meant the check quietly stopped working for the multi-account setups it exists to protect.
	- Fixed: matched per line. PowerShell matched anywhere, which had the opposite risk, and is now anchored per line too, so both behave the same.

- ✅ Code Review 20260727 item 4: nothing said gitsby needs bash 4.4, and on macOS it could never get it.
	- `bin/gitsby` was the only file pinned to `#!/bin/bash`. macOS keeps that at 3.2 permanently, so installing a newer bash would not have helped.
	- Too old a bash died on `inherit_errexit` with a raw shell error, and `install.bash` (deliberately 3.2-compatible, for macOS) installed it anyway and only failed at its own verify step.
	- The README Compatibility section covered tool interop and remotes but never the runtime requirement.
	- Fixed: shebang resolves bash through `PATH`; both `gitsby` and `install.bash` refuse early with advice per platform (Homebrew/MacPorts, `pkg`/`pkg_add`, or the package manager), and point at the PowerShell build as the no-bash option. README states the requirement per platform.

- ✅ Code Review 20260727 item 5: the "hotfix changes shipped code" note missed the ordinary case (both implementations).
	- It read the branch tip before `br land` committed the working tree, so a hotfix whose `bin/` edit was still uncommitted - the usual way of making one - got no warning.
	- Fixed: checked after the push.

- ✅ Code Review 20260727 item 6: PowerShell's gh login probe could prompt (PowerShell); `br land` carried a duplicate variable (Bash).
	- Fixed: `GH_PROMPT_DISABLED` set around the call as the Bash side already did, and the duplicate dropped.

#### Done - Code review 20260726

Release-prep pass over what changed since the last review: the noun grouping, `pr create`, and dropping bare `commit`/`pull`.

- ✅ Code Review 20260726 item 1: `br switch` from a dirty protected branch tells you to run a command that no longer exists (both implementations).
	- The refusal offered `gitsby commit` as the deliberate way to keep the work where it is. That command was dropped, so following the advice is a second error.
	- Fixed: it now names `update`, which commits on the current branch. Regression test asserts the suggested command is a real one.

- ✅ Code Review 20260726 item 2: offline only reached the pull in `update` and `sync` (both implementations).
	- `br create`, `br switch`, `br land`, `pr ok`, and `release` each pull as one of their steps, and those pulls ignored `--no-fetch` and an unreachable remote.
	- So the flag documented as "work offline" still went to the network in five of the seven commands that pull, which is exactly the thing the design note says it must not do.
	- Fixed: every in-command pull goes through one helper that applies the same rule. Regression test compares a `--no-fetch` switch (must not advance) against the same switch online (must).

- ✅ Code Review 20260726 item 3: built-in help drifted from the command set (both implementations).
	- `update` was still described as commit-then-pull, `--no-fetch` as skipping only the fetch, and the PowerShell parameter help still listed `pull` and `commit` as commands.
	- The `br create` line said it parks current work first, which is what it does from a feature branch but not from `main`/`dev`, where it carries the work along instead.
	- Also "stash only if dirty" in the summary blurb, describing a manual stash that no longer exists.
	- Fixed: all of the above, in both implementations.

- ✅ Code Review 20260726 item 4: the README command count was stale.
	- It said 13, from before the regroup and before `commit` and `pull` were dropped.
	- Fixed: 7 commands, or 15 counting subcommands, which is what the table below it lists.

- ✅ Code Review 20260726 item 5: the offline test passed on the PowerShell side for the wrong reason.
	- It spelled the flag `--no-fetch`, which PowerShell has no parameter for, and then matched output against a pattern that the resulting complaint about the flag also matched.
	- So the check went green on a command that had failed outright, and no offline behavior was ever exercised there.
	- Fixed: `-NoFetch`, which both implementations accept, and the pattern now matches only the skip message itself.

- ✅ Code Review 20260726 item 6: `br prune` could say "leaving it alone" and still delete the branch's remote copy (both implementations).
	- The delete-time re-check only guarded the local delete; the remote loop ran regardless.
	- Fixed: a branch kept by the re-check keeps its remote copy too.

- ✅ Code Review 20260726 item 7: a merged current branch vanished from `br prune`'s output (both implementations).
	- It was rightly never deleted, but appeared in neither the plan nor the Keeping list.
	- Worst case: it was the only merged branch, and the output claimed nothing was merged at all.
	- Fixed: the plan, the no-op path, and the closing summary all say it is kept because you are standing on it.

- ✅ Code Review 20260726 item 8: the README claimed 100% GitLab compatibility.
	- Every `pr` form, `repo create`, and `repo connect` with an `owner/name` go through `gh`, so they are GitHub-only. That is up to six of the sixteen subcommands.
	- Fixed: the claim now says any Git remote works and names the gh-backed exceptions.

- ✅ Code Review 20260726 item 9: "no version: bump the patch" was only one of three release paths (docs and help, both implementations).
	- A candidate tag resolves to its own release (`v2.0.0-rc1` -> `v2.0.0`), and a repo with no tag at all starts at `v0.1.0`. Neither is a patch bump.
	- Fixed: docs and help now say the next version after the latest tag. A regression check pins the help line.

- ✅ Code Review 20260726 item 10: `br create` still overpromised, in the opposite direction from item 3.
	- Item 3 changed the help from "parks current work" to "brings current work along". Both are half right: work is carried only from `main`/`dev`, and committed and pushed to the current branch otherwise.
	- Fixed: docs and help say carried or parked, and name which case is which. A regression check pins the help line.

- ✅ Code Review 20260726 item 11: the dev installers required a bash version gitsby does not.
	- Both told you gitsby itself needs bash 5+. The real floor is 4.4, set by `inherit_errexit`; design.md already said 4.4 and was the one that was right.
	- Fixed: both installers now check and report 4.4.

- ✅ Code Review 20260726 item 12: smaller doc corrections found in the same pass.
	- design.md said `gh` was needed for "the two commands that need it" - it is three.
	- The Direct-install one-liners never created the target directory, and the PowerShell one wrote to a *nix path inside the Windows section.
	- The README options list omitted `--public`/`--private` and never mentioned that the PowerShell version takes PowerShell-style parameter names.
	- "Every mutating command fetches first" ignored `repo clone` and `--no-fetch`. `br prune` was described as deleting every merged branch, which skips the current-branch and protected-branch exceptions. `repo create`'s steps were listed in the wrong order.
	- design.md's folder list omitted `reference/` and described `assets/` as holding only the demo.

- ✅ Code Review 20260726 item 13: the pre-command fetch could stop and ask for credentials (both implementations).
	- `fpProbeRemote` sets `GIT_TERMINAL_PROMPT=0` for exactly this reason. The fetch that runs ahead of every command did not, so an https remote you can't authenticate to blocks the command at a username prompt - before any of gitsby's own checks get to run, including the ones that would have refused the command anyway.
	- Only shows up with a terminal attached. Without one git fails instantly, which is why the suites were green and silent.
	- Fixed: the fetch disables prompts too. A regression check records the environment the fetch actually receives, since the behavior is invisible without a tty.

- ✅ Code Review 20260726 item 14: two suite checks reached the real github.com.
	- The `repo create refuses when origin is already set` check reuses a fixture whose origin is a real `https://github.com/me/proj.git`, but dropped the `insteadOf` rewrite that every neighbouring check sets. Confirmed by the server's own "Repository not found" reply.
	- design.md says neither suite touches the network, so this was also the thing that surfaced item 13 in the first place.
	- Fixed: the rewrite is back on that check.

- ✅ Show gh's account in the pre-flight, and refuse a gh write that acts as someone else.
	- gh authenticates with its own token and ignores ssh config, so `pr create`/`pr ok`/`repo create` act as gh's account while `git push` acts as the remote alias's key. With per-account aliases those differ, and the pre-flight was naming only the ssh one - the wrong identity for exactly those commands.
	- Found live: from a `t00mietum` repo, gh reports `jim-collier` with READ permission, so a `pr create` there would act as an account that can't do it.
	- Three outcomes, not two. Unknown (no agent, https remote, deploy key, gh logged out) is reported and never blocks - otherwise every CI runner breaks. Only a difference both sides confirm counts.
	- Interactive: warning directly above the confirm prompt. Unattended: error, nothing runs. `--any-identity`/`-AnyIdentity` proceeds, and the mismatch still shows on the identity line.
	- Decided against a general gh-config validator: policing another tool's setup isn't gitsby's job and would turn working commands into refusals.
	- 26 new checks across both implementations, driven by a fake ssh that answers the greeting GitHub really sends and doubles as the git transport. Verified they fail against the pre-feature build.

- ✅ Extend the identity check to `repo create` and `repo connect owner/name`.
	- The first pass skipped them for having no origin to compare. That was wrong: gh never uses a host alias, so the url it is about to set is always `git@github.com:owner/name.git` and the identity is knowable before anything is created. Design note revised rather than appended to.
	- Refuses before `gh repo create` and before `git init`, so a mismatch leaves no remote and no repository behind. Verified against the pre-feature build, which created both.
	- An https protocol means git will use a credential helper rather than a key, so there is no second identity and nothing to compare.
	- Deliberately does NOT rewrite the remote to a matching host alias. Guessing which alias serves an account means inferring the user's ssh setup, and a wrong guess points the repo at the wrong key. `repo connect <full url>` already covers anyone who wants their alias.

- ✅ PowerShell: gh's account was read from a stale exit status.
	- `gh api user | Select-Object -First 1` stops the native command early, so `$LASTEXITCODE` is left over from whatever ran before - in a plain directory that is the failed repo probe, so the login was discarded and every identity came back unknown.
	- Only showed up once `repo create` started needing the login, since that is the one command that runs outside a repository.
	- Fixed by collecting the output with `@()` before selecting, in all three places that read a native command this way. A regression check runs `repo create` from a plain directory and asserts the account resolves.

#### Done - Code reviews 20260725 and 20260723

- ✅ Code Review 20260725 item 1: `release` pushes only the tag when the default branch has no upstream (both implementations).
	- The branch push is gated on an upstream; the tag push is not.
	- Origin ends up holding the release commits as tag payload while its `main` still points at the previous release.
	- Same shape as item 2 of the previous review, which was fixed in `land` but not here.
	- Fixed: an upstream-less default branch is published with `git push -u origin HEAD` before the tag goes up. Regression test added.

- ✅ Code Review 20260725 item 2: `release` refuses a duplicate tag only after it has already committed and pushed (both implementations).
	- The check sat inside the command, past the plan, the confirmation, and the "park current work" step.
	- Nothing is lost, but the run mutates the repo and then dies on something knowable up front.
	- Fixed: the tag-exists check moved next to the version resolution, before anything is shown or run. Regression test added.

- ✅ Code Review 20260725 item 3: `gobr` refuses a dirty protected branch only after the plan is confirmed (both implementations).
	- Same class as item 2, and the same fix as code review 20260723 item 35 applied to the other branch arguments.
	- Fixed: the refusal moved up front, alongside the other branch-argument checks. Regression test added.

- ✅ Code Review 20260725 item 4: `newbr` shows a plan it does not follow when run from `main`/`dev` (both implementations).
	- The preview always listed the commit-and-push steps, but on a protected branch the tree is carried to the new branch instead.
	- The preview is the safety feature, so it misreporting in exactly the case that was special-cased is the wrong way round.
	- Fixed: the plan now branches on protected state and shows the checkout-and-carry steps. Regression test added.

- ✅ Code Review 20260725 item 5: `pr ok <n>` run from the branch that PR came from ends in a failed pull (both implementations).
	- `gh` deletes the branch on the remote through the API, which leaves the local `origin/*` copy in place, so the upstream still looks alive.
	- The trailing `git pull --ff-only` then asks for a branch the remote no longer has, and the whole command reports as failed.
	- Fixed: prune first, and if the branch we are standing on is the one that just went away, check out the merge target and pull that instead. The plan shows the extra step. Regression test added, with the fake `gh` restoring the stale ref so the real condition is reproduced.

- ✅ Code Review 20260723 item 1: `pull` failure strands the autostash (both implementations).
	- Dirty tree gets stashed, then a failed `git pull --ff-only` (diverged or offline) aborts before `git stash pop`.
	- Work vanishes from the tree into the stash with no message; re-runs see a clean tree and never pop it.
	- Contradicts the "never risk losing work" promise; worst finding of the review.
	- Fixed: replaced the manual stash dance with `git pull --ff-only --autostash`; a failed pull now leaves the tree intact. Regression test added.

- ✅ Code Review 20260723 item 2: `land` can delete the remote work branch before the merge ever reaches origin (both implementations).
	- Push of the merge is gated on the target having an upstream; the remote branch delete is not.
	- With a local-only `dev`, the merge stays local but `git push origin --delete <branch>` still removes origin's only ref to those commits.
	- Fixed: an upstream-less target is published first (`git push -u origin HEAD`) before the remote delete. Regression test added.

- ✅ Code Review 20260723 item 3: `newbr`/`gobr` from a dirty `main`/`dev` commit and push WIP straight to the protected branch (both implementations).
	- The "park current work" step is commit+push on whatever branch you're on - including main/dev, with an auto message in quiet mode.
	- Contradicts the tool's own opinions ("don't push to dev, main, or master").
	- Fixed: `newbr` carries dirty work to the new branch (no commit on the base); `gobr` refuses with guidance instead of auto-committing; sync preview now names the branch being pushed. Regression tests added.

- ✅ Code Review 20260723 item 4: a commit message containing `-h`/`-v` as a word makes the bash version silently no-op with exit 0.
	- The early help check scans the whole joined argv, so `gitsby commit "add -v flag"` prints the banner and skips the commit.
	- Bash only; the pwsh port checks just the command slot.
	- Fixed: -h/-v now only recognized in the command slot, matching the pwsh port. Test added.

- ✅ Code Review 20260723 item 5: non-tty stdin silently auto-confirms all mutating commands (both implementations).
	- Piped/cron/redirected input behaves as implicit `-q`: release/land/sync run with zero confirmation, even `echo n |` is ignored.
	- Should fail closed like the installers do (require explicit flag when no tty).
	- Fixed: mutating commands with no tty and no -q abort with guidance; read-only commands keep the implicit quiet. Tests added.

- ✅ Code Review 20260723 item 6: unquoted two-word positional message silently drops the second word (both implementations).
	- `gitsby commit Fixed bug` commits as "Fixed"; three words error but two don't.
	- Fixed: a non-empty third positional is rejected with "quote your commit message" (both implementations). Test added.

- ✅ Code Review 20260723 item 7: git failures print the raw trap dump instead of a plain error (bash).
	- Diverged pull shows "Signal: ERR / Message: '--ff-only' / Command#: '"${@}"'" - reads as a gitsby crash.
	- The pwsh port already prints a clean one-liner; match it.
	- Fixed: fRun reports a plain one-liner ("'git ...' failed (exit N)") and exits; the trap dump stays for real script errors. Tests added.

- ✅ Code Review 20260723 item 8: `echo -e` in fEcho_Clean expands escapes in user data (bash).
	- Mangles commit messages/filenames in the preview; a hostile repo's filenames (raw ESC bytes, C-quoted by git) can spoof the confirm display.
	- Switch to `printf '%s\n'`.
	- Fixed: fEcho_Clean uses printf '%s\n'; escape bytes in user data stay inert.

- ✅ Code Review 20260723 item 9: pwsh branch-name comparisons are case-insensitive.
	- `-eq` treats 'Main' = 'main'; newbr can branch off the wrong base. Use `-ceq`/`-cne` at the seven branch compares.
	- Fixed: -ceq/-cne at the branch compares; 'ok' and prompt answers stay case-insensitive.

- ✅ Code Review 20260723 item 10: pwsh `release` crashes under strict mode when the newest v* tag isn't X.Y.Z.
	- `v1.2` or `v2020` throws on array indexing; bash handles the same input gracefully.
	- Fixed: split parts padded before arithmetic (v1.2 -> v1.2.1, v2020 -> v2020.0.1); bash pads the same way now too. Verified on both.

- ✅ Code Review 20260723 item 11: install.ps1 downloads to a predictable temp filename.
	- `gitsby-install-$PID.ps1` in shared temp; race window before install. install.bash already uses mktemp - mirror it.
	- Fixed: downloads into a fresh random private subdirectory; recursive cleanup in finally.

- ✅ Code Review 20260723 item 12: remote URLs print verbatim, leaking embedded credentials (both implementations).
	- An `https://user:token@host/...` origin echoes the token on every run, including CI logs. Mask the userinfo part.
	- Fixed: userinfo masked in the displayed URL (https://***@host) in both implementations. Tests added.

- ✅ Code Review 20260723 item 13: default-branch detection trusts a possibly missing/stale local origin/HEAD (both implementations).
	- Ref goes stale on upstream master->main renames and can be absent on git < 2.47; release then tags the wrong branch.
	- Cheap fix: `git remote set-head origin --auto` alongside the existing fetch.
	- Fixed: successful fetch now runs git remote set-head origin --auto, healing a missing or stale origin/HEAD; local read remains the offline fallback.

- ✅ Code Review 20260723 item 18: fMustBeInPath shells out to external `which` (bash).
	- `which` is absent on some minimal distros, making every command abort with "Not found in path: git". Use builtin `command -v`.
	- Fixed: builtin command -v; dropped the stray second fThrowError argument.

- ✅ Code Review 20260723 item 21: `pull` stashes a dirty tree before checking for an upstream (both implementations).
	- No-upstream + dirty = pointless stash push/pop that rewrites every file's mtime. Check upstream first. (Goes away if item 1 lands as `--autostash`.)
	- Moot: item 1's `--autostash` fix removed the manual stash entirely; no upstream now means no stash is touched at all.

- ✅ Code Review 20260723 item 23: fetch without `--prune` leaves stale origin/* refs that existence checks trust (both implementations).
	- Stale refs make gobr check out dead branches, land abort on the remote delete, newbr refuse reusable names.
	- Fetch with `--prune`; make land's remote delete tolerant of "remote ref does not exist".
	- Fixed: fetch uses --prune, and land's remote delete warns-and-continues instead of dying if the branch is already gone.

- ✅ Code Review 20260723 item 24: pwsh skips native exit-code checks in the pr/read-only paths.
	- `gh pr view` failure isn't caught before `gh pr diff` runs; `listbr`/`status` exit 0 even if git fails.
	- Fixed: gh pr view checked before the diff; listbr throws on git failure.

- ✅ Code Review 20260723 item 25: pwsh parses Windows drive-letter remotes (`C:\...`) as ssh hosts.
	- Pre-flight then shows a bogus SSH identity line. Treat a single-letter-colon prefix as a path, like git does.
	- Fixed: single-letter-colon prefixes are treated as drive paths, not ssh hosts.

- ✅ Code Review 20260723 item 26: `ssh -G` called without `--` on a host string derived from .git/config (both implementations).
	- Option-shaped "hosts" from a hostile config parse as ssh options. Currently fails closed, but add `--`.
	- Fixed: -- added in both implementations.

- ✅ Code Review 20260723 item 27: install-dev.ps1 passes an option-shaped `-Directory` straight to `git clone`.
	- Binds as a real clone option (`--config=...`). install-dev.bash already rejects `-*`; mirror it (and/or pass `--` before the path).
	- Fixed: option-shaped -Directory rejected, same wording as the bash guard.

- ✅ Code Review 20260723 item 28: install.ps1 lacks the downloaded-content sanity check install.bash has.
	- No shebang check before install+execute; wrong-content 200s (captive portal, truncation) get installed. Mirror the `^#!` test.
	- Fixed: first line must match ^#! before install, mirroring install.bash.

- ✅ Code Review 20260723 item 29: gitsby.ps1 sets GIT_MERGE_AUTOEDIT process-wide, persisting in the caller's pwsh session.
	- The var is redundant anyway (merges pass `-m`); just delete the line.
	- Fixed: line deleted (merges pass -m, so it was redundant).

- ✅ Code Review 20260725 item 6: `release` with no version bumps the patch of a candidate tag's base, skipping that base version (both implementations).
	- After `v2.0.0-rc1`, a bare `release` proposed `v2.0.1` rather than `v2.0.0`.
	- Fixed: a candidate's own version is now what comes next, so `v2.0.0-rc1` leads to `v2.0.0`.
	- The tag scan also needed `versionsort.suffix=-`, since git's default version sort ranks `v2.0.0-rc1` above `v2.0.0` and would otherwise propose an already-cut version once the real release exists.
	- Regression tests cover both halves: the candidate's version is taken, and the release after it bumps normally.

- ✅ Code Review 20260723 item 14: bound the unconditional pre-command fetch and add an offline escape hatch (both implementations).
	- A dead/black-holed remote blocks every command for the full TCP/ssh timeout before the "offline?" warning.
	- Add a connect timeout on the fetch and a `--no-fetch`/offline flag.
	- Done: ssh fetches get ConnectTimeout=3 (user GIT_SSH_COMMAND respected), and --no-fetch/-NoFetch skips the fetch entirely.

- ✅ Code Review 20260723 item 15: cache per-run-constant git facts (both implementations).
	- Measured: 12 git spawns for `status`, 45 for `land`, 55 for `release`; upstream/branch/ahead-behind re-queried repeatedly in one display block.
	- Resolve once after the fetch, pass down; keep live re-checks only where state actually mutates. Matters most on Windows.
	- Done: default branch and merge target now resolve once per run post-fetch; branch/upstream/ahead checks stay live since checkouts change them mid-command.

- ✅ Code Review 20260723 item 16: close the test-suite gaps that hid this review's bugs.
	- Failed-pull-with-dirty-tree, no-remote fixtures, slash branch names, `-m`/`-m=` flag forms, option-like words in messages, release from a feature branch.
	- Done so far: failed-pull-with-dirty-tree, upstream-less land, dirty-protected-branch newbr/gobr fixtures.
	- Done: all listed fixtures added (failed pull, no-remote sync/newbr/land, feat/x names, -m and -m= forms, option-like message words, release from a feature branch). Suite 140 -> 199 checks.

- ✅ Code Review 20260723 item 17: README has no Commands/Usage section.
	- The pitch is "Gitsby has 11" commands, but they're never listed or demonstrated. Add the help table plus a worked newbr -> update -> land example.
	- Done: Commands section added (table of all 11, options, a typical-day flow, gh note for pr/release).

- ✅ Code Review 20260723 item 19: installer checksum + version pinning - confirms the already-open installer item below.
	- Publish SHA256SUMS from cicd, verify in both installers, allow pinning an exact tag; document that `--ref` skips verification.
	- Done: installers verify release-asset downloads against a SHA256SUMS release asset when published (note-and-continue when absent); cicd/utility/gen-checksums.bash generates it for release cuts; --ref/-Ref pins a tag but skips verification (documented in README).

- ✅ Code Review 20260723 item 20: "latest release" lookup uses the unauthenticated GitHub API (60 req/hr).
	- Shared-NAT/CI installs will 403. Read the tag from the `releases/latest` redirect Location header instead; keep the API as fallback.
	- Done: tag read from the releases/latest redirect (curl url_effective / wget Location / pwsh 302 handling); API scrape kept as fallback; rate-limit mentioned in the error.

- ✅ Code Review 20260723 item 22: fIsAhead materializes the whole ahead-range log just to test emptiness (both implementations).
	- Use `git rev-list -n 1 '@{u}..'` (or the cached ahead count from item 15).
	- Done: git rev-list -n 1 in both implementations.

- ✅ Code Review 20260723 item 30: needless external `head`/`wc` pipeline stages (bash).
	- Use `mapfile -n 1` / array counts, minding that a bare `read` returns nonzero on empty input under strict mode.
	- Done: tag lookup via mapfile -n 1; the stash wc pipelines were already removed by item 1.

- ✅ Code Review 20260723 item 31: positional parameter binding in the ps1 files (style guide requires named).
	- gitsby.ps1 one spot (`Get-Command ssh`); install.ps1 and install-dev.ps1 throughout (Join-Path, Move-Item, Test-Path, Get-Command).
	- Done: named parameters at the flagged sites in all three ps1 files.

- ✅ Code Review 20260723 item 32: no comment-based help on any gitsby.ps1 function.
	- Either add `.SYNOPSIS` to the non-trivial functions, or scope the style-guide rule to script-level + exported functions.
	- Done: style-guide rule scoped to script level + exported/public functions; private helpers take a terse ## comment.

- ✅ Code Review 20260723 item 33: installer output ends without the trailing blank line the style guide requires (all four installers).
	- Done: all four installers end with a blank line.

- ✅ Code Review 20260723 item 34: rename fpPreview's `p` padding variable to `pad` (matches the pwsh twin).
	- Done: renamed.

- ✅ Code Review 20260723 item 35: branch-argument validation runs after the status display and confirm prompt (both implementations).
	- `newbr` with a bad/missing name shows a nonsense plan ("git checkout -b ") and only errors after "y". Hoist checks next to the existing pr/release ones.
	- Done: newbr/gobr arguments validate right after the release-version check, before status/preview/prompt; command functions no longer duplicate the checks. Test added.

- ✅ Code Review 20260723 item 36: `gitsby help` / `gitsby version` are unknown-command errors (both implementations).
	- Alias the bare words to the -h/-v paths; one case entry each.
	- Done: bare words route to the same paths as -h/-v (both implementations). Tests added.

- ✅ Code Review 20260723 item 37: usage errors carry "Reverse call stack: fMain()" noise (bash).
	- Suppress the stack line for expected validation errors; keep it for real internal failures.
	- Done: fThrowError_Usage variant skips the stack line; all user-facing validation errors use it. Real script errors keep the stack.

- ✅ Code Review 20260723 item 38: accept `-y`/`--yes` as a prompt-skip alias (both implementations).
	- Installers teach -y, gitsby only takes -q; and -q's real function is "assume yes", not quiet. Keep -q, add -y, fix the help wording.
	- Done: -y/--yes (bash) and -y/-yes (pwsh) alias -q; help wording now says "assume yes". Test added.

### Future and/or deferred

### Canceled
