# Nix modules

Shared NixOS modules for the appliance host (KVM/libvirt, appliance services,
VM autostart, browser-open). The top-level `flake.nix` wires these together.

v0.1 keeps the flake minimal (bootstrap package, dev shell, checks, and the
Slice 1 installer ISO via `installer/iso/iso.nix`). Host modules land in
Slices 2–3. `flake.lock` pins nixpkgs to `nixos-25.11` rev `d6df3513…` (the same
stable revision DAWO-NixOS pins).
