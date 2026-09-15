<!-- omit in toc -->
# Contributing

*This file was generated via [https://contributing.md/generator/](https://contributing.md/generator/)*

First off, thanks for taking the time to contribute!

All types of contributions are encouraged and valued. See the [Table of Contents](#table-of-contents) for different ways to help and details about how this project handles them. Please make sure to read the relevant section before making your contribution. It will make it a lot easier for us maintainers and smooth out the experience for all involved. The community looks forward to your contributions.

> And if you like the project, but just don't have time to contribute, that's fine. There are other easy ways to support the project and show your appreciation, which we would also be very happy about:
>
> - Star the project
> - Tweet/skeet/post about it
> - Refer this project in your project's readme
> - Mention the project to your friends/colleagues

<!-- omit in toc -->
## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [I Have a Question](#i-have-a-question)
- [I Want To Contribute](#i-want-to-contribute)
	- [Reporting Bugs](#reporting-bugs)
	- [Suggesting Enhancements](#suggesting-enhancements)
	- [Your First Code Contribution](#your-first-code-contribution)
- [Styleguides](#styleguides)
	- [Commit Messages](#commit-messages)

## Code of Conduct

This project and everyone participating in it is governed by the
[gitsby Code of Conduct](https://github.com/jim-collier/gitsby/blob/main/code_of_conduct.md).
By participating, you are expected to uphold this code. Please report unacceptable behavior to <gitsby@ubx9.com>.

## I Have a Question

Before you ask a question, it is best to search for existing [Issues](https://github.com/jim-collier/gitsby/issues) that might help you. In case you have found a suitable issue and still need clarification, you can write your question in this issue. It is also advisable to search the internet for answers first.

If you then still feel the need to ask a question and need clarification, we recommend the following:

- Open an [Issue](https://github.com/jim-collier/gitsby/issues/new).

- Provide as much context as you can about what you're running into.

- Provide project and platform versions, depending on what seems relevant.

We will then take care of the issue as soon as possible.

## I Want To Contribute

> ### Legal Notice <!-- omit in toc -->
>
> When contributing to this project, you must agree that you have authored 100% of the content, that you have the necessary rights to the content and that the content you contribute may be provided under the project licence.

### Reporting Bugs

<!-- omit in toc -->
#### Before Submitting a Bug Report

A good bug report shouldn't leave others needing to chase you up for more information. Therefore, we ask you to investigate carefully, collect information and describe the issue in detail in your report. Please complete the following steps in advance to help us fix any potential bug as fast as possible.

- Make sure that you are using the latest version.

- Determine if your bug is really a bug and not an error on your side e.g. using incompatible environment components/versions (Make sure that you have read the [documentation](https://github.com/jim-collier/gitsby/blob/main/README.md). If you are looking for support, you might want to check [this section](#i-have-a-question)).

- To see if other users have experienced (and potentially already solved) the same issue you are having, check if there is not already a bug report existing for your bug or error in the [bug tracker](https://github.com/jim-collier/gitsby/issues?q=label%3Abug).

- Also search the internet, including Stack Overflow, to see if users outside the GitHub community have discussed the issue.

- Collect information about the bug:
	- OS, platform, and version (Windows, Linux, macOS, x86_64, ARM64).
	- Which version, from `gitsby --version`, and which platform.
	- Your `git` version, and `gitsby -v`.
	- Your input and the output.
	- Can you reliably reproduce it? Can you reproduce it with older versions?
	- Steps to cleanly reproduce from scratch.

<!-- omit in toc -->
#### How Do I Submit a Good Bug Report?

> You must never report security related issues, vulnerabilities or bugs including sensitive information to the issue tracker, or elsewhere in public. Instead sensitive bugs must be sent by email to <gitsby@ubx9.com>.
<!-- You may add a PGP key to allow the messages to be sent encrypted as well. -->

We use GitHub issues to track bugs and errors. If you run into an issue with the project:

- Open an [Issue](https://github.com/jim-collier/gitsby/issues/new). (Since we can't be sure at this point whether it is a bug or not, we ask you not to talk about a bug yet and not to label the issue.)

- Explain the behavior you would expect and the actual behavior.

- Please provide as much context as possible and describe the *reproduction steps* that someone else can follow to recreate the issue on their own. This usually includes your code. For good bug reports you should isolate the problem and create a reduced test case.

- Provide the information you collected in the previous section.

Once it's filed:

- The project team will label the issue accordingly.

- A team member will try to reproduce the issue with your provided steps. If there are no reproduction steps or no obvious way to reproduce the issue, the team will ask you for those steps and mark the issue as `needs-repro`. Bugs with the `needs-repro` tag will not be addressed until they are reproduced.

- If the team is able to reproduce the issue, it will be marked `needs-fix`, as well as possibly other tags (such as `critical`), and the issue will be left to be implemented by someone.

<!-- You might want to create an issue template for bugs and errors that can be used as a guide and that defines the structure of the information to be included. If you do so, reference it here in the description. -->

### Suggesting Enhancements

This covers both new features and small improvements to what's already there. Following these guidelines helps everyone understand your suggestion and find related ones.

<!-- omit in toc -->
#### Before Submitting an Enhancement

- Make sure that you are using the latest version.

- Read the [documentation](https://github.com/jim-collier/gitsby/blob/main/README.md) carefully and find out if the functionality is already covered, maybe by an individual configuration.

- Perform a [search](https://github.com/jim-collier/gitsby/issues) to see if the enhancement has already been suggested. If it has, add a comment to the existing issue instead of opening a new one.

- Find out whether your idea fits with the scope and aims of the project. It's up to you to make a strong case to convince the project's developers of the merits of this feature. Keep in mind that we want features that will be useful to the majority of our users and not just a small subset. If you're just targeting a minority of users, consider writing an add-on/plugin library.

<!-- omit in toc -->
#### How Do I Submit a Good Enhancement Suggestion?

Enhancement suggestions are tracked as [GitHub issues](https://github.com/jim-collier/gitsby/issues).

- Use a clear and descriptive title.

- Describe the suggestion step by step, in as much detail as you can.

- Say what the current behavior is, what you expected instead, and why. Mention any alternatives that don't work for you.

- Explain why it would be useful to most gitsby users. Pointing at another project that solved it well helps.

<!-- You might want to create an issue template for enhancement suggestions that can be used as a guide and that defines the structure of the information to be included. If you do so, reference it here in the description. -->

### Your First Code Contribution

<!-- omit in toc -->
#### Set up

Clone it and build it. There is no setup script any more, because there is nothing to set up beyond Go itself.

~~~bash
git clone https://github.com/jim-collier/gitsby.git
cd gitsby/src-go && go build -o gitsby .
~~~

That binary is the whole product. The rest of the tooling below is for running the checks, and every piece of it is optional except Go.

<!-- omit in toc -->
#### What you need

- `git`, and the Go toolchain. Nothing else is required to build.

- `bash` 4.4 or newer, to run the pipeline. The product does not need it; the pipeline is written in it.

- `staticcheck` (`go install honnef.co/go/tools/cmd/staticcheck@latest`), for the lint stage. Without it that check warns and skips; `gofmt` and `go vet` ship with Go and always gate.

- `golangci-lint` (`go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest`), for the rest of the Go lint set. Configured in `src-go/.golangci.yml`; warns and skips when absent.

- `govulncheck` (`go install golang.org/x/vuln/cmd/govulncheck@latest`), to check the standard library for known problems. Same treatment.

- `goversioninfo` (`go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo@v1.5.0`), to check the committed Windows resource against the newest tag. Warns and skips when absent; a release refuses without it.

- `strace`, for the spawn counts. Linux only; the step skips itself elsewhere.

- `shellcheck`, to lint the pipeline's own scripts.

- `markdownlint` (`npm install -g markdownlint-cli`), to lint the docs.

- `python3` with Pillow, and optionally `gifsicle`, to regenerate the demo. Only needed for a full pipeline run.

- `gh`, if you want to exercise the `pr` command.

<!-- omit in toc -->
#### Where things are

- `src-go/` - the implementation. One file per concern, package `main`.

- `legacy/` - the Bash and PowerShell builds, frozen at v2.1.0, plus the installers of that era. Read them, compare against them, never edit them.

- `cicd/` - the local pipeline and its config.

- `src-go/resource_windows_*.syso` - the icon and version details Windows shows for the `.exe`. Generated by `cicd/utility/gen-winres.bash` and committed, because they are linked into binaries whose checksums are published; the script's header explains why they carry the last released version rather than the working tree's.

- `cicd/utility/demo/` - everything the demo gif is built from. Start at `script.txt`, which describes scene by scene what the demo shows; the scenario file beside it is the same thing in the form the renderer reads.

- `project/` - design notes and the backlog.

<!-- omit in toc -->
#### Run the checks

- `cicd/cicd.bash --quick` - the whole pipeline, minus the slow stages. Run this before you open a PR.

- `cicd/cicd.bash` - everything, including the fuzz suite and the demo.

- `cicd/cicd.bash --gate` - every lint check and the unit tests, and nothing else: no sync, no build, no suites, no prompt and no run log. This is what the pre-push hook runs.

- `cicd/cicd.bash --install-hook` - install a git pre-push hook that runs `--gate` before every push, once for each commit pushed to a branch. It checks the commit as committed, in a separate worktree at `.git/gitsby-gate`, and never your working tree, so an uncommitted edit neither fails a push nor passes one. That worktree shows in `git worktree list`. Deletes and tags are not gated, and `git push --no-verify` skips the gate for one push. The install refuses to replace a pre-push hook it did not write, and writes nothing while `core.hooksPath` is set.

- To remove the hook, run `rm .git/hooks/pre-push` and then `git worktree remove --force .git/gitsby-gate`.

- `cicd/parity.bash` - just the compatibility comparison: whether this build *answers the same* as the frozen v2.1.0 one for a given input, rather than whether either behaves correctly on its own. It has its own pipeline stage.

- `cicd/release.bash --dry-run` - what cutting a release would do, changing nothing.

- `cicd/test.bash` - just the regression suite. It builds throwaway repos under a temp directory and never touches the network or your real repos.

- `cicd/fuzz.bash` - just the fuzz suite.

- `cicd/utility/spawn-count.bash` - how many processes each command starts, against the newest previous run. This is the profiling step: the program is blocked on git for effectively all of its wall clock, so a sampling profile has no leaders in it.

- `cicd/utility/keep-build.bash` - archive the current binary, list what is kept, run one, or diff one against the current build on the same arguments. For bisecting a behavior change.

- `cicd/utility/run-latest.ps1` - run the newest build, any arguments forwarded, from a pool of timestamped copies outside PATH. The pool means a rebuild never fights a copy that is still running, and week-old copies age out on their own. PowerShell 7, all platforms.

- `cicd/utility/spawn-report.bash` - print the newest recorded spawn counts with deltas; `--check` reports only what arrived since it last looked, the same marker pattern as `lint-report.bash --check`.

All three suites take `-q`, which drops the per-check line and keeps the failures and the total. The pipeline passes it on an unattended run.

The pipeline fast-forwards from `origin` before it builds anything, so the checks run against the tree that will actually be pushed. It stops if your branch has diverged, warns and carries on if you're offline or the branch has no upstream, and `--no-sync` skips it.

The regression and fuzz suites both run against the compiled binary, so build before you run them - or let the pipeline do it, which is what its second stage is for.

<!-- omit in toc -->
#### Then

Work on a short-named feature branch, open a PR back to `dev`, and leave `main` release-only. Coding style is in [style-guide.md](style-guide.md).

> While the Go port is in flight, all of it lives on the `gover` integration branch, and day-to-day branches come off that rather than off `dev`. `git switch gover` is the only difference; everything else is the same. This note goes when the port lands.

<!-- TODO
### Improving The Documentation

Updating, improving and correcting the documentation

-->

## Styleguides

Go code follows `gofmt`, which the lint stage enforces. The [style guide](style-guide.md) covers the Bash and PowerShell in `legacy/` and the pipeline's own scripts.

What the program prints, and how it asks and refuses, follows the [CLI style guide](project/style-guide_cli.md). A new message or option starts there.

### Commit Messages

Short and plain. A few words about what changed is enough, and that is what the history here looks like. Put the detail in the pull request, not the subject line.

<!-- TODO
## Join The Project Team

-->

<!-- omit in toc -->
## Attribution

This guide is based on the [contributing.md generator](https://contributing.md/generator)!
