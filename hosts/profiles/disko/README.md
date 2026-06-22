# Disko (storage) profiles

Explicit-target-disk storage layouts for the appliance host.

**Slice 2.** Upstream DAWO-NixOS hard-codes its disko device to `/dev/nvme0n1`
(`disko-single-nvme-luks`). The appliance must never assume a device: every
layout here takes the target disk as a parameter and is only applied after the
operator passes an explicit `--target-disk` and `--confirm-destroy`.

Planned: a single-disk BTRFS+LUKS layout parameterised by device, mirroring the
upstream subvolume structure (`/`, `/home`, `/nix`, swap) without a hard-coded
device. Not implemented yet.
