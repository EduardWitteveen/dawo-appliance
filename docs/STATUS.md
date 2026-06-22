# STATUS — session handoff

Single source of truth for "where were we". Keep this short and current.
Update the **Now / Next / Recently done** sections at the end of a work session;
`scripts/status.sh` prints this file plus a few live checks at the start of one.

This is an **experimental, unofficial** appliance — not an official DAWO / Mijn
Bureau / BZK distribution (see `CLAUDE.md`).

## Now

- **Slice 1 DONE + verified.** The live ISO (`dawo-appliance-installer.iso`,
  1.4 GiB) builds, and the headless boot test passes: the VM boots to
  multi-user.target, `dawo-appliance-bootstrap` runs `plan` non-destructively
  (checksum verified, no disk writes), and the destructive flags are refused.
- Nix is installed (2.34.7, daemon). `nix flake check` is green (portable, no
  kvm). Boot test: `nix build .#test-installer-boot -L` (needs kvm, ~72 s).
- KVM is enabled for VM tests (user + nixbld* in `kvm` group; `kvm` system
  feature on). See `docs/nix-setup.md`.
- Slices 2–7 are scaffolding (README placeholders) only.

## Next

- **Slice 2** (host install, destructive, gated): design the disko module with
  an explicit `--target-disk` + `--confirm-destroy`, and a boot test that
  installs to a **throwaway qcow2** virtual disk (never a real device) and then
  boots the installed system. Fully verifiable on this machine.
- Resolve OQ-3 (local DNS + self-signed TLS) before slices 6–7 can start.
- Repo has **no remote yet** — decide if/when to add one. Commits still need
  maintainer approval.

## Blocking decisions

- **OQ-1** — RESOLVED 2026-06-22. `/mnt/c` now mounts with `metadata`;
  `chmod` / `git init` work here. See `docs/open-questions.md`.
- **OQ-3** — local DNS/TLS strategy; blocks Mijn Bureau + browser slices.
- **OQ-2** — this machine has 15 GiB RAM; cannot run the full stack end-to-end.

## Recently done

- Pinned manifest + checksum, minimal flake/dev shell, bootstrap `plan`/`verify`.
- Offline dry-run test suite (4 checks, all passing).
- This handoff doc + `scripts/status.sh` orientation helper.
- OQ-1 resolved: WSL `metadata` enabled, `git init` verified working on `/mnt/c`.
- Git repo initialised on branch `main`; initial commit `1d94cc2` (28 files).
- Nix installed (2.34.7, daemon) per `docs/nix-setup.md`; flakes enabled.
- `nix flake check` green; ISO built (`nix build .#installer-iso`, 1.4 GiB).
- Fixed `iso.nix`: ISO filename derives from `image.baseName` (renamed from
  `isoImage.isoBaseName` in 25.11), so the artifact is now correctly named
  `dawo-appliance-installer.iso` instead of `nixos-minimal-…iso`.
- Factored the shared live payload (`installer/live-payload.nix`) + single
  bootstrap derivation (`installer/bootstrap/package.nix`).
- Added `test-installer-boot` (NixOS VM test); enabled KVM; boot test passes.

## Quick pointers

- Nix install runbook (WSL): `docs/nix-setup.md`
- Roadmap (all slices): `docs/roadmap.md`
- Open questions / decisions: `docs/open-questions.md`
- Architecture: `docs/architecture.md`
- Local dev commands: `docs/development.md`, `Makefile`
