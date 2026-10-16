# The Valtimo environment on the live USB (#246, ADR 0008): upstream's
# official GZAC demo (gzac-docker-compose, `--profile demo`) in the guest,
# deployed by apps/valtimo/deploy.sh phase by phase, with progress for the
# Launcher (#232/#235). The browser keeps upstream's addresses: while this
# environment runs, the host forwards localhost:80, :8080 and :8081 to the
# guest (systemd-socket-proxyd), so the realm, the redirect URIs and the
# frontend settings stay exactly as upstream ships them.
#
# Started and stopped by Launch (`launch valtimo`, the Launcher card); one
# environment at a time: the driver parks Mijn Bureau's K3s first.
#
# Experimental and unofficial. Not for production.
{ pkgs, lib, ... }:

let
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  up = manifest.upstream.gzac_docker_compose;
  tools = manifest.valtimo.tooling;
  driver = ../../apps/valtimo/deploy.sh;
  override = ../../environments/valtimo/compose/override.yaml;
  guestIp = "192.168.150.10";
  ports = [ 80 8080 8081 ];
  logFile = "/var/log/dawo-appliance-valtimo.log";
  progressFile = "/run/launch/progress/valtimo.json";

  runner = pkgs.writeShellApplication {
    name = "dawo-appliance-valtimo";
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
      names=(vm park net docker source pull up ready)
      labels=("Virtuele machine starten" "Mijn Bureau even stilzetten" "Wachten op internet (wifi Dawo of een netwerkkabel)"
              "Docker installeren" "Valtimo ophalen (de officiële demo)" "Onderdelen downloaden"
              "Valtimo starten" "Wachten tot Valtimo klaar is (de demozaken worden aangemaakt)")
      steps=''${#names[@]}
      since="$(date +%s)"
      durations=/var/lib/dawo-appliance/vt-durations
      last_secs() { awk -v k="$1" '$1 == k { s = $2 } END { if (s != "") print s }' "$durations" 2>/dev/null || true; }
      typical() {
        case "$1" in
          vm) echo 120 ;; park) echo 15 ;; net) echo 5 ;; docker) echo 40 ;; source) echo 10 ;;
          pull) echo 300 ;; up) echo 30 ;; ready) echo 180 ;; *) echo 30 ;;
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

      denv=(VT_REPO=${up.url} VT_REV=${up.rev} VT_OVERRIDE=/var/lib/dawo-appliance-valtimo/override.yaml
            DOCKER_URL=${tools.docker.url} DOCKER_SHA=${tools.docker.sha256}
            COMPOSE_URL=${tools.compose.url} COMPOSE_SHA=${tools.compose.sha256})
      phase() { # phase INDEX: run the driver's phase, three attempts
        local i="$1" name="''${names[$1]}" t0 attempt
        progress "$i"
        for attempt in 1 2 3; do
          t0=$SECONDS
          log "phase $name: attempt $attempt"
          if g sudo env "''${denv[@]}" /usr/local/sbin/vt-deploy --phase "$name" >> ${logFile} 2>&1; then
            log "phase $name: ok after $((SECONDS - t0))s"
            echo "$name $((SECONDS - t0))" >> "$durations" || true
            return 0
          fi
          log "phase $name: FAILED after $((SECONDS - t0))s"
          sleep 20
        done
        progress "$i" "Deze stap is drie keer mislukt. De details staan in valtimo.txt op de USB-schijf."
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

      # The driver and our override into the guest (from this image).
      g "cat > /tmp/vt-deploy.sh" < ${driver}
      g sudo install -m 0755 /tmp/vt-deploy.sh /usr/local/sbin/vt-deploy
      g sudo mkdir -p /var/lib/dawo-appliance-valtimo
      g "cat > /tmp/vt-override.yaml" < ${override}
      g sudo install -m 0644 /tmp/vt-override.yaml /var/lib/dawo-appliance-valtimo/override.yaml

      # 2. Mijn Bureau's K3s parked (one environment at a time).
      phase 1

      # 3. Internet (images and the upstream compose are downloaded).
      progress 2
      until g curl -sS -o /dev/null --max-time 10 https://github.com 2>/dev/null; do sleep 15; done
      log "internet ok"

      # 4-8. The driver's phases.
      for i in 3 4 5 6 7; do phase "$i"; done
      log "klaar: Valtimo is ready on http://localhost/"
      # Done: no progress any more, so the Launcher says "Klaar" (#238). The
      # unit stays active (RemainAfterExit), and with it the port forwards.
      kill "$refresher" 2>/dev/null || true
      rm -f ${progressFile} ${progressFile}.base
    '';
  };

  proxyUnits = lib.listToAttrs (map
    (p: lib.nameValuePair "dawo-appliance-valtimo-proxy-${toString p}" {
      description = "Forward localhost:${toString p} to the Valtimo guest (#246)";
      requires = [ "dawo-appliance-valtimo-proxy-${toString p}.socket" ];
      after = [ "dawo-appliance-valtimo-proxy-${toString p}.socket" ];
      serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${guestIp}:${toString p}";
    })
    ports);
  proxySockets = lib.listToAttrs (map
    (p: lib.nameValuePair "dawo-appliance-valtimo-proxy-${toString p}" {
      description = "localhost:${toString p} for the Valtimo environment (#246)";
      partOf = [ "dawo-appliance-valtimo.service" ];
      listenStreams = [ "127.0.0.1:${toString p}" "[::1]:${toString p}" ];
    })
    ports);
in
{
  systemd.services = proxyUnits // {
    dawo-appliance-valtimo = {
      description = "Deploy the Valtimo environment (GZAC demo) in the guest";
      after = [ "dawo-appliance-guest.service" "network-online.target" ];
      wants = [ "network-online.target" ] ++ map (p: "dawo-appliance-valtimo-proxy-${toString p}.socket") ports;
      serviceConfig = {
        Type = "simple";
        RemainAfterExit = true;
        ExecStart = "${runner}/bin/dawo-appliance-valtimo";
        # As Mijn Bureau's runner: after a normal stop no old progress shows.
        ExecStopPost = toString (pkgs.writeShellScript "valtimo-progress-clear" ''
          if [ "''${SERVICE_RESULT:-}" = success ]; then rm -f ${progressFile} ${progressFile}.base; fi
        '');
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };
  };
  systemd.sockets = proxySockets;
}
