# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
## vNEXT - DATE

### Notes

### Added

### Changed

### Removed

### Other work
-->

## vNEXT

### Added

- Commands that go through gh now act as the remote's own account when gh already holds it, chosen per run rather than by switching gh's active account. The account is named in the identity block, and `--any-identity` (`-AnyIdentity`) turns it off. A remote whose owner gh has no account for - an org, or anyone else's repo - is left alone.

### Fixed

- The identity probe asks as the key git would actually push with, following `GIT_SSH_COMMAND` and then `core.sshCommand`. It used to run a bare `ssh`, so a repo that selects its key through config - the usual way to hold two accounts on one machine - was reported as the default key's account while git pushed as somebody else. Where gh's account happened to match the default key, the mismatch check passed while both halves were wrong.

- The identity line names the key from the same source, so it can no longer report the right account beside the wrong key file.

- `fetch` and the remote probe no longer override a repo's configured ssh key. Both set `GIT_SSH_COMMAND` for the connect timeout, which outranks `core.sshCommand`, so a private repo reachable only through the repo's own key reported as offline.

## v2.0.2 - 2026-07-31

### Added

- The pre-flight display for `br create` and `br hotfix` now names the branch it is about to make, and the branch it will come off: `New branch ...: main :: hotfix/readme`. The current-branch line reports where you are standing, which for a hotfix started from `dev` is not where the new branch begins - so nothing on screen connected the two.

- `br list` now says what the repo's default branch is before listing.

### Changed

- Branch names in the status and pre-flight display are shown against the branch they land on, as `dev :: feature/retries`. `main`, `master` and `dev` are shown bare, since they are not branched off anything you would work from.

- The repo's default branch has its own line rather than being appended to the current-branch line in parentheses.

- The status block labels the branch you are on `Current branch:` rather than `Branch:`, so it reads against the `Default branch:` and `New branch:` lines beside it.

### Fixed

- The PowerShell installer verifies the download again. It read the release's `SHA256SUMS` as text, but GitHub serves that file as binary and PowerShell returns the body as raw bytes for anything it doesn't consider text - so no checksum was ever found, the default install went unverified, and it said the release had no `SHA256SUMS` when it did. The Bash installer was never affected.

- `br list` no longer refuses to run in a repo whose default branch can't be told. It is a read-only command - like `status`, it now reports `Default branch: unknown` and lists the branches, which is exactly what you need to see to fix the situation.

## v2.0.1 - 2026-07-30

### Fixed

- The SSH line in the status and pre-flight display named the local login rather than the account being acted as. It asked `ssh -G` about the bare host, and with no user in the target ssh answers with the OS login name, so a push as one GitHub account displayed as another name entirely.

- The offline messages now tell the truth. A parking push with nothing to send says "Nothing to push." instead of claiming committed work awaits; the skipped-push warning names the branch it means, since the command may move off it next; and an offline hotfix land names the two commands that actually publish the default branch - a bare `sync` runs from `dev` after the back-merge and would have left the hotfix unshipped.

### Changed

- The SSH line now leads with the account the key authenticates as, resolved by asking the host, with the connection and key after it. The connect user is the same for every GitHub account and the key shown is only the first candidate ssh would offer, so neither one answered the question the line exists for. Offline it says `unknown` instead of guessing.

## v2.0.0 - 2026-07-28

### Notes

- First release since 2022, and a rewrite rather than an update.

- Commands were reorganized, and the pre-2.0 names are gone. The tool is also invoked by a new name, so nothing that worked before was silently changed underneath you.

- Gitsby now comes in two languages, Bash (for *nix, Darwin, and WSL) and PowerShell (for any platform that PowerShell v7 runs on including Linux, macOS, and Windows); with the same commands and the same behavior in each.

- Running it needs Git, plus either bash 4.4+ or PowerShell 7+. macOS ships bash 3.2 and never replaces it, and the BSDs ship none, so on those either install a current bash (ahead of `/bin/bash` on your `PATH`) or use the PowerShell build. Gitsby and its installer both say which applies rather than failing with a shell error.

### Added

- PowerShell version, `bin/gitsby.ps1`, for Windows and anywhere else PowerShell 7 runs.

- Installers for both versions, `install.bash` and `install.ps1`, run straight from a shell one-liner. Each shows its plan and asks first, installs for you or system-wide, and checks the download against the release checksums. A branch or tag given by name has to look like one, so it can't redirect the install somewhere else; and with no terminal to ask on, they stop rather than assume yes.

- Setup scripts for contributors, `install-dev.bash` and `install-dev.ps1`: clone the repo, switch to `dev`, and check the tooling.

- `repo clone` command: get a repo you don't have yet. Derives the directory from the URL, checks out `dev` when the repo has one, and re-running it is a no-op.

- `repo create` command: make the GitHub repo and publish to it in one step. Takes an `owner/name` target, creates it via `gh` (`--public`/`--private`; private by default), then initializes, commits, and pushes.

- `repo connect` command: publish local-only work to a remote that already exists and is empty, by URL or `owner/name`. Initializes the repo if needed, commits, and pushes. Refuses remotes that already have history, remotes that don't exist yet (that's `repo create`), and won't change an existing origin.

- `pr` command: open a pull request (`pr create`), list open ones, view one with its diff, or accept one (approve + merge + branch delete), via `gh`. `pr create` pushes the current branch first, targets `dev` when the repo has one, and titles the PR from the last commit subject unless you give a title.

- `release` command: merge dev into main `--no-ff` (when the repo has a dev branch), tag, and push. With no version given, bumps the patch of the latest `v*` tag.

- `br hotfix` command: branch off the default branch as `hotfix/<name>`, to correct what is already published without waiting for a release. Landing it merges to the default branch and then carries the change back into `dev`, so the next release can't undo it. Warns if the branch touched `bin/`, since shipped code on the default branch no longer matches the latest release.

- `br prune` command: delete every branch already merged into `dev`/`main`, local copy and remote copy both. Branches that aren't merged yet are listed and left alone, and there is no flag to override that. `br land` and `pr ok` clean up after themselves, but nothing cleaned up after a PR merged from the web UI, or after a branch you walked away from.

- GitHub account shown in the pre-flight for every `gh`-backed command, since `gh` acts as its own token's account rather than the one your SSH key authenticates as. Commands that write through `gh` compare the two: a confirmed mismatch warns interactively and is refused unattended, and `--any-identity`/`-AnyIdentity` proceeds anyway.

- `repo create` and `repo connect` list the files they are about to publish, before asking. It is the one command that hands a whole directory over for the first time, possibly publicly, and the list is what `git add --all` will really add - `.gitignore` and `core.excludesFile` honored - so a stray `.env` or key is visible while you can still say no.

- Pre-flight display, before the confirmation prompt on every mutating command (and on `status`): the SSH identity a push or fetch will present (host aliases resolved to the real host, user, and key), the author that will be stamped on commits, ahead/behind counts, and the files a pull would bring in.

- `--no-fetch` to skip the fetch that every command starts with, for working offline.

- `-y`/`--yes` as an alias for `-q`, and `help`/`version` as bare words.

- A PowerShell section in `git_notes_and_oneliners.md`, mirroring the Bash one task for task.

### Changed

- The PowerShell files no longer carry a byte-order mark. It stopped both installer one-liners from running at all, and stopped `gitsby.ps1` from being executable directly on Linux and macOS.

- Commands you reach for daily stay one word: `update`, `sync`, `status`, `release`. The rest are grouped under a noun - `repo clone` / `repo create` / `repo connect`, `br` / `br create` / `br switch` / `br land`, and `pr` / `pr create` / `pr <n>` / `pr ok <n>`. `repository` and `branch` spell out if you prefer.

- The pre-2.0 command names (`scompul`, `spush`, `scommit`, `spull`, `mkbranch`, `chbranch`, `list`, `mtm`) were removed rather than aliased. Not all of them worked, and 2.0 is a clean break under a new tool name.

- `br create`, `br switch`, and `br land` branch off / land on `dev` when the repo has one, else the default branch. `br land` refuses to run from the default branch.

- Pulling no longer risks stranding your work. A pull that can't fast-forward leaves the working tree exactly as it found it.

- `br create` carries uncommitted work onto the new branch instead of committing it to `main`/`dev` first. `br switch` refuses and says what to do instead.

- `br land` publishes an unpushed target branch before deleting the branch it merged, so the work always reaches the remote first.

- `release` now fast-forwards dev to main afterward, so dev includes the release merge and tag. If dev gained commits mid-release, the fast-forward is skipped with a warning instead of discarding anything.

- `pr ok` refuses when there are uncommitted changes, or commits that never reached the remote - on the current branch or on the pull request's own branch, whichever you are standing on. Merging deletes that branch, and anything only local would be outside both the pull request and the merge.

- `update` and `sync` now pull *before* they commit. Committing first created a local commit, so any remote that had moved ahead was diverged and the fast-forward-only pull refused - the everyday case. Pulling first fast-forwards and your work lands on top, keeping history linear.

- An unreachable remote now degrades pushes as well as pulls. The commands that mean something locally still run and say what they skipped - `br create` and `br hotfix` make the branch, `br switch` switches, `br land` merges, all of it publishable later with `sync`. `br land` leaves the remote copy of the branch alone until the merge has been pushed, since until then that copy is the remote's only ref to the work.

- `sync`, `pr create`, `pr ok` and `release` refuse up front when the remote is out of reach, and name what to do instead. They exist to publish, so failing halfway through on raw git output - or worse, reporting success having sent nothing - was the wrong answer.

- `--no-fetch` skips the pull as well as the pre-command fetch, in every command that pulls. It does not stop a push: it declines the incoming round trip, which is the ordinary reason to pass it.

- Mutating commands refuse to run without a terminal unless you pass `-q`/`-y`, so a piped or scheduled run can't silently confirm itself.

- A conflicted working tree is never committed. A pull whose stashed work conflicts on the way back in still reports success, so the conflict markers used to be staged, committed, and pushed. The conflicted files are named instead, and your original work is left where git kept it.

- The default branch can be called anything. It is read from the remote, then `main`, `master`, `trunk`, or your only branch. When it genuinely can't be told, commands stop and say so rather than assuming `main` - which used to mean work committed to a branch that was never checked, and a merge into the wrong one.

- `release` refuses a version it invented when there is nothing new to release, and names the tag to push if a previous run's tag never left the machine. A version you give it, and promoting a candidate, still work on an already-released commit.

- `--help` works after a command in both builds (`gitsby br create --help`). `-v` after a command is refused rather than quietly printing the version and doing nothing.

- A commit message can start with a dash: `-m '-Wall added to CFLAGS'`.

- `--public` and `--private` together are refused instead of resolving differently in each build.

- Credentialed remote URLs are masked wherever they are printed, not only in the plan.

- Remote URLs with an embedded password or token print masked.

- Status now shows a compact one-line-per-file change list instead of `git status`'s long form, truncated to the terminal width and capped so a large working tree can't scroll the prompt out of view.

- Output starts and ends with a blank line, for breathing room between shell prompts.

- Errors read as plain one-line messages instead of a script dump.

### Removed

- Every pre-2.0 command name. See the reorganization note above.

- The bare `commit` and `pull` commands. Both were ways around the workflow the tool exists to enforce: `commit` alone leaves work committed but unshared, and `pull` alone was the only place gitsby let you take upstream changes without parking your own. `update` does both, in the right order.

### Other work

- Both versions carry a regression suite and a fuzz suite.

- The demo at the top of the README is a real session, so it shows what the tool actually does rather than an idealized version of it.
