# KVM/libvirt on the appliance host (Slice 3). An addition on top of the DAWO
# workplace (ADR 0003): it changes nothing in the desktop experience; it adds
# the hypervisor the Ubuntu 24.04 / K3s / Mijn Bureau guest (Slice 4+) runs on.
{ config, lib, pkgs, ... }:

{
  virtualisation.libvirtd = {
    enable = true;
    # The guest is started by its own libvirt autostart flag (Slice 4); at host
    # shutdown, ask guests to shut down cleanly instead of killing them.
    onBoot = "start";
    onShutdown = "shutdown";
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  # The operator can inspect the guest with virt-manager; the appliance
  # services themselves talk to libvirt directly.
  programs.virt-manager.enable = true;

  # libvirt's default NAT network. Upstream enables nftables; libvirt handles
  # both firewall backends.
  networking.firewall.trustedInterfaces = [ "virbr0" ];

  # The DAWO bootstrap/operator account (upstream `users-dawo`) may manage VMs.
  # Guarded like upstream's own definition, so disabling the bootstrap user
  # later does not leave a dangling user definition.
  users.users.dawo.extraGroups = lib.mkIf config.dawo.bootstrapUser.enable [ "libvirtd" ];
}
