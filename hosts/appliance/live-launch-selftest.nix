# Launch self-test (ADR 0008, #229): the regression run of the Launcher flow,
# the way a user goes through it. It runs only when the DAWO_LOGS stick
# carries launch-selftest.txt (the KVM test test-live-launch does that); on a
# normal boot it does nothing.
#
#   1. a clean boot: Mijn Bureau stopped, the note "kies er een in de
#      Launcher", no guest running;
#   2. the Launcher answers (user service in the desktop session) and refuses
#      a start without its token;
#   3. the automatic start (#238) is announced and fires by itself (round 1),
#      then Starten through the Launcher's API (round 2): K3s Ready;
#   4. Stoppen: guest unit inactive, no libvirt domain running, state stopped;
#   5. Starten again (re-entrant): K3s Ready again.
#
# Each step prints a `LAUNCH-TEST:` line on the serial console and in
# /run/dawo-appliance/launch-selftest.txt (copied to the stick with the logs).
#
# Experimental and unofficial. Not for production.
{ pkgs, ... }:

let
  selftest = pkgs.writeShellApplication {
    name = "launch-selftest";
    runtimeInputs = with pkgs; [ coreutils gnused gnugrep curl jq openssh systemd libvirt ];
    text = ''
      out=/run/dawo-appliance/launch-selftest.txt
      mkdir -p /run/dawo-appliance
      : > "$out"
      up() { cut -d' ' -f1 /proc/uptime | cut -d. -f1; }
      say() {
        line="LAUNCH-TEST: $* t=$(up)s"
        echo "$line" | tee -a "$out"
        if [ -w /dev/ttyS0 ]; then echo "$line" > /dev/ttyS0 2>/dev/null || true; fi
      }
      fail() { say "DONE fail: $*"; exit 1; }

      api=http://127.0.0.1:8790
      env=mijn-bureau
      key=/var/lib/dawo-appliance/ssh/id_ed25519
      g() { ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR ops@192.168.150.10 "$@"; }
      state() { curl -sf "$api/api/environments" | jq -r --arg id "$env" '.[] | select(.id == $id) | .state'; }
      running_domains() { virsh -c qemu:///system list --name 2>/dev/null | grep -c . || true; }
      wait_for() { # wait_for SECONDS DESCRIPTION COMMAND...
        local limit="$1" what="$2" t0; shift 2; t0="$(up)"
        until "$@"; do
          [ $(( $(up) - t0 )) -ge "$limit" ] && fail "no $what after ''${limit}s"
          sleep 5
        done
      }
      k3s_ready() { g sudo k3s kubectl get node 2>/dev/null | grep -q ' Ready'; }
      guest_down() { ! systemctl is-active --quiet dawo-appliance-guest.service && [ "$(running_domains)" = 0 ]; }
      launcher_up() { curl -sf -o /dev/null "$api/"; }
      is_stopped() { [ "$(state)" = stopped ]; }
      # The progress the Launcher shows while starting (#232).
      step() { curl -sf "$api/api/environments" | jq -r --arg id "$env" '.[] | select(.id == $id) | .progress.step // 0'; }
      progress_text() { curl -sf "$api/api/environments" | jq -r --arg id "$env" '.[] | select(.id == $id) | .progress | "stap \(.step) van \(.steps): \(.label) (nog ~\(.rest) s na deze stap)"'; }
      has_rest() { curl -sf "$api/api/environments" | jq -e --arg id "$env" '.[] | select(.id == $id) | .progress.rest | type == "number"' >/dev/null; }
      at_step() { [ "$(step)" -ge "$1" ]; }
      post() { # post start|stop -> the JSON answer
        curl -s -m 600 -X POST -H "X-Launcher-Token: $token" "$api/api/$1/$env"
      }

      say "started"
      # 1. A clean boot.
      wait_for 600 "Launcher on $api (desktop session)" launcher_up
      say "Launcher answers"
      [ "$(state)" = stopped ] || fail "$env is '$(state)' at boot, not stopped"
      guest_down || fail "a guest runs at boot"
      grep -q Launcher /run/dawo-appliance/guest-skipped 2>/dev/null \
        || fail "no 'kies er een in de Launcher' note at boot"
      say "clean boot: $env stopped, no guest, note shown"

      # 2. The token protects start and stop.
      token="$(curl -sf "$api/" | sed -n 's/.*const TOKEN = "\([0-9a-f]*\)".*/\1/p')"
      [ -n "$token" ] || fail "no token in the Launcher page"
      code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$api/api/start/$env")"
      [ "$code" = 403 ] || fail "start without token answered $code, not 403"
      say "start without token refused (403)"
      # The automatic start (#238) is announced at boot.
      curl -sf "$api/api/environments" | jq -e --arg id "$env" '.[] | select(.id == $id) | .autostart.at | type == "number"' >/dev/null         || fail "no automatic start announced for $env"
      say "automatic start announced"

      for round in 1 2; do
        if [ "$round" = 1 ]; then
          # 3a. Nobody presses anything: the Launcher starts it by itself (#238).
          wait_for 300 "automatic start" at_step 1
          say "start 1: started automatically (no button pressed)"
        else
          # 3b. Starten, as the button does.
          answer="$(post start)"
          echo "$answer" | jq -e .ok >/dev/null || fail "start $round: $answer"
          say "start $round accepted: $(echo "$answer" | jq -r .output | tail -n1)"
        fi
        wait_for 600 "progress in the Launcher after start $round" at_step 1
        say "start $round: Launcher shows $(progress_text)"
        wait_for 1800 "K3s Ready after start $round" k3s_ready
        st="$(state)"
        case "$st" in starting | ready) ;; *) fail "state '$st' while K3s is Ready" ;; esac
        [ -s /run/dawo-appliance/guest-skipped ] && fail "the 'no environment' note is still there"
        say "start $round: guest and K3s Ready (state $st)"
        # Past the virtual machine the progress moves on (internet, phases).
        # Step 1 also covers the guest's one-time reboot (nousershstk, #176).
        wait_for 600 "progress past step 1 after start $round" at_step 2
        has_rest || fail "no remaining-time estimate (progress.rest) in the Launcher (#235)"
        say "start $round: Launcher shows $(progress_text)"

        # 4. Stoppen.
        answer="$(post stop)"
        echo "$answer" | jq -e .ok >/dev/null || fail "stop $round: $answer"
        wait_for 300 "guest down after stop $round" guest_down
        wait_for 30 "state stopped after stop $round" is_stopped
        say "stop $round: guest unit inactive, no domain running, state stopped"
      done
      say "DONE ok"
    '';
  };
in
{
  environment.systemPackages = [ selftest ];

  systemd.services.launch-selftest = {
    description = "Launch self-test: start, stop and start again through the Launcher (only with launch-selftest.txt on DAWO_LOGS)";
    wantedBy = [ "multi-user.target" ];
    after = [ "dawo-appliance-data.service" "dawo-appliance-launch-note.service" "launch-autostart.service" ];
    wants = [ "dawo-appliance-data.service" ];
    unitConfig.ConditionPathExists = "/run/dawo-logs/launch-selftest.txt";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${selftest}/bin/launch-selftest";
    };
  };
}
