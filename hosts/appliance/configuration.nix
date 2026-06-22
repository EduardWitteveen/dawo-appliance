# Installed appliance host — minimal bootable system (Slice 2a).
#
# This is what gets installed onto the target disk and booted. It is
# deliberately minimal: the DAWO-based desktop (KDE Plasma 6), KVM/libvirt and
# the appliance services (VM autostart, health check, browser open) are added in
# later slices (3+). Storage (fileSystems) comes from the disko layout.
{ lib, pkgs, ... }:

let
  # Same wrapped bootstrap the ISO ships, available on the installed host too.
  bootstrap = pkgs.callPackage ../../installer/bootstrap/package.nix { };
in
{
  # GRUB EFI installed as "removable" (/EFI/BOOT/BOOTX64.EFI) so the host boots
  # under generic firmware and in the headless VM test without writing EFI
  # variables. (systemd-boot / efivars parity can be revisited with upstream.)
  #
  # The EFI options are mkDefault so the disko VM-test harness (which injects its
  # own grub EFI/portability settings) can override them in-test; they apply
  # as-is for a real install. systemd-boot is explicitly disabled because the
  # test harness enables it by default, which would clash with GRUB.
  boot.loader.grub = {
    enable = true;
    efiSupport = lib.mkDefault true;
    efiInstallAsRemovable = lib.mkDefault true;
    devices = lib.mkDefault [ "nodev" ];
  };
  boot.loader.systemd-boot.enable = false;

  networking.hostName = "dawo-appliance";
  networking.networkmanager.enable = true;

  # Non-root operator account. No password is stored in Git; it is set at install
  # time (a later slice). Until then the account has no password set.
  users.users.dawo = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };

  # The bootstrap command is available on the installed host as well.
  environment.systemPackages = [ bootstrap pkgs.git ];

  system.stateVersion = "25.11";
}
