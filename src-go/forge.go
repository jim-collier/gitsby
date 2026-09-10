// Which host a remote lives on, and which tool speaks to it. Everything that
// used to assume github.com asks here instead: git does the work wherever it can,
// and a host-specific CLI is reached for only once the host has been identified as
// one that CLI serves.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"strings"
	"unicode"
)

// remoteRef is a remote URL taken apart: where it lives and what it is called.
// Every field empty is the ordinary answer for a local path - a directory is a
// perfectly good remote, it just has no host to ask anything about.
type remoteRef struct {
	host  string // canonical hostname, after any ssh_config alias is resolved
	owner string
	name  string
}

// target is 'owner/name', or nothing when the URL carried only a host.
func (r remoteRef) target() string {
	if r.owner == "" || r.name == "" {
		return ""
	}
	return r.owner + "/" + r.name
}

// parseRemote splits a remote URL into host, owner and name. One parser for every
// caller: the three that grew separately agreed on github.com and on nothing else,
// which is exactly the asymmetry that hides until a second host shows up.
//
// An ssh_config alias is resolved for the ssh spellings only. An https host is
// written literally and ssh has no say in it, so asking would spend a process to
// be told what we were already looking at.
func parseRemote(url string) remoteRef {
	host, path, viaSSH := splitRemoteURL(url)
	if host == "" {
		return remoteRef{}
	}
	// A host gh already serves is a real hostname, not an alias, so asking ssh about
	// it spends a process to be told what we started with. That skip is why the
	// ordinary 'git@github.com:owner/name' remote costs no ssh call at all - dropping
	// it put one into the spawn count of every command on every GitHub repo.
	if viaSSH && !isGitHubHost(host) {
		host = resolveSSHHost(host)
	}
	ref := remoteRef{host: host}
	path = strings.TrimSuffix(strings.TrimSuffix(path, "/"), ".git")
	// Everything before the last segment is the owner: a Gitea instance served
	// under a subpath, and GitHub's own 'owner/name', both land here correctly.
	if slash := strings.LastIndex(path, "/"); slash > 0 {
		ref.owner, ref.name = path[:slash], path[slash+1:]
		// Only the segment immediately above the repo names the owner; anything
		// deeper is instance routing that says nothing about who owns this.
		if deeper := strings.LastIndex(ref.owner, "/"); deeper >= 0 {
			ref.owner = ref.owner[deeper+1:]
		}
	}
	return ref
}

// splitRemoteURL is the pure text half: the host as written, the path after it,
// and whether the spelling was one ssh would resolve an alias for. Kept apart from
// parseRemote so the alias lookup - the only part that costs a process - has one
// place it can be skipped.
func splitRemoteURL(url string) (host, path string, viaSSH bool) {
	switch {
	case strings.HasPrefix(url, "ssh://"):
		host, path, viaSSH = url[len("ssh://"):], "", true
	case isDrivePath(url):
		return "", "", false // a Windows drive path, not 'host:path'
	case len(url) > 0 && isLetter(url[0]) && strings.Contains(url, "://"):
		host = url[strings.Index(url, "://")+3:]
	default:
		// scp-like '[user@]host:path'. A colon at position zero is not a host.
		colon := strings.Index(url, ":")
		if colon < 1 {
			return "", "", false
		}
		host, path, viaSSH = url[:colon], url[colon+1:], true
		if at := strings.LastIndex(host, "@"); at >= 0 {
			host = host[at+1:]
		}
		return hostOrNothing(host, strings.TrimPrefix(path, "/"), viaSSH)
	}
	// The two '://' forms both carry the path after the first slash.
	if slash := strings.Index(host, "/"); slash >= 0 {
		host, path = host[:slash], host[slash+1:]
	}
	if at := strings.LastIndex(host, "@"); at >= 0 {
		host = host[at+1:]
	}
	if colon := strings.Index(host, ":"); colon >= 0 { // a port is not part of the name
		host = host[:colon]
	}
	return hostOrNothing(host, strings.TrimPrefix(path, "/"), viaSSH)
}

// hostOrNothing refuses a "host" no host could be: whitespace means some other
// colon-bearing string landed in the split, and "couldn't tell" (empty) is the
// honest answer rather than a name for rules to match against.
func hostOrNothing(host, path string, viaSSH bool) (string, string, bool) {
	if strings.ContainsFunc(host, unicode.IsSpace) {
		return "", "", false
	}
	return host, path, viaSSH
}

// githubHosts names the hosts gh is the right tool for. GH_HOST is how gh itself
// is pointed at an Enterprise instance, so a remote on that host is gh territory
// just as much as github.com is - and reading it here is what keeps Enterprise
// users out of the "not GitHub, so no pull requests" path they don't belong in.
func isGitHubHost(host string) bool {
	if host == "" {
		return false
	}
	if strings.EqualFold(host, "github.com") {
		return true
	}
	enterprise := os.Getenv("GH_HOST")
	return enterprise != "" && strings.EqualFold(host, enterprise)
}

// originRef is origin taken apart, asked once. The parse is cheap but the alias
// resolution behind it is a process, and half a dozen callers want the answer.
func (a *app) originRef() remoteRef {
	return a.git.originRef.get(func() remoteRef { return parseRemote(a.originURL()) })
}

// originHost is where origin lives, or nothing for a local path or no remote at all.
func (a *app) originHost() string { return a.originRef().host }

// onGitHub: this repo's origin is one gh serves. The single question every gh call
// site now asks - a gh that is installed and logged in still has no business being
// run against somebody else's forge, where at best it errors in its own vocabulary
// about a repo it was never looking at.
func (a *app) onGitHub() bool { return isGitHubHost(a.originHost()) }

// forgeName is how a host is referred to in a message. 'origin' when there is no
// host to name, so a sentence about it still reads.
func (a *app) forgeName() string {
	if host := a.originHost(); host != "" {
		return host
	}
	return "origin"
}

// teaNames: upstream installs Gitea's CLI as 'tea', and Debian ships the same
// program as 'tea-cli' because the name was already taken there. Looking for one
// spelling finds it on the machines that happen to use that one.
var teaNames = []string{"tea", "tea-cli"}

// teaCommand is Gitea's CLI as this machine spells it, or nothing when it isn't
// installed. Asked once: two LookPath calls per pr command, for an answer that
// cannot change mid-run.
func (a *app) teaCommand() string {
	return a.forge.tea.get(func() string {
		for _, name := range teaNames {
			if inPath(name) {
				return name
			}
		}
		return ""
	})
}

// forgeURL is the canonical URL for 'owner/name' on a host, in one of the two
// transports. The github.com-only version of this is what made 'repo url' - which
// only ever rewrites text - refuse to work on any other host.
func forgeURL(host, target, proto string) string {
	if host == "" || target == "" {
		return ""
	}
	if proto == "ssh" {
		return "git@" + host + ":" + target + ".git"
	}
	return "https://" + host + "/" + target + ".git"
}

// githubURL: the canonical github.com URL, for the commands that are about GitHub
// specifically rather than about whatever host this repo happens to use.
func githubURL(target, proto string) string { return forgeURL("github.com", target, proto) }

// forgeTool is which CLI, if any, speaks the API of the host origin lives on.
// Having none is not a failure in itself - it only becomes one for a command that
// needed it, which is where the message explaining it belongs.
type forgeTool int

const (
	toolNone forgeTool = iota
	toolGh
	toolTea
)

// forgeToolFor picks the CLI for a host. gh for GitHub and for nothing else: it is
// a GitHub client, and pointing it at somebody else's forge gets an error in
// GitHub's vocabulary about a repo it was never looking at. tea for any other host
// that has it installed - it is Gitea's client, and it says so itself when the host
// turns out not to be one.
func (a *app) forgeToolFor(host string) (forgeTool, string) {
	switch {
	case isGitHubHost(host):
		if inPath("gh") {
			return toolGh, "gh"
		}
	case host != "":
		if tea := a.teaCommand(); tea != "" {
			return toolTea, tea
		}
	}
	return toolNone, ""
}

// originTool is the same question about this repo, which is what every caller
// actually wants to know.
func (a *app) originTool() (forgeTool, string) { return a.forgeToolFor(a.originHost()) }

// forgeCLIHint names the tool a host needs and how to get it pointed at one, for
// the refusal that has to explain itself. Kept beside the picker so the two cannot
// drift into recommending different things.
func (a *app) forgeCLIHint() string {
	if isGitHubHost(a.originHost()) {
		return "Install gh (https://cli.github.com) and run 'gh auth login'."
	}
	return "Install Gitea's CLI (https://gitea.com/gitea/tea) and run 'tea login add'." +
		" Some distributions install it as 'tea-cli'; either name is found."
}

// forgeLogin names the account tea holds for a host, or nothing. Read from the
// login list rather than from 'tea whoami' for two reasons: whoami reports the
// DEFAULT login, which on a machine with two instances configured is as likely as
// not to be the other one; and with no login at all it prints "no gitea login
// configured" to stdout and exits 0, so neither its status nor a naive read of its
// output says anything. Asked once - it is live enough to be worth not repeating.
func (a *app) forgeLogin(cli, host string) string {
	return a.forge.login.get(func() string {
		if cli == "" || host == "" {
			return ""
		}
		out, ok := runOutOK(cli, "logins", "list", "--output", "tsv")
		if !ok {
			return ""
		}
		for _, record := range parseForgeTable(out) {
			if strings.EqualFold(parseRemote(record["url"]).host, host) {
				return record["user"]
			}
		}
		return ""
	})
}
