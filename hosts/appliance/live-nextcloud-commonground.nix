# The Nextcloud Common Ground environment on the live USB (#250, ADR 0008):
# Conduction's own local demo (dossiq-compose.yaml from ConductionNL/dossiq)
# in the guest, deployed by apps/nextcloud-commonground/deploy.sh phase by
# phase, with progress for the Launcher (#232/#235). The browser keeps
# upstream's address: while this environment runs, the host forwards
# localhost:8609 to the guest (systemd-socket-proxyd), so the trusted domains
# and OVERWRITECLIURL stay exactly as upstream ships them.
#
# Started and stopped by Launch (`launch nextcloud-commonground`, the Launcher
# card); one environment at a time: the driver parks Mijn Bureau's K3s and
# any other compose environment (Valtimo) first.
#
# Experimental and unofficial. Not for production.
{ pkgs, lib, ... }:

let
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  up = manifest.upstream.dossiq_compose;
  env = manifest.nextcloud_commonground;
  # One Docker Engine for the compose environments (D43).
  tools = manifest.valtimo.tooling;
  driver = ../../apps/nextcloud-commonground/deploy.sh;
  override = ../../environments/nextcloud-commonground/compose/override.yaml;
  # The app pins for the driver: "<id> <version> <url> <sha256>" per line.
  appsFile = pkgs.writeText "nextcloud-commonground-apps.txt"
    (lib.concatStrings (lib.mapAttrsToList (id: a: "${id} ${a.version} ${a.url} ${a.sha256}\n") env.apps));
  guestIp = "192.168.150.10";
  ports = [ env.compose.port ];
  stateDir = "/var/lib/dawo-appliance-nextcloud-commonground";
  logFile = "/var/log/dawo-appliance-nextcloud-commonground.log";
  progressFile = "/run/launch/progress/nextcloud-commonground.json";

  runner = pkgs.writeShellApplication {
    name = "dawo-appliance-nextcloud-commonground";
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
      names=(vm park net docker source pull apps up ready enable seed)
      labels=("Virtuele machine starten" "Andere omgevingen even stilzetten (er draait er één tegelijk)"
              "Wachten op internet (wifi Dawo of een netwerkkabel)" "Docker installeren"
              "Nextcloud Common Ground ophalen (de demo van Conduction)" "Onderdelen downloaden"
              "De apps van Conduction downloaden en controleren" "Nextcloud starten"
              "Wachten tot Nextcloud klaar is (de eerste keer wordt het geïnstalleerd)"
              "De apps aanzetten" "Demozaken en demogegevens aanmaken")
      steps=''${#names[@]}
      since="$(date +%s)"
      durations=/var/lib/dawo-appliance/nccg-durations
      last_secs() { awk -v k="$1" '$1 == k { s = $2 } END { if (s != "") print s }' "$durations" 2>/dev/null || true; }
      typical() {
        case "$1" in
          vm) echo 120 ;; park) echo 15 ;; net) echo 5 ;; docker) echo 40 ;; source) echo 5 ;;
          pull) echo 180 ;; apps) echo 90 ;; up) echo 20 ;; ready) echo 240 ;; enable) echo 120 ;;
          seed) echo 60 ;; *) echo 30 ;;
        esac
      }
      key_exp() { local e; e="$(last_secs "$1")"; echo "''${e:-$(typical "$1")}"; }
      rest_after() { local t=0 i; for i in $(seq "$1" $((steps - 1))); do t=$((t + $(key_exp "''${names[$i]}"))); done; echo "$t"; }
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
          --argjson started "$(date +%s)" --argjson since "$since" --argjson expected "$(key_exp "''${names[$1]}")" \
          --argjson rest "$(rest_after $(($1 + 1)))" --arg error "''${2:-}" \
          '{step: $step, steps: $steps, label: $label, started: $started, since: $since, expected: $expected, rest: $rest}
           + (if $error == "" then {} else {error: $error} end)' \
          > ${progressFile}.base.new && mv -f ${progressFile}.base.new ${progressFile}.base
        refresh_progress
      }
      ( while sleep 5; do refresh_progress; done ) &
      refresher=$!
      trap 'kill "$refresher" 2>/dev/null || true' EXIT

      denv=(NC_COMPOSE_URL=${up.raw_url} NC_COMPOSE_SHA=${up.sha256}
            NC_OVERRIDE=${stateDir}/override.yaml NC_APPS_FILE=${stateDir}/apps.txt
            DOCKER_URL=${tools.docker.url} DOCKER_SHA=${tools.docker.sha256}
            COMPOSE_URL=${tools.compose.url} COMPOSE_SHA=${tools.compose.sha256})
      phase() { # phase INDEX: run the driver's phase, three attempts
        local i="$1" name="''${names[$1]}" t0 attempt
        progress "$i"
        for attempt in 1 2 3; do
          t0=$SECONDS
          log "phase $name: attempt $attempt"
          if g sudo env "''${denv[@]}" /usr/local/sbin/nccg-deploy --phase "$name" >> ${logFile} 2>&1; then
            log "phase $name: ok after $((SECONDS - t0))s"
            echo "$name $((SECONDS - t0))" >> "$durations" || true
            return 0
          fi
          log "phase $name: FAILED after $((SECONDS - t0))s"
          sleep 20
        done
        progress "$i" "Deze stap is drie keer mislukt. De details staan in nextcloud-commonground.txt op de USB-schijf."
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

      # The driver, our override and the app pins into the guest (from this image).
      g "cat > /tmp/nccg-deploy.sh" < ${driver}
      g sudo install -m 0755 /tmp/nccg-deploy.sh /usr/local/sbin/nccg-deploy
      g sudo mkdir -p ${stateDir}
      g "cat > /tmp/nccg-override.yaml" < ${override}
      g sudo install -m 0644 /tmp/nccg-override.yaml ${stateDir}/override.yaml
      g "cat > /tmp/nccg-apps.txt" < ${appsFile}
      g sudo install -m 0644 /tmp/nccg-apps.txt ${stateDir}/apps.txt

      # 2. The other environments parked (one environment at a time).
      phase 1

      # 3. Internet (images, the upstream compose file and the apps are downloaded).
      progress 2
      until g curl -sS -o /dev/null --max-time 10 https://github.com 2>/dev/null; do sleep 15; done
      log "internet ok"

      # 4-11. The driver's phases.
      for i in 3 4 5 6 7 8 9 10; do phase "$i"; done
      log "klaar: Nextcloud Common Ground is ready on http://localhost:${toString env.compose.port}/apps/dossiq/"
      # Done: no progress any more, so the Launcher says "Klaar" (#238). The
      # unit stays active (RemainAfterExit), and with it the port forward.
      kill "$refresher" 2>/dev/null || true
      rm -f ${progressFile} ${progressFile}.base
    '';
  };

  proxyUnits = lib.listToAttrs (map
    (p: lib.nameValuePair "dawo-appliance-nextcloud-commonground-proxy-${toString p}" {
      description = "Forward localhost:${toString p} to the Nextcloud Common Ground guest (#250)";
      requires = [ "dawo-appliance-nextcloud-commonground-proxy-${toString p}.socket" ];
      after = [ "dawo-appliance-nextcloud-commonground-proxy-${toString p}.socket" ];
      serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${guestIp}:${toString p}";
    })
    ports);
  proxySockets = lib.listToAttrs (map
    (p: lib.nameValuePair "dawo-appliance-nextcloud-commonground-proxy-${toString p}" {
      description = "localhost:${toString p} for the Nextcloud Common Ground environment (#250)";
      partOf = [ "dawo-appliance-nextcloud-commonground.service" ];
      listenStreams = [ "127.0.0.1:${toString p}" "[::1]:${toString p}" ];
    })
    ports);
in
{
  systemd.services = proxyUnits // {
    dawo-appliance-nextcloud-commonground = {
      description = "Deploy the Nextcloud Common Ground environment (Conduction's demo) in the guest";
      after = [ "dawo-appliance-guest.service" "network-online.target" ];
      wants = [ "network-online.target" ] ++ map (p: "dawo-appliance-nextcloud-commonground-proxy-${toString p}.socket") ports;
      serviceConfig = {
        Type = "simple";
        RemainAfterExit = true;
        ExecStart = "${runner}/bin/dawo-appliance-nextcloud-commonground";
        # As Mijn Bureau's runner: after a normal stop no old progress shows.
        ExecStopPost = toString (pkgs.writeShellScript "nextcloud-commonground-progress-clear" ''
          if [ "''${SERVICE_RESULT:-}" = success ]; then rm -f ${progressFile} ${progressFile}.base; fi
        '');
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };
  };
  systemd.sockets = proxySockets;
}
