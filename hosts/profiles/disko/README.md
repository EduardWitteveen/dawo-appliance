# Disko (storage) profiles

Explicit-target-disk storage layouts for the appliance host.

**Slice 2.** Upstream DAWO-NixOS hard-codes its disko device to `/dev/nvme0n1`
(`disko-single-nvme-luks`). The appliance must never assume a device: every
layout here takes the target disk as a parameter and is only applied after the
operator passes an explicit `--target-disk` and `--confirm-destroy`.

## `single-disk.nix`

A single-disk layout parameterised by `device` (no hard-coded device) and
`swapSize` (default 2 GiB). GPT with:

- an EFI System Partition mounted at `/boot` (512 MiB, vfat), and
- a Btrfs root with subvolumes for `/`, `/home`, `/nix` (zstd, noatime) and a
  swapfile subvolume.

It is consumed by the appliance host (`hosts/appliance/disko.nix`, device from
the `appliance.targetDisk` option, sentinel default) and by the disk-image build
(`nix build .#appliance-disk-image`).

## No disk encryption in v0.1 (decision 2026-06-22)

Upstream DAWO-NixOS uses LUKS, but this appliance is an **experimental demo** and
the maintainer chose to keep storage **unencrypted** for v0.1: basic is enough
for a demo, and it is simpler to debug. Disk encryption (e.g. a keyfile or
TPM-bound auto-unlock that preserves the auto-start requirement) is a documented
**post-MVP hardening option**, not a v0.1 feature.
