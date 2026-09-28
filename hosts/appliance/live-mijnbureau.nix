# Mijn Bureau deploys itself on the live USB (issue #111, ADR 0006/0007).
#
# Once the guest's K3s is Ready and the laptop has internet, this host service
# copies the pinned driver (apps/mijn-bureau/deploy.sh) into the guest and runs
# its 14 phases one by one with the laptop profile (ADR 0007). It is
# re-entrant: a phase that finished leaves a marker in the guest, whose disk
# lives on the stick (#109), so a later boot continues where the last one
# stopped. Progress goes to /run/dawo-appliance/mijnbureau, shown with a
# progress bar on the live status page (#116); a desktop notification only
# says "done" or "failed". The
# full output goes to /var/log/dawo-appliance-mijnbureau.log, which the debug
# log collector copies to the stick as mijnbureau.txt. When the deployment is
# healthy, the existing dashboard opener opens the browser.
#
# Experimental and unofficial. Not for production.
{ pkgs, lib, config, ... }:

let
  driver = ../../apps/mijn-bureau/deploy.sh;
  status = "/run/dawo-appliance/mijnbureau";
  logFile = "/var/log/dawo-appliance-mijnbureau.log";

  runner = pkgs.writeShellApplication {
    name = "dawo-appliance-mijnbureau";
    runtimeInputs = with pkgs; [ coreutils gnugrep openssh curl util-linux libnotify systemd ];
    text = ''
      mkdir -p /run/dawo-appliance
      key=/var/lib/dawo-appliance/ssh/id_ed25519
      ssh_opts=(-i "$key" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30
                -o ServerAliveCountMax=10 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)
      # The command line is meant to expand here, on the host (SC2029).
      # shellcheck disable=SC2029
      g() { ssh "''${ssh_opts[@]}" ops@192.168.150.10 "$@"; }
      up() { cut -d' ' -f1 /proc/uptime | cut -d. -f1; }
      log() { echo "$(date -u +%FT%TZ) t=$(up)s $*" | tee -a ${logFile}; }

      # One notification in the dawo desktop session, replaced on every update.
      nid=""
      notify() { # notify SUMMARY BODY
        local uid bus
        uid="$(id -u dawo 2>/dev/null || true)"; bus="/run/user/$uid/bus"
        if [ -z "$uid" ] || [ ! -S "$bus" ]; then return 0; fi
        local args=(--app-name "DAWO appliance" --icon system-software-update -p)
        [ -n "$nid" ] && args+=(-r "$nid")
        nid="$(runuser -u dawo -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
               notify-send "''${args[@]}" "$1" "$2" 2>/dev/null || echo "$nid")"
      }
      state() { echo "$1" > ${status}; log "status: $1"; }

      phases=(preflight tools cert-manager issuer password source values deploy
              networking wait-certs trust oidc-restart post-fixes sessions)

      # 1. Wait for the guest's K3s (bounded by the unit's TimeoutStartSec).
      state "wacht op de virtuele machine en K3s"
      until g sudo k3s kubectl get node 2>/dev/null | grep -q ' Ready'; do
        if [ -s /run/dawo-appliance/guest-skipped ]; then
          state "niet mogelijk: de virtuele machine is niet gestart"
          exit 0
        fi
        sleep 10
      done
      log "K3s Ready"

      # 2. Internet (upstream charts and images are downloaded).
      waited=0
      until g curl -sS -o /dev/null --max-time 10 https://github.com 2>/dev/null; do
        if [ "$waited" -eq 0 ]; then
          state "wacht op internet (wifi Dawo of een netwerkkabel)"
        fi
        waited=$((waited + 15)); sleep 15
      done
      log "internet ok"

      # 3. The pinned driver into the guest.
      g "cat > /tmp/mb-deploy.sh" < ${driver}
      g sudo install -m 0755 /tmp/mb-deploy.sh /usr/local/sbin/mb-deploy
      g sudo mkdir -p /var/lib/dawo-appliance-mb

      # 4. The phases, each once; a failed phase is retried twice.
      total=''${#phases[@]}
      SECONDS=0
      for i in "''${!phases[@]}"; do
        n=$((i + 1)); name="''${phases[$i]}"
        if g sudo test -e "/var/lib/dawo-appliance-mb/phase-$n.done"; then
          log "phase $n/$total $name: already done"
          continue
        fi
        [ -s /run/dawo-appliance/mijnbureau-start ] || date +%s > /run/dawo-appliance/mijnbureau-start
        state "wordt uitgerold: stap $n van $total ($name)"
        ok=no
        for attempt in 1 2 3; do
          t0=$SECONDS
          log "phase $n/$total $name: attempt $attempt"
          if g sudo env MB_PROFILE=laptop-demo /usr/local/sbin/mb-deploy --phase "$n" >> ${logFile} 2>&1; then
            log "phase $n/$total $name: ok after $((SECONDS - t0))s"
            g sudo touch "/var/lib/dawo-appliance-mb/phase-$n.done"
            ok=yes; break
          fi
          log "phase $n/$total $name: FAILED after $((SECONDS - t0))s"
          sleep 30
        done
        if [ "$ok" != yes ]; then
          state "mislukt bij stap $n van $total ($name); zie mijnbureau.txt op de USB-stick"
          notify "Mijn Bureau: uitrol mislukt" "Stap $n van $total ($name) is drie keer mislukt. De details staan in mijnbureau.txt op de USB-stick."
          exit 1
        fi
      done
      state "klaar: Mijn Bureau is uitgerold (''${SECONDS}s)"
      notify "Mijn Bureau is uitgerold" "De browser opent het dashboard zodra alles gezond is."
    '';
  };
in
{
  systemd.services.dawo-appliance-mijnbureau = {
    description = "Deploy Mijn Bureau in the guest (laptop profile), phase by phase";
    wantedBy = [ "multi-user.target" ];
    after = [ "dawo-appliance-guest.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${runner}/bin/dawo-appliance-mijnbureau";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };

  # The status window mentions the automatic deployment (welcome script).
  environment.etc."dawo-appliance/mijnbureau-auto".text = "laptop-demo\n";
  # The dashboard opener waits long enough for a first deployment from a stick.
  environment.etc."dawo-appliance/dashboard.env".text = "DASHBOARD_TIMEOUT=14400\n";
  environment.systemPackages = [ runner ];
}
