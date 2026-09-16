<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- TOC ignore:true -->
# UI and UX style guide

How gitsby's output reads, and how its commands ask, refuse and fail. Code style is in [style-guide.md](../style-guide.md). The reasons behind most of these rules are in [design.md](design.md), under "Direction decisions" and "UI".

New output follows this guide. Where the program and the guide disagree, one of them is wrong, and that goes on the backlog.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Ground rules](#ground-rules)
- [Commands and options](#commands-and-options)
- [Layout](#layout)
- [Plans and prompts](#plans-and-prompts)
- [Status lines and warnings](#status-lines-and-warnings)
- [Errors](#errors)
- [Diagnostics](#diagnostics)
- [Words and values](#words-and-values)
- [Scripts](#scripts)

<!-- /TOC -->

## Ground rules

- Least surprise. A command does what its name says, in the order its plan shows, and nothing more.

- Every command that changes anything shows the repo state, then the exact git it will run, then asks.

- Unknown beats a guess. Where an answer can't be found out, the output says so and says why. A name that is only likely gets believed.

- A machine with nothing configured sees what it saw before a feature existed. A single-account user never learns that accounts can be configured, so a new line or column appears only once the config holds the thing it compares.

- Plain text. No color, no cursor movement and no spinners, so output reads the same on screen as it does pasted into a bug report.

## Commands and options

- Daily commands are one word: `pullcom`, `sync`, `status`, `whoami`, `release`. The rest sit under a noun: `repo`, `br`, `pr`, `account`, `raw`.

- One verb per action, across every noun. It's `create` everywhere, not `create` in one place and `new` in another.

- A renamed command keeps its old name forever, as a spelling the help doesn't list. A new name is chosen with that in mind.

- Only `pullcom` takes shortened spellings. Nothing else gets a prefix ladder.

- A command that deletes in bulk takes no names and has no `--force`. Deleting one thing by name is what raw git is for.

- An option gitsby no longer takes, or one whose name promised more than it did, is refused by name and points at the one to use. It is never quietly ignored.

- gitsby's own options go before `raw git` or `raw gh`. Everything after the tool name belongs to that tool.

## Layout

- Output starts with a blank line and ends with one. Sections are split by a single blank line, never by a rule, and there are never two blanks in a row. A refusal is the exception: it ends with two, to match the 2.1.0 scripts.

- The first line names the build, as `gitsby v2.1.0 build dbrk8`. It is left off under `-q` and on `raw`.

- A state line is a label padded with dots to 14 columns, then a colon, a space and the value. `Default branch` is the longest label. A second line under the same label keeps the colon and blanks out the label.

	~~~text
	Current dir ..: /srv/dev/acme/app
	Remote .......: git@github.com:acme/app.git
	Default branch: main
	Current branch: dev :: login-form
	~~~

- A branch is shown against the branch it merges into, as `base :: branch`. `main`, `master` and `dev` are shown bare.

- A file list is one file per line, indented four spaces, cut at the terminal width and capped in length. A big tree can't push the prompt off screen.

- The help pads each entry with dots so the descriptions in a group line up. It lists only spellings the parser takes.

- A path is shown the way its platform spells it, with backslashes and an upper-case drive letter on Windows. In a diagnostic, a leading home folder folds back to `~`. The form used to match paths is never printed.

## Plans and prompts

~~~text
Going to do (steps marked * only if needed, based on repo state):
    git checkout main *
    git pull --ff-only --autostash *
    git checkout -b login-form
    git push -u origin login-form *

Continue? (y|n):
~~~

- The plan is the git the run will use, in order. A step that runs only when the repo state calls for it ends in a `*`. A plan that differs from what runs is a bug, including where the command branches on state.

- Whatever the plan claims is known before it prints. A fact that needs the network is fetched first.

- A command that creates a branch names it in the state block, as `New branch ...: main :: login-form`.

- A warning meant to change the answer goes last, right above the prompt, where it can't scroll away behind the plan.

- The prompt is `Continue? (y|n):`, with the answer typed on the same line. Only `y` or `yes` means yes. Anything else is a no, including a bare Enter and end of input, and the run prints `[ User aborted. ]`.

- With no terminal to ask on, the run refuses and names `-q`. It never waits for input that can't come.

- `-q` or `-y` answers yes. Where a person would get a warning, `-q` gets a refusal, since nobody is there to read it. `--any-identity` is how a script says an account mismatch is intended.

- Offline, a command that exists to publish refuses before its plan. One that means something locally runs, says what it skipped, and names `sync` as the way to publish later.

## Status lines and warnings

- A line reporting progress or an outcome is bracketed: `[ Cloned into 'app'. ]`. A mutating run that worked ends with `[ Done. ]`.

- A warning starts with `WARNING:`. It says what was skipped or kept, and what to run later if anything.

## Errors

- An error goes to stderr, starting `gitsby:`, as one or more full sentences. A refusal the reader can fix reads as advice.

- When a git step fails, its own output is already on screen. gitsby adds only the command and its status: `gitsby: 'git push' failed (exit 1).`

- Any command named in an error or in the help is one the parser takes today, spelled out in full.

- A `Syntax:` line is read only by someone who just typed the command wrong. Define each placeholder where it appears. List a closed set of values from the same constant the check uses, and pick an example that shows how the placeholders relate.

| Exit status | When
| :---        | :---
| 0           | Success, and "nothing to do"
| 1           | A refusal, a failed step, or a "no" at the prompt
| The tool's  | `raw git` and `raw gh` hand back whatever the tool exited with

## Diagnostics

When a line can't just state a fact, the explanation goes in labeled notes under it. A refusal uses the same layout under its first sentence.

~~~text
gitsby: Another run is editing the accounts file.
  File: ~/.config/gitsby/config.shcl
  Lock: ~/.config/gitsby/config.shcl.lock
  Why:  Edits go in one at a time, and the lock beside the file
        was still there after waiting for it.
  Kept: Nothing was written.
  Fix:  If no other gitsby is running, a run that was stopped
        left it behind. Remove it, then run this again:
          rm '/home/pat/.config/gitsby/config.shcl.lock'
~~~

- Each label has one job. `Why:` says what went wrong and why. `Kept:` says what took effect anyway. `Fix:` says what to type, and `File:` says where. `From:` names where a value came from.

- A note's text wraps at 56 columns, whatever the terminal's width, so it reads the same on screen as in a bug report. A path or URL longer than that stays whole.

- A path goes on its own labeled line, never inside a sentence or parentheses.

- A fix that can be a command is given as one, such as `gitsby account set work host gitea.com`. A config line to retype can be mistyped. A literal to copy is indented under its note and never wrapped.

- A config key is spelled in full, the way the file takes it. So is an example value, which has to be one the matcher really accepts.

- A note names only lines that are on screen. The reference is built from the same condition that prints the line.

- A diagnostic offers a fix and never applies it. A read-only command stays read-only.

## Words and values

- One word per thing, in every command. The directory is `Current dir` everywhere, and the account is `Account`. Before naming a new field, find what the rest of the tool calls it and reuse that label.

- Labels are nouns. A verb label such as `Resolves to` leaves the reader asking who does the resolving.

- Say "git host", or name the host. Never "forge".

- Never "the config" on its own. Name the environment variable, the git config key, or the account block and its file.

- A missing thing is `(none)`, a setting with no value is `(unset)`, and an answer that couldn't be found out is `(unknown - ...)` with the reason.

## Scripts

- `-q` is the machine-readable mode. It prints no build line and asks nothing.

- `raw git` and `raw gh` give stdout to the tool alone. The one line naming the account goes to stderr, and `-q` silences it.
