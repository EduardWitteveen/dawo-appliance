# The DAWO app catalogue (ADR 0008): reads apps/catalog.toml and every
# apps/<id>/app.toml with builtins.fromTOML, validates them, and provides
#   catalog  the merged catalogue as a Nix value
#   json     the same as a JSON file (what dawo-app and the GUI read)
#   check    a derivation that fails with a list of problems, if any
#   cli      the `dawo-app` command (list for now)
# Format: apps/README.md.
#
# Experimental and unofficial. Not for production.
{ pkgs, lib, manifest }:

let
  appsDir = ../apps;
  catalogFile = appsDir + "/catalog.toml";
  catalogToml = builtins.fromTOML (builtins.readFile catalogFile);
  entries = catalogToml.app or [ ];

  idOk = id: builtins.match "[a-z0-9]+(-[a-z0-9]+)*" id != null;
  isStr = v: builtins.isString v && v != "";
  hex40 = v: builtins.isString v && builtins.match "[0-9a-f]{40}" v != null;
  deployKinds = [ "driver" "helm" "helmfile" ];

  readApp = e:
    let
      file = appsDir + "/${e.path}/app.toml";
      exists = builtins.pathExists file;
    in
    { inherit e exists; app = if exists then builtins.fromTOML (builtins.readFile file) else { }; };

  apps = map readApp entries;

  # Problems of one app, as strings prefixed with its id.
  appProblems = { e, exists, app }:
    let
      p = msg: "apps/${e.path or "?"}: ${msg}";
      needs = app.needs or { };
      source = app.source or { };
      deploy = app.deploy or { };
      fromManifest = source.manifest or null;
      pinned =
        if fromManifest == null then null
        else (manifest.upstream.${fromManifest} or { }).rev or null;
    in
    if !(isStr (e.id or null)) || !(isStr (e.path or null)) then [ "apps/catalog.toml: an entry lacks id or path" ]
    else if !exists then [ (p "no app.toml") ]
    else
      lib.optional (!(idOk e.id)) (p "id '${e.id}' is not lowercase words joined by hyphens")
      ++ lib.optional ((app.schema or null) != 1) (p "schema must be 1")
      ++ lib.optional ((app.id or null) != e.id) (p "id in app.toml differs from the catalogue ('${toString (app.id or "")}' vs '${e.id}')")
      ++ lib.concatMap (k: lib.optional (!(isStr (app.${k} or null))) (p "missing ${k}"))
        [ "title" "summary" "version" "url" "license" ]
      ++ lib.optional (!(builtins.isList (app.standards or null))) (p "standards must be a list")
      ++ lib.concatMap (k: lib.optional (!(builtins.isInt (needs.${k} or null)) || needs.${k} <= 0) (p "needs.${k} must be a positive integer"))
        [ "memory_gib" "cpus" "disk_gib" ]
      ++ lib.concatMap (k: lib.optional (!(builtins.isBool (needs.${k} or null))) (p "needs.${k} must be true or false"))
        [ "kvm" "internet" ]
      ++ lib.optional (!(isStr (source.repo or null))) (p "missing source.repo")
      ++ lib.optional (!(hex40 (source.rev or null))) (p "source.rev must be a full 40-character commit (AGENTS rule 4)")
      ++ lib.optional (fromManifest != null && pinned != source.rev)
        (p "source.rev differs from manifest upstream.${fromManifest}.rev (${toString pinned})")
      ++ lib.optional (!(builtins.elem (deploy.kind or null) deployKinds))
        (p "deploy.kind must be one of ${lib.concatStringsSep ", " deployKinds}")
      ++ lib.optional (!(isStr ((app.health or { }).url or null))) (p "missing health.url");

  ids = map (e: e.id or "") entries;
  problems =
    lib.optional ((catalogToml.schema or null) != 1) "apps/catalog.toml: schema must be 1"
    ++ lib.optional (entries == [ ]) "apps/catalog.toml: no [[app]] entries"
    ++ lib.optional (lib.length (lib.unique ids) != lib.length ids) "apps/catalog.toml: duplicate ids"
    ++ lib.concatMap appProblems apps;

  catalog = {
    schema = 1;
    apps = map ({ e, app, ... }: app // { path = "apps/${e.path}"; }) apps;
  };
  json = pkgs.writeText "dawo-apps.json" (builtins.toJSON catalog);

  cli = pkgs.writeShellApplication {
    name = "dawo-app";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      catalog="''${DAWO_APPS_CATALOG:-${json}}"
      usage() {
        cat <<'EOF'
      Gebruik: dawo-app <opdracht>

        list [--json]   de apps in de catalogus
        start <app>     een app starten          (volgt, ADR 0008 fase B1)
        stop <app>      een app stoppen          (volgt)
        status [--json] wat draait en waar       (volgt)
      EOF
      }
      case "''${1:-}" in
        list)
          if [ "''${2:-}" = "--json" ]; then
            jq . "$catalog"
          else
            jq -r '.apps[] | "\(.id)\t\(.title) \(.version)\n\t\(.summary)\n\t\(.url)"' "$catalog"
          fi
          ;;
        start | stop | status)
          echo "dawo-app $1: nog niet beschikbaar (ADR 0008, fase B1)." >&2
          exit 2
          ;;
        "" | -h | --help | help) usage ;;
        *) usage >&2; exit 1 ;;
      esac
    '';
  };

  check = pkgs.runCommand "apps-catalog"
    { nativeBuildInputs = [ pkgs.jq cli ]; }
    (if problems != [ ] then ''
      echo "The DAWO app catalogue has problems:" >&2
      ${lib.concatMapStrings (m: "echo ${lib.escapeShellArg "  - ${m}"} >&2\n") problems}
      exit 1
    '' else ''
      jq -e '.schema == 1 and (.apps | length) >= 1' ${json} >/dev/null
      dawo-app list | grep -q '^mijn-bureau'
      [ "$(dawo-app list --json | jq -r '.apps[0].id')" = mijn-bureau ]
      if dawo-app start mijn-bureau 2>/dev/null; then echo "start should not work yet" >&2; exit 1; fi
      cp ${json} $out
    '');
in
{ inherit catalog json check cli problems; }
