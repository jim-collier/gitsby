// A file another program holds open without read sharing: the Windows way a
// file can be there and unreadable, since chmod can't take the read bit away.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"strings"
	"syscall"
	"testing"
)

// Reads pass over a file held open without read sharing, and the create refuses
// by name instead of blaming permissions. The OS sentence is localized, so only
// the fixed text is matched.
func TestAccountSetRefusesAFileHeldOpen(t *testing.T) {
	a := createApp(t, newPrinter())
	file := putDefaultConfig(t, keptBody)
	name, err := syscall.UTF16PtrFromString(file)
	if err != nil {
		t.Fatal(err)
	}
	h, err := syscall.CreateFile(name, syscall.GENERIC_READ, 0, nil, syscall.OPEN_EXISTING, syscall.FILE_ATTRIBUTE_NORMAL, 0)
	if err != nil {
		t.Fatal(err)
	}
	held := true
	release := func() {
		if held {
			held = false
			// Opened only to hold the file; nothing went through it, so Close has nothing to say.
			_ = syscall.CloseHandle(h)
		}
	}
	t.Cleanup(release)
	if err := a.cfg.load(a.opt); err != nil {
		t.Fatalf("load: %v", err)
	}
	if a.cfg.file != "" {
		t.Errorf("reads took up the held file: %q", a.cfg.file)
	}
	err = a.cmdAccountSet()
	if err == nil {
		t.Fatal("set: no refusal")
	}
	for _, want := range []string{"can't be read", "Run this again once it can be read."} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal is missing %q:\n%s", want, err)
		}
	}
	release()
	if got := readBack(t, file); got != keptBody {
		t.Errorf("the held file changed:\n%q", got)
	}
}
