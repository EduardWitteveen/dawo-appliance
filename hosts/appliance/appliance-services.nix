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
#    place a user is told what to type. Slice 7 opens the Mijn Bureau
#    dashboard from the same hook.
{ pkgs, ... }:

let
  stateDir = "/var/lib/dawo-appliance";
  hashFile = "${stateDir}/dawo.password-hash";
  passwordFile = "${stateDir}/dawo.password.txt";

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
<p>Mijn Bureau (browser) volgt in een latere versie van deze appliance.</p>
<p><b>Niet voor productie.</b> Wachtwoorden staan leesbaar op deze machine en op
het scherm; er is geen schijfversleuteling. Alleen voor demonstratie en
evaluatie.</p>
<hr/>
<p><small>English: experimental, unofficial demo; logged in as <b>dawo</b>,
password <tt>$pw</tt>; <b>not for production</b> (passwords readable, no disk
encryption). Mijn Bureau follows in a later version.</small></p>" \
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
}
