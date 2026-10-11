# Launch (ADR 0008): reads environments/catalog.toml and every
# environments/<id>/environment.toml with builtins.fromTOML, validates them,
# and provides
#   catalog  the merged catalogue as a Nix value
#   json     the same as a JSON file (what `launch` and the Launcher read)
#   check    a derivation that fails with a list of problems, if any
#   cli      the `launch` command (listing for now)
# Format: environments/README.md. Launch is meant to stand on its own later:
# nothing here is specific to one workplace; appliance details (domain, CA)
# are configuration.
#
# Experimental and unofficial. Not for production.
{ pkgs, lib, manifest }:

let
  envDir = ../environments;
  catalogToml = builtins.fromTOML (builtins.readFile (envDir + "/catalog.toml"));
  entries = catalogToml.environment or [ ];

  idOk = id: builtins.match "[a-z0-9]+(-[a-z0-9]+)*" id != null;
  isStr = v: builtins.isString v && v != "";
  hex40 = v: builtins.isString v && builtins.match "[0-9a-f]{40}" v != null;
  deployKinds = [ "driver" "helm" "helmfile" ];

  readEnv = e:
    let
      file = envDir + "/${e.path}/environment.toml";
      exists = builtins.pathExists file;
    in
    { inherit e exists; env = if exists then builtins.fromTOML (builtins.readFile file) else { }; };

  envs = map readEnv entries;

  # Problems of one environment, as strings prefixed with its path.
  envProblems = { e, exists, env }:
    let
      p = msg: "environments/${e.path or "?"}: ${msg}";
      needs = env.needs or { };
      source = env.source or { };
      deploy = env.deploy or { };
      fromManifest = source.manifest or null;
      pinned =
        if fromManifest == null then null
        else (manifest.upstream.${fromManifest} or { }).rev or null;
    in
    if !(isStr (e.id or null)) || !(isStr (e.path or null)) then [ "environments/catalog.toml: an entry lacks id or path" ]
    else if !exists then [ (p "no environment.toml") ]
    else
      lib.optional (!(idOk e.id)) (p "id '${e.id}' is not lowercase words joined by hyphens")
      ++ lib.optional ((env.schema or null) != 1) (p "schema must be 1")
      ++ lib.optional ((env.id or null) != e.id) (p "id in environment.toml differs from the catalogue ('${toString (env.id or "")}' vs '${e.id}')")
      ++ lib.concatMap (k: lib.optional (!(isStr (env.${k} or null))) (p "missing ${k}"))
        [ "title" "summary" "version" "url" "license" ]
      ++ lib.optional (!(builtins.isList (env.standards or null))) (p "standards must be a list")
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
      ++ lib.optional ((deploy.kind or null) == "driver" && !(builtins.pathExists (../. + "/${deploy.driver or "-"}")))
        (p "deploy.driver must name an existing file in this repository")
      ++ lib.optional (!(isStr ((env.health or { }).url or null))) (p "missing health.url");

  ids = map (e: e.id or "") entries;
  problems =
    lib.optional ((catalogToml.schema or null) != 1) "environments/catalog.toml: schema must be 1"
    ++ lib.optional (entries == [ ]) "environments/catalog.toml: no [[environment]] entries"
    ++ lib.optional (lib.length (lib.unique ids) != lib.length ids) "environments/catalog.toml: duplicate ids"
    ++ lib.concatMap envProblems envs;

  catalog = {
    schema = 1;
    environments = map ({ e, env, ... }: env // { path = "environments/${e.path}"; }) envs;
  };
  json = pkgs.writeText "launch-catalog.json" (builtins.toJSON catalog);

  cli = pkgs.writeShellApplication {
    name = "launch";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      catalog="''${LAUNCH_CATALOG:-${json}}"
      usage() {
        cat <<'EOF'
      Gebruik:
        launch                    de omgevingen die je kunt starten
        launch <omgeving>         een omgeving starten        (volgt, ADR 0008 fase B1)
        launch --stop <omgeving>  een omgeving stoppen        (volgt)
        launch --status           wat draait er en waar       (volgt)
        launch --list [--json]    de catalogus (--json: voor de Launcher)
      EOF
      }
      list() {
        if [ "''${1:-}" = "--json" ]; then
          jq . "$catalog"
        else
          jq -r '.environments[] | "\(.id)\t\(.title) \(.version)\n\t\(.summary)\n\t\(.url)"' "$catalog"
        fi
      }
      case "''${1:-}" in
        "" | --list) list "''${2:-}" ;;
        -h | --help) usage ;;
        --stop | --status)
          echo "launch $1: nog niet beschikbaar (ADR 0008, fase B1)." >&2
          exit 2
          ;;
        -*) usage >&2; exit 1 ;;
        *)
          if ! jq -e --arg id "$1" '.environments[] | select(.id == $id)' "$catalog" >/dev/null; then
            echo "launch: onbekende omgeving '$1'. Kies uit:" >&2
            jq -r '.environments[].id' "$catalog" >&2
            exit 1
          fi
          echo "launch $1: starten is nog niet beschikbaar (ADR 0008, fase B1)." >&2
          exit 2
          ;;
      esac
    '';
  };

  check = pkgs.runCommand "environments-catalog"
    { nativeBuildInputs = [ pkgs.jq cli ]; }
    (if problems != [ ] then ''
      echo "The Launch catalogue has problems:" >&2
      ${lib.concatMapStrings (m: "echo ${lib.escapeShellArg "  - ${m}"} >&2\n") problems}
      exit 1
    '' else ''
      jq -e '.schema == 1 and (.environments | length) >= 1' ${json} >/dev/null
      launch | grep -q '^mijn-bureau'
      [ "$(launch --list --json | jq -r '.environments[0].id')" = mijn-bureau ]
      if launch mijn-bureau 2>/dev/null; then echo "starting should not work yet" >&2; exit 1; fi
      if launch does-not-exist 2>/dev/null; then echo "an unknown environment must fail" >&2; exit 1; fi
      { launch does-not-exist 2>&1 || true; } | grep -q "onbekende omgeving"
      cp ${json} $out
    '');
in
{ inherit catalog json check cli problems; }
