# Disko (storage) profiles

Explicit-target-disk storage layouts for the appliance host.

**Slice 2.** Upstream DAWO-NixOS hard-codes its disko device to `/dev/nvme0n1`
(`disko-single-nvme-luks`). The appliance must never assume a device: every
layout here takes the target disk as a parameter and is only applied after the
operator passes an explicit `--target-disk` and `--confirm-destroy`.

## `single-disk.nix` (Slice 2a)

A single-disk layout parameterised by `device` (no hard-coded device). GPT with:

- an EFI System Partition mounted at `/boot` (512 MiB, vfat), and
- a Btrfs root with subvolumes for `/`, `/home` and `/nix` (zstd, noatime).

It is consumed by the appliance host (`hosts/appliance/disko.nix`, device from
the `appliance.targetDisk` option, sentinel default) and by the install+boot
test (`nix build .#test-host-install`), which remaps the device onto a
throwaway virtual disk — it never touches a real device.

**Deferred to Slice 2b** (upstream parity): LUKS encryption (key generated at
install time, never committed) and a swap subvolume.
