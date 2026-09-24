<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD055 -- Table pipe style -->

# Multiple GitHub accounts

Most people with two GitHub accounts also have a folder for each: one tree for work, one for everything else. Gitsby takes that literally. Say which account owns which folder, once, and every command run anywhere under that folder acts as that account - `git` and `gh` alike.

Nothing here is required. With no configuration Gitsby uses whichever account `gh` is logged in as, exactly as it always did. A single-account machine never notices the feature exists.

- [Setting it up](#setting-it-up)
	- [One config file, several machines](#one-config-file-several-machines)
- [No SSH keys needed](#no-ssh-keys-needed)
- [Cloning](#cloning)
- [Teaching plain git the same rules](#teaching-plain-git-the-same-rules)
- [Scripts](#scripts)
- [Which account are you acting as?](#which-account-are-you-acting-as)

## Setting it up

One file, one block per account, `#` for comments:

~~~yaml
# ~/.config/gitsby/config.shcl

protocol: https                  # how new remotes are set up; https needs no ssh key

account: work
	path: ~/dev/work             # the folder tree this account owns
	ghaccount: my-work-login
	name: Ada Lovelace
	email: ada@work.example

account: personal
	path: ~/dev/personal
	ghaccount: my-personal-login
	email: ada@home.example
~~~

The format is [SHCL](https://github.com/yottacore/shcl): `key: value`, blocks by indentation, tabs or spaces. Key names are case-insensitive and settle on lower case. A value holding a `#`, a comma or a colon goes in quotes (`path: "C:/work"`), and a backslash in a bare value is an escape, so a Windows path is either quoted with the backslashes doubled or written with forward slashes, which Gitsby reads either way.

A file written for the 2.x scripts - flat `account.work.path = ~/dev/work` lines - is still read as it is. The first `account set` rewrites it in the layout above, comments included.

Gitsby reads the first of these it can read, and `account set` creates the first one when none of them is there:

| Platform | Where it looks
| :--      | :--
| Linux, FreeBSD | `$XDG_CONFIG_HOME/gitsby/config.shcl`, then `~/.config/gitsby/config.shcl`
| macOS    | `~/Library/Application Support/gitsby/config.shcl`
| Windows  | `%APPDATA%\gitsby\config.shcl`

Each platform is asked in its own terms and nobody else's, `~/.config` included - that is a Linux spelling, not a Mac or Windows one. `XDG_CONFIG_HOME` is a Linux and BSD variable, set by a desktop session rather than by you, so it is read there alone; `%APPDATA%` likewise is read on Windows alone. macOS and Windows each have exactly one location, and fall back to `~/.config` only in the odd case where the native one can't be worked out at all.

`--config FILE` (`-Config FILE`) overrides all of them, and so does the `GITSBY_CONFIG` environment variable.

If one of them is there but can't be read, other commands carry on without it. `account set` won't create a file in that case, since the new one would replace or hide it. It names the file and says what to do instead.

Per-account keys, all optional except a `path` to match on:

| Key             | What it does
| :--             | :--
| `path`          | A folder tree this account owns, as an absolute path or one starting at the home folder: `~`, `${HOME}` and `%USERPROFILE%` all mean it, on every platform, with either slash. No other variable is expanded, and a rule starting with one is listed as ignored. More than one: `path: ~/dev/work, ~/dev/other`, or repeat the key. The longest match wins, so a tree nested inside another account's tree belongs to the inner one. A relative path is listed as ignored, since a file cannot say what it was relative to; `account set` turns one into the folder it names from where you run it.
| `pathcontains`  | A run of folder names that appears anywhere in the path, so the same rule works on machines whose roots differ. Whole names only - `alice` never matches `alice-old`. Repeatable.
| `ghaccount`  | The GitHub login to act as.
| `tokenfile`  | A file holding that account's token, for a machine where `gh` was never logged in as it.
| `sshkey`     | A key to use instead of a token. See below.
| `name`       | Commit author name.
| `email`      | Commit author email.
| `protocol`   | `https` or `ssh`, for this account only. Anything else is listed as ignored.
| `host`       | The git host this account is on. Defaults to `github.com`, which is what every config written before this key existed meant.
| `user`       | The login on that host, when it isn't `ghaccount` - Gitea checks the username an HTTPS push presents, where GitHub ignores it.

Run `gitsby account` to see what it made of all that, and which account the folder you're standing in resolves to. It is the command to reach for when something went out as the wrong person. A `path` rule pointing at a directory that isn't there is marked as one that can never match, which is usually a typo. If an earlier `account apply` left a rule for a folder that isn't absolute in your global git config, it says so, and `account apply` removes it. Once any account names a `host`, the listing shows one for all of them, marked `(default)` where the file never said - an account meant for another host that never named one is the usual reason a repository there goes on using `gh`'s account.

The file is meant to be edited by hand, but you don't have to. `gitsby account set <account> <key> <value>` writes one key into that account's block - replacing it where the block has it, adding it where it doesn't, or creating the file if there isn't one yet. It shows the edit and asks before making it, refuses a key nothing reads rather than leaving a line that is silently dropped on every load, and keeps the rest of the file - comments and order - as it was. The spacing is the format's own: tabs, lower-case keys, one blank line between blocks. When the file isn't spaced that way already, the plan says the rest of it will be.

~~~console
$ gitsby account set work host gitea.com
    edit /home/pat/.config/gitsby/config.shcl, line 8
      was:     host: github.com
      becomes: host: gitea.com
~~~

Where an account isn't applying, the identity block names the `account set` line that fixes it. It won't make that edit for you: all it knows is that the file never said which host the account is for, which is not the same as knowing the account belongs to the host you happen to be pushing to - and guessing wrong means handing one host's token to another.

### One config file, several machines

`path` names a tree on the machine you're on, so a config using it can't be synced as-is: the roots differ. `pathcontains` names folder names instead, and matches wherever they appear:

~~~yaml
account: work
	pathcontains: github.com/my-work-login
	ghaccount: my-work-login

account: personal
	pathcontains: github.com/my-personal-login
	ghaccount: my-personal-login
~~~

That resolves under `C:/src/github.com/my-work-login/...` and `~/dev/github.com/my-work-login/...` alike, so the file syncs unchanged. A `path` under the home folder syncs too, since `~/dev/work` names the same folder on Windows as on Linux.

- Whole folder names only. `alice` never matches a directory called `alice-old`.

- More folder names is the more specific rule, so `github.com/alice` beats a bare `alice`.

- An absolute `path` beats a `pathcontains` when both match - naming this machine's own tree is the more specific claim. Mix them freely.

- `gitsby account apply` hands these to git as `includeIf.gitdir:**/github.com/alice/**`, which git globs natively - so plain `git` follows the same rule on every machine too.

## No SSH keys needed

The usual way to hold two GitHub accounts on one machine is a pair of SSH keys and a `~/.ssh/config` full of host aliases, which then have to be baked into every remote URL. Gitsby does not need any of that.

`user` is also what the identity check compares against on a non-GitHub host: if the account says one login and the key `git` pushes with authenticates as another, the command refuses before it sends anything, and `--any-identity` says the difference is intended. An account that names no login for the host makes no claim, so nothing is compared.

Neither the token nor the username is ever written into a config value: Git hands a credential helper to a shell, so both are read from the environment at the moment it runs. Nothing you put in this file becomes part of a command.

An account's token is a credential for the git host that issued it and for nowhere else, so Gitsby only applies one where it can be used: if `host` doesn't match the host `origin` is on, nothing is applied and the identity block says which two hosts disagreed. That is also why a Gitea token is never exported as `GH_TOKEN` - `gh` reads that variable, and every child process would inherit a credential for a host `gh` would try to use it on.

Over HTTPS, `git` authenticates with the account's own token - the one `gh` already stores, or the one `tokenfile` names. Gitsby supplies it for the length of a single command, through the environment, and nothing is written anywhere. So a second account costs one `gh auth login` and three lines of config.

- New remotes follow `protocol`, so `repo connect owner/name` sets up an HTTPS remote by default.

- An existing repo still on SSH is converted with `gitsby repo url https`. Only the remote URL changes - same repo, same history. Gitsby points this out on the identity line when it applies, and setting `protocol: ssh` says you meant it and stops the suggestion.

SSH keys keep working, and stay the answer when you can't use a token. Give an account an `sshkey` and Gitsby uses it (with `IdentitiesOnly`, so the agent can't offer the wrong one first). Anything you have already set yourself - `GIT_SSH_COMMAND`, or `core.sshCommand` on the repo - was chosen more deliberately than a folder rule, and wins.

## Cloning

`repo clone` is the one command whose folder is not the one you are standing in, so it uses the folder the clone lands in:

~~~bash
cd ~/dev/github.com/my-work-login/some-work-repo
gitsby repo clone my-personal-login/side-project ~/dev/github.com/my-personal-login/side-project
~~~

That clones as `my-personal-login`, because that is whose tree it lands in - not as the work account you happened to be standing in. Put the clone where it belongs and the right account fetches it.

With no rule covering the destination, gh stays on its own account. The owner of the repository you are cloning is not taken as a hint: cloning someone else's repository is ordinary, and it says nothing about who you are.

## Teaching plain git the same rules

`gitsby account apply` writes the same folder rules into your global git config, as ordinary `includeIf` blocks pointing at one small file per account. After that a bare `git commit` or `git push` in one of those folders uses the right identity and the right key, with Gitsby nowhere in the picture.

It is safe to re-run: it replaces only the entries it wrote before, leaves any you wrote by hand alone, and drops rules for accounts you have since removed.

## Scripts

`gitsby raw git ...` and `gitsby raw gh ...` run the real tool as the folder's account and then get out of the way. Everything after `git` or `gh` is passed through exactly as typed, stdout is the tool's alone, and the exit code is the tool's too - so an existing script becomes account-correct by prefixing its commands rather than being rewritten.

~~~bash
gitsby raw git push origin HEAD
gitsby raw gh pr list --json number

## One line on stderr says who you are acting as. -q silences it.
gitsby -q raw git rev-parse HEAD
~~~

`GITSBY_ACCOUNT` overrides the folder for one run, or for a whole script's environment. It takes either an account name from the config file or a bare GitHub login.

## Which account are you acting as?

`gh` talks to GitHub's API with its own token and never reads your SSH config, so the `pr` commands and `repo create` act as **gh's account** - not the account whose SSH key `git push` uses. With per-account host aliases in `~/.ssh/config` those can easily be different people, and a pull request opened as the wrong one is public and awkward to undo.

So the pre-flight names both, and the commands that *write* through gh compare them: `pr create`, `pr ok`, `repo create`, and `repo connect owner/name`.

The last two have no remote yet. The one they are about to set is knowable anyway - gh never uses a host alias, so it is always `git@github.com:owner/name.git` - so the identity that repo will live with afterward gets checked before anything is created.

- Interactively, a confirmed difference prints a warning immediately above the confirmation prompt.

- Unattended (`-q`/`-y`), a confirmed difference is an error and nothing runs.

- `--any-identity` says the difference is intended. No error and no warning; the identity block says plainly that no account was selected, and the mismatch still shows on it.

If either side can't be determined - no SSH agent, an HTTPS remote, a deploy key, gh logged out - that is reported as unknown and never blocks anything. Only a difference *both* sides confirm counts.

One consequence worth knowing if you use per-account host aliases. `repo create` and `repo connect owner/name` set `origin` to the canonical `git@github.com:...` URL, because that is what gh produces and gh does not read your SSH config.

Gitsby does not try to work out which of your aliases belongs to that account. That would be a guess about your setup, and a wrong guess is worse than none. Two ways to get the alias instead:

- Point `origin` at it afterward: `git remote set-url origin git@your-alias:owner/name.git`.

- Or skip gh and give `repo connect` the full URL: `gitsby repo connect git@your-alias:owner/name.git`.
