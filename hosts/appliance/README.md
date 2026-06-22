# Appliance host definition

The installed NixOS host configuration for the appliance (Slice 2–3).

Will consume DAWO-NixOS as a pinned flake input and reuse its modules
(`flake.modules.nixos.profiles-dawo-generic`, `desktop-plasma`, ...) for the
DAWO-based KDE Plasma desktop, then add KVM/libvirt and the appliance services
(VM autostart, health check, browser open).

Not implemented yet. See `docs/roadmap.md` (Slices 2–3) and
`docs/upstream/revisions.md` for the reuse model.
