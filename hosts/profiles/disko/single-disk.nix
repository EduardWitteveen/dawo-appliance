# Single-disk storage layout for the appliance host, parameterised by `device`.
#
# This NEVER hard-codes a device: the caller must pass one. GPT layout with an
# EFI System Partition (/boot) and a Btrfs root carrying subvolumes for /, /home
# and /nix (zstd, noatime).
#
# Scope: Slice 2a. LUKS encryption and a swap subvolume (upstream DAWO-NixOS
# parity) are deferred to Slice 2b — see hosts/profiles/disko/README.md.
#
# Used by:
#   - the appliance host config (hosts/appliance/disko.nix), device from the
#     `appliance.targetDisk` option, and
#   - the install+boot test (flake `test-host-install`), device remapped by
#     disko's test harness to a throwaway virtual disk.
{ device }:
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
            };
          };
        };
      };
    };
  };
}
