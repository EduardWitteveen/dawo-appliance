# Appliance-specific services (additions on top of the DAWO workplace).
#
# THIS IS A DEMO APPLIANCE, NOT FOR PRODUCTION: passwords are shown on screen
# and, when generated at install time, kept readable on the machine so the
# welcome dialog can repeat them. That is a deliberate choice for an evaluation
# box (docs/purpose.md, ADR 0003), and the dialog says so.
#
# 1. dawo-appliance-set-password.service — applies an install-time generated
#    password for the `dawo` account, once. `dawo-appliance-bootstrap install
#    --generate-password` generates a password on the live ISO and ships its
#    yescrypt hash (`hashFile`) plus the plain text (`passwordFile`) into the
#    installed system (disko-install --extra-files). On first boot this
#    one-shot unit applies the hash with chpasswd and removes the hash file;
#    the plain-text file stays for the welcome dialog. Because upstream keeps
#    `users.mutableUsers = true`, the user can change the password later and
#    the change sticks — as on a DAWO pilot laptop (ADR 0003).
#
#    Without the files (the default install, a VM run, the tests) nothing
#    happens and upstream's documented default password remains, exactly as
#    on a freshly imaged pilot device.
#
# 2. A welcome dialog at every Plasma login (XDG autostart): what this machine
#    is, which account is logged in, the password that unlocks the screen, and
#    what is (not yet) running. The appliance auto-logs in, so this is the one
#    place a user is told what to type.
# 3. Slice 7 (health/README.md): a second XDG autostart entry, one phase later
#    (X-KDE-autostart-phase=2, same as the welcome dialog, so the welcome
#    dialog's kdialog shows first), packages health/dawo-appliance-health.sh
#    and health/dawo-appliance-open-dashboard.sh with pkgs.writeShellApplication
#    (the scripts themselves are untouched; read by path, never hand-copied —
#    same principle as guest-vm.nix's k3sInstallScript) and runs the opener,
#    which waits for Mijn Bureau to become healthy and then opens the
#    dashboard, or shows a kdialog with what is still missing.
{ pkgs, ... }:

let
  stateDir = "/var/lib/dawo-appliance";
  hashFile = "${stateDir}/dawo.password-hash";
  passwordFile = "${stateDir}/dawo.password.txt";

  # Runtime tools the health check and the opener need (health/README.md):
  # ssh + curl to reach the guest/dashboard, systemd's resolvectl for DNS,
  # glibc's getent as a fallback, iputils' ping to phrase why ssh isn't up yet,
  # jq to parse the OIDC issuer, xdg-utils' xdg-open for the browser, kdialog
  # for the "not healthy yet" dialog. `k3s kubectl` itself runs over ssh on the
  # guest (ssh_run in the script), so no k3s/kubectl package is needed here.
  # Self-contained: the scripts must not depend on the caller's PATH (an XDG
  # autostart entry may start them with a minimal one; issue #98, where a
  # missing mktemp made the health check exit 127 right after login).
  healthRuntimeInputs = with pkgs; [
    bash
    coreutils
    gnugrep
    gnused
    gawk
    findutils
    iproute2
    openssh
    curl
    systemd
    glibc
    iputils
    jq
    xdg-utils
    kdePackages.kdialog
  ];

  health = pkgs.writeShellApplication {
    name = "dawo-appliance-health";
    runtimeInputs = healthRuntimeInputs;
    text = builtins.readFile ../../health/dawo-appliance-health.sh;
  };

  # The opener looks for the health script "next to it" by default
  # (DASHBOARD_HEALTH); packaging each script as its own writeShellApplication
  # gives them separate store paths, so point it explicitly at the packaged
  # health binary above, and default a log file under the user's XDG state
  # directory (health/README.md), unless the caller already set one (tests
  # invoke the raw .sh files directly and are unaffected by this).
  openDashboard = pkgs.writeShellApplication {
    name = "dawo-appliance-open-dashboard";
    runtimeInputs = healthRuntimeInputs;
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/dawo-appliance"
      mkdir -p "$state" 2>/dev/null || true
      : "''${DASHBOARD_HEALTH:=${health}/bin/dawo-appliance-health}"
      : "''${DASHBOARD_LOG:=$state/health.log}"
      export DASHBOARD_HEALTH DASHBOARD_LOG
    '' + builtins.readFile ../../health/dawo-appliance-open-dashboard.sh;
  };

  welcome = pkgs.writeShellScript "dawo-appliance-welcome" ''
    set -u
    if [ -r ${passwordFile} ]; then
      pw="$(tr -d '\n' < ${passwordFile})"
    else
      pw="dawo"
    fi
    ${pkgs.kdePackages.kdialog}/bin/kdialog \
      --title "DAWO appliance (experimenteel / experimental)" \
      --icon computer \
      --msgbox "<h3>Welkom bij de DAWO appliance</h3>
<p>Dit is een <b>experimentele, onofficiële demo-machine</b>: de DAWO-werkplek
(zoals in de pilots) met daarnaast een virtuele machine voor Mijn Bureau.</p>
<p><b>Ingelogd als:</b> dawo<br/>
<b>Wachtwoord</b> (voor het schermslot en beheertaken): <tt>$pw</tt></p>
<p>Mijn Bureau wordt na installatie automatisch uitgerold op de virtuele machine;
zodra dat gereed is opent deze appliance het dashboard vanzelf in de browser.</p>
<p><b>Niet voor productie.</b> Wachtwoorden staan leesbaar op deze machine en op
het scherm; er is geen schijfversleuteling. Alleen voor demonstratie en
evaluatie.</p>
<hr/>
<p><small>English: experimental, unofficial demo; logged in as <b>dawo</b>,
password <tt>$pw</tt>; <b>not for production</b> (passwords readable, no disk
encryption). Mijn Bureau is deployed automatically on the VM; this appliance
opens the dashboard in the browser once it is healthy.</small></p>" \
      >/dev/null 2>&1 || true
  '';
in
{
  systemd.services.dawo-appliance-set-password = {
    description = "Apply the install-time generated password for the dawo account (once)";
    wantedBy = [ "multi-user.target" ];
    # Run before anyone can log in.
    before = [ "display-manager.service" "getty.target" "sshd.service" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionPathExists = hashFile;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
    };
    path = [ pkgs.shadow pkgs.coreutils ];
    script = ''
      set -euo pipefail
      hash="$(tr -d '\n' < ${hashFile})"
      if [ -n "$hash" ]; then
        printf 'dawo:%s\n' "$hash" | chpasswd -e
        echo "dawo-appliance: applied the install-time password for user dawo"
      fi
      rm -f ${hashFile}
      # Demo: the plain-text copy (if the installer shipped one) stays readable
      # for the welcome dialog.
      if [ -e ${passwordFile} ]; then chmod 644 ${passwordFile}; fi
    '';
  };

  # The directory the installer drops the files into; the plain-text password
  # must be readable by the logged-in user's welcome dialog (demo!).
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 root root -"
  ];

  # Welcome dialog at Plasma login (every user; the appliance has one).
  environment.etc."xdg/autostart/dawo-appliance-welcome.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=DAWO appliance welcome
    Comment=Shows login details and the state of this demo appliance
    Exec=${welcome}
    OnlyShowIn=KDE;
    X-KDE-autostart-phase=2
  '';

  # Slice 7 (health/README.md). Same autostart phase as the welcome dialog
  # (X-KDE-autostart-phase only defines 0/1/2 in Plasma; there is no later
  # phase to move this to) — so phase alone does NOT guarantee the welcome
  # dialog runs first. In practice it reliably does anyway: the welcome
  # dialog is a near-instant kdialog box, while this opener's first visible
  # action is gated behind dawo-appliance-health --wait, which takes far
  # longer (Mijn Bureau's own deploy time) before it does anything the user
  # can see. Waits (bounded) for Mijn Bureau to become healthy, then opens the
  # dashboard; on timeout shows a kdialog with the checks that are still not
  # OK instead of opening a browser that would just error. Never
  # boot-tested (no NixOS assertion exercises this unit yet).
  environment.etc."xdg/autostart/dawo-appliance-open-dashboard.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=DAWO appliance: open Mijn Bureau
    Comment=Waits until Mijn Bureau is healthy, then opens the dashboard
    Exec=${openDashboard}/bin/dawo-appliance-open-dashboard
    OnlyShowIn=KDE;
    X-KDE-autostart-phase=2
  '';

  # Also on PATH for manual/debugging use (`dawo-appliance-health --once`),
  # like the guest-status helper in guest-vm.nix.
  environment.systemPackages = [ health openDashboard ];
}
