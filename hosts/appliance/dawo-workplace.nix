# The DAWO workplace, imported unchanged from DAWO-Core (Slice 3, ADR 0003).
#
# Parity rule: the appliance host IS a DAWO pilot workplace. This module
# imports exactly the module set a pilot client (`hosts/dawo-t495s` at the
# pinned tag) imports and makes the same host-level choices. Anything that
# shapes the user experience comes from upstream; our own layers (libvirt, the
# VM, Mijn Bureau, browser) are additions in sibling modules. Every deviation
# is listed in docs/adr/0003-workplace-parity.md and checked by nix/parity.nix.
#
# `dawoCore` is the pinned DAWO-Core flake (specialArg from flake.nix). Its
# modules expect upstream's own `inputs` and `hostConfig` as specialArgs, which
# flake.nix also supplies.
{ dawoCore, lib, modulesPath, ... }:

{
  imports = (with dawoCore.modules.nixos; [
    # Boot: systemd-boot (Secure Boot/lanzaboote stays opt-in and off) and the
    # BZK boot splash.
    boot-loader
    boot-plymouth-bzk
    # The composite workplace profile: hardware baseline, mandatory hardening,
    # desktops, environment, app sets, nl_NL, networking, programs, services,
    # users.
    profiles-dawo-generic
    # Plasma workspace as handed to a user (panel layout, wallpaper, defaults).
    maid-dawo-generic
  ]) ++ [
    # Generic hardware (D3): also installable as a virtual machine (virtio
    # disk/net/console drivers in the initrd; NixOS' standard profile, harmless
    # on bare metal). Found by the end-to-end install test (issue #14).
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  # --- Same choices as the pilot client host ------------------------------
  dawo.desktop.plasma.enable = true;
  dawo.apps = {
    office.enable = true; # office.suite defaults to libreoffice, as upstream
    comms.enable = true;
    creative.enable = true;
    media.enable = true;
  };
  dawo.secureboot.enable = false;

  # --- Deliberate deviations (ADR 0003) ------------------------------------

  # The appliance is a pinned, reproducible artifact. comin would otherwise
  # poll Codeberg `main` and rebuild the host, dropping our additions.
  dawo.autoUpdate.enable = false;

  # Generic hardware instead of a laptop-model module: microcode for both
  # vendors on top of upstream's hardware-dawo-base (firmware, fwupd, zram).
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  # Upstream ships the `dawo` bootstrap account with a documented default
  # password so a fresh image is always loginable. The demo appliance keeps it
  # (acknowledged, which silences upstream's warning) because "as easy as
  # possible" is the requirement; `dawo-appliance-bootstrap install
  # --generate-password` replaces it at first boot with a generated one. See
  # appliance-services.nix.
  dawo.bootstrapUser.acknowledgeDefaultPassword = true;

  # Demo appliance: land on the desktop without a login screen. Upstream's
  # pilot shows SDDM (autoLogin.enable = false, set plainly, hence mkForce).
  # The screen still locks per upstream's hardening rule; the welcome dialog
  # (appliance-services.nix) tells the user which password unlocks it.
  services.displayManager.autoLogin = {
    enable = lib.mkForce true;
    user = "dawo";
  };
}
