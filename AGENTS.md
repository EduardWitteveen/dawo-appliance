# AGENTS.md

Guidance and standards for AI coding assistants and agents working in this repository.

> **Human maintainer note:** Conversation with the maintainer may be in Dutch.
> All repository content—docs, code, comments, commit messages, and PRs—is strictly in **English**.

---

## 1. What this repository is

`dawo-appliance` is an **experimental, unofficial** reproducible appliance that demonstrates a digitally autonomous government workplace: a bootable installer ISO that provisions a NixOS host with a DAWO-based desktop, a KVM/libvirt Ubuntu 24.04 VM, single-node K3s, and a Mijn Bureau deployment, then opens it in the browser.

It is **not** an official DAWO / Mijn Bureau / BZK distribution. Never imply it is.

---

## 2. Hard rules & Core principles (ADR 0005)

1. **GitHub is the Single Source of Truth:**
   - Issues, task backlogs, discussions, and decision tracking live exclusively on GitHub (`github.com/EduardWitteveen/dawo-appliance`).
   - Never create local scratch, todo, or issue markdown files in the repository for items that belong in GitHub issue tracker.
   - Never push directly to `main`, never force-push, never rewrite published history without maintainer approval.
2. **Language:** All repository content is in **English**. (Conversations with the maintainer may be in Dutch.)
3. **Keep upstream separate:** Consume DAWO-Core (`codeberg.org/DAWO/DAWO-Core`, flake input) and mijn-bureau-infra (`code.overheid.nl/MinBZK/mijn-bureau-infra`, documented install path) by pinned revision. Do **not** copy upstream source unless strictly necessary and license-permitted.
4. **Pin everything:** Exact revisions, Nix inputs, K3s version, Helm chart versions, and container image digests live in version-controlled files (`manifest/appliance-manifest.json`, `flake.lock`). Never use `main`, `latest`, or floating tags.
5. **Never commit secrets:** No passwords, tokens, private keys, or generated secrets in Git. Secrets are generated at install time.
6. **License: EUPL-1.2:** (`LICENSE`). Keep the SPDX identifier `EUPL-1.2` and do not relicense without the maintainer's approval.
7. **Non-destructive by default:** Any code that can write to a disk MUST require an explicit target disk AND an explicit confirmation flag (`--target-disk` + `--confirm-destroy`). Default action is always a dry-run `plan`.
8. **No host/WSL changes without asking:** Do not install or change Windows/WSL system components (e.g. `/etc/wsl.conf`, installing Nix system-wide) without asking first.
9. **Stay in scope:** Do not add speculative functionality outside the stated v0.1 scope (`docs/adr/0001-project-scope.md`).
10. **Investigative & Thoughtful:** Understand the context, existing structure, and verify assumptions before proposing or applying code changes. Distinguish blocking problems from later improvements.

---

## 3. Environment notes

- Development machines run Windows 11 + WSL2.
- **AI agents usually run on the Windows host side** (PowerShell or Git Bash, repo root `C:\git\dawo-appliance`).
- **Nix runs inside WSL** (see machine runbook in `docs/nix-setup.md`). Run Nix through WSL:
  `wsl -d <distro> -e bash -lc 'cd /mnt/c/git/dawo-appliance && nix flake check'`
- Git Bash on Windows has `bash` at `C:\Program Files\Git\bin\bash.exe`. Native `python` is 3.x; Windows execution aliases for `python3` may redirect to Microsoft Store, so scripts should support `python` as a fallback.
- Line endings: the repository is LF-only (`.gitattributes`). Do not convert files to CRLF.

---

## 4. GitHub workflow

Every change must go through GitHub:

1. **Issue first:** Open (or pick up) a GitHub issue describing the change; check open issues and open PRs first (`gh issue list`, `gh pr list`). Comment on or assign the issue when starting.
2. **Feature branch from up-to-date `main`:**
   ```bash
   git fetch && git switch -c <type>/<issue-number>-<slug> origin/main
   ```
   (e.g. `feat/12-guest-autostart`, `docs/42-agent-guidelines`).
3. **Commits on the branch:**
   - Conventional Commits, English, logical steps.
   - Author is the maintainer's GitHub noreply address (`6449834+EduardWitteveen@users.noreply.github.com`).
   - **No AI attribution lines:** No `Co-Authored-By: Claude/Aider`, no `Generated with ...`.
4. **Pull request:**
   - Reference the issue (`Closes #N`).
   - Describe what changed and include verification run results.
   - Keep PRs small and focused.
5. **Stay in sync:**
   - `git fetch` before opening PR and before merging. If `origin/main` moved, rebase on it (`git rebase origin/main`).
6. **Merge:**
   - Merge once checks pass with a **rebase merge** (`gh pr merge --rebase --delete-branch`), then pull `main` (`git switch main && git pull --ff-only`).

---

## 5. Starting a session & Validation

- Run `bash scripts/status.sh` (via Git Bash) first. It prints the current slice, blocking open questions, live checks, and recently changed files.
- Local validation without Nix: `tests/test-bootstrap-dryrun.sh`, `make check` (lint + test).
- Test-driven: A bug becomes a check first. Never claim a check passed without running it.
