# The Nextcloud Common Ground environment on the live USB (#250, ADR 0008):
# Conduction's own local demo (dossiq-compose.yaml from ConductionNL/dossiq)
# in the guest, deployed by apps/nextcloud-commonground/deploy.sh through the
# compose-environment runner (live-compose-environments.nix). The browser
# keeps upstream's address: while this environment runs, the host forwards
# localhost:8609 to the guest, so the trusted domains and OVERWRITECLIURL stay
# as upstream ships them.
#
# Experimental and unofficial. Not for production.
{ pkgs, lib, ... }:

let
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  up = manifest.upstream.dossiq_compose;
  env = manifest.nextcloud_commonground;
  stateDir = "/var/lib/dawo-appliance-nextcloud-commonground";
in
{
  appliance.composeEnvironments.nextcloud-commonground = {
    title = "Nextcloud Common Ground";
    driver = ../../apps/nextcloud-commonground/deploy.sh;
    inherit stateDir;
    files = {
      "override.yaml" = ../../environments/nextcloud-commonground/compose/override.yaml;
      # The app pins for the driver: "<id> <version> <url> <sha256>" per line.
      "apps.txt" = pkgs.writeText "nextcloud-commonground-apps.txt"
        (lib.concatStrings (lib.mapAttrsToList (id: a: "${id} ${a.version} ${a.url} ${a.sha256}\n") env.apps));
    };
    env = {
      NC_COMPOSE_URL = up.raw_url; NC_COMPOSE_SHA = up.sha256; NC_STATE_DIR = stateDir;
      NC_OVERRIDE = "${stateDir}/override.yaml"; NC_APPS_FILE = "${stateDir}/apps.txt";
    };
    phases = [
      { name = "docker"; label = "Docker installeren"; typical = 40; }
      { name = "source"; label = "Nextcloud Common Ground ophalen (de demo van Conduction)"; typical = 5; }
      { name = "pull"; label = "Onderdelen downloaden"; typical = 120; }
      { name = "apps"; label = "De apps van Conduction downloaden en controleren"; typical = 200; }
      { name = "up"; label = "Nextcloud starten"; typical = 25; }
      { name = "ready"; label = "Wachten tot Nextcloud klaar is (de eerste keer wordt het geïnstalleerd)"; typical = 340; }
      { name = "enable"; label = "De apps aanzetten"; typical = 200; }
      { name = "seed"; label = "Demozaken en voorbeeldgegevens laden, instellingen klaarzetten"; typical = 180; }
    ];
    ports = [ env.compose.port ];
    readyUrl = "http://localhost:${toString env.compose.port}/apps/dossiq/";
  };
}
