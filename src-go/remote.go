// The remote's side of things: ssh host and identity probing, the pre-command
// fetch, and which transport a remote should use. Offline is a STATE the fetch
// discovers, never a flag.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"regexp"
	"strings"
)

// origin's url, asked once. A preview alone wanted it half a dozen times, and it
// can only change through a step, which forgets it - so the after-shot still
// reads what the step left behind. Not for another repo: '-C <dir>' asks about a
// different origin and must go direct.
func (a *app) originURL() string {
	return a.git.originURL.get(func() string { return runOut("git", "remote", "get-url", "origin") })
}

// hasOrigin: there is a remote called origin. get-url printing nothing and
// get-url failing are the same answer.
func (a *app) hasOrigin() bool { return a.originURL() != "" }

// coreSSHCommand: git's configured ssh command, read once - the account selector
// and every ssh probe ask for the same value.
func (a *app) coreSSHCommand() string {
	return a.git.coreSSHCommand.get(func() string { return runOut("git", "config", "--get", "core.sshCommand") })
}

// identityMismatchText says why the two identities disagree, or nothing. Only a
// mismatch both sides KNOW about counts: '?' on either side means we couldn't
// tell, which is not the same as being wrong. The tool is named rather than
// assumed - a message about what 'gh' is doing, printed for a run going through
// tea, sends you to check an account that had nothing to do with it.
func identityMismatchText(cli, forgeWho, sshWho string) string {
	if cli == "" {
		cli = "the host's CLI"
	}
	if forgeWho == "" {
		forgeWho = "?"
	}
	if sshWho == "" {
		sshWho = "?"
	}
	if forgeWho == "?" || sshWho == "?" || forgeWho == sshWho {
		return ""
	}
	return cli + " acts as '" + forgeWho + "', but this remote's key authenticates as '" + sshWho + "'."
}

// sshTarget is the host to ask ssh about, pulled out of a remote URL. Empty for
// https and local-path remotes - and for a Windows drive path, which is not
// 'host:path' however much it looks like one.
func sshTarget(url string) string {
	switch {
	case strings.HasPrefix(url, "ssh://"):
		host := url[len("ssh://"):]
		if i := strings.Index(host, "/"); i >= 0 {
			host = host[:i]
		}
		if at := strings.LastIndex(host, "@"); at >= 0 {
			host = host[at+1:]
		}
		if c := strings.Index(host, ":"); c >= 0 {
			host = host[:c]
		}
		return host
	case strings.Contains(url, "://"): // https/git/file: no ssh identity involved
		return ""
	case isDrivePath(url):
		return ""
	}
	// scp-like: [user@]host:path.
	c := strings.Index(url, ":")
	if c < 1 {
		return ""
	}
	host := url[:c]
	if at := strings.LastIndex(host, "@"); at >= 0 {
		host = host[at+1:]
	}
	return host
}

// sshConnectTarget is the '[user@]host' to actually connect to, so an explicit
// user in the remote URL is honored. sshTarget returns the bare host, which is
// the alias to name in the display.
func sshConnectTarget(url string) string {
	host := sshTarget(url)
	if host == "" {
		return ""
	}
	user := ""
	switch {
	case strings.HasPrefix(url, "ssh://") && strings.Contains(url, "@"):
		user = url[len("ssh://"):]
		user = user[:strings.Index(user, "@")]
	case strings.Contains(url, "://"):
	default:
		if at := strings.Index(url, "@"); at >= 0 && strings.Contains(url[at:], ":") {
			user = url[:at]
		}
	}
	if user != "" {
		return user + "@" + host
	}
	return host
}

// gitSSHCommand is the ssh command git itself would run, so probes ask as the key
// git actually pushes with. Without this a per-repo 'core.sshCommand' (the usual
// way to hold two GitHub accounts on one box) is invisible: the probe answers
// with the default key's account while git pushes as someone else - and two wrong
// halves that happen to agree read as a clean bill of health. Precedence is git's
// own: GIT_SSH_COMMAND beats core.sshCommand. Split, never shelled - a config
// value is not a place to run shell - so a quoted path degrades to a plain 'ssh'
// probe (which answers for the default key, and a wrong '?' is safer than a wrong
// name) rather than misparse.
func (a *app) gitSSHCommand() string {
	cmd := os.Getenv("GIT_SSH_COMMAND")
	if cmd == "" {
		cmd = a.coreSSHCommand()
	}
	if cmd == "" || strings.ContainsAny(cmd, `"'`) {
		return "ssh"
	}
	return cmd
}

// remoteEnv is the environment every command that reaches origin runs under: no
// auth prompts (this happens before our own checks, so an https remote we can't
// authenticate to would stop and ask for a username mid-command), and a connect
// timeout on the ssh side so a dead remote can't hang for minutes. The timeout
// composes onto whatever ssh command git would use, INCLUDING the one the account
// selector set from a config sshKey - gating on the variable merely being present
// dropped the timeout for exactly the multi-account setups it was written for.
// A GIT_SSH_COMMAND the caller chose is left alone.
func (a *app) remoteEnv() []string {
	env := append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	if !a.userSSHCommand {
		env = append(env, "GIT_SSH_COMMAND="+a.gitSSHCommand()+" -o ConnectTimeout=3")
	}
	return env
}

// The greeting each forge answers an ssh -T with. GitHub says 'Hi <user>!';
// Gitea (and Forgejo, which kept the wording) says 'Hi there, <user>!' - close
// enough to look handled by the first pattern and different enough not to be, so
// the identity line read 'unknown' on every Gitea remote while looking correct.
var sshGreetingREs = []*regexp.Regexp{
	regexp.MustCompile(`^Hi ([A-Za-z0-9_.:/-]+)!`),
	regexp.MustCompile(`^Hi there, ([A-Za-z0-9_.-]+)!`),
}

// sshLogin names the account this remote's ssh key authenticates as. GitHub
// answers 'Hi <user>!' and always exits 1, so parse the greeting, not the status.
// BatchMode + a connect timeout: never prompt, never hang. '?' for https/local
// remotes, no agent, or anything else unresolvable - and a deploy key answers
// with a repo name, which simply won't match any login. Unknown is not wrong.
func (a *app) sshLogin(url string) string {
	if who, asked := a.gh.sshLogins[url]; asked {
		return who
	}
	who := probeSSHLogin(url, a.gitSSHCommand())
	if a.gh.sshLogins == nil {
		a.gh.sshLogins = map[string]string{}
	}
	a.gh.sshLogins[url] = who
	return who
}

func probeSSHLogin(url, sshCommand string) string {
	target := sshConnectTarget(url)
	if target == "" || !inPath("ssh") {
		return "?"
	}
	sshCmd := strings.Fields(sshCommand)
	args := append(sshCmd[1:], "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=3", "--", target)
	// Both streams: ssh writes host-key and missing-identity warnings ahead of the
	// greeting, so it is not reliably the first line - anchoring to the whole output
	// answered '?' for exactly the multi-key setups this exists for.
	out, _ := exec.Command(sshCmd[0], args...).CombinedOutput()
	for _, line := range splitLines(string(out)) {
		for _, greeting := range sshGreetingREs {
			if m := greeting.FindStringSubmatch(line); m != nil {
				return m[1]
			}
		}
	}
	return "?"
}

// fetchRemote fetches with --prune (stale origin/* refs would fool the existence
// checks) and heals origin/HEAD (missing on git < 2.47, stale after an upstream
// default-branch rename). ssh gets a connect timeout so a dead remote can't hang
// every command for minutes; https relies on git's own timeouts. Never clobbers a
// user-set GIT_SSH_COMMAND, and never prompts for auth - this runs before any of
// our own checks, so an https remote we can't authenticate to would stop and ask
// for a username mid-command.
func (a *app) fetchRemote() {
	// The one thing that moves a ref without being a step, so the runners' own
	// invalidation never covers it. Only the counted answer: a fetch moves
	// origin/*, which is half of ahead-behind, and leaves everything else the run
	// has settled exactly where it was.
	a.git.aheadBehind.forget()
	env := a.remoteEnv()
	// Named, not implied: a bare 'git fetch' follows the current branch's own
	// tracking remote, and every existence check afterwards reads origin.
	fetch := exec.Command("git", "fetch", "--quiet", "--prune", "origin")
	fetch.Env = env
	if fetch.Run() != nil {
		a.gh.reachable = false
		a.out.status("WARNING: git fetch failed (offline?); remote info may be stale.")
		return
	}
	// Healing queries the remote again, so only when there is nothing to read:
	// git < 2.47 never wrote one. A ref left stale by an upstream rename survives,
	// and main already refuses naming the fix.
	if !runOK("git", "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD") {
		setHead := exec.Command("git", "remote", "set-head", "origin", "--auto")
		setHead.Env = env
		_ = setHead.Run()
	}
}

// isOffline: set by the pre-command fetch, which is the only thing that actually
// asks origin. --no-fetch is NOT offline: it declines the incoming round trip,
// and pushes still go out.
func (a *app) isOffline() bool { return !a.gh.reachable }

// ghProtocol: which transport gh hands to git for github.com ('ssh' or 'https').
// Host-specific, not the global default - they can disagree, and the host one is
// what github.com operations use. Only asked for a host gh actually serves: gh's
// preference says nothing about somebody else's forge, and asking it anyway spends
// a process to mis-answer a question about a machine gh has never heard of.
func (a *app) ghProtocol(host string) string {
	if !isGitHubHost(host) {
		return "https"
	}
	return a.gh.protocol.get(func() string {
		if inPath("gh") && runOut("gh", "config", "get", "-h", host, "git_protocol") == "ssh" {
			return "ssh"
		}
		return "https"
	})
}

// preferredProtocol: which transport a remote we set should use. The config file
// wins because that is where the accounts live, and choosing https there is what
// makes a second account work with no ssh key at all; gh's own setting is the
// answer when nothing says otherwise, so an unconfigured machine behaves exactly
// as it did before any of this existed.
func (a *app) preferredProtocol() string {
	return a.protocolFor(a.originHost())
}

// protocolFor is the same question about a named host, for the commands settling a
// remote they do not have yet - a clone's URL and a connect's target name their own
// host, and it need not be the one the current directory sits on.
func (a *app) protocolFor(host string) string {
	proto := a.cfg.value(a.acct.name, "protocol")
	if proto == "" {
		proto = a.cfg.values["protocol"]
	}
	switch strings.ToLower(proto) {
	case "https", "ssh":
		return strings.ToLower(proto)
	}
	return a.ghProtocol(host)
}

// remoteTarget: 'owner/name' out of any remote URL, or nothing. Used to re-spell
// a remote in the other transport without asking the network - which is pure text
// work on any host, and was refused everywhere but github.com for no better reason
// than that the parser behind it only knew the one.
func remoteTarget(url string) string { return parseRemote(url).target() }

// convertibleToHTTPS is true when this repo is on ssh but the account it belongs
// to could authenticate with a token instead - the one case where saying so is
// worth a line. Someone who set 'protocol = ssh' has answered the question
// already, and hears nothing.
func (a *app) convertibleToHTTPS() bool {
	if a.acct.name == "" || a.preferredProtocol() != "https" {
		return false
	}
	url := a.originURL()
	if sshTarget(url) == "" || remoteTarget(url) == "" {
		return false
	}
	// The token has to be one THIS host would accept. Offering to re-spell a Gitea
	// remote so it authenticates with a GitHub token is an invitation to break a
	// working repo, and the line reads as advice either way.
	if !a.accountServesHost(a.originHost()) {
		return false
	}
	// Only whether a token exists matters here; its source and any load complaint
	// belong to the identity block, which reports them itself.
	token, _, _ := a.accountToken(a.originHost())
	return token != ""
}
