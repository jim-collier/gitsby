#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Downloads and installs the gitsby binary for this platform.
.DESCRIPTION
    Shows the plan and asks first. Runs on Windows PowerShell 5.1 as well as PowerShell 7+,
    since 5.1 is what a fresh Windows install has; what it installs is a static binary and
    needs no PowerShell at all. Meant for one-liner use:
        irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1 | iex
    With options:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1))) -System -Yes
.PARAMETER Target
    'user' for a per-user install (default), or 'system' for all users.
.PARAMETER Arch
    Which binary to fetch: 'amd64' or 'arm64'. Detected from this machine by default.
.PARAMETER System
    Install for all users. The same thing as -Target system.
.PARAMETER Yes
    Don't ask for confirmation.
.PARAMETER Tag
    Install a specific published release tag instead of the latest.
.PARAMETER Help
    Show the options and exit. '--help' is accepted too.
.NOTES
    Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
    Licensed under The MIT License (MIT). Full text at: https://mit-license.org/
    SPDX-License-Identifier: MIT
    History: at bottom of script.
#>


# The blank line under the shebang and the two above this are load-bearing: without them the
# comment help binds to the first function rather than the script, and Get-Help on the file
# shows an auto-generated stub instead.
function Install-Gitsby {
    # Attribute lives inside the function, not at file scope: the file is also read as text
    # and evaluated (iex / scriptblock), where a top-level attribute is a parse error.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'A BOM breaks the shebang, and survives irm into iex; file is UTF-8 without BOM.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive installer; console text is the point.')]
    [CmdletBinding()]
    param(
        [ValidateSet('user', 'system')][string]$Target,
        [ValidateSet('x64', 'x86_64', 'amd64', 'arm64', 'aarch64')][string]$Arch,
        [switch]$System,
        [switch]$Yes,
        # -Ref was this parameter's name while gitsby was a script installed from a tree. It
        # names a published release now, and the old spelling stays as an alias for good.
        [Alias('Ref')][ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$Tag,
        # Took 'dev' or 'stable' when a branch could be installed from its tree. Bound rather
        # than dropped, so a familiar flag gets an explanation instead of a binder error.
        [string]$Release,
        [switch]$Help
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Windows PowerShell 5.1 is what a fresh Windows install actually has, and that is the
    # machine most likely to be running this for the first time - so the documented one-liner
    # has to work there. The syntax in here is 5.1-clean already; what 5.1 lacks is these
    # three variables (7 defines them; 5.1 only ever runs on Windows), TLS 1.2 switched on,
    # and the response parser -UseBasicParsing selects. Nothing else below is conditional.
    $isPS7 = $PSVersionTable.PSVersion.Major -ge 6
    $onWindows = if ($isPS7) { [bool]$IsWindows } else { $true }
    $onMac = if ($isPS7) { [bool]$IsMacOS } else { $false }
    if (-not $isPS7) {
        # 5.1 offers SSL3 and TLS 1.0 by default, and github.com accepts neither.
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }
        catch { Write-Verbose 'Could not raise the TLS version; the download may fail.' }
    }

    if ($Help) {
        Write-Host ''
        Write-Host 'Usage: install.ps1 [OPTIONS]'
        Write-Host 'Downloads and installs gitsby (with confirmation).'
        Write-Host 'Options:'
        Write-Host '  -Target user|system   Install for you (default) or for all users.'
        Write-Host '  -System               The same thing as -Target system.'
        Write-Host '  -Arch amd64|arm64     Which binary to fetch. Detected from this machine by default.'
        Write-Host '  -Tag TAG              A published release tag (default: the latest release).'
        Write-Host '  -Yes                  Do not ask for confirmation.'
        Write-Host '  -Help                 This.'
        Write-Host "  -Release              Took 'dev' or 'stable' when gitsby was a script; takes neither now."
        Write-Host ''
        return
    }

    $repo = 'jim-collier/gitsby'

    # '-Release dev' installed the tip of a branch, which meant downloading a script. There is
    # no script to download now, and a branch has no build behind it.
    if ($Release -eq 'dev') {
        throw "There is no '-Release dev' any more: gitsby is a compiled binary, and a branch has no published build. Take a release with '-Tag TAG', or build the tip yourself: git clone https://github.com/${repo}.git; cd gitsby/src-go; go build -o gitsby ."
    }
    if ($Release -and $Release -ne 'stable') {
        throw "-Release only ever took 'dev' or 'stable', and now takes neither; use '-Tag TAG' for a specific release."
    }
    # The tag lands in a download URL, so a path-shaped one walks out of this repo and installs
    # somebody else's binary while the plan on screen still names ours. ValidatePattern admits
    # '..' and a leading '/', so both are checked here. Reads as a harmless version selector,
    # which is exactly why the confirm prompt is no protection.
    if ($Tag -and ($Tag -match '(^|/)\.\.(/|$)' -or $Tag -match '^/' -or $Tag -match '//')) {
        throw "-Tag names a published release, not a path (got '${Tag}')."
    }
    $installSystemWide = $System.IsPresent -or ($Target -eq 'system')

    # Which asset belongs to this machine. Go's own spelling, since that is what the release
    # is named by. Anything else falls through to the SHA256SUMS lookup below, which is the
    # authority on what this release actually published.
    $goOs = if ($onWindows) { 'windows' } elseif ($onMac) { 'darwin' } else { 'linux' }
    # Detection lands in its own variable rather than back in $Arch: assigning to a parameter
    # re-runs its ValidateSet, so an x86 or 32-bit ARM box would die with a binder error
    # instead of being told what this release does publish.
    $archName = if ($Arch) { $Arch } else {
        # RuntimeInformation arrived in .NET Framework 4.7.1, so an older 5.1 box falls back to
        # the environment. Both spellings land on the same two names below.
        $osArch = try { [string][Runtime.InteropServices.RuntimeInformation]::OSArchitecture }
                  catch { [string]$env:PROCESSOR_ARCHITECTURE }
        switch ($osArch) {
            'X64'   { 'amd64' }
            'Arm64' { 'arm64' }
            default { "$_".ToLowerInvariant() }
        }
    }
    # -Arch used to be accepted and ignored, back when the product was one script that ran
    # everywhere. It picks the binary now, so spell the two the release actually publishes.
    $goArch = switch ($archName) {
        { $_ -in 'x64', 'x86_64', 'amd64' } { 'amd64'; break }
        { $_ -in 'arm64', 'aarch64' }       { 'arm64'; break }
        default                             { $archName }
    }
    $asset = "gitsby-${goOs}-${goArch}"
    if ($onWindows) { $asset += '.exe' }

    # No -Tag: resolve the latest release from the releases/latest redirect (no auth, no
    # API rate limit); unauthenticated API only as fallback (60 req/hr per IP).
    # Resolved into its own variable for the same reason as $archName: a scraped tag assigned
    # back to $Tag re-runs its ValidatePattern, which turns the check below into dead code and
    # reports a malformed tag as whatever the surrounding catch happens to say.
    $tagName = $Tag
    if (-not $tagName) {
        $location = ''
        try {
            $resp = Invoke-WebRequest -Uri "https://github.com/${repo}/releases/latest" -MaximumRedirection 0 -UseBasicParsing -ErrorAction Stop
            $location = [string]$resp.Headers.Location
        } catch {
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $location = [string]$_.Exception.Response.Headers.Location }
        }
        if ($location -match '/releases/tag/([^/\s]+)') { $tagName = $Matches[1] }
    }
    if (-not $tagName) {
        # 'releases/latest' is defined as the newest release that is NOT a pre-release, so a
        # repo whose newest publication is one has nothing there for the redirect above to
        # find. That is the case this exists for - and it used to ask the same endpoint again,
        # which fails identically. The list endpoint comes back newest-first.
        try {
            $releases = @(Invoke-RestMethod -Uri "https://api.github.com/repos/${repo}/releases" -UseBasicParsing)
        } catch {
            throw "Couldn't work out the latest release of ${repo}. GitHub may be unreachable, or rate-limiting this address (60 requests an hour, unauthenticated). A specific release always works: -Tag TAG. ($($_.Exception.Message))"
        }
        # Highest version wins, not newest-listed: the list is ordered by publish date, so a
        # backported fix cut after a newer release would otherwise resolve as latest. The
        # numeric fields decide; Sort-Object is stable, so a tie keeps the newer-listed entry.
        $tagVersion = {
            $v = ($_.tag_name -replace '^[vV]', '') -replace '[-+].*$', ''
            $parsed = [version]'0.0'
            if ([version]::TryParse($v, [ref]$parsed)) { $parsed } else { [version]'0.0' }
        }
        $newestFull = $releases | Where-Object { -not $_.prerelease } | Sort-Object -Property @{Expression = $tagVersion} -Descending | Select-Object -First 1
        if ($newestFull) {
            $tagName = [string]$newestFull.tag_name
        } elseif ($releases.Count -gt 0) {
            $tagName = [string](@($releases | Sort-Object -Property @{Expression = $tagVersion} -Descending)[0].tag_name)
            Write-Host "[ No full release yet; taking the newest pre-release, ${tagName}. ]"
        } else {
            throw "${repo} has published no releases, so there is nothing to install. Build the tip yourself: git clone https://github.com/${repo}.git; cd gitsby/src-go; go build -o gitsby ."
        }
    }
    # Scraped from a redirect header, so check it the same way as a typed one before it reaches a URL.
    if ($tagName -notmatch '^[A-Za-z0-9._/-]+$') { throw "The resolved release tag ('${tagName}') isn't a plain git tag; aborting." }

    # SHA256SUMS decides two things at once, and it is a few hundred bytes: whether this
    # release publishes a binary for this platform, and what that binary should hash to.
    # Fetching it up front means the plan can promise a specific file, before anything large
    # is downloaded. Every install path here is a release asset, so every one is verified -
    # there is no unverified route left to fall back to.
    $base = "https://github.com/${repo}/releases/download/${tagName}"
    $sums = ''
    try {
        # GitHub serves SHA256SUMS as application/octet-stream, and Invoke-WebRequest returns
        # .Content as bytes for anything it doesn't consider text. Splitting those into lines
        # matched nothing, so every default install skipped verification and said there was no
        # SHA256SUMS - which wasn't true.
        $body = (Invoke-WebRequest -Uri "${base}/SHA256SUMS" -UseBasicParsing).Content
        $sums = if ($body -is [byte[]]) { [Text.Encoding]::UTF8.GetString($body) } else { [string]$body }
    } catch { $sums = '' }
    if (-not $sums) {
        throw "Release ${tagName} publishes no SHA256SUMS, so nothing here can be verified. (A release published seconds ago may not be servable yet; try again shortly.)"
    }
    $want = ''
    $published = @(foreach ($sumLine in ($sums -split "`r?`n")) {
        if ($sumLine -match '^([0-9a-fA-F]{64})\s+\*?(gitsby-\S+)$') {
            if ($Matches[2] -eq $asset) { $want = $Matches[1] }
            $Matches[2] -replace '^gitsby-', '' -replace '\.exe$', ''
        }
    })
    if (-not $want) {
        $alsoRan = if ($published) { " It publishes: $($published -join ', ')." } else { '' }
        throw "Release ${tagName} publishes no gitsby binary for ${goOs}/${goArch}.${alsoRan} Build it for yours instead - the module is pure Go with no dependencies: git clone https://github.com/${repo}.git; cd gitsby/src-go; go build -o gitsby ."
    }

    # Destination: per-user by default; -System needs elevation (sudo / admin shell).
    if ($onWindows) {
        $destDir = if ($installSystemWide) { Join-Path -Path $env:ProgramFiles -ChildPath 'gitsby' } else { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs/gitsby' }
        $destPath = Join-Path -Path $destDir -ChildPath 'gitsby.exe'
    } else {
        $destDir = if ($installSystemWide) { '/usr/local/bin' } else { Join-Path -Path $HOME -ChildPath '.local/bin' }
        $destPath = Join-Path -Path $destDir -ChildPath 'gitsby'
    }

    Write-Host ''
    Write-Host '[ gitsby installer (PowerShell) ]'
    Write-Host 'This will:'
    Write-Host "  - Download ${asset} (${tagName}) from github.com/${repo}"
    Write-Host '  - Verify it against the release''s published SHA256SUMS'
    Write-Host "  - Install it to ${destPath}"
    if ($installSystemWide) { Write-Host '  - Need write access to that directory (run elevated / via sudo)' }
    # Windows puts nothing on PATH for you, so without this the install finishes with a program
    # that cannot be run by name. On *nix the destination is a conventional bin dir already.
    if ($onWindows -and (($env:PATH -split [IO.Path]::PathSeparator) -notcontains $destDir)) {
        $pathScopeLabel = if ($installSystemWide) { 'system' } else { 'account' }
        Write-Host "  - Add ${destDir} to your ${pathScopeLabel} PATH (new shells only; this one is unchanged)"
    }
    Write-Host "  - Run 'gitsby --version' to verify"
    if (-not $Yes) {
        $answer = Read-Host 'Continue? [y/N]'
        # Cast: Read-Host returns AutomationNull at EOF, and -notmatch on that yields an empty
        # (falsy) collection - so a non-tty stdin would sail past the prompt unasked.
        # throw, not exit: 'exit' inside iex or a scriptblock ends the CALLER's session.
        if ("${answer}" -notmatch '^(y|yes)$') { throw 'Aborted.' }
    }

    Write-Host ''
    Write-Host '[ Downloading ... ]'
    # Private random subdirectory, not a predictable name in shared temp.
    $tmpDir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    try {
        $tmpFile = Join-Path -Path $tmpDir -ChildPath $asset
        try {
            Invoke-WebRequest -Uri "${base}/${asset}" -OutFile $tmpFile -UseBasicParsing
        } catch {
            throw "Couldn't download ${asset} from release ${tagName}. ($($_.Exception.Message))"
        }
        if ((Get-Item -LiteralPath $tmpFile).Length -eq 0) { throw "Downloaded ${asset} is empty; aborting." }
        # A captive portal or a proxy answers with a page, not a binary. It would fail the
        # checksum anyway, but as tampering rather than as the network problem it is.
        # -AsByteStream is 7's spelling of what 5.1 calls -Encoding Byte; each is an error on
        # the other's parser, so the branch is on the version rather than on a try/catch.
        $firstByte = if ($isPS7) { Get-Content -LiteralPath $tmpFile -AsByteStream -TotalCount 1 }
                     else { Get-Content -LiteralPath $tmpFile -Encoding Byte -TotalCount 1 }
        if ($firstByte -eq [byte][char]'<') {
            throw 'The download came back as a web page, not a binary - something between here and GitHub is intercepting it.'
        }

        $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $tmpFile).Hash
        if ($got -ne $want) { throw "Checksum mismatch for ${asset}; aborting. (Corrupted download or tampering.)" }
        Write-Host '[ Checksum verified. ]'

        Write-Host ''
        Write-Host "[ Installing to ${destPath} ... ]"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        # Staged in the destination directory and renamed over the target, never written in
        # place. Move-Item from the system temp is only atomic within one filesystem, and the
        # temp dir and the install dir usually are not the same one - so an interrupt mid-copy
        # left a truncated executable where the real one should be, one that had passed its
        # checksum under another name.
        $staged = Join-Path -Path $destDir -ChildPath ('.gitsby.install.' + [IO.Path]::GetRandomFileName())
        try {
            Copy-Item -LiteralPath $tmpFile -Destination $staged -Force
            if (-not $onWindows) { chmod +x $staged }
            # Windows will not delete or overwrite a running executable, but it will rename one:
            # move the incumbent aside, then put the new one in its place. What it leaves behind
            # goes at the next install, once nothing is holding it open.
            if ($onWindows -and (Test-Path -LiteralPath $destPath)) {
                Get-ChildItem -LiteralPath $destDir -Filter 'gitsby.exe.replaced-*' -ErrorAction SilentlyContinue |
                    ForEach-Object { Remove-Item -Force -LiteralPath $_.FullName -ErrorAction SilentlyContinue }
                $retired = "${destPath}.replaced-" + [IO.Path]::GetRandomFileName()
                Move-Item -Force -LiteralPath $destPath -Destination $retired
                Remove-Item -Force -LiteralPath $retired -ErrorAction SilentlyContinue
            }
            Move-Item -Force -LiteralPath $staged -Destination $destPath
        } catch {
            if (Test-Path -LiteralPath $staged) { Remove-Item -Force -LiteralPath $staged }
            throw
        }

        Write-Host ''
        Write-Host '[ Verifying ... ]'
        & $destPath --version
        # A native command's nonzero exit does not trip $ErrorActionPreference, and nothing here
        # read $LASTEXITCODE - so a binary that could not run at all was reported as installed.
        if ($LASTEXITCODE -ne 0) {
            throw "Installed ${destPath}, but it would not run (exit ${LASTEXITCODE}). The download verified against the release checksum, so this is the binary not being runnable on this machine rather than a bad download."
        }

        $pathSep = [IO.Path]::PathSeparator
        if (($env:PATH -split $pathSep) -notcontains $destDir) {
            if ($onWindows) {
                # Persist it, as promised in the plan.
                $pathScope = if ($installSystemWide) { 'Machine' } else { 'User' }
                # Straight at the registry rather than [Environment]::GetEnvironmentVariable,
                # which hands back the EXPANDED PATH: writing that back would bake entries like
                # %USERPROFILE%\bin in as literals, permanently, for a PATH we only meant to
                # append to. Reading it raw and putting back the kind it already had leaves
                # every other entry exactly as it was.
                $pathKeyPath = if ($installSystemWide) { 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' } else { 'HKCU:\Environment' }
                try {
                    $pathKey = Get-Item -LiteralPath $pathKeyPath
                    $stored = [string]$pathKey.GetValue('PATH', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    if (($stored -split $pathSep) -notcontains $destDir) {
                        $joined = if ([string]::IsNullOrEmpty($stored)) { $destDir } else { $stored.TrimEnd($pathSep) + $pathSep + $destDir }
                        $storedKind = if ($stored) { $pathKey.GetValueKind('PATH') }
                            elseif ($joined -match '%') { [Microsoft.Win32.RegistryValueKind]::ExpandString }
                            else { [Microsoft.Win32.RegistryValueKind]::String }
                        Set-ItemProperty -LiteralPath $pathKeyPath -Name 'PATH' -Value $joined -Type $storedKind
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
# documented shape binding: -Tag after the scriptblock form, and pwsh -File install.ps1 -Yes.
try {
    # '--help' is what the README documents for both installers, and what anyone types out of
    # habit. PowerShell's binder would only ever report it as a parameter nobody has heard of.
    if (@($args) | Where-Object { $_ -in '--help', '-h', '/?', '-?' }) { Install-Gitsby -Help }
    else { Install-Gitsby @args }
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
#   - 20260819 JC: Installs the binary for this platform, as gitsby.exe on Windows. -Arch is
#     real (it picks the asset) and -Ref is now -Tag, naming a release rather than any git
#     ref. -Release is bound only to explain itself. Every route is a release asset now, so
#     every route is verified and the unverified branch of the plan no longer exists.
#     SHA256SUMS is fetched before the plan is printed, because it is what says whether this
#     platform has a binary at all - and it names the ones that do when this one doesn't.
#   - 20260819 JC: Detection no longer lands back in -Arch and -Tag. Assigning to a parameter
#     re-runs its own validation, so an x86 box and a malformed scraped tag each died in the
#     binder instead of reaching the message written for them. PATH is now read raw from the
#     registry before it is rewritten - the expanded copy would have baked %USERPROFILE%-style
#     entries in as literals, for good, on a PATH we only meant to append to.
#   - 20260819 JC: Runs on Windows PowerShell 5.1: the three platform variables get a fallback,
#     TLS 1.2 is switched on, every web request asks for basic parsing, and the byte read is
#     spelled the way each version spells it. A fresh Windows box has 5.1 and nothing else, so
#     the documented one-liner could not work on the machine most likely to be running it.
#   - 20260819 JC: -Help, and '--help' with it - the README documented an option that did not
#     exist. The verification step reads $LASTEXITCODE, which nothing did: a native command's
#     nonzero exit does not trip $ErrorActionPreference, so a binary that would not run at all
#     was reported as installed. The binary is staged in the destination directory and renamed
#     over the target, since a move from the system temp is only atomic within one filesystem.
#   - 20260819 JC: The release fallback is one. Both routes asked releases/latest, which is
#     defined as the newest release that is NOT a pre-release - so on a repo whose newest
#     publication is one, the fallback failed exactly as the primary had, and blamed rate
#     limiting for it.
