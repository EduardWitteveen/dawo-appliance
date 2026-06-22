# Non-destructive live installer ISO for dawo-appliance (Slice 1).
#
# Goal: a bootable NixOS live image that boots, has networking, and ships the
# `dawo-appliance-bootstrap` command plus the trusted manifest checksum. It does
# NOT install anything automatically and writes nothing to disk. The operator
# runs `dawo-appliance-bootstrap plan` to see what would be installed.
#
# Build (requires Nix; blocked on this machine, see docs/open-questions.md OQ-1):
#   nix build .#installer-iso
#
# Experimental and unofficial.
{ modulesPath, pkgs, lib, ... }:

let
  # Wrap the bootstrap script with its runtime dependencies on PATH.
  bootstrap = pkgs.runCommand "dawo-appliance-bootstrap"
    { nativeBuildInputs = [ pkgs.makeWrapper ]; }
    ''
      mkdir -p $out/bin
      cp ${../bootstrap/dawo-appliance-bootstrap} $out/bin/dawo-appliance-bootstrap
      chmod +x $out/bin/dawo-appliance-bootstrap
      wrapProgram $out/bin/dawo-appliance-bootstrap \
        --prefix PATH : ${pkgs.lib.makeBinPath [
          pkgs.bash pkgs.coreutils pkgs.curl pkgs.jq pkgs.gnused pkgs.gawk
        ]}
    '';
in
{
  imports = [
    # Minimal graphical-less installer base image from nixpkgs.
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Identify the image.
  isoImage.isoName = lib.mkForce "dawo-appliance-installer.iso";
  isoImage.volumeID = lib.mkForce "DAWO_APPLIANCE";

  # Networking: bring up an internet connection (step 1 of the flow).
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false; # avoid clash with NetworkManager

  # Tools available on the live system.
  environment.systemPackages = with pkgs; [
    bootstrap
    curl
    jq
    coreutils
    git
  ];

  # Ship the trusted manifest + checksum read-only on the ISO. The bootstrap
  # falls back to /etc/dawo-appliance/manifest for the expected checksum.
  environment.etc."dawo-appliance/manifest/appliance-manifest.json".source =
    ../../manifest/appliance-manifest.json;
  environment.etc."dawo-appliance/manifest/appliance-manifest.json.sha256".source =
    ../../manifest/appliance-manifest.json.sha256;

  # Friendly login banner pointing at the bootstrap command.
  services.getty.helpLine = lib.mkForce ''

    dawo-appliance installer (experimental, unofficial) — NON-DESTRUCTIVE.
    Run:  dawo-appliance-bootstrap plan
    This downloads + verifies the pinned manifest and shows what WOULD be
    installed. It writes nothing to disk.
  '';

  # Pin the state version to the pinned nixpkgs release.
  system.stateVersion = "25.11";
}
