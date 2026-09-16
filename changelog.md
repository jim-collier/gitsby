# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
## TEMPLATE_vNEXT - DATE

### Notes

### Added

### Changed

### Removed

### Other work

-->

## vNEXT

### Notes

- The Bash and PowerShell builds are frozen at v2.1.0 and will not gain features. Development continues in a single Go build, which keeps every command that works today - where a command is renamed, the old name keeps working. The two scripts stay in the repository as a reference, and would be reopened only for a production fix.

### Added

- The installers install the binary this machine needs, chosen by platform and architecture, and check it against the release's published `SHA256SUMS` before it lands. There is no unverified route left: where the checksum can't be fetched or can't be computed, the install stops instead of carrying on. Where a release publishes nothing for a platform, it says which ones it did publish and how to build the rest.

- FreeBSD joins the published platforms, amd64 and arm64 both, alongside Linux, Windows and macOS.

- `whoami` shows who commands in this folder act as - the account, the ssh key and who it authenticates as, the commit author, and the git host login - without the branch and working-tree state `status` prints around it. It answers outside a repository too, which is where the question comes up before a `repo clone` or `repo create`. `who` and `identity` are accepted spellings of it.

- Other Git hosts are first-class. Gitsby looks at where `origin` actually points and picks the tool that serves it: `gh` on GitHub, `tea` on Gitea and Forgejo (found under `tea-cli` too, which is how some distributions ship it). Everything that is only Git - branching, committing, pulling, pushing, merging, pruning, releasing, and re-spelling a remote between HTTPS and SSH - now works on any host with no host-specific client installed at all.

- Accounts can say which git host they are on, with `host` and `user`. An account's token is only applied where it can be used, so a GitHub token is never handed to a push at somebody else's host, and the identity block says which two hosts disagreed. A non-GitHub token is exported under its own variable rather than as `GH_TOKEN`, which `gh` would otherwise pick up. `account list` shows the host each account is on, marked as the default where the file never said, and both it and the identity block name the account's own login instead of looking only for a GitHub one.

- The credential helper reads both the token and the username from the environment, so nothing from your config file or `GITSBY_ACCOUNT` is ever part of a command Git runs.

- The identity gate covers every host, not just GitHub's. A pull request opened through `tea` while `git` pushes as a different key is refused the same way the `gh` version always was, and the refusal names the tool that would have acted. The check on commands that push with plain Git - `sync` above all - now reads the account's login on the host in question, so an account identified by `user` rather than `ghAccount` is compared instead of skipped.

- The identity block has a `Git host` line for hosts `gh` does not serve, naming the host and who its CLI holds a login for. Previously it simply printed nothing there.

- `account set <account> <key> <value>` writes one key into an account's block of the accounts file, so the fixes the identity block suggests can be typed as a command rather than made by hand. It shows the edit before making it, refuses a key nothing reads instead of leaving a line that is silently dropped, and keeps the rest of the file - comments and order - as it was. It creates the file if there isn't one yet, with a header naming the keys.

- The Windows binaries carry an icon and version details. Explorer shows the gitsby logo instead of the blank default, and Properties reads a version, description, copyright and file name off the file itself.

- Every build carries a build number alongside the version: `gitsby v2.1.0 build dbrk8`. It is the number of minutes from the start of 2000 to the commit the build was made from, in Crockford base32 - five characters, and none of the letters that get misread when somebody reads one back over the phone. Taken from the commit rather than the clock, so the same source always gives the same build number and a published binary can still be rebuilt to the checksum it was published with. `--version`, the help screen and the release notes all name it.

- Commands say which build produced their output, on a line of their own above it, so a report of something going wrong carries the version and build number without anyone having to ask for them. `-q` leaves the line out, and `raw git` and `raw gh` still hand their tool's output straight back with nothing added.

- `--about` prints what Gitsby is, who wrote it, the license it is under, and where it lives. `--donate` prints the sponsorship link. Both work outside a repository, and both are spelled as bare words too.

- The accounts file takes `~`, `${HOME}` and `%USERPROFILE%` as the home folder on every platform, with either slash, so one file synced between Windows and Linux applies on both. No other variable is expanded, and a rule that starts with one is listed as ignored.

### Changed

- The accounts file is in [SHCL](https://github.com/jim-collier/shcl) now - `key: value`, one indented block per account - read and written through that format's own module rather than a parser of Gitsby's own. Several folders for one account are a list: `path: ~/dev/work, ~/dev/other`. Key names settle on lower case (`ghaccount`, `tokenfile`, `sshkey`, `pathcontains`); the file takes any casing. A file in the old flat `key = value` layout is still read as it is, and the first `account set` rewrites it in the new layout with its comments kept. A file `account set` creates ends with a footer naming the format and where its syntax is written down.

- The accounts file lives where each platform keeps one, and each platform is asked in its own terms. Windows reads `%APPDATA%\gitsby\config.shcl`; macOS reads `~/Library/Application Support/gitsby/config.shcl`; Linux and FreeBSD read `$XDG_CONFIG_HOME/gitsby/config.shcl`, then `~/.config/gitsby/config.shcl`. The first of those is also where `account set` creates a file when there is none, and where the identity block points you when it has advice about one.

- `XDG_CONFIG_HOME` is read on Linux and FreeBSD only, and `APPDATA` on Windows only. Each is one platform's variable and means nothing on the others: reading `APPDATA` under Linux put a name that a Wine or Samba install can leave set on the list of places Gitsby looks for credentials, and reading `XDG_CONFIG_HOME` under Windows let an MSYS shell's session answer for a Windows one. `~/.config` is a Linux spelling by the same measure, so Windows and macOS no longer read it either.

	> **Upgrading on Windows or macOS**: if your accounts file is under `~/.config/gitsby/` - which earlier versions did search everywhere - move that whole folder, `accounts` and any token files included, to `%APPDATA%\gitsby\` on Windows or `~/Library/Application Support/gitsby/` on a Mac. Neither platform looks in the old place any more, and a file that isn't found is not an error: Gitsby carries on with no accounts configured at all. Linux and FreeBSD are unaffected.

- `update` is now `pullcom`, which names both halves in the order they run rather than reading like it updates gitsby itself. It also answers to `update`, `pull`, and every partial spelling from `pullc` through `pullcommit`. `sync` is unchanged; the pair was the unclear part, not either word alone.

- `br land` is now `br merge`, the word most people reach for first. `br land` still works.

- On Windows, every path Gitsby works out itself is spelled the Windows way - backslashes and an upper-case drive letter. `account list` prints each rule the way the config file writes it. It was showing folder rules in the internal form paths are matched in, lower case with links resolved, so the folder on screen was one nobody had typed.

- One word per thing, across every screen. The current directory is `Current dir` everywhere; `status` and `whoami` called it `Directory` and `account list` called it `Here`. `account list`'s `Resolves to` is now `Account`, which is what `status` already called the same answer - the old label named no actor, so the first question it raised was who was doing the resolving. A folder with nothing configured gets `(nothing configured)` and nothing further; it used to go on to name `gh`, which is wrong on every host `gh` does not serve and answers a question about Git's own fallback that nobody asked. An account that resolves but names no login no longer assumes `gh` either - it names whichever tool serves that account's own host, and names none where there is none.

- The identity display now says where the account it is using came from, and which file that is, on their own lines: `From: An account block named 'acme', because its folder rule covers this directory.` and `File: /home/pat/.config/gitsby/config.shcl`. The old `(from config 'acme')` named neither, and "config" is ambiguous here - `gitsby.ghAccount` is a Git config key and the account blocks are not.

- Where an account resolves but cannot be applied, that block goes on to explain it rather than trailing one long clause off the end of the line. It says which half of the account did still apply - an SSH key and a commit identity go in whether or not a token does - why the rest didn't, and the `account set` command that fixes it.

- The identity block says `Git host` rather than `Forge`, there and everywhere else it appears. "Forge" is a word for people who already knew the answer, and this block exists for the people who don't.

- `pr` no longer requires `gh` to be installed before it will look at your arguments. It establishes the host first, so a repository on another host is told which tool it needs rather than told to install a GitHub client it would never use. `pr` on a repository with no remote at all now says so outright instead of failing further in.

- `repo url` re-spells a remote between HTTPS and SSH on any host. It only ever rewrote text - it asks the host nothing - and refusing everywhere but github.com was a limitation of the URL parser rather than a rule.

- The ssh identity probe understands Gitea's greeting as well as GitHub's, so the SSH line names the account on a Gitea remote instead of reporting it unknown.

- The old spellings are permanent, not a deprecation period. Nothing that works today stops working, and no script needs editing.

- `repo clone` takes `owner/name` as well as a full URL, the way `repo create` and `repo connect` already did - and takes it before showing you the plan, rather than failing on it afterwards.

- `release` with nothing new to release now exits 0 and says so. Every other command treats nothing-to-do as success, and re-running one is meant to be safe.

- `yes` at a confirmation prompt is a yes. Only a bare `y` counted before, so the word most people type aborted the command.

- Options with no command - `gitsby -q`, `gitsby -q --help` - print the command list. The first reported an unknown empty command; the second printed nothing, because `-q` was silencing help somebody had explicitly asked for.

- Trailing arguments are refused everywhere now. `pr <number> extra` was the one place an extra word was silently dropped, and `pr create` with an unquoted title now gives the same quote-your-message hint the other commands give.

- An option typed between `raw` and the tool says where gitsby's own options go, instead of calling it a subcommand nobody has heard of.

- The installers' `--arch` (`-Arch`) picks the binary now. It was accepted and ignored while the product was one script that ran everywhere. `--ref` became `--tag` (`-Ref` became `-Tag`), because what it names is a published release rather than any git ref; both old spellings still bind.

- Installing on Windows through the Bash installer now points at the PowerShell one, which is the one that also puts the install directory on PATH.

### Fixed

- `account set` no longer replaces an accounts file it can't read. It names the file, says why and what to do, and writes nothing. It also refuses when a file turns up while it runs, or when a link where the file goes points at nothing.

- `br prune` no longer deletes a branch on origin that has moved since your last fetch. It asks origin just before deleting, leaves a moved branch alone, and reports one already deleted there instead of abandoning the rest. This happened with `--no-fetch`, or when someone pushed while the prompt waited. With `--no-fetch` and origin unreachable, it now says so instead of guessing the branches were already gone.

- A folder rule has to be absolute or start at the home folder. A relative one is listed as ignored and `account apply` no longer writes it, since git read `path: .` as the whole home folder, in 2.1.0 as well. `account set` turns a relative path into the folder it names from where you run it, and `account list` warns about a relative rule an earlier `account apply` left in your global git config.

- `repo clone` picks its account from the folder the clone lands in, not the folder you launched it from. Cloning into your personal tree while standing in a work repository used the work account - the one case where the folder that decides is not the one you are in. A `gitsby.ghAccount` set on the surrounding repository no longer follows the clone out of it either, and the owner of a repository being cloned is not taken as evidence that it is yours: with no rule for the destination, gh stays on its own account.

- A folder rule written through a symlink now claims the folder. A path that goes through a link - a synced folder, a stable name pointing at a dated one, a home directory that is itself a link - was compared against the folder's real name and matched nothing, so the account silently never applied. `account list` looked right while this was happening; it now marks the account in force either way.

- A repository that sets its own commit name or email keeps it. An account naming both used to replace whichever one the repository had set, if the repository had left the other alone. The account still fills in the half that isn't set.

- The note that a hotfix changes shipped code appears wherever you run `br merge` from. It only appeared from the top of the repository, and was silently missing from any subdirectory.

- `GITSBY_ACCOUNT` naming a configured account applies that account. Where the account named no GitHub login of its own - a commit identity and an ssh key and nothing else - the name was read as a bare login instead: none of the account applied, the key fell back to whichever one ssh picked, and the account's own name was reported as the GitHub login the run was acting as. A folder rule had always applied such an account, so asking for one by name got you less than not asking. The same account is also kept now when a repository sets `gitsby.ghAccount` itself; an account that names no login disagrees with nothing.

- A config file saved with a byte-order mark keeps its first line. The mark landed on the first key, which was then read as one gitsby doesn't understand and dropped - and the line that reports those printed the mark along with the name, so the only warning named a key that looks exactly right. Windows editors write a mark by default.

### Removed

- The installers no longer take `--release dev` (`-Release dev`). It installed the tip of a branch, which was possible while the product was a script in the tree; a branch has no published build behind it now. Typing it says so and names the two routes that exist - a release by tag, or a one-command build from source. The contributor setup scripts went with it: a Go checkout needs only Go, and the three commands are in the README.

- `--offline` is no longer accepted as a spelling of `--no-fetch`. It was undocumented, and it never did what the word says - pushes went out regardless. Typing it now says so and names `--no-fetch`, which skips the pre-command fetch. Being offline is still handled on its own: gitsby finds out by trying, and each command degrades or refuses accordingly.

### Other work

- The demo gif runs about forty-seven seconds instead of just over two minutes, and is less than half the size. Five scenes rather than nine, and one of them stops on its confirmation and is answered on camera - the tool showing its Git and asking first is the first thing the README claims, and the demo had never shown it happening. Captions now appear whole instead of arriving a letter at a time, which had been taking more screen time than the commands they introduce.

- The installers' fallback release lookup - the path taken when the newest publication is a pre-release - now takes the highest-versioned release rather than the newest-published one, so a fix backported to an older line can never install over a newer release. The lookup also stopped depending on how GitHub formats the list, and `Get-Help` on `install.ps1` shows the real help instead of an auto-generated stub.

- `br prune` re-checks its delete candidates in one git call instead of one per branch, so pruning many branches costs the same handful of processes as pruning one.

- The remote-URL and accounts-file parsers refuse a little more nonsense: a "host" containing whitespace is treated as unparseable rather than matched against account rules, and `account.<name>.` with no key after the final dot is an ignored line rather than a half-parsed account. Both were found by the module's new native fuzz targets, which the pipeline now runs briefly every full pass.

- PSScriptAnalyzer is back in the lint stage. The Windows installer is the one piece of PowerShell that still ships, and it had been going out unlinted since the scripted build was frozen.

- `cicd/release.bash` retries the installer it runs against the freshly published release before reporting that the release isn't installable. Cutting v2.1.0 warned that it wasn't when it was: GitHub serves the tag a little ahead of its assets, and the installer stops rather than quietly skip checksum verification. A warning that fires on a good release is worse than no warning at all.

- The Bash and PowerShell builds and their installers moved to `legacy/`, and the pipeline became Go-specific: one engine instead of two, seven stages, and the Go toolchain required rather than probed. `cicd/parity.bash` was kept and repointed - it compares this build against the frozen v2.1.0 one, which is the backwards-compatibility question, and checks that `update` and `br land` still route where they always did.

- A release is now one binary per platform - linux, windows, macOS and FreeBSD, amd64 and arm64 each - with a single `SHA256SUMS` over the set. They are built before the tag is cut, so a target that stops compiling fails while nothing has been changed. The version comes from the tag alone; no file in the tree records it.

## v2.1.0 - 2026-08-14

### Added

- Commands that go through gh now act as the account that belongs to where you are, chosen per run rather than by switching gh's active account. The account is named in the identity block, and `--any-identity` (`-AnyIdentity`) turns it off. A remote whose owner gh has no account for - an org, or anyone else's repo - is left alone.

- Multiple GitHub accounts, chosen by which folder you are in. A config file maps a folder tree to an account, and every command run anywhere under it acts as that account - gh, git's credentials, the ssh key, and the commit identity. Read from `~/.config/gitsby/config.shcl` (or `$XDG_CONFIG_HOME`, or `%APPDATA%` on Windows), overridable with `--config FILE` (`-Config FILE`) or `GITSBY_CONFIG`. With no config file at all nothing changes.

- Git itself can now authenticate as the folder's account over https, using the token gh already holds or one named by `tokenFile` - so a second account needs no ssh key, no host alias, and no rewritten remote URLs. The token is supplied through the environment for the length of one command and written nowhere.

- `repo url [https|ssh]` shows how `origin` authenticates, or switches it between the two. Only the remote URL changes. The identity line suggests it where a repo is still on ssh but its account holds a token; `protocol = ssh` in the config says you meant it and stops the suggestion.

- `account` lists the configured accounts and says which one the current folder resolves to, and from where. `account apply` writes the same folder rules into your global git config as `includeIf` blocks, so plain `git` outside gitsby behaves identically. Re-running it refreshes only the entries it wrote, leaves hand-written ones alone, and drops rules for accounts you removed.

- `raw git <args>` and `raw gh <args>` run the real tool as the folder's account and pass everything after the tool name through verbatim, with the tool's own stdout and exit code. An existing script becomes account-correct by prefixing its commands rather than being rewritten. `GITSBY_ACCOUNT` overrides the folder for one run.

- Two optional git config keys remain, for a repo that wants to answer for itself. `gitsby.ghAccount` names the account to act as, and `gitsby.ghTokenFile` names a file holding its token. Both are read through `git config`, so an `includeIf` on the repo path selects them, and both outrank the config file's folder rules.

- `cicd/utility/include/gh-account.bash`, a sourceable version of the same selection for pipelines that call `gh` directly rather than through gitsby.

- `account.<name>.pathContains` matches a run of folder names appearing anywhere in a path, rather than a tree on this machine - so one config file can be synced between machines whose roots differ. Whole folder names only, so `alice` never matches `alice-old`. More folder names is the more specific rule, and an absolute `path` still wins when both match. `account apply` hands it to git as `includeIf.gitdir:**/github.com/alice/**`, which git globs natively, so plain `git` follows the same rule on every machine too.

### Changed

- Healing `origin/HEAD` after a fetch only runs when there is nothing to read locally, instead of on every command. It queries the remote a second time, and git 2.47 and newer write one at clone.

- The passthrough no longer asks gh which account is active. That answer named only the account being replaced, on the identity line that `raw` does not print.

### Fixed

- Git over https was handed an empty password whenever the folder's account was the one gh was already active as. The token is now supplied whenever one is found, rather than only when it replaces a different account. Because the helper sets aside any credential manager configured ahead of it, the effect was worst on the setup that needs no configuration at all: a single account, logged in to gh, pushing over https.

- A `#` after whitespace starts a comment anywhere in the config file, not just at the start of a line. A trailing comment used to become part of the value, so a folder rule could never match any directory - and a rule that never matches reads exactly like no rule at all, leaving the run to act as gh's own account with nothing said. Quote a value to keep a literal `#` in it.

- An account name is held to letters, digits, dot, dash and underscore, and anything else is reported as an unread key. The name becomes a file under the include directory, so a name with a path in it sent `account apply` to write its fragment somewhere else entirely.

- The identity line now names an account that was asked for by name, including the bare GitHub login `GITSBY_ACCOUNT` accepts. It used to appear only when some configured value had been used, so a bare login - which `raw` reports on stderr, and which selects the token a push authenticates with - printed no line at all in `status`, the command that exists to answer who a push goes out as. An account merely inferred from the remote's owner is still not shown, so a single-account machine sees nothing new.

- PowerShell: the fetch and the remote probe add their connect timeout to git's own ssh command instead of replacing it. A repo carrying `core.sshCommand` - the usual way to hold two accounts on one machine - was read with the default key, so a private repo only the account's key can reach reported as unreachable and the publishing commands refused to run.

- The identity probe asks as the key git would actually push with, following `GIT_SSH_COMMAND` and then `core.sshCommand`. It used to run a bare `ssh`, so a repo that selects its key through config - the usual way to hold two accounts on one machine - was reported as the default key's account while git pushed as somebody else. Where gh's account happened to match the default key, the mismatch check passed while both halves were wrong.

- The identity line names the key from the same source, so it can no longer report the right account beside the wrong key file.

- `fetch` and the remote probe no longer override a repo's configured ssh key. Both set `GIT_SSH_COMMAND` for the connect timeout, which outranks `core.sshCommand`, so a private repo reachable only through the repo's own key reported as offline.

- On Windows, a local-path remote on a drive letter was read as an ssh host named after the drive, so every command probed a machine called `C` for an account. `repo clone` re-run against a directory it had already cloned refused itself, and `repo connect` refused a URL matching the origin it already had - git stores a local path in the platform's own spelling, and both compared it as text against the spelling you typed.

- PowerShell: `-Config=FILE` written as one word is refused by name, instead of failing in a way that looked like nothing had happened. PowerShell can't bind a joined option through `-File`: ahead of a command it took the next word as the option's value, so `br list` arrived as `list`; after one it overflowed the positional slots. The first of those printed the whole help and exited, which `-q` then silenced completely. Use `-Config FILE` or `-Config:FILE`. The Bash build takes the joined form as it always has, and `raw` still takes it too, since it reads the real command line.

- `--config` with an empty file name is refused instead of falling back to the default config. A script expanding a variable that turned out to be empty was indistinguishable from never passing the option, so the run silently acted as whichever account the default file named - the wrong identity, on a push, with nothing said. An empty `GITSBY_CONFIG` still falls through, as an unset environment variable and an empty one are the same thing.

- Windows: a folder rule spelled the way Git Bash spells paths now resolves in both builds. The PowerShell build folded the drive letter only after asking the filesystem, and .NET reads `/c/...` against the current drive - so nothing resolved, short names were left as written, and the same rule matched in one build and not the other. An MSYS mount path such as `/tmp/...` still cannot work in the native build, and `account` now marks any folder rule that resolves to no directory rather than letting it look like no rule at all.

- The identity line says when an account was resolved but could not be applied. With no token available gh goes on using its own account, and the block that exists to answer who a push goes out as was naming the other one.

- `sync` compares identities before it pushes. The commands that push with git rather than writing through gh now ask whether the folder's account is the one origin will authenticate as: a warning interactively, a refusal unattended, and `--any-identity` (`-AnyIdentity`) says it was intended.

- `account apply` also writes `credential.https://github.com.username`, so plain `git` over https asks for the folder's account instead of whichever credential the helper happened to hold first. It wrote the ssh half and left that gap open.

- PowerShell: an unknown option is named. It landed in the remaining-arguments slot, left the command empty, and got answered with the whole help text - or under `-q` with nothing at all but an exit code.

- `br prune` asks git once per target ref instead of twice per branch. The re-check immediately before each delete stays: that one is the safety net, not the survey.

- `account apply` writes its `includeIf` rules shortest path first. git applies includes in file order and the last match wins, while gitsby takes the longest matching folder - so a tree nested inside another account's tree got whichever account was declared later, and plain `git` then disagreed with gitsby about that one directory, which is the single thing `apply` exists to prevent.

- `--config` (`-Config`) requires a readable regular file in both builds. Bash took a directory, loaded no accounts and exited 0; PowerShell passed silently over an unreadable file. Either way the run went on to act as an account nobody chose. A config found in one of the default locations is still skipped rather than refused - nobody asserted that one was there.

- An account name is matched whatever case you type it in. Bash's loader lowercases the key on the way in but its lookup did not, so it could miss the entry it had just stored.

- Gitsby's own options all work before `raw` now. Only a handful were taken, and anything else produced "Unknown command 'raw'" - naming the one token that was not the problem. The ones with nothing to act on in a passthrough are accepted and inert; `-h` and `-v` still mean help and version.

- PowerShell: `raw` can pass git's `--` pathspec separator, spelled `` `-- ``. A bare `--` is taken by PowerShell's parameter binder before the script starts, so it can never reach the tool at all. The Bash build takes a plain `--`.

- `account apply` reports an unusable include directory in gitsby's own words, instead of a raw shell or .NET error that differed between the two builds.

- Both installers say in the plan, before you agree to it, whether the download will be checked against the release's `SHA256SUMS`. That was reported only afterwards, and on the `--release dev` path not at all - so the one route that installs an unverified file was also the quiet one. Where the plan promises verification and it then can't happen, the install stops rather than noting it in passing; `--ref TAG` (`-Ref TAG`) takes it unverified as an explicit choice.

- The PowerShell installer adds the install directory to your PATH on Windows, and says so in the plan. Nothing else on Windows does, so an install used to finish with a program that couldn't be run by name.

### Other work

- The demo now shows folder-based accounts. It ends with the same command run in two repos under different roots, resolving to a different account each time with nothing configured per repo and no flags given - and the six scenes before it, which were already acting as the work account, now say so on their identity line. The throwaway world it is built from grew a second tree and a gitsby config file to match.

- The demo's prompt shows the folder the command runs in, rather than always `~`. A demo whose point is which folder you are standing in cannot hide it. Steps that do not say get `~`, and the renderer now warns by name when a caption or command would run off the edge of the screen instead of silently cutting it off.

- Everything the demo gif is built from now sits together in `cicd/utility/demo/`, alongside a plain-language `script.txt` describing what the demo shows, scene by scene, in a form meant to be edited by hand. The renderer's own scenario file stays as the machine version of the same thing.

- Both suites now run their PowerShell leg on Windows rather than only on Linux. Test stubs get a `.cmd` sibling, since PowerShell finds a shebang script on PATH but starts nothing and reads the silence as no output; and the checks that need a confirmation to refuse no longer depend on `setsid`, which Windows has no equivalent of.

- The fuzz suite deliberately does not get that `.cmd` sibling, and skips four checks on the Windows PowerShell leg instead. Its arguments are hostile by design, and `cmd.exe` re-parses an unquoted `&` or `>` - which would run part of a vector for real and report an injection gitsby never had.

- The fuzz suite also skips its glob-shaped clone directories on Windows, so it can pass there at all. Win32 forbids `*` and `?` in a path, so native git cannot create such a work tree in the first place and the check could never be satisfied. The same vectors still run everywhere else, where they pass.

- The PowerShell build is verified on Linux, not just assumed to work there. Both suites run green on Debian, the same as on Windows.

- Refusals that only checked an exit code now check the reason as well. A build predating a command also exits nonzero when handed it, so the exit code alone could not tell a working refusal from an unknown command.

- A parity suite, `cicd/parity.bash`, runs in the test stage of both engines. It asks whether the two builds *answer the same* for one input, where the regression suite asks whether each behaves correctly - a check written per implementation passes on both while they quietly disagree, which is what every port defect that reached users actually was. It found two real divergences while being written.

- `cicd/utility/demo/demo-repo.bash` no longer removes the directory it is pointed at without checking whose it is. It took a path as its first argument and wiped it before doing anything else, so a mistyped or inherited argument took whatever lived there and still reported success. It now stamps the directories it builds and refuses to remove one it did not, along with a relative path, the filesystem root, and anything containing `..`.

- Every other recursive or forced removal in the tree names a path the script itself just created, and each one is now written so that an unset variable stops it instead of widening it. The suite checks this, and checks that no new one slips in.

- The publish preview's throwaway git directory is removed even if the run is interrupted while the preview is still on screen. The Bash build removed it only on the way out of the function, so a Ctrl-C mid-preview left an empty directory in temp; the PowerShell build already covered this.

- All three harnesses now drop the two settings that reach them from an ordinary working terminal and outrank everything they pin: `GIT_CONFIG_COUNT` and its numbered keys, which beat every config file including a repo-local one, and an inherited `GH_TOKEN`. A run carrying either still reported a count and a list of names - the checks were simply no longer about what they said.

- `cicd/release.bash` cuts a release end to end, in three phases so a failure never leaves a half-cut one: verify and change nothing, land, then publish and prove by running the documented installer against the published release. `--dry-run` says what it would do. It guards the two things that have been forgotten by hand - the two builds agreeing on the version, and the history footers carrying an entry since the last tag. The gate it runs is the pipeline engine belonging to the platform it is on, rather than always the Bash one.

- The pipeline fast-forwards from origin before it builds anything, in both engines. Its only pull used to be in the publish stage, which runs after lint, tests and fuzz have all passed - so a change merged upstream meanwhile was pushed having been validated against the older tree. It stops on a real divergence, warns and carries on when offline or with no upstream, and `--no-sync` (`-NoSync`) skips it.

- The test suite no longer reads whatever accounts the person running it has configured. It already isolated git config and the commit identity; the accounts config decides which account a command acts as, and a single line in a real one failed three checks per implementation.

- The README is a landing page again: what it is, the commands, a worked example, and the install, with the depth moved to `accounts.md` and `workflows.md`. It also now says up front that gitsby picks a GitHub account by folder, which was the one thing in this release it never mentioned.

- `cicd/release.bash` reads the changelog from below the commented-out template at the top of the file. All three of its readings took the first heading that matched and so found the template's, which would have retitled the template instead of the section being released, left that section saying vNEXT, and published the empty template as the release notes - non-empty text, so the warning that exists for exactly this never fired. The template's heading is spelled `TEMPLATE_vNEXT` as well, so either guard is enough alone.

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
