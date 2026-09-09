#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads and installs the latest gitsby release (PowerShell edition).
.DESCRIPTION
    Shows the plan and asks first. Requires PowerShell 7+. Meant for one-liner use:
        irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1 | iex
    With options:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1))) -System -Yes
.PARAMETER Release
    Which build: 'stable' (the latest release, default) or 'dev' (the tip of the dev branch).
.PARAMETER Target
    'user' for a per-user install (default), or 'system' for all users.
.PARAMETER Arch
    Accepted for consistency with other installers, and has no effect here: gitsby is a
    script, so the same file runs on every architecture.
.PARAMETER System
    Install for all users. The same thing as -Target system.
.PARAMETER Yes
    Don't ask for confirmation.
.PARAMETER Ref
    Install from a specific branch/tag/commit instead of the latest release.
.NOTES
    Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
    Licensed under The MIT License (MIT). Full text at: https://mit-license.org/
    SPDX-License-Identifier: MIT
    History: at bottom of script.
#>
function Install-Gitsby {
    # Attribute lives inside the function, not at file scope: the file is also read as text
    # and evaluated (iex / scriptblock), where a top-level attribute is a parse error.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'A BOM breaks the shebang, and survives irm into iex; file is UTF-8 without BOM.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive installer; console text is the point.')]
    [CmdletBinding()]
    param(
        [ValidateSet('dev', 'stable')][string]$Release,
        [ValidateSet('user', 'system')][string]$Target,
        [ValidateSet('x64', 'x86_64', 'amd64', 'arm64', 'aarch64')][string]$Arch,
        [switch]$System,
        [switch]$Yes,
        [ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$Ref
    )

    # Windows PowerShell 5.1 is still 'powershell' on Windows and has no $IsWindows, which
    # StrictMode turns into an undefined-variable error further down - so say it plainly here.
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "This installer needs PowerShell 7+; this is $($PSVersionTable.PSVersion). Install it: 'winget install --id Microsoft.PowerShell' on Windows, or see https://aka.ms/powershell."
    }
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $repo = 'jim-collier/gitsby'

    # -Release is the friendly spelling; -Ref is the escape hatch. Both at once is ambiguous.
    if ($Release -and $Ref) { throw 'Use -Release or -Ref, not both.' }
    if ($Release -eq 'dev') { $Ref = 'dev' }
    # The ref lands in a download URL, so a path-shaped one walks out of this repo and installs
    # somebody else's script while the plan on screen still names ours. ValidatePattern admits
    # '..' and a leading '/', so both are checked here. Reads as a harmless branch selector,
    # which is exactly why the confirm prompt is no protection.
    if ($Ref -and ($Ref -match '(^|/)\.\.(/|$)' -or $Ref -match '^/' -or $Ref -match '//')) {
        throw "-Ref names a branch, tag or commit, not a path (got '${Ref}')."
    }
    $isRelease = -not $Ref
    $installSystemWide = $System.IsPresent -or ($Target -eq 'system')

    # No -Ref: resolve the latest release tag from the releases/latest redirect (no auth, no
    # API rate limit); unauthenticated API only as fallback (60 req/hr per IP).
    if (-not $Ref) {
        $location = ''
        try {
            $resp = Invoke-WebRequest -Uri "https://github.com/${repo}/releases/latest" -MaximumRedirection 0 -ErrorAction Stop
            $location = [string]$resp.Headers.Location
        } catch {
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $location = [string]$_.Exception.Response.Headers.Location }
        }
        if ($location -match '/releases/tag/([^/\s]+)') { $Ref = $Matches[1] }
    }
    if (-not $Ref) {
        try {
            $Ref = (Invoke-RestMethod -Uri "https://api.github.com/repos/${repo}/releases/latest").tag_name
        } catch {
            throw "Couldn't determine the latest release; pass e.g. -Ref main. GitHub may be rate-limiting; try again later. ($($_.Exception.Message))"
        }
    }
    # Scraped from a redirect header, so check it the same way as a typed one before it reaches a URL.
    if ($Ref -notmatch '^[A-Za-z0-9._/-]+$') { throw "The resolved release tag ('${Ref}') isn't a plain git ref; aborting." }

    # Destination: per-user by default; -System needs elevation (sudo / admin shell).
    if ($IsWindows) {
        $destDir = if ($installSystemWide) { Join-Path -Path $env:ProgramFiles -ChildPath 'gitsby' } else { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs/gitsby' }
    } else {
        $destDir = if ($installSystemWide) { '/usr/local/bin' } else { Join-Path -Path $HOME -ChildPath '.local/bin' }
    }
    $destPath = Join-Path -Path $destDir -ChildPath 'gitsby.ps1'

    Write-Host ''
    Write-Host '[ gitsby installer (PowerShell) ]'
    Write-Host 'This will:'
    Write-Host "  - Download gitsby.ps1 (${Ref}) from github.com/${repo}"
    if ($Arch) { Write-Host "  - Ignore -Arch ${Arch}: gitsby is a script, so the same file runs on every architecture" }
    Write-Host "  - Install it to ${destPath}"
    if ($installSystemWide) { Write-Host '  - Need write access to that directory (run elevated / via sudo)' }
    # Whether the download gets checked is the one thing worth knowing BEFORE agreeing to it.
    # It used to be reported afterwards, and on the dev path not at all.
    if ($isRelease) { Write-Host '  - Verify the download against the release''s published SHA256SUMS' }
    else            { Write-Host "  - NOT verify the download: ${Ref} is a branch or tag, which has no published checksum" }
    # Windows puts nothing on PATH for you, so without this the install finishes with a program
    # that cannot be run by name. On *nix the destination is a conventional bin dir already.
    if ($IsWindows -and (($env:PATH -split [IO.Path]::PathSeparator) -notcontains $destDir)) {
        $pathScopeLabel = if ($installSystemWide) { 'system' } else { 'account' }
        Write-Host "  - Add ${destDir} to your ${pathScopeLabel} PATH (new shells only; this one is unchanged)"
    }
    Write-Host "  - Run 'gitsby.ps1 --version' to verify"
    if (-not $Yes) {
        $answer = Read-Host 'Continue? [y/N]'
        # Cast: Read-Host returns AutomationNull at EOF, and -notmatch on that yields an empty
        # (falsy) collection - so a non-tty stdin would sail past the prompt unasked.
        # throw, not exit: 'exit' inside iex or a scriptblock ends the CALLER's session.
        if ("${answer}" -notmatch '^(y|yes)$') { throw 'Aborted.' }
    }

    # Prefer the release asset; fall back to the file in the tagged tree.
    Write-Host ''
    Write-Host '[ Downloading ... ]'
    # Private random subdirectory, not a predictable name in shared temp.
    $tmpDir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    $tmpFile = Join-Path -Path $tmpDir -ChildPath 'gitsby.ps1'
    $downloaded = $false
    $fromReleaseAsset = $false
    foreach ($url in @(
            "https://github.com/${repo}/releases/download/${Ref}/gitsby.ps1",
            "https://raw.githubusercontent.com/${repo}/${Ref}/bin/gitsby.ps1")) {
        if ($downloaded) { break }
        if (-not $isRelease -and $url -like '*releases/download*') { continue }
        try {
            Invoke-WebRequest -Uri $url -OutFile $tmpFile
            $downloaded = $true
            $fromReleaseAsset = ($url -like '*releases/download*')
        } catch {
            Write-Verbose "Fetch failed, trying next source: ${url}"
        }
    }
    if (-not $downloaded) {
        throw "Couldn't download gitsby.ps1 at '${Ref}'. (Releases before v2 predate the current layout; try '-Release dev'.)"
    }
    # Only the release asset can be checked against SHA256SUMS, so falling back to the tree here
    # would quietly deliver the unverified copy the plan promised to check. Asking for a release
    # and getting that is not what was agreed, so it stops instead.
    if ($isRelease -and -not $fromReleaseAsset) {
        throw "Release ${Ref} publishes no gitsby.ps1 asset, so only an unverified copy of the tagged tree is available. Re-run with -Ref ${Ref} to take it."
    }
    # Wrong-content 200s happen (captive portals, truncation); a script starts with a shebang.
    if ((Get-Content -LiteralPath $tmpFile -First 1) -notmatch '^#!') { throw "Downloaded file doesn't look like a script; aborting." }

    # Verify against the release's SHA256SUMS when there is one. Only the release-asset
    # path can be verified; -Ref installs pull straight from the tree, unverified.
    if ($fromReleaseAsset) {
        $sums = ''
        # GitHub serves SHA256SUMS as application/octet-stream, and Invoke-WebRequest returns
        # .Content as bytes for anything it doesn't consider text. Splitting those into lines
        # matched nothing, so every default install skipped verification and said there was no
        # SHA256SUMS - which wasn't true.
        try {
            $body = (Invoke-WebRequest -Uri "https://github.com/${repo}/releases/download/${Ref}/SHA256SUMS").Content
            $sums = if ($body -is [byte[]]) { [Text.Encoding]::UTF8.GetString($body) } else { [string]$body }
        } catch { $sums = '' }
        $want = ''
        foreach ($sumLine in ($sums -split "`r?`n")) {
            if ($sumLine -match '^([0-9a-fA-F]{64})\s+\*?gitsby\.ps1$') { $want = $Matches[1]; break }
        }
        if ($want) {
            $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $tmpFile).Hash
            if ($got -ne $want) { throw 'Checksum mismatch for the downloaded gitsby.ps1; aborting. (Corrupted download or tampering.)' }
            Write-Host '[ Checksum verified. ]'
        } else {
            # The plan said this download would be checked, so not checking it is a broken
            # promise rather than a note in passing. Taking it unverified stays available, but
            # as an explicit choice rather than the quiet default.
            throw "Release ${Ref} publishes no SHA256SUMS entry for gitsby.ps1, so the download can't be verified. Re-run with -Ref ${Ref} to take it unverified."
        }
    }

    try {
        Write-Host "[ Installing to ${destPath} ... ]"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Move-Item -Force -Path $tmpFile -Destination $destPath
        if (-not $IsWindows) { chmod +x $destPath }

        Write-Host '[ Verifying ... ]'
        & $destPath --version

        $pathSep = [IO.Path]::PathSeparator
        if (($env:PATH -split $pathSep) -notcontains $destDir) {
            if ($IsWindows) {
                # Persist it, as promised in the plan. Only PATHEXT is left alone: PowerShell already
                # resolves a bare 'gitsby' to gitsby.ps1 from PATH without it, and adding .PS1 there
                # would only affect cmd.exe - which still cannot run one, because it needs a file
                # association, and the default association opens .ps1 in an editor rather than running it.
                $pathScope = if ($installSystemWide) { 'Machine' } else { 'User' }
                try {
                    $stored = [Environment]::GetEnvironmentVariable('PATH', $pathScope)
                    if (($stored -split $pathSep) -notcontains $destDir) {
                        $joined = if ([string]::IsNullOrEmpty($stored)) { $destDir } else { $stored.TrimEnd($pathSep) + $pathSep + $destDir }
                        [Environment]::SetEnvironmentVariable('PATH', $joined, $pathScope)
                    }
                    $env:PATH = $env:PATH.TrimEnd($pathSep) + $pathSep + $destDir
                    Write-Host "[ Added ${destDir} to your ${pathScope} PATH. Open a new shell to pick it up. ]"
                } catch {
                    Write-Host "Note: couldn't update PATH ($($_.Exception.Message)). Add ${destDir} to it to run 'gitsby' by name."
                }
            } else {
                Write-Host "Note: ${destDir} isn't on your PATH; add it in your shell profile."
            }
        }
        Write-Host ''
        Write-Host '[ Done. ]'
        Write-Host ''
    } finally {
        ## LiteralPath, like every other removal in the tree: the temp path is ours, but a bracket
        ## anywhere in it would otherwise be read as a wildcard rather than as a character.
        if ($tmpDir -and (Test-Path -LiteralPath $tmpDir)) { Remove-Item -LiteralPath $tmpDir -Recurse -Force }
    }
}

# A function, not top-level script text: 'iex' evaluates a top-level param() block in the
# caller's scope, where [ValidateSet] validates against its own empty default and dies before
# anything runs - so the documented one-liner never worked. Splatting $args keeps every
# documented shape binding: -Ref after the scriptblock form, and pwsh -File install.ps1 -Yes.
try {
    Install-Gitsby @args
} catch {
    # Run from a file: report plainly and exit nonzero, so callers and CI see the failure -
    # a parameter-binding error against @args would otherwise leave the exit code at 0.
    # Evaluated as text (iex / scriptblock): rethrow, because 'exit' would end the session.
    if ($PSCommandPath) {
        [Console]::Error.WriteLine("install.ps1: $($_.Exception.Message)")
        exit 1
    }
    throw
}


# History:
#   - 20260722 JC: Created.
#   - 20260724 JC: Latest-release lookup via the releases/latest redirect (API scrape
#     is now the rate-limited fallback); random private temp dir; shebang sanity check;
#     release-asset downloads verify against a SHA256SUMS asset when published; named
#     parameters throughout; trailing blank line.
#   - 20260727 JC: Options now spelled -Release, -Target and -Arch, to match the other
#     installers. -System and -Ref still work.
#   - 20260727 JC: Body wrapped in a function: as top-level text the param() block never
#     bound (its ValidateSet validated its own empty default and died), a decline ended the
#     caller's session, and StrictMode leaked into it. Refuses at EOF instead of proceeding.
#     PowerShell 7 is now checked before anything reads $IsWindows.
#   - 20260728 JC: The failed-download message names '-Release dev', like install.bash's does. It used to send you to the Bash installer, which resolves the same stale release and fails the same way.
#   - 20260731 JC: SHA256SUMS is decoded from bytes before it's read. GitHub serves it as
#     octet-stream, so the response body arrived as a byte array and no checksum was ever
#     found - the default install path had been unverified since the check was added.
#   - 20260812 JC: The plan says whether the download will be checked, and on Windows that the
#     install directory is about to be added to PATH - which it now is. Nothing else on Windows
#     puts it there, so the install used to finish with a program that could not be run by name.
#     PATHEXT is deliberately left alone: PowerShell resolves a bare name to a .ps1 on PATH
#     without it, and it would only affect cmd.exe, which cannot run one regardless.
