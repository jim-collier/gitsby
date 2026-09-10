<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Gitsby backlog

This is a product backlog for the run-up to v2.0.0. After that release, bugs, features, and enhancements move to GitHub Issues.

## Table of contents

<!-- TOC -->

- [Table of contents](#table-of-contents)
- [Conventions](#conventions)
- [Backlog](#backlog)
	- [Bugs](#bugs)
	- [Features and enhancements](#features-and-enhancements)
	- [Done](#done)
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
	- [Future and/or deferred](#future-andor-deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest.

The sections are Bugs, Features and enhancements, Done, Future and/or deferred, and Canceled. No others. "Done" splits into "Done - Bugs" and "Done - Features and enhancements", and nothing else.

A round of work stays together as one bullet with its items nested under it, rather than becoming a heading. Code review rounds work the same way, one bullet per round under "Done - Bugs" - a round finds mostly defects, and splitting one across two sections loses the thread.

Every item carries an `Opened:` and, once finished, a `Closed:` date, as `YYYYmmDD-HHMMSS`. `Opened: n/a` means it was raised and settled in the same sitting. Older dates were recovered from git history and working notes, so treat them as close rather than exact.

To make using these icons easier, add them to a clipboard or key macro manager. (These are temporary anyway until we switch over to nano-git-db for the minor stuff, and GitHub Issues for the bigger stuff.)

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

## Backlog

### Bugs

- 🛠️ Code review 20260909 - a pass against the standing directives, aimed at the work since the last round. Twenty defects, twelve enhancements.
	- Opened: 20260909-184419

	- 🔘 Code Review 20260909 item 1: a folder rule typed as `.` binds every repo under the home directory to that account.
		- Reproduced: `account set work path .` is accepted and stored as typed. `account list` shows the folder with no warning, because `.` always exists relative to wherever you are standing. gitsby itself then ignores the rule and reports no account for that very folder.
		- Cause: `account apply` turns it into an includeIf rule spelled `./`, and git resolves a leading `./` against the folder holding the config file, which is the home directory. Every repo under home then commits as that account and offers its login to the credential helper.
		- Note: this is the wrong-account commit the whole feature exists to stop, and nothing on screen says it happened. A bare `.` is the natural thing to type from the folder you mean to bind.
		- Probable fix: refuse a `path` that is not absolute, list one as ignored when read, and test the folder's existence against the resolved value rather than against the current directory.

	- 🔘 Code Review 20260909 item 2: `br prune --no-fetch` deletes a branch on origin that origin has moved past.
		- Reproduced: with a branch merged locally and one further commit pushed to origin from a second clone, prune deleted it on origin and the pushed commit became unreachable.
		- Cause: the remote half of the plan reads the local mirror of origin, and the delete-time re-check surveys local branches only, so origin is never asked again. `--no-fetch` leaves the mirror as stale as it was.
		- Note: the plan line asserts each branch was re-checked at delete time. With the fetch left on, the same case is handled correctly, so the flag is the trigger, and its help text gives no hint that it makes this command unsafe.
		- Probable fix: ask origin about each remote candidate before the delete push, or send the delete with a lease so git refuses on stale information.

	- 🔘 Code Review 20260909 item 3: a config file that exists but cannot be read is replaced instead of refused.
		- Reproduced: with the accounts file mode 0200, `account set` printed a plan saying "create", truncated the file and wrote a fresh one. The login and token path that were in it are gone.
		- Cause: a candidate that fails the readable test is skipped, so an empty answer means both "no file anywhere" and "a file that could not be read".
		- Note: mode 0000 fails cleanly, so the window is a file that is writable and not readable.
		- Probable fix: keep the two cases apart and refuse the second by name. Open the create so it cannot truncate.

	- ✅ Code Review 20260909 item 4: the pipeline cannot finish, because the committed Windows resources no longer match their generator.
		- Reproduced: the resource check fails for both architectures, and stage 1 stops the run.
		- Cause: the copyright change edited the string the generator writes, and the two resource files were not regenerated.
		- Note: a release still passes its first phase, which tolerates a stale resource by design, so only ordinary runs are stopped.
		- Note: regenerating publishes whichever marker is in the generator into the Windows file properties, where a user reads it. See enhancement 1, which has to be settled first.
		- Fixed: the generator writes the plain copyright again, which is what both resource files already held. The check passes, and nothing needed regenerating.

	- 🔘 Code Review 20260909 item 5: a key indented one level too deep is dropped, and the line listing what was ignored does not mention it.
		- Reproduced: an `sshkey` written one tab further in than the keys around it does not apply, and `account list` reports only the unknown key beside it.
		- Note: over-indent the key that picks the ssh key or the token file and the account applies without it, silently. The listing that always says, says nothing.
		- Probable fix: walk the children of each key as well as the children of each block, and add whatever turns up to the ignored list.

	- 🔘 Code Review 20260909 item 6: a whitespace-only ssh command crashes the program.
		- Cause: an ssh command taken from the environment or from git config is passed through whenever it is not empty and carries no quotes, so a single space survives. Splitting it yields nothing, and the first element is read anyway.
		- Note: it fires while printing the identity block, so every mutating command dies ahead of its plan.
		- Probable fix: split first, and fall back to plain `ssh` when the split comes back empty.

	- 🔘 Code Review 20260909 item 7: `release` invents version 0.1.0 in a repo whose tags carry no leading `v`.
		- Cause: the tag scan matches a `v` followed by a digit, so a tag like `1.0.0` is invisible and the next version starts from nothing. The duplicate-tag guard below it does see those tags, so the two halves of one command disagree about which tags exist.
		- Note: unattended there is no prompt, and the invented tag is pushed.
		- Probable fix: rank all tags with the leading `v` optional, or refuse to invent a version when the newest tag does not parse.

	- 🔘 Code Review 20260909 item 8: three flaws in `account set`.
		- The refusals are decided inside the preview, so the refusal prints as the plan and it still asks you to confirm. Answering yes fails with the same sentence. Every other command settles its refusals before the plan.
		- A save rewrites the file into the canonical layout, which is the settled decision, but the plan calls it an edit of one line. Space indentation, mixed-case keys, line endings and duplicate blocks are all reshaped with no word.
		- `protocol` takes any value at all. The two it honors are documented in the header of the file it writes, and anything else is quietly ignored later.
		- Probable fix: settle the refusals ahead of the preview, add a reformat line to the plan when the file is not already canonical, and validate `protocol` the way the other closed-set keys are validated.

	- 🔘 Code Review 20260909 item 9: `repo url` previews a github.com address on every host.
		- Reproduced: against a Gitea remote the plan named a github.com URL, and the command then set the Gitea one.
		- Cause: the preview builds its line with the GitHub-only helper while the command uses the host-aware one. The read-only half was widened and the preview was left behind.
		- Probable fix: build the preview line the way the command does.

	- 🔘 Code Review 20260909 item 10: a conflicted `br merge` leaves the merge in progress and says nothing useful.
		- Reproduced: a conflicting merge onto the protected branch ended on a bare step failure, with the tree in conflict and the merge still open.
		- Note: the back-merge path in the same file handles the same failure the other way. It aborts, says what got through, and names the command to finish by hand.
		- Probable fix: give the forward merge the same treatment.

	- 🔘 Code Review 20260909 item 11: being offline reads as "that repo doesn't exist".
		- Cause: the remote probe answers missing for any failure. A comment a few lines above it says unknown must not collapse into missing, and the GitHub-side probe honors that by reading the error text.
		- Note: offline, `repo connect` says a repo that exists does not, and points at the command that would create a second one.
		- Probable fix: read the error text, keep "could not tell" as its own answer, and give it its own message.

	- 🔘 Code Review 20260909 item 12: install.ps1 fails on Windows PowerShell 5.1 in the default lookup.
		- Cause: the release lookup reads a header through a property that exists on version 7's object and not on 5.1's. Strict mode turns that into an error inside the handler, so the fallback below is never reached.
		- Note: 5.1 is the shell Windows ships and the documented one-liner path. Read rather than reproduced on 5.1 itself, though the two object shapes were checked.
		- Probable fix: read the header by name through the indexer, and let a failure there fall through to the list lookup.

	- 🔘 Code Review 20260909 item 13: five more flaws in install.ps1.
		- A system install promises write access it never checks, does not elevate, and fails after the download with a raw error. The bash one checks, and says up front that it will use sudo.
		- The documented parameters are unreachable: they sit on the inner function, so help shows a syntax line carrying no options at all.
		- The joined `--target=value` form is refused, though the bash one takes it and the documented spelling uses it.
		- The checksum compare works only because the operator is case-insensitive by default. A case-sensitive one would fail every good install.
		- The message for a binary that will not run is unreachable in the common case, because a launch failure is a terminating error and the outer handler prints raw text instead.

	- 🔘 Code Review 20260909 item 14: six flaws in install.bash, or shared by both installers.
		- An uppercase hash in the checksums file makes it report the asset as absent and then name nothing. The PowerShell one accepts the same file.
		- `--release stable` is accepted, while the help and the error text both say the option takes neither value.
		- `--ref` is accepted and missing from `--help`, against the file's own note that help lists every option.
		- Several exit paths skip the blank line framing: the "publishes no binary for this platform" block, the declined prompt, the pre-release notice, and every error the PowerShell one raises.
		- Neither plan says it will overwrite an existing install.
		- Nothing is said when the installed binary will not run. The run simply ends.

	- 🔘 Code Review 20260909 item 15: there is no fast gate and no pre-push hook.
		- The standing directive asks for a quick mode that checks formatting, lints with warnings as errors and runs the unit tests, registered as a pre-push hook, so nothing reaches dev or main unverified outside a full run.
		- Nothing like it exists, and the hooks directory holds only the stock samples.
		- Note: the full pipeline is the only gate today, it takes minutes, and it is currently red.

	- 🔘 Code Review 20260909 item 16: the demo gif is rebuilt and recommitted on nearly every commit.
		- Cause: every command prints the version and build number above its output, and the first scene captures one. The version moves with every commit, so the render always differs and an eleven megabyte file is replaced.
		- Note: three places state the opposite, that an unchanged binary and scenario reproduce the same bytes.
		- The run also lasts about two minutes against a twenty to thirty second budget, and its closing black is two seconds where three was asked for.
		- The quiet flag reaches every other child of the pipeline and not the demo generator.
		- Probable fix: stamp a fixed version for the demo build, or keep the banner out of the demo run.

	- 🔘 Code Review 20260909 item 17: pipeline housekeeping.
		- The two "have I seen this yet" markers live inside the working tree. A clean checkout loses them.
		- The lint report counts a filename as a warning, because one source file has the word error in its name. This is the second time that report has matched something that was never a warning.
		- `run-latest.ps1` is first-party PowerShell that the lint globs do not cover.
		- `git-auto-msg.bash` has no caller. Its header says it is the editor for the publish stage, and nothing sets it as one.
		- Three pipeline files stop their history at 2026-08-19 and have a month of changes since. The release check only inspects two other files.
		- The generator writes copyright 2026 while the program prints 2014-2026.
		- A dev or dogfood build is stamped with the parent commit's version, because the stamp is read before the commit that holds the source.
		- The version banner puts the copyright on the same line, where a separate line was asked for.

	- 🔘 Code Review 20260909 item 18: public documents contradict the code.
		- The recipe for checking a published binary against its checksum leaves out the build stamp, so it can never produce the published bytes. That is the one section whose whole point is that nobody has to take our word for it.
		- Every config file the program creates carries a link to the account documentation on `main`, which still describes the old flat format that the new file is deliberately not in.
		- The code of conduct's enforcement contact is an empty pair of angle brackets. `main` has the address, and so does contributing.md here.
		- design.md says everything is published as a full release, while both installers, the release badge and the changelog all assume pre-releases.
		- design.md heads the config-location block with "the place it used to live is never taken away" and says the opposite five lines down.
		- "Uninstalling is deleting it" is wrong on Windows, where the installer also writes a PATH entry.
		- A diagnostic points at a README section that does not exist, for a file format the README does not document.
		- The pipeline settings file numbers its stages one lower than the run prints, from stage four on.
		- The backlog still opens by calling itself the run-up to v2.0.0, two releases ago.
		- design.md says the word forge is gone from the whole tool. The printed output is clean and guarded, but the word is still in about thirty comments and in design.md itself.
		- The style guide covers three languages and calls them "Both languages" in two places. The private pointer to it still says Bash and PowerShell.
		- Two British spellings in the code of conduct, in lines that match neither upstream nor `main`.
		- contributing.md and the code of conduct both advertise being produced by a generator.
		- trademark.md holds the only hard-wrapped paragraph in a first-party document, and writes its contact address with a circled letter A in place of the at sign.

	- 🔘 Code Review 20260909 item 19: `account list` runs one `gh` per configured account.
		- The token lookup sits inside the listing loop. One account costs one process and twenty cost twenty, and `account set` pays the same bill before its edit, because it prints the listing first.
		- Note: this is the only per-item process spawn left in the program, and the style guide states the rule it breaks.
		- Probable fix: remember the answer per login for the length of the run.

	- 🔘 Code Review 20260909 item 20: the hotfix warning about changing shipped code can never fire in anyone else's repo.
		- The path it watches is this project's own source folder. In any other repo the check matches nothing and stays quiet.
		- Note: read rather than reproduced. The comment above it records that it used to watch a folder that had been renamed away, so this is the second turn of the same trap.
		- Also, the check cannot tell "nothing changed" from "the comparison could not run".

### Features and enhancements

- 🛠️ Code review 20260909 - enhancements from the same pass. Twelve items, none of them urgent.
	- Opened: 20260909-184419

	- ✅ Code Review 20260909 enhancement 1: decide whether the identity marker belongs in the Windows file properties.
		- The copyright change put it into the string Windows shows on the Properties tab of the executable, which is a product-facing string rather than a source header. The standing rules exempt two other projects' Windows version strings and keep the plain form there.
		- Bug item 4 waits on this: regenerating the resource files publishes whichever answer is given.
		- Kept out. The Properties tab shows the plain copyright, and the source headers keep the ID.

	- 🔘 Code Review 20260909 enhancement 2: there is no `account unset`. Setting a key to an empty value prints the syntax block, so the only way back is the hand edit that `account set` exists to avoid.

	- 🔘 Code Review 20260909 enhancement 3: `--about`, `--donate` and `--version` are honored only as the first word, while `--help` works at any position. The help screen lists all four on one line.

	- 🔘 Code Review 20260909 enhancement 4: two of the six README badges are shields the repo grants itself and assert nothing outside the README. The language badge names no version.

	- 🔘 Code Review 20260909 enhancement 5: three things the README leaves out.
		- The build number, which every command prints and which comes from the commit rather than the clock.
		- How to ask for a pre-release, which is what the first Go publication will be.
		- The real check counts. "Several hundred" rounds down from eight hundred and ten, plus the fuzz and comparison suites.

	- 🔘 Code Review 20260909 enhancement 6: record that goreleaser is not being adopted, and why, so the question stops coming back. The hand-rolled build is already byte-identical from one flag set, goreleaser would have to be talked out of its own stamps, and packaging is the only thing it would add.

	- 🔘 Code Review 20260909 enhancement 7: `--quick` still runs the two slowest harnesses in full. Neither takes a flag to shorten itself.

	- 🔘 Code Review 20260909 enhancement 8: tool pinning covers the four Go tools and silently skips the one that is not on the path. Six other tools that shape results are pinned nowhere.

	- 🔘 Code Review 20260909 enhancement 9: the release's final build compiles the working tree rather than a checkout of the tag. The two match in the ordinary case, and the comment above it claims the stronger thing.

	- 🔘 Code Review 20260909 enhancement 10: smaller points in the installers.
		- No writability check for a user-scope install, so it fails after the download the way the system scope does.
		- sudo is promised without checking it exists.
		- The two scripts leave the installed file in different modes, and the PowerShell one takes the umask.
		- The PowerShell plan does not mention creating the destination folder, or clearing its own leftovers.
		- The README does not say how to pass a flag to the bash one-liner, though the script knows the answer in a comment nobody sees.

	- 🔘 Code Review 20260909 enhancement 11: preallocate the slices whose size is already known, about fourteen of them. The style guide could also use a Go performance section, and its package-variable rule needs widening: five variables that Go cannot express as constants currently read as standing violations.

	- 🔘 Code Review 20260909 enhancement 12: `.gitignore` covers the pipeline's own output and nothing a contributor's machine drops.

- ✋ The repo's blurb, homepage and topics still describe the Bash and PowerShell product.
	- Opened: 20260819-142046
	- They name both scripts and give the old command count, and the topics say `bash` rather than `go`.
	- Deferred until the Go build is released on `main`. Until then the description would be ahead of what a visitor can actually download, which is worse than being behind.
	- One command when the time comes: `gh repo edit --description ... --homepage ... --add-topic go --remove-topic bash`.

### Done

#### Done - Bugs

- ✅ A release tag whose patch number is too large to hold overflowed into a negative version.
	- Opened: n/a
	- Closed: 20260822-113804
	- `strconv.Atoi` answers overflow with the clamped maximum, not zero, so the bump wrapped it negative. Found by the new fuzz targets on their first full pipeline pass; crasher committed as a regression seed.
	- Fixed: an unreadable patch number starts the count over at zero, as the comment beside it already claimed.

- ✅ `account set`'s syntax block hung its indent off the `gitsby:` prefix, which is on one line only.
	- Opened: n/a
	- Closed: 20260821-150802
	- Everything below the first line sat at eight spaces, so the whole block read as one flat wall - the placeholders, the example and the sentence introducing it all at the same depth.
	- Fixed: it nests two spaces at a time. The written line is under `Syntax:`, the placeholders under that, `Examples:` alongside them and the commands one deeper.
	- Second example added, for picking an account by a run of folder names rather than an absolute path - the case a person with one employer folder full of repos actually has.
	- That example spells `pathContains` with a plain `my-employer/github`, not a glob: the matcher takes a run of folder names, so a `*` in the example would teach a pattern language that isn't there and a rule that never fires.

- ✅ `account set`'s syntax line named three placeholders and defined none of them.
	- Opened: 20260821-132716
	- Closed: 20260821-133346
	- Real output: `Syntax: gitsby account set <account> <key> <value>   (e.g. gitsby account set work host gitea.com)`.
	- The only person who ever reads it is the one who just typed the command wrong, and it left them to work out what an account is, which keys exist, and what a value looks like.
	- Fixed: a block. It names the line that gets written - `account.<account>.<key> = <value>` - then defines each placeholder, and lists all ten keys off the same constant the unknown-key refusal reads.
	- The example is now two commands on one account name, a folder and a login, since that repetition is what `<account>` means.

- ✅ `account list`'s header raised more questions than it answered.
	- Opened: n/a
	- Closed: 20260821-122605
	- Real output, in a Gitea folder with nothing set up yet: `Here .........: C:\opt\...\gitea.com\work\proj` over `Resolves to ..: (nothing configured - gh's own account)`.
	- "Resolves to" names no actor, so the first thing it prompts is "resolves by whom?". "Here" is a second word for the directory `status` calls `Directory`.
	- And `gh` has no business in that answer on a Gitea host. It is wrong wherever `gh` does not serve, and it answers a question about git's own fallback that nobody asked.
	- Fixed: `Here` is now `Current dir`, `Resolves to` is now `Account` - the label `status` already puts on the same answer - and an unconfigured folder gets `(nothing configured)`, full stop.
	- An account that resolves but names no login no longer asserts `gh` either: it names whichever tool serves that account's own host, and names none where there is none.
	- `status` and `whoami` said `Directory` for that same value, so they moved to `Current dir` too - one label, one constant, shared by all four places that print it.

- ✅ On Windows, `account list` printed the same directory two ways on the one screen.
	- Opened: n/a
	- Closed: 20260821-105738
	- Real output: `Here .........: C:\opt\...\dev\gitea.com\work\proj` above `folder ..: c:/opt/.../dev/github.com/work`.
	- The folder rules are held in the form paths are matched in - lower case, forward slashes - and that form was going straight to the display. Same disk, same tree, two spellings.
	- Fixed: every path printed anywhere is spelled the platform's way, which on Windows means backslashes and an upper-case drive letter. The internal form is untouched, so nothing about matching changed.
	- Covers the config file, `Here`, the folder rules, the machine-free `anywhere` rules, the ssh key, and a token file. No effect off Windows.

- ✅ The Account line explained an account it could not apply in a single run-on clause nobody could act on.
	- Opened: 20260820-160751
	- Closed: 20260820-162154
	- Real example: "(no login named) (from config 'work-gitea') - NOT applied: this remote is on gitea.com, and that account names no host, so it counts as a github.com one. Add 'host = gitea.com' to it." Two parentheticals back to back, then a clause long enough to wrap wherever the terminal ended.
	- Nothing in it could be acted on: which config, added where, what "NOT applied" covered, what "counts as" meant.
	- Worse, it was wrong twice. The line it told you to add is not a line the file accepts - keys are `account.<name>.<field>`, so a bare `host = ...` is reported as one gitsby doesn't understand. And "NOT applied" was false: the ssh key and the commit identity apply outside the credential decision, so it contradicted the SSH and Author lines printed directly underneath.
	- Fixed: the line says who and what happened, and an indented `Why:` / `Kept:` / `Fix:` / `File:` block underneath says why, which half did apply, exactly what to type, and which file to type it in. Wrapped at a fixed 78 columns rather than at the terminal, so it reads the same in a transcript as on screen.
	- "(no login named)" is gone from both the status line and `account list`; an account that names no login is now named by its own name, which is the thing you have to go and edit.
	- Second pass: `(from config 'work')` is gone from the applied line too. It named neither the file nor which config, and there are two of those in play - `gitsby.ghAccount` is a git config key and the account blocks are not. Every account now gets `From:` (the variable, the git config key, or the account block) and `File:` (the accounts file), on their own lines under the answer.
	- Displayed config paths fold a leading home directory back to `~`, so the file reads as somebody would type it rather than filling the line.

- ✅ The account display never learned about `host` and `user`, so a Gitea account was reported as a GitHub one that had nothing set.
	- Opened: 20260820-132706
	- Closed: 20260820-133645
	- Found on the first real Gitea repo: `status` named "(no GitHub account named)" and said the account was on github.com, which nothing in the config had said.
	- Four places read `ghAccount` alone. The status line and `account list` both named only the GitHub field; the "no token" case was keyed on it too, so a correctly declared Gitea account with no token said nothing at all and read as applied.
	- Fixed: all four ask the account's login on the account's own host. An unstated host is now reported as unstated and names the key that fixes it, and `account list` shows the host, marked `(default)` where the file never said.

- ✅ `repo clone` resolves its account from the folder you are standing in, not the one it is cloning into.
	- Opened: 20260819-092526
	- Closed: 20260819-094134
	- Every other command is about the folder you are in. A clone's repo lands somewhere else, so a clone launched from a work repo used the work account whatever tree it was cloning into.
	- Three ways in, all now closed: the folder rules read the current directory, `gitsby.ghAccount` was read off the surrounding repo, and the owner of that repo's origin stood in when nothing else answered.
	- Fixed: the destination folder decides. The surrounding repo's git config is not asked (a destination has no config yet, and an includeIf on gitdir cannot answer for a repo that does not exist), and no owner is guessed - with no rule for the destination, gh stays on its own account.
	- Noticed while making clone accept the `owner/name` shorthand; left alone there because it changes which credentials a clone uses, not just what it accepts.

- ✅ Accounts and arguments, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-181826

	- ✅ `account apply` ordered its rules the opposite way from the way gitsby matches them.
		- Cause: gitsby takes the longest matching folder; git applies includes in file order and the last match wins. The rules were written grouped by account, in declaration order.
		- Note: so a tree nested inside another account's tree got whichever account happened to be declared later, and plain git and gitsby then disagreed about one directory - the single thing `apply` exists to prevent.
		- Fixed: shortest path first, so the longest match is written last and wins in git too. Folder is the tie-break, so the order is deterministic.
		- Verified both ways: with the old build, plain git in the nested folder used the outer account's email while gitsby resolved the inner account. Both now say inner.

	- ✅ Bash accepted `--config` naming a directory: shell error, no accounts, exit 0. PowerShell's matching hole was an unreadable file, passed over silently.
		- Fixed: both now require a readable regular file, and refuse by name. A *discovered* config is still skipped rather than refused - nobody asserted that one was there.
		- Note: PowerShell has no readable bit, so the test is opening the file.

	- ✅ `GITSBY_ACCOUNT` matched an account name case-sensitively in Bash, case-insensitively in PowerShell.
		- Cause: Bash's loader lowercases the whole key on the way in, but the lookup lowercased only the key half and left the account name as typed - so it could miss what it had just stored.
		- Fixed: lowercase both halves, which makes Bash self-consistent and matches PowerShell.

	- ✅ Only `-q`, `-y` and `--config` could precede `raw`, and the error blamed the wrong thing.
		- Note: worse than recorded - the message was "Unknown command 'raw'", which is false. Only the passthrough's own scan runs before `raw`, so an option it didn't take left the main parser looking at a command by that name.
		- Fixed: the scan takes gitsby's whole option vocabulary, spelled and normalized the same way the main parser does it. The ones with nothing to act on in a passthrough are inert. `-h` and `-v` still fall through to the main parser, and a genuinely unknown option is refused by its own name.

	- ✅ PowerShell `raw` could not pass `--`, git's pathspec separator.
		- Cause is not what was recorded, and matters: PowerShell's binder reads a bare `--` as an empty parameter name and fails *before the script runs at all*. Nothing in the passthrough can intercept it. Five param-block shapes were tested; a script with no `param()` block receives `--` fine.
		- Fixed as far as it can be: `` `-- `` survives binding, and is handed to the tool as `--`. Documented in `accounts.md`.
		- Note: dropping the `param()` block would fix this and the joined-option binding together. Not taken - it is a large change to a documented option surface.

	- ✅ `account apply` ended in a raw operating-system error, a different one in each build.
		- Note: not the no-config case, which already reports itself properly. The trigger is the include directory being unusable - something else already at that path.
		- Fixed: check the directory before writing anything, and fail in gitsby's own voice. Nothing partial was ever written, and still isn't.

- ✅ Installers, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-160521

	- ✅ A Windows install finished with the program not on `PATH`.
		- Fixed: the PowerShell installer adds the install directory to the account (or system) PATH, and says so in the plan before you agree. Idempotent, and it leaves the current shell alone.
		- `PATHEXT` deliberately left alone, and the original reasoning for it was wrong. PowerShell already resolves a bare `gitsby` to `gitsby.ps1` on `PATH` without it - verified with `PATHEXT` cut back to `.COM;.EXE;.BAT;.CMD`. It would only affect `cmd.exe`, which still cannot run a `.ps1` even with the entry, because that needs a file association - and the default association opens the script in an editor rather than running it. Adding it buys nothing and risks that.

	- ✅ Both installers installed anyway when `SHA256SUMS` was absent, and said nothing at all on the `--release dev` path.
		- Fixed: the plan states which of the two you are about to get, before the confirmation.
		- Fixed: where the plan promised verification and it can't happen, the install now stops instead of noting it in passing - separately naming the two causes, no published checksum and no sha256 tool here. `--ref TAG` takes it unverified, as an explicit choice.
		- Note: the release-asset fallback to the tagged tree was the same broken promise and stops the same way.
		- Verified against the real v2.0.2 release, both installers: plan promises verification, checksum verifies, correct version installed.

- ✅ Pipeline, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-153506

	- ✅ The pipeline had no remote-sync stage, so the pull at publish time could carry in changes nothing had tested.
		- Cause: the only pull was in the publish stage, which runs last - after lint, tests and fuzz have all passed against the older tree.
		- Fixed: stage 0 in both engines. Fetch, fast-forward when only behind, and stop when diverged. No upstream or an unreachable origin warns and carries on; `--no-sync` (`-NoSync`) skips it. Publish keeps its own pull as the late guard.
		- Note: the fast-forward is `--autostash`, so a dirty tree rides over it. Verified against throwaway repos in all five states, both engines.

- ✅ Documentation, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-152949

	- ✅ `design.md` stated the opposite of itself in two places, each time because a later decision was added without revising the earlier one.
		- Fixed: the Architecture bullet now says no *state* of its own, and names the accounts config as the one read-only exception. The `--no-fetch` bullet no longer calls itself offline, which is what the code and the offline rule below it already said.

	- ✅ The `Status: Passing` badge was a fixed image wired to nothing, so it read the same on a broken branch.
		- Fixed: removed. The pipeline is local, so there is no build to report; the remaining badges all resolve to something real.

	- ✅ README was about four times the length it should be, and the first runnable example was well over half way down.
		- Fixed: 535 lines to 273. Install and a worked example are now the first two sections, above the fold.
		- Fixed: the headline names folder-based accounts, which is the strongest thing in the release and went unmentioned.
		- Fixed: the long material moved to `accounts.md` and `workflows.md` rather than being deleted, so the README reads as a landing page and the depth is one click away.

	- ✅ README wording: a missing verb and a doubled letter in the workflow comparison, and a bullet with no full stop in Compatibility.
		- Fixed: all three, in the moved text.

- ✅ Code review 20260821 - a full pass over the whole tree, docs and installers included. Suite 773 -> 776, fuzz 269/0, parity 27/0, all green; every new check fails against the build or file that preceded its fix.
	- Opened: 20260821-174646
	- Closed: 20260821-182749

	- ✅ Code Review 20260821 item 1: the installers trusted GitHub's list order in the fallback release lookup.
		- The list is ordered by publish date, so a fix backported after a newer release would have resolved as latest and installed a downgrade. Both installers now take the highest version among the candidates; a numeric tie keeps the newer-listed one.
		- The bash one also stopped depending on GitHub pretty-printing the JSON - the scrape was line-anchored, and a packed payload matched nothing and then blamed rate limiting.
		- The new suite check runs the backport case against a stub serving a one-line payload; the previous installer fails it both ways.

	- ✅ Code Review 20260821 item 2: `Get-Help` on install.ps1 showed an auto-generated stub.
		- Comment help was binding to the first function. A blank line under the shebang and two above the function fix the binding; a comment marks them load-bearing.
		- Also gone: the one `+=`-in-a-loop, and the `iex` one-liner's inability to take flags is now documented in the README with the script-block form.

	- ✅ Code Review 20260821 item 3: `br prune`'s delete-time re-check forked git once per branch.
		- Now one `for-each-ref --merged` survey, same as the plan-time one, asked per target ref only while a candidate is still unconfirmed - so one branch costs one call and eight branches cost the same. The first cut cost one extra call at n=1, and the spawn counts caught it before it landed.

	- ✅ Code Review 20260821 item 4: no native Go fuzz targets existed.
		- Five now cover the pure parsers (remote URLs, forge tables, tags, config keys, URL masking); the pipeline hunts briefly past the seed corpus each full pass, capped like the builds.
		- They paid immediately: a "host" carrying whitespace was matched against account rules instead of reading as unparseable, and `account.<name>.` with no key half-parsed instead of landing with the ignored lines. Both fixed; the crashers are committed as regression seeds.

	- ✅ Code Review 20260821 item 5: error chains were stringified at the two places a usage error carries a cause.
		- `usageWrapf` keeps the cause on the chain for `errors.Is`/`As`, message text unchanged. `errorlint` and revive's `early-return` now gate what was until now only convention, and the dozen bare `_` discards each carry a one-line reason.

	- ✅ Code Review 20260821 item 6: three pipeline steps ignored the half-the-cores budget the builds keep.
		- `go test`, `golangci-lint` and vet/staticcheck now run under `BUILD_JOBS`; `go test` also gained `-race`, cheap on a tree with no goroutines and armed for the day one appears.

	- ✅ Code Review 20260821 item 7: `-q` and `-y` behaved identically, against their own help text.
		- The quiet variable was set and never read. Harness quieting now keys on `-q`; `-y` is unattended and full-volume, as documented. release.bash gained `-q` and hands it to the pipeline. Stage 0 also printed "0/6" in an eight-header run; it says 0/7 now.

	- ✅ Code Review 20260821 item 8: nothing existed to run the newest build the way the pipeline dogfoods it.
		- `cicd/utility/run-latest.ps1`: pooled timestamped copies outside PATH, week-long age-out, args forwarded, exit code returned. A rebuild never fights a running copy.
		- `cicd/utility/spawn-report.bash`: the newest recorded spawn counts with deltas, `--check` marker-gated like lint-report's, so the startup look at profiler output has a tool to call.

	- ✅ Code Review 20260821 item 9: docs swept.
		- Backlog: completed items moved out of Future, empty headings gone, older round numbering unified, example names and paths anonymized. README: sponsor badge and a short support section, the `br prune` exactness paragraph, install subsections in the TOC, the script-block install form, stage numbering matched to what the run prints, count fixes. design.md: table of contents, one duplicated sentence deduplicated. style-guide.md: a Go section for the conventions gofmt can't see. Remaining British spellings fixed, code_of_conduct.md matched back to its upstream text.

- ✅ Code review 20260819d - a third adversarial pass, aimed at what a run inherits from the machine it runs on.
	- Opened: 20260819-174102
	- Closed: 20260819-180413

	- Three defects, all in account selection or in what proves it. The first was found by the third: the suite went red on this machine the day it grew a real config of its own, which is what exposed the other two. Four new suite checks (699 -> 703) and two Go tests. Suite 703/0, fuzz 268/0, parity 27/0, spawn counts unchanged.

	- ✅ Code Review 20260819d item 1: the test suite reads the accounts of whoever runs it.
		- Cause: the blocks that test config discovery opt out of the file-scope `GITSBY_CONFIG` pin and fake `HOME` instead. `XDG_CONFIG_HOME` is tried before `HOME` and `APPDATA` after it, and neither was covered.
		- Note: harmless until this machine had a gitsby config of its own, at which point thirty checks failed against it. Not a false alarm to wave through either - it is the block that would catch an account regression.
		- Note: same shape as the symlink rule the round before - one side of a pair normalized and the other left alone.
		- Fixed: every discovery input emptied in one place, so `HOME` stays the candidate under test. Six env strings went through it. The thirty failures clear with no product change.

	- ✅ Code Review 20260819d item 2: an account named through `GITSBY_ACCOUNT` applies nothing unless it names a GitHub login.
		- Cause: the test was whether the account had a `ghAccount` key, not whether the file defined the account at all.
		- Note: an account can be a commit identity and an ssh key and nothing else, and a folder rule has always applied one - so asking for the same account by name got you less than not asking. The key fell back to whichever one ssh picks, which is the wrong-person push the feature exists to stop.
		- Note: it also reported the account's own name as the GitHub login the run acts as, which the push-identity gate would then compare against the real one and refuse on.
		- Fixed: a name the file defines is a configured account either way. Same correction where a repository sets `gitsby.ghAccount` itself - an account naming no login disagrees with nothing, and was being dropped along with its key.

	- ✅ Code Review 20260819d item 3: a byte-order mark eats the config file's first key.
		- Cause: the mark was left on the front of the first line, so the key it belonged to parsed as one nothing understands.
		- Note: the ignored-keys line printed the mark as part of the name, so the one diagnostic meant to explain the loss named a key that looks perfectly valid. Windows editors write a mark by default.
		- Fixed: stripped on the way in. One Go test and two suite checks.

- ✅ Code review 20260819c - a fresh adversarial pass over the rewritten Go, after the refactor settled.
	- Opened: 20260819-150417
	- Closed: 20260819-152223

	- Went in over the same ground as the round before it, looking for what a whole-file rewrite could have carried across unchanged rather than for anything the linters would see. gofmt, vet, staticcheck, golangci-lint and govulncheck were clean and the suite was 694/0 going in, so none of the four defects below is tool-visible. Five new suite checks (694 -> 699) and three Go tests, every one of them run against the build that preceded its fix.

	- Item 1 is the one that matters. The other three are narrower, and two of them were transcribed faithfully from the frozen 2.1.0 script rather than introduced here.

	- ✅ Code Review 20260819c item 1: a folder rule written through a symlink claims nothing, and nothing says so.
		- Cause: only the Windows build resolved link spellings. `git rev-parse --show-toplevel` answers with the tree's real path, so on Linux and macOS a rule spelled the way it was typed was compared against the resolved one.
		- Note: this is the failure the whole feature exists to prevent - the run acts as the wrong account while the listing looks right. `account list` made it worse: the folder is real, so its "this rule can never match" note stayed quiet and gave a false all-clear.
		- Note: a synced folder, a stable name pointing at a dated one, a home that is itself a link - all ordinary ways to write a rule.
		- Fixed: resolution through the nearest ancestor that exists now runs on every platform, not just Windows. A destination that does not exist yet still canonicalizes, which is what `repo clone` needs. Two Go tests and two suite checks.

	- ✅ Code Review 20260819c item 2: the hotfix "changes shipped code" warning goes missing unless you run it from the top of the tree.
		- Cause: the pathspec naming the shipped source was written bare, and git reads one relative to the current directory.
		- Note: from anywhere else it matched nothing, git exited 0 with no output, and the warning simply did not appear. Every existing check ran from the repo root, so all of them passed.
		- Fixed: anchored at the repo root with `:(top)`. Suite check added that runs the whole thing from a subdirectory.

	- ✅ Code Review 20260819c item 3: an account's commit name replaces one the repo had pinned for itself.
		- Cause: both identity keys were gated on a single question about `user.email`, so a repo that set only `user.name` locally passed the gate and had that name overridden.
		- Note: these entries reach git the way `-c` does, which outranks the local config - so the override was silent, and it contradicted the rule the same code states.
		- Note: transcribed from the 2.1.0 script, which has it too. Not a hotfix: the name is display, the email is what attributes a commit, and that half was already right.
		- Fixed: asked per key, in one call rather than two. A repo-local value is honored and the account fills in only what the repo left unset. Two suite checks.

	- ✅ Code Review 20260819c item 4: a two-line answer read as one string kept the interior carriage return.
		- Cause: `runOut` trims the end of the whole capture; only `runLines` trimmed each line. Four places split a capture themselves and skipped it - `pr ok` reading the PR's head branch among them, where the branch name would then match no ref anywhere.
		- Note: hardening rather than a reproduced failure - the tools involved write LF today. It was already the reason `runLines` exists, applied in some places and not others.
		- Fixed: one `splitLines` helper, used by `runLines` and by all four. Go test added.

	- Nothing came out of the rest. Naming, comments, the linter set, the optimization levels, the pipeline stages, the demo and both installers were gone over in the three rounds before this one and needed no change. Two housecleaning items did: a code-review bullet still filed under features, and a block of generator boilerplate left in `contributing.md`.

- ✅ Code review 20260819b - a full adversarial pass over the rewritten Go, plus a re-check of the ground the earlier rounds covered.
	- Opened: 20260819-120120
	- Closed: 20260819-145236

	- The rewrite of 20260818 moved every command onto one run struct and gave every failure an error to return, so this went looking for what that shifted rather than for what it left behind. gofmt, vet, staticcheck, golangci-lint and govulncheck are clean and the suite was 684/0 going in, so none of the five defects below is tool-visible. Ten new suite checks (684 -> 694) and two Go tests; seven of the twelve fail against the build or the tree that preceded them.

	- Most areas needed nothing this round - naming, comments, the linter set, the optimization levels, the seven pipeline stages, the demo, the housecleaning sweeps and both installers were all gone over in the two rounds before this one. Items 6 and 7 are what did come out of them.

	- ✅ Code Review 20260819b item 1: the pre-command fetch drops its connect timeout for the accounts that configure an ssh key.
		- Cause: the timeout was added only when `GIT_SSH_COMMAND` was unset, so a caller's own choice would be left alone. The account selector sets that same variable a moment earlier, from the config file's `sshKey` - so the test saw a value and stood down.
		- Note: it goes missing for exactly the setups it exists for. An unreachable host then hangs for the full TCP wait rather than three seconds, on every command that starts with a fetch, which is nearly all of them.
		- Fixed: the run records whether the variable was already set when it started, and one helper builds the environment for both places that reach origin - the fetch, and `repo connect`'s probe. A value the caller chose is still left exactly as typed.

	- ✅ Code Review 20260819b item 2: on macOS and the BSDs, `/dev/null` passes for a terminal.
		- Cause: only Linux and Windows asked the real question. Everything else fell back to "is this a character device", which `/dev/null` is.
		- Note: that test decides the fail-closed rule - with no terminal to confirm on, a mutating command refuses rather than prompt into the void. The end state stays safe, since the prompt reads end-of-file and aborts, but the message is the wrong one. macOS and FreeBSD are published targets now rather than someday ones.
		- Fixed: `tty_bsd.go` asks the same ioctl the Linux file asks, under this family's name for it. Still nothing installed. The character-device fallback now covers only platforms nothing here is built for.

	- ✅ Code Review 20260819b item 3: `~` in a config value expands to nothing on native Windows.
		- Cause: four places resolved it through `HOME`, which a shell sets and Windows does not.
		- Note: a `tokenFile = ~/...` then reads no token and falls back to gh's own account, and a `path = ~/...` folder rule matches nothing - which reads exactly like no rule at all. `accounts.md` says the `~/.config` location works on Windows too, and it did not.
		- Fixed: one helper, `HOME` first so a shell that sets one still wins. What it cannot resolve is left as typed, rather than turned into a path that names somewhere real.

	- ✅ Code Review 20260819b item 4: one branch git won't delete stops the whole of `br prune`.
		- Cause: the deletes go out in a single call, which is what made prune cheap. Git deletes the branches it can and still exits nonzero for the rest - one checked out in another worktree, most often - and that status was returned.
		- Note: the run then ended with some branches already deleted, origin untouched and no count printed, on the one command whose whole answer is a count.
		- Fixed: non-fatal, the way the remote half beside it already was. It counts what actually went, names what it could not delete, and holds that branch's remote copy back so nothing is left here with nothing behind it on origin.

	- ✅ Code Review 20260819b item 5: an account fragment left readable stays readable through every re-apply.
		- Cause: the file is written 0600, but a mode only applies where the write creates the file.
		- Note: the fragment names the account and points at the token file, and `account apply` is the command someone re-runs after tightening permissions.
		- Fixed: the mode is set explicitly.

	- ✅ Code Review 20260819b item 6: the lint and audit tools gate at whatever version this machine happens to have.
		- Note: a finding that appears - or stops appearing - on a tree nobody touched is usually a tool that moved rather than code that did.
		- Fixed: `GO_TOOL_VERSIONS` in `config.bash` records the four, read back with `go version -m` since they spell `--version` four different ways and one has no such flag at all. Stage 1 warns on drift. Not a gate and not an installer - this pipeline installs nothing.

	- ✅ Code Review 20260819b item 7: nothing published says the builds are reproducible.
		- Note: a checksum is worth having because anyone can rebuild the bytes it covers, and that was recorded in a comment in `config.bash` and nowhere a reader would look.
		- Fixed: a short Install subsection with the command, verified to produce the same bytes as the pipeline's own build.

- ✅ Code review 20260819 - the installers, back at the repo root. Six findings, none of which reach the binary.
	- Opened: 20260819-103518
	- Closed: 20260819-111554

	- Pass over the installers that came back to the repo root. All six findings are in the two new files; none of them reach the binary. The first two are the serious ones - they end a default install with no output at all.

	- ✅ Code Review 20260819 item 1: a wget-only box could never install.
		- Cause: the latest-release lookup declines the redirect and reads the tag out of the header, and wget answers a declined redirect with exit 8 whether or not it printed what was asked for. Under `set -e` an assignment carries its command's status, so the run ended there - after the lookup had already succeeded.
		- Note: the one-liner printed nothing and exited 8. No message, no fallback, nothing to go on.
		- Fixed: `|| true` on the lookup, which is the only thing that ever wanted the status.

	- ✅ Code Review 20260819 item 2: any curl failure did the same thing, and hid the fallback.
		- Cause: same assignment rule. DNS, a proxy, a rate limit - anything that made curl exit nonzero ended the run, so neither the API fallback nor the message that names rate-limiting could be reached.
		- Fixed: `|| true` on both, and on the API fallback beside them.

	- ✅ Code Review 20260819 item 3: `-Arch` refused the machines it was written to explain itself to.
		- Cause: detection assigned back to the parameter, and assigning to a parameter re-runs its own `ValidateSet`. On x86 or 32-bit ARM the detected value isn't in the set, so the binder error arrived instead of the message naming what the release does publish.
		- Fixed: detection lands in its own variable.

	- ✅ Code Review 20260819 item 4: `-Tag` had the same shape, one layer deeper.
		- Cause: the scraped tag assigned back to `$Tag` re-ran its `ValidatePattern`, which made the explicit check below it dead code. Through the API fallback the throw was caught and reported as rate-limiting, which it wasn't.
		- Fixed: resolved into its own variable, so the check that was written for it is the one that runs.

	- ✅ Code Review 20260819 item 5: persisting PATH on Windows flattened it.
		- Cause: `[Environment]::GetEnvironmentVariable` hands back the expanded PATH. Reading that and writing it back turned entries like `%USERPROFILE%\bin` into literals - permanently, on a PATH we only meant to append one directory to. Worse under `-System`, where the whole machine's PATH goes through it.
		- Fixed: read raw from the registry with `DoNotExpandEnvironmentNames`, written back with the kind it already had.

	- ✅ Code Review 20260819 item 6: the captive-portal check read the whole binary to look at one byte.
		- Fixed: one byte off the stream.

	- ✅ Code Review 20260819, coverage: nothing exercised the release lookup, which is why items 1 and 2 got through green.
		- Fixed: two checks stand the network up as stubs - a curl that always fails, and a wget-only PATH where the stub prints the header and exits 8. Both fail against the build before the fix. The two PowerShell findings need the hardware or the network to reproduce, so they are pinned in the source the way the SHA256SUMS decode already is. Suite 613 -> 617.

- ✅ Code review 20260819a - the whole tree, top to bottom. Forty-three numbered items, plus the pass that preceded them.
	- Opened: 20260819-105954
	- Closed: 20260819-144325

	- Item 30, the last one open and the only one that needed a decision first. Fourteen new checks, nine of which fail against the tree that preceded them; the suite went 668 -> 682. That closes the round at 43 of 43.

	- ✅ Code Review 20260819a item 30: Windows binaries carry no icon and no version details.
		- Needs a Windows resource (.syso) beside the source. Two ways in: `goversioninfo` from a checked-in JSON template plus an .ico, which is the standard route and is well tested; or writing the COFF resource ourselves, which keeps the zero-dependency character but cannot be proved right from here - a malformed one links cleanly and fails on the machine that runs it.
		- Decided: `goversioninfo`, installed outside the tree, probe-gated in the pipeline and required by `release.bash`.
		- Done. `cicd/utility/gen-winres.bash` writes one `.syso` per published Windows target from a spec it generates, and the two are committed - they are linked into binaries whose checksums we publish, so rebuilding a release from its tag must not need a tool installed.
		- Which is why they carry the last released version rather than the working tree's describe output: a file that changed every commit could not be committed. A release stamps them with the version it is cutting - in phase 1 for the assets, then restored, and again in phase 2 where it lands in the bump commit beside the changelog heading.
		- `assets/gitsby.ico` is a committed asset too, regenerated by hand from `logo.png` (`gen-winres.bash --icon`) when the logo changes. Six sizes: 16/32/48 stay BMP so pre-10 Explorer draws them, 64/128/256 are PNG quantized to 256 colors - 134 KB down to 48 KB for a difference the eye cannot find at icon size.
		- Verified rather than assumed: both Windows targets link the resource and no other platform does, two cold-cache Windows builds are byte-identical with it in place, and the string and numeric version fields both read 2.1.0 out of the built `.exe`.

	- The documentation, 34-41. The suite went 666 -> 668.

	- ✅ Code Review 20260819a item 34: batching the branch deletes in `br prune` is the largest speed win available, and it changes the output.
		- One push per branch, each forking three processes. Eight branches cost 24 of the command's 81.
		- Deleting them in one call collapses the per-branch status and warning lines into one, so it needs a decision and a suite carve-out before it can be done.
		- Done, and the call was made here rather than deferred: the win is large and the output change is smaller than the finding suggested - one plan line and one status line instead of eight of each, which reads better. Measured on eight branches: 77 spawns down to 42, with the cached branch lookups from item 16 in the same figure. The local re-check still runs per branch before anything is handed to git, and a partly-failed remote delete counts what actually went rather than writing the batch off. Parity needed no carve-out.

	- ✅ Code Review 20260819a item 35: ten statements in the public docs are no longer true.
		- The command count is one short in three places, including the repo blurb.
		- The README and contributing both send a new contributor to a branch that has no Go code on it.
		- The README still describes a suite that runs against two implementations.
		- design.md documents a folder, a test leg and a pipeline engine that were all removed, and its release section describes work that shipped, wrongly.
		- Two smaller ones: a flag that only ever existed on the deleted engine, and a command spelled the old way.
		- Fixed, all ten: the counts (ten, and 23 with subcommands), the branch a contributor is sent to (named nowhere now - `git clone` then `cd src-go` is the whole of it), the suite that ran against two implementations, design.md's folder list, testing section and release section, `bin/gitsby` in the style guide, `-NoSync` in contributing, and the old command spelling in the one-liners. The dogfood caveat is in the README too - those destinations are one machine's paths.

	- ✅ Code Review 20260819a item 36: the Install section has no sub-headings.
		- Nothing in the contents leads a reader to "is this in my package manager", though the answer is written a few lines down.
		- The development section does not say the pipeline commits and pushes at the end, which will surprise someone running it on a fork.
		- Fixed: Install now has "Is it in my package manager?" (the answer was already there, four paragraphs down), "The one-liners", "Where it goes", "Without the installer" and "Coming from 2.x". The pipeline is described as eight numbered steps, and step 8 says in bold that it commits and pushes.

	- ✅ Code Review 20260819a item 37: several of the strongest features are buried.
		- One static binary with nothing alongside it is the third bullet of a compatibility list.
		- That every mutating command shows the exact git commands and asks first is the main safety argument and appears once, near the bottom.
		- `repo create` listing what it is about to publish, the offline behavior, and `account apply` teaching plain git the same rules are each a clause inside a longer paragraph.
		- Nothing anywhere says gitsby keeps no state of its own.
		- The repo blurb needs the same count fix, a homepage, and its topics refreshed - it still says bash and powershell.
		- Fixed in the docs: the three arguments - it shows its work, it keeps no state of its own, it is one file - are their own short list in "What it is", where nothing else competes with them. The offline behavior, the publish list and `account apply` each became a point of their own instead of a clause. The tagline names the show-and-ask promise.
		- Left to do by hand: the repo blurb, homepage and topics are GitHub settings rather than files here, and changing them edits the public repo page. `gh repo edit --description ... --homepage ... --add-topic go --remove-topic bash` is the one command.

	- ✅ Code Review 20260819a item 38: design.md has no goals and non-goals section, and no header.
		- The non-goals are the most interesting thing about the project and they are scattered across three sections and another document.
		- Everything else about the file is right. It is a decision log with rejection rationale recorded inline, which is the correct form here - do not restructure it.
		- Fixed: a "Goals and non-goals" section, with the seven non-goals gathered from the three places they were scattered across, plus a short note on what kind of document this is. Nothing else was restructured - it is a decision log and that is the right form for it.

	- ✅ Code Review 20260819a item 39: twenty-five finished items are still sitting in the open sections.
		- The Bugs section reads as fourteen open bugs, all of which are done.
		- The review items also want their outcome bullet labeled, so the finding and the fix can be told apart at a glance.
		- Fixed: 25 finished items moved into the matching Done subsections, and Bugs now says "None open" rather than reading as fourteen open bugs. Every review item's outcome bullet is labeled - "Fixed:", "Done:", "Decided:" - so the finding and what happened to it can be told apart at a glance.

	- ✅ Code Review 20260819a item 40: about twenty British spellings across the docs, scripts and code comments.
		- Not in the code of conduct or contributing - those reproduce upstream text and should stay as published.
		- Fixed: 23 of them across the docs, the pipeline scripts and the demo notes. `code_of_conduct.md` and contributing.md's DCO notice are untouched - both reproduce published text. Two of the 23 are in the shared `cicd/utility/include/` files, so a future re-sync from their source could bring them back.

	- ✅ Code Review 20260819a item 41: five paragraphs run long enough to be hard to scan.
		- The worst is 620 characters. All five are ideas that want to be bullets.
		- Fixed, all five plus the tagline: each became two or three short paragraphs, or a lead-in and bullets. The longest line left in the published docs is the tagline, and that one is an HTML cell rendering as three separate lines.

	- The pipeline, 17-18 and 26-32 (bar 30), plus 42 and 43. Eleven new checks, each verified against the pipeline that preceded them; the suite went 649 -> 666.

	- ✅ Code Review 20260819a item 17: the lint summary reports warnings on a perfectly clean run.
		- Its filter matches the test harness's own check labels, so a green pipeline reports seven warnings that do not exist.
		- A warning that fires when nothing is wrong is worse than no warning.
		- Fixed: the harness lines are excluded by shape (`ok:` / `FAIL:`) rather than by wording, so a check label about warnings stops reading as one. A clean log now reports CLEAN, and a real finding still reports.

	- ✅ Code Review 20260819a item 18: `--quick` still cross-builds three platforms.
		- It skips fuzz and the gif, which are not the slow part.
		- Fixed: `--quick` narrows the dogfood list to the native target. The other two cross-builds were the slow part it was meant to be skipping.

	- ✅ Code Review 20260819a item 26: the published binaries cannot be rebuilt to the same checksum.
		- Version control stamps go into the binary, and the release builds its assets before it cuts the tag - so the published binaries carry the previous revision and nobody can reproduce the checksums we publish.
		- Also wants the build id cleared, the native build built the same way as the cross-builds, and the toolchain pinned. Once it holds, say so in the README.
		- Fixed: `-buildvcs=false`, `-buildid=` and `CGO_ENABLED=0` on every build site, from one place in config.bash. Verified: two builds from a cold cache are byte-identical, and `go version -m` shows no revision. The ordering worry dissolves with the stamps gone - the changelog bump does not touch the source, so a phase-1 asset is the tagged commit's asset. The release toolchain is named in config.bash, since go.mod's line is a minimum rather than a pin.

	- ✅ Code Review 20260819a item 27: no build step limits itself to half the cores.
		- The compiler defaults to all of them, in every build and in the eight-target release loop.
		- Fixed: `BUILD_JOBS` is half the cores rounded up, and `-p` is on all four build calls.

	- ✅ Code Review 20260819a item 28: nothing in the pipeline looks at the standard library for known problems.
		- With no third-party dependencies, that is the only library code there is to check.
		- Fixed: `govulncheck` in stage 3, probe-gated like staticcheck. It runs even under `--quick` - it is a lookup, not a workload.

	- ✅ Code Review 20260819a item 29: no profiling step exists.
		- A flamegraph would be the wrong instrument here - the program spends its life blocked waiting on git, so a sampling profile is a flat wall with no leaders.
		- What carries signal is counting spawns per command against a fixture repo, and failing on a regression. The rotation and the seen-marker patterns already exist and can be reused as they are.
		- Done as spawn counting, per the recommendation: `cicd/utility/spawn-count.bash` measures eight commands against a restored fixture (origin included), compares with the newest previous run, and fails on a rise beyond a small tolerance. GFS-rotated like the lint logs.

	- ✅ Code Review 20260819a item 31: `-q` reaches the publisher but not the three test harnesses.
		- None of them accepts an option at all, so a quiet run still prints every one of 617 check lines.
		- Fixed: all three take `-q`, and the engine hands it on for an unattended run. Header, failures and totals stay.

	- ✅ Code Review 20260819a item 32: `--target=` and `--release=` are not accepted with an equals sign.
		- Fixed: both spellings of every option that takes a value.

	- ✅ Code Review 20260819a item 42: no script exists to run an older build alongside the current one.
		- Worth less here than in the projects it comes from: gitsby exits immediately, so nothing is ever held open. The real use is keeping timestamped builds around to bisect a behavior change.
		- Done: `cicd/utility/keep-build.bash` archives the current binary with a timestamp, lists what is kept, runs one by number, and diffs one against the current build on the same arguments. GFS-rotated.

	- ✅ Code Review 20260819a item 43: the demo script file is stale in two ways beyond the renamed commands.
		- It points a future editor at the deleted Windows engine, twice. Fix it in the same pass as the regeneration.
		- Fixed: the notes no longer point at the deleted Windows engine, and the scenario uses the current command names, so the next render publishes those rather than the old ones. The regeneration itself is still pending - it needs a full pipeline run.

	- The installers, 12-15 and 33. Ten new checks, each verified against the installers that preceded them.

	- ✅ Code Review 20260819a item 12: the installers cannot find a release that is only a prerelease.
		- Both the main route and the fallback ask the same endpoint, and that endpoint skips prereleases. So there is no fallback.
		- The failure message blames rate limiting, which sends anyone debugging it the wrong way.
		- Latent today, live the first time a version ships as a prerelease.
		- Fixed: the fallback lists the releases instead, newest first, taking the newest full one and saying so when only a candidate exists. The failure message names rate limiting as one possibility among several, and points at `--tag`.

	- ✅ Code Review 20260819a item 13: `install.ps1` has no `--help`, and the README tells people to use it.
		- Fixed: `-Help`, plus `--help` recognized before the binder sees it - which is what the README documents and what anyone types.

	- ✅ Code Review 20260819a item 14: `install.ps1` can report success over a binary that failed to run.
		- The verification step's exit code is never read, and a native command's failure does not stop the script on its own.
		- Fixed: `$LASTEXITCODE` is read, and a binary that will not run is reported as that rather than as a finished install.

	- ✅ Code Review 20260819a item 15: both installers write straight to the final path.
		- An interrupt mid-copy leaves a truncated executable in place that passed its checksum under a different name.
		- Re-installing over a copy that is currently running fails on both platforms.
		- Staging in the destination directory and renaming over the target fixes both at once.
		- Fixed: both stage in the destination directory and rename over the target. On Windows the incumbent is renamed aside first, since Windows will not overwrite a running executable but will rename one.

	- ✅ Code Review 20260819a item 33: decide whether `install.ps1` should run on Windows PowerShell 5.1.
		- It refuses below 7 on purpose, and the reason is sound. But 5.1 is what a fresh Windows install actually has, so the documented one-liner fails there.
		- The syntax is already 5.1-clean. Lifting it needs a fallback for three variables that do not exist in 5.1, one parameter spelled differently, plus forcing TLS and basic parsing.
		- Decided: yes. 5.1 is the machine most likely to be installing this for the first time. The three variables get a fallback, TLS 1.2 is switched on, every request asks for basic parsing, and the byte read is spelled each version's way. `PSUseCompatibleSyntax` against 5.1 now gates in the pipeline.

	- The defects, 1-20. Eighteen new suite checks, each verified against the build that preceded the fix; the suite went 617 -> 636.

	- ✅ Code Review 20260819a item 1: a second `account apply` deletes the rules and then gives up.
		- Two accounts claiming the same folder produce the same rule key twice. The first removal takes both, the second finds nothing, and git's "nothing to remove" is read as a failure.
		- End state is worse than before it ran: no rules at all, and an error.
		- Nothing warns that two accounts claim one folder in the first place.
		- Fixed: the key list is deduped, and git's exit 5 ("nothing to remove") is read as the end state it is rather than as a failure. `account list` now names any folder more than one account claims.

	- ✅ Code Review 20260819a item 2: gitsby and plain git can resolve the same folder to different accounts.
		- The two tie-breaks disagree when two accounts declare the same path. Gitsby goes by declaration order, git goes by what sorts last.
		- That disagreement is the exact thing `apply` exists to prevent.
		- Fixed: the plan is ordered by declaration index, reversed, so the rule gitsby keeps is the last one git sees. Checked both ways in the suite.

	- ✅ Code Review 20260819a item 3: a bare repo, or a `.git` directory, passes the in-a-repo check.
		- The question is asked of a command that answers in text and exits zero either way.
		- `status` there prints a full state block ending in "working tree clean", which it has no business claiming. `pullcom` prints its whole plan, gets confirmed, then dies in git.
		- Fixed: one `rev-parse` call answers all three questions in text; a bare repo and the `.git` directory are each refused by name, whatever the command.

	- ✅ Code Review 20260819a item 4: a token read from a file is never checked against the account it claims.
		- The name comes from the config key, so a stale token file reports the right name and pushes as the wrong one.
		- That is precisely the mistake the identity block exists to catch. With no `gh` installed at all it still names an account.
		- Fixed: a token from gh's own store still short-circuits; one from a file is probed with the token exported, and the block says either who it really belongs to or that it couldn't be checked.

	- ✅ Code Review 20260819a item 5: `--any-identity` quietly drops the commit identity and key.
		- Account selection is skipped entirely, but the Account line still names the account as if it had been applied.
		- Commits get authored by whatever git falls back to. The help only mentions the key mismatch, not the authorship.
		- Fixed: the Account line says the selection was skipped and what that leaves in place. Behavior is unchanged - what it did was never the problem.

	- ✅ Code Review 20260819a item 6: `raw` names an account for a repo you only cloned.
		- The gate accepts the remote-owner guess, so cloning someone else's repo prints "acting as <them>" - untrue, nothing was applied, and it tells a single-account user the feature exists.
		- Fixed: the same test the identity block uses, so nothing is claimed for a name merely inferred from the remote's owner.

	- ✅ Code Review 20260819a item 7: `br prune` tries to delete remote branches while offline.
		- `br merge` holds its remote delete back; prune has no such check.
		- Each failed push is reported as "already gone", blaming the branch for a network problem, and the summary reads as if it finished.
		- Fixed: the remote half is skipped while origin is unreachable and says so by name; the local deletes still happen.

	- ✅ Code Review 20260819a item 8: `release` in a repo with no origin cuts a tag nobody can fetch, silently.
		- The offline check never trips, because with no remote there is nothing to find unreachable.
		- `sync` gets this right and says so; release just ends on "Done."
		- Fixed: refused up front, naming `repo connect`. No tag is cut.

	- ✅ Code Review 20260819a item 9: the pre-command fetch may refresh a remote nothing else reads.
		- With no remote named, git follows the branch's own tracking remote. Every existence check afterwards reads origin.
		- Fixed: the fetch names origin. Caught by a repo whose branch tracks a second remote.

	- ✅ Code Review 20260819a item 10: the ssh-login cache ignores which remote it was asked about.
		- One slot, no key, three different callers. Reachable through `repo connect` from outside a repo, where it produces a mismatch warning about an origin that does not exist.
		- Fixed: keyed by remote URL. No dedicated check - reaching it needs three remotes and a stubbed ssh in one run, and the shape is the same one the other caches already use.

	- ✅ Code Review 20260819a item 11: `br switch` assumes a single remote.
		- With two remotes carrying the same branch name git refuses to guess, and the up-front check does not notice because it only ever looks at origin.
		- Fixed: one helper decides how a branch gets checked out, and the plan prints what the command will run. Applies everywhere a remote-only branch can be checked out, not just `br switch`.

	- ✅ Code Review 20260819a item 16: an unresolvable default branch is re-derived on every ask.
		- The two branch lookups are the only cached values in the codebase with no "we already asked" flag, so a repo where the answer is empty repeats the whole five-command ladder each time.
		- Measured: 38 processes for one `status`, 25 of them the same five commands over and over.
		- Fixed: every cached answer now pairs a value with a "we already asked" flag, so an empty answer is remembered like any other. Came free with the shape work in item 21.

	- ✅ Code Review 20260819a item 19: the hotfix warning watches a folder that no longer exists.
		- It was written when the deliverable was `bin/gitsby`. A hotfix to the code that actually ships gets nothing.
		- Fixed: it watches `src-go/`, named once beside the reason. The two suite checks were pointed at the same place.

	- ✅ Code Review 20260819a item 20: file permissions are never checked, and one directory is created wide open.
		- A token file readable by everyone loads without comment. ssh and gh both refuse or warn on that.
		- The folder holding the per-account identity fragments is created 0777 and relies entirely on umask.
		- A malformed inherited `GIT_CONFIG_COUNT` is read as zero, which half-overwrites whatever the caller set up. That variable is injected by the terminal here, so it is not hypothetical.
		- Fixed: the fragment directory is 0700 and the fragments 0600; a token file other users can read is called out by name; a GIT_CONFIG_COUNT that isn't a count stops the run instead of half-overwriting the caller's block.

	- The Go shape items, 21-25. One problem wearing four hats: gathering the run's state into a struct is the change the other three followed from.

	- ✅ Code Review 20260819a item 21: the Go reads as a shell script transcribed into Go syntax.
		- State is passed through about 120 package-level variables. Several functions take nothing and return nothing, and work only by mutating them.
		- Not one function returns an error. Failure is a hard exit called from inside leaf helpers, which is also why nothing can be unit tested.
		- Records are packed into tab-delimited strings and re-parsed to sort them.
		- All of that is one problem wearing four hats. Gathering the run's state into a struct passed to the command functions is the change the other three follow from.
		- Note against the old builds: only input and output parity matters now, so mirroring their structure is not a reason to keep any of this.
		- Done: the run's state is a struct passed to the command functions; every failure returns an error and main is the only place that exits; the tab-delimited sort became typed records. 4529 lines rewritten, output byte-identical (617/268/27 all green, parity unchanged).

	- ✅ Code Review 20260819a item 22: there are no Go tests at all.
		- The whole suite is external. The pure string functions - remote parsing, config values, path canonicalization, tag matching - have a lot of edge cases and nothing exercises them directly.
		- Done: unit tests for the parsing, the config and folder matching, the URL shapes, the version bump, the includeIf ordering and the output framing. `go test ./...` gates in stage 2.

	- ✅ Code Review 20260819a item 23: add a linter config so the review findings become gates.
		- gofmt, vet and staticcheck are clean and gated already. A config file would add the checks that caught the rest: unchecked errors, shadowed builtins, and the naming convention below.
		- Done: `src-go/.golangci.yml` - errcheck, ineffassign, predeclared, unconvert, revive (var-naming, redefines-builtin-id, and three flow rules). Probe-gated in stage 1 like staticcheck.

	- ✅ Code Review 20260819a item 24: internal names do not follow Go's convention for initialisms.
		- Twenty-six of them, all unexported, all internal. No effect on output or arguments.
		- Done: URL, SSH and HTTPS spelled the Go way throughout. No effect on output or arguments.

	- ✅ Code Review 20260819a item 25: five discarded errors want either handling or a reason.
		- Three of them set environment variables that decide the whole account selection.
		- Done: the three that decide account selection now stop the run; the temp-dir removal and the readability probe say in one line why they discard theirs.

	- Also in the same round, and unnumbered: the defects a first pass turned up.

	- From the first 20260819a pass. Everything below was checked against the code, not inferred. gofmt, vet, staticcheck and the suite (617/0) are all clean, so none of this is tool-visible.

	- ✅ Twenty regression checks reported on the terminal they were run from, not on the code.
		- The harnesses pinned git's config files and gitsby's own config file. Two inputs outrank all of those and arrive from any ordinary working terminal: `GIT_CONFIG_COUNT` with its numbered keys beats every config file, a repo-local one included, and an inherited `GH_TOKEN` is what a gh call reports back.
		- Ten checks per implementation, the same ten on both, which is what showed it was not a port difference. Five gh checks that can only pass when no token is held, and five identity checks that read a commit address back through a config file.
		- Nothing was wrong with the product. The same suite and the same builds pass standalone, and pass under the pipeline once the environment is clean.
		- Fixed in all three harnesses. `fuzz.bash` was also the only one never pinning gitsby's config file.
		- Pinned in the source of each harness. The two runtime companions are labeled as regression guards: on a clean machine they pass against a harness that isolates nothing.

	- ✅ `demo-repo.bash` removed whatever directory it was pointed at, without checking whose it was.
		- It took a root path as its first argument and `rm -rf`'d it before doing anything else. A mistyped or inherited argument took whatever lived there, and the script then reported success.
		- Reproduced against the previous version: a directory holding an unrelated file was passed as the root, and came back empty with an exit code of 0.
		- Fixed by stamping the directories it builds. Only a stamped one is removed; a relative path, the filesystem root, a symlink and anything containing `..` are all refused up front.
		- Checked against the previous version. The filesystem-root case is pinned in the source rather than run, since running it against a build without the guard is `rm -rf /`.

	- ✅ Every other recursive or forced removal now fails closed on an unset variable.
		- All of them name a path the script itself created, but they were spelled so that an unset variable would have widened the target rather than stopped it.
		- Ten sites across both installers, the pipeline engine and all four harnesses. The suite checks the whole set, so a new unguarded one is caught.

	- ✅ The publish preview leaked its throwaway git directory when a run was interrupted.
		- The Bash build removed it on the way out of the function that made it, so a Ctrl-C while the preview was still on screen stranded an empty directory in temp. The PowerShell build already covered this.
		- Moved to the exit path, which already runs on interrupt. Checked by driving the cleanup hook directly - a real Ctrl-C could not be staged, since Git Bash defers the signal until the native child returns.

	- ✅ Twelve regression checks were testing nothing on Windows.
		- The suite handed PowerShell its own MSYS paths. .NET has no mount table, so `/tmp/x` and `/c/x` were read against the current drive root - `Set-Location`, the script lookup and `ReadAllBytes` all failed and the commands under test never ran.
		- Seven reported red. The other five passed because they forbid something that also never happened, which is the worse half. Among them the guard for the working-directory bug, which had been guarding nothing.
		- Fixed with an `fWinPath` helper, the same conversion the folder-account block already needed. Two smaller ones alongside: Git Bash rewrites a unix-absolute argument before the native pwsh sees it, so the `-Ref` refusal was being triggered by the wrong rule; and the system install location is the platform's own, not `/usr/local/bin`.
		- Windows now runs 850/0, matching Linux. Checked the repaired guard fails against the code that predates the working-directory fix, so it discriminates rather than merely passing.

	- ✅ The identity probe ignored the ssh key git was configured to push with.
		- It ran a bare `ssh`, so a repo selecting its key through `core.sshCommand` was reported as the default key's account. Where that matched gh's account the mismatch check passed with both halves wrong - green in exactly the setup it exists for.
		- Fixed to follow git's own precedence, `GIT_SSH_COMMAND` then `core.sshCommand`. The identity line takes the key file from the same source, so it can't name the right account beside the wrong key.
		- Same override was overriding the key on `fetch` and the remote probe, which made a private repo reachable only via that key look like being offline.

	- ✅ The PowerShell build died on the identity line whenever no ssh command was configured.
		- `Get-GitSshCommand` returns a list, but PowerShell unwraps a one-element return to a bare string - and under StrictMode, reading `.Count` off a string throws. One element is the ordinary case: a plain `ssh` with nothing configured.
		- So any repo with an ssh remote and no `core.sshCommand` failed with "The property 'Count' cannot be found", which is most of them. The Bash build was never affected; bash arrays don't unwrap.
		- Found by running the suite's PowerShell leg on Windows, which until now had only ever run on Linux. It would have failed there too - it had simply never been run since the identity work landed.

	- ✅ gh acted as whatever account was last switched to, regardless of who owns the remote.
		- Now picks the owner's account for the run when gh already holds it, via `GH_TOKEN`, leaving gh's active account alone. Only when the owner can be named and the token is held - an org or someone else's repo is left untouched rather than refused.

	- ✅ On Windows, a local-path remote was read as an ssh host named after the drive letter.
		- `C:/path/to/repo.git` matched the `host:path` shape, so every command ran an ssh identity probe against a machine called `C` and reported an account for it.

	- ✅ PowerShell: a joined `-Config=FILE` failed silently.
		- PowerShell can't bind a joined option through `-File`. Ahead of a command it ate the next word as the value, so `br list` arrived as `list`; after one it overflowed the positional slots.
		- The first case printed the help and exited 1, which `-q` silenced entirely - the reported symptom was a command that appeared to do nothing.
		- Now refused by name from any position, naming `-Config FILE` and `-Config:FILE`. Bash keeps taking the joined form, and so does `raw`, which reads the real command line.

	- ✅ `--config ""` silently used the default config instead of refusing.
		- The check asked whether the value was non-empty, not whether the option was typed, so an empty one was indistinguishable from never passing it.
		- That fell back to the default file, which decides the account - a script whose variable came out empty would push as the wrong identity and say nothing. Both builds.
		- An empty `GITSBY_CONFIG` still falls through on purpose: an unset environment variable and an empty one are the same thing, unlike a typed option.
		- Found by the new fuzz vectors on their first run.

	- ✅ `repo clone` refused to re-run, and `repo connect` refused a matching URL, on Windows.
		- Git stores a local-path remote in the platform's own spelling: hand it `/c/tmp/x` and it gives back `C:/tmp/x`. Both commands compared their own argument against git's copy as plain text, so the same directory read as a different one.
		- Both now compare local paths as paths. These were the two long-standing Windows-only failures in the suite.

	- ✅ The PowerShell installer never verified the checksum, and said the release had none.
		- Found by running both documented one-liners against the current release: the Bash one reported the checksum verified, the PowerShell one reported no `SHA256SUMS` for the same release, which does publish one.
		- Cause: GitHub serves that file as binary, and PowerShell returns a response body as raw bytes for anything it doesn't treat as text. Read as lines, bytes match nothing, so no checksum was found and the download was installed unverified.
		- The message made it look settled rather than broken, so the default install had gone unverified since the check was added. The Bash installer was never affected.
		- Fixed: the body is decoded before it is read. Verified against the published release - the checksum is found, compared, and matches the installed file.

	- ✅ Every install command in the README 404s, because `main` is still the 2022 tree.
		- `main` holds no `install.bash`, `install.ps1`, `install-dev.*` or `bin/gitsby.ps1`, so all six documented one-liners fail at the download.
		- Cutting v2.0.0 fixes it outright: the merge to `main` puts the files there, and `releases/latest` stops resolving to the 2022 `v1.0.1`, which is a dead end for the default install path (that tag predates the `bin/` layout).
		- Until then the working incantation is the `dev` URL plus `--release dev` / `-Release dev`. Left undocumented on purpose rather than pointing strangers at `dev`.

	- ✅ The SSH identity line named the local login instead of the account being acted as.
		- It asked `ssh -G` about the bare host. With no user in the target, ssh answers with the OS login name, so a push as the second account displayed as `<os-login>@github.com`.
		- That value is neither of the two real ones: the connect user is `git`, and the account is whatever the key authenticates as. On a personal machine it looks plausible enough to be believed, which is worse than showing nothing.
		- The probe now uses the connect target, so an explicit user in the remote URL is honored the way git honors it. Host alias resolution is unaffected - the user part only overrides `User` in `~/.ssh/config`.
		- The line also leads with the account now, resolved by asking the host. That is what it existed to answer; the connect user is identical for every GitHub account, and the key shown is only ssh's first readable candidate, not necessarily the one that authenticates. Offline it says `unknown` rather than guessing, and skips the round trip.
		- Every other test uses a local-path origin, which has no ssh identity, so the whole line had shipped untested. It now has a fake ssh that reproduces the real defaulting behavior.

	- ✅ A byte-order mark on the three PowerShell files broke both installer one-liners and direct execution.
		- `irm` keeps the BOM, so `iex` and `[scriptblock]::Create` saw it glued to the shebang and the first line stopped being a comment. Both documented one-liners failed for every user, on every platform.
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

	- And the shape-and-process half of it.

	- ✅ The demo gif demonstrates an account changing on a partial folder match higher in the path.
		- Folder-based accounts are the headline feature and the demo never showed them. Three scenes were added to the end of the existing demo rather than made into a second gif, so the one loop tells the whole story.
		- The throwaway world now has two repos in trees that differ from their first folder down, and a gitsby config matching on `github.com/acme-corp` and `github.com/mika-rivers`. Different roots are the point: a shared root would not show that the match is a run of folder names rather than a prefix.
		- The closing scene runs the same command in the second tree, with no flags and nothing configured per repo, and the account has changed. The six scenes before it were already acting as the work account and now say so on their identity line.
		- The prompt shows the folder the command runs in. A demo about folders that hides the folder proves nothing.
		- The identity the accounts set is deliberately not exported into the demo's environment. It had been, and an exported `GIT_AUTHOR_EMAIL` supplies exactly what the folder rules are meant to supply - the demo would have been showing something it had not proved.
		- 2632 frames, 122.5 seconds, 11.06 MB, up from 2007 / 84.9 s / 9.97 MB. Read time is free; the growth is the three scenes' own output and typing.

	- ✅ The demo gif has a readable script, and its tooling lives in one place.
		- What the demo shows was only ever recorded as a scenario table of captions, commands and timing numbers, next to a renderer full of constants. Changing it meant reading both.
		- `cicd/utility/demo/script.txt` now describes it in plain language: the format, the set, the throwaway repo, and one section per scene with its caption, its typed line and how long it holds. That file is the one to edit.
		- The scenario file stays as the machine version and points at it. Nothing parses the script - keeping the two in step is deliberate habit, not a mechanism.
		- The renderer, the repo builder and the scenario moved from `cicd/` and `cicd/utility/` into `cicd/utility/demo/` alongside it. Both pipeline engines needed their paths and lint globs updated by hand, since neither discovers files.

	- ✅ The fuzz suite can pass on Windows.
		- Three vectors clone into a directory named `*`, `?` or `v*`. Win32 forbids those characters in a path, so native git cannot create such a work tree at all and the check could never pass there.
		- They are skipped on Windows now, with a line saying why. The suite already skipped four PowerShell vectors there for the same kind of reason.
		- Not a gitsby bug: MSYS `mkdir` will happily make one of those directories, which is what makes the first guess wrong.

	- ✅ The PowerShell build verified on Linux.
		- It had shipped without ever being executed there, which was one of the stated requirements. Run against the full suite on Debian, both legs.
		- One check failed, for an environment reason rather than a real one: with `gh` absent, `pr create` refuses over the missing tool before it gets to the offline refusal the check is about. It uses a stub now, so it tests the same thing everywhere.

- ✅ Code review 20260818 - the first full review of the Go code. Eighteen items: thirteen defects, five of shape and speed.
	- Opened: 20260818-181424
	- Closed: 20260819-124128

	- From a full review of the Go code, 20260818. gofmt, vet, staticcheck and the suite (530/0) are clean; these are what the tools don't see. Several are inherited from the frozen bash build - latent there, but live in the shipping binary.

	- ✅ Code Review 20260818 item 1: `pr ok` can destroy never-pushed commits.
		- Standing on the PR's own branch with no upstream configured, the lost-work guard asks `@{u}` and gets silence, so it passes. gh then merges what origin has and deletes the branch with `-D`.
		- The stronger per-branch check only runs when standing somewhere else.
		- Inherited from the bash build.
		- Asked of the PR's own branch by name wherever you are standing. `@{u}` answers nothing at all for a branch pushed without `-u`, which is the one arrangement that lost the commits.

	- ✅ Code Review 20260818 item 2: `repo create`/`repo connect` never actually select the target account.
		- The late re-selection is a no-op behind the already-applied guard, so publishing happens as gh's active account, silently. The comment at the call site says the opposite.
		- Inherited from the bash build.
		- The target named on the command line resolves the account, ahead of the validation that itself talks to gh. The late re-selection behind the already-applied guard is gone.

	- ✅ Code Review 20260818 item 3: the "gh's active account is 'X'" identity line can never print truthfully.
		- The token is exported before the probe that asks who was active, so the probe answers as the new account and the line stays dark. With a tokenFile whose token belongs to a different login, it prints a wrong name instead.
		- Inherited from the bash build.
		- The probe runs before the token is exported, so it can still answer with the account being replaced.

	- ✅ Code Review 20260818 item 4: `account apply` can't clean up rules under folder paths with a space.
		- The managed-includes scan splits each config line at the first space, so such keys are never recognized as ours. Re-runs append duplicates, and a rule removed from the config file keeps applying forever.
		- Inherited from the bash build.
		- Reads the rules with `--null`, so a key holding a folder path with a space comes back whole.

	- ✅ Code Review 20260818 item 5: `account apply` reports success no matter what.
		- The fragment truncate error is discarded and every `git config` exit code is ignored; "Wrote ..." and "Done." print regardless, exit 0.
		- The one command that writes outside the repo is the one that can silently no-op.
		- Every write is checked; the first failure stops the run and names what was left incomplete.

	- ✅ Code Review 20260818 item 6: `pr ok` with a dead PR number sails through preflight.
		- A failed `gh pr view` silently falls back to the current branch, so the plan is confidently about the wrong thing and the run dies after confirmation - the shape preflight exists to prevent.
		- Head branch and state come back in one call. A number gh can't resolve is refused, and so is a PR that is no longer open.

	- ✅ Code Review 20260818 item 7: offline reads as "repo doesn't exist" in `repo connect`/`repo create`.
		- Any `gh repo view` failure is taken as absence and stated as fact, with advice that derails further. These two skip the pre-command fetch (no origin yet), so offline is never discovered for them.
		- gh's stderr tells a name that resolves to nothing apart from an API it couldn't reach; the second is repeated back rather than stated as absence.

	- ✅ Code Review 20260818 item 8: `--offline` is a hidden third spelling of `--no-fetch` - and pushes still go out.
		- Contradicts the design rule that offline is a discovered state, never a flag. `sync --offline` publishes work.
		- Call to make: drop the alias, or make that one spelling refuse outgoing traffic too. Inherited from the bash build, undocumented in help.
		- Dropped, and refused by name with a pointer to `--no-fetch`. A flag that also stopped the pushes would only simulate a state the fetch already discovers, and nothing outside the source ever documented the spelling. Reasoning in design.md.

	- ✅ Code Review 20260818 item 9: the `sshkey` config value reaches shell-executed strings unquoted.
		- Concatenated into `GIT_SSH_COMMAND` and written into `core.sshCommand`; git hands both to a shell. The config is trusted input, but the file is redirectable by flag/env, and the repo-local sshCommand path already refuses quoting tricks - this path should match it.
		- A key path carrying whitespace or a shell character is dropped and listed as unusable, rather than quietly falling back to whatever key ssh picks.

	- ✅ Code Review 20260818 item 10: branch names from a cloned repo can reach git as leading options.
		- A repo whose default branch is named `-something` makes checkout/merge/branch/push parse it as flags. Bounded to breakage, not code execution. `--` separators fix it; the ssh probe paths already have them.
		- A dash-led name is refused before it reaches git in a leading argument position - checkout, merge, branch delete.

	- ✅ Code Review 20260818 item 11: a handed-over repo's own `.git/config` can pick gitsby's identity and token file.
		- `gitsby.ghAccount`/`gitsby.ghTokenFile` are honored from local config, so a foreign repo can have an arbitrary readable file loaded into the token env for child processes. No exfiltration channel exists - the credential helper is host-scoped - so this is identity confusion plus file read, not theft. Consider honoring tokenFile from global/folder config only.
		- `gitsby.ghTokenFile` is honored from global/system scope only. `gitsby.ghAccount` still reads repo-local: naming a login there is an ordinary thing to do, and the account still has to be one you hold.

	- ✅ Code Review 20260818 item 12: the wrong-account warning talks about pull requests on commands with no gh involvement.
		- The ssh-key-mismatch case appends the "gh does the pull request work..." sentence to plain push commands, and can name '?' when gh is absent - right at the y/n moment.
		- The gh sentence prints only where gh is the one acting.

	- ✅ Code Review 20260818 item 13: the push-identity gate fires for commands that push nothing.
		- Keyed on mutating, not pushing, so `pullcom -q` under a mismatched key is refused outright and pays a live ssh probe, for a local-only commit.
		- Keyed on whether the command pushes, named by exception so a mutating command added later stays covered until it says otherwise.

	- ✅ Code Review 20260818 item 14: skip the identity network probe when no identity block will print.
		- Every token-configured run paid a live `gh api user` round trip; `br list`, `account list` and bare `pr` never show what it feeds.
		- One predicate now answers "does this run reach the identity block", and both the probe and the later prime read it.
		- Measured with an account configured: `br list` 12 -> 11 spawns, `account list` 14 -> 11, `repo url` 13 -> 10. The one dropped from each is the network call.

	- ✅ Code Review 20260818 item 15: cache the handful of git answers asked repeatedly per run.
		- Origin's url, the current branch, upstream state, ahead/behind, git's ssh command, the context directory and the terminal width are each asked once now.
		- Ahead and behind came from two separate calls asking git the same thing; one call answers both.
		- Invalidated centrally by the runners that execute a step, not by each writer by hand - a step is exactly what can make an answer stale, and a future one gets it for free.
		- Measured: `status` 20 -> 17 spawns, `sync` 32 -> 25, `pullcom` 28 -> 24.

	- ✅ Code Review 20260818 item 16: two per-branch spawn loops left in `br prune`.
		- The survey's remote-existence check was already answered by the merged map beside it, and the delete loop re-verified the same target refs once per branch.
		- Dropping the verify costs nothing: merge-base against a ref that has gone fails, which is the same answer.
		- Measured on five merged branches: 69 -> 52 spawns, and the gap widens with the branch count.

	- ✅ Code Review 20260818 item 17: least-surprise paper cuts, one sweep.
		- `release` with nothing new exits 1 where every sibling's nothing-to-do exits 0 - and the About text promises idempotent re-runs.
		- `gitsby -q` alone: "Unknown command ''" instead of help.
		- `pr <n> extra` is the one place a trailing argument is silently ignored.
		- `pr create` with an unquoted title doesn't give the quote-your-message hint `pullcom` gives.
		- `repo clone owner/name` fails only after confirmation; `create`/`connect` both accept the shorthand.
		- "yes" at the y/n prompt aborts.
		- An option typed between `raw` and the tool is called an unknown subcommand.
		- All seven fixed. Nothing-to-do is a success for `release` too; a command list answers a bare option; `pr` refuses its trailing argument and hints at quoting; `repo clone` takes `owner/name` before the plan, not after; `yes` is a yes; an option before the tool says where ours go.
		- The overflow message picked up the quote-it hint as well - the ceiling is four slots, so an unquoted message of three words or more never reached the per-command hint.

	- ✅ Code Review 20260818 item 18: dead code and stale comments, one sweep.
		- Unreachable option-value arm plus its dead variable in the parser; two dead branches in the prompt helper; an empty-message fallback nobody passes; a handover error message a preceding check makes unreachable; a comment describing a superseded key-splitting contract; a near-verbatim duplicated comment in main. (The prune survey's redundant re-check went with item 16.)
		- All six gone. The handover kept its branch but not its claim: it named a cause the preceding check had already ruled out, so it reports what actually failed.
		- Also found: the three help printers each returned early under `-q`, which is why `-q --help` printed nothing. Removed with item 17's bare-option fix.

- ✅ Code review 20260813 - the folder-name rules, the release script and the removal audit.
	- Opened: 20260813-121029
	- Closed: 20260813-164625

	- Light pass over the folder-name rules, the release script, the changelog template guard and the removal audit, plus what they knocked loose elsewhere. Nothing wrong with the changes themselves; all four findings are things around them that went stale or were missed.

	- ✅ Code Review 20260813 item 1: the README stopped saying where it installs to, or that the download is checked.
		- Cause: the section was folded down to two one-liners so they could be pasted and run as-is. Dropping the flag table was the point; the locations and the checksum went with it by accident. The sentence left behind also had a stray plural and said "options" twice.
		- Note: both are reasons to trust the installer, and neither is visible until you have already run it.
		- Fixed: restored in the same place, without the flags - what you need Git and a shell for, what gets checked, a small table of the four install locations, the PATH note on Windows, and a pointer to `--help` for the rest.

	- ✅ Code Review 20260813 item 2: the changelog described a README that no longer exists.
		- Cause: it claimed install and the worked example are the first two sections. Both have since moved down, below the commands and the accounts material.
		- Fixed: the entry names the order the page actually has.

	- ✅ Code Review 20260813 item 3: markdown under `project/design_docs/` was not linted.
		- Cause: both engines list `*.md` and `project/*.md`, and the directory is a level below that. It arrived after the globs were last set.
		- Fixed: the directory added to both engines. The file in it was already clean.

	- ✅ Code Review 20260813 item 4: the PowerShell installer read its own temp path as a wildcard when cleaning up.
		- Cause: the removal took the path positionally. Every other removal in the tree names it literally, and this one was missed when they were hardened.
		- Note: only bites on a temp path containing a bracket, so nothing to reproduce in ordinary use.
		- Fixed: named literally, and skipped outright when the path was never set.

- ✅ Code review 20260812 - against the coding, performance, pipeline, housecleaning, marketing and installer standards.
	- Opened: 20260812-150636
	- Closed: 20260812-181826

	- Full review against the coding, performance, pipeline, housecleaning, marketing and installer standards. What is fixed here is listed below; the rest is filed above as open items.

	- ✅ Code Review 20260812 item 1: git over https authenticated with an empty password.
		- Cause: the token was supplied only when it replaced a different active account, while the helper that reads it was installed either way. The helper sets aside any credential manager configured ahead of it, so nothing was left to answer.
		- Note: worst on the setup needing no configuration - one account, logged in to gh, pushing over https.
		- Fixed: supply the token whenever one is found.

	- ✅ Code Review 20260812 item 2: a trailing comment in the config file became part of the value.
		- Cause: `#` started a comment only at the start of a line, and the documented example writes them at the end of one.
		- Note: a folder rule carrying a comment could never match, and a rule that never matches reads exactly like no rule at all.
		- Fixed: a `#` after whitespace ends the value. Quote the value to keep a literal one.

	- ✅ Code Review 20260812 item 3: an account name could name a file outside the include directory.
		- Cause: the name went into a path with nothing checking it, so a name containing a path sent `account apply` elsewhere - as far as the global git config.
		- Fixed: hold the name to letters, digits, dot, dash and underscore, and report anything else as an unread key.

	- ✅ Code Review 20260812 item 4: PowerShell read a repo with its own ssh key configured using the default key instead.
		- Cause: the fetch and the probe replaced git's ssh command to add a connect timeout, rather than adding to it.
		- Note: a private repo only the account's key can reach reported as unreachable, and the publishing commands then refused.
		- Fixed: add the timeout to git's own command, as the Bash build already did.

	- ✅ Code Review 20260812 item 5: `origin/HEAD` was healed after every fetch, at the cost of a second query to the remote.
		- Fixed: only when there is nothing to read locally. git 2.47 and newer write one at clone.

	- ✅ Code Review 20260812 item 6: the passthrough asked gh which account was active, over the network, on every call.
		- Note: the answer only named the account being replaced, on a line the passthrough does not print.
		- Fixed: skip it where no identity block is shown.

	- ✅ Code Review 20260812 item 7: a bare GitHub login got no identity line, in the command that exists to answer who a push goes out as.
		- Cause: the line asked whether some configured value had been used. A bare login names no account and sets no key, so it satisfied none of those tests - though it does select the token git authenticates with.
		- Note: `GITSBY_ACCOUNT` documents the bare-login spelling, and `raw` already reported it on stderr, so the two disagreed.
		- Fixed: an account asked for by name is enough on its own. One merely inferred from the remote's owner still prints nothing, so a single-account machine sees no change.

	- ✅ Code Review 20260812 item 8: the test suite read whatever accounts the person running it had configured.
		- Cause: it isolates git config and the commit identity, but not gitsby's own config file, which decides the account a command acts as.
		- Note: found by running it - a single `protocol = ssh` line in a real config failed three checks per implementation, because the repo commands then built a different remote URL than the check expected.
		- Fixed: point `GITSBY_CONFIG` at an empty file for the whole run. The account block, where discovery through `HOME` is the thing being tested, opts back out.

- ✅ Code review 20260731.
	- Opened: 20260731-104703
	- Closed: 20260731-110307

	- Delta review of the branch-display and status-label rounds. One finding, both implementations.

	- ✅ Code Review 20260731 item 1: `br list` refused to run in a repo whose default branch can't be told.
		- The default-branch gate exempted only `status` and the `repo` commands, so `br list` - read-only, and the other command you'd run to look around - errored out. The `Default branch: unknown` fallback it had just gained could never print.
		- Fixed: `br list` joins the gate exemption. Mutating commands still refuse up front.

- ✅ Code review 20260730.
	- Opened: 20260730-160015
	- Closed: 20260730-162216

	- Delta review of what landed since the 20260727b round: the offline handling, the BOM fix, the installer message, and the SSH identity line. Three findings, all in the offline messages, all in both implementations.

	- ✅ Code Review 20260730 item 1: an offline hotfix land pointed at a recovery that leaves the hotfix unshipped.
		- The warning said `sync` publishes the merge, but a hotfix land ends on `dev` after the back-merge - `sync` from there publishes `dev` and leaves origin's default branch stale. That is the one branch a hotfix exists to fix, and following the advice would read as success.
		- Fixed: the hotfix warning names both steps, `br switch <default>` then `sync` - the switch's parking push publishes `dev` on the way, so the pair covers both branches. A normal land still just names `sync`, which is right there because the command ends on the target.

	- ✅ Code Review 20260730 item 2: parking offline claimed committed work awaits even when there was nothing to push.
		- A clean, in-sync branch got "Your work is committed locally" with no work at all; online, the same state correctly said "Nothing to push."
		- Fixed: nothing ahead of the last-known origin means "Nothing to push.", offline or not.

	- ✅ Code Review 20260730 item 3: the skipped-push warning said `sync` publishes it, during commands that then leave that branch.
		- `br switch` and `br land` park the current branch and move off it, so a `sync` from where you end up publishes a different branch.
		- Fixed: the warning names the branch it means, and says `sync` from it.

- ✅ Code review 20260727b.
	- Opened: 20260727-090659
	- Closed: 20260727-201925

	- Full pre-release review, run across nine lenses with every finding independently checked before it was accepted. Fifty-three held up; the ones that changed behavior are below. Deep evidence is kept out of the repo.

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

- ✅ Code review 20260727.
	- Opened: 20260726-115807
	- Closed: 20260727-004615

	- Review of the hotfix branches, the gh/ssh identity check, and the docs pass that went with them.

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

- ✅ Code review 20260726.
	- Opened: 20260726-125534
	- Closed: 20260726-133354

	- Release-prep pass over what changed since the last review: the noun grouping, `pr create`, and dropping bare `commit`/`pull`.

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
		- The `repo create refuses when origin is already set` check reuses a fixture whose origin is a real `https://github.com/me/proj.git`, but dropped the `insteadOf` rewrite that every neighboring check sets. Confirmed by the server's own "Repository not found" reply.
		- design.md says neither suite touches the network, so this was also the thing that surfaced item 13 in the first place.
		- Fixed: the rewrite is back on that check.

	- ✅ Show gh's account in the pre-flight, and refuse a gh write that acts as someone else.
		- gh authenticates with its own token and ignores ssh config, so `pr create`/`pr ok`/`repo create` act as gh's account while `git push` acts as the remote alias's key. With per-account aliases those differ, and the pre-flight was naming only the ssh one - the wrong identity for exactly those commands.
		- Found live: in a repo on the second account, gh reports the first with READ permission, so a `pr create` there would act as an account that can't do it.
		- Three outcomes, not two. Unknown (no agent, https remote, deploy key, gh logged out) is reported and never blocks - otherwise every CI runner breaks. Only a difference both sides confirm counts.
		- Interactive: warning directly above the confirm prompt. Unattended: error, nothing runs. `--any-identity`/`-AnyIdentity` proceeds, and the mismatch still shows on the identity line.
		- Decided against a general gh-config validator: policing another tool's setup isn't gitsby's job and would turn working commands into refusals.
		- 26 new checks across both implementations, driven by a fake ssh that answers the greeting GitHub really sends and doubles as the git transport. Verified they fail against the pre-feature build.

	- ✅ Extend the identity check to `repo create` and `repo connect owner/name`.
		- The first pass skipped them for having no origin to compare. That was wrong: gh never uses a host alias, so the url it is about to set is always `git@github.com:owner/name.git` and the identity is knowable before anything is created. Design note revised rather than appended to.
		- Refuses before `gh repo create` and before `git init`, so a mismatch leaves no remote and no repository behind. Verified against the pre-feature build, which created both.
		- An https protocol means git will use a credential helper rather than a key, so there is no second identity and nothing to compare.
		- Deliberately does not rewrite the remote to a matching host alias. Guessing which alias serves an account means inferring the user's ssh setup, and a wrong guess points the repo at the wrong key. `repo connect <full url>` already covers anyone who wants their alias.

	- ✅ PowerShell: gh's account was read from a stale exit status.
		- `gh api user | Select-Object -First 1` stops the native command early, so `$LASTEXITCODE` is left over from whatever ran before - in a plain directory that is the failed repo probe, so the login was discarded and every identity came back unknown.
		- Only showed up once `repo create` started needing the login, since that is the one command that runs outside a repository.
		- Fixed by collecting the output with `@()` before selecting, in all three places that read a native command this way. A regression check runs `repo create` from a plain directory and asserts the account resolves.

- ✅ Code reviews 20260725 and 20260723.
	- Opened: 20260723-190151
	- Closed: 20260725-171015

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

	- ✅ Code Review 20260723 item 39: README typos.
		- Line 82 "devoted to to", line 100 "besome", line 218 "cononical".
		- Done: all three fixed.

	- ✅ Add a PowerShell badge to README.md.
		- Added next to the bash badge in the header block, linking to the PowerShell docs.

#### Done - Features and enhancements

- ✅ macOS builds no longer need a Mac or an SDK.
	- Opened: 20260817-115422
	- Closed: 20260818-181424
	- `darwin/amd64` and `darwin/arm64` cross-compile from this box, so both are in the release matrix. Signing and quarantine on real hardware are a separate question, still open.

- ✅ `.shcl` goes hierarchical via a real module, replacing the hand parse.
	- Opened: 20260826-152000
	- Closed: 20260826-153701
	- The file is read and written through the shcl Go module: one block per account, folders as a list, the old flat layout still read and converted by the first `account set`. A created file carries a key header and the format's footer.

- ✅ Dogfood destinations tidied. The Linux fallback is `~/.local/bin`, the same dir the installer defaults to, and it only applies to the target matching the box doing the build. Dropped a second macOS entry that spelled out a home directory.
	- Opened: 20260826-155615
	- Closed: 20260826-160101

- ✅ `--about` and `--donate`.
	- Opened: 20260826-122906
	- Closed: 20260826-123436
	- `--about` is the copyright block, the description the help screen carries, and a link to the project. `--donate` is the build line, two sentences, and the sponsorship link.
	- Both answer outside a repository, both take a bare word as well as the flag, and neither reads any configuration.
	- Help lists both on the line that already names `--help` and `--version`.

- ✅ A build number, printed next to the version and on every command's output.
	- Opened: 20260826-114339
	- Closed: 20260826-120037
	- Minutes from the start of 2000, Crockford base32, lower case. Five characters until 2063, and no letters that get misread when one is read back over the phone.
	- Taken from the commit's date rather than the clock at build time. A clock-derived number changes on every rebuild, which would mean a published binary could never be rebuilt to its published checksum.
	- Commands print `gitsby <version> build <build>` above their output. Not under `-q`, and never on `raw git`/`raw gh`, which hand their tool's output back untouched. `--version` and the help screen gained the build number on the version line they already had, rather than a second line repeating it.
	- The release cross-builds twice as a result: phase 1 as a compile gate, phase 3 from the tagged commit for the bytes that get uploaded. The release notes name the build number, read out of the built binary so the two cannot disagree.
	- An unstamped build (a hand-run `go build`) reports no build number at all.

- ✅ Port the mutating commands (`update`/`sync`, `br create`/`land`/`prune`, `pr`, `repo`, `account apply`). Four slices, one branch each.
	- Opened: 20260818-090334
	- Closed: 20260818-140234
	- ✅ The mutating frame plus `update`, `sync`, `br prune`. The frame is the shared part: state, plan, confirm, run, state again, "Done." - and the commit/pull/push core the rest compose from. `br prune` now deletes rather than stopping at its plan. Go leg 249/189 -> 285/153.
	- ✅ `br create` / `hotfix` / `switch` / `land`, with the hotfix back-merge and the shipped-code warning. Also the up-front branch-name and dirty-protected-branch refusals, and the `New branch ...:` state line. Go leg 285/153 -> 345/93.
	- ✅ `pr create` / `pr ok`, and `release` with its version resolution and the nothing-new guard. Also the `GitHub (gh)` identity line, which only gh-backed commands print, and the gh-write account comparison behind it. Go leg 345/93 -> 385/53.
	- ✅ `repo clone` / `create` / `connect` / `url`, and `account list` / `apply` - the includeIf writer, the fragment files, and the smaller no-repo headers (clone, connect-from-plain-dir, files-to-publish). With this the whole command surface is ported. Go leg 385/53 -> 438/0.

- ✅ Rename `update` -> `pullcom` and `br land` -> `br merge`, keeping the old spellings as aliases. After slice four.
	- Opened: 20260818-144709
	- Closed: 20260818-165649
	- `sync` keeps its name; only its help line changes, to say it goes both ways.
	- Aliases are permanent - the Go build stays compatible with the 2.1.0 surface. `pullcom` also answers to `update`, `pull`, `pullc`, `pullco`, `pullcomm`, `pullcommit`; `br merge` also answers to `br land`.
	- Why: `update` reads like it updates gitsby itself, and says nothing about direction, where `pullcom` names both halves in the order they run. `merge` is what people reach for before `land`.
	- Go build only. The scripts keep their current spelling and stand as the reference.
	- The old spellings still work, so the demo gif stays correct - regenerate it once the Go build is release quality, not for this.
	- Done: renamed in the parser, the help, the four messages that named a command, and the internal tokens. The offline `sync` refusal now says the pull is the half that gets skipped. Run output is byte-identical to the frozen build under either spelling. The suite's go leg carries the checks for the new names and the aliases; two shared checks that pinned the old wording now take either. Go leg 438/0 -> 455/0.

- ✅ New command: `identity`.
	- Opened: 20260818-144709
	- Closed: 20260818-165649
	- The identity half of `status` on its own - account, ssh key and who it authenticates as, commit author, gh login - without the branch and working-tree state.
	- Same lines, same code as `status`, so the two can't drift. Answers outside a repository too, which is where you ask it before cloning or creating.
	- Read-only, so no confirmation and no plan. No alias; `whoami` and `who` were left alone rather than spent, since every alias is permanent.
	- Superseded 2026-08-21: the command is now `whoami`, with `who` and `identity` as permanent spellings of it. The two names that were held back were held back for this.

- ✅ Sweep the published docs for the renamed commands, and add `identity` to them.
	- Opened: n/a
	- Closed: 20260818-165649
	- Done: README.md command table (`pullcom`, `br merge`, new `identity` row) plus the prose around it, workflows.md, git_notes_and_oneliners.md. A short paragraph says the old spellings are permanent, and the PowerShell paragraph now names the one place the builds differ - the scripts predate both new names.
	- Safe to do now: this all sits on `gover`, which nothing ships from until the Go build releases. The published README is whatever `main` holds.
	- Historical changelog entries keep the names they shipped with; only vNEXT gets the new ones.
	- The `identity` row became `whoami` in the same docs on 2026-08-21; nothing else in the sweep changed.
	- `demo-scenario.toml` deliberately left on the old spellings. The aliases keep it correct, and changing text the scenario prints makes the committed gif stale, which the pipeline compares byte for byte. It rides along with the gif regeneration at release.

- ✅ Per-platform release artifacts with a checksum each.
	- Opened: n/a
	- Closed: 20260818-181424
	- Six targets: linux, windows and macOS, amd64 and arm64 each. Published as `gitsby-<goos>-<goarch>` (`.exe` on Windows) with one `SHA256SUMS` over the set. The list lives in `cicd/config.bash`.
	- Free because the module is pure stdlib with no cgo, so every target cross-builds from one box - macOS included, with no SDK and no Mac.
	- `--arch` becoming real belongs to the installer, which does not exist yet. See the installer item below.

- ✅ Retire the scripted implementations, and make the pipeline Go-specific.
	- Opened: 20260818-165649
	- Closed: 20260818-181424
	- `legacy/` holds the six frozen deliverables and nothing else: both builds and the four installers of that era, plus a README saying what they are. No copy of the pipeline - the v2.1.0 tag is a better hotfix tree than any copy could be, since it holds the scripts, the pipeline that built them and the installers all in their original places, unmodified.
	- A hotfix therefore starts at `git switch -c hotfix/2.1.1 v2.1.0`, ships from that branch with its own tag, and is never merged back to `main` - those paths do not exist there.
	- `cicd-win.ps1` deleted. One engine, everywhere, which also ends the hand-synced lint globs.
	- `parity.bash` kept and repointed, rather than dropped as originally planned. Comparing this build against the frozen one is exactly the backwards-compatibility question worth asking, and the harness for it already existed. It is stage 4 of the pipeline now, and it also checks that `update` and `br land` still route where they always did.
	- The suite runs one leg. The 58 checks that were never about an implementation - the installers, the frozen builds' own platform gates, the source pins on this pipeline's files - stayed, repointed at `legacy/`; they had only ever ridden the Bash leg because that was the leg that always ran. Counted before and after so none went missing: 530 pass, against 513 + 455 across the old three legs.
	- Pipeline is seven stages now: lint, build + test, fuzz, backwards compatibility, dogfood, demo gif, publish. The Go toolchain is required rather than probed.

- ✅ Installer for the Go build, and the README install section that documents it.
	- Opened: 20260819-095014
	- Closed: 20260819-103518
	- `install.bash` and `install.ps1` are back at the repo root, so the two documented one-liners resolve again once this reaches `main`. The `install-dev.*` pair was dropped rather than ported - a Go checkout needs only Go.
	- Both pick the binary by `<goos>-<goarch>`, which is what makes `--arch` real. `--ref` became `--tag`, since it names a published release rather than any git ref; both old spellings still bind.
	- The PowerShell one was kept. It is the only shell every Windows machine already has, and the only thing that puts the install directory on PATH. PSScriptAnalyzer came back into the lint stage with it, having been dropped when the scripted build was frozen.
	- `--release dev` is gone. It installed the tip of a branch, which a compiled product has nothing to offer; typing it says so and names the two routes that exist.
	- Every route is a release asset now, so every route is verified - the unverified branch of the plan no longer exists. `SHA256SUMS` is fetched before the plan is printed, because it is what says whether this platform has a binary at all, and it names the ones that do when this one doesn't.
	- FreeBSD joined the release matrix rather than being documented as an exception; it cross-builds for free. OpenBSD and NetBSD still fall through to the build-from-source message.
	- README: badges, "Compatibility" and "Install" rewritten for one binary and no runtime. The stale paragraph about the PowerShell build's option spellings is gone, replaced by a short note for anyone coming from 2.x.
	- Suite 582 -> 613. The new checks stop at the network: parsing, every refusal, the Windows hand-off, and pins on what a live run would reach. Verified end to end by hand against a fake release served locally - both installers, plus the tampered, intercepted, missing-release and wrong-architecture paths.
	- Left stale on purpose: design.md "Automating a release" still describes writing a version into two builds. That predates the Go round, not this one - filed below.

- ✅ design.md "Automating a release" still described the two-script era: a version written into both builds, footers in `bin/gitsby` and `bin/gitsby.ps1`, and phase 1 comparing two version strings.
	- Opened: n/a
	- Closed: 20260819-103518
	- Already current when this was checked. The section describes the three phases as they run, and says outright that the version lives in the tag and nowhere else - naming the two-build design as what it replaced, and why.

- ✅ Regenerate the demo gif. Stale twice over: the renamed commands moved text the scenario prints, and the pipeline now renders it from the Go build rather than the dogfooded script.
	- Opened: n/a
	- Closed: 20260821-181037
	- Done, and it needed the fixture fixed first: the real `gh` was answering as the rendering machine's own login, and the fake tokens' permissions put a warning on every scene. Both were on camera.

- ✅ Dogfood location change.
	- Opened: n/a
	- Closed: 20260821-181037
	- Three targets built and placed every run: linux to `util/linux/bin`, windows to `util/mswin/cli/by-self/win64`, macOS to `util/macos/bin`. Windows and macOS each carry a second spelling of the same share, for when the run is happening on that platform instead.
	- The old bash build is still sitting in `util/linux/bash` and nothing removes it. Worth clearing by hand.

- ✅ Release ordering: the build matrix runs before the release is cut, so a failed build never leaves a half-published release.
	- Opened: n/a
	- Closed: 20260821-181037
	- All six binaries are built in phase 1, alongside the pipeline gate. A target that stops compiling fails where nothing has been changed; found in phase 3 it would have left a pushed tag with no release behind it.

- ✅ The accounts file now lives where each platform keeps one.
	- Opened: 20260821-125351
	- Closed: 20260821-130130
	- One search order was used everywhere - `$XDG_CONFIG_HOME`, then `~/.config`, then `%APPDATA%` - which is the Linux convention applied to Windows and macOS as well.
	- Windows now reads `%APPDATA%\gitsby\config.shcl` and nothing else, macOS `~/Library/Application Support/gitsby/config.shcl` and nothing else. Linux and FreeBSD are unchanged.
	- Each platform's variable is read on that platform alone: `XDG_CONFIG_HOME` on Linux and the BSDs, `APPDATA` on Windows. Both used to be read everywhere, which let an MSYS session answer for a Windows run, and put a name Wine or Samba can leave set on a Linux run's credential search path.
	- `~/.config` is a Linux spelling too, so neither Windows nor macOS reads it any more - only where the native location can't be worked out at all. Users upgrading on either have a one-line move, called out in the changelog.
	- One ordered list now answers both "where do we look" and "where does a new file go", instead of three copies of the order in three files.

- ✅ `identity` is now `whoami`, and its help line says what it shows.
	- Opened: 20260821-104756
	- Closed: 20260821-105738
	- The command is a question, and the old name was a noun. Every shell already has a `whoami` that means this.
	- `who` and `identity` both still work, permanently. Those were the two names held back when the command was added.
	- The help line was "Who commands here act as: ..." - a sentence fragment where every other line starts with a verb. Now "Show account, ssh key, commit author, git host login."
	- The block it prints is still the identity block; only the command changed.

- ✅ The account diagnostic answers its own questions, and offers the fix as a command.
	- Opened: 20260820-174958
	- Closed: 20260820-182956
	- Read on a real Gitea repo, the block raised more questions than it settled: `'work-gitea' - no token applied` never said what token, applied to what, or what that string even was, and "that account doesn't say which forge it is for" used a word for people who already knew the answer.
	- The headline now names the token and the host it wasn't used for. `From:` says what kind of thing the name is and which of the several possible sources produced it, rather than repeating the name.
	- "Forge" is gone from the whole tool. The status line is `Git host`, and the notes say "git host" or name the host outright.
	- The notes read as sentences - capitalized, `SSH` spelled one way throughout.
	- `Kept:` names only the lines actually on screen. It said "the SSH and Author lines" whichever half applied, sending readers after an SSH line that was never printed.
	- `Fix:` names one command instead of a config line to copy: `gitsby account set <account> <key> <value>`, new, which makes the edit itself.
	- It stops short of making the edit unasked, and says why: all it knows is that the file never named a host, which is not the same as knowing the account belongs to this one - and guessing wrong hands one host's token to another.

- ✅ `account set` writes one key of one account into the accounts file.
	- Opened: 20260820-174958
	- Closed: 20260820-182956
	- Shows the edit and asks first; `-q` proceeds. Replaces that key's line, adds one, or creates the file.
	- Refuses a key nothing reads, and a value the loader would drop - a line written past either lands in the file and is ignored on every load, so the file says one thing and every command does another.
	- Everything else in the file comes back byte for byte: comments, spacing, a Windows byte-order mark, CRLF endings.
	- A key already present twice is refused rather than guessed at. `path` is repeatable by design.

- ✅ Other Git hosts are first-class; `gh` is reached for only when the remote is actually GitHub's.
	- Opened: 20260819-193000
	- Closed: 20260819-195612
	- Gitsby began as a GitHub program and asked `gh` for things Git could answer on its own, so a Gitea remote got GitHub errors about a repo `gh` was never looking at.
	- Where `origin` points is now established first, aliases resolved. `gh` serves github.com and `GH_HOST`; `tea` serves Gitea and Forgejo, under `tea-cli` as well - Debian renames it.
	- Everything answerable with Git alone works on any host with no forge client installed. `repo url` was the clearest case: it only rewrites text, and refused everywhere but github.com purely because of the URL parser.
	- Accounts gained `host` and `user`, so a token is applied only where it can be used and a non-GitHub token never goes out as `GH_TOKEN`.
	- A remote whose host can't be named still falls through to `gh`, deliberately - "couldn't tell" is not "definitely not a forge".
	- `repo create` and `repo connect owner/name` stay GitHub-only, being about GitHub specifically.
	- The tea path is written against tea's real command surface but has not been exercised against a live Gitea instance; the suite drives it through a stub.
	- Defect found and fixed before dogfooding: giving the credential helper a username interpolated the login into a string Git hands to a shell, so a `;`, a backtick or a `$()` in `ghAccount`/`GITSBY_ACCOUNT` ran as a command the moment an HTTPS push needed credentials. Both the token and the username now come from the environment. Fuzz gained four vectors driven through a real `git credential fill`; three of four fired on the pre-fix build.
	- Follow-up done: the identity gate covers non-GitHub hosts too. A tea write is compared against the ssh key like a gh write, and the push-side check reads the account's login on the host rather than `ghAccount`. Both were verified against the pre-fix build - a mismatched `pr create` went through and pushed.

Go port, round one. Rationale and route: `design_docs/20260813_golang-port.md`. Work top to bottom; everything happens on branches off `gover`, nothing touches the scripted implementations yet.

- ✅ Go scaffolding.
	- Opened: 20260817-113400
	- Closed: 20260817-115833
	- Module, `src-go/` tree, builds from the Linux cicd engine.
	- Version is a build-time value, not a line in the source.
	- Done: stub binary that owns only `version`; test stage builds it fresh each run, dev builds carry the git-describe version.

- ✅ Third suite leg in test.bash for the Go binary.
	- Opened: 20260817-115833
	- Closed: 20260817-170407
	- Mirrors the pwsh leg: a shim path, same fixture, same checks.
	- Skipped when no binary exists; failures don't fail cicd until the leg is expected to pass everything. Pass counts print either way so progress is visible per run.
	- Done: leg prints its own counts and stays out of the totals and the exit code. First run 162/279 - the passing side is mostly refusals a stub satisfies, so the failed count is the real distance.

- ✅ Go tooling in the lint stage.
	- Opened: 20260817-170407
	- Closed: 20260817-201711
	- gofmt, go vet, staticcheck. Shellcheck and PSScriptAnalyzer keep covering the pipeline and installers.
	- Done: stage 1 runs gofmt (list mode) and go vet as gates, staticcheck when installed. Keyed off `src-go/` existing, no globs, so nothing to mirror in the Windows settings yet. Verified the gate fails a misformatted file by name.

- ✅ Port the shared layer first.
	- Opened: 20260817-170407
	- Closed: 20260817-201711
	- Argument parsing, output helpers, and the process runner. Commands run from an argument list, no shell between.
	- Config read (`.shcl` stays flat and hand-parsed for now) and account resolution, same order and same env-only application.
	- Done: one file per concern in `src-go/`. `raw git`/`raw gh` shipped with it as the layer's first consumer, proving the whole chain - prescan, config, resolution, env-only application, hand-over - against the real suite. Verified side by side with the bash build: same messages, same credential helper, same commit identity. Leg moved 162/279 -> 182/259; the one new-code failure is the `--` check handing the go leg the PowerShell spelling, which is the known leg-name sweep in the command-slice item.

- ✅ Port a first command slice: `version`, `help`, `status`, `br list`.
	- Opened: 20260817-201711
	- Closed: 20260818-055519
	- Read-only commands, so the suite leg starts passing real checks with no mutation risk.
	- Note: any command named in an error message or help must be one the parser accepts.
	- Done: help/version/status/br list, plus the full command-sort validation so every known command refuses bad arguments with the script's own message before saying it isn't built yet. Status carries the whole identity block (account, config-ignored, SSH probe, author) and the capped change/incoming lists. Verified byte-identical against the bash build across status, br list, help, and every refusal path. test.bash leg-name branches now split pwsh from everyone else; the leg moved 182/259 -> 236/202, and every remaining failure in this area is prep leaning on a command from the next slice.

- ✅ Port the remaining read paths: `br prune` preview, `pr list`, default-branch resolution.
	- Opened: 20260818-055519
	- Closed: 20260818-090334
	- Done: `br prune` runs its whole survey and shows the real plan (including the empty-plan answers and the keep reasons); only the deleting half still says it isn't built. Bare `pr` lists and `pr <n>` views with diff; create/ok wait for the writers, and pr's argument shapes refuse with the script's messages. Default-branch resolution itself landed with the previous slice - what this adds is the refusal gate for commands that need a confirmable branch. Config-file errors now match the scripts' one-trailing-blank shape (they throw inside a command substitution there). All verified byte-identical against the bash build; the leg moved 236/202 -> 249/189, and every remaining failure in these areas needs the mutating half.

- ✅ Accounts, parity and release automation, 20260812.
	- Opened: 20260812-150636
	- Closed: 20260812-181826

	- ✅ On Windows a folder rule spelled the way this shell spells paths resolved in one build and not the other.
		- Cause: the PowerShell build folded the drive letter *after* asking the filesystem, and .NET reads a `/c/...` path against the current drive - which never exists. So nothing resolved, and short names and junctions were left as written.
		- Fixed: fold the drive letter first. All four spellings now resolve identically in both builds, short names included.
		- Known limit, and now visible rather than silent: an MSYS *mount* path such as `/tmp/...` has no meaning to the native build and never can, since only the shell knows its own mount table. `account` marks any folder rule that resolves to no directory, which shows that up along with ordinary typos.

	- ✅ The identity lines reported the account that was resolved, not the one that was applied.
		- Fixed: an account with no token available now says so on the line. It is still resolved, but gh goes on using its own account - and the block whose whole job is answering "who does this go out as" was naming the wrong one.
		- Only for a configured or explicitly asked-for account; one inferred from the remote's owner is not a claim that we can act as it.

	- ✅ `sync` compared no identities before it pushed.
		- Fixed: the commands that push with git, rather than writing through gh, now ask whether the folder's account is the one origin will actually authenticate as. A warning interactively, a refusal unattended, and `--any-identity` says it was intended.
		- The https half is covered by the item above: gitsby supplies the token itself, so the push goes out as the resolved account or says it could not.

	- ✅ `account apply` wrote identity and key but nothing about credentials.
		- Fixed: the fragment now sets `credential.https://github.com.username`, so a credential manager looks up that account's entry rather than any entry for the host.

	- ✅ Added a parity suite: `cicd/parity.bash`, wired into the test stage of both engines.
		- It asks whether the two builds *answer the same* for one input, where `test.bash` asks whether each behaves correctly. A behavioral check written per implementation passes on both while they quietly disagree - which is what every port defect that reached users actually was.
		- Covers path spellings, option forms, string case and file encoding: 23 comparisons.
		- It earned its place while being written, finding two real divergences: the `/tmp` mount limitation above, and PowerShell answering an unknown option with the entire help text - and under `-q` with nothing at all but an exit code - where Bash named the option.

	- ✅ `br prune` asked about one branch at a time.
		- Fixed: `git for-each-ref --merged` answers for every branch in one call per target ref, instead of two ancestry questions per branch. The delete-time re-check stays per branch, deliberately: that one is the safety net, not the survey.
		- Verified on a 33-branch repo - the same 30 merged branches pruned, the same 3 unmerged kept.

	- ✅ Fully automated releases, end to end: `cicd/release.bash`, to the three-phase shape in `design.md`.
		- Phase 1 verifies and changes nothing, phase 2 is the only one that pushes, and phase 3 publishes and then proves the result the way a user meets it - by running the documented installer against the published release.
		- Both guards exist because the thing they check has already gone wrong: the two builds' version strings drifting apart, and the history footers going a whole release with no entry.
		- `--dry-run` says what each phase would do and changes nothing. Writing it that way immediately caught a bug in the script itself: a loose version match picked a version-shaped string out of a comment, which phase 2 would then have rewritten instead of the real declaration.

- ✅ Multiple GitHub accounts, chosen by which folder you are in, for both git and gh.
	- Opened: n/a
	- Closed: 20260808-105027
	- People with two accounts already keep a folder per account. A config file maps a folder tree to an account, and everything under it acts as that account - gh, git's credentials, the ssh key, the commit identity.
	- The platform's own config location - `%APPDATA%` on Windows, `~/Library/Application Support` on macOS, `$XDG_CONFIG_HOME` or `~/.config` elsewhere - flat `key = value` lines, overridable with `--config FILE` or `GITSBY_CONFIG`. With no config file at all, nothing changes.
	- The ssh-key-and-host-alias trick is no longer needed: over https, git authenticates with the account's own token. Keys stay fully supported for anyone who wants them.
	- `repo url [https|ssh]` converts an existing remote, which is the only thing between an ssh repo and a token.
	- `account` explains what is configured and which account applies here. `account apply` writes the same rules into the global git config, so plain `git` matches.
	- `raw git` and `raw gh` run either tool as the folder's account, verbatim, so scripts can use gitsby as a drop-in prefix.

- ✅ A Windows-native CI/CD pipeline, so the whole thing can be run from Windows and not only from Linux.
	- Opened: n/a
	- Closed: 20260808-095515
	- `cicd/cicd-win.ps1` runs the same six stages as `cicd/cicd.bash`, with the same options under PowerShell spelling and the same output shape, so the two read side by side.
	- The publish stage is a native port of `n8git_backup-and-publish`, minus the rar version archive - skipped by request, since git carries the history.
	- The demo gif is compared, never regenerated. Reproducing it byte for byte depends on fontconfig, the installed fonts and the pinned optimizer, none of which Windows matches - a render here would land a file the next Linux run flips straight back.
	- Stages whose tool is missing warn and skip, as they already do on Linux. On a stock Windows box that is markdownlint and the demo gif.
	- Settings are carried in the script rather than read from `config.bash`; only the dogfood destinations genuinely differ.

- ✅ Run the PowerShell leg of both suites on Windows, not just on Linux.
	- Opened: n/a
	- Closed: 20260808-095515
	- It had never run there, and it found a real defect the Linux-only habit had been hiding for as long as the identity work existed.
	- Two things blocked it. PowerShell finds a shebang stub on PATH but starts nothing and reads the silence as empty output, so every stub gained a `.cmd` sibling that hands the body back to bash. And the confirmation checks needed `setsid`, which Windows has none of - unnecessary there, since PowerShell reads redirected stdin and never reaches for a terminal.
	- Fuzz keeps a plain stub and skips four checks on that leg instead. Its arguments are hostile on purpose, and `cmd.exe` re-parses an unquoted `&` or `>`: a vector would partly run for real, and be reported as an injection gitsby never had. A skip that says so beats a pass that isn't one.
	- The ssh probe now starts the ssh PowerShell itself resolves rather than letting `ProcessStartInfo` search PATH its own way - which on Windows reached the real `ssh.exe` and would have gone to github.com, against the suite's promise never to touch the network.

- ✅ Say what a branch is branched from, wherever a branch is named.
	- Opened: 20260731-080041
	- Closed: 20260731-083030
	- Reported against `br hotfix` run from `dev`: the current-branch line read `dev` while the plan directly under it checked out `main`. Both were correct and nothing connected them.
	- Branch names now render as `base :: branch` - `dev :: feature/retries`, `main :: hotfix/readme`. `main`, `master` and `dev` stay bare; they are not off anything you would work from.
	- `br create` and `br hotfix` gained a `New branch` line naming what they will make and its base, so the answer is on screen before the plan is read. Pre-flight only - after the run the branch exists and the question is gone.
	- The repo's default branch moved to its own line instead of riding along in parentheses, and `br list` now states it too.
	- The base shown is where the branch lands. Git records no fork point, and for anything gitsby made the two are the same by construction.

- ✅ Show the file list before first publication (`repo create`, `repo connect` from a plain directory).
	- Opened: n/a
	- Closed: 20260728-073221
	- Every other command shows what it is about to touch; the one that hands a whole directory over for the first time did not.
	- The list is what `git add --all` will really add, asked through a throwaway git dir outside the work tree - so `.gitignore` and `core.excludesFile` are honored, and answering "n" leaves the directory exactly as it was found.

- ✅ `br hotfix <name>`: a branch that targets the default branch instead of `dev`, for corrections to published material.
	- Opened: n/a
	- Closed: 20260727-000406
	- The branching model is written up in `design.md`; this is the command that carries it.
	- Branches off the default branch, pushed as `hotfix/<name>`. The prefix is the marker, so it survives a clone and shows in a branch listing. A name given with the prefix already on it is accepted rather than doubled.
	- `br land`, `pr create`, and `pr ok` recognize a `hotfix/` branch and target the default branch, then merge it back into `dev`. `br create` still comes off `dev`, so feature work is untouched.
	- A back-merge that conflicts aborts and leaves `dev` alone, reporting that the hotfix landed and naming the two commands to finish by hand. Conflict surgery stays raw-git territory.
	- Landing warns when the branch touched `bin/`: the default branch would then carry code no tag contains, so the latest release's downloads no longer match it.
	- Implemented as `fBranchTarget` / `Get-BranchTarget` alongside the existing merge target, rather than by changing `fMergeTarget` - "where new branches come from" and "where this branch lands" are different questions, and only the second one varies.
	- 30 new checks across both implementations. Verified the pre-feature build rejects `br hotfix` outright.

- ✅ Release-prep sweep over the docs and the built-in help.
	- Opened: 20260726-125534
	- Closed: 20260726-130242
	- The help still described `sync` as commit-then-pull. That order changed when the bare `pull` command was dropped, and this line was missed. The README already had it right.
	- A regression check pins the wording, so the same drift can't come back quietly.
	- Also two stale references in the project notes: a command name that was renamed, and a description of argument parsing from before the noun grouping.

- ✅ `br prune`: delete branches already merged into the merge target, local + remote.
	- Opened: 20260726-110940
	- Closed: 20260726-112615
	- Nothing cleaned up after a PR merged from the web UI or another machine, or after an abandoned branch. `br land` and `pr ok` only ever delete the one branch they just merged.
	- Kept safe by what the tool already enforces: every landing is a real merge commit, so ancestry is an exact test. Unmerged branches are listed and left alone, and there is no `--force`.
	- The remote copy is only deleted once origin's own merge target contains it, so an unpushed landing can't strand work.
	- Verified the safety gates discriminate: a version with the ancestry check removed deletes an unmerged branch, and one without the origin-side check deletes origin's only ref to unpushed work.
	- Deletes with `git branch -D` behind our own check. Deferring to `git branch -d` was tried first and was wrong both ways: it warns about HEAD on every branch when pruning from anywhere but the target, and it flatly refuses a merged branch that was never pushed, so the plan promised a deletion that silently didn't happen.
	- Closes with a count (`Pruned 3 local, 3 on origin`) and names what it kept, so a wall of git output still ends in a plain answer.

- ✅ Drop the bare `commit` and `pull` commands - both work around the opinionated workflow.
	- Opened: 20260726-101513
	- Closed: 20260726-102919
	- `commit` alone leaves work committed but unshared. `pull` alone was the only place the tool took upstream changes without parking your own, unlike every other command.
	- Reversible in one direction only: dropping now is free, adding back later breaks nobody, removing later would.

- ✅ `update`/`sync` pull before they commit (bug this exposed, present on dev).
	- Opened: 20260726-101513
	- Closed: 20260726-102919
	- Committing first guaranteed divergence whenever the remote had moved, so the ff-only pull refused - in the most ordinary case there is. `pull` had been the accidental workaround.
	- Verified against the pre-fix build: it fails, the fixed one lands the work on top and keeps history linear.

- ✅ An unreachable remote warns and skips the pull instead of failing; `--no-fetch` means offline and skips the pull too.
	- Opened: n/a
	- Closed: 20260726-102919
	- Needed because `update` is now the only way to commit; a genuine non-fast-forward still fails hard.

- ✅ Group the infrequent commands under nouns: `repo clone|create|connect`, `br list|create|switch|land`, `pr create|<n>|ok <n>`.
	- Opened: 20260726-095211
	- Closed: 20260726-100901
	- Daily verbs stay one word. The extra word only lands where you type it rarely, and it buys a discoverable set instead of a flat list of abbreviations.
	- One verb across all three nouns (`create`, never `new` in some places). `new` and `go` still work but aren't published.
	- Landed before v2.0.0 on purpose: every name being changed was unreleased, so it cost nothing now and would have cost a permanent alias later.

- ✅ Split the old `connect` into `repo create` and `repo connect`.
	- Opened: 20260726-095211
	- Closed: 20260726-100901
	- Creating a remote is the one irreversible, outward-facing step, so it gets its own verb instead of happening as a side effect.
	- Each refuses the other's case and names it, so a wrong guess costs one line of output.

- ✅ Drop every pre-2.0 command alias (`scommit`, `spull`, `scompul`, `saveup`, `spush`, `mkbranch`, `chbranch`, `mtm`, `list`).
	- Opened: 20260726-095211
	- Closed: 20260726-100901
	- v2 is a clean break under a new tool name, and not all of the old commands worked. The suite now asserts they're rejected, so none creeps back.

- ✅ `pr new [title]` opens a pull request, so the whole PR round trip lives in gitsby instead of half in `gh`.
	- Opened: n/a
	- Closed: 20260726-092038
	- Pushes the branch first - GitHub can only diff what the remote has.
	- Targets `dev` when the repo has one, else the default branch. Refuses from that branch, since there is nothing to propose.
	- No title given: the last commit subject, which is already a description of the work. The preview shows it before anything happens.
	- An already-open PR for the branch reports its number instead of letting `gh` error.

- ✅ `pr ok <n>` refuses while the current branch has uncommitted changes or unpushed commits.
	- Opened: n/a
	- Closed: 20260726-092038
	- Merging deletes the branch local and remote, so work that never reached origin was outside both the PR and the merge.
	- Every other mutating command already parked work first; this was the one that did not.

- ✅ The installers' default "latest release" lookup skips anything flagged as a pre-release on GitHub.
	- Opened: n/a
	- Closed: 20260726-082146
	- GitHub's `releases/latest` returns the newest full release, so a pre-release-only repo resolves to the last full one - for this repo, the 2022 release.
	- Decided: publish releases as full releases rather than adding a `--pre` flag. The semver suffix still marks a candidate for anyone reading the tag, and the one-liner installs keep working with no extra arguments.
	- `--ref`/`-Ref` remains the way to install a specific tag or branch, and is already documented.

- ✅ CICD process (full spec in private notes):
	- Opened: 20260724-142509
	- Closed: 20260726-082146

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
		- Follow-up: cicd now runs the render through `gifsicle -O3` when it is installed, before the compare, so the committed file is the optimized one (`DEMOGIF_OPT_CMD` in config.bash; silently skipped when absent). Worth about 9% - 7.3 -> 6.6 MiB. Less than it sounds like it should be: the renderer already crops each frame to what changed, so most of the win was banked, and the lossy modes buy almost nothing on a 35-color text demo.

- ✅ New commands for getting connected: `clone` (get an existing repo) and `connect` (publish work that only exists locally to a new or empty remote).
	- Opened: 20260724-133000
	- Closed: 20260724-141714
	- `clone <url> [dir]`: derives the dir from the URL, checks out `dev` when the repo has one, re-run is a no-op.
	- `connect [target]`: init if needed, commit, push. URL to an existing empty remote, or `owner/name` creates the GitHub repo via gh (`--public`/`--private`). Refuses remotes with history and won't change an existing origin.
	- Done: both implementations, previewed + confirmed like the rest; tests 207 -> 241.
	- Follow-up: logically validated (no bugs) and exhaustively tested. Closed the "gh paths untested offline" gap with a hermetic fake gh (create / add https+ssh / refuse-nonempty), plus clone edges (no-dev, pre-existing empty dir, different-url refuse) and connect edges (empty inited repo, matching-url re-connect). Tests 241 -> 269, both implementations.

- ✅ One-liner installers for Bash and PowerShell: download the release, verify the checksum, install the script. Idempotent, and they state the plan and ask before touching anything. Documented in README under "Installation", including a "Direct" subsection with the commands and the install locations.
	- Opened: n/a
	- Closed: 20260731-141354

	- Done: `install.bash` and `install.ps1` cover it. Checksum verification against a published `SHA256SUMS` landed with code review item 19, and the README "Direct" subsection lists both the commands and the paths each installer uses.

	- Note on the spec's option names: `--arch` doesn't apply, since gitsby is a script rather than a compiled binary. `--release dev|stable` is spelled `--ref`, and `--target user|system` is spelled `--system` (user is the default).

	- Note on install paths: gitsby is a single file, so it goes straight to `~/.local/bin` or `/usr/local/bin` rather than into a program directory with a symlink.

- ✅ Rename `saveup` to `update`.
	- Opened: 20260723-140731
	- Closed: 20260723-141405
	- Done in both implementations; `saveup` stays as a hidden alias like the other old names. Docs and changelog swept.

- ✅ Script output starts and ends with a blank line (breathing room between prompt text).
	- Opened: n/a
	- Closed: 20260723-141405
	- Trailing blanks already existed on every exit path; added the leading one (both implementations). Error paths were already blank-wrapped.

- ✅ After `release` merges dev to main, bring dev up to include the release merge and tag.
	- Opened: n/a
	- Closed: 20260723-141405
	- Done via `git merge --ff-only main` on dev (then push), not `git branch -f dev main`: same result normally, but if dev gained commits mid-release it skips with a warning instead of discarding work. Previews updated; tests cover it.

- ✅ 'git_notes_and_oneliners.md': Move the current commands under a "Bash" section, and add a "PowerShell" section below it, with pwsh v7 parity versions of the same one-liners.
	- Opened: 20260723-133000
	- Closed: 20260723-135833
	- Two mirrored sections, same task headings in the same order, so the two are easy to compare side by side.
	- The PowerShell section opens with the three gotchas that bite when translating from Bash: `&&`/`||` need pwsh 7, `@{u}` has to be quoted, and staged-change tests read `$LASTEXITCODE`.
	- Every pwsh one-liner was run against throwaway repos, not just eyeballed. Two spots deviate on purpose: no `less` (git pages its own diff), and `Remove-Item` deletes outright since there is no cross-platform `trash`.
	- Also swapped the stale sister-tool reference in the Bash "push local changes" one-liner for `gitsby update`.

- ✅ All potentially destructive or conflict-producing commands - or anything that will reveal a user identity on the remote - should:
	- Opened: n/a
	- Closed: 20260723-134733
	- Show what's going to change (including a list of changed files, piped through an internal equivalent of `... | less -FX` if necessary)
	- git status without line-breaks, and SSH connection info. And a prompt to continue. All with standard 1 blank line where appropriate.
	- Every mutating command already previewed its plan and prompted; this added the identity and change detail. `status` shows the same block.
	- SSH line resolves the remote URL through `ssh -G`, so a `~/.ssh/config` host alias shows the real host and key behind it - the point being to catch acting as the wrong account before you push. (It later grew the account itself, which is the part that actually answers that; see the bug above.) Author line shows what git will actually stamp on the commit.
	- Changes list one file per line (short form), truncated to the terminal width and capped at 25 with an "and N more" tail - the `less -FX` idea without depending on a pager. Incoming section lists what a pull would change, and the branch line carries ahead/behind.

- ✅ Better command names; dev-aware merging; PR and release commands (both implementations).
	- Opened: 20260722-200007
	- Closed: 20260722-201054
	- Renames: scompul->saveup, spush->sync, scommit->commit, spull->pull, mkbranch->newbr, chbranch->gobr, list->listbr, mtm->land. Old names still work as hidden aliases.
	- newbr/gobr/land now branch off / land on dev when the repo has one, else main/master. land refuses to run from the default branch.
	- New: pr (bare = list, n = view + diff, ok n = approve + merge, via gh), release (merge dev into main --no-ff, tag, push; no version = patch bump on the latest v* tag).

- ✅ PowerShell port of gitsby (style guide already covers pwsh; dogfood pwsh leg activates when it lands).
	- Opened: 20260722-182703
	- Closed: 20260722-183557
	- `bin/gitsby.ps1`: same commands, checks, and flow as the bash version. Regression suite now runs once per implementation (78 checks total); PSScriptAnalyzer joined the lint stage (gates all three .ps1 files); dogfood pwsh leg live. Not in a release yet - README says to use `-Ref dev` until one is cut.

- ✅ Create a release-install script per platform (`bash` and \[`pwsh` or `cmd`\]), runnable via a single `curl`/`wget` (etc.) and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort. Update README.md with one-liner for both local and system-level installs.
	- Opened: n/a
	- Closed: 20260722-181311
	- `install.bash` + `install.ps1` at repo root; plan-then-confirm, `--system`/`-y`/`--ref`; README Installation one-liners filled in (user + system, curl and wget). Resolves the latest release tag, prefers a release asset, falls back to the tagged tree. The 2022-era releases predate the `bin/` layout so the release path activates for real once a v2 release is cut (`--ref main`/`--ref dev` works today); the pwsh installer says the port hasn't shipped and points at the bash one until then.

	- ✅ Do the same thing for a dev-branch install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort. Update README.md with one-liner for both local and system-level installs.
		- `install-dev.bash` + `install-dev.ps1`: clone, check out `dev`, check tooling (offers package-manager install where one is found), verify, print next steps. Documented in README "How to develop" + contributing.md "Your First Code Contribution". Bash installers run on macOS stock bash 3.2.

- ✅ Get original commands and options working. At some point some just kind of broke (pre-git), and were never fixed.
	- Opened: n/a
	- Closed: 20260722-165821
	- All commands work and are regression-tested; the commit/save/sync/land family takes -m or a positional message, newbr/gobr validate their branch argument.

- ✅ Integrate these rules and ideals: `reference/git.txt` (in this repo), including:
	- Opened: n/a
	- Closed: 20260722-165821
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
	- Opened: n/a
	- Closed: 20260722-165821
	- Every command verifies state first and is idempotent: stash only if dirty (pop only what was pushed), pull only with an upstream, push only if ahead, commit only if changes; main/master detected from origin HEAD, not hardcoded. All covered by the regression tests.

	- Is done safely. E.g. before stashing, verify safely in a robust way that makes no assumptions, that there is anything to pull. `n8git_backup-and-publish` has examples.

	- Never make assumptions about the local and/or repo state. Verify first for every command, whatever is relevant for the command.

	- Everything must be idempotent.

- ✅ Refactor the bash script:
	- Opened: n/a
	- Closed: 20260722-165821
	- Rewritten 2142 -> ~620 lines on the current template generation (same one as `n8git_backup-and-publish`): strict mode, trap suite, arg parser, minified header trio.

	- ✅ Use newer, easier-to-maintain Bash template/boilerplate/common functions. (E.g. from sister project silkterm.) But even those examples need to be cleaner (don't change anything outside of repo.)

	- ✅ Modernize function and variable naming convention. Be descriptive with names, but not too long. Use of one-letter variables in small loop structures is OK.

	- ✅ Remove dead code.
		- Dropped the unused ~1400-line generic library (ping, symlink, editor pickers, sudo plumbing, glob-permutation engine, platform detection).

	- ✅ Refactor to maximize usefulness of idiomatic Bash 5 features.
		- Argument arrays instead of eval (which also retired the curly-quote message mangling), `[[ -v ]]`, parameter transforms, arithmetic conditionals.

- ✅ Work on dev branch. Push releases to main.
	- Opened: n/a
	- Closed: 20260722-165821

	- ✅ `dev` branch created from `main` and pushed; feature branches now merge to `dev`, `main` is release-only.

- ✅ Create PRs rather than pushing directly (for this project).
	- Opened: n/a
	- Closed: 20260722-165821
	- Feature branches now go up as PRs to `dev` and land via merge commit; direct local merges retired.

- ✅ Delete stale branch from 2020.
	- Opened: n/a
	- Closed: 20260722-165821
	- `20201003-074416_jc_rewrite-in-golang` (abandoned golang rewrite) deleted from origin.

### Future and/or deferred

Waiting on hardware, an upstream module, or a decision.

- ✋ Rework the fuzz suite. Much of what it proves becomes structurally impossible with no shell in the path; figure out what remains meaningful.
	- Opened: 20260817-115422

- ✋ macOS signing and quarantine on real ARM hardware: does a terminal download need either?
	- Opened: 20260817-115422
	- All that is left of the old macOS item. The build half is settled and filed under done.

- ✋ GitHub Actions and platform packaging (.deb/.rpm/.exe installer), deferred to the port by decision.
	- Opened: 20260817-115422
	- The port is underway now, so this is decidable rather than deferred. Two calls: whether a bare workflow (vet, test, build on push and PR) is worth the dependency on a hosted service, and whether a release packager earns its place by bringing the Linux packages with it.
	- Against the packager: the release already proves itself by downloading, checksumming and running the asset, which is more than it would do. For it: the packages come free.

### Canceled

None.
