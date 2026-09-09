// The state display: the status block, the identity block, and the capped lists
// under them. What these print is what the user reads before saying yes, so every
// line either states something verified or says "unknown" - never a guess.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// showList indents and prints a command's output, truncated to the terminal so
// nothing wraps and capped so a huge working tree can't scroll the prompt
// off-screen - the 'less -FX' idea without a pager.
func (a *app) showList(name string, args ...string) {
	var outLines []string
	if out, _ := exec.Command(name, args...).Output(); len(out) > 0 {
		outLines = strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	}
	a.showLines(outLines)
}

// terminalWidth: asked once. Every capped list was spawning its own tput, and
// measuring twice in one run would only let the plan and the after-shot wrap
// differently.
func (a *app) terminalWidth() int {
	return a.termWidth.get(func() int {
		const fallback = 100
		if !isTTY(os.Stdout) || !inPath("tput") {
			return fallback
		}
		if w, err := strconv.Atoi(runOut("tput", "cols")); err == nil && w >= 40 {
			return w
		}
		return fallback
	})
}

// showLines is the same treatment for lines we already hold.
func (a *app) showLines(outLines []string) {
	const maxLines = 25
	termWidth := a.terminalWidth()
	shown := 0
	for _, line := range outLines {
		if shown >= maxLines {
			break
		}
		if r := []rune(line); len(r) > termWidth-4 {
			line = string(r[:termWidth-7]) + "..."
		}
		a.out.clean("    " + line)
		shown++
	}
	if len(outLines) > shown {
		a.out.cleanf("    ... and %d more", len(outLines)-shown)
	}
	a.lastListCount = len(outLines)
}

// showChanges: short form on purpose - git status's long form buries the file
// list under paragraphs of hints.
func (a *app) showChanges() {
	a.out.clean("Local changes:")
	a.showList("git", "status", "--short")
	if a.lastListCount == 0 {
		a.out.clean("    (working tree clean)")
	}
}

// showIncoming is the other half of "what's going to change": what a pull would
// bring down on top of your work.
func (a *app) showIncoming() {
	if !a.hasUpstream() {
		return
	}
	_, behind := a.aheadBehind()
	if behind == 0 {
		return
	}
	a.out.clean("")
	a.out.cleanf("Incoming (%d commit(s) to pull):", behind)
	a.showList("git", "diff", "--name-status", "HEAD..@{u}")
}

// identityWillPrint: whether this run reaches showIdentity at all. Every mutating
// command previews the block, bar 'account apply', which shows the account list
// instead; among the read-only ones only status and whoami do. It gates the live
// probes that feed the block and nothing else, so being over-broad costs a round
// trip and never an answer.
func (a *app) identityWillPrint() bool {
	if a.cmd.name == "account-apply" || a.cmd.name == "account-set" {
		return false
	}
	if a.cmd.mutating {
		return true
	}
	return a.cmd.name == "status" || a.cmd.name == "whoami"
}

// showIdentity: who a remote-touching command will act as. Host aliases in
// ~/.ssh/config hide this, and with more than one account configured it is easy
// to push as the wrong person.
func (a *app) showIdentity(remoteURL string) {
	a.showAccountLine()
	// A key nothing reads is how you end up acting as the wrong account while
	// believing you configured it, so say so - once, here, rather than failing or
	// staying quiet.
	if len(a.cfg.unknown) > 0 {
		a.out.clean("Config .......: " + a.cfg.file + " - ignored: " + strings.Join(a.cfg.unknown, ", "))
	}
	a.showSSHLine(remoteURL)
	a.out.clean("Author .......: " + commitIdentity())
	a.showGhLine()
	a.showForgeLine()
}

// showForgeLine is the gh line's counterpart for every host gh does not serve.
// Without it a Gitea repo had no answer at all to the question this whole block
// exists for - the identity display quietly stopped covering the case rather than
// saying it couldn't, which is the one thing it is not allowed to do.
func (a *app) showForgeLine() {
	host := a.originHost()
	if host == "" || isGitHubHost(host) {
		return
	}
	tool, cli := a.originTool()
	line := host
	switch {
	case tool == toolNone:
		line += " - no CLI installed for it here, so git works and pull requests don't"
	case a.isOffline():
		line += " (" + cli + ") - offline, so who it acts as is unknown"
	default:
		who := a.forgeLogin(cli, host)
		if who == "" {
			who = "unknown - '" + cli + " login add' has no login for this host"
		}
		line += " (" + cli + "): " + who
		// Only a write can act as the wrong account, so only a write gets the
		// comparison - the same rule the gh line above follows, and the reason this
		// block exists at all rather than just naming the host.
		if a.gh.isWrite {
			keyWho := a.sshLogin(a.gh.probeURL)
			if identityMismatchText(cli, who, keyWho) != "" {
				line += "  <-- NOT the ssh key's account ('" + keyWho + "')"
			} else if keyWho == "?" {
				line += " (no ssh identity to compare)"
			}
		}
	}
	a.out.clean("Git host .....: " + line)
}

// accountDecidedSomething: whether the account resolution actually changed how
// this run behaves - asked for or configured, not merely inferred. A single-account
// machine must never learn the feature exists.
func (a *app) accountDecidedSomething() bool {
	return a.acct.explicit || a.acct.name != "" || a.acct.switchedFrom != "" ||
		a.acct.usedHTTPSAuth || a.acct.usedSSHKey != "" || a.acct.usedIdentity
}

// acctLabel and acctCont are the Account block's first-line and continuation
// prefixes. Same width, so an explanation lines up in a column under the answer
// instead of wrapping wherever the terminal happens to end.
const (
	acctLabel = "Account ......: "
	acctCont  = "              : "
)

// dirLabel is the current-directory line, shared by every command that prints one
// so the tool cannot end up calling the same thing two names on two screens.
const dirLabel = "Current dir ..: "

// accountFile names the accounts file, for advice that tells somebody to edit it.
// The discovered path where there is one, the default location where there isn't:
// "add a line to your config" is not advice until it says which file.
func (a *app) accountFile() string {
	if a.cfg.file != "" {
		return displayPath(a.cfg.file)
	}
	if d := defaultConfigFile(); d != "" {
		return displayPath(d)
	}
	return "~/.config/gitsby/config.shcl"
}

// accountFileRef points a fix at the accounts file in whichever way costs the
// reader least: the line above where the From block has already named it, the line
// below where showAccountFix is about to.
func (a *app) accountFileRef() string {
	if a.acct.fromFile {
		return "the file above"
	}
	return "the file below"
}

// accountSubject names the account a note is about, in whatever terms the config
// actually gave it: the login where one is known, otherwise the account's own name,
// which is the thing the reader has to go and edit. The old "(no login named)"
// named neither.
func (a *app) accountSubject() string {
	if who := a.accountWho(a.accountHost()); who != "" {
		return who
	}
	if a.acct.name != "" {
		return "'" + a.acct.name + "'"
	}
	return "the account asked for"
}

// accountSourceText says where this run's account came from, in terms somebody can
// go and look at. "(from config 'acme')" named neither the file nor which config -
// and there are two configs in play here, since 'gitsby.ghAccount' is a git config
// key and the account blocks are not. withFile spells out the accounts file too,
// for the one caller that has not already put it on screen.
func (a *app) accountSourceText(withFile bool) string {
	if a.acct.fromFile && withFile {
		return a.acct.source + " in " + a.accountFile()
	}
	return a.acct.source
}

// showAccountFrom names where the account came from, and which file that is, under
// the line they explain. Their own lines rather than a parenthetical: the honest
// answer names a path, and a path is what makes a line wrap. Printed even when the
// source repeats the name on the line above - what the reader is missing there is
// not the string, it is what KIND of thing the string is and who chose it.
func (a *app) showAccountFrom() {
	if a.acct.source == "" {
		return
	}
	from := upperFirst(a.acct.source)
	if a.acct.pickedBy != "" {
		from += ", because " + a.acct.pickedBy
	}
	a.showAccountNote("From", from+".")
	if a.acct.fromFile {
		a.showAccountNote("File", a.accountFile())
	}
}

// upperFirst capitalizes a sentence built from a fragment, so every note under the
// Account line starts like a sentence whichever fragment it was assembled from.
// Left alone where the first character is not a letter: '--any-identity' and a
// config key are spelled the way you type them.
func upperFirst(text string) string {
	if text == "" || text[0] < 'a' || text[0] > 'z' {
		return text
	}
	return string(text[0]-32) + text[1:]
}

// showAccountNote prints one labeled explanation under the Account line, wrapped at
// a fixed column rather than at whatever the terminal happens to be. A line given
// with a leading indent is a literal - a config line to type - and is printed as it
// stands, since wrapping one would make it wrong.
func (a *app) showAccountNote(label string, lines ...string) {
	const labelWidth, bodyWidth = 4, 56 // 'Kept', the longest label; 78 columns in all
	head := label + ":" + strings.Repeat(" ", labelWidth-len(label)) + " "
	pad := strings.Repeat(" ", len(head))
	prefix := head
	for _, line := range lines {
		if strings.HasPrefix(line, " ") {
			a.out.clean(acctCont + pad + line)
			continue
		}
		for _, wrapped := range wrapWords(line, bodyWidth) {
			a.out.clean(acctCont + prefix + wrapped)
			prefix = pad
		}
	}
}

// showAccountFix prints the edit that repairs the account. The file to make it in
// goes on its own line, because a path is the one thing here that can be
// arbitrarily long - unless the From line above already named it, which it does
// whenever the account came out of that same file.
func (a *app) showAccountFix(lines ...string) {
	a.showAccountNote("Fix", lines...)
	if !a.acct.fromFile {
		a.showAccountNote("File", a.accountFile())
	}
}

// showAccountKept says which parts of the account took effect anyway. The ssh key
// and the commit identity are applied outside the credential decision, so a flat
// "NOT applied" contradicted the SSH and Author lines printed directly under it -
// the exact confusion this block exists to prevent.
func (a *app) showAccountKept() {
	var parts, lines []string
	if a.acct.usedSSHKey != "" {
		parts, lines = append(parts, "SSH key"), append(lines, "SSH")
	}
	if a.acct.usedIdentity {
		parts, lines = append(parts, "commit identity"), append(lines, "Author")
	}
	if len(parts) == 0 {
		return
	}
	// Named one at a time. Pointing at "the SSH and Author lines" when only the
	// identity applied sent the reader looking for an SSH line that is not printed
	// at all, which reads as a second thing gone wrong.
	tail := " line below comes from."
	if len(lines) > 1 {
		tail = " lines below come from."
	}
	a.showAccountNote("Kept", "Its "+strings.Join(parts, " and ")+
		" still applied - that is where the "+strings.Join(lines, " and ")+tail)
}

// showAccountUnapplied covers the cases where the account did not authenticate this
// run, and reports whether it printed. Separate from the applied line because the
// two answer different questions: the applied line says who, and this says what
// happened instead, why, and what to type to fix it. One line carries the first.
// It cannot carry the other three, and the attempt read as a paragraph.
func (a *app) showAccountUnapplied() bool {
	switch {
	case a.acct.bypassed:
		a.out.clean(acctLabel + "nothing applied - " + meName + " was run with --any-identity")
		a.showAccountNote("Why", "--any-identity leaves the token, the SSH key and the commit author exactly as they already were.")
	case a.acct.otherHost:
		a.out.clean(acctLabel + a.accountSubject() + a.noTokenText())
		a.showAccountFrom()
		a.showAccountOtherHost()
	case a.acct.noToken:
		a.out.clean(acctLabel + a.accountSubject() + a.noTokenText())
		a.showAccountFrom()
		a.showAccountNoToken()
	default:
		return false
	}
	return true
}

// noTokenText says what did not happen, in terms that answer WHICH token and
// applied to WHAT. Naming the host is most of that answer - but a remote whose host
// cannot be named still reaches here, and forgeName() stands in "origin" for it,
// which reads as a host called origin. Say less rather than something untrue.
func (a *app) noTokenText() string {
	if host := a.originHost(); host != "" {
		return " - no access token used for " + host
	}
	return " - no access token used"
}

// showAccountOtherHost explains an account whose credentials bank somewhere other
// than where this remote lives. Three different mistakes end up here and they have
// three different fixes, so they get three different notes - said in one wording,
// they sent people hunting through the config for a line that was never there.
func (a *app) showAccountOtherHost() {
	host := a.forgeName()
	switch {
	case a.acct.name == "":
		a.showAccountNote("Why", "Nothing says which git host the login '"+a.acct.ghWho+
			"' belongs to, and a login with no host named is taken to be a github.com one. This repo's origin is at "+
			host+", and a token issued by one host is no use at another.")
		a.showAccountKept()
		a.showAccountFix("Declare an account for "+host+" in "+a.accountFileRef()+
			", then name that one here. To start one:",
			"  "+meName+" account set <name> host "+host)
	case a.cfg.value(a.acct.name, "host") == "":
		// An account that never named a host is TAKEN to be a github.com one, for the
		// configs written before the key existed. Said in the same words as a host
		// somebody actually typed, it sends them looking for a line that isn't there.
		a.showAccountNote("Why", "That block doesn't say which git host it is for, and a block that doesn't say is taken to be a github.com one. This repo's origin is at "+
			host+", and a token issued by one host is no use at another.")
		a.showAccountKept()
		a.showAccountFix("Run this:",
			"  "+meName+" account set "+a.acct.name+" host "+host)
	default:
		a.showAccountNote("Why", "That block is declared for "+a.accountHost()+
			", and this repo's origin is at "+host+". A token issued by one host is no use at another.")
		a.showAccountKept()
		a.showAccountFix("Name an account declared for "+host+" here, or move this one to that host:",
			"  "+meName+" account set "+a.acct.name+" host "+host)
	}
}

// showAccountNoToken explains the account gitsby resolved but holds no credential
// for. gh is what goes on acting as itself where gh is the tool; anywhere else there
// is no second identity to fall back to, and git pushes with whatever it already had.
func (a *app) showAccountNoToken() {
	who := a.accountSubject()
	if isGitHubHost(a.accountHost()) {
		a.showAccountNote("Why", "An account is applied by handing git and gh its access token, and "+meName+
			" holds none here for "+who+". gh goes on acting as whichever account it is logged in as.")
		a.showAccountKept()
		if a.acct.name == "" {
			a.showAccountNote("Fix", "Run 'gh auth login' as "+who+".")
			return
		}
		a.showAccountFix("Run 'gh auth login' as "+who+", or point this block at a file holding its token:",
			"  "+meName+" account set "+a.acct.name+" tokenFile <file>")
		return
	}
	a.showAccountNote("Why", "An account is applied by handing git its access token, and "+meName+
		" holds none here for "+who+". Git authenticates however it already would, usually with an SSH key.")
	a.showAccountKept()
	if a.acct.name == "" {
		return
	}
	a.showAccountFix("Point this block at a file holding a "+a.accountHost()+" token for it:",
		"  "+meName+" account set "+a.acct.name+" tokenFile <file>")
}

// showAccountLine leads the block, because it explains the lines under it: the key
// on the SSH line and the name on the Author line can both be its doing.
func (a *app) showAccountLine() {
	if !a.accountDecidedSomething() {
		return
	}
	if !a.showAccountUnapplied() {
		a.showAccountApplied()
	}
	if a.acct.looseTokenFile != "" {
		a.out.clean(acctCont + "WARNING: " + a.acct.looseTokenFile + " is readable by other users on this machine; chmod 600 it.")
	}
	// This repo could authenticate with the account's token instead of a key, and
	// doesn't. Worth one line, because it is the whole point of configuring accounts
	// this way - and setting 'protocol = ssh' answers the question, so nobody hears
	// it twice.
	if a.convertibleToHTTPS() {
		a.out.clean(acctCont + "origin still uses ssh; '" + meName + " repo url https' switches it to this account's token.")
	}
}

// accountFallbackNote says what happens instead when an account names no login:
// whichever forge CLI serves the account's own host goes on using its own. Named
// only where there is one to name - asserting gh on a Gitea host is the same
// mistake as assuming every account is a GitHub one.
func (a *app) accountFallbackNote() string {
	if _, tool := a.forgeToolFor(a.accountHost()); tool != "" {
		return ", so " + tool + " keeps its own account"
	}
	return ""
}

// showAccountApplied names who this run acts as, for the ordinary case where the
// account did take effect.
func (a *app) showAccountApplied() {
	// The login the account claims on its OWN host, not 'ghAccount' alone. Reading
	// only the GitHub field reported every Gitea account as "(no GitHub account
	// named)" - true, and no answer at all to the question this line asks.
	line := a.accountSubject()
	if a.accountWho(a.accountHost()) == "" {
		// It applied its key and its commit identity and simply names no login of its
		// own - which is a whole way of holding a second account, not a broken one.
		line += " - it names no login" + a.accountFallbackNote()
	}
	// The one thing the lines below can't show: an https push authenticating with
	// the token rather than with a key, which is what makes a second account work
	// with no ssh setup.
	if a.acct.usedHTTPSAuth {
		line += ", git over https"
	}
	a.out.clean(acctLabel + line)
	a.showAccountFrom()
	switch {
	case a.acct.tokenWho == "?":
		a.showAccountNote("Note", "gh is unreachable or not installed here, so the token could not be checked against the account it claims.")
	case a.acct.tokenWho != "" && a.acct.tokenWho != a.acct.ghWho:
		a.showAccountNote("Warn", "its token file authenticates as '"+a.acct.tokenWho+
			"', so that is who anything pushed from here goes out as.")
	}
}

// sshConfig is what 'ssh -G' says about a target: who it would connect as, where,
// and with which key.
type sshConfig struct {
	user, host, keyFile string
}

// readSSHConfig probes the connect target, not the bare host. Without a user,
// 'ssh -G' answers with the local login name - neither who we connect as nor the
// account we act as, and on a personal box it looks plausible enough to be
// believed. '--': an option-shaped host must not parse as an option.
func readSSHConfig(target string) sshConfig {
	var cfg sshConfig
	out, _ := exec.Command("ssh", "-G", "--", target).Output()
	for _, line := range splitLines(string(out)) {
		key, value, found := strings.Cut(line, " ")
		if !found || value == "" {
			continue
		}
		switch key {
		case "user":
			if cfg.user == "" {
				cfg.user = value
			}
		case "hostname":
			if cfg.host == "" {
				cfg.host = value
			}
		case "identityfile":
			if cfg.keyFile == "" {
				if isReadableFile(expandTilde(value)) {
					cfg.keyFile = value
				}
			}
		}
	}
	return cfg
}

func (a *app) showSSHLine(remoteURL string) {
	hostAlias := sshTarget(remoteURL)
	if hostAlias == "" || !inPath("ssh") {
		return
	}
	ssh := readSSHConfig(sshConnectTarget(remoteURL))
	// An '-i' in git's own ssh command outranks whatever ssh -G nominated: that is
	// the key git hands ssh, and with IdentitiesOnly set ssh_config's candidates
	// never get a look in. Without this the line can name the right account beside
	// the wrong key file, which is worse than either alone - it invites you to
	// trust the half that happens to be wrong.
	fields := strings.Fields(a.gitSSHCommand())
	for i, arg := range fields {
		if arg == "-i" && i+1 < len(fields) {
			ssh.keyFile = fields[i+1]
		}
	}
	if ssh.host == "" {
		return
	}
	if ssh.user == "" {
		ssh.user = "?"
	}
	line := ssh.user + "@" + ssh.host
	if hostAlias != ssh.host {
		line += " via alias '" + hostAlias + "'"
	}
	if ssh.keyFile != "" {
		line += ", key " + nativePath(ssh.keyFile)
	}
	// Neither half above answers the question this line exists for: the connect
	// user is 'git' for every GitHub account, and the key is only ssh's first
	// readable candidate, not necessarily the one that authenticates. So ask the
	// host who we actually are. Offline it stays unknown - the fetch already said why.
	account := "unknown"
	if !a.isOffline() {
		if resolved := a.sshLogin(remoteURL); resolved != "?" {
			account = resolved
		}
	}
	a.out.clean("SSH ..........: " + account + " (" + line + ")")
}

// showGhLine: gh-backed commands act as gh's account, not the ssh key's - so name
// it where it applies.
func (a *app) showGhLine() {
	if !a.gh.isCommand || a.gh.tool != toolGh {
		return
	}
	ghWho := a.ghLogin()
	line := ghWho
	if ghWho == "?" {
		line = "(unknown - gh not logged in, or offline)"
	}
	// An account we picked for this remote is still a change of who you act as.
	// Say it here, in the block you read before confirming, rather than let it look
	// like it was already active.
	if a.acct.switchedFrom != "" {
		line += " (selected here; gh's active account is '" + a.acct.switchedFrom + "')"
	}
	// Only a write can act as the wrong account, so only a write gets the
	// comparison. The round trip behind it is the one the SSH line above already
	// made.
	if a.gh.isWrite {
		keyWho := a.sshLogin(a.gh.probeURL)
		if identityMismatchText("gh", ghWho, keyWho) != "" {
			line += "  <-- NOT the ssh key's account ('" + keyWho + "')"
		} else if keyWho == "?" {
			line += " (no ssh identity to compare)"
		}
	}
	a.out.clean("GitHub (gh) ..: " + line)
}

// cmdWhoami is the identity block on its own - the same lines 'status' prints,
// without the branch and working-tree state, for when the only question is who
// the next command acts as. Directory and remote lead it because they are what
// decides the answer.
func (a *app) cmdWhoami() {
	remoteURL := a.originURL()
	remoteDisp := maskURL(remoteURL)
	if remoteDisp == "" {
		remoteDisp = "(none)"
	}
	// A cwd nothing can name prints as empty; not worth stopping a display over.
	wd, _ := os.Getwd()
	a.out.clean("")
	a.out.clean(dirLabel + wd)
	a.out.clean("Remote .......: " + remoteDisp)
	a.showIdentity(remoteURL)
	a.out.resetBlank()
}

// showStatus prints the state block. withIdentity: also show who we'll be on the
// remote - pre-flight and 'status', but not the after-shot.
func (a *app) showStatus(withIdentity bool) {
	remoteURL := a.originURL()
	remoteDisp := maskURL(remoteURL)
	if remoteDisp == "" {
		remoteDisp = "(none)"
	}
	a.out.clean("")
	// Same as cmdWhoami: an unnameable cwd prints as empty rather than refusing.
	wd, _ := os.Getwd()
	a.out.clean(dirLabel + wd)
	a.out.clean("Remote .......: " + remoteDisp)
	if withIdentity {
		a.showIdentity(remoteURL)
	}
	// Say "unknown" rather than assert a name we couldn't resolve - this is the one
	// command that still runs when the default branch can't be told, so it must not
	// fabricate one.
	dflt := a.defaultBranch()
	if dflt == "" {
		dflt = "unknown"
	}
	a.out.clean("Default branch: " + dflt)
	a.out.clean("Current branch: " + strings.TrimRight(a.branchDisp("")+" "+a.branchSync(), " "))
	// Pre-flight only, and only for the two commands that make a branch: the line
	// above is where you ARE, which is exactly what misled here - it says 'dev'
	// while the plan checks out main.
	if withIdentity {
		switch a.cmd.name {
		case "br-create":
			a.out.clean("New branch ...: " + a.mergeTarget() + " :: " + a.cmd.arg)
		case "br-hotfix":
			a.out.clean("New branch ...: " + a.defaultBranch() + " :: " + a.cmd.arg)
		}
	}
	a.out.clean("")
	a.showChanges()
	if withIdentity {
		a.showIncoming()
	}
	a.out.resetBlank()
}
