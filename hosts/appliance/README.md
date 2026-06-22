# Appliance host definition

The installed NixOS host configuration for the appliance (Slice 2–3).

## Now (Slice 2a)

- `configuration.nix` — minimal bootable host: GRUB EFI (removable), hostname
  `dawo-appliance`, NetworkManager, a `dawo` operator account, and the
  `dawo-appliance-bootstrap` command. Storage comes from disko.
- `disko.nix` — wires `hosts/profiles/disko/single-disk.nix` and exposes
  `appliance.targetDisk` (sentinel default; the install overrides it explicitly).

Built as `nixosConfigurations.appliance`; verified by `nix build
.#test-host-install` (install to a throwaway disk + boot).

## Later (Slice 3+)

Consume DAWO-NixOS as a pinned flake input and reuse its modules
(`flake.modules.nixos.profiles-dawo-generic`, `desktop-plasma`, ...) for the
DAWO-based KDE Plasma desktop, then add KVM/libvirt and the appliance services
(VM autostart, health check, browser open). See `docs/roadmap.md` and
`docs/upstream/revisions.md` for the reuse model.
