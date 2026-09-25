# Non-destructive live installer ISO for dawo-appliance (Slice 1).
#
# Goal: a bootable NixOS live image that boots, has networking, and ships the
# `dawo-appliance-bootstrap` command plus the trusted manifest checksum. It does
# NOT install anything automatically and writes nothing to disk. The operator
# runs `dawo-appliance-bootstrap plan` to see what would be installed.
#
# The live-system payload (bootstrap, manifest, banner) lives in
# ../live-payload.nix and is shared with the headless boot test. This file adds
# only the CD-specific bits.
#
# Build (requires Nix; see docs/nix-setup.md):
#   nix build .#installer-iso
#
# Experimental and unofficial.
{ modulesPath, lib, ... }:

{
  imports = [
    # Minimal graphical-less installer base image from nixpkgs.
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    # The shared live-system payload (bootstrap + manifest + banner).
    ../live-payload.nix
  ];

  # Identify the image. Since nixpkgs 25.11 the ISO filename derives from
  # `image.baseName` (see iso-image.nix: `isoName = "${image.baseName}.iso"`).
  # The old `isoImage.isoName`/`isoBaseName` were renamed to `image.fileName`/
  # `image.baseName`; setting `isoName`/`fileName` alone does NOT rename the
  # built file, so we set `image.baseName` here.
  image.baseName = lib.mkForce "dawo-appliance-installer";
  isoImage.volumeID = lib.mkForce "DAWO_APPLIANCE";

  # Networking: bring up an internet connection (step 1 of the flow).
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false; # avoid clash with NetworkManager

  # Pin the state version to the pinned nixpkgs release.
  system.stateVersion = "26.05";
}
