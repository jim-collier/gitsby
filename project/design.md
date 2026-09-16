<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Design

Design, requirements, and direction. The active bug and feature task list lives in [backlog.md](backlog.md).

This is a decision log, not a specification. Each entry says what was decided and - where it matters - what was rejected and why, so a later reader can tell a considered choice from an accident. Entries are revised in place when the thinking changes rather than appended to, so what is here is what is currently true.

## Table of contents

<!-- TOC -->

- [Table of contents](#table-of-contents)
- [Goals and non-goals](#goals-and-non-goals)
- [Assumptions](#assumptions)
- [Project structure](#project-structure)
	- [Folder structure](#folder-structure)
	- [Logical code structure](#logical-code-structure)
	- [Execution flow](#execution-flow)
- [Direction decisions](#direction-decisions)
- [Branching model](#branching-model)
	- [How the common models compare](#how-the-common-models-compare)
	- [Which model this is](#which-model-this-is)
	- [Why not GitHub Flow](#why-not-github-flow)
	- [The GitFlow author's caveat](#the-gitflow-authors-caveat)
	- [Hotfix branches](#hotfix-branches)
	- [Enforcement](#enforcement)
	- [Repos that have no dev branch](#repos-that-have-no-dev-branch)
- [Architecture](#architecture)
	- [Software stack](#software-stack)
	- [UI](#ui)
	- [Testing](#testing)
	- [Demo](#demo)
	- [Release policy](#release-policy)
	- [Automating a release](#automating-a-release)

<!-- /TOC -->

## Goals and non-goals

The non-goals do more work than the goals. Most of what makes gitsby small is a decision not to do something, and those decisions were previously scattered across three sections and another document.

Goals, in priority order:

1. **Bulletproof.** No command may risk losing work - yours or anyone else's. Every one is idempotent, tolerant of a previous run having been interrupted, and safe to run at any time.
2. **Unsurprising.** Every mutating command shows the repo state, then the exact git it will run, then asks. Nothing happens that was not read first.
3. **Useful.** In that order: a useful command that can surprise you is not worth having.

Non-goals, each one deliberate:

- **Covering all of git.** Roughly 90% of git's complexity serves about 10% of the cases. Partial staging, rebase surgery, conflict resolution, multiple remotes: those belong to raw `git`, and gitsby stays out of the way for them rather than growing a worse version of each.

- **Being a git replacement.** Gitsby, `git`, `gh`, Lazygit and Tig are meant to be intermixed on the same repo, in any order. Anything that would make gitsby the only safe tool for a repo is off the table.

- **Keeping state.** No database, no metadata, no dotfile in the repo. Everything is asked of git and `gh` at the moment it is needed, so stopping mid-project leaves nothing to undo, and no state of ours can disagree with the repo.

- **Policing another tool's configuration.** Gitsby names who you are about to act as; it does not validate `gh`'s setup, rewrite your `~/.ssh/config`, or refuse a command because another tool is configured unusually.

- **Guessing.** Where an answer cannot be established, the display says "unknown" and the command either proceeds or refuses by name. A name that is merely likely is worse than none, because it gets believed.

- **Requiring configuration.** A machine with nothing set up must behave exactly as it did before any of this existed. Every account feature degrades to silence.

- **Running anywhere but where the binary runs.** One static binary, no runtime, no interpreter, nothing installed alongside it - which is also why there is no plugin system and no scripting surface beyond `raw`.

## Assumptions

- Any repo gitsby touches may also be touched by raw `git`, `gh`, or an IDE - before, during, and after. Nothing gitsby does can be allowed to confuse those tools.

- Repo state is never assumed. Every command re-checks what it needs at the moment it needs it, because the last command may have been interrupted, or someone else may have moved the remote.

- The awkward cases (partial staging, multiple remotes, rebases, conflict surgery) belong to raw `git`. Gitsby covers the common path and stays out of the way for the rest.

## Project structure

### Folder structure

- `src-go/` - the implementation. Package `main`, one file per concern.

- `legacy/` - the Bash and PowerShell builds, frozen at v2.1.0, and the installers of that era. Reference only; a hotfix to 2.x branches from the tag, not from here.

- `cicd/` - the local pipeline, its config, and the test, fuzz and comparison suites. Everything the demo gif is built from lives together under `cicd/utility/demo/`.

- `project/` - this file, the backlog, and the UI and UX style guide.

- `assets/` - the logo and the demo shown at the top of the README.

- `reference/` - notes kept for lookup, not published as project docs.

- Root - the two installers, the license, and the public docs.

### Logical code structure

The command flow, in order:

1. Parse arguments, and collapse a noun and its verb (including the unpublished spellings) into one command name.

2. Refuse anything unworkable up front: unknown commands, bad branch names, a version that is already tagged, no terminal to confirm on.

3. Fetch, so everything displayed afterward is current.

4. Show the repo state, then the exact commands about to run, then ask.

5. Run them, each one state-checked at the moment it runs.

6. Show the state again.

The Bash and PowerShell files were ports of each other, and were kept in step for as long as they were the implementation. Both are frozen at v2.1.0; the Go build is the only one that moves - see "Direction decisions" below. The suites run against it alone, and the comparison suite is what keeps its answers matching the frozen ones.

### Execution flow

- Every mutating command is preview-then-confirm. `-q`/`-y` skips the prompt; nothing skips the state checks.

- The preview is a static recipe per command, with `*` marking steps that only happen if the repo state calls for them. It has to match what the command actually does, including where the command branches on state.

- No command shells out through `eval`. Arguments are passed as arrays, so a message or branch name is never re-parsed.

- Any command named inside an error message, or in the built-in help, has to be one the parser still accepts. The help is the only documentation most people read, so it drifting is a defect, not a typo.

- A recursive or forced removal may only target a path the running script itself created, and has to be able to prove it.
	- In practice that means the path came straight from `mktemp` and nothing else ever assigns it.
	- Where a path arrives from outside - an argument, an environment variable - proof means a marker the script wrote when it built the directory. Absent marker, absent removal.
	- Every such removal is written so an unset variable stops it rather than widening it, because the failure mode of getting this wrong is not recoverable.
	- The one product-side temp path is the throwaway git dir the publish preview uses. It is removed on the exit path, so an interrupt cannot strand it.

## Direction decisions

- The host decides the tool, and the tool is reached for only once the host is known to be one it serves.
	- Gitsby began as a GitHub program and reached for `gh` whenever it wanted anything from a remote. Most of what it does is Git, and Git does not care whose server it is - so among these options, it was decided that everything answerable with Git alone must work on any host with no host-specific client installed.
	- Where `origin` points is established first, from the remote URL, with any `ssh_config` alias resolved. `gh` serves `github.com` and whatever `GH_HOST` names, so Enterprise stays on the `gh` path; `tea` serves Gitea and Forgejo. Some distributions install tea as `tea-cli`, and both spellings are looked for.
	- A remote whose host cannot be named - a local path, or a URL shape not parsed - is deliberately *not* a refusal. "We could not tell" and "it is definitely not GitHub" are different answers, and only one of them is gitsby's to assert; such a remote falls through to `gh` exactly as before. This follows the rule already standing for remote owners.
	- `repo create` and `repo connect owner/name` stay GitHub-only. They are about GitHub specifically rather than about whichever host a repository happens to use.

- The identity gate asks about the host in question, not about GitHub.
	- Two accounts disagreeing about who you are is the same outward-facing mistake wherever it happens, so a write through any host's CLI is compared against the key Git pushes with, and the message names the tool that would have acted rather than always saying `gh`.
	- The push-side check reads the account's login on the host being pushed to. `ghaccount` is a GitHub login and answers for GitHub alone; `user` answers anywhere. Keyed on `ghaccount` alone the gate silently stopped guarding every non-GitHub account.
	- An account naming no login on this host makes no claim, so there is nothing to compare - and that is deliberately not read as a match. Unknown stays unknown on both sides: a `tea` with no login configured, like an unreachable `gh`, has said nothing about who you are, and refusing on that would refuse every unconfigured machine.

- Every run says which build it came from.
	- A version alone does not identify a build: between two releases there are dozens, and the one someone is reporting on is usually not a tagged one. So each build carries a build number - minutes from the start of 2000, Crockford base32, five characters until 2063 - printed next to the version, as `gitsby v2.1.0 build dbrk8`.
	- Crockford's alphabet leaves out I, L, O and U, so a build number read aloud or retyped comes back as the one it was.
	- It is derived from the commit's own date, not from the clock at build time. A clock-derived number would change on every rebuild, which would mean nobody, including us, could rebuild a published binary to its published checksum - the same property `-buildvcs=false` exists to protect. As a consequence the release cross-builds twice: once in phase 1 as a compile gate, and again in phase 3 from the tagged commit, which is where the uploaded bytes come from.
	- A hand-run `go build` stamps nothing and reports no build number at all, rather than one invented from the clock. A number that moves every minute would say the opposite of what a build number means.
	- Output starts with the build line so a bug report carries it without being asked. Not under `-q`, which is the machine-readable mode, and never on `raw git`/`raw gh`, which exist to hand a tool's output back unchanged. `--version` and the help screen already printed a version line and gained the build number there instead of a second line saying the same thing.

- An account's credentials are only credentials where that account banks.
	- Accounts gained `host` (defaulting to `github.com`, which is what every config written before the key existed meant) and `user`. If an account's host is not the host `origin` is on, nothing is applied and the identity block names both hosts.
	- A non-GitHub token is exported under its own variable, never as `GH_TOKEN`: `gh` reads that one, and every child process would otherwise inherit a credential for a host `gh` would try to use it on.
	- The credential helper is written for the host actually being authenticated to. `user` exists because Gitea checks the username an HTTPS push presents where GitHub ignores it.
	- Neither the token nor the username is interpolated into the helper - both are read from the environment when it runs. The helper is a string Git hands to a shell, and the login reaching it can come from `GITSBY_ACCOUNT`, from a git config key, or from the config file, none of which is a place to accept shell. Interpolating the login put whatever those said inside the command Git runs; the environment removes the class rather than filtering it.

- There is no bare `commit`, and no bare `pull` that skips the commit. Both were escape hatches around the workflow the tool exists to enforce.
	- `commit` alone produces exactly the state gitsby was written to prevent: work committed locally that never reaches the remote, diverging quietly until the merge is painful.
	- `pull` alone was the only place gitsby let you take upstream changes without dealing with your own work first, which contradicts what it does everywhere else - `br switch`, `br merge`, and `pr create` park it; `br create` off `dev`/`main` carries it onto the new branch.
	- We decided the asymmetry settles it: dropping a command before release costs nothing, and adding one back later breaks nobody. Removing one after release would.
	- Removing `pull` exposed a real bug it had been masking - see the ordering decision below.
	- The word came back later as one of the spellings of `pullcom`, which does not reopen this: an alias onto the command that pulls *and* commits structurally cannot skip the commit.

- `pullcom` and `sync` pull *before* they commit.
	- Committing first mints a local commit, so a remote that has merely moved ahead is now diverged and a fast-forward-only pull must refuse. That is the everyday case, not an edge one, and it was failing.
	- Pulling first fast-forwards under `--autostash`, so the dirty tree rides over and the commit lands on top. History stays linear and fast-forward-only stays satisfiable, which is the whole reason the tool never merges behind your back.
	- Nothing is risked by pulling first: on a failed pull `--autostash` restores the tree as it found it, rather than stranding work in the stash. (A restore that conflicts is the one case git leaves the entry behind, and it says so.)

- Being offline must never turn a good commit into a failed command, now that `pullcom` is the only way to commit.
	- A remote that can't be reached warns and skips the pull. A remote that *is* reachable but can't fast-forward is a real problem and still fails hard - the distinction is what the pre-command fetch already discovered.
	- `--no-fetch` declines the incoming round trip, so it skips the pull as well as the fetch. Skipping only the fetch and then pulling anyway would have saved nothing. It is not a way to say "I am offline" - see the offline rule below for why that distinction is deliberate.

- The command set is split by how often you type it. Daily verbs stay one word (`pullcom`, `sync`, `status`, `whoami`, `release`); everything else is grouped under a noun (`repo`, `br`, `pr`).
	- Among the options considered, we decided the extra word is worth it for infrequent commands. It buys discoverability - three nouns to explore instead of a flat list to memorize - and it retires mashed-together abbreviations like `newbr`/`gobr`/`listbr`.
	- One verb per action across all three nouns: `create`, not `create` in one place and `new` in another. `new` and `go` still work as unpublished spellings, because they are what fingers reach for.
	- `repository` and `branch` are accepted in full. Only the short forms are published, so the help stays scannable.
	- Internally each noun/verb pair collapses to a single token, so the rest of the program still deals with one flat command name. Tokens carry a hyphen, which no typed command may, so they cannot be invoked directly.

- Getting connected is three commands, not one overloaded one: `repo clone` (get an existing repo), `repo create` (make the remote, then publish to it), and `repo connect` (publish to a remote that already exists). The mental models differ, and a single command inferring intent from directory and remote state could silently do the wrong thing in the wrong directory.
	- All three use the same preview-then-confirm flow as every other mutating command.
	- Creating a remote is the one irreversible, outward-facing thing here, so it was given its own verb rather than left as a side effect of connecting. `repo connect` now refuses a target that doesn't exist and names `repo create`; `repo create` refuses one that does and names `repo connect`.
	- `repo connect` refuses remotes that already have history rather than auto-merging: forgiving means not destroying either side. Reconciling unrelated histories stays raw-git territory.
	- `owner/name` targets go through gh (honoring gh's git_protocol setting); plain URLs never touch gh, and can only be connected to, never created.

- Pull requests are subcommands of one noun (`pr`, `pr create`, `pr <n>`, `pr ok <n>`) rather than separate top-level verbs.
	- This puts everything about a PR in one place to look, and matches how `repo` and `br` group.
	- `pr create` defaults its title to the last commit subject. The alternative, requiring a title, was rejected as inconsistent with `pullcom`/`sync`, which generate a message when none is given. The preview shows the resolved title before the prompt, so a bad default is visible rather than surprising.

- `br prune` deletes only what is provably already landed, and never takes a branch name.
	- `br merge` and `pr ok` delete the branch they merged, but nothing cleaned up after a PR merged from the web UI or another machine, after a superseded branch, or after one simply abandoned. Those accumulate, and a noisy `br list` works against the tool's own goal of keeping the repo easy to see at a glance.
	- The test is `merge-base --is-ancestor` against the merge target. That is exact here only because gitsby always lands with a real merge commit: a squash- or rebase-landed branch never looks contained, so it is kept rather than guessed at. Other tools' prune commands are unreliable for exactly that reason; the opinions are what make this one safe.
	- Unmerged branches are listed and left alone, and there is deliberately no `--force`. A bulk delete is the wrong place to offer an override, and the one branch the user cares about is the one an override would eat.
	- The remote copy goes only when origin's own copy of the merge target contains it. A landing that hasn't been pushed yet leaves origin holding the only ref to that work.
	- The current branch and `main`/`master`/`dev` are never candidates.
	- Deletion runs `git branch -D`, gated by our own containment check rather than git's. `git branch -d` asks whether the branch is contained in its *upstream*, or in *HEAD* when it has none - neither of which is the question prune asks. The first produces a warning about HEAD on every branch when you prune from anywhere but the target; the second silently refuses a genuinely-merged local-only branch, so the plan promises a deletion that never happens. Deferring to git here looked conservative and was actually wrong in both directions.
	- The containment check is re-run immediately before each delete rather than trusted from plan time, since the confirmation prompt can sit for a while.
		- The remote half is re-checked against origin itself, not the local copy of it. That copy is only as new as the last fetch, and `--no-fetch` or a long prompt leaves it older. Decided 2026-09-14.
			- Before anything is deleted, prune asks origin where each branch points. One that origin has moved is left alone, and its local branch stays too, so the next prune can look at it again. One origin has already deleted is reported as gone rather than sent.
			- Each delete is leased on the value that passed the containment check, so origin refuses a branch that moves after it was asked. It names the full ref, since origin matches a short name against its tags too.
			- Asking is part of the push, so `--no-fetch` still sends it. If origin does not answer, nothing is deleted there, the same as when the fetch finds origin unreachable. The local branches still go, and another prune could not find those copies, so prune prints the leased delete for each one. Decided 2026-09-15.
			- `br merge` deletes origin's copy of the branch it merged the same way, leased on the tip it merged. A copy with commits the merge doesn't have is left alone.
	- It takes no arguments at all. Choosing branches by name is what raw git is for, and an argument slot would invite exactly the "delete this one specific thing" use that the ancestry gate cannot vouch for.

- The pre-2.0 command names were dropped outright rather than kept as hidden aliases. Version 2 is a deliberate break, the tool is invoked by a different name than it was, and not all of the old commands worked. Carrying dead spellings forward would have been the worst of both.

- A branch is displayed against the branch it is off of, as `base :: branch`.
	- Every line in the state block answered "where am I", and none answered "off what". Running `br hotfix` from `dev` showed `dev` on the current-branch line and `git checkout main` in the plan under it. Both true, and read together they look like a mistake.
	- The base shown is where the branch *lands*. Git records no fork point to read back, and for a branch gitsby made the two are the same by construction, so the land target is the honest answer and the only available one.
	- `main`, `master` and `dev` are shown bare. They are not off anything you would branch from, and `dev :: dev` is noise. `dev` does land on `main`, but only at release, and saying so on every line would imply otherwise.
	- Commands that create a branch state it outright, before the plan. That is pre-flight only: afterward the branch exists and the current-branch line already answers it.
	- The repo's default branch is its own line. It applies to the whole repo, not to the branch you are on, and parenthetical asides on one line do not scale to two facts.

- The pre-flight names gh's account, because it is not necessarily the one git pushes as.
	- gh authenticates to the API with its own token and never reads ssh config. So `pr create`, `pr ok`, and `repo create` act as gh's account, while `git push` in the same repo acts as whatever key the remote's host alias selects. With per-account aliases those are different people.
	- Showing it is not new policy - the identity block already exists to answer "who am I about to be on the remote", and for the gh-backed commands it was answering with the wrong identity.
	- We decided against validating gh's configuration more broadly. Policing another tool's setup is not gitsby's job, gh's config moves, and it would turn working commands into refusals. The failure that prompted this was a *hang*, and the fix for a hang is to never hang.

- A gh write acting as a different account than the ssh key is refused unattended, warned about interactively.
	- Every command that writes through gh compares identities: `pr create`, `pr ok`, `repo create`, and `repo connect` with an `owner/name`. The read-only `pr` forms never pay for the extra round trip.
	- `repo create` and `repo connect` have no origin to read, but they do not need one. gh never uses a host alias - it builds the canonical `git@github.com:owner/name.git` from its own protocol setting - so the identity that repo will live with afterward is knowable before anything is created, and is checked then.
	- There are three outcomes, not two: match, mismatch, and **unknown**. Unknown is common and harmless - no ssh agent (every CI runner), an https remote, a deploy key answering with a repo name instead of a login, gh logged out. It is reported and never blocks. Only a difference both sides confirm counts, or the check would break exactly the automated runs it cannot help.
	- Erroring under `-q` rather than warning follows the rule already set for a missing tty: when nobody is there to read a warning, refuse instead of guessing. Opening a pull request as the wrong account is public and awkward to undo, which is the same reasoning that gave `repo create` its own verb.
	- The warning prints immediately above the confirmation prompt, not with the rest of the state block, so it cannot scroll away behind the plan.
	- `--any-identity` says the difference is intended. It suppresses the error and the warning but not the identity line, so an override still leaves the mismatch visible on screen.
	- The remote these commands leave behind keeps gh's canonical URL. Gitsby will not guess which of your host aliases serves that account: it would have to infer your setup from `~/.ssh/config` and probe each candidate, and a wrong guess silently points a repo at the wrong key. Reporting the identity and leaving the URL alone is the honest version. Anyone who wants an alias can pass a full URL to `repo connect`, which never involves gh at all.

- The ssh identity is probed with the command git itself would run, not a bare `ssh`.
	- `core.sshCommand` is the usual way to keep two accounts apart on one machine: set per repo (often through `includeIf` on the path), it picks the key without any host alias, so every remote stays a plain `git@github.com` URL.
	- A bare probe cannot see that. It answers for ssh's default key while git pushes as somebody else, and the two wrong halves agree often enough to read as a clean bill of health - the check passed most confidently in exactly the setup it exists for.
	- `GIT_SSH_COMMAND` beats `core.sshCommand`, which is git's own precedence. The value is split, never re-shelled: config is not a place to run code, so a quoted path falls back to a plain probe instead of misparsing. Answering "unknown" is safe; answering with the wrong name is not.
	- The same command backs the fetch and the remote probe. Both used to force a bare `ssh` for the connect timeout, and because `GIT_SSH_COMMAND` outranks `core.sshCommand` that silently overrode the repo's key - a private repo only that key can read looked like being offline. A quoted command is the exception: gitsby can't add the timeout to it without re-shelling, so the fetch leaves it to git and goes without one.
	- The key named in the identity line comes from the same place, so the line cannot report the right account beside the wrong key file. Half-right is worse than either half alone: it invites you to trust whichever half happens to be wrong.

- Which GitHub account you act as is decided by the folder you are in.
	- People who have two accounts almost always have a folder per account already. That existing habit is the configuration; asking them to restate it per repo would be asking twice.
	- One account is resolved per run and applied to everything at once - gh, git's credentials, the ssh key, and the commit identity - because a run that pushes as one person and commits as another is the failure this exists to prevent.
	- Resolution order, most specific first: `GITSBY_ACCOUNT`, then `gitsby.ghAccount` in git config, then the config file's folder rules, then the owner of the remote. Finding none of them is the ordinary single-account case and changes nothing.
	- The folder that decides is the one the command is about, which for every command but `repo clone` is the one you are standing in. A clone's repo lands somewhere else, so it resolves against its destination instead. Decided 2026-08-19, after the earlier behavior turned out to read the current directory for it as well.
		- Only the config file's folder rules can answer for a destination. `gitsby.ghAccount` answers for the repo it is set in, and an `includeIf` keyed on gitdir cannot be asked about a repo that does not exist yet - so the surrounding repo's value is skipped rather than allowed to follow the clone out of its own tree.
		- The remote's owner is skipped too. That step reads "this repo is mine, so act as its owner", which holds for a repo you already have and for one you are about to create, and does not hold for a copy you are fetching of someone else's. Among the options - guess from the cloned URL, guess from the surrounding repo, or decline - we decided to decline: with nothing configured for the destination, gh stays on its own account, which is the no-configuration promise.
	- Zero configuration stays the default case, and it is why the remote's owner is consulted at all: that fact is already knowable, so a single-account setup never notices the feature exists.
	- Everything degrades to silence. Unset keys, a missing or unreadable or empty token file, no config file, no gh at all: each falls back to gh's own account rather than failing. A checkout that was never set up this way still has to work, and a pipeline must not break on a box that has not been prepared.
	- Only when the account can be named *and* its token is held. An org or a fork we have no account for is ordinary, and is left alone rather than refused: `owner != your login` is the normal case for contributing to anyone else's repo, so asserting on it would fire constantly and wrongly.
	- Reads get this as well as writes. A `pr` listing against a private repo the active account cannot see fails the same way a write does.
	- The choice is named in the identity block, not silent. Picking an account is still a change of who you act as, and this is a tool that shows its plan before acting. `--any-identity` turns it off along with the mismatch check.

- Gitsby does have a config file, and it is deliberately not a git config file.
	- The earlier decision was the opposite - `includeIf` on the repo path already selects the ssh key and the commit identity, so a second config system looked like a second thing to keep in step with reality.
	- What changed the answer is that folder rules are the point. `includeIf` can only say "when you are here, read this"; it cannot be listed, checked, or explained back to you, and writing one block per account per machine by hand is the chore the feature exists to remove.
	- So the file owns the mapping and `account apply` generates the `includeIf` blocks from it. There is still one source of truth, and plain `git` outside gitsby follows it.
	- The file is [SHCL](https://github.com/jim-collier/shcl), read and written through its Go module: `key: value`, one block per account.
		- The flat `key = value` layout, hand parsed, was the right call while two script builds had to agree on every line of it. With one implementation, a real format buys blocks, comments that survive an edit, and a writer that cannot drift from the reader.
		- The flat layout is still read as it is. The first `account set` on such a file rewrites it whole in the current layout, comments kept. The frozen 2.x scripts cannot read the result; that is the cost of moving, and they are frozen.
		- A save goes through the module, which writes its canonical shape - tabs, lower-case keys - rather than the bytes that were there. So the keys are documented in lower case: it is the one spelling a file settles on. When a save changes more of the file than the key, the plan says so before the prompt.
		- A file created from nothing gets a header naming the keys and the footer `shcl init` writes, naming the format and where its syntax lives.
	- `gitsby.ghAccount` and `gitsby.ghTokenFile` in git config still work and still win, for a single repo that wants to answer for itself.
	- `gitsby.ghTokenFile` and the per-account `tokenfile` name a token for an account gh has never been logged in as, for a machine set up by copying files rather than by authenticating. gh's own store is consulted first, so a rotated login is never shadowed by a stale token on disk.
	- Paths are compared canonically, never as text. The Bash build sees `/c/x` where the PowerShell build sees `C:\x`, and a rule that matched in one build and not the other would be worse than no rule at all.
	- Paths are *displayed* the way the platform spells them, which on Windows is not the canonical form. Every path on screen goes out with backslashes and an upper-case drive letter there, so a folder rule and the directory it claims read as the same place instead of two. The canonical form stays internal, where the matching happens.
	- A `path` rule is absolute or it is ignored, and an ignored one is listed with the rest. A value starting with `~` counts, since it is expanded before anything is matched. Decided 2026-09-14.
		- A relative rule has nothing to be relative to once it is in a file. gitsby measured one from wherever a command ran. git measures `./` from the folder holding the git config, usually home, and matches any other relative folder as a run of names anywhere. So `path: .`, the natural thing to type in the folder you mean, bound every repo under home in plain git and matched nothing in gitsby.
		- `account set` reads a relative path the way any command-line path is read, from the folder it runs in, and writes the absolute result. The plan shows that value before the edit. The file keeps no record of where a value was typed, so the loader cannot do the same.
		- `~name` is ignored too. gitsby expands only a bare `~`, and git expands another user's home, so the two would disagree.
		- `tokenfile` and `sshkey` are held to the same test, and `account set` writes them absolute the same way. A relative token file was read from the folder a command ran in, and ssh read a relative key from each repo's own folder, so a file inside a cloned repo could pick either. A relative `gitsby.ghTokenFile` in git config reads no token. Decided 2026-09-15.
	- A folder rule is plain text, and `account apply` escapes `*`, `?`, `[` and `\` so git reads it that way too. git matches an includeIf as a pattern, so `path: ~/d*` bound `~/dev` in plain git and nothing in gitsby. Listing such a rule as ignored was the other option, and it would have dropped a rule for a real folder like `[archive]` that gitsby matched fine. Decided 2026-09-15.

- A token, not a key, is the way to hold two accounts - and gitsby says so without taking the choice away.
	- The conventional answer is a key per account plus `~/.ssh/config` host aliases, which then have to be baked into every remote URL. It works, and it spreads the account across three places that can disagree.
	- Over https, git can authenticate with the same token gh already stores. Gitsby supplies it through the environment for one command, so nothing is written and a killed run leaves nothing behind.
	- `repo url` converts an existing remote, because that is the only thing standing between an ssh repo and a token. Only the URL changes.
	- Keys remain fully supported, and `IdentitiesOnly` is set with them: without it ssh offers every key the agent holds and the server takes the first that authenticates, which on a two-account machine is a coin toss.
	- Anything the user set themselves - `GIT_SSH_COMMAND`, `core.sshCommand` on the repo, a repo-local `user.email` - outranks a folder rule. A folder rule is a default, not an override.
	- The suggestion to convert is one line, shown only when it would actually help, and `protocol = ssh` retires it. Advice you cannot turn off is noise.

- `raw` is a noun, so the tools it fronts stay out of the command namespace.
	- `gitsby git ...` would have read better and cost more: `git` and `gh` would become reserved words in the command slot forever, and anything else needing verbatim passthrough later would have no home.
	- Everything after the tool name is the tool's, verbatim. Our own options have to come first, because past that point a `-q` is git's flag and not ours.
	- The PowerShell build cannot get those arguments from its own parameters: the binder claims `-m`, `-q` and friends wherever they appear, so `raw git commit -m "msg"` would arrive rearranged. It reads the process command line instead, and refuses rather than guessing when that is unavailable.
	- stdout belongs to the tool alone and the exit code is passed straight back, so a script can pipe it. The one line naming the account goes to stderr, and `-q` silences it.

- Commands that hand a branch to someone else's deletion must park work first.
	- `gh pr merge --delete-branch` removes the branch local and remote. Anything not pushed is outside the pull request, so merging it would drop that work from the branch it lived on.
	- We decided `pr ok` refuses rather than auto-pushing. Pushing and immediately merging would land commits nobody reviewed, which defeats the point of proposing a change for review.
	- `pr create` is the opposite case and does park work automatically: publishing is the whole intent, and nothing is being deleted.

- Offline is split by what a command is for, not handled once for all of them.
	- A command that means something locally runs and reports what it skipped: `pullcom` commits, `br create` and `br hotfix` make the branch, `br switch` switches, `br merge` merges. Each one names `sync` as the way to publish afterward.
	- A command that exists to publish refuses before the plan is shown: `sync`, `pr create`, `pr ok`, `release`. Reporting success having sent nothing is worse than a hard failure, and failing halfway through on raw git output is worse than refusing up front.
	- Offline is the state the pre-command fetch discovers, not a flag you pass. `--no-fetch` declines the incoming round trip - a reasonable thing to want against a reachable remote - so it does not stop a push. The cost is that it also declines the check, so a push while genuinely offline fails with git's own message.
	- `--offline` was accepted as an undocumented third spelling of `--no-fetch`, which made the word promise something the option never did. Among the options - leave it, make that one spelling refuse outgoing traffic too, or drop it - we decided to drop it and refuse it by name, pointing at `--no-fetch`. A flag that stops the pushes would only let someone simulate a state the fetch already discovers on its own, and nothing but the source ever documented the spelling.
	- Two places need more than a skipped push. `br merge` holds back the remote branch delete until the merge is published, because until then origin's copy is its only ref to that work. It keeps the local branch too, since `br prune` looks for what to clear among local branches. The hotfix back-merge normally merges `origin/<default>` (correct after `pr ok`, which lands server-side); offline that ref is the stale one, so it falls back to the local branch.

- The one command that publishes a directory shows what is in it first.
	- `repo create` and `repo connect` from a plain directory list the files before asking. Everything else in the tool previews what it touches; this is the step where a stray `.env` or private key becomes public.
	- The list has to be git's own answer, not a directory walk, or it would name files `git add --all` will skip and miss the exclusions that matter. A throwaway git dir outside the work tree asks git the real question and writes nothing into the user's directory - which is the point, since answering "n" must leave it untouched.

- The Bash and PowerShell scripts are frozen. The Go build in `src-go/` is the implementation that moves.
	- Both scripts stay in the tree, read-only, as the behavioral reference the port is measured against. Only a production hotfix reopens them.
	- Among the options considered, we decided that keeping three implementations in step triples the cost of every change and leaves the newest one nothing to be checked against - a reference that moves is not a reference. Pinned at 2.1.0 behavior, the scripts give the port something byte-for-byte to compare against.
	- The Go build keeps the whole 2.1.0 command surface. Where a command is renamed the old name stays as an unpublished spelling, so nothing that works today stops working. It may add a command or two of its own.
	- Byte-identical output stays the test for everything that has not deliberately changed. A rename moves help and error text on purpose, and those cases are carved out explicitly rather than left to read as regressions.

- `update` became `pullcom`, and `br land` became `br merge`. The old spellings keep working, permanently.
	- `update` said nothing about direction, and read like it updated gitsby itself. `pullcom` names both halves in the order they run - the ordering decision above, made visible in the name.
	- `sync` kept its name. It was never unclear on its own; the pair was. Two words that read as synonyms, with no hint which one publishes, and renaming one end settles it.
	- `merge` is the word people reach for before they learn `land`. `land` stays as a spelling, and stays the vocabulary the rest of the tool uses for the act itself.
	- `pullcom` also answers to `update`, `pull`, `pullc`, `pullco`, `pullcomm` and `pullcommit`. This is the only prefix ladder in the tool, and it earns the inconsistency: the command you type all day, with a tail nobody recalls exactly. Nothing else is prefix-tolerant, and the fix for that is not to spread it.
	- `finish` was considered as a second name for `br merge` and rejected. It overclaims - merging to `dev` still owes a release - and under a permanent-alias promise every spelling is forever.
	- Go build only. The scripts keep the names they shipped with and stay the reference for everything the rename does not touch.

- `whoami` shows the identity block on its own. It also answers to `who` and to `identity`, the name it was built under.
	- `status` already answers "who does this act as", but buried under branch and working-tree state you did not ask about. `account list` answers a different question - what is configured, everywhere, rather than what applies here.
	- `whoami` over `identity`: the command is a question, and `identity` is a noun. Every shell already has a `whoami` meaning exactly this, so the name needs no explaining. `identity` is still the word for the block it prints, which is why the block keeps it.
	- The same lines `status` prints, from the same code, so the two cannot drift apart. That includes the rule that the Account line appears only for an account asked for or configured, never one merely inferred from the remote's owner.
	- It answers outside a repository too. Which account a folder belongs to is worth knowing before there is anything in it, which is exactly when you are about to clone or create.

- The CI/CD stack follows the implementation into Go, rather than becoming cross-platform PowerShell.
	- Among the options considered, PowerShell was rejected for the stack. A single pwsh engine would have retired the hand-synced Windows copy, but only the interpreter is portable - the stack still shells out to git, gh, shellcheck, markdownlint and the rest, so the glue changes syntax without changing what it depends on. It also adds an interpreter that has to be installed, where Bash is already present everywhere the project builds and Go needs nothing at all.
	- The test suite was the specific reason. It fakes `gh`, `git` and `uname` by writing shebang scripts onto PATH, which a process launched from .NET cannot execute on Windows - so a PowerShell port would have traded one platform trap for a new one.
	- What stays as it is: the demo gif generator, already portable and pinned byte for byte to a font stack and an optimizer, and the lint stage, genuinely better expressed as a shell pipeline than as compiled code.
	- Done as of 2026-08-18. `cicd-win.ps1` is deleted, the engine runs seven stages, and the Go toolchain is required rather than probed. The remaining Bash is the pipeline's own, not the product's.

- Pushes are gated by a pre-push hook that runs `cicd/cicd.bash --gate` on each commit pushed to a branch.
	- Among the options considered, gating the working tree was rejected, though it is the usual hook default. Uncommitted edits are routine here, and a push names commits, not a tree. Each pushed commit is checked out in a detached worktree at `.git/gitsby-gate` and checked there. That also gets a branch pushed from elsewhere right.
	- The hook is a file in the repo's hooks directory, written only by `--install-hook`. `core.hooksPath` was rejected: it replaces the whole hooks directory, which switches off any hooks already there, and it cannot be committed anyway. The install refuses to replace a hook it did not write, and refuses while `core.hooksPath` is set.
	- Only branches are gated. A delete has nothing to check, and a tag points at a commit its branch push already gated. A commit whose `cicd/cicd.bash` has no `--gate`, such as the v2.1.0 tag and hotfixes cut from it, is pushed with a note rather than refused.
	- The gate is stage 1 and the unit tests, as the same two functions the full run calls, so the two cannot drift apart. A lint tool that is not installed warns and is skipped, as it is in the full run. Making it fatal in the gate alone was rejected for that reason.
	- git hands a hook the checkout it pushes from, through `GIT_DIR`, `GIT_WORK_TREE` and `GIT_PREFIX`. The hook drops them before anything else, or its git calls and the unit tests would act on that checkout instead of the gate worktree.
	- Accepted cost: the gate runs the pushed commit's own pipeline and unit tests, as running the pipeline on that commit would. `git push --no-verify` is how to push a branch that should not be run.

- The frozen builds live in `legacy/`, holding the deliverables alone - both scripts and the four installers of that era. No copy of the pipeline went with them.
	- Among the options considered, copying `cicd/` into `legacy/cicd/` was rejected. The v2.1.0 tag is a better hotfix tree than any copy: it holds the scripts, the pipeline that built them and the installers all in their original places, wired to each other and unmodified. A copy would have needed its config edited - no dogfood, no publish, no demo, different lint globs - so the thing reached for during a hotfix would no longer have matched what shipped.
	- Rot argues the same way. In a few years the old suite may not run from either location, and a rotted copy at a tag is inert where a rotted copy in the working tree keeps surfacing in greps, lint globs and reviews.
	- So a hotfix starts at the tag, ships from its own branch with its own tag, and is never merged back to `main` - those paths do not exist there.
	- What keeps the six files in the tree at all is the port, not hotfixes: they are the reference this build is compared against. When that comparison retires, they can go, and the tag still holds them.

- `parity.bash` was kept and repointed rather than dropped. It used to compare the two scripts against each other; it now compares this build against the frozen v2.1.0 one.
	- That is the backwards-compatibility question, and it is the one still worth asking. The behavioral suite asks "is this correct?" of one build at a time, so it passes while two builds quietly disagree about the same input - which is what every port defect that reached users actually was.
	- The PowerShell build is not a third leg. The two scripts were proven identical to each other at v2.1.0, so agreeing with one is agreeing with both, and a third leg would only add an interpreter to find.
	- It also checks that `update` and `br land` still route where they always did, under both spellings. A permanent alias is a promise, and promises get checks.

- The installers stayed - one Bash, one PowerShell - and now install a binary rather than a script.
	- The PowerShell one was reconsidered, since what it installs needs no PowerShell. It was kept because PowerShell is the only shell every Windows machine already has: without it, installing on Windows would need Git Bash or WSL first, and nothing would put the install directory on PATH. It is the only piece of PowerShell that still ships, and PSScriptAnalyzer came back into the lint stage with it.
	- `--arch` became real. It was accepted and ignored while one script ran everywhere; it now picks which published binary to fetch.
	- `--ref` became `--tag`, because what it names is a published release rather than any git ref. Both old spellings still bind, like every other retired name.
	- `--release dev` is gone rather than reinterpreted. It installed the tip of a branch, which a script in the tree allowed and a compiled product does not. Typing it says so and names the two routes that exist. A flag that quietly changed meaning would be worse than one that explains itself.
	- `--release stable` still binds and changes nothing, since it always meant the latest release. The help and the refusal for any other value say so. Refusing it too was the other choice (2026-09-15).
	- The PowerShell installer also takes the Bash one's long options, with the value joined by `=` or apart, so a flag copied from one works in the other.
	- A system install that can't write its folder is refused before the plan, not found out after the download. Elevating was rejected: the `iex` and script block forms have no file to start again as administrator.
	- Every route is a release asset, so every route is verified. The unverified branch of the plan no longer exists, and where the checksum can't be fetched or can't be computed the install stops. `SHA256SUMS` is fetched before the plan is printed, because it is what says whether this platform has a binary at all - and it names the ones that do when this one doesn't.
	- The contributor setup scripts were dropped rather than ported. A Go checkout needs only Go, and the three commands that do it are in the README.

- FreeBSD is a published platform.
	- The installer had to answer for a platform with no asset either way. Adding one costs a line in the target list - the module is pure stdlib with no cgo, so every target cross-builds from one box - which is cheaper than documenting an exception.
	- OpenBSD and NetBSD are still that exception. They fall through to the build-from-source message, which names the platforms the release did publish.

- The version lives in the tag and nowhere else.
	- The scripted builds each carried a `thisVersion` string by hand, and a release rewrote both. They had drifted before, which is why phase 1 compared them.
	- A Go build takes its version from `-ldflags` at build time, so there is nothing in the source that can disagree with the tag. Cutting a release edits two files, neither of them source: the changelog heading, and the Windows resource below.

- Windows binaries carry an icon and version details.
	- A pure Go build links no resource, so Explorer showed the default blank icon and an empty Properties tab. Among the options - `goversioninfo` from a generated spec, or writing the COFF resource by hand to keep the zero-dependency character - we decided on the former: a malformed hand-written resource links cleanly and fails only on the machine that runs it, which is not something a Linux box can disprove.
	- The `.syso` files are committed rather than generated during the build. They are linked into binaries whose checksums we publish, so rebuilding a release from its tag must not depend on a tool being installed - the same reasoning that put `-buildvcs=false` in the build flags.
	- Which means they carry the last released version rather than the working tree's: a file that changed with every commit could not be a committed file. A release stamps them with the version being cut, in the same commit as the changelog heading, and the pipeline checks the committed ones against the newest tag.
	- The `.ico` is a committed asset too, not a build product. Image encoders differ between versions, so regenerating it is a hand step (`gen-winres.bash --icon`) run when the logo changes, and nothing gates on reproducing it byte for byte.

- A diagnostic explains itself in the reader's vocabulary, and offers its fix as a command.
	- The identity block's unapplied-account notes, read on a real Gitea repository, raised more questions than they answered: which token, applied to what, what the quoted string even was, and what a "forge" is. Among these options, it was decided that the block must answer all four without the reader knowing anything about how gitsby resolves accounts.
	- "Forge" is gone from the whole tool: what it prints, its docs, its code and its suites. It is a word for people who already know the answer. The status line is `Git host`, and the notes name the host outright wherever they can.
	- `From:` says what the name *is* and which of several possible sources produced it, rather than repeating the name already on the line above. That was the question the old wording could not answer.
	- Every note names only what is actually on screen. `Kept:` pointed at "the SSH and Author lines" whichever half of the account applied, which sent readers looking for an SSH line that was never printed - a second thing gone wrong, apparently.
	- Advice that can be a command is a command. `Fix:` names `gitsby account set <account> <key> <value>`, which makes the edit itself, rather than a config line to retype. It cannot be mistyped and cannot name a key the parser does not take, which the advice had already done once.

- `account set` writes the accounts file, but the diagnostic never writes it unasked.
	- The obvious next step from "gitsby knows the fix" is "gitsby applies the fix", and it was decided against. What gitsby knows is that the account block never named a host - not that the account belongs to the host this repository happens to be on. Applying its token on that inference is exactly the mistake the host field was added to prevent: one host's credential handed to another.
	- So the fix is offered, not taken. `account set` is an ordinary mutating command with a plan and a confirmation, and `status`/`whoami` stay read-only and script-safe.
	- It refuses a key the loader does not read, and a value the loader would drop. A line written past either check lands in the file and is ignored on every load, so the file says one thing and every command does another - the worst of the three possible outcomes.
	- Everything it does not change comes back byte for byte, byte-order mark and line endings included. This file is hand-written and hand-commented; a command that reformatted it in passing would cost more than it saved.
	- A key already present more than once is refused rather than guessed at. `path` and `pathcontains` are repeatable by design, and replacing the first of several would look like it worked and change nothing that is read.
	- It never replaces a file it could not read. Reads pass over a discovered file that can't be read, as if it were not there, since nobody asserted it was. `account set` is the one thing that would act on that absence, so it refuses to create a file while anything is at a place gitsby looks, and names it. Decided 2026-09-14.
		- An unreadable file had read as no file, and the create truncated it. With `XDG_CONFIG_HOME` set, the new file went in ahead of the old one instead and hid it from every later command.
		- The create opens exclusively, so a file that turns up while it runs, or a link to a file that isn't there, is refused rather than written over or through.
	- Two runs never save over each other. Each one reads the whole file and saves it whole, so the later save used to drop the earlier one's key. A run takes a `.lock` file beside the accounts file, reads the file again, and refuses if it changed since the plan read it. Decided 2026-09-15.
		- The lock goes beside the file, not on it, since the save renames a new file over the name. An exclusive create is the one lock every platform has.
		- It is held for milliseconds, so a run that finds one waits three seconds and then refuses, naming the lock. One left behind by a run that was stopped is removed by hand.

- The accounts file lives where the platform in hand keeps one, even where it used to be found somewhere else.
	- Gitsby searched `$XDG_CONFIG_HOME`, then `~/.config`, then `%APPDATA%`, on every platform. That is a Linux convention applied everywhere: a Windows user's file landed under a dot-directory in their profile, a macOS user's outside `Application Support`, and both only because nothing had been found first.
	- Among these options, it was decided that each platform is asked in its own terms and in nobody else's: `%APPDATA%` on Windows, `~/Library/Application Support` on macOS, `$XDG_CONFIG_HOME` on Linux and the BSDs.
	- A platform's variable is read on that platform alone. `XDG_CONFIG_HOME` is set by a desktop session rather than by the person running gitsby, so reading it under Windows let an MSYS shell's leftovers decide where a Windows run looked for credentials; `APPDATA` read under Linux did the same for anything that leaves it set, Wine and Samba included.
	- `~/.config` is itself a Linux spelling by the same measure, so Windows and macOS each have exactly one location and reach for it only where the native one cannot be worked out at all. It was considered and rejected that macOS keep it as a second place to look on the grounds that macOS is a Unix - the argument proves too much, since it would equally reinstate `XDG_CONFIG_HOME` there.
	- That costs a Windows or Mac user upgrading from a version that did search `~/.config` - the file stops being found, and "no accounts file" is a valid state rather than an error, so nothing says so. It was decided the platform's own convention is worth that, and the changelog carries the one-line move.
	- One ordered list answers both questions - where a run looks and where a new file is created - so the file `account set` writes is always the file the next command finds.

- The config file takes any spelling of a path that names the same place, on every platform. `~`, `${HOME}` and `%USERPROFILE%` mean the same thing wherever gitsby runs, and a rule may be written with either slash. One file can then be synced between a Windows box and a Linux one without rules that only half apply.
	- The variables are a closed set, expanded by gitsby itself. A config value ends up in a git credential helper, which a shell runs, so none of this is handed to a shell to expand.
	- A variable this machine does not set makes the rule ignored and listed, never an empty expansion. `path = ${NOPE}/dev` would otherwise become `/dev` and claim every repo on the disk.
	- A drive letter is not mapped across platforms. `C:\Users\pat\dev` read on Linux would name `/Users/pat/dev`, which exists often enough on macOS to match the wrong tree in silence. A rule absolute only on another platform stays ignored and listed, as decided 2026-09-14.
	- `account apply` still writes plain absolute paths into git's `includeIf` rules, since git knows none of these spellings. The synced file stays portable and the generated git rules stay per machine.

## Branching model

Gitsby's own repo runs the model gitsby enforces, so the tool is its own first user.

### How the common models compare

| Model | Long-lived branches | Feature branches | Release | Path to the published branch between releases
| :-- | :-- | :-- | :-- | :--
| GitFlow | `master` + `develop` | off `develop`, back to `develop` | `release/*` off `develop`, merged to `master`, tagged | `hotfix/*` off `master`, merged to `master` and `develop`
| GitHub Flow | `main` | off `main`, back via pull request | tag on `main` | not needed - `main` is always current
| Trunk-based | `main` | very short-lived, sometimes direct commits | `release-X.Y` cut from `main` | cherry-pick onto the release branch
| GitLab Flow | `main` + environment or release branches | off `main` | promote downstream through one-way merges | fix on `main`, cherry-pick downstream
| Gitsby | `dev` + `main` | off `dev`, back to `dev` | `dev` merged to `main`, tagged | `hotfix/*` off `main`, merged to `main` and `dev`

### Which model this is

Gitsby follows GitFlow, with the stabilization branches left out.

- Two long-lived branches. Feature work lands on `dev`. `main` advances only through a release or a hotfix, so it always describes published state.

- No `release/*` branches. Those hold a version steady while it stabilizes and `develop` keeps moving, which matters when several versions are supported at once. Gitsby supports one. Cutting the release straight from `dev` costs nothing here and removes a branch type.

- `hotfix/*` branches come off `main`. `main` is what the world sees: GitHub renders the README from it, and the install one-liners are served from it. A correction to published material should not have to wait for a release, and should not have to cause one.

- Feature branches are short-lived and land with a real merge commit. That is also what makes `br prune`'s ancestry test exact.

### Why not GitHub Flow

- GitHub Flow keeps one long-lived branch, so what is on `main` is both the published state and the in-progress state. For software distributed by version those are different things: the README should describe the release people can install, while unreleased work has to live somewhere.

- Among the options considered, we decided the second branch earns its place. `dev` is where unreleased work accumulates, and `main` stays a truthful description of the current release.

### The GitFlow author's caveat

- Vincent Driessen added a note to the original 2010 post recommending simpler models, GitHub Flow among them, for teams doing continuous delivery of a single always-current version.

- That caveat is aimed at applications deployed from trunk. Gitsby is versioned released software with downloadable artifacts and an installer that resolves the latest release, which is the case GitFlow was written for.

- What does not apply is supporting several versions simultaneously. That is the part of GitFlow the stabilization branches serve, and the reason they are left out.

### Hotfix branches

- The `hotfix/` prefix marks a branch that targets `main` rather than `dev`. The prefix lives in the ref name, so it survives a clone and shows up in a branch listing. It is also the name the model already uses, so it reads correctly to anyone who knows GitFlow.

- Landing one merges to `main`, then merges `main` back into `dev`. The back-merge is not optional. Without it the next release either conflicts on the same file or quietly reinstates the superseded text.

- A hotfix that changes only documentation needs no version bump, because nothing released changed. Documentation is not versioned with the binary - the README describes the release, and it is served from `main`, not from the tag.

- A hotfix that changes anything else leaves `main` carrying changes that no tag contains, so the latest release may stop matching it. That may warrant a patch release, and landing says so in a note rather than leaving it to be noticed later.
	- What counts as documentation is a guess from the file names: Markdown and text files, anything under a top-level `docs/` or `doc/`, and license files. A wrong guess costs one note too many or too few, never a refusal.
	- A repo that has never tagged a release gets no note. It has no release to fall out of step with.
	- When the comparison can't run, the note says it couldn't tell. Saying nothing would read as nothing changed.
	- Watching one named folder was rejected. The folder was this project's own `src-go/`, so in any other repo a code hotfix said nothing. Naming the folder in config was rejected too, since nothing else here needs configuring.

### Enforcement

- A GitHub ruleset covers `refs/heads/main` and `refs/heads/dev`: pull request required, deletion blocked, non-fast-forward blocked. A second ruleset blocks deletion of `v*` tags.

- Repository admins bypass the pull-request rule, which is what lets `release` push the release merge and the tag directly.

- Nothing in the model asks for that bypass to be widened. A hotfix reaches `main` through a pull request like every other change.

### Repos that have no dev branch

- Gitsby adapts to the repo it runs in. With no `dev`, the merge target falls back to the default branch, so feature branches come off `main` and land back on `main`.

- That is GitHub Flow, and it is the better default for a project with no release cadence. The model above is what a repo opts into by creating a `dev` branch.

See also the release policy under Architecture, which covers how releases are published once `main` has advanced.

## Architecture

### Software stack

- Go for the live build: one binary per platform, nothing to install alongside it.

- The frozen scripts need Bash 4.4+ (for *nix or WSL), and/or PowerShell 7+ (cross-platform).

- Nothing else at run time except `git`, plus `gh` for the commands that need it: every `pr` form, `repo create`, and `repo connect` when given an `owner/name` rather than a URL.

- No state of its own. Everything gitsby knows about a repo, it asks `git` for, so there is nothing to get out of sync and nothing to migrate.

	- The one file it does read is the accounts config, and apart from `account set` it is read-only from gitsby's side: it maps folders to accounts and nothing else. Every value it yields is applied through the environment for the length of one command. See "Gitsby does have a config file" above for why that exception was made.

### UI

The rules these entries lead to are collected in [style-guide_ui-ux.md](style-guide_ui-ux.md). This section keeps the reasons.

- Terminal text, one screen at a time. Output opens and closes with a blank line, and sections are separated by blank lines rather than rules.

- Lists of files are one per line, truncated to the terminal width and capped, so a large working tree cannot scroll the prompt out of view.

- Before anything touches a remote, the display names who you would be acting as: the account the SSH key authenticates as, the connection behind it once host aliases are resolved, and the author that would be stamped on commits. Having more than one account configured is common, and pushing as the wrong one is easy and awkward to undo.

- The account is resolved by asking the host, not inferred from the key filename or the connection - a guess would get believed. When it cannot be resolved the display says so.

- Where the display cannot just state a fact - an account that resolved but did not take effect - it drops into a labeled block under the line rather than growing the line. It was decided that a diagnostic has four separate jobs (what happened, why, what did still take effect, what to type and where), and that a single trailing clause carrying all four is one nobody reads. Each gets its own `Why:` / `Kept:` / `Fix:` / `File:` label, indented under the line it belongs to.

	- Wrapped at a fixed width, not the terminal's. An explanation written to fit reads the same on screen, in a transcript and in a bug report, and a width that moves is one nothing can be written against.

	- Any config key an error or a fix names is spelled the way the file actually takes it, in full. Advice naming a key the parser then rejects is worse than no advice.

	- The path of the file to edit goes on its own labeled line. It is the one thing here that can be arbitrarily long, and folding it into a sentence is what wrecks the wrapping. Displayed paths fold a leading home directory back to `~`, so they read as somebody would type them.

	- Where a value came from is named the same way, on its own line, and in terms that can be gone and looked at - the variable, the Git config key, or the account block and its file. "config" alone is ambiguous wherever a program reads more than one.

- A path is printed as it is, never re-spelled to save room. One gitsby worked out itself - the accounts file it found, the directory it is standing in - prints in full, and one that came from the config file prints the way the file writes it. Folding a leading home back to `~` was dropped on 2026-09-16: it shortened one line while the folder rules under it printed in full, and a screen that spells the same prefix two ways costs more than the width it saved. That reverses the display half of the Windows fix which had taught that fold to match either slash.

### Testing

- A regression suite, a fuzz suite and a comparison suite, all against throwaway repos built under a temp directory. None touches the network or a real repo. Alongside them, unit tests inside the module cover the parsing, the folder matching and the string handling, which need no repo at all and answer in milliseconds.

- The fuzz suite asserts three things: no internal crash, no shell or command injection, and that inputs which must be refused exit nonzero and leave the repo unchanged.

- The `gh` paths are covered by a stub on `PATH`, so the GitHub-facing branches are exercised without a network or an account.

- The suites run on Windows as well as Linux, under Git Bash. Path spelling is the recurring trap there, and a handful of checks are gated on the platform for that reason rather than skipped.
	- Stubs are shebang scripts, which some Windows tooling locates on `PATH` but cannot start - silently, so a check passes or fails for the wrong reason. The regression suite gives each stub a `.cmd` sibling that hands the body back to bash.
	- The fuzz suite deliberately does not, and skips the affected checks with a printed reason. A `.cmd` goes through `cmd.exe`, which re-parses an unquoted `&` or `>` in an argument - so a vector this suite hands gitsby would partly run for real, and be reported as an injection that gitsby never had. Its glob vectors break the same way. A named skip is worth more than a green that means nothing.
	- Checks that reach a confirmation need it to refuse rather than wait, which `setsid` does where it exists. The Bash installer falls back to `/dev/tty`, so its checks additionally require that open to fail.
	- Every check that measures the *fix* for a defect is run against the build that preceded it before it is kept. A check that passes both ways is a regression guard, and is labeled as one rather than counted as coverage.

### Demo

- The demo in the README is drawn, not screen-recorded, and the commands in it really run. They act on a throwaway repo built offline for each render, so the output cannot drift from what the tool actually prints.

- Commit dates in that repo are pinned, and the build the demo runs is stamped with the newest release rather than with the commit it was built from. An unchanged demo therefore renders byte for byte identical from one commit to the next, which is what lets the pipeline replace the committed file only when the demo really changed. The version banner in it names the last release, not the build in progress.

- Among the options considered, keeping the version banner out of the demo was rejected. gitsby prints it above every command's output, so hiding it would take either a switch that only the demo uses or a filter on output this section says really runs.

- The demo is described twice on purpose. `script.txt` is the readable version - scenes, captions, typed lines, hold times - and is the one to edit; the scenario file beside it is the machine version. We decided the readable one is the source of truth, because the parameters that shape a demo are aesthetic judgments, and they are far easier to argue about in prose than in a table of numbers.

- Nothing parses `script.txt`. Keeping the two in step is a habit, not a mechanism - a parser would have to be maintained, and the file's value is that a person can change it without learning a format.

- The demo must not be handed the answer it is demonstrating. Its throwaway world deliberately withholds the environment variables that would supply an identity, so the commit author on screen is the one the folder rules chose and not one exported ahead of them. A demo that cannot fail to look right is showing nothing.

- Where a feature is about context - which folder, which account - the demo has to show that context. That is why the prompt carries the working directory: a scene proving the folder decides who you act as, above a prompt that never names a folder, asks to be taken on trust.

### Release policy

GitHub's `releases/latest` returns the newest release not flagged as a pre-release, and both installers resolve through that redirect. Among the options - flag candidates as pre-releases and teach the installers a `--pre` switch, or publish everything as a full release - we decided on the latter. The semver suffix in the tag already tells a reader that `v2.0.0-rc1` is a candidate, and it keeps the documented one-liner installs working with no extra arguments. `--tag`/`-Tag` covers anyone who wants a specific release.

The installers read the release list rather than that redirect. They take the highest full release, and the newest pre-release only when there is no full one, so a repo whose only publication is a pre-release still installs.

### Automating a release

`cicd/release.bash` does everything around `gitsby release`, which stays the git half: merge `dev` into `main`, tag, push, fast-forward `dev`. The script is a maintainer's pipeline task and wants `gh`, the checksum generator and the working tree - none of which the shipped tool should grow a dependency on.

Three phases, so a failure never leaves a half-cut release:

1. **Prepare and verify**, changing nothing outside the working tree. Resolve the version (argument, else the bump `release` would choose), refuse if the tag exists or the changelog has no `vNEXT` section, run the full pipeline, and cross-build every release target as a compile gate. Nothing here needs undoing, so a target that stopped compiling costs nothing to discover.
2. **Land.** Retitle the changelog's `vNEXT` heading, open a PR for it, merge it, then `gitsby release`. The only phase that pushes. The bump goes through a branch and a PR like everything else: committing it straight to the merge target would be the one place this project does to itself what the tool refuses to do for you.
3. **Publish and prove.** Rebuild the per-platform binaries from the tagged commit, create the GitHub release with that changelog section as the body, upload the binaries and their `SHA256SUMS`, then verify - download this platform's published binary, check it, run it, and confirm it reports the released version.

Decisions inside that shape:

- **The assets are built twice.** Phase 1 compiles every target to prove none has stopped building, where the cost of a failure is nothing. Phase 3 builds them again once the tag exists, and those are the bytes that get uploaded - a build number taken from the commit can only be the tag's if the tag is already there. The second build is the price of "check out the tag, build, and get the published checksums back".

- **The release notes name the build number**, read out of the freshly built binary rather than computed a second time in the release script, so the notes and the download cannot disagree about it.

- **The version lives in the tag and nowhere else.** The build injects it with `-ldflags`, so there is no source string to bump and nothing that can disagree with the tag. That replaced an earlier design in which two builds each carried their own version and were compared to each other before pushing - a guard that only existed because the duplication did.

- **The proof is the contract, not the installer.** Download, checksum, run. That is what an installer does at the end of its plan, and it is also what someone who skipped the installer does by hand, so the narrower check covers both. The installers' own behavior is covered by the suite, which reaches everything up to the network. The earlier version of this ran both installer one-liners side by side, which is what caught the PowerShell checksum bug that had silently skipped verification since the day it was added.

- **History footers are warned about, not gated.** The suites' own footers are checked for an entry newer than the last release tag. It is a warning because a release with a stale footer is untidy, not wrong, and a hard gate on a habit is a gate people learn to work around.

- **Assets are built before the tag is cut.** With version-control stamps switched off at build time, a phase-1 binary and one built from the tagged commit are byte-identical. Phase 2 changes two files: a changelog heading, which no binary contains, and the Windows resource - which phase 1 stamps with the same version before building and puts back afterwards, so both phases link identical bytes. The ordering therefore costs nothing, and the reproducibility it used to cost is what `-buildvcs=false` bought back.
