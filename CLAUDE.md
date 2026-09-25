# CLAUDE.md

Guidance for AI assistants (and humans) working in this repository.

## What this is

`dawo-appliance` is an **experimental, unofficial** reproducible appliance that
demonstrates a digitally autonomous government workplace: a bootable installer
ISO that provisions a NixOS host with a DAWO-based desktop, a KVM/libvirt Ubuntu
24.04 VM, single-node K3s, and a Mijn Bureau deployment, then opens it in the
browser.

It is **not** an official DAWO / Mijn Bureau / BZK distribution. Never imply it
is.

## Hard rules

- **Language:** All repository content — docs, code, comments, commit messages —
  is in **English**. (Conversation with the maintainer may be in Dutch.)
- **Keep upstream separate.** Consume DAWO-Core (formerly DAWO-NixOS; flake input) and
  mijn-bureau-infra (documented install path) by pinned revision. Do **not**
  copy upstream source unless strictly necessary and license-permitted. Do not
  create a fork or submodule without first explaining why it is needed.
- **Pin everything.** Exact revisions, Nix inputs, K3s version, Helm chart
  versions, and container image digests. Never use `main`, `latest`, or
  floating tags in reproducible builds. All pins live in version-controlled
  files (`manifest/appliance-manifest.json`, `flake.lock`).
- **Never commit secrets.** No passwords, tokens, private keys, or generated
  secrets in Git. Secrets are generated at install time.
- **License: EUPL-1.2** (`LICENSE`). Keep the SPDX identifier `EUPL-1.2` and do
  not relicense without the maintainer's approval.
- **No remote yet.** Do not configure or push to a remote Git repository.
- **Non-destructive by default.** Any code that can write to a disk MUST require
  an explicit target disk AND an explicit confirmation flag. Never make
  destructive disk changes while developing or testing.
- **No host/WSL changes without asking.** Do not install or change Windows/WSL
  system components (e.g. `/etc/wsl.conf`, installing Nix system-wide) without
  asking first.
- **Stay in scope.** Do not add functionality outside the stated v0.1 scope
  because it "might be useful later". Structure for extension; do not build
  unscoped features.
- **Distinguish blocking problems from later improvements** in every report.

## Environment notes (this machine)

- Windows 11 + WSL2, x86-64, KVM available inside WSL (`/dev/kvm`).
- **Claude Code runs on the Windows side** (Git Bash / PowerShell, cwd
  `C:\git\dawo-appliance`). **Nix (2.34.7, daemon, flakes) is installed only in
  the WSL distro `Ubuntu-24.04`** (user `ewitteveen`). Run Nix through it:
  `wsl -d Ubuntu-24.04 -e bash -lc 'cd /mnt/c/git/dawo-appliance && nix flake check'`.
  The default WSL distro "Ubuntu" has neither the user nor Nix. Keep the Nix
  store on the WSL ext4 filesystem (it is), not on the slow `/mnt/c` 9p mount.
  Runbook: `docs/nix-setup.md`.
- `/mnt/c` mounts with `metadata` (since 2026-06-22), so `chmod` and git work
  from WSL too (OQ-1 resolved). The repo is a git repo on `main`; commits need
  maintainer approval and there is **no remote yet**.
- Line endings: the repo is LF-only (`.gitattributes`). Windows git has
  `core.autocrlf=true`; do not convert files to CRLF.
- qemu/libvirt are not installed on the Windows side; VM tests run inside WSL
  via Nix (`nix build .#test-installer-boot -L`, needs KVM).

## Scope (v0.1)

In: x86-64, online install, single machine, one Ubuntu 24.04 VM, single-node
K3s, Mijn Bureau, auto-start, local health check, auto-open browser.

Out: openDesk, Nextcloud AIO, multi-node, HA, branding, AD, offline install.

## Layout

`README.md` is the front door (directory table included); `docs/README.md`
indexes every document. Pins: `manifest/`. Upstream facts:
`docs/upstream/revisions.md`. Decisions: `docs/adr/`. Unknowns:
`docs/open-questions.md`. Generated, never hand-edited:
`docs/verification-latest.md`, `docs/verification-history.csv`,
`docs/screenshots/PROVENANCE.md` and the PNGs next to it.

## Starting a session

Run `bash scripts/status.sh` (or `make status`) first. It prints where we left
off (current slice + next step from `docs/STATUS.md`), the blocking open
questions, live checks (manifest checksum + dry-run tests), and recently changed
files — no Nix, network, or git required. Update `docs/STATUS.md` at the end of a
session so the next one starts oriented.

## Working method

Carry the task through from start to finish autonomously. Do not ask for
confirmation on normal implementation choices, file edits, tests, bug fixes, or
easily reversible decisions. For minor ambiguities, make a reasonable choice,
record it briefly, and continue.

Ask a question only when:

- information is missing that makes the task impossible to carry out;
- multiple options lead to materially different end results;
- an action is irreversible, destructive, or security-sensitive;
- the requested change falls outside the agreed scope.

Do not stop after analysis or a plan. Make the change, test it, and then report
briefly what was done and what could not yet be established. (The hard rules
above — non-destructive by default, no secrets, no host/WSL changes without
asking, commits only when asked — always take precedence.)

## Test-driven, in the small

- **A bug becomes a check first.** When something fails (boot, eval, a wrong
  upstream assumption, a flaky assertion), add or extend a check that
  reproduces it, then fix, and keep the check in the suite and in the matrix
  in `docs/testing.md`.
- **Green means a real run.** `docs/verification-latest.md` is written only by
  `REPORT=1 bash scripts/verify.sh`. Never claim a check passed without that
  run; the README points at that file.
- Before reporting a slice done, run `bash scripts/verify.sh` (inside WSL
  `Ubuntu-24.04` on this machine) and record the result.

## Local validation

- `tests/test-bootstrap-dryrun.sh` — runs the bootstrap in dry-run against the
  local manifest (no network, no Nix, no root). Verifies checksum behaviour and
  that no disk writes occur.
- `make check` (lint + test), `make plan`, `make fmt` — see `Makefile`.
- Nix checks (`nix flake check`, `nix develop`, VM boot tests) run inside the
  WSL distro `Ubuntu-24.04` (see Environment notes); `bash scripts/verify.sh`
  chains all of them. Documented in `docs/development.md`.

## Conventions

- Commit messages: Conventional Commits (matches DAWO-Core upstream), English.
- Shell scripts: `bash`, `set -euo pipefail`, pass `shellcheck`.
- Do not create commits unless the maintainer asks.
