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
  # A phase marker records the driver it was made with (#131): after a driver
  # update every phase runs again (they are idempotent), so e.g. new values
  # (phase 7) really reach the guest whose disk persisted on the stick.
  driverSum = builtins.substring 0 16 (builtins.hashFile "sha256" driver);
  status = "/run/dawo-appliance/mijnbureau";
  # Progress for the Launcher (#232), read by `launch status`.
  progressFile = "/run/launch/progress/mijn-bureau.json";
  logFile = "/var/log/dawo-appliance-mijnbureau.log";
  domain = (builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json)).mijn_bureau.base_domain.value;

  runner = pkgs.writeShellApplication {
    name = "dawo-appliance-mijnbureau";
    runtimeInputs = with pkgs; [ coreutils gnugrep gnused gawk jq openssh curl util-linux libnotify systemd ];
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

      # Progress for the Launcher (#232): the whole start is one list of steps
      # (virtual machine, internet, the 14 phases, the apps answering); each
      # step says how long it took last time on this machine (mb-durations
      # on the stick), or a typical value. Written as one JSON object.
      labels=("Controles" "Hulpprogramma's installeren" "Certificaatbeheer installeren"
              "Certificaatuitgever instellen" "Wachtwoorden maken" "Mijn Bureau ophalen"
              "Instellingen schrijven" "Apps installeren (downloaden)" "Netwerk instellen"
              "Wachten op certificaten" "Beveiligde verbindingen instellen (de apps herstarten)"
              "Inloggen koppelen" "Apps afronden (Office, inloggen)" "Sessies instellen")
      steps=$(( ''${#phases[@]} + 3 ))
      since="$(date +%s)"
      durations=/var/lib/dawo-appliance/mb-durations
      last_secs() { awk -v k="$1" '$1 == k { s = $2 } END { if (s != "") print s }' "$durations" 2>/dev/null || true; }
      typical() { # the status page's typical durations (Dell Latitude 5550)
        case "$1" in
          vm) echo 180 ;; reboot) echo 90 ;; net) echo 10 ;; apps) echo 540 ;;
          8) echo 360 ;; 10) echo 90 ;; 11) echo 420 ;; 13) echo 120 ;; *) echo 45 ;;
        esac
      }
      # The time still to come (#235): a phase that is already done with this
      # driver takes seconds. Before the guest answers, a finished deployment
      # with the same driver (mb-deployed-driver) predicts that all are done.
      deployed="$(cat /var/lib/dawo-appliance/mb-deployed-driver 2>/dev/null || true)"
      done_now=()
      key_exp() { local e; e="$(last_secs "$1")"; echo "''${e:-$(typical "$1")}"; }
      phase_exp() {
        if [ "$deployed" = "${driverSum}" ] || [ -n "''${done_now[$1]:-}" ]; then echo 2; else key_exp "$1"; fi
      }
      rest_after() { # seconds expected for the steps after STEP
        local t=0 n
        if [ "$1" -lt 2 ]; then t=$((t + $(key_exp net))); fi
        for n in $(seq 1 ''${#phases[@]}); do
          if [ $((n + 2)) -gt "$1" ]; then t=$((t + $(phase_exp "$n"))); fi
        done
        if [ "$1" -lt "$steps" ]; then t=$((t + $(key_exp apps))); fi
        echo "$t"
      }
      # What the deployment does right now: its last log line, in plain Dutch
      # where we know the pattern (#235: "veel te technisch, maar goh wat leuk").
      activity() {
        tail -n 30 ${logFile} 2>/dev/null | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n 1 | cut -c1-200 | sed -E \
          -e 's/^[0-9T:Z-]+ t=[0-9]+s //' \
          -e 's/.*Waiting for deployment "([^"]+)" rollout to finish.*/Wacht tot \1 (opnieuw) is gestart/' \
          -e 's/.*deployment "([^"]+)" successfully rolled out.*/\1 is gestart/' \
          -e 's/.*Waiting for (statefulset|daemon set) "?([^" ]+)"? rollout to finish.*/Wacht tot \2 (opnieuw) is gestart/' \
          -e 's/.*(statefulset|daemon set) "?([^" ]+)"? successfully rolled out.*/\2 is gestart/' || true
      }
      # The step (progress.base) plus the activity, every 5 s while we run.
      refresh_progress() {
        local tmp
        [ -s ${progressFile}.base ] || return 0
        tmp="$(mktemp ${progressFile}.XXXXXX)" || return 0
        if jq --arg detail "$(activity)" --argjson activity "$(stat -c %Y ${logFile} 2>/dev/null || date +%s)" \
             '. + {detail: $detail, activity: $activity}' ${progressFile}.base > "$tmp" 2>/dev/null; then
          # mktemp makes it 0600; the Launcher reads it as the desktop user.
          chmod 0644 "$tmp"
          mv -f "$tmp" ${progressFile}
        else
          rm -f "$tmp"
        fi
      }
      progress() { # progress STEP LABEL KEY [ERROR]
        local exp
        exp="$(last_secs "$3")"; exp="''${exp:-$(typical "$3")}"
        mkdir -p "$(dirname ${progressFile})"
        jq -n --argjson step "$1" --argjson steps "$steps" --arg label "$2" \
          --argjson started "$(date +%s)" --argjson since "$since" --argjson expected "$exp" \
          --argjson rest "$(rest_after "$1")" --arg error "''${4:-}" \
          '{step: $step, steps: $steps, label: $label, started: $started, since: $since, expected: $expected, rest: $rest}
           + (if $error == "" then {} else {error: $error} end)' \
          > ${progressFile}.base.new && mv -f ${progressFile}.base.new ${progressFile}.base
        refresh_progress
      }
      ( while sleep 5; do refresh_progress; done ) &
      refresher=$!
      trap 'kill "$refresher" 2>/dev/null || true' EXIT
      failed() { # failed STEP LABEL KEY MESSAGE: keep the step, add the error
        progress "$1" "$2" "$3" "$4"
      }

      k3s_ready() { g sudo k3s kubectl get node 2>/dev/null | grep -q ' Ready'; }

      # 1. Wait for the guest's K3s (bounded by the unit's TimeoutStartSec).
      state "wacht op de virtuele machine en K3s"
      progress 1 "Virtuele machine en K3s starten" vm
      vm_t0="$(date +%s)"
      until k3s_ready; do
        if [ -s /run/dawo-appliance/guest-skipped ]; then
          state "niet mogelijk: de virtuele machine is niet gestart"
          failed 1 "Virtuele machine en K3s starten" vm "De virtuele machine kon niet starten: $(cat /run/dawo-appliance/guest-skipped)"
          exit 0
        fi
        sleep 10
      done
      log "K3s Ready"

      # A guest kernel Oops left the guest hanging, unreachable, until it was
      # powered off (#119). Make it reboot itself instead (persistent, and
      # now); wait_guest below then waits for it to come back.
      # One string: ssh joins its arguments, the guest's shell parses them.
      if g "sudo sh -c 'printf \"kernel.panic_on_oops = 1\nkernel.panic = 10\n\" > /etc/sysctl.d/90-dawo-appliance-panic.conf && sysctl -q -p /etc/sysctl.d/90-dawo-appliance-panic.conf'"; then
        log "guest: reboots itself after a kernel oops (panic_on_oops=1, panic=10)"
      else
        log "guest: could not set panic_on_oops"
      fi

      # Before a retry: the guest may have dropped off the network or
      # rebooted (#119). Wait up to 15 minutes for SSH and K3s Ready again.
      wait_guest() {
        local waited=0
        until k3s_ready; do
          if [ "$waited" -ge 900 ]; then
            log "guest: no SSH/K3s Ready after ''${waited}s"
            return 1
          fi
          [ "$waited" -eq 0 ] && log "guest: not answering; waiting for SSH and K3s Ready"
          sleep 15; waited=$((waited + 15))
        done
        [ "$waited" -gt 0 ] && log "guest: back after ''${waited}s"
        return 0
      }

      # The Dell's guest collapsed after ~48 min with every process faulting
      # on its shadow stack at the same address (#176): the host kernel
      # (6.18) offers CET to the guest, but our QEMU does not know CET and
      # does not keep its state. Run the guest without user shadow stacks
      # (kernel parameter `nousershstk`, as on CPUs without CET). Takes one
      # guest reboot the first time; persistent on the guest disk.
      if ! g grep -qw nousershstk /proc/cmdline; then
        # The literal $GRUB_CMDLINE_LINUX_DEFAULT is for grub's shell (SC2016).
        # shellcheck disable=SC2016
        if printf 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT nousershstk"\n' \
             | g "sudo tee /etc/default/grub.d/90-dawo-appliance-cet.cfg >/dev/null && sudo update-grub" >> ${logFile} 2>&1; then
          log "guest: nousershstk added to the kernel command line (#176); rebooting the guest once"
          state "de virtuele machine herstart eenmalig (instelling)"
          progress 1 "Virtuele machine herstart eenmalig (instelling)" reboot
          # The guest watchdog (fwwatch) watched only the first boot; under
          # nested KVM this reboot can hang in the firmware too (#184, three
          # KVM runs on 2026-10-18): watch it from here in the console log.
          mkdir -p /run/dawo-appliance
          cat /var/log/libvirt/qemu/*-console.log 2>/dev/null | wc -c > /run/dawo-appliance/fwwatch-offset || true
          g sudo systemctl reboot || true
          systemctl restart dawo-appliance-guest-fwwatch.service || true
          sleep 20
          reboot_t0="$(date +%s)"
          wait_guest || log "guest: not back after the nousershstk reboot"
          echo "reboot $(( $(date +%s) - reboot_t0 ))" >> "$durations" || true
        else
          log "guest: could not set nousershstk (#176)"
        fi
      else
        log "guest: runs with nousershstk (#176)"
      fi

      echo "vm $(( $(date +%s) - vm_t0 ))" >> "$durations" || true

      # 2. Internet (upstream charts and images are downloaded).
      progress 2 "Wachten op internet (wifi Dawo of een netwerkkabel)" net
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
        marker="/var/lib/dawo-appliance-mb/phase-$n.done"
        progress $((n + 2)) "''${labels[$i]}" "$n"
        made_with="$(g sudo cat "$marker" 2>/dev/null || true)"
        if [ "$made_with" = "${driverSum}" ]; then
          done_now[n]=1
          log "phase $n/$total $name: already done"
          continue
        elif [ -n "$made_with" ] || g sudo test -e "$marker"; then
          log "phase $n/$total $name: done with another driver (''${made_with:-unknown}); running it again"
        fi
        [ -s /run/dawo-appliance/mijnbureau-start ] || date +%s > /run/dawo-appliance/mijnbureau-start
        state "wordt uitgerold: stap $n van $total ($name)"
        ok=no
        for attempt in 1 2 3; do
          t0=$SECONDS
          log "phase $n/$total $name: attempt $attempt"
          if g sudo env MB_PROFILE=laptop-demo /usr/local/sbin/mb-deploy --phase "$n" >> ${logFile} 2>&1; then
            log "phase $n/$total $name: ok after $((SECONDS - t0))s"
            # Kept on the stick (#143): the status page shows how long this
            # step took last time on this machine.
            echo "$n $((SECONDS - t0))" >> /var/lib/dawo-appliance/mb-durations || true
            g "echo ${driverSum} | sudo tee $marker >/dev/null"
            ok=yes; break
          fi
          log "phase $n/$total $name: FAILED after $((SECONDS - t0))s"
          sleep 30
          wait_guest || break
        done
        if [ "$ok" != yes ]; then
          state "mislukt bij stap $n van $total ($name); zie mijnbureau.txt op de USB-stick"
          failed $((n + 2)) "''${labels[$i]}" "$n" "Deze stap is drie keer mislukt. De details staan in mijnbureau.txt op de USB-schijf."
          notify "Mijn Bureau: uitrol mislukt" "Stap $n van $total ($name) is drie keer mislukt. De details staan in mijnbureau.txt op de USB-stick."
          exit 1
        fi
      done
      # After a reboot every phase is "already done" in seconds, but the apps
      # need minutes to start again (#177). Say "klaar" only once they answer
      # over HTTPS (2xx/3xx through Traefik; 404/502/503 means not yet; -k:
      # this is a liveness probe, trust is checked elsewhere).
      state "Mijn Bureau start op: wacht tot de apps reageren (na een herstart meestal 5 tot 10 minuten)"
      progress "$steps" "Mijn Bureau start op (de apps gaan reageren)" apps
      waited=0; answered=0; apps=(id bureaublad nextcloud element); last=""
      for h in "''${apps[@]}"; do
        until code="$(g curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "https://$h.${domain}/" 2>/dev/null)" \
              && [ "''${code:-000}" -ge 200 ] && [ "''${code:-000}" -lt 400 ]; do
          if [ "$waited" -ge 1200 ]; then
            state "mislukt: $h.${domain} reageert niet (HTTP ''${code:-000}); zie mijnbureau.txt op de USB-stick"
            failed "$steps" "Mijn Bureau start op (de apps gaan reageren)" apps "$h.${domain} reageert na 20 minuten nog niet."
            notify "Mijn Bureau reageert niet" "$h.${domain} gaf na 20 minuten nog geen antwoord."
            exit 1
          fi
          # A line on every change and every 30 s, so the Launcher's "laatste
          # activiteit" moves while the apps start (#272: it looked stuck for
          # minutes on the Dell and the presenter switched the laptop off).
          now="$h ''${code:-000}"
          if [ "$now" != "$last" ] || [ $((waited % 30)) -eq 0 ]; then
            log "Wacht tot $h antwoordt ($answered van ''${#apps[@]} apps antwoorden, nu HTTP ''${code:-000}, ''${waited} s)"
            last="$now"
          fi
          sleep 10; waited=$((waited + 10))
        done
        answered=$((answered + 1))
        log "app $h.${domain}: HTTP $code after ''${waited}s ($answered van ''${#apps[@]} apps antwoorden)"
      done
      echo "apps $waited" >> "$durations" || true
      echo "${driverSum}" > /var/lib/dawo-appliance/mb-deployed-driver || true
      state "klaar: Mijn Bureau is uitgerold (''${SECONDS}s)"
      notify "Mijn Bureau is uitgerold" "De browser opent het dashboard zodra alles gezond is."
    '';
  };
  # Optional Nextcloud apps (#190): `dawo-appliance-nc-app <id>` installs one
  # of the pinned apps (deploy.sh --nc-app) into the deployed Nextcloud;
  # without an argument it lists them. Runs as dawo (in libvirtd, so it can
  # read the guest key), once Mijn Bureau says "klaar".
  ncApp = pkgs.writeShellApplication {
    name = "dawo-appliance-nc-app";
    runtimeInputs = with pkgs; [ coreutils gnugrep openssh ];
    text = ''
      key=/var/lib/dawo-appliance/ssh/id_ed25519
      ssh_opts=(-i "$key" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)
      # The command line is meant to expand here, on the host (SC2029).
      # shellcheck disable=SC2029
      g() { ssh "''${ssh_opts[@]}" ops@192.168.150.10 "$@"; }
      if [ $# -eq 0 ]; then
        echo "Gebruik: dawo-appliance-nc-app <app>   (installeert een Nextcloud-app in Mijn Bureau)"
        echo
        g sudo /usr/local/sbin/mb-deploy --list-nc-apps
        exit 0
      fi
      # The name goes through the guest's shell (ssh joins its arguments).
      case "$1" in *[!a-z]* | "") echo "Onbekende app: $1" >&2; exit 2 ;; esac
      grep -q '^klaar' ${status} 2>/dev/null || { echo "Mijn Bureau is nog niet klaar ($(cat ${status} 2>/dev/null || echo 'geen status')); probeer het later." >&2; exit 1; }
      g sudo /usr/local/sbin/mb-deploy --nc-app "$1"
    '';
  };
in
{
  systemd.services.dawo-appliance-mijnbureau = {
    description = "Deploy Mijn Bureau in the guest (laptop profile), phase by phase";
    # With Launch (live-launch.nix) the environment is started by `launch`.
    wantedBy = lib.mkIf (!config.appliance.guest.onDemand) [ "multi-user.target" ];
    after = [ "dawo-appliance-guest.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${runner}/bin/dawo-appliance-mijnbureau";
      # A stopped environment shows no old progress when it is started again
      # (#232); after a failure the file stays, so the Launcher shows the error.
      ExecStopPost = toString (pkgs.writeShellScript "mijnbureau-progress-clear" ''
        if [ "''${SERVICE_RESULT:-}" = success ]; then rm -f ${progressFile} ${progressFile}.base; fi
      '');
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };

  # The status window mentions the automatic deployment (welcome script).
  environment.etc."dawo-appliance/mijnbureau-auto".text = "laptop-demo\n";
  # No automatic dashboard tab on the live USB (#159): a tab that opened by
  # itself left people unsure what to do. The live status page (live.nix)
  # already opens at login and, once the deployment says "klaar", offers
  # "Open Mijn Bureau" in a new tab with the demo login next to it. The
  # installed appliance has no status page and keeps its opener.
  environment.etc."xdg/autostart/dawo-appliance-open-dashboard.desktop".text = lib.mkForce ''
    [Desktop Entry]
    Type=Application
    Name=DAWO appliance: open Mijn Bureau (live USB: the status page's button instead)
    Hidden=true
  '';
  # For a manual `dawo-appliance-open-dashboard`: wait long enough for a first
  # deployment from a stick, and open only when it says "klaar" (#143).
  environment.etc."dawo-appliance/dashboard.env".text = ''
    DASHBOARD_TIMEOUT=14400
    DASHBOARD_WAIT_STATUS=${status}
  '';
  environment.systemPackages = [ runner ncApp ];
}
