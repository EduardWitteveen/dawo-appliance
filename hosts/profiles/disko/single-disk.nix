# Single-disk storage layout for the appliance host, parameterised by `device`.
#
# This NEVER hard-codes a device: the caller must pass one. GPT layout with an
# EFI System Partition (/boot) and a Btrfs root carrying subvolumes for /, /home
# and /nix (zstd, noatime).
#
# Scope: Slice 2. Btrfs root with /, /home, /nix and a swap subvolume. Disk
# encryption (LUKS) is intentionally out of v0.1: this is an experimental demo
# and basic (unencrypted) storage is sufficient; encryption is a documented
# post-MVP hardening option (see hosts/profiles/disko/README.md).
#
# Used by:
#   - the appliance host config (hosts/appliance/disko.nix), device from the
#     `appliance.targetDisk` option, and
#   - the disk-image build (flake `appliance-disk-image`).
{ device, swapSize ? "2G" }:
{
  disko.devices.disk.main = {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          name = "ESP";
          start = "1M";
          end = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ]; # override any existing signature
            subvolumes = {
              "/rootfs" = {
                mountpoint = "/";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "/home" = {
                mountpoint = "/home";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "/nix" = {
                mountpoint = "/nix";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "/swap" = {
                mountpoint = "/.swapvol";
                swap.swapfile.size = swapSize;
              };
            };
          };
        };
      };
    };
  };
}
