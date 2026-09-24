<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD024 -- Duplicate headings (the Bash and PowerShell sections mirror each other) -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Git help

Command strings for common git tasks

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [General notes](#general-notes)
	- [Stash](#stash)
- [Commands for common tasks - Bash](#commands-for-common-tasks---bash)
	- [Basics using main or master](#basics-using-main-or-master)
		- [Clone a project and start programming with it, using aliases in ~/.ssh/config](#clone-a-project-and-start-programming-with-it-using-aliases-in-sshconfig)
		- [Initialize an existing local project with git and push it to a new github repo](#initialize-an-existing-local-project-with-git-and-push-it-to-a-new-github-repo)
		- [Reconnect to a project after renaming it remotely](#reconnect-to-a-project-after-renaming-it-remotely)
	- [Regular use](#regular-use)
		- [Refresh local with changes from upstream](#refresh-local-with-changes-from-upstream)
		- [Push local changes to upstream](#push-local-changes-to-upstream)
	- [Read-only inspection](#read-only-inspection)
		- [Show what SSH keys and username git thinks you're using](#show-what-ssh-keys-and-username-git-thinks-youre-using)
		- [Show diff between local state and upstream](#show-diff-between-local-state-and-upstream)
	- [Branches](#branches)
		- [Check out an existing branch and start using it, while preserving local changes](#check-out-an-existing-branch-and-start-using-it-while-preserving-local-changes)
		- [Create a new branch and sync it to GitHub](#create-a-new-branch-and-sync-it-to-github)
		- [Push current changes and switch to a different branch](#push-current-changes-and-switch-to-a-different-branch)
		- [Merge current local feature branch to main, and return to main](#merge-current-local-feature-branch-to-main-and-return-to-main)
	- [Maintenance](#maintenance)
		- [Remove a file from git AND locally](#remove-a-file-from-git-and-locally)
- [Commands for common tasks - PowerShell](#commands-for-common-tasks---powershell)
	- [Basics using main or master](#basics-using-main-or-master-1)
		- [Clone a project and start programming with it, using aliases in ~/.ssh/config](#clone-a-project-and-start-programming-with-it-using-aliases-in-sshconfig-1)
		- [Initialize an existing local project with git and push it to a new github repo](#initialize-an-existing-local-project-with-git-and-push-it-to-a-new-github-repo-1)
		- [Reconnect to a project after renaming it remotely](#reconnect-to-a-project-after-renaming-it-remotely-1)
	- [Regular use](#regular-use-1)
		- [Refresh local with changes from upstream](#refresh-local-with-changes-from-upstream-1)
		- [Push local changes to upstream](#push-local-changes-to-upstream-1)
	- [Read-only inspection](#read-only-inspection-1)
		- [Show what SSH keys and username git thinks you're using](#show-what-ssh-keys-and-username-git-thinks-youre-using-1)
		- [Show diff between local state and upstream](#show-diff-between-local-state-and-upstream-1)
	- [Branches](#branches-1)
		- [Check out an existing branch and start using it, while preserving local changes](#check-out-an-existing-branch-and-start-using-it-while-preserving-local-changes-1)
		- [Create a new branch and sync it to GitHub](#create-a-new-branch-and-sync-it-to-github-1)
		- [Push current changes and switch to a different branch](#push-current-changes-and-switch-to-a-different-branch-1)
		- [Merge current local feature branch to main, and return to main](#merge-current-local-feature-branch-to-main-and-return-to-main-1)
	- [Maintenance](#maintenance-1)
		- [Remove a file from git AND locally](#remove-a-file-from-git-and-locally-1)
- [References](#references)

<!-- /TOC -->

## General notes

### Stash

`git stash apply` leaves the current stash on the stash. `git stash pop` does the same thing as apply, but removes the last stash. `--include-untracked` includes untracked, which could make the stash grow large. The stash is local.

Care is needed with `stash apply` or `stash pop`, because if the a `git stash push` didn't succeed, then a corresponding `apply` or `pop` may use a stale set.

## Commands for common tasks - Bash

### Basics using main or master

#### Clone a project and start programming with it, using aliases in ~/.ssh/config

~~~bash
gitProj="REMOTE_REPO_NAME"
gitUser="YOUR_GIT_USER_NAME"
[[ -n "${gitProj}"  &&  -n "${gitUser}" ]]  &&  git clone "git@github_${gitUser}:${gitUser}/${gitProj}.git"  &&  cd "${gitProj}"  &&  echo  &&  git remote -v  &&  echo  &&  git config user.name  &&  git config user.email  &&  echo
~~~

#### Initialize an existing local project with git and push it to a new github repo

~~~bash
gitProj="REMOTE_REPO_NAME"
gitUser="YOUR_GIT_USER_NAME"
[[ -n "${gitProj}"  &&  -n "${gitUser}" ]]  &&  git init -b main  &&  git add --all  &&  git commit -m "Initial commit."  &&  git remote add origin "git@github_${gitUser}:${gitUser}/${gitProj}.git"  &&  git push -u origin main  &&  echo  &&  git remote -v  &&  echo  &&  git config user.name  &&  git config user.email  &&  echo
~~~

#### Reconnect to a project after renaming it remotely

~~~bash
gitProj="REMOTE_REPO_NAME"
gitUser="YOUR_GIT_USER_NAME"
[[ -n "${gitProj}"  &&  -n "${gitUser}" ]]  &&  git remote set-url origin "git@github_${gitUser}:${gitUser}/${gitProj}.git"  &&  echo -e "\ngit will be using this contact info:" ; git config user.name ; git config user.email; echo -e "\ngit remote info:" ; git remote -v; echo -e "\nSSH login test:" ; ssh -T git@github.com; echo  &&  git status  &&  echo
~~~

### Regular use

#### Refresh local with changes from upstream

~~~bash
preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0)); git pull --ff-only; ((didStash)) && git stash pop; echo && git status && echo
~~~

#### Push local changes to upstream

~~~bash
gitsby pullcom
~~~

or

~~~bash
preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0)); git pull --rebase; ((didStash)) && git stash pop; git add --all && (git diff --cached --quiet || git commit) && git push -u origin HEAD; echo && git status && echo
~~~

### Read-only inspection

#### Show what SSH keys and username git thinks you're using

~~~bash
echo -e "\ngit will be using this contact info:" ; git config user.name ; git config user.email; echo -e "\ngit remote info:" ; git remote -v; echo -e "\nSSH login test:" ; ssh -T git@github.com; echo  &&  git status  &&  echo
~~~

#### Show diff between local state and upstream

~~~bash
git fetch && echo && git status  &&  { echo; git diff HEAD @{u} | less -FRX; echo; }
~~~

### Branches

#### Check out an existing branch and start using it, while preserving local changes

~~~bash
branchName="feature|bugfix/EXISTING_BRANCH_NAME"
[[ -n "${branchName}" ]]  &&  { preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0));  git fetch origin  &&  git checkout "${branchName}"  &&  { ((didStash)) && git stash pop || true; }  &&  echo  &&  git status  &&  echo ; }
~~~

#### Create a new branch and sync it to GitHub

~~~bash
branchName="feature|bugfix/NEW_BRANCH_NAME"
[[ -n "${branchName}" ]]  &&  { preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0));  git pull --ff-only  &&  git checkout -b "${branchName}"  &&  { ((didStash)) && git stash pop || true; }  &&  git push -u origin "${branchName}"  &&  echo  &&  git branch -vv  &&  echo  &&  git status  &&  echo ; }
~~~

#### Push current changes and switch to a different branch

~~~bash
branchName="feature|bugfix/EXISTING_BRANCH_NAME"

## Commit and push current branch, then switch
git add --all && (git diff --cached --quiet || git commit) && git push -u origin HEAD
[[ -n "${branchName}" ]]  &&  git fetch origin  &&  git checkout "${branchName}"  &&  git pull --ff-only  &&  echo  &&  git branch -vv  &&  echo  &&  git status  &&  echo
~~~

#### Merge current local feature branch to main, and return to main

~~~bash
branchName="feature|bugfix/EXISTING_BRANCH_NAME"

## Commit local changes and sync with upstream
preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0)); git pull --rebase; ((didStash)) && git stash pop; git add --all && (git diff --cached --quiet || git commit) && git push -u origin HEAD; echo && git status && echo

## Merge to main (assumes clean working tree - run preceding block first)
[[ -n "${branchName}" ]]  &&  git checkout main  &&  git pull --ff-only origin main  &&  git checkout "${branchName}"  &&  git merge main  &&  git checkout main  &&  git merge --no-ff "${branchName}"  &&  git push origin main  &&  echo  &&  git branch -vv  &&  echo  &&  git status  &&  echo
~~~

### Maintenance

#### Remove a file from git AND locally

~~~bash
fileToDelete="FILE_TO_DELETE"
[[ -n "${fileToDelete}"  &&  -e "${fileToDelete}" ]]  &&  git rm --cached -r "${fileToDelete}"  &&  git commit -m "Remove '${fileToDelete}' from tracking."  &&  git push  &&  trash "${fileToDelete}"
~~~

## Commands for common tasks - PowerShell

Same tasks as the Bash section, for PowerShell 7+ (`pwsh`) on any platform. Three things differ from Bash and are easy to trip over:

- The `&&` and `||` chain operators need pwsh 7 or newer. Windows PowerShell 5.1 will not run these.

- `@{u}` (upstream shorthand) has to be quoted as `'@{u}'`, otherwise pwsh reads `@{` as the start of a hashtable.

- Native commands set `$LASTEXITCODE`, not `$?`-style status, so tests like "are there staged changes" check that instead.

### Basics using main or master

#### Clone a project and start programming with it, using aliases in ~/.ssh/config

~~~pwsh
$gitProj = 'REMOTE_REPO_NAME'
$gitUser = 'YOUR_GIT_USER_NAME'
if ($gitProj -and $gitUser) { git clone "git@github_${gitUser}:${gitUser}/${gitProj}.git" && Set-Location $gitProj && Write-Host '' && git remote -v && Write-Host '' && git config user.name && git config user.email && Write-Host '' }
~~~

#### Initialize an existing local project with git and push it to a new github repo

~~~pwsh
$gitProj = 'REMOTE_REPO_NAME'
$gitUser = 'YOUR_GIT_USER_NAME'
if ($gitProj -and $gitUser) { git init -b main && git add --all && git commit -m 'Initial commit.' && git remote add origin "git@github_${gitUser}:${gitUser}/${gitProj}.git" && git push -u origin main && Write-Host '' && git remote -v && Write-Host '' && git config user.name && git config user.email && Write-Host '' }
~~~

#### Reconnect to a project after renaming it remotely

~~~pwsh
$gitProj = 'REMOTE_REPO_NAME'
$gitUser = 'YOUR_GIT_USER_NAME'
if ($gitProj -and $gitUser) { git remote set-url origin "git@github_${gitUser}:${gitUser}/${gitProj}.git" }; Write-Host "`ngit will be using this contact info:"; git config user.name; git config user.email; Write-Host "`ngit remote info:"; git remote -v; Write-Host "`nSSH login test:"; ssh -T git@github.com; Write-Host ''; git status; Write-Host ''
~~~

### Regular use

#### Refresh local with changes from upstream

~~~pwsh
$preCount = @(git stash list).Count; git stash push --include-untracked -m 'auto-stash'; $didStash = (@(git stash list).Count -gt $preCount); git pull --ff-only; if ($didStash) { git stash pop }; Write-Host ''; git status; Write-Host ''
~~~

#### Push local changes to upstream

~~~pwsh
gitsby pullcom
~~~

or

~~~pwsh
$preCount = @(git stash list).Count; git stash push --include-untracked -m 'auto-stash'; $didStash = (@(git stash list).Count -gt $preCount); git pull --rebase; if ($didStash) { git stash pop }; git add --all; git diff --cached --quiet; if ($LASTEXITCODE -ne 0) { git commit }; git push -u origin HEAD; Write-Host ''; git status; Write-Host ''
~~~

### Read-only inspection

#### Show what SSH keys and username git thinks you're using

~~~pwsh
Write-Host "`ngit will be using this contact info:"; git config user.name; git config user.email; Write-Host "`ngit remote info:"; git remote -v; Write-Host "`nSSH login test:"; ssh -T git@github.com; Write-Host ''; git status; Write-Host ''
~~~

#### Show diff between local state and upstream

~~~pwsh
git fetch; Write-Host ''; git status; Write-Host ''; git diff HEAD '@{u}'; Write-Host ''
~~~

git pages its own diff output, so there is no `less` in this one. To page it yourself instead, append `| Out-Host -Paging`.

### Branches

#### Check out an existing branch and start using it, while preserving local changes

~~~pwsh
$branchName = 'feature|bugfix/EXISTING_BRANCH_NAME'
if ($branchName) { $preCount = @(git stash list).Count; git stash push --include-untracked -m 'auto-stash'; $didStash = (@(git stash list).Count -gt $preCount); git fetch origin && git checkout $branchName; if ($didStash) { git stash pop }; Write-Host ''; git status; Write-Host '' }
~~~

#### Create a new branch and sync it to GitHub

~~~pwsh
$branchName = 'feature|bugfix/NEW_BRANCH_NAME'
if ($branchName) { $preCount = @(git stash list).Count; git stash push --include-untracked -m 'auto-stash'; $didStash = (@(git stash list).Count -gt $preCount); git pull --ff-only && git checkout -b $branchName; if ($didStash) { git stash pop }; git push -u origin $branchName && Write-Host '' && git branch -vv && Write-Host '' && git status && Write-Host '' }
~~~

#### Push current changes and switch to a different branch

~~~pwsh
$branchName = 'feature|bugfix/EXISTING_BRANCH_NAME'

# Commit and push current branch, then switch
git add --all; git diff --cached --quiet; if ($LASTEXITCODE -ne 0) { git commit }; git push -u origin HEAD
if ($branchName) { git fetch origin && git checkout $branchName && git pull --ff-only && Write-Host '' && git branch -vv && Write-Host '' && git status && Write-Host '' }
~~~

#### Merge current local feature branch to main, and return to main

~~~pwsh
$branchName = 'feature|bugfix/EXISTING_BRANCH_NAME'

# Commit local changes and sync with upstream
$preCount = @(git stash list).Count; git stash push --include-untracked -m 'auto-stash'; $didStash = (@(git stash list).Count -gt $preCount); git pull --rebase; if ($didStash) { git stash pop }; git add --all; git diff --cached --quiet; if ($LASTEXITCODE -ne 0) { git commit }; git push -u origin HEAD; Write-Host ''; git status; Write-Host ''

# Merge to main (assumes clean working tree - run preceding block first)
if ($branchName) { git checkout main && git pull --ff-only origin main && git checkout $branchName && git merge main && git checkout main && git merge --no-ff $branchName && git push origin main && Write-Host '' && git branch -vv && Write-Host '' && git status && Write-Host '' }
~~~

### Maintenance

#### Remove a file from git AND locally

~~~pwsh
$fileToDelete = 'FILE_TO_DELETE'
if ($fileToDelete -and (Test-Path -LiteralPath $fileToDelete)) { git rm --cached -r $fileToDelete && git commit -m "Remove '${fileToDelete}' from tracking." && git push && Remove-Item -LiteralPath $fileToDelete -Recurse -Force }
~~~

Unlike the Bash version's `trash`, `Remove-Item` deletes outright - there is no cross-platform recycle bin from pwsh.

## References

- [gitsby project](https://github.com/yottacore/gitsby/tree/main)
- [gitsby reference](https://github.com/yottacore/gitsby/blob/main/reference/git.txt)
