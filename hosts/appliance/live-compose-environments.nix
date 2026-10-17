# Compose environments on the live USB (ADR 0008; #246 Valtimo, #250 Nextcloud
# Common Ground, #261 Tezza): an upstream demo setup that runs with Docker
# compose in the guest, deployed by its driver (apps/<id>/deploy.sh) phase by
# phase, with progress for the Launcher (#232/#235). One runner for all of
# them; each environment only declares its data:
#
#   appliance.composeEnvironments.<id> = {
#     title = "Valtimo";                    # in the log and the messages
#     driver = ../../apps/valtimo/deploy.sh;
#     files = { "override.yaml" = ...; };   # copied to <stateDir>/<name> in the guest
#     env = { VT_REV = "..."; ... };        # the driver's inputs
#     phases = [ { name = "docker"; label = "Docker installeren"; typical = 40; } ... ];
#     ports = [ 80 8080 ];                  # localhost:<port> forwarded to the guest
#     hostNames = [ ];                      # names the browser needs on 127.0.0.1
#     readyUrl = "http://localhost/";
#   };
#
# Before the driver's phases the runner waits for the guest (step "vm"), runs
# the driver's "park" phase (one environment at a time) and waits for
# internet. Each phase gets three attempts. While the environment runs, the
# host forwards its ports (systemd-socket-proxyd), so the browser keeps
# upstream's addresses; the forwards stop with it. Launch learns the units
# and the progress file from here (services.launch.environments.<id>).
#
# Experimental and unofficial. Not for production.
{ config, pkgs, lib, ... }:

let
  cfg = config.appliance.composeEnvironments;
  guestIp = "192.168.150.10";
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  # One Docker Engine for every compose environment (D43).
  tools = manifest.valtimo.tooling;

  phaseType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; description = "The driver's phase (deploy.sh --phase NAME)."; };
      label = lib.mkOption { type = lib.types.str; description = "What the Launcher shows (Dutch)."; };
      typical = lib.mkOption { type = lib.types.ints.positive; default = 30; description = "Seconds it takes, until a run has measured it."; };
    };
  };

  envType = lib.types.submodule ({ name, ... }: {
    options = {
      title = lib.mkOption { type = lib.types.str; };
      driver = lib.mkOption { type = lib.types.path; };
      files = lib.mkOption { type = lib.types.attrsOf lib.types.path; default = { }; };
      env = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = { }; };
      phases = lib.mkOption { type = lib.types.listOf phaseType; };
      ports = lib.mkOption { type = lib.types.listOf lib.types.port; default = [ ]; };
      hostNames = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
      readyUrl = lib.mkOption { type = lib.types.str; };
      stateDir = lib.mkOption { type = lib.types.str; default = "/var/lib/dawo-appliance-${name}"; };
    };
  });

  mk = id: e:
    let
      unit = "dawo-appliance-${id}";
      logFile = "/var/log/${unit}.log";
      progressFile = "/run/launch/progress/${id}.json";
      q = lib.escapeShellArg;
      allPhases = [
        { name = "vm"; label = "Virtuele machine starten"; typical = 120; }
        { name = "park"; label = "Andere omgevingen even stilzetten (er draait er één tegelijk)"; typical = 15; }
        { name = "net"; label = "Wachten op internet (wifi Dawo of een netwerkkabel)"; typical = 5; }
      ] ++ e.phases;
      driverEnv = e.env // {
        DOCKER_URL = tools.docker.url; DOCKER_SHA = tools.docker.sha256;
        COMPOSE_URL = tools.compose.url; COMPOSE_SHA = tools.compose.sha256;
      };
      runner = pkgs.writeShellApplication {
        name = unit;
        runtimeInputs = with pkgs; [ coreutils gnugrep gnused gawk jq openssh curl ];
        text = ''
          key=/var/lib/dawo-appliance/ssh/id_ed25519
          ssh_opts=(-i "$key" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30
                    -o ServerAliveCountMax=10 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)
          # The command line is meant to expand here, on the host (SC2029).
          # shellcheck disable=SC2029
          g() { ssh "''${ssh_opts[@]}" ops@${guestIp} "$@"; }
          up() { cut -d' ' -f1 /proc/uptime | cut -d. -f1; }
          log() { echo "$(date -u +%FT%TZ) t=$(up)s $*" | tee -a ${logFile}; }

          # Progress for the Launcher (#232, #235): the same JSON as Mijn Bureau's.
          names=(${lib.concatMapStringsSep " " (p: q p.name) allPhases})
          labels=(${lib.concatMapStringsSep " " (p: q p.label) allPhases})
          typicals=(${lib.concatMapStringsSep " " (p: toString p.typical) allPhases})
          steps=''${#names[@]}
          since="$(date +%s)"
          durations=/var/lib/dawo-appliance/${id}-durations
          last_secs() { awk -v k="$1" '$1 == k { s = $2 } END { if (s != "") print s }' "$durations" 2>/dev/null || true; }
          key_exp() { local e; e="$(last_secs "''${names[$1]}")"; echo "''${e:-''${typicals[$1]}}"; }
          rest_after() { local t=0 i; for i in $(seq "$1" $((steps - 1))); do t=$((t + $(key_exp "$i"))); done; echo "$t"; }
          activity() {
            tail -n 30 ${logFile} 2>/dev/null | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n 1 | cut -c1-200 \
              | sed -E -e 's/^[0-9T:Z-]+ t=[0-9]+s //' -e 's/^(==>|    )//' || true
          }
          refresh_progress() {
            local tmp
            [ -s ${progressFile}.base ] || return 0
            tmp="$(mktemp ${progressFile}.XXXXXX)" || return 0
            if jq --arg detail "$(activity)" --argjson activity "$(stat -c %Y ${logFile} 2>/dev/null || date +%s)" \
                 '. + {detail: $detail, activity: $activity}' ${progressFile}.base > "$tmp" 2>/dev/null; then
              chmod 0644 "$tmp"; mv -f "$tmp" ${progressFile}
            else
              rm -f "$tmp"
            fi
          }
          progress() { # progress INDEX [ERROR]  (INDEX 0-based into names)
            mkdir -p "$(dirname ${progressFile})"
            jq -n --argjson step $(($1 + 1)) --argjson steps "$steps" --arg label "''${labels[$1]}" \
              --argjson started "$(date +%s)" --argjson since "$since" --argjson expected "$(key_exp "$1")" \
              --argjson rest "$(rest_after $(($1 + 1)))" --arg error "''${2:-}" \
              '{step: $step, steps: $steps, label: $label, started: $started, since: $since, expected: $expected, rest: $rest}
               + (if $error == "" then {} else {error: $error} end)' \
              > ${progressFile}.base.new && mv -f ${progressFile}.base.new ${progressFile}.base
            refresh_progress
          }
          ( while sleep 5; do refresh_progress; done ) &
          refresher=$!
          trap 'kill "$refresher" 2>/dev/null || true' EXIT

          denv=(${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: q "${k}=${v}") driverEnv)})
          phase() { # phase INDEX: run the driver's phase, three attempts
            local i="$1" name="''${names[$1]}" t0 attempt
            progress "$i"
            for attempt in 1 2 3; do
              t0=$SECONDS
              log "phase $name: attempt $attempt"
              if g sudo env "''${denv[@]}" /usr/local/sbin/${id}-deploy --phase "$name" >> ${logFile} 2>&1; then
                log "phase $name: ok after $((SECONDS - t0))s"
                echo "$name $((SECONDS - t0))" >> "$durations" || true
                return 0
              fi
              log "phase $name: FAILED after $((SECONDS - t0))s"
              sleep 20
            done
            progress "$i" "Deze stap is drie keer mislukt. De details staan in ${id}.txt op de USB-schijf."
            exit 1
          }

          # 1. The guest answers over SSH.
          progress 0
          t0="$(date +%s)"
          until g true 2>/dev/null; do
            if [ -s /run/dawo-appliance/guest-skipped ]; then
              progress 0 "De virtuele machine kon niet starten: $(cat /run/dawo-appliance/guest-skipped)"
              exit 0
            fi
            sleep 5
          done
          echo "vm $(( $(date +%s) - t0 ))" >> "$durations" || true
          log "guest answers"

          # The driver and its files into the guest (from this image).
          g "cat > /tmp/${id}-deploy.sh" < ${e.driver}
          g sudo install -m 0755 /tmp/${id}-deploy.sh /usr/local/sbin/${id}-deploy
          g sudo mkdir -p ${e.stateDir}
          ${lib.concatStrings (lib.mapAttrsToList (n: f: ''
            g "cat > /tmp/${id}-${n}" < ${f}
            g sudo install -m 0644 /tmp/${id}-${n} ${e.stateDir}/${n}
          '') e.files)}
          # 2. The other environments parked (one environment at a time).
          phase 1

          # 3. Internet (images and upstream's files are downloaded).
          progress 2
          until g curl -sS -o /dev/null --max-time 10 https://github.com 2>/dev/null; do sleep 15; done
          log "internet ok"

          # 4-. The driver's phases.
          for i in $(seq 3 $((steps - 1))); do phase "$i"; done
          log "klaar: ${e.title} is ready on ${e.readyUrl}"
          # Done: no progress any more, so the Launcher says "Klaar" (#238). The
          # unit stays active (RemainAfterExit), and with it the port forwards.
          kill "$refresher" 2>/dev/null || true
          rm -f ${progressFile} ${progressFile}.base
        '';
      };
      proxy = p: "${unit}-proxy-${toString p}";
    in
    {
      services = lib.listToAttrs (map
        (p: lib.nameValuePair (proxy p) {
          description = "Forward localhost:${toString p} to the ${e.title} guest";
          requires = [ "${proxy p}.socket" ];
          after = [ "${proxy p}.socket" ];
          serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${guestIp}:${toString p}";
        })
        e.ports) // {
        ${unit} = {
          description = "Deploy the ${e.title} environment in the guest";
          after = [ "dawo-appliance-guest.service" "network-online.target" ];
          wants = [ "network-online.target" ] ++ map (p: "${proxy p}.socket") e.ports;
          serviceConfig = {
            Type = "simple";
            RemainAfterExit = true;
            ExecStart = "${runner}/bin/${unit}";
            # As Mijn Bureau's runner: after a normal stop no old progress shows.
            ExecStopPost = toString (pkgs.writeShellScript "${id}-progress-clear" ''
              if [ "''${SERVICE_RESULT:-}" = success ]; then rm -f ${progressFile} ${progressFile}.base; fi
            '');
            StandardOutput = "journal+console";
            StandardError = "journal+console";
          };
        };
      };
      sockets = lib.listToAttrs (map
        (p: lib.nameValuePair (proxy p) {
          description = "localhost:${toString p} for the ${e.title} environment";
          partOf = [ "${unit}.service" ];
          listenStreams = [ "127.0.0.1:${toString p}" "[::1]:${toString p}" ];
        })
        e.ports);
      launch = {
        units = [ "dawo-appliance-guest.service" "${unit}.service" ];
        inherit progressFile;
      };
    };

  built = lib.mapAttrs mk cfg;
in
{
  options.appliance.composeEnvironments = lib.mkOption {
    type = lib.types.attrsOf envType;
    default = { };
    description = "Compose environments deployed in the guest (see the header of this file).";
  };

  config = lib.mkIf (cfg != { }) {
    systemd.services = lib.mkMerge (lib.mapAttrsToList (_: b: b.services) built);
    systemd.sockets = lib.mkMerge (lib.mapAttrsToList (_: b: b.sockets) built);
    services.launch.environments = lib.mapAttrs (_: b: b.launch) built;
    networking.hosts."127.0.0.1" = lib.concatMap (e: e.hostNames) (lib.attrValues cfg);
  };
}
