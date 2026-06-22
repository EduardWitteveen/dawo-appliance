# Roadmap

Incremental, vertical slices. Each slice is runnable and adds one layer toward
the full boot-to-demo flow (`docs/architecture.md`). Destructive steps are gated
behind explicit confirmation and built late.

## Slice 0 — scaffolding (done / in progress)

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

## Slice 2 — host install (destructive, gated)

### Slice 2a (DONE 2026-06-22)

- Explicit-target-disk disko module, never a default device
  (`hosts/profiles/disko/single-disk.nix`; sentinel `appliance.targetDisk`).
- Installable host `nixosConfigurations.appliance` (minimal bootable, GRUB-EFI).
- Verified: `appliance-disk-image` builds a bootable raw image (disko format +
  nixos-install succeed); `test-appliance-boot` boots the host config and
  asserts identity, the operator account, the bootstrap and NetworkManager.

### Slice 2b (next)

- Bootstrap `install` subcommand: drive disko + nixos-install on a confirmed
  target disk (`--target-disk` + `--confirm-destroy`, block-device safety
  checks), then reboot into the installed host.
- LUKS encryption + swap subvolume (upstream parity; key generated at install).

## Slice 3 — DAWO desktop + virtualisation

- Consume DAWO-NixOS `profiles-dawo-generic` / `desktop-plasma` (pinned input).
- Configure KVM/libvirt on the host.

## Slice 4 — Ubuntu 24.04 VM

- Pin the Ubuntu 24.04 cloud image (version + SHA-256) — resolves OQ-6.
- libvirt domain + cloud-init; auto-start the VM.

## Slice 5 — single-node K3s

- Pin the K3s release (version + checksum) — resolves OQ-6.
- Install/start single-node K3s in the VM.

## Slice 6 — Mijn Bureau

- Resolve local DNS + self-signed TLS (OQ-3).
- Drive mijn-bureau-infra Helmfile (pinned rev `ef1d796…`), generate the master
  password at install time (never stored in Git).
- Digest-pin images (OQ-5).

## Slice 7 — health + browser

- Health check: wait until certificates Ready and the dashboard responds.
- Open `https://bureaublad.<domain>` in the browser.

## Hardening (cross-cutting, after MVP)

- Signature verification of manifest + artifacts (OQ-7).
- Reproducibility audit of all pins.
- Offline install (explicitly out of v0.1 scope).

## Decisions needed (see open-questions.md)

- **OQ-3** local DNS/TLS (blocks slices 6–7). — still open.
- OQ-2 large host for the full end-to-end run (slices 5–7). — still open.

Resolved: OQ-1 (WSL `metadata` enabled, git/Nix work here), OQ-4 (license =
EUPL-1.2).
