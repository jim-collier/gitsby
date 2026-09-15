<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Style guide

Canonical coding style for this project's Go, Bash, and PowerShell. For contribution process, see [contributing.md](contributing.md).

Scope: the product itself is Go now. Go's *formatting* is `gofmt` - the lint stage runs it in list mode and gates on any file it would reformat, so layout is not written down here - but the conventions the formatter can't see are, below. The Bash and PowerShell sections govern the frozen, read-only scripts in `legacy/` and the pipeline's own scripts under `cicd/`.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [All languages](#all-languages)
	- [Naming](#naming)
	- [Comments and headers](#comments-and-headers)
	- [Misc](#misc)
- [Go](#go)
- [Bash](#bash)
- [PowerShell](#powershell)
- [Performance](#performance)
	- [Bash performance](#bash-performance)
	- [PowerShell performance](#powershell-performance)

<!-- /TOC -->

## All languages

### Naming

- Use meaningful names, e.g. that can be searched for. `upperBound`, not `ub`.

- But short conventional names are fine where the meaning is clear.

- Single-letter variables are fine for loop counters and iterators (`for i in ...`), where that's idiomatic.

### Comments and headers

- Terse. Explain *why*, not *what*. Don't restate the next line of code.

- No decorative flair or banner dividers. (The one exception: full-width section-rule comments between major blocks.)

- The file header carries purpose, copyright, and license, in the existing format: `©` copyright line, license name and URL, SPDX identifier.

- Helper and utility scripts are usually MIT-licensed regardless of the project's license, and say so in their own header.

### Misc

- Functions should be idempotent.

- Output should be "friendly", with a blank line to start, a blank line after the end, and never two blank lines in a row (except if beyond script control e.g. in the middle of external command output). The custom bash fEcho*() family of functions help with that.

## Go

`gofmt` settles everything it has an opinion on. The rest:

- Errors return; they don't exit. One `os.Exit` at the top of `main`, no `panic` or `log.Fatal` in library code. A command's failure is a value the caller decides what to do with.

- Add context when passing an error up, and wrap with `%w` (`fmt.Errorf("reading config: %w", err)`) so the chain stays inspectable with `errors.Is`/`As`. Stringifying the cause with `%s`/`%v` throws that away.

- Never discard an error silently. Handle it, return it, or discard it with a one-line comment saying why discarding is correct there.

- Return early. Handle the error or the edge case and get out; the happy path stays at the lowest indent. No `else` after a `return`.

- No goroutines or channels without a measured reason. This program's life is spent waiting on `git`; concurrency here buys latency bugs, not speed.

- Package-level variables are for compiled regexps (`regexp.MustCompile`) and true constants only. Run state lives on the struct that owns the run.

- Keep interfaces small, define them where they are consumed, and don't introduce one until a second implementation exists.

- When a slice's final size is knowable, allocate it with `make(len 0, cap n)` up front.

- `.golangci.yml` at the module root is the gate; a finding there is a defect, not advice.

## Bash

- Bash 4.4 is the floor, and the script refuses to run below it. Write to Bash 5 idioms otherwise, rather than portable-but-clunky POSIX-only workarounds. (The installers are the exception: they run on macOS stock bash 3.2, so that they can report what to do about it.)

- Must pass shellcheck. Per-file disables go at the top, each with a short reason (see the top of `cicd/test.bash`).

- Tabs for indentation, spaces for alignment.

- Reuse the script's existing output helpers (`fEcho`, `fEcho_Clean`). Don't add new echo/printf wrapper functions.

- Avoid shelling out unless necessary (e.g. for `git` commands).

	- For regex matching, `[[ $string =~ $pattern ]]` with `BASH_REMATCH` does the job without forking `grep`.

## PowerShell

- Objects, not text. The pipeline passes .NET objects, not strings. Never parse command output as text when you can access properties. Filter, select, and sort on properties (`Where-Object`, `Select-Object`, `Sort-Object`, `Group-Object`); don't string-munge grep/sed/awk-style. This is the #1 rule; Bash habits break here.

- Use approved verbs (`Get-Verb`) for functions: Verb-Noun naming, PascalCase, singular noun (`Get-User`, not `Get-Users` or `Fetch-User`).

- Full cmdlet names and full parameter names in scripts (`Where-Object` not `?`, `-Property` not positional). Aliases and positional parameters are for the interactive prompt, not committed code.

- Advanced functions: `[CmdletBinding()]` and typed `param()` blocks. Declare parameter types; use `[Parameter(Mandatory)]`, validation attributes (`ValidateSet`, `ValidateNotNullOrEmpty`), and pipeline binding (`ValueFromPipeline`) with `begin`/`process`/`end` where relevant.

- `Set-StrictMode -Version Latest`, and deliberate `$ErrorActionPreference` handling. Prefer terminating errors for real failures: `-ErrorAction Stop` plus `try`/`catch`, and `throw` for your own errors. Don't silently swallow with `-ErrorAction SilentlyContinue` unless you then check `$?`/`$Error` and mean it.

- Output objects, don't `Write-Host`. Emit objects (or `[PSCustomObject]`) to the pipeline so callers can consume them. `Write-Host` is only for genuine console-only UI text. Use `Write-Verbose`/`Write-Warning`/`Write-Error` for diagnostics, gated by streams - not inline print debugging.

- Return rich data as `[PSCustomObject]` with named properties, not formatted strings. Keep formatting (`Format-Table`/`Format-List`) at the very end of a pipeline, display layer only. Never feed `Format-*` output into further logic.

- Comparison operators: `-eq -ne -lt -gt -match -contains` etc., not `<`, `>`, `==`. Remember `-eq` is case-insensitive by default (`-ceq` for case-sensitive). `$null` goes on the LEFT of `-eq` comparisons.

- Prefer the pipeline and cmdlets over manual loops when readable. Use `foreach ($x in $y) {}` for complex per-item logic. Avoid array `+=` in loops (O(n^2) recopy); use a `List[T]` or collect pipeline output.

- Quote deliberately: single quotes for literals, double quotes only when interpolating. Brace variables in strings when ambiguous: `"${name}"`.

- Comment-based help (`.SYNOPSIS`/`.PARAMETER`/`.EXAMPLE`) at script level, and on exported/public functions. Private helpers inside a script take a terse `##` comment instead - full help blocks on every internal function would bury the code.

- Cross-platform: target PowerShell 7+ (`pwsh`). Don't assume Windows-only cmdlets or paths. Use `Join-Path` and `$PSScriptRoot`, not hardcoded separators.

- Must pass PSScriptAnalyzer clean (settings, if any, live in `PSScriptAnalyzerSettings.psd1`).

- 4 spaces per indent (PowerShell convention; unlike the Bash side of this repo).

## Performance

Correctness comes first. What follows costs nothing extra to write, so it is habit rather than optimization. Measuring and tuning a hot path is a separate exercise, and it needs a number to justify it.

- In a shell script the cost is process spawns, not the interpreter. Every everyday gitsby command runs a fixed handful of `git` processes no matter how large the repo is, and that is what keeps them feeling instant.

- Never fork per item in a loop. One call that answers the whole question beats one call per branch or per file. A single `git for-each-ref` with the right filter replaces a loop of `git merge-base` calls.

- Hoist what cannot change during a run. The default branch, the merge target, and the account probes are resolved once and kept in a variable, not asked for again at each use.

- Don't make every run pay for what few runs need. Probes that cost a round trip belong to the commands that actually use them.

### Bash performance

- Use parameter expansion, `[[ ]]`, and arithmetic for small string and number work. The thing to avoid is a `$(...)`, a pipe, or an external `grep`/`sed`/`cut` inside a loop.

- One pass of `awk` or `sed` over the whole input beats a shell loop over its lines. Where a loop is unavoidable, feed it with `mapfile` or `read -r` and keep builtins inside it.

- Pass large strings by nameref (`local -n`) rather than copying them through a subshell.

### PowerShell performance

- Never `+=` an array in a loop. It reallocates and recopies each time, which is O(n^2). Use a `List[T]`, or collect the pipeline's output.

- In a hot loop, `foreach ($x in $y)` and direct .NET methods beat `ForEach-Object` and long cmdlet chains. Everywhere else, prefer whichever reads better.

- Filter as early as possible, using the provider's own `-Filter`, so objects never enter the pipeline just to be thrown away.

- Read files in bulk with `Get-Content -Raw` or .NET IO, not line by line through the pipeline.
