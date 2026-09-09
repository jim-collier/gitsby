#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sets up a gitsby development environment (PowerShell edition).
.DESCRIPTION
    Clones the repo, checks out the 'dev' branch, and checks the tooling. Shows
    the plan and asks first. Requires PowerShell 7+ and git. Meant for one-liner use:
        irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.ps1 | iex
    With options:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.ps1))) -Directory ~/dev/gitsby -Yes
.PARAMETER Directory
    Where to clone to (default: ./gitsby).
.PARAMETER Yes
    Don't ask for confirmation.
.NOTES
    Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
    Licensed under The MIT License (MIT). Full text at: https://mit-license.org/
    SPDX-License-Identifier: MIT
    History: at bottom of script.
#>
function Install-GitsbyDev {
    # Attribute lives inside the function, not at file scope: the file is also read as text
    # and evaluated (iex / scriptblock), where a top-level attribute is a parse error.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'A BOM breaks the shebang, and survives irm into iex; file is UTF-8 without BOM.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive installer; console text is the point.')]
    [CmdletBinding()]
    param(
        [string]$Directory = './gitsby',
        [switch]$Yes
    )

    # Windows PowerShell 5.1 is still 'powershell' on Windows and has no $IsMacOS/$IsWindows,
    # which StrictMode turns into an undefined-variable error further down.
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "This installer needs PowerShell 7+; this is $($PSVersionTable.PSVersion). Install it: 'winget install --id Microsoft.PowerShell' on Windows, or see https://aka.ms/powershell."
    }
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $repo = 'jim-collier/gitsby'

    if (-not (Get-Command -Name git -ErrorAction SilentlyContinue)) { throw 'git is required; install it first.' }
    # Option-shaped paths would bind as real git clone options; same guard as install-dev.bash.
    if ($Directory -match '^-') { throw "'${Directory}' looks like an option, not a directory." }
    if (Test-Path -LiteralPath $Directory) { throw "'${Directory}' already exists; pick another -Directory or remove it." }

    # The local cicd pipeline (cicd/cicd.bash) is bash-based; on Windows it runs
    # under WSL or Git Bash. Only git + PowerShell 7 are needed to hack on the
    # PowerShell port itself.
    $toolNotes = @()
    if (-not (Get-Command -Name bash -ErrorAction SilentlyContinue)) {
        # The BSDs ship no bash at all, so name the package rather than just the requirement.
        $bashHint = if ($IsMacOS) { "; 'brew install bash'" }
                    elseif ($IsWindows) { '; WSL or Git Bash' }
                    elseif ($PSVersionTable.OS -match 'BSD|DragonFly') { "; 'pkg install bash' (FreeBSD) or 'pkg_add bash' (OpenBSD)" }
                    else { '' }
        $toolNotes += "bash 4.4+ (for the cicd pipeline and the Bash gitsby${bashHint})"
    }
    if (-not (Get-Command -Name shellcheck -ErrorAction SilentlyContinue)) { $toolNotes += 'shellcheck (lint stage)' }
    if (-not (Get-Command -Name markdownlint -ErrorAction SilentlyContinue)) { $toolNotes += 'markdownlint (npm install -g markdownlint-cli)' }

    Write-Host ''
    Write-Host '[ gitsby dev setup (PowerShell) ]'
    Write-Host 'This will:'
    Write-Host "  - Clone github.com/${repo} into '${Directory}' and check out the 'dev' branch"
    if ($toolNotes.Count -gt 0) {
        Write-Host '  - Note tooling to install by hand if you want the full pipeline:'
        $toolNotes | ForEach-Object { Write-Host "      - $_" }
    }
    if (-not $Yes) {
        $answer = Read-Host 'Continue? [y/N]'
        # Cast: Read-Host returns AutomationNull at EOF, and -notmatch on that yields an empty
        # (falsy) collection - so a non-tty stdin would sail past the prompt unasked.
        # throw, not exit: 'exit' inside iex or a scriptblock ends the CALLER's session.
        if ("${answer}" -notmatch '^(y|yes)$') { throw 'Aborted.' }
    }

    Write-Host ''
    Write-Host '[ Cloning ... ]'
    git clone "https://github.com/${repo}.git" $Directory
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed.' }
    Push-Location -Path $Directory
    try {
        git checkout dev 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Host "Note: no 'dev' branch on origin; staying on the default branch." }

        Write-Host ''
        Write-Host '[ Done. ]'
        Write-Host 'Next steps:'
        Write-Host '  - Read contributing.md and style-guide.md'
        Write-Host '  - Run the local pipeline (bash): cicd/cicd.bash --quick'
        Write-Host "  - Work on a short-named feature branch off 'dev'; PRs merge back to 'dev'"
        Write-Host ''
    } finally {
        Pop-Location
    }
}

# A function, not top-level script text: 'iex' evaluates a top-level param() block in the
# caller's scope rather than binding parameters, and a bare 'exit' there ends the caller's
# session. Splatting $args keeps both documented shapes binding.
try {
    Install-GitsbyDev @args
} catch {
    # Run from a file: report plainly and exit nonzero, so callers and CI see the failure -
    # a parameter-binding error against @args would otherwise leave the exit code at 0.
    # Evaluated as text (iex / scriptblock): rethrow, because 'exit' would end the session.
    if ($PSCommandPath) {
        [Console]::Error.WriteLine("install-dev.ps1: $($_.Exception.Message)")
        exit 1
    }
    throw
}


# History:
#   - 20260722 JC: Created.
#   - 20260724 JC: Option-shaped -Directory rejected; named parameters throughout; trailing blank line.
#   - 20260727 JC: Body wrapped in a function, for the same reasons as install.ps1: a
#     decline no longer ends the caller's session, StrictMode no longer leaks into it, and a
#     non-tty stdin refuses rather than cloning unasked. PowerShell 7 checked up front.
