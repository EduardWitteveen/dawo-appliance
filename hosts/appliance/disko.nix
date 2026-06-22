# Wires the single-disk storage layout into the appliance host and exposes the
# target disk as an explicit option.
#
# `appliance.targetDisk` has an intentionally non-existent sentinel default so
# the configuration still evaluates (e.g. `nix flake check`) WITHOUT ever
# pointing at a real device. The actual install overrides it explicitly — the
# bootstrap requires `--target-disk` and runs `disko-install --disk main <dev>`
# (or sets this option), honouring the project's non-destructive-by-default rule.
{ config, lib, ... }:

{
  options.appliance.targetDisk = lib.mkOption {
    type = lib.types.str;
    default = "/dev/disk/by-id/DAWO_APPLIANCE_SET_TARGET_DISK";
    example = "/dev/sda";
    description = ''
      Explicit target disk for installation. The default is a deliberately
      non-existent sentinel so nothing is wiped by accident; a real install must
      override it with an explicit device.
    '';
  };

  config = import ../profiles/disko/single-disk.nix {
    device = config.appliance.targetDisk;
  };
}
