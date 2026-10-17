# The Valtimo environment on the live USB (#246, ADR 0008): upstream's
# official GZAC demo (gzac-docker-compose, profiles demo, zgw and
# openformulieren, #260) in the guest, deployed by apps/valtimo/deploy.sh
# through the compose-environment runner (live-compose-environments.nix).
# The browser keeps upstream's addresses: while this environment runs, the
# host forwards localhost:80, :8080, :8081 (and the ZGW services and Open
# Formulieren: :8001, :8002, :8003, :8010, :8011) to the guest, so the realm,
# the redirect URIs and the frontend settings stay as upstream ships them.
#
# Experimental and unofficial. Not for production.
{ ... }:

let
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  up = manifest.upstream.gzac_docker_compose;
  stateDir = "/var/lib/dawo-appliance-valtimo";
in
{
  appliance.composeEnvironments.valtimo = {
    title = "Valtimo";
    driver = ../../apps/valtimo/deploy.sh;
    inherit stateDir;
    files."override.yaml" = ../../environments/valtimo/compose/override.yaml;
    env = { VT_REPO = up.url; VT_REV = up.rev; VT_OVERRIDE = "${stateDir}/override.yaml"; VT_STATE_DIR = stateDir; };
    phases = [
      { name = "docker"; label = "Docker installeren"; typical = 40; }
      { name = "source"; label = "Valtimo ophalen (de officiële demo)"; typical = 10; }
      { name = "pull"; label = "Onderdelen downloaden"; typical = 480; }
      { name = "up"; label = "Valtimo starten"; typical = 240; }
      { name = "ready"; label = "Wachten tot Valtimo, Open Zaak en het burgerformulier klaar zijn"; typical = 420; }
    ];
    # Valtimo, its backend and Keycloak; Open Zaak, Open Notificaties, Open
    # Formulieren (the citizen form), Objecten and Objecttypen (#260).
    ports = [ 80 8080 8081 8001 8002 8003 8010 8011 ];
    readyUrl = "http://localhost/";
  };
}
