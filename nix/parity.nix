# Workplace parity check (ADR 0003).
#
# Compares the option values that define the DAWO pilot experience between the
# appliance host and upstream's pilot client host at the pinned DAWO-Core tag.
# A pin bump that changes the pilot's choices fails `nix flake check` until the
# appliance follows or the deviation is recorded in `deviations` below (and in
# ADR 0003). Evaluation only — nothing is built.
{ lib, pkgs, appliance, reference, referenceName }:

let
  # Option paths that shape what a user sees and how the machine is governed.
  paths = [
    [ "dawo" "desktop" "plasma" "enable" ]
    [ "dawo" "desktop" "gnome" "enable" ]
    [ "dawo" "apps" "office" "enable" ]
    [ "dawo" "apps" "office" "suite" ]
    [ "dawo" "apps" "comms" "enable" ]
    [ "dawo" "apps" "creative" "enable" ]
    [ "dawo" "apps" "media" "enable" ]
    [ "dawo" "apps" "dev" "enable" ]
    [ "dawo" "apps" "security" "enable" ]
    [ "dawo" "secureboot" "enable" ]
    [ "dawo" "pam" "lockout" "enable" ]
    [ "dawo" "pam" "quality" "enable" ]
    [ "dawo" "ssh" "enable" ]
    [ "dawo" "sysctlBaseline" "enable" ]
    [ "dawo" "timesync" "enable" ]
    [ "dawo" "usbControl" "enable" ]
    [ "dawo" "bootstrapUser" "enable" ]
    [ "dawo" "autoUpdate" "enable" ]
    [ "services" "desktopManager" "plasma6" "enable" ]
    [ "services" "displayManager" "sddm" "enable" ]
    [ "services" "displayManager" "autoLogin" "enable" ]
    [ "services" "printing" "enable" ]
    [ "services" "flatpak" "enable" ]
    [ "services" "pipewire" "enable" ]
    [ "i18n" "defaultLocale" ]
    [ "time" "timeZone" ]
    [ "users" "mutableUsers" ]
    [ "boot" "loader" "systemd-boot" "enable" ]
    [ "boot" "plymouth" "enable" ]
  ];

  # Deliberate deviations: appliance value on the left, pilot value on the
  # right. Anything else that differs is a parity bug.
  deviations = {
    # Pinned artifact; comin must not rebuild the host from Codeberg main.
    "dawo.autoUpdate.enable" = { appliance = false; reference = true; };
    # Demo appliance lands on the desktop without a login screen.
    "services.displayManager.autoLogin.enable" = { appliance = true; reference = false; };
  };

  name = lib.concatStringsSep ".";
  get = cfg: path: lib.attrByPath path "<unset>" cfg;
  show = v: builtins.toJSON v;

  rows = map
    (path:
      let
        key = name path;
        a = get appliance path;
        r = get reference path;
        dev = deviations.${key} or null;
        status =
          if dev != null then
            (if a == dev.appliance && r == dev.reference then "DEVIATION (recorded)" else "DEVIATION DRIFTED")
          else if a == r then "same"
          else "MISMATCH";
      in
      { inherit key status; a = show a; r = show r; })
    paths;

  bad = builtins.filter (row: row.status == "MISMATCH" || row.status == "DEVIATION DRIFTED") rows;

  report = lib.concatStringsSep "\n" (
    [ "workplace parity: appliance vs ${referenceName}" "" ]
    ++ map (row: "${row.status}\t${row.key}\tappliance=${row.a}\tpilot=${row.r}") rows
    ++ [ "" ]
  );
in
if bad != [ ] then
  throw ''
    Workplace parity check FAILED (ADR 0003). The appliance host differs from
    upstream's pilot host ${referenceName} in options that shape the user
    experience. Either follow upstream or record the deviation in
    nix/parity.nix and docs/adr/0003-workplace-parity.md.

    ${report}
  ''
else
  pkgs.runCommand "workplace-parity" { passAsFile = [ "report" ]; inherit report; } ''
    cp "$reportPath" "$out"
  ''
