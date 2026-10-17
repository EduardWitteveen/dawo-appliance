# Launch self-test (ADR 0008, #229): the regression run of the Launcher flow,
# the way a user goes through it. It runs only when the DAWO_LOGS stick
# carries launch-selftest.txt (the KVM test test-live-launch does that); on a
# normal boot it does nothing.
#
#   1. a clean boot: Mijn Bureau stopped, the note "kies er een in de
#      Launcher", no guest running;
#   2. the Launcher answers (user service in the desktop session) and refuses
#      a start without its token;
#   3. the automatic start (#238; the round, #257) is announced and fires by
#      itself (round 1), the round is stopped so it does not go on to the next
#      environment, then Starten through the Launcher's API (round 2): K3s
#      Ready;
#   4. Stoppen: guest unit inactive, no libvirt domain running, state stopped;
#   5. Starten again (re-entrant): K3s Ready again.
#
# Right after the clean boot it also opens a terminal on the desktop that runs
# `launch`, `launch --check valtimo` and `launch --status`, and saves one
# screenshot of it (screens/launch-cli.png on the stick) for the README (#252).
# That part only logs when it does not work; it never fails the run.
#
# Each step prints a `LAUNCH-TEST:` line on the serial console and in
# /run/dawo-appliance/launch-selftest.txt (copied to the stick with the logs).
#
# Experimental and unofficial. Not for production.
{ pkgs, ... }:

let
  # Runs in a terminal on the desktop, as the user (#252): the real commands,
  # each after a prompt in the shape of the shell's own (the NixOS default),
  # then it waits so the 30-s debug screenshots catch it too.
  cliDemo = pkgs.writeShellScript "launch-cli-demo" ''
    cd "$HOME" 2>/dev/null || true
    p='\e[1;32m[\u@\h:\w]\$\e[0m '
    run() { printf '%s%s\n' "''${p@P}" "$*"; "$@" 2>&1; echo; }
    run launch
    run launch --check valtimo
    run launch --status
    printf '%s' "''${p@P}"
    : > "''${XDG_RUNTIME_DIR:-/tmp}/launch-cli.done"
    sleep "''${1:-75}"
  '';

  selftest = pkgs.writeShellApplication {
    name = "launch-selftest";
    runtimeInputs = with pkgs; [ coreutils gnused gnugrep curl jq openssh systemd libvirt procps util-linux ];
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
      round_off() { curl -sf "$api/api/cycle" | jq -e '.active == false' >/dev/null; }
      post() { # post start|stop -> the JSON answer
        curl -s -m 600 -X POST -H "X-Launcher-Token: $token" "$api/api/$1/$env"
      }
      # The command line for the README (#252): a full-screen Konsole in the
      # dawo desktop session runs `launch`, `launch --check valtimo` and
      # `launch --status` (cliDemo); one Spectacle screenshot of it goes to
      # the session's dawo-shots dir as launch-cli.png, which the log
      # collector copies to DAWO_LOGS/.../screens/. Best effort: it only says
      # what did not work.
      cli_shot() {
        set +e
        local uid pid dir done_file kpid
        local -a envs
        uid="$(id -u dawo 2>/dev/null)"
        # The desktop comes up a few seconds after the Launcher answers.
        for _ in $(seq 1 90); do
          # -f: on NixOS the process is .plasmashell-wrapped (-x never matched).
          pid="$(pgrep -o -u dawo -f plasmashell || true)"
          [ -n "$pid" ] && break; sleep 1
        done
        sleep 5
        if [ -z "$uid" ] || [ -z "$pid" ]; then say "cli screenshot: no dawo desktop session"; return 0; fi
        # The session's own environment (Wayland display, D-Bus, PATH, XDG).
        mapfile -d "" -t envs < "/proc/$pid/environ"
        as_dawo() { runuser -u dawo -- env -i "''${envs[@]}" "$@"; }
        dir="/run/user/$uid/dawo-shots"; done_file="/run/user/$uid/launch-cli.done"
        rm -f "$done_file"
        as_dawo mkdir -p "$dir"
        as_dawo konsole --separate --nofork --hide-menubar --hide-tabbar --fullscreen \
          -p "Font=Monospace,15" -e ${cliDemo} 75 >/dev/null 2>&1 &
        kpid=$!
        for _ in $(seq 1 60); do [ -e "$done_file" ] && break; sleep 1; done
        if [ ! -e "$done_file" ]; then
          say "cli screenshot: the terminal did not run the commands within 60 s"
          kill "$kpid" 2>/dev/null; return 0
        fi
        sleep 3
        if as_dawo ${pkgs.kdePackages.spectacle}/bin/spectacle --background --nonotify --fullscreen \
             --output "$dir/launch-cli.png" >/dev/null 2>&1 && [ -s "$dir/launch-cli.png" ]; then
          say "cli screenshot: launch-cli.png saved"
        else
          say "cli screenshot: spectacle did not save launch-cli.png"
        fi
        # The terminal closes by itself after 75 s; make sure of it.
        for _ in $(seq 1 90); do kill -0 "$kpid" 2>/dev/null || break; sleep 1; done
        kill "$kpid" 2>/dev/null
        rm -f "$done_file"
        return 0
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
      # The command line for the README (#252), in the background: it never
      # fails or delays the run.
      cli_shot &

      # 2. The token protects start and stop.
      token="$(curl -sf "$api/" | sed -n 's/.*const TOKEN = "\([0-9a-f]*\)".*/\1/p')"
      [ -n "$token" ] || fail "no token in the Launcher page"
      code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$api/api/start/$env")"
      [ "$code" = 403 ] || fail "start without token answered $code, not 403"
      say "start without token refused (403)"
      # The automatic start (#238) is announced at boot: the round (#257).
      curl -sf "$api/api/cycle" | jq -e '.autostart.at | type == "number"' >/dev/null \
        || fail "no automatic start of the round announced: $(curl -sf "$api/api/cycle")"
      say "automatic start of the round announced"

      for round in 1 2; do
        if [ "$round" = 1 ]; then
          # 3a. Nobody presses anything: the Launcher starts it by itself (#238).
          wait_for 300 "automatic start" at_step 1
          [ "$(curl -sf "$api/api/cycle" | jq -r .env)" = "$env" ] || fail "the round did not start $env first"
          say "start 1: started automatically by the round (no button pressed)"
          # Only $env here (no internet for the others): the round stops,
          # $env goes on starting.
          curl -sf -X POST -H "X-Launcher-Token: $token" "$api/api/cycle/stop" >/dev/null || fail "stopping the round"
          wait_for 30 "the round stopped" round_off
          say "start 1: round stopped, $env goes on"
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
