# Debug logs on a USB stick (ADR 0006 decision 3, #93).
#
# The maintainer wants to hand a stick back after a run so that a failed or
# slow boot can be debugged. Every 30 seconds, and once more at shutdown, this
# writes the progress report, the journal of this boot, the guest status, the
# guest's own logs and the hardware facts to a filesystem labelled DAWO_LOGS,
# then syncs.
#
# NON-DESTRUCTIVE: this never partitions or formats anything. It only writes
# files into an EXISTING filesystem that the user labelled DAWO_LOGS, and only
# when that filesystem sits on a USB disk. The user prepares it once, for
# example by formatting a second stick as FAT32/exFAT with the name DAWO_LOGS
# in Windows (docs/live-usb.md). Without such a filesystem, logs stay in RAM
# (/run/dawo-appliance) and nothing is written anywhere.
#
# Layout:
#   DAWO_LOGS/dawo-appliance/<UTC boot time>_<boot id>/
#     progress.txt   DAWO-LIVE stage lines with seconds since boot
#     journal.txt    journalctl -b (the whole boot so far)
#     guest.txt      guest status, the guest's serial console, and its
#                    cloud-init and K3s logs
#     health.log     the desktop's health check and dashboard opener log
#     network.txt    NetworkManager connections/devices, addresses, DNS, internet check
#     hardware.txt   model, firmware, CPU, memory, disks (once per boot)
#     screens/       debug mode (default for now): a screenshot every 30 s
#
# Experimental and unofficial. Not for production.
{ pkgs, ... }:

let
  mnt = "/run/dawo-logs";

  collect = pkgs.writeShellApplication {
    name = "dawo-appliance-logs-collect";
    runtimeInputs = with pkgs; [ util-linux coreutils gnugrep procps systemd openssh dmidecode pciutils networkmanager iproute2 curl ];
    text = ''
      if ! mountpoint -q ${mnt}; then
        dev="$(blkid -L DAWO_LOGS 2>/dev/null || true)"
        if [ -z "$dev" ]; then
          exit 0 # no DAWO_LOGS filesystem: keep logs in RAM only
        fi
        disk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1)"
        [ -n "$disk" ] || disk="$(basename "$dev")"
        if [ "$(lsblk -dno TRAN "/dev/$disk" 2>/dev/null)" != usb ]; then
          echo "dawo-logs: DAWO_LOGS on $dev is not on a USB disk; not writing to it" >&2
          exit 0
        fi
        mkdir -p ${mnt}
        mount -o sync "$dev" ${mnt}
      fi
      bootid="$(tr -d '-' < /proc/sys/kernel/random/boot_id | cut -c1-8)"
      stamp_file=/run/dawo-appliance/logs-dir
      mkdir -p /run/dawo-appliance
      if [ ! -s "$stamp_file" ]; then
        booted="$(( $(date +%s) - $(cut -d. -f1 /proc/uptime) ))"
        echo "${mnt}/dawo-appliance/$(date -u -d "@$booted" +%Y%m%dT%H%M%SZ)_$bootid" > "$stamp_file"
      fi
      dir="$(cat "$stamp_file")"
      mkdir -p "$dir"
      if [ ! -s "$dir/hardware.txt" ]; then
        {
          echo "== model"; dmidecode -s system-manufacturer 2>/dev/null || true; dmidecode -s system-product-name 2>/dev/null || true
          echo "== firmware"; if [ -d /sys/firmware/efi ]; then echo UEFI; else echo BIOS; fi
          echo "== cpu"; lscpu
          echo "== memory"; free -m
          echo "== disks"; lsblk -o NAME,SIZE,TRAN,TYPE,LABEL,FSTYPE,MODEL
          echo "== pci"; lspci
          echo "== kvm"; ls -l /dev/kvm 2>&1 || true
        } > "$dir/hardware.txt" 2>&1
      fi
      cp -f /run/dawo-appliance/live-report.txt "$dir/progress.txt" 2>/dev/null || true
      # The desktop's health check / dashboard opener log (health/README.md).
      cp -f /home/dawo/.local/state/dawo-appliance/health.log "$dir/health.log" 2>/dev/null || true
      journalctl -b --no-pager -o short-iso-precise > "$dir/journal.txt" 2>&1 || true
      if [ -z "''${DAWO_LOGS_FINAL:-}" ]; then
      {
        echo "== $(date -u +%FT%TZ) uptime $(cut -d' ' -f1 /proc/uptime)s"
        echo "== nmcli connections"; nmcli -f NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show 2>&1 || true
        echo "== nmcli devices"; nmcli device status 2>&1 || true
        echo "== addresses"; ip -brief address 2>&1 || true
        echo "== routes"; ip route 2>&1 || true
        echo "== dns"; resolvectl status 2>&1 | head -40 || true
        echo "== internet (flathub)"; curl -sS -o /dev/null -w "%{http_code} %{time_total}s
" --max-time 10 https://dl.flathub.org/repo/flathub.flatpakrepo 2>&1 || true
      } > "$dir/network.txt" 2>&1
      fi
      # Desktop screenshots (each copied once; see `shots` above).
      for d in /run/user/*/dawo-shots; do
        [ -d "$d" ] || continue
        mkdir -p "$dir/screens"
        cp -n "$d"/*.png "$dir/screens/" 2>/dev/null || true
      done
      if [ -z "''${DAWO_LOGS_FINAL:-}" ]; then
      {
        echo "== $(date -u +%FT%TZ) uptime $(cut -d' ' -f1 /proc/uptime)s"
        /run/current-system/sw/bin/dawo-appliance-guest-status 2>&1 || true
        echo "== guest serial console (tail)"
        tail -n 200 /var/log/libvirt/qemu/dawo-appliance-mb-console.log 2>&1 || true
        echo "== guest qemu log (tail)"
        tail -n 40 /var/log/libvirt/qemu/dawo-appliance-mb.log 2>&1 || true
        key=/var/lib/dawo-appliance/ssh/id_ed25519
        if [ -r "$key" ]; then
          g() { timeout 20 ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR ops@192.168.150.10 "$@"; }
          echo "== cloud-init status"; g cloud-init status --long 2>&1 || true
          echo "== k3s stage log"; g sudo cat /var/log/dawo-appliance-k3s-stage.log 2>&1 || true
          echo "== k3s nodes and pods"; g sudo k3s kubectl get node,pods -A -o wide 2>&1 || true
          echo "== cloud-init-output.log (tail)"; g sudo tail -n 300 /var/log/cloud-init-output.log 2>&1 || true
        fi
      } > "$dir/guest.txt" 2>&1
      fi
      sync
    '';
  };
  # Debug mode (the default boot entry for now; off with dawo.debug=0): a
  # screenshot of the desktop every 30 s (Spectacle, part of the DAWO
  # workplace), kept in RAM (last 60) and copied to the stick by the collector
  # below, for debugging and for documentation. Demo posture: anything on
  # screen, including the welcome dialog's password, ends up on the stick.
  shots = pkgs.writeShellScript "dawo-appliance-screenshots" ''
    set -u
    # Debug is on unless the boot entry says dawo.debug=0 (see live.nix).
    if grep -qw dawo.debug=0 /proc/cmdline; then exit 0; fi
    # The welcome/status window says that debug mode is on (#106).
    dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dawo-shots"
    mkdir -p "$dir"
    sleep 20
    while true; do
      ${pkgs.kdePackages.spectacle}/bin/spectacle --background --nonotify --fullscreen         --output "$dir/$(date +%Y%m%dT%H%M%S).png" >/dev/null 2>&1 || true
      ls -1t "$dir"/*.png 2>/dev/null | tail -n +61 | xargs -r rm -f
      sleep 30
    done
  '';
in
{
  environment.etc."xdg/autostart/dawo-appliance-screenshots.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=DAWO appliance debug screenshots
    Comment=Debug mode (default for now): screenshot every 30 s for the DAWO_LOGS stick
    Exec=${shots}
    OnlyShowIn=KDE;
    X-KDE-autostart-phase=2
    NoDisplay=true
  '';

  systemd.services.dawo-appliance-logs = {
    description = "Copy DAWO appliance debug logs to a DAWO_LOGS USB filesystem";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${collect}/bin/dawo-appliance-logs-collect";
    };
  };
  systemd.timers.dawo-appliance-logs = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };
  # One last copy at shutdown, so the final state is on the stick.
  systemd.services.dawo-appliance-logs-final = {
    description = "Final DAWO appliance debug log copy at shutdown";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = "${collect}/bin/dawo-appliance-logs-collect";
      # At shutdown the network and the guest are already going down: keep the
      # last real network.txt/guest.txt instead of overwriting them with a
      # "NetworkManager is not running" snapshot (seen on the Dynabook).
      Environment = [ "DAWO_LOGS_FINAL=1" ];
    };
  };
  environment.systemPackages = [ collect ];
}
