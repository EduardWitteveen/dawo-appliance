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

  # The command itself is launch/launch.sh; the package only points it at
  # the catalogue built above.
  cli = pkgs.writeShellApplication {
    name = "launch";
    runtimeInputs = with pkgs; [ jq coreutils gawk curl ];
    text = ''
      export LAUNCH_CATALOG="''${LAUNCH_CATALOG:-${json}}"
    '' + builtins.readFile ../launch/launch.sh;
  };

  check = pkgs.runCommand "environments-catalog"
    { nativeBuildInputs = [ pkgs.jq cli pkgs.gnugrep ]; }
    (if problems != [ ] then ''
      echo "The Launch catalogue has problems:" >&2
      ${lib.concatMapStrings (m: "echo ${lib.escapeShellArg "  - ${m}"} >&2\n") problems}
      exit 1
    '' else ''
            fail() { echo "FAIL: $*" >&2; exit 1; }
            jq -e '.schema == 1 and (.environments | length) >= 1' ${json} >/dev/null
            launch | grep -q '^mijn-bureau' || fail "listing"
            [ "$(launch --list --json | jq -r '.environments[0].id')" = mijn-bureau ] || fail "--list --json"
            if launch does-not-exist 2>/dev/null; then fail "an unknown environment must fail"; fi
            { launch does-not-exist 2>&1 || true; } | grep -q "onbekende omgeving" || fail "unknown message"

            # Preflight (#212), with a fake laptop: 32 GB, 100 GB free, KVM, internet.
            printf 'MemTotal:       32768000 kB
      ' > mem32; printf 'MemTotal:        8192000 kB
      ' > mem8
            touch kvm; echo ok > net
            export LAUNCH_MEMINFO=$PWD/mem32 LAUNCH_FREE_GIB=100 LAUNCH_KVM_DEVICE=$PWD/kvm LAUNCH_INTERNET_URL=file://$PWD/net
            launch --check mijn-bureau | grep -q "Alles in orde" || fail "check on a good laptop"
            [ "$(launch --check mijn-bureau --json | jq -r .ok)" = true ] || fail "check --json ok"
            # A good laptop: preflight passes, starting itself is not there yet (exit 2).
            rc=0; launch mijn-bureau </dev/null >out 2>&1 || rc=$?
            [ "$rc" = 2 ] || fail "start on a good laptop: exit $rc, want 2"

            # A small laptop: every shortfall is named, in Dutch.
            export LAUNCH_MEMINFO=$PWD/mem8 LAUNCH_FREE_GIB=4 LAUNCH_KVM_DEVICE=$PWD/no-kvm LAUNCH_INTERNET_URL=file://$PWD/no-net
            rc=0; launch --check mijn-bureau >out 2>&1 || rc=$?
            [ "$rc" = 3 ] || fail "check on a small laptop: exit $rc, want 3"
            grep -q "8 GB geheugen" out || fail "memory warning"; grep -q "nog 4 GB vrij" out || fail "disk warning"
            grep -q "virtualisatie" out || fail "kvm warning"; grep -q "geen internet" out || fail "internet warning"
            [ "$(launch --check mijn-bureau --json | jq '.problems | length')" = 4 ] || fail "check --json lists 4 problems"
            # Without a terminal and without --yes: not started (exit 3); with --yes: goes on (exit 2).
            rc=0; launch mijn-bureau </dev/null >out 2>&1 || rc=$?
            [ "$rc" = 3 ] && grep -q -- "--yes" out || fail "start without --yes: exit $rc"
            rc=0; launch mijn-bureau --yes </dev/null >out 2>&1 || rc=$?
            [ "$rc" = 2 ] || fail "start with --yes: exit $rc, want 2"
            # --status (#215): a catalogue whose health URL answers, and one that does not.
      jq --arg up "file://$PWD/net" '.environments[0].health.url = $up' ${json} > up.json
      LAUNCH_CATALOG=$PWD/up.json launch --status | grep -q "Mijn Bureau: klaar op file://" || fail "--status answering"
      [ "$(LAUNCH_CATALOG=$PWD/up.json launch --status --json | jq -r '.[0].answers')" = true ] || fail "--status --json answering"
      jq --arg down "file://$PWD/no-net" '.environments[0].health.url = $down' ${json} > down.json
      LAUNCH_CATALOG=$PWD/down.json launch --status | grep -q "Mijn Bureau: niet actief" || fail "--status not answering"
      cp ${json} $out
    '');
in
{ inherit catalog json check cli problems; }
