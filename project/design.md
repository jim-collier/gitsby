<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Design

Design, requirements, and direction. The active bug and feature task list lives in `backlog.md`.

## Assumptions

- Any repo gitsby touches may also be touched by raw `git`, `gh`, or an IDE - before, during, and after. Nothing gitsby does can be allowed to confuse those tools.

- Repo state is never assumed. Every command re-checks what it needs at the moment it needs it, because the last command may have been interrupted, or someone else may have moved the remote.

- The awkward cases (partial staging, multiple remotes, rebases, conflict surgery) belong to raw `git`. Gitsby covers the common path and stays out of the way for the rest.

## Project structure

### Folder structure

- `bin/` - the two implementations, one file each.

- `cicd/` - the local pipeline, its config, and the test and fuzz suites.

- `project/` - this file and the backlog.

- `assets/` - the logo and the demo shown at the top of the README.

- `reference/` - notes kept for lookup, not published as project docs.

- Root - the four installers, the license, and the public docs.

### Logical code structure

Both implementations follow the same shape, in the same order:

1. Parse arguments, and collapse a noun and its verb (including the unpublished spellings) into one command name.

2. Refuse anything unworkable up front: unknown commands, bad branch names, a version that is already tagged, no terminal to confirm on.

3. Fetch, so everything displayed afterward is current.

4. Show the repo state, then the exact commands about to run, then ask.

5. Run them, each one state-checked at the moment it runs.

6. Show the state again.

The two files are ports of each other. A change to one nearly always belongs in the other, and the suites run against both.

### Execution flow

- Every mutating command is preview-then-confirm. `-q`/`-y` skips the prompt; nothing skips the state checks.

- The preview is a static recipe per command, with `*` marking steps that only happen if the repo state calls for them. It has to match what the command actually does, including where the command branches on state.

- No command shells out through `eval`. Arguments are passed as arrays, so a message or branch name is never re-parsed.

- Any command named inside an error message, or in the built-in help, has to be one the parser still accepts. The help is the only documentation most people read, so it drifting is a defect, not a typo.

## Direction decisions

- There is no bare `commit` and no bare `pull`. Both were escape hatches around the workflow the tool exists to enforce.
	- `commit` alone produces exactly the state gitsby was written to prevent: work committed locally that never reaches the remote, diverging quietly until the merge is painful.
	- `pull` alone was the only place gitsby let you take upstream changes without dealing with your own work first, which contradicts what it does everywhere else - `br switch`, `br land`, and `pr create` park it; `br create` off `dev`/`main` carries it onto the new branch.
	- We decided the asymmetry settles it: dropping a command before release costs nothing, and adding one back later breaks nobody. Removing one after release would.
	- Removing `pull` exposed a real bug it had been masking - see the ordering decision below.

- `update` and `sync` pull *before* they commit.
	- Committing first mints a local commit, so a remote that has merely moved ahead is now diverged and a fast-forward-only pull must refuse. That is the everyday case, not an edge one, and it was failing.
	- Pulling first fast-forwards under `--autostash`, so the dirty tree rides over and the commit lands on top. History stays linear and fast-forward-only stays satisfiable, which is the whole reason the tool never merges behind your back.
	- Nothing is risked by pulling first: on a failed pull `--autostash` restores the tree as it found it, rather than stranding work in the stash. (A restore that conflicts is the one case git leaves the entry behind, and it says so.)

- Being offline must never turn a good commit into a failed command, now that `update` is the only way to commit.
	- A remote that can't be reached warns and skips the pull. A remote that *is* reachable but can't fast-forward is a real problem and still fails hard - the distinction is what the pre-command fetch already discovered.
	- `--no-fetch` means offline, so it skips the pull too. Skipping only the fetch and then pulling anyway would have saved nothing.

- The command set is split by how often you type it. Daily verbs stay one word (`update`, `sync`, `status`, `release`); everything else is grouped under a noun (`repo`, `br`, `pr`).
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
	- `pr create` defaults its title to the last commit subject. The alternative, requiring a title, was rejected as inconsistent with `update`/`sync`, which generate a message when none is given. The preview shows the resolved title before the prompt, so a bad default is visible rather than surprising.

- `br prune` deletes only what is provably already landed, and never takes a branch name.
	- `br land` and `pr ok` delete the branch they merged, but nothing cleaned up after a PR merged from the web UI or another machine, after a superseded branch, or after one simply abandoned. Those accumulate, and a noisy `br list` works against the tool's own goal of keeping the repo easy to see at a glance.
	- The test is `merge-base --is-ancestor` against the merge target. That is exact here only because gitsby always lands with a real merge commit: a squash- or rebase-landed branch never looks contained, so it is kept rather than guessed at. Other tools' prune commands are unreliable for exactly that reason; the opinions are what make this one safe.
	- Unmerged branches are listed and left alone, and there is deliberately no `--force`. A bulk delete is the wrong place to offer an override, and the one branch the user cares about is the one an override would eat.
	- The remote copy goes only when origin's own copy of the merge target contains it. A landing that hasn't been pushed yet leaves origin holding the only ref to that work.
	- The current branch and `main`/`master`/`dev` are never candidates.
	- Deletion runs `git branch -D`, gated by our own containment check rather than git's. `git branch -d` asks whether the branch is contained in its *upstream*, or in *HEAD* when it has none - neither of which is the question prune asks. The first produces a warning about HEAD on every branch when you prune from anywhere but the target; the second silently refuses a genuinely-merged local-only branch, so the plan promises a deletion that never happens. Deferring to git here looked conservative and was actually wrong in both directions.
	- The containment check is re-run immediately before each delete rather than trusted from plan time, since the confirmation prompt can sit for a while.
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
	- The same command backs the fetch and the remote probe. Both used to force a bare `ssh` for the connect timeout, and because `GIT_SSH_COMMAND` outranks `core.sshCommand` that silently overrode the repo's key - a private repo only that key can read looked like being offline.
	- The key named in the identity line comes from the same place, so the line cannot report the right account beside the wrong key file. Half-right is worse than either half alone: it invites you to trust whichever half happens to be wrong.

- gh acts as the remote's own account when we already hold it, chosen per run.
	- gh keeps one active account per host. Against a remote owned by somebody else it acts as whoever you last switched to, and `gh auth switch` is global state you have to remember to set and to put back.
	- The owner is read off the remote URL and the token comes from `gh auth token --user`, which reads gh's own store. `GH_TOKEN` outranks the stored credentials for that run only, so nothing is left behind and no global state moves.
	- We decided against a config file mapping paths to accounts. Both facts are already knowable - the remote names the owner, gh knows which accounts it holds - and a mapping would be one more thing to keep in step with reality. It also means the feature is inert until it applies, so a single-account setup never notices it.
	- Only when the owner can be named *and* their token is held. An org or a fork we have no account for is ordinary, and is left alone rather than refused: `owner != your login` is the normal case for contributing to anyone else's repo, so asserting on it would fire constantly and wrongly.
	- Reads get this as well as writes. A `pr` listing against a private repo the active account cannot see fails the same way a write does.
	- The switch is named in the identity block, not silent. Picking an account is still a change of who you act as, and this is a tool that shows its plan before acting. `--any-identity` turns it off along with the mismatch check.

- Commands that hand a branch to someone else's deletion must park work first.
	- `gh pr merge --delete-branch` removes the branch local and remote. Anything not pushed is outside the pull request, so merging it would drop that work from the branch it lived on.
	- We decided `pr ok` refuses rather than auto-pushing. Pushing and immediately merging would land commits nobody reviewed, which defeats the point of proposing a change for review.
	- `pr create` is the opposite case and does park work automatically: publishing is the whole intent, and nothing is being deleted.

- Offline is split by what a command is for, not handled once for all of them.
	- A command that means something locally runs and reports what it skipped: `update` commits, `br create` and `br hotfix` make the branch, `br switch` switches, `br land` merges. Each one names `sync` as the way to publish afterward.
	- A command that exists to publish refuses before the plan is shown: `sync`, `pr create`, `pr ok`, `release`. Reporting success having sent nothing is worse than a hard failure, and failing halfway through on raw git output is worse than refusing up front.
	- Offline is the state the pre-command fetch discovers, not a flag you pass. `--no-fetch` declines the incoming round trip - a reasonable thing to want against a reachable remote - so it does not stop a push. The cost is that it also declines the check, so a push while genuinely offline fails with git's own message.
	- Two places need more than a skipped push. `br land` holds back the remote branch delete until the merge is published, because until then origin's copy is its only ref to that work. The hotfix back-merge normally merges `origin/<default>` (correct after `pr ok`, which lands server-side); offline that ref is the stale one, so it falls back to the local branch.

- The one command that publishes a directory shows what is in it first.
	- `repo create` and `repo connect` from a plain directory list the files before asking. Everything else in the tool previews what it touches; this is the step where a stray `.env` or private key becomes public.
	- The list has to be git's own answer, not a directory walk, or it would name files `git add --all` will skip and miss the exclusions that matter. A throwaway git dir outside the work tree asks git the real question and writes nothing into the user's directory - which is the point, since answering "n" must leave it untouched.

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

- A hotfix that touches nothing under `bin/` needs no version bump, because nothing shipped changed. Documentation is not versioned with the binary - the README describes the release, and it is served from `main`, not from the tag.

- A hotfix that does touch `bin/` leaves `main` carrying code that no tag contains, so the assets on the latest release stop matching it. That warrants a patch release, and landing says so rather than leaving it to be noticed later.

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

- Bash 4.4+ (for *nix or WSL), and/or PowerShell 7+ (cross-platform). Nothing else at run time except `git`, plus `gh` for the commands that need it: every `pr` form, `repo create`, and `repo connect` when given an `owner/name` rather than a URL.

- No configuration file, and no state of its own. Everything gitsby knows, it asks `git` for. That is deliberate: there is nothing to get out of sync, and nothing to migrate.

### UI

- Terminal text, one screen at a time. Output opens and closes with a blank line, and sections are separated by blank lines rather than rules.

- Lists of files are one per line, truncated to the terminal width and capped, so a large working tree cannot scroll the prompt out of view.

- Before anything touches a remote, the display names who you would be acting as: the account the SSH key authenticates as, the connection behind it once host aliases are resolved, and the author that would be stamped on commits. Having more than one account configured is common, and pushing as the wrong one is easy and awkward to undo.

- The account is resolved by asking the host, not inferred from the key filename or the connection. A name that is merely likely is worse than none here, because it gets believed. When it cannot be resolved the display says so.

### Testing

- A regression suite and a fuzz suite, both run once per implementation, both against throwaway repos built under a temp directory. Neither touches the network or a real repo.

- The fuzz suite asserts three things: no internal crash, no shell or command injection, and that inputs which must be refused exit nonzero and leave the repo unchanged.

- The `gh` paths are covered by a stub on `PATH`, so the GitHub-facing branches are exercised without a network or an account.

### Release policy

GitHub's `releases/latest` returns the newest release not flagged as a pre-release, and both installers resolve through that redirect. Among the options - flag candidates as pre-releases and teach the installers a `--pre` switch, or publish everything as a full release - we decided on the latter. The semver suffix in the tag already tells a reader that `v2.0.0-rc1` is a candidate, and it keeps the documented one-liner installs working with no extra arguments. `--ref`/`-Ref` covers anyone who wants a specific tag or branch.
