// The ways a run ends, and the blank-line framing each one prints. Every failure
// travels back to main as an error - nothing exits from where it was noticed - so
// the one place that writes an exit status is also the only place that reads one.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"errors"
	"fmt"
)

// errDone stops a run early with nothing left to do. Nothing to do is a success
// everywhere here, and a nonzero exit would tell a calling script the opposite.
var errDone = errors.New("nothing left to do")

// exitReporter is implemented by the errors that know how a run ends: each
// prints its own framing and names the status. Anything else reaching main is a
// fault in here rather than a mistake out there, and gets the usage framing.
type exitReporter interface {
	error
	report(out *printer) int
}

// usageError is an expected validation failure - something the caller can fix.
// Blank lines wrap it on stdout while the message itself goes to stderr; the
// scripts' exit trap resets the blank counter and prints once more on the way
// out, so an error ends with two blanks where success ends with one.
type usageError struct {
	msg string
	// sub marks the errors the scripts raise inside a command substitution: that
	// subshell swallows the wrapping stdout blanks, so only the message escapes
	// and the parent's own exit adds the single blank that lands.
	sub bool
	// cause keeps the underlying error inspectable (errors.Is/As) when one exists;
	// its text is already part of msg.
	cause error
}

func (e *usageError) Error() string { return e.msg }

func (e *usageError) Unwrap() error { return e.cause }

func (e *usageError) report(out *printer) int {
	if !e.sub {
		out.clean("")
	}
	out.errorf("%s", e.msg)
	out.forceClean("")
	if !e.sub {
		out.forceClean("")
	}
	return 1
}

// usagef reports a validation error the caller can act on.
func usagef(format string, a ...any) error {
	return &usageError{msg: fmt.Sprintf(format, a...)}
}

// usageWrapf is usagef over an underlying error: the cause's text lands in the
// message, and the cause itself stays on the chain for errors.Is/As.
func usageWrapf(cause error, format string, a ...any) error {
	return &usageError{msg: fmt.Sprintf(format, a...) + ": " + cause.Error(), cause: cause}
}

// usageSubf is usagef for the errors the scripts raise inside a command
// substitution, which land with one trailing blank instead of two.
func usageSubf(format string, a ...any) error {
	return &usageError{msg: fmt.Sprintf(format, a...), sub: true}
}

// stepError reports an announced step that ran and failed. Its own output is
// already on the terminal, so this adds only what the tool cannot say itself:
// which command, and what it exited with.
type stepError struct {
	disp string
	code int
}

func (e *stepError) Error() string { return fmt.Sprintf("'%s' failed (exit %d)", e.disp, e.code) }

func (e *stepError) report(out *printer) int {
	out.clean("")
	out.errorf("'%s' failed (exit %d).", e.disp, e.code)
	out.forceClean("")
	return 1
}

// silentExit ends the run with a status and nothing further to say - the help
// text already printed, or a passthrough tool that has had its say and ours
// would only be noise on top.
type silentExit int

func (e silentExit) Error() string { return fmt.Sprintf("exit %d", int(e)) }

func (e silentExit) report(*printer) int { return int(e) }
