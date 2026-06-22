# Shared payload for the dawo-appliance live system.
#
# This is the part that must be present and working on the booted system: the
# `dawo-appliance-bootstrap` command, the trusted manifest + checksum shipped
# read-only under /etc, and a login banner. It carries NOTHING destructive and
# nothing CD-specific.
#
# Imported by:
#   - installer/iso/iso.nix   — the bootable live ISO (Slice 1)
#   - flake checks            — the headless boot test, so the test verifies
#                               exactly what the ISO ships.
{ pkgs, lib, ... }:

let
  bootstrap = pkgs.callPackage ./bootstrap/package.nix { };
in
{
  # Tools available on the live system.
  environment.systemPackages = with pkgs; [
    bootstrap
    curl
    jq
    coreutils
    git
  ];

  # Ship the trusted manifest + checksum read-only. The bootstrap falls back to
  # /etc/dawo-appliance/manifest for the expected checksum (its root of trust).
  environment.etc."dawo-appliance/manifest/appliance-manifest.json".source =
    ../manifest/appliance-manifest.json;
  environment.etc."dawo-appliance/manifest/appliance-manifest.json.sha256".source =
    ../manifest/appliance-manifest.json.sha256;

  # Friendly login banner pointing at the bootstrap command.
  services.getty.helpLine = lib.mkForce ''

    dawo-appliance installer (experimental, unofficial) — NON-DESTRUCTIVE.
    Run:  dawo-appliance-bootstrap plan
    This downloads + verifies the pinned manifest and shows what WOULD be
    installed. It writes nothing to disk.
  '';
}
