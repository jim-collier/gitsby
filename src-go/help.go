// The help text: what gitsby is, and one line per command. Written out rather than
// generated from a table, because the grouping and the dotted leaders are the point -
// this is the first thing anyone reads.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

func (a *app) printCopyright() {
	a.out.clean("")
	a.out.cleanf("%s %s, Copyright © %s %s.", meName, versionText(), copyrightYear, author)
	a.out.clean("Licensed under The MIT License (MIT). Full text at:")
	a.out.clean("  https://mit-license.org/")
	a.out.clean("No Warranty.")
	a.out.clean("")
}

func (a *app) printBlurb() {
	a.out.clean("")
	a.out.clean("Safer, state-checked wrappers for everyday git. Every command verifies the")
	a.out.clean("repo state before acting (commit only if dirty, pull only with an upstream,")
	a.out.clean("push only if ahead), so each is idempotent and safe to re-run.")
	a.out.clean("")
}

func (a *app) printAbout() {
	a.printCopyright()
	a.printBlurb()
	a.out.clean("  " + homeURL)
	a.out.clean("")
}

func (a *app) printDonate() {
	a.out.clean("")
	a.printBanner()
	a.out.clean("Gitsby is free, and built and maintained in spare time. A star or a mention")
	a.out.clean("helps other people find it. If it is saving you real time, sponsorship is")
	a.out.clean("welcome, and never expected.")
	a.out.clean("")
	a.out.clean("  " + donateURL)
	a.out.clean("")
}

func (a *app) printSyntax() {
	a.out.clean("")
	a.out.clean("Common commands:")
	a.out.clean("  pullcom [msg] ......: Pull updates, then commit all local changes. Do frequently!")
	a.out.clean("  br create <branch> .: Create a new branch off " + mergeTargetLabel + " (current work is carried or parked).")
	a.out.clean("  br switch [branch] .: Switch to a branch (parks current work first). No arg: back to " + mergeTargetLabel + ".")
	a.out.clean("  br [list] ..........: Fetch and list branches.")
	a.out.clean("  status .............: Fetch and show current status.")
	a.out.clean("One-time setup commands:")
	a.out.clean("  repo clone <url> ...: Clone a repo you don't have yet, into [dir] (checks out dev if it has one).")
	a.out.clean("  repo create <o/n> ..: Create GitHub repo 'owner/name' via gh, then connect this directory and push.")
	a.out.clean("  repo connect [url] .: Connect this directory to an existing empty remote, and push.")
	a.out.clean("  repo url [https|ssh]: Show how origin authenticates, or switch it between the two.")
	a.out.clean("  account [list] .....: Show your configured GitHub accounts, and which one this folder uses.")
	a.out.clean("  account set ........: Set one key of one account, e.g. 'account set work host gitea.com'.")
	a.out.clean("  account apply ......: Teach plain git the same folder rules, so 'git' outside gitsby matches.")
	a.out.clean("Less common commands:")
	a.out.clean("  sync [msg] .........: Pull, commit, and push (pullcom, plus the push). Do infrequently.")
	a.out.clean("  whoami .............: Show account, ssh key, commit author, git host login.")
	a.out.clean("Admin commands, e.g. for small solo projects:")
	a.out.clean("  br merge [msg] .....: Merge current branch into " + mergeTargetLabel + " (--no-ff), push, delete it local + remote.")
	a.out.clean("  br prune ...........: Delete branches already merged into " + mergeTargetLabel + ", local + remote.")
	a.out.clean("  br hotfix <name> ...: Branch off the default branch, to correct what's already published.")
	a.out.clean("  pr [create|n|ok n] .: Create, list, review, or accept a pull request (gh on GitHub, tea on Gitea).")
	a.out.clean("  release [ver] ......: Cut a release: merge dev into main, tag, push. No ver: next after latest tag.")
	a.out.clean("For scripts:")
	a.out.clean("  raw git <args> .....: Run git as the account this folder belongs to. Everything after 'git' is git's.")
	a.out.clean("  raw gh <args> ......: The same, for gh.")
	a.out.clean("Options:")
	a.out.clean("  -m, --message MSG ....: Commit or merge message (or give it positionally).")
	a.out.clean("  -q, --quiet, -y ......: Assume yes - no prompts; if committing with no message, one is generated.")
	a.out.clean("  --public / --private .: Visibility for the repo 'repo create' makes (default: private).")
	a.out.clean("  --any-identity .......: Act as gh's active account, and proceed when it differs from the remote's ssh key.")
	a.out.clean("  --no-fetch ...........: Skip the pre-command fetch, and the pull. (Pushes still go out.)")
	a.out.clean("  --config FILE ........: Read accounts from FILE instead of the usual config location.")
	a.out.clean("  -h, --help  /  -v, --version  /  --about  /  --donate")
	a.out.clean("")
}

func (a *app) printHelp() {
	a.printCopyright()
	a.printBlurb()
	a.printSyntax()
}

// printBanner names the build every command's output came from, so a bug report
// can say which one. Skipped under -q, which is the machine-readable mode, and
// never reached by 'raw' - that hands stdout straight back to the caller.
func (a *app) printBanner() {
	if a.opt.sawQuiet {
		return
	}
	a.out.cleanf("%s %s", meName, versionText())
	a.out.clean("")
}
