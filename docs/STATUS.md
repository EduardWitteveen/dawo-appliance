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
- **Slice 2a DONE + verified.** Installable appliance host
  (`nixosConfigurations.appliance`): disko single-disk layout (parameterised,
  never a hard-coded device — sentinel `appliance.targetDisk`), minimal bootable
  GRUB-EFI host. `appliance-disk-image` builds a bootable raw image (disko
  format + nixos-install succeed); `test-appliance-boot` boots the host config
  and asserts identity/operator/bootstrap/NetworkManager.
- Nix is installed (2.34.7, daemon). `nix flake check` is green (portable, no
  kvm). VM tests need kvm: `nix build .#test-installer-boot -L`,
  `.#test-appliance-boot -L`, `.#appliance-disk-image`.
- KVM is enabled for VM tests (user + nixbld* in `kvm` group; `kvm` system
  feature on). See `docs/nix-setup.md`.
- Slices 3–7 are scaffolding (README placeholders) only.

## Next

- **Slice 2b**: (1) ✅ DONE — the gated `install` subcommand (`disko-install`,
  `--target-disk` + `--confirm-destroy`, safety checks, `--dry-run`); shipped on
  the ISO; 8 dry-run checks. (2) ⬜ swap subvolume + LUKS encryption (upstream
  parity) — LUKS unlock strategy is a pending security-sensitive decision.
- **Slice 3** (DAWO desktop + KVM/libvirt): consume DAWO-NixOS modules.
- Resolve OQ-3 (local DNS + self-signed TLS) before slices 6–7 can start.
- Repo has **no remote yet** — decide if/when to add one. Commits still need
  maintainer approval.

Known limitation: disko's own `makeDiskoTest` is incompatible with nixpkgs
25.11's test driver (`machines_qemu`); we cover install via `appliance-disk-image`
+ the install phase, and boot via the native `test-appliance-boot`.

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
- Slice 2a: pinned disko; `nixosConfigurations.appliance` + single-disk Btrfs
  layout; `appliance-disk-image` and `test-appliance-boot` both pass.

## Quick pointers

- Nix install runbook (WSL): `docs/nix-setup.md`
- Roadmap (all slices): `docs/roadmap.md`
- Open questions / decisions: `docs/open-questions.md`
- Architecture: `docs/architecture.md`
- Local dev commands: `docs/development.md`, `Makefile`
