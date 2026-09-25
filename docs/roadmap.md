# Roadmap

Incremental, vertical slices. Each slice is runnable and adds one layer toward
the full boot-to-demo flow (`docs/architecture.md`). Destructive steps are gated
behind explicit confirmation and built late. Purpose and success criteria:
`docs/purpose.md`.

## Slice 0 — scaffolding (DONE)

- Repository structure, docs, ADRs.
- Pinned manifest format + checksum.
- Minimal Nix flake + dev shell.
- Bootstrap `plan` command (download manifest, verify checksum, print plan,
  **no disk writes**).
- Local tests that need no Nix/root/network.

## Slice 1 — non-destructive live ISO + bootstrap dry-run (DONE 2026-06-22)

A bootable NixOS live ISO that:

- boots successfully ✅ (verified headless in QEMU/KVM);
- has working networking ✅ (NetworkManager);
- contains the `dawo-appliance-bootstrap` command ✅;
- downloads a pinned manifest from a release of this repository ✅
  (`--manifest-url`, incl. `file://`; real release host is OQ-8);
- verifies its checksum ✅;
- shows what would be installed (the plan) ✅;
- **does not write to disk** ✅ (destructive flags refused).

Build: `nix build .#installer-iso` → `dawo-appliance-installer.iso` (1.4 GiB).
Verified two ways: the offline dry-run suite (`nix flake check`, no privileges)
and a full headless boot test (`nix build .#test-installer-boot`, needs KVM)
that boots the live payload and asserts the bootstrap runs non-destructively.

Upstream now ships its own headless fleet installer; we keep ours on purpose
(`docs/adr/0002-own-installer-iso.md`).

## Slice 2 — host install (destructive, gated)

### Slice 2a (DONE 2026-06-22)

- Explicit-target-disk disko module, never a default device
  (`hosts/profiles/disko/single-disk.nix`; sentinel `appliance.targetDisk`).
- Installable host `nixosConfigurations.appliance` (minimal bootable; the
  GRUB-EFI choice of this slice was replaced by upstream's systemd-boot in
  Slice 3).
- Verified: `nix flake check`; the appliance toplevel builds; `diskoScript`
  builds (the layout, touching only the sentinel device); and
  `test-appliance-boot` boots the host config and asserts identity, the operator
  account, the bootstrap and NetworkManager. (`appliance-disk-image` builds a
  full raw image but is KVM-flaky on WSL — see open-questions OQ-9.)

### Slice 2b (DONE 2026-06-22)

- ✅ Bootstrap `install` subcommand: drives `disko-install` on a confirmed
  target disk (`--target-disk` + `--confirm-destroy`, block-device / mount /
  live-medium safety checks, `--dry-run` preview). `disko-install` ships on the
  ISO. Gating covered by the dry-run suite (`docs/testing.md`, R2–R4).
- ✅ Swap subvolume added to the disko layout.
- ❌ LUKS encryption — **out of v0.1 by decision** (experimental demo; basic
  unencrypted storage is enough and simpler to debug). Disk encryption is a
  documented post-MVP hardening option.

### Slice 2c — upstream refresh (DONE 2026-09-25)

Three months of upstream movement, re-inspected and re-pinned
(`docs/upstream/revisions.md`, `manifest/appliance-manifest.json`):

- ✅ DAWO-NixOS became **DAWO-Core on Codeberg**; pinned to release `0.1.3`
  (`695f17c…`). Ecosystem recorded in `docs/upstream/ecosystem.md`.
- ✅ nixpkgs **`nixos-25.11` → `nixos-26.05`** (25.11 is end-of-life), same rev
  DAWO-Core pins; disko to the rev DAWO-Core pins; `stateVersion` 26.05.
- ✅ mijn-bureau-infra pinned to `b2ae545…` (2026-07-27); image tags refreshed.
- ✅ ADR 0002 (keep our own installer), ADR 0003 (workplace parity),
  `docs/purpose.md` (goal, rationale, deviations, trade-offs).
- ✅ Housekeeping: `.gitattributes` (LF-only), environment notes for the
  Windows + WSL setup, stale comments.
- Verification: `nix flake check`, ISO build and both boot tests on 26.05 — see
  `docs/STATUS.md` for the result of this run.

## Slice 3 — DAWO workplace + virtualisation (built 2026-09-25; verification in STATUS.md)

Parity rule: the host **is** the DAWO pilot workplace, plus additions
(`docs/adr/0003-workplace-parity.md`).

- ✅ DAWO-Core `0.1.3` is a pinned flake input (`git+https://codeberg.org/…?ref=refs/tags/0.1.3`,
  rev locked; nixpkgs and disko follow ours, which are upstream's revs).
- ✅ `hosts/appliance/dawo-workplace.nix` imports what a pilot client imports:
  `boot-loader`, `boot-plymouth-bzk`, `profiles-dawo-generic`,
  `maid-dawo-generic`; Plasma; app sets office/comms/creative/media; Secure
  Boot off. Our GRUB and our own `users.users.dawo` are gone (upstream's
  systemd-boot and `users-dawo` apply).
- ✅ Deviations only as listed in ADR 0003: our disko module, generic
  hardware (microcode both vendors), `dawo.autoUpdate.enable = false`,
  **auto-login as `dawo`** plus a **welcome dialog** with the login details
  (demo: nothing to type), upstream's default password by default and an
  install-time generated one with `install --generate-password` (hash shipped
  by `install`, applied once at first boot by
  `dawo-appliance-set-password.service`).
- ✅ KVM/libvirt (`hosts/appliance/virtualisation.nix`): libvirtd + swtpm,
  virt-manager, `dawo` in `libvirtd`.
- ✅ Parity check `checks.workplace-parity` (`nix/parity.nix`) in
  `nix flake check`: 29 user-facing options compared with `hosts/dawo-t495s`
  at the pinned tag; two recorded deviations (auto-update off, auto-login on).
- ✅ `nix run .#appliance-vm`: the host in a QEMU window for a human look.
- ✅ The ISO now ships this flake at `/etc/dawo-appliance/config` (the default
  install source) and `mkpasswd`.
- Boot test `test-appliance-boot` extended: `graphical.target`, SDDM, pilot
  apps present, hardening active, libvirtd, comin inactive, screenshot.

## Slice 4 — Ubuntu 24.04 VM

- Pin the Ubuntu 24.04 cloud image (version + SHA-256) — resolves OQ-6 part 1.
- libvirt domain + cloud-init; auto-start the VM.

## Slice 5 — single-node K3s

- Pin the K3s release (version + checksum) — resolves OQ-6 part 2. Upstream
  installs K3s unpinned from `get.k3s.io`; we do not.
- Install/start single-node K3s in the VM.

## Slice 6 — Mijn Bureau

- Resolve local DNS + self-signed TLS (OQ-3).
- Drive mijn-bureau-infra Helmfile at the pinned rev `b2ae545…` with the
  sub-scripts taken from that revision (never from a live raw URL); generate
  the master password at install time (never stored in Git).
- Digest-pin images (OQ-5).

## Slice 7 — health + browser

- Health check: wait until certificates Ready and the dashboard responds.
- Open `https://bureaublad.<domain>` in the browser at desktop login.

## Hardening (cross-cutting, after MVP)

- Signature verification of manifest + artifacts (OQ-7).
- Reproducibility audit of all pins.
- LUKS (upstream layout), Secure Boot / TPM2 as upstream documents them.
- Offline install (explicitly out of v0.1 scope).

## Decisions needed (see open-questions.md)

- **OQ-3** local DNS/TLS (blocks slices 6–7). — still open.
- OQ-2 large host for the full end-to-end run (slices 5–7). — still open.

Resolved: OQ-1 (WSL `metadata` enabled, git/Nix work here), OQ-4 (license =
EUPL-1.2). Decided 2026-09-25: own installer kept (ADR 0002), workplace parity
(ADR 0003).
