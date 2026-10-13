# Launch on the live USB (ADR 0008, #228): the Mijn Bureau environment is
# started and stopped by Launch (`launch mijn-bureau`, `launch --stop
# mijn-bureau`) instead of being wanted at boot. Until the Launcher window
# (phase B2) exists it is still marked to start at boot, so nothing changes
# for the user yet.
#
# Experimental and unofficial. Not for production.
{ ... }:

{
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
    autostart = [ "mijn-bureau" ];
    # The Launcher window (B2), reachable from the menu; for now Mijn Bureau
    # still starts at boot and the status page stays what opens at login.
    launcher.enable = true;
  };

  # The desktop user starts and stops environments without sudo (polkit).
  users.users.dawo.extraGroups = [ "launch" ];
}
