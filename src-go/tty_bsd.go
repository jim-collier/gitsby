//go:build darwin || freebsd || netbsd || openbsd || dragonfly

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"syscall"
	"unsafe"
)

// isTTY answers the scripts' '[[ -t 0 ]]' on the BSDs and macOS: the terminal
// query, not a mode test. Same question the Linux file asks, under this family's
// name for it - TIOCGETA rather than TCGETS. The character-device test that stood
// here passed for /dev/null, which is the one case the no-tty rule exists for, and
// macOS is a published target rather than a someday one.
func isTTY(f *os.File) bool {
	var t syscall.Termios
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), syscall.TIOCGETA, uintptr(unsafe.Pointer(&t)))
	return errno == 0
}
