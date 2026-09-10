// Argument parsing: the option vocabulary, the positional slots, the grouped-noun
// collapse, and the 'raw' passthrough prescan. Options are lowercased FIRST, then
// the dashes stripped, so no two entry points can accept different spellings of
// the same option. Nothing here touches the repo, so all of it can be exercised
// on its own.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"strings"
)

func defaultOptions() options {
	return options{fetch: true, visibility: "private"}
}

var switchRegex = regexp.MustCompile(`^--?[^ -]`)

func stripDashes(s string) string {
	for strings.HasPrefix(s, "-") {
		s = s[1:]
	}
	return s
}

// afterEq is the value of a joined option, from the argument as typed - the
// normalized copy is for matching only, a file name or message keeps its case.
func afterEq(arg string) string { return arg[strings.Index(arg, "=")+1:] }

// parseArgs fills the option and positional state. The bool reports that help was
// asked for - from any position: '<noun> <verb> --help' is the reflex every git
// user has, and slot 1 always holds a real command, so nothing can be shadowed.
// -v is deliberately not an option here - it must not turn a mutating command
// into a silent no-op.
func parseArgs(argv []string) (options, command, bool, error) {
	const maxPositional = 5
	opt := defaultOptions()
	cmd := command{mutating: true}
	lastSwitch := ""
	expectingValue := false
	positional := 0
	for _, arg := range argv {
		switch {
		case expectingValue:
			// A value we are already waiting for wins over the option test:
			// '-m -Wall added' is a commit message, and there is no other way to
			// write one starting with '-'.
			switch lastSwitch {
			case "m", "message", "msg":
				opt.message = arg
			case "config":
				opt.configFile, opt.configGiven = arg, true
			}
			expectingValue = false
		case switchRegex.MatchString(arg):
			t := stripDashes(strings.ToLower(arg))
			lastSwitch = t
			switch {
			case t == "h" || t == "help":
				return opt, cmd, true, nil
			case t == "q" || t == "quiet" || t == "y" || t == "yes":
				opt.quiet = true
			case t == "no-fetch" || t == "nofetch":
				opt.fetch = false
			case t == "offline":
				// Old spelling of --no-fetch, and a lie: it never stopped a push.
				return opt, cmd, false, usagef("There is no --offline option. Offline is a state gitsby finds by trying, not one you declare; use --no-fetch to skip the pre-command fetch (pushes still go out).")
			case t == "public":
				opt.visibility, opt.sawPublic = "public", true
			case t == "private":
				opt.visibility, opt.sawPrivate = "private", true
			case t == "any-identity" || t == "anyidentity":
				opt.anyIdentity = true
			case strings.HasPrefix(t, "m=") || strings.HasPrefix(t, "message=") || strings.HasPrefix(t, "msg="):
				opt.message = afterEq(arg)
			case strings.HasPrefix(t, "config="):
				opt.configFile, opt.configGiven = afterEq(arg), true
			case t == "m" || t == "message" || t == "msg":
				expectingValue = true
			case t == "config":
				expectingValue = true
			default:
				return opt, cmd, false, usagef("Unexpected option in this context: '%s'.", arg)
			}
		default:
			positional++
			if positional > maxPositional {
				return opt, cmd, false, usagef("Too many positional arguments: %d, for max of %d. If that was a message or title, quote it.", positional, maxPositional)
			}
			switch positional {
			case 1:
				cmd.name = arg
			case 2:
				cmd.arg = arg
			case 3:
				cmd.arg2 = arg
			case 4:
				cmd.arg3 = arg
			case 5:
				cmd.arg4 = arg
			}
		}
	}
	if expectingValue {
		return opt, cmd, false, usagef("Never received a parameter for switch '--%s'.", lastSwitch)
	}
	return opt, cmd, false, nil
}

// collapseCommand folds '<noun> <verb>' to one internal token and shifts the
// positionals down, so everything downstream deals with a single flat name. No
// real command has a hyphen, so rejecting one keeps the tokens untypeable.
func collapseCommand(cmd command) (command, error) {
	cmd.name = strings.ToLower(cmd.name)
	if strings.Contains(cmd.name, "-") {
		return cmd, usagef("Unknown command '%s'. Run '%s' with no arguments for a list.", cmd.name, meName)
	}
	// The one prefix ladder in the tool, and deliberately so: this is the command
	// you type all day, and its tail is the half nobody recalls exactly. Nothing
	// else here is prefix-tolerant - don't spread it for consistency. 'update' is
	// the 2.1.0 name; 'pull' is safe because the bare pull command is gone, and an
	// alias onto this one cannot skip the commit the way that one could.
	switch cmd.name {
	case "update", "pull", "pullc", "pullco", "pullcom", "pullcomm", "pullcommi", "pullcommit":
		cmd.name = "pullcom"
	// 'identity' is the name this command was born with, and 'who' is the question
	// shortened. Both permanent: a spelling that ever worked has to keep working.
	case "who", "identity":
		cmd.name = "whoami"
	}
	shift := true
	switch cmd.name {
	case "repo", "repository":
		switch strings.ToLower(cmd.arg) {
		case "clone":
			cmd.name = "repo-clone"
		case "create", "new":
			cmd.name = "repo-create"
		case "connect":
			cmd.name = "repo-connect"
		case "url":
			cmd.name = "repo-url"
		case "":
			return cmd, usagef("Syntax: %s repo <clone <url> [dir] | create <owner/name> | connect [url] | url [https|ssh]>", meName)
		default:
			return cmd, usagef("Unknown 'repo' subcommand '%s'. One of: clone, create, connect, url.", cmd.arg)
		}
	case "account", "acct":
		switch strings.ToLower(cmd.arg) {
		case "", "list", "show":
			cmd.name = "account-list"
		case "apply":
			cmd.name = "account-apply"
		case "set":
			cmd.name = "account-set"
		default:
			return cmd, usagef("Unknown 'account' subcommand '%s'. One of: list, set, apply.", cmd.arg)
		}
	case "br", "branch":
		switch strings.ToLower(cmd.arg) {
		case "", "list":
			cmd.name = "br-list"
		case "create", "new":
			cmd.name = "br-create"
		case "hotfix":
			cmd.name = "br-hotfix"
		case "switch", "go":
			cmd.name = "br-switch"
		case "merge", "land":
			cmd.name = "br-merge"
		case "prune", "clean":
			cmd.name = "br-prune"
		default:
			return cmd, usagef("Unknown 'br' subcommand '%s'. One of: list, create, hotfix, switch, merge, prune.", cmd.arg)
		}
	default:
		shift = false
	}
	if shift {
		cmd.arg, cmd.arg2, cmd.arg3, cmd.arg4 = cmd.arg2, cmd.arg3, cmd.arg4, ""
	}
	return cmd, nil
}

// sortCommand validates each command's argument shape and settles whether it
// mutates. Trailing arguments are rejected everywhere, so silently ignoring one
// anywhere would make a typo look like it did what you meant.
func sortCommand(cmd command, opt *options) (command, error) {
	switch cmd.name {
	case "status", "whoami", "br-list":
		// br list's extra lands in cmd.arg too, after the noun shift, so one test
		// covers both.
		cmd.mutating = false
		if cmd.arg != "" {
			return cmd, usagef("'%s %s' takes no arguments (got '%s').", meName, strings.Replace(cmd.name, "br-list", "br list", 1), cmd.arg)
		}
	case "account-list":
		cmd.mutating = false
		if cmd.arg != "" {
			return cmd, usagef("'%s account list' takes no arguments (got '%s').", meName, cmd.arg)
		}
	case "account-apply":
		if cmd.arg != "" {
			return cmd, usagef("'%s account apply' takes no arguments (got '%s').", meName, cmd.arg)
		}
	case "account-set":
		// Three words exactly. A missing value would otherwise read as a request to
		// set the key empty, which is a different thing from what anybody typed.
		if cmd.arg == "" || cmd.arg2 == "" || cmd.arg3 == "" {
			return cmd, accountSetUsage()
		}
		// Returns here rather than falling through: this is the one command whose
		// third positional is a value it wants, and the tail below rejects one.
		return cmd, nil
	case "pr":
		switch strings.ToLower(cmd.arg) {
		case "create", "new":
			if cmd.arg3 != "" {
				return cmd, usagef("Unexpected extra argument '%s'; quote your title.", cmd.arg3)
			}
		case "ok":
		default:
			// A number, or nothing. Either way there is no third word.
			cmd.mutating = false
			if cmd.arg2 != "" {
				return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg2)
			}
		}
	case "pullcom", "sync", "br-merge":
		if opt.message == "" {
			opt.message = cmd.arg
		}
		if cmd.arg2 != "" {
			return cmd, usagef("Unexpected extra argument '%s'; quote your commit message.", cmd.arg2)
		}
	case "repo-clone": // the only one with a second argument of its own (the target directory)
	case "br-prune":
		// Takes nothing: what it deletes is decided by repo state, never by a name
		// on the command line.
		if cmd.arg != "" {
			return cmd, usagef("'%s br prune' takes no arguments (got '%s'); it prunes every branch already merged.", meName, cmd.arg)
		}
	case "br-create", "br-hotfix", "br-switch", "release", "repo-create", "repo-connect":
		if cmd.arg2 != "" {
			return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg2)
		}
	case "repo-url":
		// Bare is the read-only "what is it now"; naming a transport is what makes
		// it mutate.
		if cmd.arg2 != "" {
			return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg2)
		}
		if cmd.arg == "" {
			cmd.mutating = false
		}
	default:
		return cmd, usagef("Unknown command '%s'. Run '%s' with no arguments for a list.", cmd.name, meName)
	}
	if cmd.arg4 != "" {
		return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg4)
	}
	if cmd.arg3 != "" {
		return cmd, usagef("Unexpected extra argument '%s'.", cmd.arg3)
	}
	return cmd, nil
}

// scanPassthrough spots 'raw <git|gh>' ahead of the main parser, because past the
// tool name the arguments belong to the tool: a '-q' there is its own flag, not
// ours. Ours come first. The whole option vocabulary is taken here, spelled and
// normalized the same way as the main parser; the ones with nothing to act on in
// a passthrough are inert. -h and -v fall through on purpose - they mean show
// help or the version, which is the main parser's job.
func scanPassthrough(argv []string, opt *options) (string, []string, error) {
	tool := ""
	var ptArgs []string
	wantConfig, wantTool, wantValue := false, false, false
scan:
	for _, arg := range argv {
		switch {
		case tool != "":
			ptArgs = append(ptArgs, arg)
		case wantConfig:
			opt.configFile, opt.configGiven = arg, true
			wantConfig = false
		case wantValue:
			wantValue = false
		case wantTool:
			// Past the tool name every option is the tool's, so one typed here is
			// ours arriving too late - not a subcommand nobody has heard of.
			if strings.HasPrefix(arg, "-") {
				return "", nil, usagef("'%s' is an option, and %s's own options come before 'raw'. Syntax: %s raw <git|gh> <arguments ...>", arg, meName, meName)
			}
			if arg != "git" && arg != "gh" {
				return "", nil, usagef("Unknown 'raw' subcommand '%s'. One of: git, gh.", arg)
			}
			tool, wantTool = arg, false
		case arg == "raw":
			wantTool = true
		case !strings.HasPrefix(arg, "-"):
			break scan
		default:
			o := stripDashes(strings.ToLower(arg))
			switch {
			case o == "q" || o == "quiet" || o == "y" || o == "yes":
				opt.quiet = true
			case o == "config":
				wantConfig = true
			case strings.HasPrefix(o, "config="):
				opt.configFile, opt.configGiven = afterEq(arg), true
			case o == "no-fetch" || o == "nofetch":
			case o == "any-identity" || o == "anyidentity":
			case o == "public" || o == "private":
			case o == "m" || o == "message" || o == "msg":
				wantValue = true
			case strings.HasPrefix(o, "m=") || strings.HasPrefix(o, "message=") || strings.HasPrefix(o, "msg="):
			default:
				break scan
			}
		}
	}
	if wantTool {
		return "", nil, usagef("Syntax: %s raw <git|gh> <arguments ...>", meName)
	}
	return tool, ptArgs, nil
}
