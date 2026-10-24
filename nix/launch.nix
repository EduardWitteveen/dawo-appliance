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
      ++ lib.optional (!(isStr ((env.health or { }).url or null))) (p "missing health.url")
      ++ lib.optional (!(builtins.isList (env.links or [ ])) || lib.any (l: !(isStr (l.title or null)) || !(isStr (l.url or null))) (env.links or [ ]))
        (p "links: each needs a title and a url")
      ++ lib.optional (env ? notice && (!(isStr (env.notice.title or null)) || !(isStr (env.notice.text or null))
           || !(builtins.isInt (env.notice.seconds or 60)) || !(builtins.elem (env.notice.level or "info") [ "info" "danger" ])))
        (p "notice: needs a title and a text; seconds an integer; level info or danger");

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

  # The Launcher (ADR 0008, B2): launch/launcher.py serving launch/launcher.html
  # on 127.0.0.1, running `launch` for the buttons.
  launcher = pkgs.writeShellApplication {
    name = "launcher";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${../launch/launcher.py} --page ${../launch/launcher.html} --launch ${cli}/bin/launch "$@"
    '';
  };

  # The Launcher answers on 127.0.0.1 and refuses actions without its token.
  launcherCheck = pkgs.runCommand "launcher"
    { nativeBuildInputs = [ launcher cli pkgs.curl pkgs.jq pkgs.gnugrep ]; }
    ''
            fail() { echo "FAIL: $*" >&2; kill "$pid" 2>/dev/null || true; exit 1; }
            printf 'MemTotal:       32768000 kB
      ' > mem32; touch kvm; echo ok > net
            export LAUNCH_MEMINFO=$PWD/mem32 LAUNCH_FREE_GIB=100 LAUNCH_KVM_DEVICE=$PWD/kvm LAUNCH_INTERNET_URL=file://$PWD/net LAUNCH_CONFIG=/dev/null
            launcher --port 18790 2> launcher.log & pid=$!
            for _ in $(seq 1 50); do curl -sf http://127.0.0.1:18790/ -o page.html && break; sleep 0.2; done
            grep -q "<title>Launcher</title>" page.html || fail "page"
            ! grep -q "__LAUNCHER_TOKEN__" page.html || fail "token placeholder left in the page"
            token="$(grep -o 'const TOKEN = "[0-9a-f]*"' page.html | grep -o '[0-9a-f]\{32\}')"
            [ -n "$token" ] || fail "no token in the page"
            curl -sf http://127.0.0.1:18790/api/environments > envs.json || fail "environments"
            [ "$(jq -r '.[0].id' envs.json)" = mijn-bureau ] || fail "environments list"
            [ "$(jq -r '.[0].state' envs.json)" = stopped ] || fail "state"
            code="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:18790/api/start/mijn-bureau)"
            [ "$code" = 403 ] || fail "start without the token answered $code, want 403"
            curl -s -X POST -H "X-Launcher-Token: $token" http://127.0.0.1:18790/api/start/mijn-bureau > start.json
            # No units on this machine: launch exits 2, the Launcher reports it.
            [ "$(jq -r '.code' start.json)" = 2 ] || fail "start through the Launcher: $(cat start.json)"
            kill "$pid"
            # The automatic start (#238): announced with its time, cancelled with the token.
            launcher --port 18791 --auto-start mijn-bureau --auto-start-delay 300 2>> launcher.log & pid=$!
            for _ in $(seq 1 50); do curl -sf http://127.0.0.1:18791/api/environments -o auto.json && break; sleep 0.2; done
            jq -e '.[0].autostart.at | type == "number"' auto.json >/dev/null || fail "no autostart.at: $(cat auto.json)"
            token="$(curl -sf http://127.0.0.1:18791/ | grep -o 'const TOKEN = "[0-9a-f]*"' | grep -o '[0-9a-f]\{32\}')"
            code="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:18791/api/autostart/cancel)"
            [ "$code" = 403 ] || fail "cancel without the token answered $code, want 403"
            curl -sf -X POST -H "X-Launcher-Token: $token" http://127.0.0.1:18791/api/autostart/cancel > /dev/null || fail "cancel"
            curl -sf http://127.0.0.1:18791/api/environments -o auto.json
            [ "$(jq -r '.[0].autostart' auto.json)" = null ] || fail "autostart still pending after cancel"
            kill "$pid"
            # A short delay fires: launch is run (and exits 2 here, no units).
            launcher --port 18792 --auto-start mijn-bureau --auto-start-delay 1 2>> launcher.log & pid=$!
            for _ in $(seq 1 60); do grep -q "automatic start of mijn-bureau: exit 2" launcher.log && break; sleep 0.5; done
            grep -q "automatic start of mijn-bureau: exit 2" launcher.log || { cat launcher.log >&2; fail "the automatic start did not run launch"; }
            kill "$pid"
            # The round (#251), short: it starts by itself when the marker file
            # exists, tries every environment in turn (none is set up here, so
            # each is skipped) and reports it.
            touch rondgang-marker
            launcher --port 18793 --cycle-file $PWD/rondgang-marker --cycle-hold 1 --cycle-gap 1 \
              --cycle-ready-timeout 3 --cycle-report $PWD/rondgang.log 2>> launcher.log & pid=$!
            for _ in $(seq 1 80); do grep -q "rondgang stopt" rondgang.log 2>/dev/null && break; sleep 0.5; done
            grep -q "ronde 1 mijn-bureau: overgeslagen" rondgang.log || { cat rondgang.log launcher.log >&2; fail "round: mijn-bureau not tried"; }
            grep -q "ronde 1 valtimo: overgeslagen" rondgang.log || { cat rondgang.log >&2; fail "round: valtimo not tried"; }
            curl -sf http://127.0.0.1:18793/api/cycle > cyc.json || fail "GET /api/cycle"
            [ "$(jq -r '.available' cyc.json)" = true ] && [ "$(jq -r '.persisted' cyc.json)" = true ] || fail "cycle state: $(cat cyc.json)"
            kill "$pid"
            # A marker file that names environments: only those go round.
            printf '# only this one\nvaltimo\n' > rondgang-marker
            launcher --port 18795 --cycle-file $PWD/rondgang-marker --cycle-hold 1 --cycle-gap 1 \
              --cycle-ready-timeout 3 --cycle-report $PWD/rondgang3.log 2>> launcher.log & pid=$!
            for _ in $(seq 1 60); do grep -q "rondgang stopt" rondgang3.log 2>/dev/null && break; sleep 0.5; done
            grep -q "ronde 1 valtimo: overgeslagen" rondgang3.log || { cat rondgang3.log >&2; fail "named round: valtimo not tried"; }
            ! grep -q "mijn-bureau" rondgang3.log || { cat rondgang3.log >&2; fail "named round tried mijn-bureau"; }
            kill "$pid"
            # Started from the page with a long pause, then stopped with the token.
            rm -f rondgang-marker
            launcher --port 18794 --cycle-file $PWD/rondgang-marker --cycle-gap 300 --cycle-report $PWD/rondgang2.log 2>> launcher.log & pid=$!
            for _ in $(seq 1 50); do curl -sf http://127.0.0.1:18794/ -o p2.html && break; sleep 0.2; done
            token="$(grep -o 'const TOKEN = "[0-9a-f]*"' p2.html | grep -o '[0-9a-f]\{32\}')"
            code="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:18794/api/cycle/start)"
            [ "$code" = 403 ] || fail "cycle start without the token answered $code"
            curl -sf -X POST -H "X-Launcher-Token: $token" http://127.0.0.1:18794/api/cycle/start > /dev/null || fail "cycle start"
            [ "$(curl -sf http://127.0.0.1:18794/api/cycle | jq -r .active)" = true ] || fail "cycle not active after start"
            curl -sf -X POST -H "X-Launcher-Token: $token" http://127.0.0.1:18794/api/cycle/stop > /dev/null || fail "cycle stop"
            for _ in $(seq 1 20); do [ "$(curl -sf http://127.0.0.1:18794/api/cycle | jq -r .active)" = false ] && break; sleep 0.3; done
            [ "$(curl -sf http://127.0.0.1:18794/api/cycle | jq -r .active)" = false ] || fail "cycle still active after stop"
            kill "$pid"
            # The round as the automatic start (#257): announced on /api/cycle,
            # not on a card; with a short delay it begins.
            launcher --port 18796 --auto-start-cycle --auto-start-delay 300 --cycle-file $PWD/no-marker 2>> launcher.log & pid=$!
            for _ in $(seq 1 50); do curl -sf http://127.0.0.1:18796/api/cycle -o ac.json && break; sleep 0.2; done
            jq -e '.autostart.at | type == "number"' ac.json >/dev/null || fail "round not announced as the automatic start: $(cat ac.json)"
            [ "$(curl -sf http://127.0.0.1:18796/api/environments | jq '[.[].autostart] | map(select(. != null)) | length')" = 0 ] || fail "a card announces an automatic start"
            kill "$pid"
            launcher --port 18797 --auto-start-cycle --auto-start-delay 1 --cycle-file $PWD/no-marker --cycle-gap 300 \
              --cycle-report $PWD/rondgang4.log 2>> launcher.log & pid=$!
            for _ in $(seq 1 40); do grep -q "gestart" rondgang4.log 2>/dev/null && break; sleep 0.5; done
            grep -q "gestart" rondgang4.log || { cat launcher.log >&2; fail "the automatic round did not begin"; }
            kill "$pid"
            # A fake launch: every environment is ready at once, start and stop
            # take two seconds.
            real="$(command -v launch)"
            LAUNCH_CATALOG_SRC="$(grep -o '/nix/store/[^"]*launch-catalog.json' "$real" | head -n1)"
            echo '[{"id":"mijn-bureau","state":"ready"},{"id":"valtimo","state":"ready"}]' > fake-status.json
            echo '{"ok":true,"problems":[]}' > fake-check.json
            {
              echo '#!/bin/sh'
              echo "echo \"\$*\" >> $PWD/fl.log"
              echo 'case "$1" in'
              echo "  --list) exec $real \"\$@\" ;;"
              echo "  --status) cat $PWD/fake-status.json ;;"
              echo "  --check) cat $PWD/fake-check.json ;;"
              echo '  *) sleep 2 ;;'
              echo 'esac'
            } > fake-launch
            chmod +x fake-launch
            : > fl.log
            touch marker5
            launcher --port 18798 --launch $PWD/fake-launch --cycle-file $PWD/marker5 --cycle-gap 1 --cycle-hold 300 \
              --cycle-report $PWD/rondgang5.log 2>> launcher.log & pid=$!
            for _ in $(seq 1 50); do curl -sf http://127.0.0.1:18798/ -o p5.html && break; sleep 0.2; done
            token="$(grep -o 'const TOKEN = "[0-9a-f]*"' p5.html | grep -o '[0-9a-f]\{32\}')"
            for _ in $(seq 1 60); do [ "$(curl -sf http://127.0.0.1:18798/api/cycle | jq -r .phase)" = up ] && break; sleep 0.5; done
            [ "$(curl -sf http://127.0.0.1:18798/api/cycle | jq -r .env)" = mijn-bureau ] || fail "round not up at mijn-bureau: $(curl -sf http://127.0.0.1:18798/api/cycle)"
            # Stop on the card the round is at; a second action meanwhile waits (409).
            curl -s -X POST -H "X-Launcher-Token: $token" http://127.0.0.1:18798/api/stop/mijn-bureau > stop1.json & spid=$!
            sleep 0.7
            code="$(curl -s -o busy.json -w '%{http_code}' -X POST -H "X-Launcher-Token: $token" http://127.0.0.1:18798/api/stop/mijn-bureau)"
            [ "$code" = 409 ] || fail "a second action while one runs answered $code, want 409: $(cat busy.json)"
            wait "$spid" || true
            for _ in $(seq 1 40); do grep -q "valtimo --yes" fl.log && break; sleep 0.5; done
            grep -q "ronde 1 mijn-bureau: klaar na .*door de gebruiker gestopt, door naar de volgende" rondgang5.log \
              || { cat rondgang5.log >&2; fail "a Stop on the round's card did not move the round on"; }
            grep -q "valtimo --yes" fl.log || { cat fl.log rondgang5.log >&2; fail "the round did not go on with valtimo"; }
            [ "$(curl -sf http://127.0.0.1:18798/api/cycle | jq -r .active)" = true ] || fail "the round ended on a card's Stop"
            # The notice before a start (#261): shown, cancelled, then started after its seconds.
            jq '(.environments[] | select(.id == "valtimo")) += {notice: {title: "Licentie onduidelijk", text: "Voorwaarden", seconds: 2, level: "danger"}}' \
              "$LAUNCH_CATALOG_SRC" > notice.json
            : > fl.log
            LAUNCH_CATALOG=$PWD/notice.json launcher --port 18799 --launch $PWD/fake-launch 2>> launcher.log & npid=$!
            for _ in $(seq 1 50); do curl -sf http://127.0.0.1:18799/ -o p6.html && break; sleep 0.2; done
            ntoken="$(grep -o 'const TOKEN = "[0-9a-f]*"' p6.html | grep -o '[0-9a-f]\{32\}')"
            curl -sf -X POST -H "X-Launcher-Token: $ntoken" http://127.0.0.1:18799/api/start/valtimo > n1.json
            [ "$(jq -r .pending n1.json)" = true ] || fail "a start with a notice is not pending: $(cat n1.json)"
            curl -sf http://127.0.0.1:18799/api/environments > n2.json
            jq -e '.[] | select(.id == "valtimo") | (.pending.at | type == "number") and .notice.level == "danger"' n2.json >/dev/null \
              || fail "the card does not show the pending notice: $(cat n2.json)"
            curl -sf -X POST -H "X-Launcher-Token: $ntoken" http://127.0.0.1:18799/api/cancel/valtimo > /dev/null
            sleep 3
            ! grep -q "^valtimo --yes" fl.log || fail "started although 'Niet starten' was chosen"
            curl -sf -X POST -H "X-Launcher-Token: $ntoken" http://127.0.0.1:18799/api/start/valtimo > /dev/null
            for _ in $(seq 1 20); do grep -q "^valtimo --yes" fl.log && break; sleep 0.5; done
            grep -q "^valtimo --yes" fl.log || fail "not started after its notice: $(cat fl.log)"
            kill "$npid"
            # Starting an environment: the user takes over, the round ends.
            curl -s -X POST -H "X-Launcher-Token: $token" http://127.0.0.1:18798/api/start/mijn-bureau > /dev/null
            for _ in $(seq 1 30); do [ "$(curl -sf http://127.0.0.1:18798/api/cycle | jq -r .active)" = false ] && break; sleep 0.5; done
            [ "$(curl -sf http://127.0.0.1:18798/api/cycle | jq -r .active)" = false ] || fail "the round goes on after a Start"
            kill "$pid"
            touch $out
    '';

  check = pkgs.runCommand "environments-catalog"
    { nativeBuildInputs = [ pkgs.jq cli pkgs.gnugrep ]; }
    (if problems != [ ] then ''
      echo "The Launch catalogue has problems:" >&2
      ${lib.concatMapStrings (m: "echo ${lib.escapeShellArg "  - ${m}"} >&2\n") problems}
      exit 1
    '' else ''
                  fail() { echo "FAIL: $*" >&2; exit 1; }
                  jq -e '.schema == 1 and (.environments | length) >= 1' ${json} >/dev/null
                  launch > ls.txt; grep -q '^mijn-bureau' ls.txt || fail "listing"; grep -q '^valtimo' ls.txt || fail "listing valtimo"; grep -q '^nextcloud-commonground' ls.txt || fail "listing nextcloud-commonground"
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
            LAUNCH_CATALOG=$PWD/up.json launch --status > st.txt; grep -q "Mijn Bureau: klaar op file://" st.txt || fail "--status answering"
            [ "$(LAUNCH_CATALOG=$PWD/up.json launch --status --json | jq -r '.[0].answers')" = true ] || fail "--status --json answering"
            jq --arg down "file://$PWD/no-net" '.environments[0].health.url = $down' ${json} > down.json
            LAUNCH_CATALOG=$PWD/down.json launch --status > st.txt; grep -q "Mijn Bureau: niet actief" st.txt || fail "--status not answering"
            # Start and stop through the bound units (#228), with a fake systemctl.
            printf '%s\n' '#!/bin/sh' 'echo "$*" >> "$FAKE_LOG"' \
              '[ "$1" = is-active ] && [ -e "$FAKE_ACTIVE" ] && exit 0' \
              '[ "$1" = is-active ] && exit 3' \
              '[ "$1" = is-failed ] && [ -e "$FAKE_FAILED" ] && exit 0' \
              '[ "$1" = is-failed ] && exit 1' 'exit 0' > fake-systemctl
            chmod +x fake-systemctl
            echo '{"dataPath":"/tmp","reserveGiB":6,"environments":{"mijn-bureau":{"units":["guest.service","deploy.service"]}}}' > config.json
            export LAUNCH_SYSTEMCTL=$PWD/fake-systemctl LAUNCH_CONFIG=$PWD/config.json FAKE_LOG=$PWD/sc.log FAKE_ACTIVE=$PWD/active FAKE_FAILED=$PWD/failed
            export LAUNCH_MEMINFO=$PWD/mem32 LAUNCH_FREE_GIB=100 LAUNCH_KVM_DEVICE=$PWD/kvm LAUNCH_INTERNET_URL=file://$PWD/net
            launch mijn-bureau </dev/null > out || fail "start exit"; grep -q "wordt gestart" out || fail "start message"
            grep -qx "start --no-block guest.service deploy.service" sc.log || fail "start runs the units in order"
            : > sc.log; launch --stop mijn-bureau > out || fail "stop exit"; grep -q "is gestopt" out || fail "stop message"
            [ "$(cat sc.log)" = "$(printf 'stop deploy.service
      stop guest.service')" ] || fail "stop in reverse order"
            touch active
            LAUNCH_CATALOG=$PWD/down.json launch --status > out; grep -q "Mijn Bureau: wordt gestart" out || fail "--status starting"
            # Progress while starting (#232), from the environment's progressFile.
            echo '{"step":11,"steps":17,"label":"Vertrouwen instellen","started":1,"since":1,"expected":420}' > progress.json
            jq --arg f "$PWD/progress.json" '.environments["mijn-bureau"].progressFile = $f' config.json > config2.json
            LAUNCH_CONFIG=$PWD/config2.json LAUNCH_CATALOG=$PWD/down.json launch --status > out
            grep -q "wordt gestart, stap 11 van 17: Vertrouwen instellen" out || fail "--status shows the progress"
            LAUNCH_CONFIG=$PWD/config2.json LAUNCH_CATALOG=$PWD/down.json launch --status --json > out.json
            [ "$(jq -r '.[0].progress.step' out.json)" = 11 ] || fail "--status --json has the progress"
            # Answering from an earlier run while it is set up again: not ready yet (#238).
            LAUNCH_CONFIG=$PWD/config2.json LAUNCH_CATALOG=$PWD/up.json launch --status --json > out.json
            [ "$(jq -r '.[0].state' out.json)" = starting ] || fail "answering but still reporting progress must be starting, not $(jq -r '.[0].state' out.json)"
            echo 'not json' > progress.json
            LAUNCH_CONFIG=$PWD/config2.json LAUNCH_CATALOG=$PWD/down.json launch --status --json > out.json || fail "--status with a broken progress file"
            [ "$(jq -r '.[0] | has("progress")' out.json)" = false ] || fail "a broken progress file is ignored"
            echo '{"step":3,"steps":17,"label":"x","started":1,"expected":45}' > progress.json
            rm -f active
            LAUNCH_CONFIG=$PWD/config2.json LAUNCH_CATALOG=$PWD/down.json launch --status --json > out.json
            [ "$(jq -r '.[0] | has("progress")' out.json)" = false ] || fail "no progress when the environment is stopped"
            # A failed start (#282): failed, not "Klaar", even when its URL
            # answers; the progress file's error comes along.
            echo '{"step":6,"steps":9,"label":"Starten","started":1,"expected":60,"error":"Deze stap is drie keer mislukt."}' > progress.json
            touch failed
            LAUNCH_CONFIG=$PWD/config2.json LAUNCH_CATALOG=$PWD/up.json launch --status --json > out.json
            [ "$(jq -r '.[0].state' out.json)" = failed ] || fail "a failed unit whose URL answers must be failed, not $(jq -r '.[0].state' out.json)"
            [ "$(jq -r '.[0].progress.error' out.json)" = "Deze stap is drie keer mislukt." ] || fail "failed: the progress error"
            LAUNCH_CONFIG=$PWD/config2.json LAUNCH_CATALOG=$PWD/up.json launch --status > out
            grep -q "Mijn Bureau: starten mislukt: Deze stap is drie keer mislukt." out || fail "--status says the start failed: $(cat out)"
            touch active
            LAUNCH_CONFIG=$PWD/config2.json LAUNCH_CATALOG=$PWD/down.json launch --status --json > out.json
            [ "$(jq -r '.[0].state' out.json)" = starting ] || fail "started again (active) is starting, not failed"
            rm -f active failed
            # One environment at a time (#246): Mijn Bureau runs (its own unit is
            # active), Valtimo starts: Mijn Bureau stops first, all its units.
            mkdir -p up.d && touch up.d/guest.service up.d/deploy.service
            printf '%s\n' '#!/bin/sh' 'echo "$*" >> "$FAKE_LOG"' \
              '[ "$1" = is-active ] && { u="$3"; [ -z "$u" ] && u="$2"; [ -e "$FAKE_UP/$u" ] && exit 0; exit 3; }' \
              '[ "$1" = is-failed ] && exit 1' 'exit 0' > fake2
            chmod +x fake2
            echo '{"dataPath":"/tmp","reserveGiB":6,"environments":{"mijn-bureau":{"units":["guest.service","deploy.service"]},"valtimo":{"units":["guest.service","vt.service"]}}}' > config3.json
            : > sc.log
            LAUNCH_SYSTEMCTL=$PWD/fake2 FAKE_UP=$PWD/up.d LAUNCH_CONFIG=$PWD/config3.json launch valtimo </dev/null > out || fail "start valtimo: $(cat out)"
            grep -q "Eerst stoppen: de Mijn Bureau-omgeving" out || fail "no 'Eerst stoppen' message: $(cat out)"
            grep -n "stop deploy.service" sc.log > /dev/null || fail "Mijn Bureau's unit not stopped: $(cat sc.log)"
            last_stop=$(grep -n '^stop guest.service' sc.log | tail -n1 | cut -d: -f1); first_start=$(grep -n '^start --no-block' sc.log | head -n1 | cut -d: -f1)
            [ -n "$last_stop" ] && [ -n "$first_start" ] && [ "$last_stop" -lt "$first_start" ] || fail "stop before start: $(cat sc.log)"
            # It starts Valtimo's units, not those of the one it stopped (#282).
            [ "$(grep '^start --no-block' sc.log | tail -n1)" = "start --no-block guest.service vt.service" ] \
              || fail "starts the wrong environment after stopping the other: $(cat sc.log)"
            # Nothing else runs (only the shared guest): no stop.
            rm -f up.d/deploy.service; : > sc.log
            LAUNCH_SYSTEMCTL=$PWD/fake2 FAKE_UP=$PWD/up.d LAUNCH_CONFIG=$PWD/config3.json launch valtimo </dev/null > out || fail "start valtimo 2"
            ! grep -q "^stop " sc.log || fail "stopped although only the shared guest was active: $(cat sc.log)"
            # The state is judged by the environment's own units (#257): with
            # only the shared guest active, no card is "starting".
            jq '.environments |= [.[0], (.[0] | .id = "valtimo" | .title = "Valtimo")]' down.json > two.json
            LAUNCH_SYSTEMCTL=$PWD/fake2 FAKE_UP=$PWD/up.d LAUNCH_CONFIG=$PWD/config3.json LAUNCH_CATALOG=$PWD/two.json launch --status --json > out.json
            [ "$(jq -r '[.[].state] | join(",")' out.json)" = "stopped,stopped" ] || fail "shared guest only: $(cat out.json)"
            touch up.d/vt.service
            LAUNCH_SYSTEMCTL=$PWD/fake2 FAKE_UP=$PWD/up.d LAUNCH_CONFIG=$PWD/config3.json LAUNCH_CATALOG=$PWD/two.json launch --status --json > out.json
            [ "$(jq -r '[.[].state] | join(",")' out.json)" = "stopped,starting" ] || fail "only Valtimo's own unit: $(cat out.json)"
            rm -f up.d/vt.service
            cp ${json} $out
    '');
in
{ inherit catalog json check cli problems launcher launcherCheck; }
