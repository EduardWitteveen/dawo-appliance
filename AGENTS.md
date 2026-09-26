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
3. **Keep upstream separate:** Consume DAWO-Core (`codeberg.org/DAWO/DAWO-Core`, flake input) and mijn-bureau-infra (`code.overheid.nl/MinBZK/mijn-bureau-infra`, documented install path) by pinned revision. Do **not** copy upstream source unless strictly necessary and license-permitted. Do not create a fork or submodule without first explaining why it is needed.
4. **Pin everything:** Exact revisions, Nix inputs, K3s version, Helm chart versions, and container image digests live in version-controlled files (`manifest/appliance-manifest.json`, `flake.lock`). Never use `main`, `latest`, or floating tags in reproducible builds.
5. **Never commit secrets:** No passwords, tokens, private keys, or generated secrets in Git. Secrets are generated at install time.
6. **License: EUPL-1.2:** (`LICENSE`). Keep the SPDX identifier `EUPL-1.2` and do not relicense without the maintainer's approval.
7. **Non-destructive by default:** Any code that can write to a disk MUST require an explicit target disk AND an explicit confirmation flag (`--target-disk` + `--confirm-destroy`). Default action is always a dry-run `plan`.
8. **No host/WSL changes without asking:** Do not install or change Windows/WSL system components (e.g. `/etc/wsl.conf`, installing Nix system-wide) without asking first.
9. **Stay in scope:** Do not add speculative functionality outside the stated v0.1 scope (`docs/adr/0001-project-scope.md`). Structure for extension; do not build unscoped features.
10. **Investigative & Thoughtful:** Understand context, existing structure, and verify assumptions before proposing or applying code changes. Distinguish blocking problems from later improvements.
11. **Never post to an external tracker on our own authority:** Filing an upstream bug (Codeberg DAWO-Core, GitHub mijn-bureau-infra, or any third-party tracker) is a public action outside this repository and needs the maintainer's explicit go-ahead each time — track the underlying problem as our own GitHub issue first (see issue #35 for the pattern: documented here, reported upstream only if and when the maintainer decides to). This applies to all agents equally.

---

## 3. Environment notes

- Development machines run Windows 11 + WSL2, x86-64.
- **AI agents usually run on the Windows host side** (PowerShell or Git Bash, repo root `C:\git\dawo-appliance`).
- **Nix runs inside WSL** (see machine runbook in `docs/nix-setup.md`). Run Nix through WSL:
  `wsl -d <distro> -e bash -lc 'cd /mnt/c/git/dawo-appliance && nix flake check'`
- Git Bash on Windows has `bash` at `C:\Program Files\Git\bin\bash.exe`. Native `python` is 3.x; Windows execution aliases for `python3` may redirect to Microsoft Store, so scripts should support `python` as a fallback.
- Line endings: the repository is LF-only (`.gitattributes`). Do not convert files to CRLF.
- qemu/libvirt run inside WSL via Nix (`nix build .#test-installer-boot -L`, needs KVM).

---

## 4. Scope (v0.1)

- **In:** x86-64, online install, single machine, one Ubuntu 24.04 VM, single-node K3s, Mijn Bureau, auto-start, local health check, auto-open browser.
- **Out:** openDesk, Nextcloud AIO, multi-node, HA, branding, AD, offline install.

---

## 5. Repository layout

`README.md` is the front door; `docs/README.md` indexes every document.
- Pins: `manifest/`.
- Upstream facts: `docs/upstream/revisions.md`.
- Decisions: `docs/adr/`.
- Unknowns: `docs/open-questions.md`.
- Deviations: `docs/deviations.md`.
- Generated files (never edit by hand): `docs/verification-latest.md`, `docs/verification-history.csv`, `docs/screenshots/PROVENANCE.md` and the PNGs next to it.

---

## 6. GitHub workflow

Every change must go through GitHub:

1. **Issue first:** Open (or pick up) a GitHub issue describing the change; check open issues and open PRs first (`gh issue list`, `gh pr list`). Comment on or assign the issue when starting, **naming the machine** ("Picked up on the KVM laptop" / "on the VDI") — all sessions authenticate as the same GitHub account, so `assignees` cannot tell them apart, only free-text can. Issues that need a KVM-capable boot test are labeled `needs-kvm`; check for that label (or its absence) before claiming work if your machine has no KVM.
   - A self-merged PR is typically open for seconds, not long enough for the other session to review it — `gh issue list`/`gh pr list --state open`, done immediately before you start, is the actual collision check, not PR review time.
2. **Feature branch from up-to-date `main`:**
   ```bash
   git fetch && git switch -c <type>/<issue-number>-<slug> origin/main
   ```
   (e.g. `feat/12-guest-autostart`, `docs/45-deduplicate-claude-md`). A cross-cutting change with no single matching issue (a multi-commit sync, a follow-up verification run) may use `chore/<slug>` or `test/verify-after-<ref>` instead — keep this rare.
3. **Commits on the branch:**
   - Conventional Commits, English, logical steps.
   - Author is the maintainer's GitHub noreply address (`6449834+EduardWitteveen@users.noreply.github.com`).
   - **No AI attribution lines:** No `Co-Authored-By: Claude/Aider`, no `Generated with ...`.
4. **Pull request:**
   - Reference the issue (`Closes #N`).
   - Describe what changed and include verification run results.
   - Keep PRs small and focused.
5. **Stay in sync:**
   - `git fetch` before opening PR and before merging. If `origin/main` moved, rebase on it (`git rebase origin/main`) — expect to redo this more than once; `main` can move every few minutes with three agents active.
6. **Merge:**
   - Merge once checks pass with a **rebase merge** (`gh pr merge --rebase --delete-branch`), then pull `main` (`git switch main && git pull --ff-only`).

### Division of labor (three concurrent agents, same git identity)

At least three sessions work this repo at once: two Claude Code sessions (one on a KVM-capable physical laptop, one on a Nutanix AHV VDI with no KVM at all — nested virtualization is a hypervisor-level limit, not a config problem) and a Gemini/Antigravity session. All commit under the same noreply identity, so `git log` never tells you which session did what — only issue/PR comments do.

- **KVM-capable session:** boot tests, `test-appliance-boot`/`test-guest-boot`/`test-install-e2e`, anything labeled `needs-kvm`.
- **Non-KVM session(s):** offline test suites, `nix flake check` (eval/build-only, works fine without KVM), security review, Nix module wiring that doesn't need a boot to verify, docs/backlog reconciliation.
- **Gemini:** documentation, localization, presentation, and target-audience material — not code or Nix modules. Per `docs/adr/0005-ai-agent-conduct.md`, an elaborate, unrequested multi-issue "initiative" (persona-driven docs, marketing framing) needs the maintainer's explicit go-ahead before implementation, not just a mention in conversation — see issue #44 for the concrete example (a Gemini-authored `README.nl.md` was merged, then reverted, for exactly this reason).
- Shared working directories are a real hazard: a background agent's Bash tool and a live interactive session can end up pointed at the same checkout. Before switching/resetting a branch, check `git status --short` for surprises; if something unexpected is mid-flight, use `git worktree add` into a separate directory instead of touching the shared one.

---

## 7. Working method & Standards first

- Follow standard ways of doing things (upstream DAWO-Core, nixpkgs conventions, GitHub flow) unless it blocks the goal.
- Every deviation is recorded in `docs/deviations.md`, one line each with motivation, in the same PR that introduces it.
- Ask questions only when:
  - information is missing that makes the task impossible to carry out;
  - multiple options lead to materially different results;
  - an action is irreversible, destructive, or security-sensitive;
  - the requested change falls outside agreed scope.

### Periodic self-evaluation & invariant checking (Mandatory for Gemini / non-Claude agents)

Claude exhibits natural deliberation, context sensitivity, and careful restraint. To ensure non-Claude assistants (such as Gemini / Antigravity) maintain the same high standard of rigor and do not exhibit hasty, unreflective behavior:
- **Model self-verification:** The Gemini agent MUST operate using its highest reasoning tier (e.g., `gemini-3.1-pro-high` or a `claude-*-thinking` model) to match Claude's depth of thought. If the agent suspects it is running on a faster but shallower tier (like Flash), it must explicitly ask the user to adjust the `/model` setting before executing complex tasks.
- **Periodic self-evaluation:** Before and during any task, pause and ask:
  > *"Is this action in line with how Eduard (the maintainer) or Claude would approach it? Does it preserve existing standards, architectural boundaries, and conventions?"*
- **Hard invariant verification:** Explicitly check against the hard rules in this file (e.g. English-only repository content, non-destructive safety defaults, scope bounds). Do not turn casual maintainer brainstorming mentions into immediate PRs.
- **Ask upon any doubt:** When encountering ambiguity, conflicting goals, or doubt about whether a change belongs in the repository: stop, do not take unilateral action, and ask the maintainer directly.

---

## 8. Starting a session & Validation

- Run `bash scripts/status.sh` (via Git Bash) first. It prints the current slice, blocking open questions, live checks, and recently changed files.
- Local validation without Nix: `tests/test-bootstrap-dryrun.sh`, `make check` (lint + test).
- Test-driven: A bug becomes a check first. Never claim a check passed without running it.
