#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Safer, state-checked wrappers for everyday git.
.DESCRIPTION
    PowerShell port of gitsby. Every command verifies the repo state before
    acting (commit only if dirty, pull only with an upstream, push only if
    ahead), so each is idempotent and safe to re-run.
.PARAMETER Command
    update | sync | status | release, or a grouped noun:
    repo (clone | create | connect) | br (list | create | switch | land | prune) | pr (create | n | ok n)
.PARAMETER CommandArg
    Subcommand of a grouped noun, else: message (update/sync), version (release).
.PARAMETER CommandArg2
    First argument of a grouped subcommand: branch name, message, URL, PR number, title.
.PARAMETER CommandArg3
    Target directory for 'repo clone <url> [dir]'.
.PARAMETER Message
    Commit or merge message (-m/-msg also work; or give it positionally).
.PARAMETER Quiet
    No prompts; if committing with no message, one is generated.
.PARAMETER Yes
    The same thing as -Quiet.
.PARAMETER NoFetch
    Skip the pre-command fetch, and the pull. Pushes still go out.
.EXAMPLE
    gitsby.ps1 update "fixed the frobnicator"
.EXAMPLE
    gitsby.ps1 br create featx
.NOTES
    History at bottom of script. Copyright © 2014-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞).
    Licensed under The MIT License (MIT): https://mit-license.org/
    SPDX-License-Identifier: MIT
#>

## Console-only UI tool; everything written is for the human at the terminal.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive console tool; output is UI, not pipeline data.')]
## No BOM: the shebang must be the first two bytes for direct execution on *nix.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'BOM would break the shebang; file is UTF-8 without BOM.')]
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = '',
    [Parameter(Position = 1)][string]$CommandArg = '',
    [Parameter(Position = 2)][string]$CommandArg2 = '',
    [Parameter(Position = 3)][string]$CommandArg3 = '',
    [Alias('m', 'msg')][string]$Message = '',
    [Alias('q')][switch]$Quiet,
    ## Separate switch, not another alias of -Quiet: aliases of one parameter can't both be
    ## given, so '-q -y' was rejected as "specified more than once" where bash accepts it.
    [Alias('y')][switch]$Yes,
    [Alias('offline')][switch]$NoFetch,
    [switch]$Public,
    [switch]$Private,
    [switch]$AnyIdentity,
    [Alias('h')][switch]$Help,
    [Alias('v', 'ver')][switch]$Version
)

## Windows PowerShell 5.1 is still 'powershell' on Windows, and it has no $IsWindows - under
## StrictMode that surfaces as an undefined variable partway through a command rather than as
## something a reader can act on. Bash has the same gate for the same reason.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Error: $(Split-Path -Leaf -Path $PSCommandPath) needs PowerShell 7 or newer; this is $($PSVersionTable.PSVersion)."
    Write-Host "  Install it: 'winget install --id Microsoft.PowerShell' on Windows, or see https://aka.ms/powershell."
    Write-Host '  Or use the Bash build (gitsby), which does the same thing.'
    exit 1
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:thisVersion = '2.0.2'
$script:thisCopyrightYear = '2014-2026'
$script:thisAuthor = 'Jim Collier'
$script:meName = Split-Path -Leaf -Path $PSCommandPath
$script:doQuietly = ([bool]$Quiet -or [bool]$Yes)
$script:noFetch = [bool]$NoFetch
$script:commitMessage = $Message
$script:cmdArg = $CommandArg
$script:wasLastEchoBlank = $false
$script:wasShownCopyright = $false
$script:wasShownAbout = $false
$script:wasShownSyntax = $false
$script:mergeTargetLabel = 'dev/main'  ## for help text, before we know we're in a repo
$script:defaultBranchCache = ''  ## per-run constants, filled post-fetch
$script:mergeTargetCache = ''
$script:repoVisibility = if ($Public) { 'public' } else { 'private' }  ## for 'repo create'
$script:inRepo = $false
$script:remoteReachable = $true  ## cleared when the pre-command fetch can't reach origin
$script:cloneUrl = ''; $script:cloneDir = ''
$script:connectMode = ''; $script:connectUrl = ''; $script:ghTarget = ''  ## resolved by the repo create/connect validation
$script:isGhCommand = $false   ## command goes through gh at all -> show whose account that is
$script:isGhWrite = $false     ## command WRITES through gh -> also compare against the ssh key
$script:ghLoginCache = ''; $script:sshLoginCache = ''; $script:ghProtocolCache = ''  ## per-run, each costs a round trip
$script:ghSwitchedFrom = ''    ## gh's active account, when this run picked a different one for the remote
$script:identityProbeUrl = ''  ## url the ssh identity is read from (existing origin, or the one about to be set)
$script:pruneLocal = @(); $script:pruneRemote = @(); $script:pruneKeep = @(); $script:pruneTargetRefs = @(); $script:pruneCurrentMerged = ''  ## resolved by the br prune validation


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Output helpers (same contract as the Bash fEcho family)

function Write-PlainLine {
    param([string]$Text = '')
    if ('' -ne $Text) {
        Write-Host $Text
        $script:wasLastEchoBlank = $false
    } elseif (-not $script:wasLastEchoBlank) {
        Write-Host ''
        $script:wasLastEchoBlank = $true
    }
}

function Write-StatusLine {
    param([string]$Text = '')
    if ('' -ne $Text) { Write-PlainLine "[ ${Text} ]" } else { Write-PlainLine '' }
}

function Clear-BlankCounter {
    $script:wasLastEchoBlank = $false
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Copyright, about, & syntax

function Show-Copyright {
    if ($script:doQuietly -or $script:wasShownCopyright) { return }
    $script:wasShownCopyright = $true
    Write-PlainLine ''
    Write-PlainLine "${script:meName} v${script:thisVersion}, Copyright © ${script:thisCopyrightYear} ${script:thisAuthor}."
    Write-PlainLine 'Licensed under The MIT License (MIT). Full text at:'
    Write-PlainLine '  https://mit-license.org/'
    Write-PlainLine 'No Warranty.'
    Write-PlainLine ''
}

function Show-About {
    if ($script:doQuietly -or $script:wasShownAbout) { return }
    $script:wasShownAbout = $true
    Write-PlainLine ''
    Write-PlainLine 'Safer, state-checked wrappers for everyday git. Every command verifies the'
    Write-PlainLine 'repo state before acting (commit only if dirty, pull only with an upstream,'
    Write-PlainLine 'push only if ahead), so each is idempotent and safe to re-run.'
    Write-PlainLine ''
}

function Show-Syntax {
    if ($script:doQuietly -or $script:wasShownSyntax) { return }
    $script:wasShownSyntax = $true
    Write-PlainLine ''
    Write-PlainLine 'Common commands:'
    Write-PlainLine '  update [msg] .......: Pull updates, then commit all local changes. Do frequently!'
    Write-PlainLine "  br create <branch> .: Create a new branch off ${script:mergeTargetLabel} (current work is carried or parked)."
    Write-PlainLine "  br switch [branch] .: Switch to a branch (parks current work first). No arg: back to ${script:mergeTargetLabel}."
    Write-PlainLine '  br [list] ..........: Fetch and list branches.'
    Write-PlainLine '  status .............: Fetch and show current status.'
    Write-PlainLine 'One-time setup commands:'
    Write-PlainLine '  repo clone <url> ...: Clone a repo you don''t have yet, into [dir] (checks out dev if it has one).'
    Write-PlainLine '  repo create <o/n> ..: Create GitHub repo ''owner/name'' via gh, then connect this directory and push.'
    Write-PlainLine '  repo connect [url] .: Connect this directory to an existing empty remote, and push.'
    Write-PlainLine 'Less common commands:'
    Write-PlainLine '  sync [msg] .........: Pull, commit, and push. Do infrequently.'
    Write-PlainLine 'Admin commands, e.g. for small solo projects:'
    Write-PlainLine "  br land [msg] ......: Merge current branch into ${script:mergeTargetLabel} (--no-ff), push, delete it local + remote."
    Write-PlainLine "  br prune ...........: Delete branches already merged into ${script:mergeTargetLabel}, local + remote."
    Write-PlainLine "  br hotfix <name> ...: Branch off the default branch, to correct what's already published."
    Write-PlainLine '  pr [create|n|ok n] .: Create, list, review, or accept a pull request (needs gh).'
    Write-PlainLine '  release [ver] ......: Cut a release: merge dev into main, tag, push. No ver: next after latest tag.'
    Write-PlainLine 'Options:'
    Write-PlainLine '  -m, -Message MSG .....: Commit or merge message (or give it positionally).'
    Write-PlainLine '  -q, -Quiet, -y .......: Assume yes - no prompts; if committing with no message, one is generated.'
    Write-PlainLine '  -Public / -Private ...: Visibility for the repo ''repo create'' makes (default: private).'
    Write-PlainLine '  -AnyIdentity .........: Act as gh''s active account, and proceed when it differs from the remote''s ssh key.'
    Write-PlainLine '  -NoFetch .............: Skip the pre-command fetch, and the pull. (Pushes still go out.)'
    Write-PlainLine '  -h, -Help  /  -v, -Version'
    Write-PlainLine ''
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Git-state helpers (each verifies, assumes nothing)

function Get-CurrentBranch {
    $branch = git branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $branch) { return '' }
    return [string]$branch
}

function Test-GitOrigin {
    git remote get-url origin *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-GitUpstream {
    git rev-parse --abbrev-ref '@{u}' *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-GitAhead {
    ## -n 1: stop at the first commit; the count doesn't matter.
    $ahead = git rev-list -n 1 '@{u}..' 2>$null
    return (($LASTEXITCODE -eq 0) -and ($null -ne $ahead) -and (@($ahead).Count -gt 0))
}

function Test-GitBranchLocal {
    param([Parameter(Mandatory)][string]$Branch)
    git show-ref --verify --quiet "refs/heads/${Branch}" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-GitBranchRemote {
    param([Parameter(Mandatory)][string]$Branch)
    git show-ref --verify --quiet "refs/remotes/origin/${Branch}" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-GitBranchUnpushed {
    ## Named branch, not HEAD: ahead-ness of a branch you aren't standing on can't be asked with '@{u}'.
    param([Parameter(Mandatory)][string]$Branch)
    $unpushed = git rev-list -n 1 "refs/remotes/origin/${Branch}..refs/heads/${Branch}" 2>$null
    return (($null -ne $unpushed) -and (@($unpushed).Count -gt 0))
}

function Test-ProtectedBranch {
    ## main/master/dev: branches WIP should never be auto-committed to, or deleted.
    ## Takes a branch name; no argument means the current one.
    param([string]$Branch = '')
    $cur = if ($Branch) { $Branch } else { Get-CurrentBranch }
    if ($cur -ceq (Get-DefaultBranch)) { return $true }
    if ($cur -cin 'main', 'master') { return $true }  ## a leftover one isn't ours to touch either
    return (($cur -ceq 'dev') -and ((Test-GitBranchLocal -Branch 'dev') -or (Test-GitBranchRemote -Branch 'dev')))
}

function Test-MergedInto {
    ## True when $Ref is already contained in any of $IntoRefs.
    param([Parameter(Mandatory)][string]$Ref, [Parameter(Mandatory)][string[]]$IntoRefs)
    foreach ($into in $IntoRefs) {
        git rev-parse -q --verify "$into" *> $null
        if ($LASTEXITCODE -ne 0) { continue }
        git merge-base --is-ancestor "$Ref" "$into" *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

function Resolve-PruneList {
    ## Sorts local branches into what's already landed and what isn't. Ancestry is an exact
    ## test here only because gitsby always lands with a real merge commit - a squash- or
    ## rebase-landed branch never looks contained, and is kept rather than guessed at.
    $target = Get-MergeTarget
    $targetRemoteRef = "refs/remotes/origin/${target}"
    if (Test-GitBranchLocal  -Branch $target) { $script:pruneTargetRefs += "refs/heads/${target}" }
    if (Test-GitBranchRemote -Branch $target) { $script:pruneTargetRefs += $targetRemoteRef }
    $currentBranch = Get-CurrentBranch
    foreach ($branch in @(git for-each-ref --format='%(refname:short)' refs/heads/ 2>$null)) {
        if (-not $branch) { continue }
        ## The branch we're standing on can't be deleted, and protected ones never are.
        ## But if it WOULD have qualified, say so - otherwise it just vanishes from every list.
        if ($branch -ceq $currentBranch) {
            if ((-not (Test-ProtectedBranch -Branch $branch)) -and ($script:pruneTargetRefs.Count -gt 0) -and (Test-MergedInto -Ref "refs/heads/${branch}" -IntoRefs $script:pruneTargetRefs)) {
                $script:pruneCurrentMerged = $branch
            }
            continue
        }
        if (Test-ProtectedBranch -Branch $branch) { continue }
        if (($script:pruneTargetRefs.Count -gt 0) -and (Test-MergedInto -Ref "refs/heads/${branch}" -IntoRefs $script:pruneTargetRefs)) {
            $script:pruneLocal += $branch
            ## The remote copy goes only when origin has the merge too: a landing that hasn't
            ## been pushed yet leaves origin holding the only ref to that work.
            if ((Test-GitBranchRemote -Branch $branch) -and (Test-MergedInto -Ref "refs/remotes/origin/${branch}" -IntoRefs @($targetRemoteRef))) {
                $script:pruneRemote += $branch
            }
        } else {
            $script:pruneKeep += $branch
        }
    }
}

function Test-GitDirty {
    $dirty = git status --porcelain 2>$null
    return (($null -ne $dirty) -and (@($dirty).Count -gt 0))
}

function Get-DefaultBranch {
    ## Prefer origin's HEAD; fall back to whichever of main/master exists locally. A repo whose
    ## default is neither (git init -b trunk, init.defaultBranch) and that was never cloned has
    ## no origin/HEAD to read, so a sole local branch is the honest answer there. Guessing 'main'
    ## at the end would name a branch that doesn't exist - Invoke-GitsbyMain refuses instead.
    if ($script:defaultBranchCache) { return $script:defaultBranchCache }
    $originHead = git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $originHead) { return (([string]$originHead) -replace '^origin/', '') }
    if (Test-GitBranchLocal -Branch 'main') { return 'main' }
    if (Test-GitBranchLocal -Branch 'master') { return 'master' }
    if (Test-GitBranchLocal -Branch 'trunk') { return 'trunk' }
    ## Nothing conventional to go on: a lone branch is the default by elimination. A named one has
    ## to stay stable as feature branches come and go, which is why the list above is checked first.
    $locals = @(git for-each-ref --format='%(refname:short)' refs/heads 2>$null)
    if ($locals.Count -eq 1) { return ([string]$locals[0]).Trim() }
    ## Unborn HEAD: nothing exists yet, so the name it will get is the honest answer. 'repo connect'
    ## and 'repo create' both legitimately run here, and nothing is checked out to get wrong.
    if ($locals.Count -eq 0) {
        $unborn = git symbolic-ref --quiet --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $unborn) { return ([string]$unborn).Trim() }
        return 'main'
    }
    return ''
}

function Get-MergeTarget {
    ## Feature branches come off of - and land on - dev when the repo has one; else the default branch.
    if ($script:mergeTargetCache) { return $script:mergeTargetCache }
    if ((Test-GitBranchLocal -Branch 'dev') -or (Test-GitBranchRemote -Branch 'dev')) { return 'dev' }
    return (Get-DefaultBranch)
}

function Test-HotfixBranch {
    ## A hotfix corrects what is already published, so it targets the default branch instead of dev.
    ## The 'hotfix/' prefix is the marker: it lives in the ref name, so it survives a clone and is
    ## visible in a branch listing - unlike branch-local config, which neither is.
    param([string]$Branch = '')
    if (-not $Branch) { $Branch = Get-CurrentBranch }
    return $Branch.StartsWith('hotfix/')
}

function Get-BranchTarget {
    ## Where THIS branch lands, which is not always where new feature branches come from.
    ## Get-MergeTarget stays the answer for 'br create' (always dev when there is one); this is the
    ## answer for landing, and for what a pull request should be based on.
    param([string]$Branch = '')
    if (-not $Branch) { $Branch = Get-CurrentBranch }
    if (Test-HotfixBranch -Branch $Branch) { return (Get-DefaultBranch) }
    return (Get-MergeTarget)
}

function Get-BranchDisplay {
    ## "base :: branch" for work branches; a bare name for main/master/dev, which are off nothing.
    ## The base is where the branch LANDS - for anything gitsby made that's also where it came from,
    ## and git records no fork point to read, so the land target is the honest answer either way.
    param([string]$Branch = '')
    if (-not $Branch) { $Branch = Get-CurrentBranch }
    if (-not $Branch) { return '' }
    if (Test-ProtectedBranch -Branch $Branch) { return $Branch }
    $base = Get-BranchTarget -Branch $Branch
    if (-not $base) { return $Branch }
    return "${base} :: ${Branch}"
}

function Get-BackMergeRef {
    ## What the back-merge actually merges. 'pr ok' lands the hotfix on the server, so the LOCAL
    ## default branch never sees it and merging that is a silent no-op; the fetched remote-tracking
    ## ref is the one holding it. After 'br land' the two are the same commit, so this is right
    ## either way - and falls back to the local branch when there's no remote at all.
    ## Offline flips it back: land's push was skipped, so origin's copy is the stale one, and
    ## merging it would carry the hotfix nowhere. ('pr ok' can't run offline at all.)
    $mainBranch = Get-DefaultBranch
    if (-not (Test-Offline)) {
        git rev-parse --verify --quiet "refs/remotes/origin/${mainBranch}" *> $null
        if ($LASTEXITCODE -eq 0) { return "origin/${mainBranch}" }
    }
    return $mainBranch
}

function Invoke-BackMergeToDev {
    ## After a hotfix lands on the default branch, dev has to receive it. Skipping this is how the
    ## next release conflicts on the same file, or quietly reinstates the text the hotfix replaced.
    ## A conflict here is raw-git territory: abort so the tree is left clean, and say so plainly.
    $mainBranch = Get-DefaultBranch
    $devBranch = Get-MergeTarget
    if ($devBranch -ceq $mainBranch) { return }   ## no dev in this repo: nothing to carry back
    if (-not ((Test-GitBranchLocal -Branch $devBranch) -or (Test-GitBranchRemote -Branch $devBranch))) { return }
    $mergeRef = Get-BackMergeRef
    Write-PlainLine ''
    Invoke-Git -GitArgs @('checkout', $devBranch)
    Invoke-GitsbyPullIfOnline
    Write-StatusLine "git merge ${mergeRef} ..."
    git merge $mergeRef -m "Merge ${mainBranch}"
    if ($LASTEXITCODE -eq 0) {
        Clear-BlankCounter
        Invoke-GitsbyPushIfOnline
    } else {
        git merge --abort 2>$null
        Clear-BlankCounter
        Write-StatusLine "WARNING: '${mainBranch}' would not merge cleanly into '${devBranch}'; left '${devBranch}' untouched."
        Write-PlainLine "  The hotfix landed on '${mainBranch}' - that part is done."
        Write-PlainLine "  Carry it across by hand: git checkout ${devBranch} && git merge ${mergeRef}"
    }
}

function Show-HotfixBinWarning {
    ## A hotfix that changes shipped code leaves the default branch carrying something no tag
    ## contains, so the latest release's assets stop matching it. Documentation does not.
    param([Parameter(Mandatory)][string]$WorkBranch, [Parameter(Mandatory)][string]$TargetBranch)
    $changed = @(git diff --name-only "${TargetBranch}...${WorkBranch}" -- bin/ 2>$null)
    if ($changed.Count -eq 0) { return }
    Write-PlainLine ''
    Write-StatusLine 'NOTE: this hotfix changes shipped code, not just documentation.'
    Write-PlainLine "  '${TargetBranch}' will carry code that no tag contains, so the latest release's"
    Write-PlainLine "  downloads no longer match it. Cut a patch release when you're ready: ${script:meName} release"
}

function Get-BranchSync {
    ## Ahead/behind for the branch line; empty when in sync, so a quiet line means "nothing pending".
    if (-not (Test-GitUpstream)) { return '(no upstream)' }
    $counts = git rev-list --left-right --count '@{u}...HEAD' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $counts) { return '' }
    $parts = ([string]$counts) -split '\s+'
    $behind = [int]$parts[0]
    $ahead = [int]$parts[1]
    $bits = @()
    if ($ahead) { $bits += "ahead ${ahead}" }
    if ($behind) { $bits += "behind ${behind}" }
    if (-not $bits) { return '' }
    return '[{0}]' -f ($bits -join ', ')
}

function Get-CommitIdentity {
    ## What actually gets stamped on commits (config or GIT_AUTHOR_*) - and shown to everyone on the remote.
    $ident = git var GIT_AUTHOR_IDENT 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $ident) { return '(unset)' }
    ## Drop the trailing "timestamp timezone".
    return (([string]$ident) -replace '\s+\S+\s+\S+$', '')
}

function Get-MaskedUrl {
    ## Hide userinfo in displayed URLs (https://user:token@host -> https://***@host);
    ## a credentialed origin would otherwise echo the token on every run.
    param([string]$Url)
    return ($Url -replace '^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]+@', '$1***@')
}

function Get-SshTarget {
    ## Host to ask ssh about, pulled out of a remote URL. Empty for https and local-path remotes.
    param([string]$Url)
    if (-not $Url) { return '' }
    if ($Url -match '^[A-Za-z]:[\\/]') { return '' }  ## Windows drive path, not an ssh host
    if ($Url -match '^ssh://(?:[^@/]+@)?([^:/]+)') { return $Matches[1] }
    if ($Url -match '^[a-z][a-z0-9+.-]*://') { return '' }   ## https/git/file: no ssh identity involved
    if ($Url -match '^(?:[^@/]+@)?([^/:]+):') { return $Matches[1] }  ## scp-like: [user@]host:path
    return ''
}

function Get-SshConnectTarget {
    ## '[user@]host' to actually connect to, so an explicit user in the remote URL is honored.
    ## Get-SshTarget returns the bare host, which is the alias to name in the display.
    param([string]$Url)
    $sshHost = Get-SshTarget -Url $Url
    if (-not $sshHost) { return '' }
    if ($Url -match '^ssh://([^@/]+)@') { return '{0}@{1}' -f $Matches[1], $sshHost }
    if ($Url -match '^([^@/]+)@[^/:]+:') { return '{0}@{1}' -f $Matches[1], $sshHost }
    return $sshHost
}

function Get-GitSshCommand {
    ## The ssh command git itself would run, so the probe below asks as the key git actually pushes
    ## with. Without this a per-repo 'core.sshCommand' (the usual way to hold two GitHub accounts on
    ## one box) is invisible here: the probe answers with the default key's account while git pushes
    ## as someone else - and two wrong halves that happen to agree read as a clean bill of health.
    ## Precedence is git's own: GIT_SSH_COMMAND beats core.sshCommand. Split, never re-shelled - a
    ## config value is not a place to run code - so a quoted path degrades to a plain 'ssh' probe
    ## (which answers for the default key, and a wrong '?' is safer than a wrong name) rather than misparse.
    $cmd = $env:GIT_SSH_COMMAND
    if (-not $cmd) {
        $out = @()
        try { $out = @(git config --get core.sshCommand 2>$null) } catch { $out = @() }
        if ($out.Count -gt 0) { $cmd = ([string]$out[0]).Trim() }
    }
    if (-not $cmd -or $cmd -match '["'']') { return @('ssh') }
    return @($cmd -split '\s+' | Where-Object { $_ })
}

function Resolve-SshHost {
    ## Real hostname behind an ssh_config alias ('github_work' -> 'github.com'), so an aliased
    ## remote can still be recognised as GitHub. The alias itself when ssh can't say.
    param([string]$HostAlias)
    if (-not $HostAlias -or -not (Get-Command -Name ssh -ErrorAction SilentlyContinue)) { return $HostAlias }
    ## --: an option-shaped host must not parse as an ssh option
    foreach ($line in @(ssh -G -- "$HostAlias" 2>$null)) {
        if ($line -match '^hostname\s+(\S+)') { return $Matches[1] }
    }
    return $HostAlias
}

function Get-RemoteOwner {
    ## The GitHub account a remote belongs to, or '' when that cannot be said. Only github.com
    ## counts, and an alias is resolved first - 'git@github_work:me/repo.git' names no host worth
    ## comparing. '' for other forges, local paths, or anything that doesn't parse: the caller
    ## treats empty as "no opinion", so a remote we don't understand can never trigger a refusal.
    param([string]$Url)
    if (-not $Url) { return '' }
    if ($Url -match '^[A-Za-z]:[\\/]') { return '' }  ## Windows drive path, not a remote host
    $gitHost = ''; $path = ''                          ## not $host - that is an automatic variable
    if ($Url -match '^[a-z][a-z0-9+.-]*://(?:[^@/]+@)?([^:/]+)(?::\d+)?/(.+)$') { $gitHost = $Matches[1]; $path = $Matches[2] }
    elseif ($Url -match '^(?:[^@/]+@)?([^/:]+):(.+)$')                          { $gitHost = $Matches[1]; $path = $Matches[2] }
    else { return '' }
    $path = $path -replace '^/+', ''
    if ($path -notmatch '/') { return '' }
    if ($gitHost -ne 'github.com') { $gitHost = Resolve-SshHost -HostAlias $gitHost }
    if ($gitHost -ne 'github.com') { return '' }
    return ($path -split '/')[0]
}

function Get-GhTokenFor {
    ## The stored token for an account gh already holds, or ''. Reads gh's own credential store -
    ## no network, no prompt - so it doubles as the "does gh have this account" test.
    param([string]$Who)
    if (-not $Who) { return '' }
    if (-not (Get-Command -Name gh -ErrorAction SilentlyContinue)) { return '' }
    $out = @()
    ## "$Who" quoted: an unquoted user value is wildcard-expanded against the cwd before gh sees it.
    try { $out = @(gh auth token --user "$Who" 2>$null) } catch { $out = @() }
    if ($LASTEXITCODE -eq 0 -and $out.Count -gt 0) { return ([string]$out[0]).Trim() }
    return ''
}

function Select-GhAccount {
    ## gh keeps ONE active account per host, so against a remote owned by somebody else it will act
    ## as whoever you last switched to - and 'gh auth switch' is global state you have to remember to
    ## set and to put back. When the remote's owner is an account gh already holds, point just this
    ## run at it via GH_TOKEN, which outranks the stored credentials and leaves nothing behind.
    ## Only when we can name the owner AND hold their token: an org or a fork we have no account for
    ## is ordinary, and stays untouched. Never silent - Show-Identity names the switch in the preview.
    param([string]$Url)
    $owner = Get-RemoteOwner -Url $Url
    if (-not $owner) { return }
    $active = Get-GhLogin
    if ($active -eq '?' -or $active -eq $owner) { return }
    $token = Get-GhTokenFor -Who $owner
    if (-not $token) { return }
    $env:GH_TOKEN = $token
    ## The token came out of gh's store keyed by that login, so it is that account - no round trip
    ## needed to confirm it, and this stays correct offline.
    $script:ghSwitchedFrom = $active
    $script:ghLoginCache = $owner
}

function Get-GhLogin {
    ## The account gh's token belongs to. gh talks to the API over https and never consults
    ## ssh config, so this is who every gh-backed command acts as - regardless of which key
    ## git pushes with. '?' when gh can't say (missing, logged out, offline).
    if (-not $script:ghLoginCache) {
        $script:ghLoginCache = '?'
        if (Get-Command -Name gh -ErrorAction SilentlyContinue) {
            ## @() first: piping a native command into Select-Object -First stops it early,
            ## leaving $LASTEXITCODE stale (or unset), so success can't be read from it afterward.
            $out = @()
            ## Same as the Bash side: never let gh stop and prompt for anything mid-command.
            $origGhPrompt = $env:GH_PROMPT_DISABLED
            $env:GH_PROMPT_DISABLED = '1'
            try { $out = @(gh api user --jq .login 2>$null) } catch { $out = @() } finally {
                if ($null -eq $origGhPrompt) { Remove-Item -Path Env:GH_PROMPT_DISABLED -ErrorAction SilentlyContinue } else { $env:GH_PROMPT_DISABLED = $origGhPrompt }
            }
            if ($LASTEXITCODE -eq 0 -and $out.Count -gt 0) { $script:ghLoginCache = ([string]$out[0]).Trim() }
        }
    }
    return $script:ghLoginCache
}

function Get-GhProtocol {
    ## Which transport gh hands to git for github.com ('ssh' or 'https'). Host-specific, not the
    ## global default - they can disagree, and the host one is what github.com operations use.
    if (-not $script:ghProtocolCache) {
        $script:ghProtocolCache = 'https'
        if (Get-Command -Name gh -ErrorAction SilentlyContinue) {
            $out = @()
            try { $out = @(gh config get -h github.com git_protocol 2>$null) } catch { $out = @() }
            if ($out.Count -gt 0 -and ([string]$out[0]).Trim() -eq 'ssh') { $script:ghProtocolCache = 'ssh' }
        }
    }
    return $script:ghProtocolCache
}

function Get-SshLogin {
    ## The account this remote's ssh key authenticates as. GitHub answers 'Hi <user>!' and always
    ## exits 1, so parse the greeting, not the status. BatchMode + a connect timeout: never prompt,
    ## never hang. '?' for https/local remotes, no agent, or anything else unresolvable - and a
    ## deploy key answers with a repo name, which simply won't match any login. Unknown is not wrong.
    param([string]$RemoteUrl)
    if (-not $script:sshLoginCache) {
        $script:sshLoginCache = '?'
        $target = Get-SshConnectTarget -Url $RemoteUrl
        if ($target -and (Get-Command -Name ssh -ErrorAction SilentlyContinue)) {
            $greeting = ''
            ## ArgumentList, not a splat: git's ssh command is user config, and a splatted element
            ## can't be quoted against wildcard expansion. ssh tilde-expands its own -i argument,
            ## so an unexpanded '~/.ssh/key' out of config still resolves.
            $sshCmd = Get-GitSshCommand
            $sshArgs = @()
            if ($sshCmd.Count -gt 1) { $sshArgs += $sshCmd[1..($sshCmd.Count - 1)] }
            $sshArgs += @('-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=3', '--', $target)
            try {
                $psi = [System.Diagnostics.ProcessStartInfo]::new($sshCmd[0])
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                foreach ($sshArg in $sshArgs) { [void]$psi.ArgumentList.Add($sshArg) }
                $proc = [System.Diagnostics.Process]::Start($psi)
                ## The greeting is on stderr and is a couple of lines, so a sequential read cannot deadlock.
                $greeting = $proc.StandardOutput.ReadToEnd() + $proc.StandardError.ReadToEnd()
                $proc.WaitForExit()
            } catch { $greeting = '' }
            ## Anchored per line ((?m)), because the greeting is not necessarily the first one: we
            ## capture stderr too, and ssh puts 'Warning: Permanently added ...' or 'Warning:
            ## Identity file ... not accessible' ahead of it. Unanchored would match mid-line text.
            if ($greeting -match '(?m)^Hi ([A-Za-z0-9_.:/-]+)!') { $script:sshLoginCache = $Matches[1] }
        }
    }
    return $script:sshLoginCache
}

function Get-IdentityMismatch {
    ## Returns why the two identities disagree, or ''. Only a mismatch both sides KNOW about
    ## counts: '?' on either side means we couldn't tell, which is not the same as being wrong.
    param([string]$GhLogin = '?', [string]$SshLogin = '?')
    if ($GhLogin -eq '?' -or $SshLogin -eq '?') { return '' }
    if ($GhLogin -eq $SshLogin) { return '' }
    return "gh acts as '${GhLogin}', but this remote's key authenticates as '${SshLogin}'."
}

function Sync-Remote {
    ## Mirror of bash's fpFetchRemote, and the only fetch in this file: --prune (stale origin/*
    ## refs fool the existence checks) plus an origin/HEAD heal. ssh gets a connect timeout so a
    ## dead remote can't hang the command for minutes; never clobber a user-set GIT_SSH_COMMAND.
    ## No auth prompts, same as Get-RemoteProbe: an https remote we can't authenticate to would
    ## otherwise stop and ask for a username mid-command.
    $hadSshCommand = [bool]$env:GIT_SSH_COMMAND
    if (-not $hadSshCommand) { $env:GIT_SSH_COMMAND = 'ssh -o ConnectTimeout=3' }
    $origTermPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        git fetch --quiet --prune 2>$null
        if ($LASTEXITCODE -ne 0) {
            $script:remoteReachable = $false
            Write-StatusLine 'WARNING: git fetch failed (offline?); remote info may be stale.'
        } else {
            git remote set-head origin --auto *> $null
        }
    } finally {
        if (-not $hadSshCommand) { Remove-Item -Path Env:GIT_SSH_COMMAND -ErrorAction SilentlyContinue }
        if ($null -eq $origTermPrompt) { Remove-Item -Path Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue } else { $env:GIT_TERMINAL_PROMPT = $origTermPrompt }
    }
}

function Get-RemoteProbe {
    ## One network round-trip: does the remote exist, and does it have history?
    ## Returns missing | empty | nonempty. No auth prompts - a bad https URL would
    ## otherwise stop and ask for credentials mid-run.
    param([string]$Url)
    $origPrompt = $env:GIT_TERMINAL_PROMPT
    $origSsh = $env:GIT_SSH_COMMAND
    $env:GIT_TERMINAL_PROMPT = '0'
    if (-not $origSsh) { $env:GIT_SSH_COMMAND = 'ssh -o ConnectTimeout=3' }
    try {
        ## Quote: a bare $var lets PowerShell glob '*'/'?'/'[...]' against the cwd first, so the
        ## probe would answer about a different target than the one git is later handed.
        $refs = git ls-remote "$Url" 2>$null
        if ($LASTEXITCODE -ne 0) { return 'missing' }
        if ($refs -and @($refs).Count -gt 0) { return 'nonempty' }
        return 'empty'
    } finally {
        if ($null -eq $origPrompt) { Remove-Item -Path Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue } else { $env:GIT_TERMINAL_PROMPT = $origPrompt }
        if (-not $origSsh) { Remove-Item -Path Env:GIT_SSH_COMMAND -ErrorAction SilentlyContinue }
    }
}

function Get-ReleaseVersion {
    ## Resolve the release tag: validate the given version, or bump patch on the latest v* tag.
    ## Also records in $script:releaseBumped whether we invented the version rather than being
    ## told it - a version you typed is never a no-op, an invented one can be.
    $script:releaseBumped = $false
    $ver = $script:cmdArg -replace '^v', ''
    if ($ver) {
        if ($ver -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$') {
            throw "'${ver}' is not a version (want X.Y.Z, optional -suffix). Syntax: ${script:meName} release [version]"
        }
    } else {
        $ver = '0.1.0'  ## first release ever, or an unreadable tag
        $script:releaseBumped = $true
        ## versionsort.suffix=- ranks v2.0.0 above its own v2.0.0-rc1; the default sort inverts them.
        $latest = @(git -c versionsort.suffix=- tag --list 'v[0-9]*' --sort=-v:refname 2>$null) | Select-Object -First 1
        if ([string]$latest -match '^v?([0-9]+)(\.([0-9]+))?(\.([0-9]+))?(.*)$') {
            $maj = $Matches[1]
            $min = if ($Matches[3]) { $Matches[3] } else { '0' }  ## pad short tags like v1.2 or v2020
            $pat = if ($Matches[5]) { [int]$Matches[5] } else { 0 }
            ## A candidate's own version is what comes next: v2.0.0-rc1 -> v2.0.0, not v2.0.1,
            ## and promoting one is a deliberate version rather than an invented one.
            if ($Matches[6]) { $script:releaseBumped = $false } else { $pat += 1 }
            $ver = "${maj}.${min}.${pat}"
        }
    }
    return "v${ver}"
}

function Invoke-Git {
    ## Announce and run git with a literal argv. Splatting 'git @GitArgs' lets
    ## PowerShell wildcard-expand any element that is a bare '*'/'?'/'[...]' against
    ## the cwd (a commit message of '*' would glob to filenames), and splatted
    ## elements can't be quoted to stop it. ProcessStartInfo.ArgumentList builds the
    ## argv directly - each element is one literal arg, no globbing, no reshell.
    ## UseShellExecute=$false with no redirection inherits the console, so git's
    ## output still appears inline.
    ## WorkingDirectory is not optional here: .NET starts the child in the PROCESS cwd, and
    ## Set-Location moves only PowerShell's own location. Left unset, every read went to the
    ## directory the user was in while every write went to wherever pwsh happened to launch.
    param([Parameter(Mandatory)][string[]]$GitArgs)
    ## Display copy only: a credentialed URL reaching a clone/push argument would otherwise
    ## print the token here and again in the failure line, after the plan carefully masked it.
    $disp = ($GitArgs | ForEach-Object { Get-MaskedUrl -Url $_ }) -join ' '
    Write-PlainLine ''
    Write-StatusLine "git ${disp} ..."
    $psi = [System.Diagnostics.ProcessStartInfo]::new('git')
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
    foreach ($arg in $GitArgs) { [void]$psi.ArgumentList.Add($arg) }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "'git ${disp}' failed (exit $($proc.ExitCode))." }
    Clear-BlankCounter
}

function Show-CappedList {
    ## Indent and print a command's output, truncated to the terminal so nothing wraps and capped so a
    ## huge working tree can't scroll the prompt off-screen - the 'less -FX' idea without a pager.
    ## Returns the untruncated line count.
    param([Parameter(Mandatory)][string[]]$GitArgs)
    $maxLines = 25
    $termWidth = 100
    if ($Host.UI.RawUI -and $Host.UI.RawUI.WindowSize.Width -ge 40) { $termWidth = $Host.UI.RawUI.WindowSize.Width }
    $outLines = @(git @GitArgs 2>$null)
    $shown = 0
    foreach ($line in $outLines) {
        if ($shown -ge $maxLines) { break }
        $text = [string]$line
        if ($text.Length -gt $termWidth - 4) { $text = $text.Substring(0, $termWidth - 7) + '...' }
        Write-PlainLine "    ${text}"
        $shown++
    }
    if ($outLines.Count -gt $shown) { Write-PlainLine "    ... and $($outLines.Count - $shown) more" }
    return $outLines.Count
}

function Show-LocalChangeList {
    ## Short form on purpose: git status's long form buries the file list under paragraphs of hints.
    Write-PlainLine 'Local changes:'
    $count = Show-CappedList -GitArgs @('status', '--short')
    if (-not $count) { Write-PlainLine '    (working tree clean)' }
}

function Show-FilesToPublish {
    ## Every in-repo command shows what it is about to touch; this is the one that publishes a
    ## whole directory for the first time, possibly to a public repo, so it owes the same. Asked
    ## through a throwaway git dir OUTSIDE the work tree: that way .gitignore and core.excludesFile
    ## are honored exactly as the real 'git add --all' will honor them (listing files git would
    ## skip is its own kind of wrong), and answering 'n' leaves the directory as it was found.
    $probeDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    $savedGitDir = $env:GIT_DIR
    $savedWorkTree = $env:GIT_WORK_TREE
    try {
        [void](New-Item -ItemType Directory -Path $probeDir -Force -ErrorAction Stop)
        $env:GIT_DIR = $probeDir
        $env:GIT_WORK_TREE = (Get-Location -PSProvider FileSystem).ProviderPath
        git init --quiet *> $null
        Write-PlainLine ''
        Write-PlainLine 'Files to publish:'
        $count = Show-CappedList -GitArgs @('ls-files', '--others', '--exclude-standard')
        if (-not $count) { Write-PlainLine '    (nothing - the directory is empty, or everything in it is ignored)' }
    } catch {
        ## A probe we can't set up is not a reason to refuse the command; it just goes unlisted.
        return
    } finally {
        ## Restore, not blank: an empty GIT_DIR is not the same as an unset one.
        if ($null -eq $savedGitDir) { Remove-Item Env:GIT_DIR -ErrorAction SilentlyContinue } else { $env:GIT_DIR = $savedGitDir }
        if ($null -eq $savedWorkTree) { Remove-Item Env:GIT_WORK_TREE -ErrorAction SilentlyContinue } else { $env:GIT_WORK_TREE = $savedWorkTree }
        Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Show-Incoming {
    ## The other half of "what's going to change": what a pull would bring down on top of your work.
    if (-not (Test-GitUpstream)) { return }
    $behind = git rev-list --count 'HEAD..@{u}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $behind -or [int]$behind -eq 0) { return }
    Write-PlainLine ''
    Write-PlainLine "Incoming (${behind} commit(s) to pull):"
    $null = Show-CappedList -GitArgs @('diff', '--name-status', 'HEAD..@{u}')
}

function Show-Identity {
    ## Who a remote-touching command will act as. Host aliases in ~/.ssh/config hide this, and with more
    ## than one account configured it is easy to push as the wrong person.
    param([string]$RemoteUrl)
    $sshHostAlias = Get-SshTarget -Url $RemoteUrl
    if ($sshHostAlias -and (Get-Command -Name ssh -ErrorAction SilentlyContinue)) {
        ## Probe the connect target, not the bare host. Without a user, 'ssh -G' answers with the
        ## local login name - neither who we connect as nor the account we act as, and on a personal
        ## box it looks plausible enough to be believed. The user part only overrides ssh_config's
        ## User, exactly as git does, so alias resolution is unaffected.
        $sshProbeTarget = Get-SshConnectTarget -Url $RemoteUrl
        $sshUser = ''; $sshHost = ''; $keyFile = ''
        foreach ($line in @(ssh -G -- "$sshProbeTarget" 2>$null)) {  ## --: an option-shaped 'host' from .git/config must not parse as an ssh option
            $key, $value = ([string]$line) -split '\s+', 2
            switch ($key) {
                'user' { if (-not $sshUser) { $sshUser = $value } }
                'hostname' { if (-not $sshHost) { $sshHost = $value } }
                'identityfile' {
                    if (-not $keyFile) {
                        $expanded = $value -replace '^~', $HOME
                        if (Test-Path -LiteralPath $expanded) { $keyFile = $value }
                    }
                }
            }
        }
        ## An '-i' in git's own ssh command outranks whatever ssh -G nominated: that is the key git
        ## hands ssh, and with IdentitiesOnly set ssh_config's candidates never get a look in. Without
        ## this the line can name the right account beside the wrong key file, which is worse than
        ## either alone - it invites you to trust the half that happens to be wrong.
        $gitSshCmd = Get-GitSshCommand
        for ($i = 0; $i -lt $gitSshCmd.Count - 1; $i++) {
            if ($gitSshCmd[$i] -eq '-i') { $keyFile = $gitSshCmd[$i + 1]; break }
        }
        if ($sshHost) {
            $sshLine = '{0}@{1}' -f $(if ($sshUser) { $sshUser } else { '?' }), $sshHost
            if ($sshHostAlias -ne $sshHost) { $sshLine += " via alias '${sshHostAlias}'" }
            if ($keyFile) { $sshLine += ", key ${keyFile}" }
            ## Neither half above answers the question this line exists for: the connect user is
            ## 'git' for every GitHub account, and the key is only ssh's first readable candidate,
            ## not necessarily the one that authenticates. So ask the host who we actually are.
            ## Offline it stays unknown - the fetch already said why, no need to repeat it.
            $sshAccount = 'unknown'
            if (-not (Test-Offline)) {
                $resolved = Get-SshLogin -RemoteUrl $RemoteUrl
                if ($resolved -ne '?') { $sshAccount = $resolved }
            }
            Write-PlainLine "SSH ..........: ${sshAccount} (${sshLine})"
        }
    }
    Write-PlainLine "Author .......: $(Get-CommitIdentity)"
    ## gh-backed commands act as gh's account, not the ssh key's - so name it where it applies.
    if ($script:isGhCommand) {
        $ghLogin = Get-GhLogin
        $ghLine = $ghLogin
        if ($ghLogin -eq '?') { $ghLine = '(unknown - gh not logged in, or offline)' }
        ## An account we picked for this remote is still a change of who you act as. Say it here,
        ## in the block you read before confirming, rather than let it look like it was already active.
        if ($script:ghSwitchedFrom) { $ghLine += " (selected for this remote; active account is '$($script:ghSwitchedFrom)')" }
        ## Only a write can act as the wrong account, so only a write gets the comparison. The
        ## round trip behind it is the same one the SSH line above already made.
        if ($script:isGhWrite) {
            $sshLogin = Get-SshLogin -RemoteUrl $script:identityProbeUrl
            if (Get-IdentityMismatch -GhLogin $ghLogin -SshLogin $sshLogin) {
                $ghLine += "  <-- NOT the ssh key's account ('${sshLogin}')"
            } elseif ($sshLogin -eq '?') {
                $ghLine += ' (no ssh identity to compare)'
            }
        }
        Write-PlainLine "GitHub (gh) ..: ${ghLine}"
    }
}

function Show-RepoStatus {
    ## -WithIdentity: also show who we'll be on the remote - pre-flight and 'status', but not the after-shot.
    ## -CommandName: pre-flight for a mutating command. Only the branch-creating ones use it, and only
    ## the pre-flight caller passes it, so the after-shot can't claim a branch it already made.
    param([switch]$WithIdentity, [string]$CommandName = '')
    $remote = git remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $remote) { $remote = '' }
    $remoteDisp = if ($remote) { Get-MaskedUrl -Url ([string]$remote) } else { '(none)' }
    Write-PlainLine ''
    Write-PlainLine "Directory ....: $(Get-Location)"
    Write-PlainLine "Remote .......: ${remoteDisp}"
    if ($WithIdentity) { Show-Identity -RemoteUrl ([string]$remote) }
    ## Say "unknown" rather than assert a name we couldn't resolve - this is the one command that
    ## still runs when the default branch can't be told, so it must not fabricate one.
    $dfltDisp = Get-DefaultBranch
    if (-not $dfltDisp) { $dfltDisp = 'unknown' }
    Write-PlainLine "Default branch: ${dfltDisp}"
    $branchLine = "$(Get-BranchDisplay) $(Get-BranchSync)"
    Write-PlainLine "Current branch: $($branchLine.TrimEnd())"
    ## The line above is where you ARE, which is exactly what misled here - it says 'dev'
    ## while the plan checks out main. This says where you'll end up, and off what.
    switch ($CommandName) {
        'br-create' { Write-PlainLine "New branch ...: $(Get-MergeTarget) :: $($script:cmdArg)"; break }
        'br-hotfix' { Write-PlainLine "New branch ...: $(Get-DefaultBranch) :: $($script:cmdArg)"; break }
    }
    Write-PlainLine ''
    Show-LocalChangeList
    if ($WithIdentity) { Show-Incoming }
    Clear-BlankCounter
}

function Show-CommandPreview {
    ## Static per-command recipe; the command functions do the real state checks at run time.
    ## 'commit' and 'pull' are no longer commands of their own - they stay here as the
    ## fragments update/sync/br-* compose their own plans from.
    param([Parameter(Mandatory)][string]$CommandName)
    $pad = '    '
    $msgDisp = 'git commit'
    if ($script:commitMessage) { $msgDisp = "git commit -m `"$($script:commitMessage)`"" }
    switch ($CommandName) {
        'commit' {
            Write-PlainLine "${pad}git add --all"
            Write-PlainLine "${pad}${msgDisp} *"
            break
        }
        'pull' {
            Write-PlainLine "${pad}git pull --ff-only --autostash *"
            break
        }
        'update' {
            Show-CommandPreview -CommandName 'pull'
            Show-CommandPreview -CommandName 'commit'
            break
        }
        'sync' {
            Show-CommandPreview -CommandName 'update'
            Write-PlainLine "${pad}git push (branch '$(Get-CurrentBranch)') *"
            break
        }
        'br-create' {
            ## From main/dev the dirty tree rides along to the new branch, so there's no commit here.
            if (Test-ProtectedBranch) {
                Write-PlainLine "${pad}git checkout $(Get-MergeTarget) *"
                Write-PlainLine "${pad}git pull --ff-only --autostash *"
            } else {
                Show-CommandPreview -CommandName 'sync'
                Write-PlainLine "${pad}git checkout $(Get-MergeTarget) *"
                Write-PlainLine "${pad}git pull --ff-only *"
            }
            Write-PlainLine "${pad}git checkout -b $($script:cmdArg)"
            Write-PlainLine "${pad}git push -u origin $($script:cmdArg) *"
            break
        }
        'br-hotfix' {
            ## Off the default branch, not dev: this corrects what is already published.
            if (Test-ProtectedBranch) {
                Write-PlainLine "${pad}git checkout $(Get-DefaultBranch) *"
                Write-PlainLine "${pad}git pull --ff-only --autostash *"
            } else {
                Show-CommandPreview -CommandName 'sync'
                Write-PlainLine "${pad}git checkout $(Get-DefaultBranch) *"
                Write-PlainLine "${pad}git pull --ff-only *"
            }
            Write-PlainLine "${pad}git checkout -b $($script:cmdArg)"
            Write-PlainLine "${pad}git push -u origin $($script:cmdArg) *"
            break
        }
        'br-switch' {
            $target = if ($script:cmdArg) { $script:cmdArg } else { Get-MergeTarget }
            ## Already on the target: nothing is parked and no checkout happens, so the plan must
            ## not promise an add/commit/push it will not do.
            if ((Get-CurrentBranch) -cne $target) {
                Show-CommandPreview -CommandName 'sync'
                Write-PlainLine "${pad}git checkout ${target}"
            }
            Write-PlainLine "${pad}git pull --ff-only *"
            break
        }
        'br-land' {
            Show-CommandPreview -CommandName 'sync'
            Write-PlainLine "${pad}git checkout $(Get-BranchTarget)"
            Write-PlainLine "${pad}git pull --ff-only *"
            Write-PlainLine "${pad}git merge --no-ff $(Get-CurrentBranch)"
            Write-PlainLine "${pad}git push *"
            Write-PlainLine "${pad}git branch -d $(Get-CurrentBranch)"
            Write-PlainLine "${pad}git push origin --delete $(Get-CurrentBranch) *"
            Write-PlainLine "${pad}git pull --ff-only *"
            ## A hotfix owes dev the same change, or the next release undoes it.
            if (Test-HotfixBranch) {
                Write-PlainLine "${pad}git checkout $(Get-MergeTarget)"
                Write-PlainLine "${pad}git merge $(Get-BackMergeRef)"
                Write-PlainLine "${pad}git push *"
            }
            break
        }
        'br-prune' {
            ## -D is what runs, so -D is what the plan says. The line above it is the reason
            ## that's safe: gitsby checked containment itself, against the branch that matters.
            Write-PlainLine "${pad}(each verified contained in $(Get-MergeTarget), and re-checked at delete time)"
            foreach ($branch in $script:pruneLocal)  { Write-PlainLine "${pad}git branch -D ${branch}" }
            foreach ($branch in $script:pruneRemote) { Write-PlainLine "${pad}git push origin --delete ${branch}" }
            if ($script:pruneCurrentMerged) { Write-PlainLine "${pad}Keeping '$($script:pruneCurrentMerged)' - merged, but it's the current branch." }
            if ($script:pruneKeep.Count -gt 0) { Write-PlainLine "${pad}Keeping (not merged yet): $($script:pruneKeep -join ', ')" }
            break
        }
        'repo-clone' {
            Write-PlainLine "${pad}git clone $(Get-MaskedUrl -Url $script:cloneUrl) $($script:cloneDir)"
            Write-PlainLine "${pad}git -C $($script:cloneDir) checkout dev *"
            break
        }
        { $_ -in 'repo-create', 'repo-connect' } {
            if (-not $script:inRepo) { Write-PlainLine "${pad}git init -b main" }
            Show-CommandPreview -CommandName 'commit'
            switch ($script:connectMode) {
                'create' {
                    Write-PlainLine "${pad}gh repo create $($script:ghTarget) --$($script:repoVisibility) --source . --push --remote origin"
                    break
                }
                'add' {
                    Write-PlainLine "${pad}git remote add origin $(Get-MaskedUrl -Url $script:connectUrl)"
                    Write-PlainLine "${pad}git push -u origin HEAD"
                    break
                }
                'push' {
                    Write-PlainLine "${pad}git push -u origin HEAD *"
                    break
                }
            }
            break
        }
        'pr' {
            if ($script:prSub -eq 'create') {
                Show-CommandPreview -CommandName 'sync'
                Write-PlainLine "${pad}gh pr create --base $(Get-BranchTarget) --title `"$($script:prTitle)`""
            } else {
                Write-PlainLine "${pad}gh pr review $($script:prNum) --approve *"
                Write-PlainLine "${pad}gh pr merge $($script:prNum) --merge --delete-branch"
                Write-PlainLine "${pad}git checkout $(Get-BranchTarget -Branch $script:prHeadBranch) *"
                Write-PlainLine "${pad}git pull --ff-only *"
                if (Test-HotfixBranch -Branch $script:prHeadBranch) {
                    Write-PlainLine "${pad}git checkout $(Get-MergeTarget)"
                    Write-PlainLine "${pad}git merge $(Get-BackMergeRef)"
                    Write-PlainLine "${pad}git push *"
                }
            }
            break
        }
        'release' {
            Show-CommandPreview -CommandName 'sync'
            if ((Get-MergeTarget) -eq 'dev') {
                Write-PlainLine "${pad}git checkout dev *"
                Write-PlainLine "${pad}git pull --ff-only *"
            }
            Write-PlainLine "${pad}git checkout $(Get-DefaultBranch) *"
            Write-PlainLine "${pad}git pull --ff-only *"
            if ((Get-MergeTarget) -eq 'dev') { Write-PlainLine "${pad}git merge --no-ff dev" }
            Write-PlainLine "${pad}git tag -a $($script:releaseTag)"
            Write-PlainLine "${pad}git push *"
            Write-PlainLine "${pad}git push origin $($script:releaseTag) *"
            if ((Get-MergeTarget) -eq 'dev') {
                Write-PlainLine "${pad}git checkout dev *"
                Write-PlainLine "${pad}git merge --ff-only $(Get-DefaultBranch) *"
                Write-PlainLine "${pad}git push *"
            }
            Write-PlainLine "${pad}git checkout $(Get-CurrentBranch) *"
            break
        }
    }
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Commands

function Invoke-GitsbyCommit {
    ## Never stage a conflicted tree. 'git add --all' marks a conflicted file resolved, so the
    ## markers themselves would be committed, and then pushed by sync. Ordinary use reaches this:
    ## a pull whose autostash reapply conflicts still exits 0, so nothing upstream of here notices.
    $conflicted = git diff --name-only --diff-filter=U 2>$null
    if ($conflicted -and @($conflicted).Count -gt 0) {
        Write-PlainLine ''
        Write-StatusLine 'Unresolved conflicts; nothing was committed:'
        [void](Show-CappedList -GitArgs @('diff', '--name-only', '--diff-filter=U'))
        throw "Resolve those, then run '$($script:meName) update' again. Git also kept your pre-pull tree - see 'git stash list'."
    }
    Invoke-Git -GitArgs @('add', '--all')
    if (-not (Test-GitDirty)) {
        Write-StatusLine 'Nothing to commit.'
    } elseif ($script:commitMessage) {
        Invoke-Git -GitArgs @('commit', '-m', $script:commitMessage)
    } elseif ($script:doQuietly) {
        ## quiet mode can't open an editor
        Invoke-Git -GitArgs @('commit', '-m', "${script:meName} $(Get-Date -Format 'yyyyMMdd-HHmmss')")
    } else {
        Invoke-Git -GitArgs @('commit')
    }
}

function Invoke-GitsbyPull {
    ## --autostash instead of a manual stash push/pop: a failed pull (diverged, offline)
    ## leaves the tree intact instead of stranding work in the stash.
    ## Skipping beats failing when the remote is simply out of reach: update is the only
    ## way to commit, so being offline must not turn a good commit into a failed command.
    ## A reachable remote that can't fast-forward is a real problem and still fails hard.
    if ($script:noFetch) {
        Write-StatusLine 'Skipping the pull (-NoFetch).'
    } elseif (-not $script:remoteReachable) {
        Write-StatusLine 'WARNING: remote unreachable; skipping the pull. Local changes still get committed.'
    } elseif (Test-GitUpstream) {
        Invoke-Git -GitArgs @('pull', '--ff-only', '--autostash')
    } else {
        Write-StatusLine 'No upstream configured for this branch; nothing to pull.'
    }
}

function Invoke-GitsbyPullIfOnline {
    ## The pull inside a multi-step command. Same offline rule as Invoke-GitsbyPull, quietly:
    ## -NoFetch and an unreachable remote both mean skip. Extra arguments go through to git pull.
    param([string[]]$ExtraArgs = @())
    if ($script:noFetch -or -not $script:remoteReachable -or -not (Test-GitUpstream)) { return }
    Invoke-Git -GitArgs (@('pull', '--ff-only') + $ExtraArgs)
}

function Test-Offline {
    ## Set by the pre-command fetch, which is the only thing that actually asks origin. -NoFetch
    ## is NOT offline: it declines the incoming round trip, and pushes still go out (a local or
    ## fast remote with nothing to pull is the ordinary reason to pass it). Skipping the fetch does
    ## mean gitsby was never told you are offline, so a push then fails with git's own message.
    return (-not $script:remoteReachable)
}

function Assert-Online {
    ## Commands that exist to publish, refused before the preview promises a push rather than
    ## halfway through on raw git text - and far better than "succeeding" having sent nothing.
    param([Parameter(Mandatory)][string]$CommandName, [Parameter(Mandatory)][string]$Instead)
    if (-not (Test-Offline)) { return }
    throw "Can't reach origin, and '${CommandName}' has nothing left to do without it. ${Instead}"
}

function Invoke-GitsbyPushIfOnline {
    ## The park push, for a command that still means something without it. The commands that
    ## exist to publish never get here - they are refused up front - so nothing reports success
    ## having sent nothing. Silence would read as published, hence the note - which names the
    ## branch, because the command may move off it next (br switch, land), and a 'sync' from
    ## wherever you end up would publish that branch, not this one.
    if (-not (Test-GitOrigin)) { Write-StatusLine "No 'origin' remote; nothing to push."; return }
    if ((Test-GitUpstream) -and -not (Test-GitAhead)) {
        Write-StatusLine 'Nothing to push.'  ## true offline too: nothing local is ahead of the last-known origin
    } elseif (Test-Offline) {
        Write-StatusLine "WARNING: remote unreachable; skipping the push. The work stays local on '$(Get-CurrentBranch)' - '$($script:meName) sync' from it publishes it."
    } elseif (-not (Test-GitUpstream)) {
        Invoke-Git -GitArgs @('push', '-u', 'origin', 'HEAD')  ## first publish of this branch
    } else {
        Invoke-Git -GitArgs @('push')
    }
}

function Publish-NewBranch {
    ## A new branch's own first push, which is separate from the park push above it.
    param([Parameter(Mandatory)][string]$Branch)
    if (-not (Test-GitOrigin)) { return }
    if (Test-Offline) {
        Write-StatusLine "WARNING: remote unreachable; '${Branch}' is local only for now - '$($script:meName) sync' publishes it."
    } else {
        Invoke-Git -GitArgs @('push', '-u', 'origin', $Branch)
    }
}

function Invoke-GitsbyCommitPull {
    ## Pull BEFORE committing. Committing first mints a local commit, so a remote that merely
    ## moved ahead is now diverged and --ff-only refuses - which is the everyday case, not an
    ## edge one. Pulling first fast-forwards (the dirty tree rides over on --autostash) and the
    ## commit lands on top, so history stays linear and --ff-only stays satisfiable.
    Invoke-GitsbyPull
    Invoke-GitsbyCommit
}

function Invoke-GitsbyPush {
    Invoke-GitsbyCommitPull
    Invoke-GitsbyPushIfOnline
}

function Invoke-GitsbyMakeBranch {
    ## Branch-name validation already happened up front in the entry point.
    param([string]$NewBranch = '')
    $baseBranch = Get-MergeTarget
    if (Test-ProtectedBranch) {
        ## Don't commit WIP to main/dev; a dirty tree survives checkout -b, so carry it to the new branch.
        if ((Get-CurrentBranch) -cne $baseBranch) { Invoke-Git -GitArgs @('checkout', $baseBranch) }
        Invoke-GitsbyPullIfOnline -ExtraArgs @('--autostash')
    } else {
        Invoke-GitsbyPush  ## park current work safely first
        Invoke-Git -GitArgs @('checkout', $baseBranch)
        Invoke-GitsbyPullIfOnline
    }
    Invoke-Git -GitArgs @('checkout', '-b', $NewBranch)
    Publish-NewBranch -Branch $NewBranch
}

function Invoke-GitsbyHotfix {
    ## A branch off the default branch, for correcting what is already published. Feature work
    ## still goes through dev; this exists because the default branch is what the world reads.
    param([string]$NewBranch = '')
    $baseBranch = Get-DefaultBranch
    if (Test-ProtectedBranch) {
        ## Same rule as br create: don't commit work-in-progress to a protected branch, carry it.
        if ((Get-CurrentBranch) -cne $baseBranch) { Invoke-Git -GitArgs @('checkout', $baseBranch) }
        Invoke-GitsbyPullIfOnline -ExtraArgs @('--autostash')
    } else {
        Invoke-GitsbyPush  ## park current work safely first
        Invoke-Git -GitArgs @('checkout', $baseBranch)
        Invoke-GitsbyPullIfOnline
    }
    Invoke-Git -GitArgs @('checkout', '-b', $NewBranch)
    Publish-NewBranch -Branch $NewBranch
}

function Invoke-GitsbyChangeBranch {
    param([string]$TargetBranch = '')
    if (-not $TargetBranch) { $TargetBranch = Get-MergeTarget }
    if ((Get-CurrentBranch) -ceq $TargetBranch) {  ## -ceq: branch names are case-sensitive
        Write-StatusLine "Already on '${TargetBranch}'."
        Invoke-GitsbyPullIfOnline
        return
    }
    ## The dirty-protected-branch refusal happens up front in the entry point, before the plan is shown.
    Invoke-GitsbyPush  ## park current work safely first
    Invoke-Git -GitArgs @('checkout', $TargetBranch)  ## auto-creates a tracking branch if it only exists on origin
    Invoke-GitsbyPullIfOnline
}

function Invoke-GitsbyLand {
    ## Merges the current branch into dev (or main/master) - backwards from 'git merge', but saves a step.
    $workBranch = Get-CurrentBranch
    $targetBranch = Get-BranchTarget -Branch $workBranch
    if ($workBranch -ceq $targetBranch) { throw "Already on '${targetBranch}'. Run this from the branch to merge in: ${script:meName} br switch <branch>, then ${script:meName} br land" }
    if ($workBranch -ceq (Get-DefaultBranch)) { throw "'${workBranch}' is the default branch; landing it on '${targetBranch}' is backwards. To cut a release: ${script:meName} release" }
    $mergeMessage = $script:commitMessage
    if (-not $mergeMessage) { $mergeMessage = "Merge ${workBranch}" }
    $wasHotfix = Test-HotfixBranch -Branch $workBranch
    Invoke-GitsbyPush
    ## After the push, not before: the warning reads the branch tip, and uncommitted work
    ## only becomes part of it here. Checking first missed a hotfix whose bin/ edit was
    ## still in the working tree - the ordinary way of doing one.
    if ($wasHotfix) { Show-HotfixBinWarning -WorkBranch $workBranch -TargetBranch $targetBranch }
    Invoke-Git -GitArgs @('checkout', $targetBranch)
    Invoke-GitsbyPullIfOnline
    Invoke-Git -GitArgs @('merge', '--no-ff', $workBranch, '-m', $mergeMessage)
    ## The merge must reach origin before the remote work branch goes away, or origin
    ## loses its only ref to those commits. Publish an upstream-less target first.
    $mergePublished = $false
    if (Test-GitOrigin) {
        if (Test-Offline) {
            ## A hotfix ends on dev after the back-merge, so a bare 'sync' from there would publish
            ## dev and leave the default branch - the branch the hotfix exists to fix - stale on
            ## origin. The switch's park push publishes dev on the way, so two commands cover both.
            if ($wasHotfix) {
                Write-StatusLine "WARNING: remote unreachable; the merge to '${targetBranch}' is local only - once online, '$($script:meName) br switch ${targetBranch}' then '$($script:meName) sync' publishes it."
            } else {
                Write-StatusLine "WARNING: remote unreachable; the merge to '${targetBranch}' is local only - '$($script:meName) sync' publishes it."
            }
        } else {
            if (Test-GitUpstream) { Invoke-Git -GitArgs @('push') } else { Invoke-Git -GitArgs @('push', '-u', 'origin', 'HEAD') }
            $mergePublished = $true
        }
    }
    Invoke-Git -GitArgs @('branch', '-d', $workBranch)
    if (-not $mergePublished -and (Test-GitBranchRemote -Branch $workBranch)) {
        ## The same rule as above, from the other side: with the merge still unpublished,
        ## origin's copy of the branch is its only ref to those commits.
        Write-StatusLine "Leaving origin's '${workBranch}' alone until the merge is pushed; '$($script:meName) br prune' clears it later."
    } elseif (Test-GitBranchRemote -Branch $workBranch) {
        ## Non-fatal: someone (a PR merge, another clone) may have deleted it already.
        Write-PlainLine ''
        Write-StatusLine "git push origin --delete ${workBranch} ..."
        git push origin --delete $workBranch
        if ($LASTEXITCODE -ne 0) { Write-StatusLine "WARNING: couldn't delete the remote branch (already gone?); continuing." }
        Clear-BlankCounter
    }
    Invoke-GitsbyPullIfOnline
    ## The hotfix now has to reach dev too, or the next release undoes it.
    if ($wasHotfix) { Invoke-BackMergeToDev }
}

function Invoke-GitsbyPrune {
    ## Deletes exactly what the plan listed - Resolve-PruneList did all the deciding, up front.
    $doneLocal = 0
    $doneRemote = 0
    $reKept = @()
    foreach ($branch in $script:pruneLocal) {
        ## -D with our own gate, not -d. 'git branch -d' asks whether the branch is contained in
        ## its upstream, or in HEAD when it has none - neither of which is the question here, and
        ## the second one refuses a genuinely-merged local-only branch from any other branch.
        ## Re-checked right now rather than trusting the plan: the prompt may have sat a while.
        if (-not (Test-MergedInto -Ref "refs/heads/${branch}" -IntoRefs $script:pruneTargetRefs)) {
            Write-StatusLine "'${branch}' is no longer contained in $(Get-MergeTarget); leaving it alone."
            $reKept += $branch
            continue
        }
        Invoke-Git -GitArgs @('branch', '-D', $branch)
        $doneLocal++
    }
    foreach ($branch in $script:pruneRemote) {
        ## "Leaving it alone" has to mean the remote copy too, or the message is a lie.
        if ($branch -cin $reKept) { continue }
        ## Non-fatal, same as br land: someone else may have deleted it already.
        Write-PlainLine ''
        Write-StatusLine "git push origin --delete ${branch} ..."
        git push origin --delete "$branch"
        if ($LASTEXITCODE -ne 0) {
            Write-StatusLine "WARNING: couldn't delete origin/${branch} (already gone?); continuing."
        } else {
            $doneRemote++
        }
        Clear-BlankCounter
    }
    ## Close with the count, so a wall of git output still ends in a plain answer.
    Write-PlainLine ''
    Write-StatusLine "Pruned ${doneLocal} local, ${doneRemote} on origin."
    if ($script:pruneCurrentMerged) {
        Write-StatusLine "Kept '$($script:pruneCurrentMerged)' - merged, but it's the current branch."
    }
    if ($script:pruneKeep.Count -gt 0) {
        Write-StatusLine "Kept $($script:pruneKeep -join ', ') - not merged into $(Get-MergeTarget) yet."
    }
}

function Invoke-GitsbyClone {
    Invoke-Git -GitArgs @('clone', $script:cloneUrl, $script:cloneDir)
    ## Opinionated: if the repo works dev-first, start there.
    git -C "$script:cloneDir" show-ref --verify --quiet refs/remotes/origin/dev *> $null
    if ($LASTEXITCODE -eq 0) { Invoke-Git -GitArgs @('-C', $script:cloneDir, 'checkout', 'dev') }
}

## Serves both 'repo create' and 'repo connect'; connectMode is what they disagree about.
function Invoke-GitsbyConnect {
    if (-not $script:inRepo) { Invoke-Git -GitArgs @('init', '-b', 'main') }
    Invoke-GitsbyCommit  ## publish everything as-is; no-op when clean
    switch ($script:connectMode) {
        'create' {
            Write-PlainLine ''
            Write-StatusLine "gh repo create $($script:ghTarget) --$($script:repoVisibility) --source . --push --remote origin ..."
            gh repo create "$script:ghTarget" "--$($script:repoVisibility)" --source . --push --remote origin
            if ($LASTEXITCODE -ne 0) { throw "'gh repo create' failed (exit ${LASTEXITCODE})." }
            Clear-BlankCounter
            break
        }
        'add' {
            Invoke-Git -GitArgs @('remote', 'add', 'origin', $script:connectUrl)
            Invoke-Git -GitArgs @('push', '-u', 'origin', 'HEAD')
            break
        }
        'push' {
            ## origin already set - just make sure everything is published
            if (-not (Test-GitUpstream)) { Invoke-Git -GitArgs @('push', '-u', 'origin', 'HEAD') }
            elseif (Test-GitAhead) { Invoke-Git -GitArgs @('push') }
            else { Write-StatusLine 'Nothing to push; already connected and current.' }
            break
        }
    }
}

function Invoke-GitsbyPrView {
    ## Bare: list open PRs. With a number: view it plus its diff.
    param([string]$PrNumber = '')
    if (-not $PrNumber) {
        Write-PlainLine ''
        Write-StatusLine 'gh pr list ...'
        gh pr list
        if ($LASTEXITCODE -ne 0) { throw "'gh pr list' failed (exit ${LASTEXITCODE})." }
    } else {
        Write-PlainLine ''
        Write-StatusLine "gh pr view ${PrNumber} ..."
        gh pr view $PrNumber
        if ($LASTEXITCODE -ne 0) { throw "'gh pr view ${PrNumber}' failed (exit ${LASTEXITCODE})." }
        Write-PlainLine ''
        Write-StatusLine "gh pr diff ${PrNumber} ..."
        gh pr diff $PrNumber
        if ($LASTEXITCODE -ne 0) { throw "'gh pr diff ${PrNumber}' failed (exit ${LASTEXITCODE})." }
    }
    Clear-BlankCounter
}

function Invoke-GitsbyPrCreate {
    ## GitHub can only diff what origin has, so park the work first - same as br land and release do.
    param([Parameter(Mandatory)][string]$Title)
    Invoke-GitsbyPush
    $base = Get-BranchTarget
    $head = Get-CurrentBranch
    Write-PlainLine ''
    Write-StatusLine "gh pr create --base ${base} --title `"${Title}`" ..."
    gh pr create --base "$base" --head "$head" --title "$Title" --body ''
    if ($LASTEXITCODE -ne 0) { throw "gh pr create failed (exit ${LASTEXITCODE})." }
    Clear-BlankCounter
}

function Invoke-GitsbyPrAccept {
    param([Parameter(Mandatory)][string]$PrNumber)
    ## Resolve both before gh deletes the branch out from under us, and off the PR's own head
    ## branch (resolved up front) rather than the current one - they need not be the same.
    $prTargetBranch = Get-BranchTarget -Branch $script:prHeadBranch
    $wasHotfixPr = Test-HotfixBranch -Branch $script:prHeadBranch
    Write-PlainLine ''
    Write-StatusLine "gh pr review ${PrNumber} --approve ..."
    ## Best-effort: gh refuses to approve your own PR; merging is the part that matters.
    gh pr review $PrNumber --approve
    if ($LASTEXITCODE -ne 0) { Write-StatusLine 'Could not approve (own PR?); merging anyway.' }
    Clear-BlankCounter
    Write-PlainLine ''
    Write-StatusLine "gh pr merge ${PrNumber} --merge --delete-branch ..."
    gh pr merge $PrNumber --merge --delete-branch
    if ($LASTEXITCODE -ne 0) { throw "gh pr merge failed (exit ${LASTEXITCODE})." }
    Clear-BlankCounter
    ## gh deletes the PR's branch on the remote but leaves our origin/* copy behind, so an
    ## upstream still looks present. Prune first; if ours is the branch that just went away,
    ## pulling it can only fail - land on the merge target instead.
    ## Through the same helper as the entry-point fetch: a bare fetch here would prompt for https
    ## credentials mid-command, skip the ssh timeout, and turn a blip into a reported failure
    ## after the merge already landed server-side. Not gated on -NoFetch, same as bash: gh has
    ## just merged over the network, so we are demonstrably online, and pruning the branch gh
    ## deleted is what keeps the pull below from asking for a ref that no longer exists.
    Sync-Remote
    if (-not (Test-GitUpstream)) { Invoke-Git -GitArgs @('checkout', $prTargetBranch) }
    Invoke-GitsbyPullIfOnline
    ## Same rule as land: a hotfix that reached the default branch still owes dev a merge.
    if ($wasHotfixPr) { Invoke-BackMergeToDev }
}

function Invoke-GitsbyRelease {
    ## Cuts a release: merge dev into main/master --no-ff (if the repo has a dev), tag, push both.
    $mainBranch = Get-DefaultBranch
    $devBranch = ''
    if ((Test-GitBranchLocal -Branch 'dev') -or (Test-GitBranchRemote -Branch 'dev')) { $devBranch = 'dev' }
    $startBranch = Get-CurrentBranch
    Invoke-GitsbyPush  ## park current work safely first
    if ($devBranch -and ((Get-CurrentBranch) -cne $devBranch)) {
        Invoke-Git -GitArgs @('checkout', $devBranch)  ## freshen dev so the release has all of it
        Invoke-GitsbyPullIfOnline
    }
    if ((Get-CurrentBranch) -cne $mainBranch) { Invoke-Git -GitArgs @('checkout', $mainBranch) }
    Invoke-GitsbyPullIfOnline
    if ($devBranch) {
        $mergeMessage = $script:commitMessage
        if (-not $mergeMessage) { $mergeMessage = "Release $($script:releaseTag)" }
        Invoke-Git -GitArgs @('merge', '--no-ff', $devBranch, '-m', $mergeMessage)
    }
    Invoke-Git -GitArgs @('tag', '-a', $script:releaseTag, '-m', $script:releaseTag)
    ## The branch has to reach origin, not just the tag - otherwise origin gets the commits
    ## as tag payload while its main still points at the old release. Same trap as land's.
    if (Test-GitOrigin) {
        if (Test-GitUpstream) { Invoke-Git -GitArgs @('push') } else { Invoke-Git -GitArgs @('push', '-u', 'origin', 'HEAD') }
        Invoke-Git -GitArgs @('push', 'origin', $script:releaseTag)
    }
    ## Fast-forward dev to include the release merge and tag, so dev isn't left a commit behind.
    ## ff-only (not branch -f): if dev moved mid-release, skip rather than discard work.
    if ($devBranch) {
        git merge-base --is-ancestor $devBranch $mainBranch *> $null
        if ($LASTEXITCODE -eq 0) {
            Invoke-Git -GitArgs @('checkout', $devBranch)
            Invoke-Git -GitArgs @('merge', '--ff-only', $mainBranch)
            if (Test-GitUpstream) { Invoke-Git -GitArgs @('push') }
        } else {
            Write-StatusLine "WARNING: '${devBranch}' gained commits during the release; leaving it as-is."
        }
    }
    ## Don't leave the user parked on main.
    if ($startBranch -and ($startBranch -cne (Get-CurrentBranch)) -and ($startBranch -cne $mainBranch)) { Invoke-Git -GitArgs @('checkout', $startBranch) }
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Script entry point

try {
    ## pwsh doesn't bind '--help'-style tokens as parameters; they land positionally.
    ## The bare words 'help' and 'version' work too.
    if ($Command -match '^(-{1,2}(h|help)|help)$') { $Help = $true; $Command = '' }
    if ($Command -match '^(-{1,2}(v|ver|version)|version)$') { $Version = $true; $Command = '' }

    ## -h and -v bind from any position under pwsh, unlike bash where they are option tokens.
    ## Help is allowed anywhere on purpose ('br create --help' is the reflex every git user has),
    ## but -v alongside a command must not silently turn it into a version print that does no work.
    if ($Version -and $Command) { throw "Unexpected option in this context: '-v'." }
    ## Both visibilities given is a contradiction, not a precedence question - and silently
    ## picking one would publish a repo the caller believes is the other. The two ports used to
    ## resolve it in opposite directions.
    if ($Public -and $Private) { throw '--public and --private are mutually exclusive; pick one.' }
    if ($Help) { Show-Copyright; Show-About; Show-Syntax; Write-PlainLine ''; exit 0 }
    if ($Version) { Show-Copyright; exit 0 }
    if (-not $Command) { Show-Copyright; Show-About; Show-Syntax; exit 1 }

    ## Breathing room after the shell prompt (the matching trailing blank is at each exit path).
    Write-PlainLine ''

    if (-not (Get-Command -Name git -ErrorAction SilentlyContinue)) { throw 'Not found in path: git' }

    ## Anything else option-shaped in the positional slots is a mistake, not data.
    if ($Command -match '^--?[^ -]') { throw "Unexpected option in this context: '${Command}'." }
    if ($CommandArg -match '^--$|^--?[^ -]') { throw "Unexpected option in this context: '${CommandArg}'." }
    if ($CommandArg2 -match '^--$|^--?[^ -]') { throw "Unexpected option in this context: '${CommandArg2}'." }
    if ($CommandArg3 -match '^--$|^--?[^ -]') { throw "Unexpected option in this context: '${CommandArg3}'." }

    ## Grouped commands are '<noun> <verb> [args]'. Collapse each pair to one internal token and
    ## shift the positionals down, so everything downstream still deals with a single flat name.
    ## No real command has a hyphen, so rejecting one keeps the internal tokens from being typeable.
    $cmdName = $Command.ToLowerInvariant()
    if ($cmdName -like '*-*') { throw "Unknown command '${cmdName}'. Run '$($script:meName)' with no arguments for a list." }
    if ($cmdName -in 'repo', 'repository') {
        $cmdName = switch ($CommandArg.ToLowerInvariant()) {
            'clone' { 'repo-clone'; break }
            { $_ -in 'create', 'new' } { 'repo-create'; break }
            'connect' { 'repo-connect'; break }
            '' { throw "Syntax: $($script:meName) repo <clone <url> [dir] | create <owner/name> | connect [url]>" }
            default { throw "Unknown 'repo' subcommand '${CommandArg}'. One of: clone, create, connect." }
        }
        $CommandArg = $CommandArg2; $CommandArg2 = $CommandArg3; $CommandArg3 = ''
    } elseif ($cmdName -in 'br', 'branch') {
        $cmdName = switch ($CommandArg.ToLowerInvariant()) {
            { $_ -in '', 'list' } { 'br-list'; break }
            { $_ -in 'create', 'new' } { 'br-create'; break }
            'hotfix' { 'br-hotfix'; break }
            { $_ -in 'switch', 'go' } { 'br-switch'; break }
            'land' { 'br-land'; break }
            { $_ -in 'prune', 'clean' } { 'br-prune'; break }
            default { throw "Unknown 'br' subcommand '${CommandArg}'. One of: list, create, hotfix, switch, land, prune." }
        }
        $CommandArg = $CommandArg2; $CommandArg2 = $CommandArg3; $CommandArg3 = ''
    }
    $script:cmdArg = $CommandArg  ## the preview reads this; re-point it after the shift

    ## Sort commands, and route positional arg 2 (message vs branch name; -m wins for messages).
    $isMutating = $true
    switch ($cmdName) {
        ## Trailing arguments are rejected everywhere else, so silently ignoring them here would
        ## make a typo look like it did what you meant. 'br list' extra lands in cmdArg too.
        { $_ -in 'status', 'br-list' } {
            $isMutating = $false
            if ($script:cmdArg) { throw "'$($script:meName) $($cmdName -replace 'br-list', 'br list')' takes no arguments (got '$($script:cmdArg)')." }
            break
        }
        'pr' { if ($CommandArg.ToLowerInvariant() -notin 'ok', 'create', 'new') { $isMutating = $false }; break }
        { $_ -in 'update', 'sync', 'br-land' } {
            if (-not $script:commitMessage) { $script:commitMessage = $CommandArg }
            if ($CommandArg2) { throw "Unexpected extra argument '${CommandArg2}'; quote your commit message." }
            break
        }
        'repo-clone' { break }  ## the only one with a second argument of its own (the target directory)
        'br-prune' {
            ## Takes nothing: what it deletes is decided by repo state, never by a name on the command line.
            if ($CommandArg) { throw "'$($script:meName) br prune' takes no arguments (got '${CommandArg}'); it prunes every branch already merged." }
            break
        }
        { $_ -in 'br-create', 'br-hotfix', 'br-switch', 'release', 'repo-create', 'repo-connect' } {
            if ($CommandArg2) { throw "Unexpected extra argument '${CommandArg2}'." }
            break
        }
        default { throw "Unknown command '${cmdName}'. Run '${script:meName}' with no arguments for a list." }
    }
    if ($CommandArg3) { throw "Unexpected extra argument '${CommandArg3}'." }

    ## No tty = nobody to answer a prompt. Read-only commands just go quiet; mutating
    ## ones fail closed (require an explicit -Quiet) so piped/cron input can't silently auto-confirm.
    if ([Console]::IsInputRedirected) {
        if ($isMutating -and -not $script:doQuietly) { throw 'No terminal to confirm on; re-run with -q to proceed without prompts.' }
        $script:doQuietly = $true
    }

    ## pr needs gh and a valid number (except the bare list form).
    $script:prNum = ''
    $script:prSub = ''
    $script:prTitle = ''
    $script:prHeadBranch = ''
    if ($cmdName -eq 'pr') {
        if (-not (Get-Command -Name gh -ErrorAction SilentlyContinue)) { throw 'Not found in path: gh' }
        switch ($CommandArg.ToLowerInvariant()) {
            'ok' {
                $script:prSub = 'ok'
                $script:prNum = $CommandArg2
                if ($script:prNum -notmatch '^[0-9]+$') { throw "Syntax: ${script:meName} pr ok <number>" }
                break
            }
            { $_ -in 'create', 'new' } {
                $script:prSub = 'create'
                ## -m wins, same as everywhere else.
                $script:prTitle = if ($script:commitMessage) { $script:commitMessage } else { $CommandArg2 }
                break
            }
            '' { break }
            default {
                $script:prNum = $CommandArg
                if ($script:prNum -notmatch '^[0-9]+$') { throw "Syntax: ${script:meName} pr [create [title] | <number> | ok <number>]" }
                break
            }
        }
    }

    ## Every command needs a repo - except the repo ones: clone works anywhere, and create/connect
    ## exist precisely to turn a plain directory into one.
    git rev-parse --is-inside-work-tree *> $null
    $script:inRepo = ($LASTEXITCODE -eq 0)
    if (-not $script:inRepo -and $cmdName -notlike 'repo-*') { throw 'Not inside a git repository. Change to a git project directory first.' }

    ## Freshen remote refs so status/ahead-behind info is current. Never fatal - offline still works locally.
    ## --prune: stale origin/* refs would fool the existence checks. set-head heals a missing/stale
    ## origin/HEAD. ssh gets a connect timeout so a dead remote can't hang every command for minutes.
    ## clone skips it: cwd may sit inside some unrelated repo, and the clone doesn't care about it.
    if (-not $NoFetch -and $cmdName -ne 'repo-clone' -and (Test-GitOrigin)) {
        Write-StatusLine 'git fetch ...'
        Sync-Remote
    }

    ## These can't change mid-command, so resolve them once (post-fetch, so origin/HEAD is fresh).
    if ($script:inRepo) {
        $script:defaultBranchCache = Get-DefaultBranch
        $script:mergeTargetCache = Get-MergeTarget
        ## Every branch command checks this out, protects it, or merges into it, so a name we
        ## can't confirm has to stop things here - before a preview promises it and the park step
        ## commits WIP to a branch we wrongly judged unprotected. 'repo *' predates having one.
        ## 'status' and 'br list' are exempt on purpose: they mutate nothing and are the commands
        ## you run to see what is wrong, so they report "unknown" instead of refusing.
        git rev-parse -q --verify HEAD *> $null
        if ($LASTEXITCODE -eq 0 -and $cmdName -cne 'status' -and $cmdName -cne 'br-list' -and $cmdName -notlike 'repo-*') {
            if (-not $script:defaultBranchCache) {
                throw "Can't tell this repo's default branch. Set it with 'git remote set-head origin --auto', or create a main/master."
            }
            if (-not ((Test-GitBranchLocal -Branch $script:defaultBranchCache) -or (Test-GitBranchRemote -Branch $script:defaultBranchCache))) {
                throw "This repo's default branch resolves to '$($script:defaultBranchCache)', which exists neither here nor on origin. Fix it with 'git remote set-head origin --auto'."
            }
        }
    }

    ## Commands that exist to publish, refused here rather than halfway through on raw git text -
    ## and far better than "succeeding" having sent nothing. The rest degrade instead: they mean
    ## something locally, so they run and say what they skipped.
    switch ($cmdName) {
        'sync'    { Assert-Online -CommandName 'sync' -Instead "Commit locally with '$($script:meName) update', then '$($script:meName) sync' when you are back online."; break }
        'release' { Assert-Online -CommandName 'release' -Instead "A release nobody can fetch isn't one."; break }
        'pr' {
            if ($script:prSub -ceq 'create' -or $script:prSub -ceq 'ok') {
                Assert-Online -CommandName "pr $($script:prSub)" -Instead 'The pull request lives on GitHub; there is no local half to do first.'
            }
            break
        }
    }

    ## Release version resolves up front so preview and command agree (and bad input dies early).
    $script:releaseTag = ''
    if ($cmdName -eq 'release') {
        $script:releaseTag = Get-ReleaseVersion
        ## Up front, not mid-command: by the time Invoke-GitsbyRelease runs it has already committed and pushed.
        git rev-parse -q --verify "refs/tags/$($script:releaseTag)" *> $null
        if ($LASTEXITCODE -eq 0) { throw "Tag '$($script:releaseTag)' already exists." }
        ## An invented version on a target that would gain nothing cuts a tag for no release, and
        ## the natural re-run after a failed push cuts a second one on the same commit - so the
        ## first is stranded forever. A version you typed, and promoting a candidate, are
        ## deliberate and stay allowed. Fails open: if we can't tell, the release goes ahead.
        ## 'release' parks first, so uncommitted work or unpushed commits ARE something to release
        ## even when the branches currently look level - the guard only speaks for a settled repo.
        if ($script:releaseBumped -and -not (Test-GitDirty) -and -not (Test-GitAhead)) {
            $relMain = Get-DefaultBranch
            $relTarget = if (Test-GitBranchLocal -Branch $relMain) { $relMain } else { "origin/${relMain}" }
            ## The local branch is what gets tagged and pushed, so it is what 'nothing new' is
            ## about. Stand down if origin holds commits we don't: the pull would bring them in.
            $relKnown = $true
            if ($relTarget -ceq $relMain -and (Test-GitBranchRemote -Branch $relMain)) {
                git merge-base --is-ancestor "origin/${relMain}" $relMain 2>$null
                if ($LASTEXITCODE -ne 0) { $relKnown = $false }
            }
            $relSource = ''
            if (Test-GitBranchRemote -Branch 'dev') { $relSource = 'origin/dev' }
            elseif (Test-GitBranchLocal -Branch 'dev') { $relSource = 'dev' }
            $relMerged = $true
            if ($relSource) {
                git merge-base --is-ancestor $relSource $relTarget 2>$null
                $relMerged = ($LASTEXITCODE -eq 0)
            }
            if ($relKnown -and $relMerged) {
                $relExisting = git describe --exact-match --tags $relTarget 2>$null
                if ($LASTEXITCODE -eq 0 -and $relExisting) {
                    throw "Nothing new to release since ${relExisting}. If that tag never reached origin, push it: git push origin ${relExisting}"
                }
            }
        }
    }

    ## The mutating pr subcommands check here too, so nothing can fail after the plan was confirmed.
    if ($script:prSub) {
        $prBranch = Get-CurrentBranch
        if (-not $prBranch) { throw 'Detached HEAD (no current branch); resolve that manually first.' }
        if ($script:prSub -eq 'ok') {
            ## Where a PR lands, and whether it is a hotfix, are properties of the PR - not of
            ## whatever branch you happen to be standing on. 'pr ok <n>' can be run from anywhere,
            ## so ask gh which branch it proposes. Fall back to the current one if gh can't say.
            $headOut = @()
            try { $headOut = @(gh pr view $script:prNum --json headRefName --jq .headRefName 2>$null) } catch { $headOut = @() }
            $script:prHeadBranch = if ($headOut.Count -gt 0) { ([string]$headOut[0]).Trim() } else { '' }
            if (-not $script:prHeadBranch) { $script:prHeadBranch = $prBranch }
            ## gh merges what origin already has, then deletes the branch local and remote. Work
            ## that never reached origin is outside the PR and outside the merge - refuse, don't lose it.
            if ((Test-GitDirty) -or (Test-GitAhead)) {
                if ($prBranch -ceq $script:prHeadBranch) {
                    throw "'${prBranch}' has changes that aren't on origin, so PR #$($script:prNum) can't include them. Run '${script:meName} sync' first."
                }
                throw "'${prBranch}' has changes that aren't on origin. Park them first: ${script:meName} sync"
            }
            ## Standing somewhere else doesn't make the PR's own branch safe: gh deletes it with
            ## 'branch -D', so unpushed commits on it go too, and 'sync' can't reach it from here.
            if (($prBranch -cne $script:prHeadBranch) -and (Test-GitBranchLocal -Branch $script:prHeadBranch)) {
                if (-not (Test-GitBranchRemote -Branch $script:prHeadBranch)) {
                    throw "'$($script:prHeadBranch)' is here but not on origin, so PR #$($script:prNum) holds none of it - and it would be deleted. Push it first: git push -u origin $($script:prHeadBranch)"
                }
                if (Test-GitBranchUnpushed -Branch $script:prHeadBranch) {
                    throw "'$($script:prHeadBranch)' has commits that never reached origin, so PR #$($script:prNum) can't include them - and it would be deleted. Push them first: git push origin $($script:prHeadBranch)"
                }
            }
        } else {
            if ($prBranch -cin @((Get-MergeTarget), (Get-DefaultBranch))) {
                throw "'${prBranch}' is what pull requests merge into; there is nothing to propose. Start a branch first: ${script:meName} br create <name>"
            }
            ## No title given: the last commit subject is what the work is called already.
            if (-not $script:prTitle) { $script:prTitle = (git log -1 --pretty=%s 2>$null | Select-Object -First 1) }
            if (-not $script:prTitle) { throw "No commits on '${prBranch}' yet; nothing to propose." }
            ## An open PR for this branch already is the answer to 'pr create' - say so instead of letting gh error.
            $existingPr = (gh pr list --head "$prBranch" --state open --json number --jq '.[0].number // empty' 2>$null | Select-Object -First 1)
            if ($existingPr) { throw "PR #${existingPr} is already open for '${prBranch}'. View it: ${script:meName} pr ${existingPr}" }
        }
    }

    ## Branch arguments validate up front too, so a bad name can't survive to a nonsense preview.
    if ($cmdName -eq 'br-create') {
        if (-not $CommandArg) { throw "No branch name given. Syntax: ${script:meName} br create <new branch name>" }
        git check-ref-format --branch "$CommandArg" *> $null  ## quote: a bare $var lets PowerShell glob '*'/'?' to filenames, defeating the check
        if ($LASTEXITCODE -ne 0) { throw "'${CommandArg}' is not a valid branch name." }
        if (Test-GitBranchLocal -Branch $CommandArg) { throw "Branch '${CommandArg}' already exists; use: ${script:meName} br switch ${CommandArg}" }
        if (Test-GitBranchRemote -Branch $CommandArg) { throw "Branch '${CommandArg}' already exists on origin; use: ${script:meName} br switch ${CommandArg}" }
    } elseif ($cmdName -eq 'br-hotfix') {
        if (-not $CommandArg) { throw "No name given. Syntax: ${script:meName} br hotfix <name>" }
        ## The prefix is the marker, so put it on ourselves - and accept it if the user typed it.
        $CommandArg = 'hotfix/' + ($CommandArg -replace '^hotfix/', '')
        $script:cmdArg = $CommandArg
        git check-ref-format --branch "$CommandArg" *> $null
        if ($LASTEXITCODE -ne 0) { throw "'${CommandArg}' is not a valid branch name." }
        if (Test-GitBranchLocal -Branch $CommandArg) { throw "Branch '${CommandArg}' already exists; use: ${script:meName} br switch ${CommandArg}" }
        if (Test-GitBranchRemote -Branch $CommandArg) { throw "Branch '${CommandArg}' already exists on origin; use: ${script:meName} br switch ${CommandArg}" }
    } elseif ($cmdName -eq 'br-land') {
        ## Landing ends in 'git branch -d', so a leftover main/master must be refused here for the
        ## same reason br prune never lists one - and up front, not after a destructive plan was shown.
        if (Test-ProtectedBranch) {
            throw "'$(Get-CurrentBranch)' is a protected branch; landing it would delete it. Run this from a work branch instead."
        }
    } elseif ($cmdName -eq 'br-switch') {
        if ($CommandArg -and -not ((Test-GitBranchLocal -Branch $CommandArg) -or (Test-GitBranchRemote -Branch $CommandArg))) {
            throw "No branch '${CommandArg}' locally or on origin. To create it: ${script:meName} br create ${CommandArg}"
        }
        ## Refusing a dirty protected branch belongs here too, before the plan is shown and confirmed.
        $switchTarget = if ($CommandArg) { $CommandArg } else { Get-MergeTarget }
        if (((Get-CurrentBranch) -cne $switchTarget) -and (Test-ProtectedBranch) -and (Test-GitDirty)) {
            throw "Working tree has changes on '$(Get-CurrentBranch)'; won't auto-commit to a protected branch. Carry them to a new branch (${script:meName} br create <name>), or commit them here deliberately (${script:meName} update) first."
        }
    }

    ## br prune: work out what goes before anything is shown, so the plan names every branch by name.
    if ($cmdName -eq 'br-prune') {
        if (-not (Get-CurrentBranch)) { throw 'Detached HEAD (no current branch); resolve that manually first.' }
        Resolve-PruneList
        if ($script:pruneLocal.Count -eq 0 -and $script:pruneRemote.Count -eq 0) {
            ## "no branch is merged" would be a lie when the merged one is the branch we're standing on.
            if ($script:pruneCurrentMerged) {
                Write-StatusLine 'Nothing to prune from here.'
                Write-PlainLine "  Current branch '$($script:pruneCurrentMerged)' is merged, but you're on it; switch off it to prune it."
            } else {
                Write-StatusLine "Nothing to prune; no branch is fully merged into '$(Get-MergeTarget)' yet."
            }
            if ($script:pruneKeep.Count -gt 0) { Write-PlainLine "  Keeping (not merged yet): $($script:pruneKeep -join ', ')" }
            Write-PlainLine ''
            exit 0
        }
    }

    ## repo clone: derive the target dir, and make re-runs a no-op instead of an error.
    if ($cmdName -eq 'repo-clone') {
        if (-not $CommandArg) { throw "No URL given. Syntax: ${script:meName} repo clone <url> [directory]" }
        $script:cloneUrl = $CommandArg
        $script:cloneDir = $CommandArg2
        if (-not $script:cloneDir) {
            $trimmed = $script:cloneUrl.TrimEnd('/') -replace '\.git$', ''
            $script:cloneDir = @($trimmed -split '[/:]')[-1]
            if (-not $script:cloneDir) { throw "Can't derive a directory name from '$(Get-MaskedUrl -Url $script:cloneUrl)'; give one explicitly." }
        }
        if (Test-Path -LiteralPath $script:cloneDir) {
            $existingUrl = git -C "$script:cloneDir" remote get-url origin 2>$null
            if ($LASTEXITCODE -ne 0 -or $null -eq $existingUrl) { $existingUrl = '' }
            if ((Test-Path -LiteralPath (Join-Path -Path $script:cloneDir -ChildPath '.git')) -and (([string]$existingUrl) -ceq $script:cloneUrl)) {
                Write-StatusLine "'$($script:cloneDir)' is already a clone of that URL; nothing to do."
                Write-PlainLine ''
                exit 0
            }
            ## An empty dir is fine (git allows it); anything else would clobber.
            $entries = @(Get-ChildItem -LiteralPath $script:cloneDir -Force -ErrorAction SilentlyContinue)
            if (-not ((Test-Path -LiteralPath $script:cloneDir -PathType Container) -and $entries.Count -eq 0)) {
                throw "'$($script:cloneDir)' already exists and isn't a clone of that URL."
            }
        }
    }

    ## repo create/connect: resolve what we're publishing to before the preview, so the plan is real.
    ## Same machinery, one difference - only 'create' will bring a remote into existence.
    if ($cmdName -in 'repo-create', 'repo-connect') {
        $wantCreate = ($cmdName -eq 'repo-create')
        $hasWork = $false
        if ($script:inRepo) {
            git rev-parse -q --verify HEAD *> $null
            if ($LASTEXITCODE -eq 0 -or (Test-GitDirty)) { $hasWork = $true }
        } elseif (@(Get-ChildItem -Force -ErrorAction SilentlyContinue).Count -gt 0) {
            $hasWork = $true
        }
        if (-not $hasWork) { throw 'Nothing to publish here: no commits and no files.' }
        $originUrl = ''
        if ($script:inRepo -and (Test-GitOrigin)) { $originUrl = [string](git remote get-url origin 2>$null) }
        if ($originUrl) {
            if ($wantCreate) { throw "origin is already set to '$(Get-MaskedUrl -Url $originUrl)', so there is no repo left to create. Push what you have with: ${script:meName} repo connect" }
            if ($CommandArg -and ($CommandArg -cne $originUrl)) { throw "origin is already set to '$(Get-MaskedUrl -Url $originUrl)'; changing remotes is raw-git territory." }
            $script:connectMode = 'push'; $script:connectUrl = $originUrl
        } elseif ($wantCreate) {
            if (-not $CommandArg) { throw "No target given. Syntax: ${script:meName} repo create <owner/name>" }
            if (-not ($CommandArg -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -and -not (Test-Path -LiteralPath $CommandArg))) {
                throw "'${CommandArg}' isn't a GitHub 'owner/name'; only GitHub repos can be created from here. For a remote that already exists: ${script:meName} repo connect ${CommandArg}"
            }
            if (-not (Get-Command -Name gh -ErrorAction SilentlyContinue)) { throw 'Not found in path: gh' }
            $script:ghTarget = $CommandArg
            $isEmpty = gh repo view "$script:ghTarget" --json isEmpty --jq .isEmpty 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $isEmpty) {
                $script:connectMode = 'create'
            } elseif (([string]$isEmpty).Trim() -eq 'true') {
                throw "github.com/$($script:ghTarget) already exists and is empty; connect to it instead: ${script:meName} repo connect $($script:ghTarget)"
            } else {
                throw "github.com/$($script:ghTarget) already has commits; clone it instead (${script:meName} repo clone), or reconcile with raw git."
            }
        } else {
            if (-not $CommandArg) { throw "No remote configured and no target given. Syntax: ${script:meName} repo connect <url | owner/name>" }
            if ($CommandArg -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -and -not (Test-Path -LiteralPath $CommandArg)) {
                ## owner/name shorthand: gh can say whether it exists and whether it's empty.
                if (-not (Get-Command -Name gh -ErrorAction SilentlyContinue)) { throw 'Not found in path: gh' }
                $script:ghTarget = $CommandArg
                $isEmpty = gh repo view "$script:ghTarget" --json isEmpty --jq .isEmpty 2>$null
                if ($LASTEXITCODE -ne 0 -or -not $isEmpty) {
                    throw "github.com/$($script:ghTarget) doesn't exist, or you can't see it. To create it: ${script:meName} repo create $($script:ghTarget)"
                } elseif (([string]$isEmpty).Trim() -eq 'true') {
                    ## gh never uses a host alias, so this is the canonical url - same one gh itself would build.
                    $script:connectUrl = if ((Get-GhProtocol) -eq 'ssh') { "git@github.com:$($script:ghTarget).git" } else { "https://github.com/$($script:ghTarget).git" }
                    $script:connectMode = 'add'
                } else {
                    throw "github.com/$($script:ghTarget) already has commits; clone it instead (${script:meName} repo clone), or reconcile with raw git."
                }
            } else {
                switch (Get-RemoteProbe -Url $CommandArg) {
                    'missing' { throw "Can't reach '$(Get-MaskedUrl -Url $CommandArg)' (doesn't exist, or no access). Create it first, or on GitHub: ${script:meName} repo create <owner/name>" }
                    'nonempty' { throw "'$(Get-MaskedUrl -Url $CommandArg)' already has history; clone it instead (${script:meName} repo clone $(Get-MaskedUrl -Url $CommandArg)), or reconcile with raw git." }
                    'empty' { $script:connectMode = 'add'; $script:connectUrl = $CommandArg }
                }
            }
        }
    }

    ## Which commands go through gh, which of those WRITE through it, and which url the ssh
    ## identity should be read from. For pr that's the origin we already have. repo create and
    ## connect have no origin yet - but the one they are about to set is knowable, because gh
    ## never uses a host alias: it builds 'git@github.com:owner/name.git' from its own protocol
    ## setting. So the identity that repo will live with afterward can be checked before we start.
    switch ($cmdName) {
        'pr' {
            $script:isGhCommand = $true
            if ($script:prSub -in 'create', 'ok') {
                $script:isGhWrite = $true
                $script:identityProbeUrl = [string](@(git remote get-url origin 2>$null) | Select-Object -First 1)
            }
            break
        }
        'repo-create' {
            $script:isGhCommand = $true; $script:isGhWrite = $true
            if ((Get-GhProtocol) -eq 'ssh') { $script:identityProbeUrl = "git@github.com:$($script:ghTarget).git" }
            break
        }
        'repo-connect' {
            if ($script:ghTarget) {
                $script:isGhCommand = $true; $script:isGhWrite = $true
                ## connectUrl is the url we resolved ourselves, so probe that rather than guess.
                if ($script:connectUrl -match '^[^@/]+@[^/:]+:') { $script:identityProbeUrl = $script:connectUrl }
            }
            break
        }
    }

    ## A gh write acting as a different account than the key git pushes with is a wrong-account
    ## mistake waiting to happen, and it is outward-facing. Refuse it unattended (nobody is there
    ## to read a warning); warn interactively, right before the prompt. -AnyIdentity means
    ## the difference is intended.
    ## Before anything reads gh's identity, point the run at the remote's own account when we hold
    ## it. Reads need this as much as writes: 'pr' against a private repo the active account cannot
    ## see fails the same way a write does. -AnyIdentity means hands off.
    if ($script:isGhCommand -and -not $AnyIdentity) {
        $ghOwnerUrl = $script:identityProbeUrl
        if (-not $ghOwnerUrl) { $ghOwnerUrl = [string](@(git remote get-url origin 2>$null) | Select-Object -First 1) }
        Select-GhAccount -Url $ghOwnerUrl
    }

    $identityMismatch = ''
    if ($script:isGhWrite -and -not $AnyIdentity) {
        $identityMismatch = Get-IdentityMismatch -GhLogin (Get-GhLogin) -SshLogin (Get-SshLogin -RemoteUrl $script:identityProbeUrl)
        ## Up front, like every other refusal: don't show a plan we won't run.
        if ($identityMismatch -and $script:doQuietly) { throw "${identityMismatch} Nothing was done. Re-run with -AnyIdentity if that is intended." }
    }

    ## Read-only commands
    if (-not $isMutating) {
        switch ($cmdName) {
            'status' { Show-RepoStatus -WithIdentity; break }
            'br-list' {
                $dfltDisp = Get-DefaultBranch
                if (-not $dfltDisp) { $dfltDisp = 'unknown' }
                Write-PlainLine ''
                Write-PlainLine "Default branch: ${dfltDisp}"
                Write-StatusLine 'git branch -a -vv'
                git branch -a -vv
                if ($LASTEXITCODE -ne 0) { throw "'git branch -a -vv' failed (exit ${LASTEXITCODE})." }
                Clear-BlankCounter
                break
            }
            'pr' { Invoke-GitsbyPrView -PrNumber $script:prNum; break }
        }
        Write-PlainLine ''
        exit 0
    }

    ## Mutating commands: show state and plan, confirm, execute, show state again.
    ## clone, and create/connect from a plain dir, have no repo state to show; a smaller header stands in.
    if ($cmdName -eq 'repo-clone') {
        Write-PlainLine ''
        Write-PlainLine "Directory ....: $(Get-Location)"
        Write-PlainLine "Remote .......: $(Get-MaskedUrl -Url $script:cloneUrl)"
        Show-Identity -RemoteUrl $script:cloneUrl
        Write-PlainLine "Clone into ...: $($script:cloneDir)"
    } elseif (-not $script:inRepo) {
        $remoteDisp = if ($script:connectUrl) { Get-MaskedUrl -Url $script:connectUrl } else { "github.com/$($script:ghTarget) (to be created)" }
        Write-PlainLine ''
        Write-PlainLine "Directory ....: $(Get-Location)"
        Write-PlainLine "Remote .......: ${remoteDisp}"
        Show-Identity -RemoteUrl $script:connectUrl
        Write-PlainLine 'Current branch: (not a git repository yet)'
        Show-FilesToPublish
    } else {
        if (-not (Get-CurrentBranch)) { throw 'Detached HEAD (no current branch); resolve that manually first.' }
        Show-RepoStatus -WithIdentity -CommandName $cmdName
    }
    Write-PlainLine ''
    Write-PlainLine 'Going to do (steps marked * only if needed, based on repo state):'
    Show-CommandPreview -CommandName $cmdName
    ## Said once here, where you can still say no, and again by each step as it skips. repo-*
    ## has no park push to skip - it probes its own remote and fails on its own terms.
    if ($cmdName -notlike 'repo-*' -and (Test-Offline)) {
        Write-PlainLine ''
        Write-PlainLine 'WARNING: remote unreachable - nothing will be pushed; the work stays local.'
    }
    ## Last thing before the prompt, so it can't scroll away above the plan.
    if ($identityMismatch) {
        Write-PlainLine ''
        Write-StatusLine '*** WRONG ACCOUNT? ***'
        Write-PlainLine "  ${identityMismatch}"
        Write-PlainLine "  gh does the pull request work, so it happens as '$(Get-GhLogin)'."
        Write-PlainLine '  Continue only if that is what you mean. (-AnyIdentity silences this.)'
    }
    if (-not $script:doQuietly) {
        Write-PlainLine ''
        $answer = Read-Host -Prompt 'Continue? (y|n)'
        Clear-BlankCounter
        ## Trailing blank on this exit too, like every other one, and like bash's.
        if ($answer -ne 'y') { Write-StatusLine 'User aborted.'; Write-PlainLine ''; exit 1 }
    }

    switch ($cmdName) {
        'update' { Invoke-GitsbyCommitPull; break }
        'sync' { Invoke-GitsbyPush; break }
        'br-create' { Invoke-GitsbyMakeBranch -NewBranch $CommandArg; break }
        'br-hotfix' { Invoke-GitsbyHotfix -NewBranch $CommandArg; break }
        'br-switch' { Invoke-GitsbyChangeBranch -TargetBranch $CommandArg; break }
        'br-land' { Invoke-GitsbyLand; break }
        'br-prune' { Invoke-GitsbyPrune; break }
        'pr' {
            if ($script:prSub -eq 'create') { Invoke-GitsbyPrCreate -Title $script:prTitle }
            else { Invoke-GitsbyPrAccept -PrNumber $script:prNum }
            break
        }
        'release' { Invoke-GitsbyRelease; break }
        'repo-clone' { Invoke-GitsbyClone; break }
        { $_ -in 'repo-create', 'repo-connect' } { Invoke-GitsbyConnect; break }
    }

    Write-PlainLine ''
    if ($cmdName -eq 'repo-clone') {
        Write-StatusLine "Cloned into '$($script:cloneDir)'."  ## the after-status would show the wrong (current) directory
    } else {
        Show-RepoStatus
    }
    Write-StatusLine ''
    Write-StatusLine 'Done.'
    Write-PlainLine ''
} catch {
    Write-PlainLine ''
    [Console]::Error.WriteLine("${script:meName}: $($_.Exception.Message)")
    ## Forced: the message went to stderr, so the blank-line counter didn't see it and would
    ## swallow this one. Bash closes every exit path with a blank the same way.
    Clear-BlankCounter
    Write-PlainLine ''
    exit 1
}


##  History:
##      - 20260722 JC: Created; port of bin/gitsby (same commands, checks, and flow).
##      - 20260722 JC: Command renames (old names stay as hidden aliases), dev-aware merge target, pr and release commands - in step with bin/gitsby.
##      - 20260723 JC: Pre-flight display (SSH identity, commit author, ahead/behind, incoming files) and the capped short-form change list - in step with bin/gitsby.
##      - 20260723 JC: Renamed saveup->update (old name aliased); release fast-forwards dev to main afterward; leading blank line on output - in step with bin/gitsby.
##      - 20260724 JC: pull uses --autostash (failed pull leaves the tree intact); land publishes an upstream-less target before the remote branch delete; newbr carries dirty work off main/dev, gobr refuses to auto-commit there - in step with bin/gitsby.
##      - 20260724 JC: Non-tty mutating runs fail closed without -q; extra positional after a message rejected; case-sensitive branch compares; release tolerates short tags like v1.2; masked credentials in the displayed remote URL; fetch with --prune + origin/HEAD heal + ssh connect timeout; -NoFetch; tolerant remote-branch delete in land; exit-code checks in pr view/listbr; drive-letter remotes not treated as ssh hosts; ssh -G gets --; per-run default-branch/merge-target caching; dropped the redundant GIT_MERGE_AUTOEDIT (it leaked into the calling session) - in step with bin/gitsby.
##      - 20260724 JC: newbr/gobr branch arguments validate before the preview; bare 'help'/'version' words work; -y/-yes aliases for -Quiet; Test-GitAhead stops at the first commit - in step with bin/gitsby.
##      - 20260724 JC: Added clone (checks out dev if the repo has one; re-run is a no-op) and connect (init if needed, commit, push to an empty remote, or gh repo create for owner/name; -Public/-Private) - in step with bin/gitsby.
##      - 20260725 JC: release publishes an upstream-less default branch instead of pushing only the tag; the duplicate-tag and dirty-protected-branch refusals moved up front, ahead of the confirmed plan; newbr's plan no longer promises a commit when run from main/dev; pr ok lands on the merge target when gh deleted the branch we were on; a bare release after a candidate proposes that candidate's own version - in step with bin/gitsby.
##      - 20260726 JC: Added 'pr new [title]' (parks the work, opens a PR against the merge target, titles it from the last commit subject when none is given, reports an already-open PR instead of erroring); pr ok refuses a dirty tree or unpushed commits, since --delete-branch would drop work that never reached origin - in step with bin/gitsby.
##      - 20260726 JC: Commands regrouped under the repo/br/pr nouns, connect split into 'repo create' vs 'repo connect', all pre-v2 aliases dropped - in step with bin/gitsby.
##      - 20260726 JC: Dropped the bare 'commit' and 'pull' commands; update/sync pull before committing (committing first guaranteed divergence against a moved remote); unreachable remote warns and skips the pull, -NoFetch skips it too - in step with bin/gitsby.
##      - 20260726 JC: Every command's pull honors offline, not just update/sync's; the dirty-protected-branch refusal names 'update' rather than the dropped 'commit'; help text back in step with the command set - in step with bin/gitsby.
##      - 20260726 JC: Added 'br prune': deletes every local branch already merged into the merge target, plus its remote copy; unmerged branches are kept and listed, never deleted; deletes with -D behind gitsby's own containment check, since 'git branch -d' asks about the upstream or HEAD rather than the merge target - in step with bin/gitsby.
##      - 20260726 JC: br prune's delete-time re-check now covers the remote copy too, and a merged current branch is reported as kept rather than left off every list - in step with bin/gitsby.
##      - 20260727 JC: Git now runs in the location the user is actually in. Set-Location moves PowerShell's location but not the process cwd, and the launcher inherits the latter, so state was read from one repo while commits, merges and pushes went to another.
##      - 20260727 JC: A conflicted tree is never committed - a pull whose autostash reapply conflicts exits 0, so the markers were being staged, committed and pushed - in step with bin/gitsby.
##      - 20260727 JC: Review round: 'pr ok <n>' checks the PR's own branch for unpushed commits; the default branch is resolved rather than assumed; 'release' refuses an invented version with nothing to release; 'br land' won't delete a leftover main/master; '-v' alongside a command is refused instead of silently printing the version and doing nothing; '--help' works after a command; '-Public' with '-Private' is refused; credentialed URLs are masked on the execution line too; the remote URL and ssh probes are quoted (PowerShell was globbing them); one guarded fetch helper serves both fetch sites - in step with bin/gitsby.
##      - 20260727 JC: Review round, smaller items: a PowerShell 7 gate up front (5.1 has no $IsWindows, so StrictMode used to surface it partway through a command); status and br list reject trailing arguments; pr view blames the command that actually failed; error and abort exits close with a blank line like bash's - in step with bin/gitsby.
##      - 20260728 JC: An unreachable remote no longer fails the push - local-meaning commands skip it and say so, publishing commands refuse up front; br land holds the remote branch delete until the merge is published - in step with bin/gitsby.
##      - 20260728 JC: 'repo create'/'repo connect' from a plain directory list the files they will publish, via a throwaway git dir outside the work tree - in step with bin/gitsby.
##      - 20260730 JC: The SSH identity line probes the connect target instead of the bare host (which answered with the OS login name), and leads with the account the key authenticates as - in step with bin/gitsby.
##      - 20260730 JC: Offline messages tell the truth: a park with nothing to push says so, the skipped-push warning names its branch, and an offline hotfix land names the two commands that publish the default branch - in step with bin/gitsby.
##      - 20260731 JC: Branch names display against the branch they land on; br create/hotfix name the branch they are about to make and where it comes from; the repo default gets its own line, and br list states it before listing - in step with bin/gitsby.
##      - 20260731 JC: The status block labels the branch you are on 'Current branch' - in step with bin/gitsby.
##      - 20260731 JC: br list runs in a repo whose default branch can't be told, reporting it unknown rather than refusing - in step with bin/gitsby.
