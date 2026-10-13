# Launch on the live USB (ADR 0008, #228, #229): a clean workplace boots, the
# Launcher opens at login and the user starts an environment (Mijn Bureau) from
# it; `launch mijn-bureau` / `launch --stop mijn-bureau` do the same in a
# terminal. Nothing starts at boot, unless the DAWO_LOGS stick carries
# launch-autostart.txt with environment ids (one per line), as the KVM tests
# do.
#
# Experimental and unofficial. Not for production.
{ pkgs, ... }:

{
  imports = [ ./live-launch-selftest.nix ];

  appliance.guest.onDemand = true;

  services.launch = {
    enable = true;
    # The guest disk grows in dawo-images/ on DAWO_LOGS (live-data.nix).
    dataPath = "/var/lib/dawo-appliance/images";
    reserveGiB = 6; # appliance.guest.hostReserveMiB
    environments.mijn-bureau.units = [
      "dawo-appliance-guest.service"
      "dawo-appliance-mijnbureau.service"
    ];
    # Written by the Mijn Bureau runner (live-mijnbureau.nix, #232).
    environments.mijn-bureau.progressFile = "/run/launch/progress/mijn-bureau.json";
    autostartFile = "/run/dawo-logs/launch-autostart.txt";
    launcher.enable = true;
  };

  # The desktop user starts and stops environments without sudo (polkit).
  users.users.dawo.extraGroups = [ "launch" ];

  # The stick (and launch-autostart.txt on it) is mounted by the data service.
  systemd.services.launch-autostart.after = [ "dawo-appliance-data.service" ];
  systemd.services.launch-autostart.wants = [ "dawo-appliance-data.service" ];

  # Nothing started at boot: say so where the status page, the welcome dialog
  # and the boot report look (they treat it like a skipped guest). The guest
  # unit removes the note when it starts.
  systemd.services.dawo-appliance-launch-note = {
    description = "Note that no environment was started at boot (choose one in the Launcher)";
    wantedBy = [ "multi-user.target" ];
    after = [ "launch-autostart.service" "dawo-appliance-data.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      # launch-autostart starts with --no-block: a guest that was asked for
      # may still be a queued job here (state "inactive"); that counts too.
      state="$(${pkgs.systemd}/bin/systemctl is-active dawo-appliance-guest.service || true)"
      job="$(${pkgs.systemd}/bin/systemctl list-jobs --no-legend dawo-appliance-guest.service || true)"
      if [ "$state" != active ] && [ "$state" != activating ] && [ -z "$job" ] && [ ! -s /run/dawo-appliance/guest-skipped ]; then
        mkdir -p /run/dawo-appliance
        echo "Er is nog geen omgeving gestart: kies er een in de Launcher." > /run/dawo-appliance/guest-skipped
      fi
    '';
  };
}
