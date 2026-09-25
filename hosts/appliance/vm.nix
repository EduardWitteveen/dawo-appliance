# `nix run .#appliance-vm` — the installed appliance host as a local QEMU VM
# with a window, so a human can look at the DAWO workplace (SDDM, Plasma, the
# pilot app set) without installing anything. Development aid only; it is NOT
# the installer and NOT the disk image.
#
# Differences from the real host, all VM-only:
# - qemu-vm.nix supplies the disk and file systems; disko's generated
#   fileSystems/swap are switched off (the layout is still what `install` uses).
# - No bootloader is installed (direct kernel boot).
# - Login: user `dawo` with upstream's documented bootstrap default password
#   (no install-time password exists in a VM run; see appliance-services.nix).
# - `-cpu host` so KVM inside the VM (libvirt, Slice 4) can work where the host
#   allows nested virtualisation (WSL2 does).
{ lib, modulesPath, ... }:

{
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

  disko.enableConfig = lib.mkForce false;

  virtualisation = {
    memorySize = 6144;
    cores = 4;
    diskSize = 40 * 1024;
    graphics = true;
    resolution = { x = 1600; y = 900; };
    qemu.options = [ "-cpu host" ];
    # No shared store mount; boot from the VM disk like a real machine would.
    writableStore = true;
  };
}
