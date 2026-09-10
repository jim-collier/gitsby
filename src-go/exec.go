// Process running. Everything goes out as an argument list - no shell between, so
// word splitting and expansion cannot happen to user values on the way to a tool.
// The plain readers are free functions because they hold nothing; the announcing
// runners hang off the run, because a step we announce is exactly the thing that
// invalidates what the run has cached.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"errors"
	"os"
	"os/exec"
	"strings"
)

// runOut captures a command's stdout, trimmed. Any failure is simply no output -
// most callers treat empty as "no answer", never as an error to report.
func runOut(name string, args ...string) string {
	out, _ := runOutOK(name, args...)
	return out
}

// runOutOK is runOut that also says whether the command worked, for the few
// callers that must tell "the tool failed" apart from "the answer is nothing".
// gh in particular exits nonzero for a repo that isn't there and for a network
// that is down, and stating the first when it was the second sends you off to
// create something that already exists.
func runOutOK(name string, args ...string) (string, bool) {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return "", false
	}
	return strings.TrimRight(string(out), "\r\n"), true
}

// runOK is the exit-code question: did it succeed at all.
func runOK(name string, args ...string) bool {
	return exec.Command(name, args...).Run() == nil
}

// splitLines cuts captured output into lines. The trailing '\r' comes off every
// one of them: trimming only the end of the whole capture leaves the interior
// ones in place, so the first line of a two-line answer carried a stray carriage
// return that no later comparison could match.
func splitLines(out string) []string {
	lines := strings.Split(out, "\n")
	for i, line := range lines {
		lines[i] = strings.TrimRight(line, "\r")
	}
	return lines
}

// runLines is runOut split into lines, empties dropped.
func runLines(name string, args ...string) []string {
	all := splitLines(runOut(name, args...))
	lines := make([]string, 0, len(all))
	for _, line := range all {
		if line != "" {
			lines = append(lines, line)
		}
	}
	return lines
}

// exitCode reads a failed command's status. A tool that never started counts as
// a plain failure - the PATH check upstream is what catches a missing one.
func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return 1
}

// stdio wires a command to our own streams, for the ones whose output IS the
// point.
func stdio(cmd *exec.Cmd) *exec.Cmd {
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd
}

// inherit streams a command straight to our stdio and carries on regardless -
// for listings whose output IS the point and whose failure has nothing to add.
func (a *app) inherit(name string, args ...string) {
	a.git.forget()
	_ = stdio(exec.Command(name, args...)).Run()
}

// inheritRC is inherit that reports the exit code, for the callers that print it.
func (a *app) inheritRC(name string, args ...string) int {
	a.git.forget()
	return exitCode(stdio(exec.Command(name, args...)).Run())
}

// inheritOK is inherit that still answers whether it worked - for the steps whose
// failure is survivable but worth a word (a remote branch somebody else already
// deleted).
func (a *app) inheritOK(name string, args ...string) bool {
	return a.inheritRC(name, args...) == 0
}

// step announces and runs a command verbatim, with our stdio - the scripts' fRun.
// Display copy is masked per argument, so a credentialed URL never prints its
// token in the announcement or the failure.
func (a *app) step(name string, args ...string) error {
	disp := maskURL(name)
	for _, arg := range args {
		disp += " " + maskURL(arg)
	}
	return a.stepAs(disp, disp, name, args...)
}

// stepAs announces one thing and runs another, for the gh calls whose real
// argument list carries flags the plan never showed - echoing it verbatim would
// contradict the preview. The failure names the command, not the arguments.
func (a *app) stepAs(announce, label, name string, args ...string) error {
	a.out.clean("")
	a.out.status(announce + " ...")
	if rc := a.inheritRC(name, args...); rc != 0 {
		return &stepError{disp: label, code: rc}
	}
	a.out.resetBlank()
	return nil
}

func mustBeInPath(name string) error {
	if _, err := exec.LookPath(name); err != nil {
		return usagef("Not found in path: %s", name)
	}
	return nil
}

func inPath(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// handover runs the tool with our stdio and leaves with its exit code - the
// portable stand-in for the scripts' exec, which cannot exist on Windows.
func (a *app) handover(name string, args []string) error {
	if err := stdio(exec.Command(name, args...)).Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return silentExit(exitErr.ExitCode())
		}
		// Whether it exists was settled before the handover, so whatever this is,
		// it isn't that.
		return usageWrapf(err, "Couldn't run '%s'", name)
	}
	return silentExit(0)
}
