# The Tezza environment on the live USB (#261, ADR 0008): Contezza's own demo
# setup (tezza-packaging, the complete product) in the guest, deployed by
# apps/tezza/deploy.sh through the compose-environment runner
# (live-compose-environments.nix). Nothing of Tezza is in this image: it is
# downloaded from Contezza when the user starts it (after the Launcher's
# notice). The browser keeps upstream's addresses: the host forwards
# localhost:8082 (Tezza), :8084 (Admin Tools) and :8181 (Keycloak, which the
# browser reaches as http://identity:8181, upstream's README) to the guest.
#
# Experimental and unofficial. Not for production.
{ ... }:

let
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  up = manifest.upstream.tezza_packaging;
  swf = manifest.tezza.swf_catalogue;
  stateDir = "/var/lib/dawo-appliance-tezza";
in
{
  appliance.composeEnvironments.tezza = {
    title = "Tezza";
    driver = ../../apps/tezza/deploy.sh;
    inherit stateDir;
    files = {
      "override.yaml" = ../../environments/tezza/compose/override.yaml;
      # Súdwest-Fryslân's case types (#286).
      "swf-convert.py" = ../../apps/tezza/swf/convert.py;
      "swf-publish.py" = ../../apps/tezza/swf/publish.py;
    };
    env = {
      TZ_REPO = up.url; TZ_REV = up.rev; TZ_OVERRIDE = "${stateDir}/override.yaml"; TZ_STATE_DIR = stateDir;
      TZ_SWF_URL = swf.url; TZ_SWF_SHA = swf.sha256;
    };
    phases = [
      { name = "docker"; label = "Docker installeren"; typical = 40; }
      { name = "source"; label = "Tezza ophalen (de demo van Contezza)"; typical = 15; }
      { name = "pull"; label = "Onderdelen downloaden (ongeveer 8 GB)"; typical = 1500; }
      { name = "up"; label = "Tezza starten"; typical = 300; }
      { name = "ready"; label = "Wachten tot Tezza klaar is (de eerste keer wordt alles ingericht)"; typical = 600; }
      { name = "catalog"; label = "De zaaktypes van Súdwest-Fryslân laden"; typical = 180; }
      { name = "setup"; label = "Tezza inrichten (sites, groepen, sjablonen) en de login dawo"; typical = 120; }
    ];
    # Tezza, its Admin Tools, Keycloak and Open Zaak (#268).
    ports = [ 8082 8084 8181 8000 ];
    # Upstream's README: "127.0.0.1 identity" (the realm's issuer).
    # Tezza's case views ask Open Zaak by its compose alias (#268).
    hostNames = [ "identity" "openzaak.local" ];
    readyUrl = "http://localhost:8082/";
  };
}
