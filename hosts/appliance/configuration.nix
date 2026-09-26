# Installed appliance host (Slices 2–3).
#
# This is what gets installed onto the target disk and booted. It is the DAWO
# workplace — imported unchanged from DAWO-Core in dawo-workplace.nix (ADR
# 0003) — plus the appliance's own additions: KVM/libvirt (virtualisation.nix),
# the appliance services (appliance-services.nix), the per-install CA
# (appliance-ca.nix), the Ubuntu guest VM and its network (guest-vm.nix, Slice
# 4a), and the bootstrap command.
# The Ubuntu VM, K3s, Mijn Bureau, health check and browser step follow in
# slices 4–7. Storage (fileSystems) comes from the disko layout (disko.nix).
#
# Boot loader, users (incl. the `dawo` admin account), networking, locale,
# hardening and `system.stateVersion` all come from the DAWO profile; do not
# redefine them here — every deviation must be recorded in ADR 0003.
{ pkgs, ... }:

let
  # Same wrapped bootstrap the ISO ships, available on the installed host too.
  bootstrap = pkgs.callPackage ../../installer/bootstrap/package.nix { };
in
{
  imports = [
    ./dawo-workplace.nix
    ./virtualisation.nix
    ./appliance-services.nix
    ./appliance-ca.nix
    ./guest-vm.nix
  ];

  networking.hostName = "dawo-appliance";

  # The bootstrap command is available on the installed host as well.
  environment.systemPackages = [ bootstrap pkgs.git ];
}
