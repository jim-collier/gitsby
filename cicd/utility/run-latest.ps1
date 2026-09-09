#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Runs the newest gitsby build from a private pool, args forwarded.
.DESCRIPTION
    The dogfood answer to "is the binary I am running the one I just built?", and
    independent of the pipeline: each run copies the newest build (src-go/gitsby,
    the one every cicd pass refreshes) into a pool directory under a name carrying
    the build's own mtime, ages out stale copies, then launches the newest copy
    with every argument forwarded and its exit code returned.

    The pool lives outside PATH and the names can't collide with an installed
    gitsby, so this never shadows the real one. Copying by build-mtime means a
    given build lands in the pool once, and a copy that is currently running never
    blocks the next one - Windows will not overwrite a running executable, but a
    new build gets a new name.

    Cross-platform PowerShell 7. Pool: ~/.cache/gitsby-runs (Linux/macOS),
    %LOCALAPPDATA%\gitsby\runs (Windows). Copies older than 7 days go, except the
    newest, which always stays; a copy the OS refuses to delete is left for the
    next run.
.PARAMETER Arguments
    Everything, verbatim, to the launched gitsby.
.NOTES
    Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
    Licensed under The MIT License (MIT). Full text at: https://mit-license.org/
    SPDX-License-Identifier: MIT
    History: at bottom of script.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'A BOM breaks the shebang; file is UTF-8 without BOM.')]
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exeName = if ($IsWindows) { 'gitsby.exe' } else { 'gitsby' }
$buildPath = Join-Path -Path $repoRoot -ChildPath (Join-Path -Path 'src-go' -ChildPath $exeName)

$poolDir = if ($IsWindows) {
    Join-Path -Path $env:LOCALAPPDATA -ChildPath 'gitsby/runs'
} else {
    Join-Path -Path $HOME -ChildPath '.cache/gitsby-runs'
}
$null = New-Item -ItemType Directory -Force -Path $poolDir

# The build's own mtime names the copy, so one build is copied exactly once and a
# rebuild gets a fresh name a running copy can't be holding open.
$ext = if ($IsWindows) { '.exe' } else { '' }
if (Test-Path -LiteralPath $buildPath) {
    $stamp = (Get-Item -LiteralPath $buildPath).LastWriteTime.ToString('yyyyMMdd-HHmmss')
    $pooled = Join-Path -Path $poolDir -ChildPath "gitsby_${stamp}${ext}"
    if (-not (Test-Path -LiteralPath $pooled)) {
        # Staged and renamed, so an interrupt can't leave a half-written copy under a
        # name a later run would trust.
        $staged = Join-Path -Path $poolDir -ChildPath ".staging_$([IO.Path]::GetRandomFileName())"
        Copy-Item -LiteralPath $buildPath -Destination $staged
        if (-not $IsWindows) { chmod +x $staged }
        Move-Item -LiteralPath $staged -Destination $pooled
    }
}

$copies = @(Get-ChildItem -LiteralPath $poolDir -Filter "gitsby_*${ext}" -File | Sort-Object -Property Name)
if (-not $copies) {
    Write-Error "No build to run: nothing pooled in ${poolDir} and no build at ${buildPath} - run cicd/cicd.bash, or 'go build' in src-go."
    exit 1
}

# Age-out: a week, except the newest, which stays however old it is. A running
# copy makes Remove-Item fail on Windows; that one is simply left for next time.
$cutoff = (Get-Date).AddDays(-7)
foreach ($stale in ($copies | Select-Object -SkipLast 1 | Where-Object { $_.LastWriteTime -lt $cutoff })) {
    try { Remove-Item -LiteralPath $stale.FullName -Force } catch { Write-Verbose "left $($stale.Name): $($_.Exception.Message)" }
}

$newest = $copies[-1].FullName
& $newest @Arguments
exit $LASTEXITCODE


# History:
#   20260821 JC: Created. The pooled-copy runner: newest build, timestamped copies,
#   week-long age-out, args forwarded.
