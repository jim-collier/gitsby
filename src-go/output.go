// Output. The blank-line counter is what keeps the section rhythm: repeated blanks
// collapse to one, so callers can ask for breathing room without coordinating with
// each other. Held on a value rather than in package state, so a test can read back
// what a command printed.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
)

// A write to the terminal that fails has nowhere left to report it, and the next
// one would fail the same way - so every write here discards its error on purpose.
type printer struct {
	out       io.Writer
	err       io.Writer
	in        io.Reader
	lastBlank bool
}

func newPrinter() *printer {
	return &printer{out: os.Stdout, err: os.Stderr, in: os.Stdin}
}

func (p *printer) resetBlank() { p.lastBlank = false }

// clean prints a plain line; an empty one only lands when the previous line was
// not already blank.
func (p *printer) clean(s string) {
	if s != "" {
		_, _ = fmt.Fprintln(p.out, s)
		p.lastBlank = false
		return
	}
	if !p.lastBlank {
		_, _ = fmt.Fprintln(p.out)
		p.lastBlank = true
	}
}

func (p *printer) cleanf(format string, a ...any) { p.clean(fmt.Sprintf(format, a...)) }

// forceClean lands a blank even directly after another one, for the framing that
// has to be a fixed number of lines rather than a rhythm.
func (p *printer) forceClean(s string) {
	p.resetBlank()
	p.clean(s)
}

// status prints a bracketed status line - the scripts' fEcho.
func (p *printer) status(s string) {
	if s == "" {
		p.clean("")
		return
	}
	p.clean("[ " + s + " ]")
}

// errorf writes to stderr, prefixed the way every message from here is.
func (p *printer) errorf(format string, a ...any) {
	_, _ = fmt.Fprintln(p.err, meName+": "+fmt.Sprintf(format, a...))
}

// confirm gates every mutation. Only 'y' or 'yes' is yes: a typo, a stray
// newline, or an EOF is a no, because the fallback has to be the harmless answer.
func (p *printer) confirm(prompt string) bool {
	_, _ = fmt.Fprint(p.out, prompt)
	answer, _ := bufio.NewReader(p.in).ReadString('\n')
	p.resetBlank()
	switch strings.ToLower(strings.TrimSpace(answer)) {
	case "y", "yes":
		return true
	}
	return false
}

// wrapWords breaks a sentence at word boundaries, at a fixed column rather than at
// the terminal's. Fixed on purpose: an explanation written to fit is one that reads
// the same in a transcript, in a bug report and on a narrow terminal, and a width
// that moves cannot be written to at all. A word longer than the limit - a path, a
// URL - is left whole and allowed to overhang, since breaking one makes it
// un-copyable.
func wrapWords(text string, width int) []string {
	var lines []string
	var line string
	for _, word := range strings.Fields(text) {
		switch {
		case line == "":
			line = word
		case len(line)+1+len(word) <= width:
			line += " " + word
		default:
			lines = append(lines, line)
			line = word
		}
	}
	if line != "" {
		lines = append(lines, line)
	}
	return lines
}
