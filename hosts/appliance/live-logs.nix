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
#     guest.txt      guest status + the guest's cloud-init and K3s logs
#     hardware.txt   model, firmware, CPU, memory, disks (once per boot)
#
# Experimental and unofficial. Not for production.
{ pkgs, ... }:

let
  mnt = "/run/dawo-logs";

  collect = pkgs.writeShellApplication {
    name = "dawo-appliance-logs-collect";
    runtimeInputs = with pkgs; [ util-linux coreutils gnugrep procps systemd openssh dmidecode pciutils ];
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
      journalctl -b --no-pager -o short-iso-precise > "$dir/journal.txt" 2>&1 || true
      {
        echo "== $(date -u +%FT%TZ) uptime $(cut -d' ' -f1 /proc/uptime)s"
        /run/current-system/sw/bin/dawo-appliance-guest-status 2>&1 || true
        key=/var/lib/dawo-appliance/ssh/id_ed25519
        if [ -r "$key" ]; then
          g() { timeout 20 ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR ops@192.168.150.10 "$@"; }
          echo "== cloud-init status"; g cloud-init status --long 2>&1 || true
          echo "== k3s stage log"; g sudo cat /var/log/dawo-appliance-k3s-stage.log 2>&1 || true
          echo "== k3s nodes and pods"; g sudo k3s kubectl get node,pods -A -o wide 2>&1 || true
          echo "== cloud-init-output.log (tail)"; g sudo tail -n 300 /var/log/cloud-init-output.log 2>&1 || true
        fi
      } > "$dir/guest.txt" 2>&1
      sync
    '';
  };
in
{
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
    };
  };
  environment.systemPackages = [ collect ];
}
