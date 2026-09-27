# Persistent data on the live USB stick (issue #109, ADR 0006).
#
# Mijn Bureau needs ~15-20 GB of guest disk that survives a reboot, and the
# guest SSH key and the appliance CA need Unix permissions that exFAT cannot
# store. So, when a USB filesystem labelled DAWO_LOGS exists (the stick the
# user prepared, docs/live-usb.md), this uses two things on it:
#   - `dawo-data.ext4`, a SMALL file (1 GiB) formatted as ext4 and
#     loop-mounted at /var/lib/dawo-appliance: SSH key, CA, seed;
#   - the directory `dawo-images/`, bind-mounted at
#     /var/lib/dawo-appliance/images: the guest's qcow2 disk, a plain file on
#     exFAT that grows with actual use.
# No large preallocated file (issue #113): on exFAT every write beyond the
# valid data length zero-fills the gap, so a 40 GiB ext4 file meant ~40 GB of
# zeros on the very stick the system runs from, which starved the Dell for
# 15-20 minutes. Later boots reuse both (after an fsck of the small file). It
# never partitions or formats a disk (AGENTS rule 7); it only writes files
# into a filesystem the user created for this appliance.
#
# Without a DAWO_LOGS filesystem, or with too little room on it, nothing
# changes: /var/lib/dawo-appliance stays on the RAM root, as before. The
# status window says which of the two applies (/run/dawo-appliance/data).
#
# Experimental and unofficial. Not for production.
{ pkgs, lib, config, ... }:

let
  cfg = config.appliance.live.data;
  logsMnt = "/run/dawo-logs";
  stateDir = "/var/lib/dawo-appliance";

  setup = pkgs.writeShellApplication {
    name = "dawo-appliance-data-setup";
    runtimeInputs = with pkgs; [ util-linux coreutils gnugrep e2fsprogs exfatprogs systemd getent ];
    text = ''
      status=/run/dawo-appliance/data
      mkdir -p /run/dawo-appliance
      say() { echo "dawo-appliance-data: $* (t=$(cut -d. -f1 /proc/uptime)s)"; }
      ram() { echo "ram: $1" > "$status"; say "keeping $1: data stays in RAM"; exit 0; }

      # The DAWO_LOGS filesystem (udev may still be settling at this point).
      dev=""
      for _ in $(seq 1 ${toString cfg.waitSeconds}); do
        dev="$(blkid -L DAWO_LOGS 2>/dev/null || true)"
        [ -n "$dev" ] && break
        sleep 1
      done
      [ -n "$dev" ] || ram "no DAWO_LOGS stick found"
      say "found DAWO_LOGS at $dev"
      disk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1)"
      [ -n "$disk" ] || disk="$(basename "$dev")"
      [ "$(lsblk -dno TRAN "/dev/$disk" 2>/dev/null)" = usb ] || ram "DAWO_LOGS on $dev is not on a USB disk"

      if ! mountpoint -q ${logsMnt}; then
        mkdir -p ${logsMnt}
        # exFAT has no per-file owners or modes: owner root, group
        # qemu-libvirtd, so libvirt's QEMU (uid qemu-libvirtd) can open the
        # guest disk in dawo-images/, and nobody else can read the stick here.
        qgid="$(getent group qemu-libvirtd | cut -d: -f3)"
        mount -o "uid=0,gid=''${qgid:-0},fmask=0117,dmask=0007" "$dev" ${logsMnt} || ram "cannot mount DAWO_LOGS ($dev)"
      fi
      freeg="$(( $(df --output=avail -B1 ${logsMnt} | tail -n1) / 1073741824 ))"

      file=${logsMnt}/dawo-data.ext4
      rm -f "$file.new"   # left over from an interrupted first boot
      if [ ! -f "$file" ]; then
        if [ "$freeg" -lt ${toString cfg.minGiB} ]; then
          ram "only ''${freeg} GiB free on DAWO_LOGS (need ${toString cfg.minGiB} GiB for the guest disk)"
        fi
        say "creating $file (${toString cfg.stateMiB} MiB) on DAWO_LOGS"
        truncate -s ${toString cfg.stateMiB}M "$file.new"
        mkfs.ext4 -q -F -L DAWO_DATA -m 0 "$file.new"
        mv "$file.new" "$file"
        say "formatted"
        created=yes
      else
        created=no
        # Repair after an unclean shutdown (a pulled stick, a power cut).
        e2fsck -p "$file" || say "e2fsck returned $? (continuing)"
      fi

      loop="$(losetup -f --show "$file")"
      mkdir -p ${stateDir}
      mount -o noatime "$loop" ${stateDir}
      # The guest disk: a plain, growing qcow2 file in dawo-images/ on the stick.
      mkdir -p ${logsMnt}/dawo-images ${stateDir}/images
      mount --bind ${logsMnt}/dawo-images ${stateDir}/images
      # Directories and modes the appliance's tmpfiles rules create under it.
      systemd-tmpfiles --create --prefix=${stateDir} || true
      imgg="$(du -s -BG ${logsMnt}/dawo-images 2>/dev/null | cut -f1 | tr -d G)"
      if [ "$created" = yes ]; then
        echo "stick: created dawo-data.ext4 + dawo-images (''${freeg} GiB free)" > "$status"
      else
        echo "stick: reused dawo-data.ext4 + dawo-images (guest disk ''${imgg:-0} GiB, ''${freeg} GiB free)" > "$status"
      fi
      say "$(cat "$status")"
    '';
  };

  teardown = pkgs.writeShellScript "dawo-appliance-data-teardown" ''
    ${pkgs.coreutils}/bin/sync
    ${pkgs.util-linux}/bin/mountpoint -q ${stateDir}/images && { ${pkgs.util-linux}/bin/umount ${stateDir}/images || ${pkgs.util-linux}/bin/umount -l ${stateDir}/images; }
    ${pkgs.util-linux}/bin/mountpoint -q ${stateDir} || exit 0
    dev="$(${pkgs.util-linux}/bin/findmnt -no SOURCE ${stateDir})"
    ${pkgs.coreutils}/bin/sync
    ${pkgs.util-linux}/bin/umount ${stateDir} || ${pkgs.util-linux}/bin/umount -l ${stateDir}
    case "$dev" in /dev/loop*) ${pkgs.util-linux}/bin/losetup -d "$dev" || true ;; esac
  '';

  # Everything that keeps state under /var/lib/dawo-appliance. Not
  # dawo-appliance-set-password: it orders before the display manager, so
  # waiting for the data file would hold up the desktop (seen: 149 s instead
  # of 20 s on the first boot), and the live USB ships no install-time
  # password files anyway.
  stateUsers = [
    "dawo-appliance-ca.service"
    "dawo-appliance-guest-image.service"
    "dawo-appliance-guest-network.service"
    "dawo-appliance-guest.service"
  ];
in
{
  options.appliance.live.data = {
    stateMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1024;
      description = "Size of dawo-data.ext4 (SSH key, CA, seed). Kept small: exFAT zero-fills a new file as it is written (#113).";
    };
    minGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = "Free space on DAWO_LOGS needed for the guest disk to grow into; below it the data stays in RAM.";
    };
    waitSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 20;
      description = "How long to wait for the DAWO_LOGS stick to appear at boot.";
    };
  };

  config = {
    systemd.services = lib.mkMerge [
      # The state users wait for the data mount (or its decision to stay in RAM).
      (lib.genAttrs (map (lib.removeSuffix ".service") stateUsers) (_: {
        after = [ "dawo-appliance-data.service" ];
        wants = [ "dawo-appliance-data.service" ];
      }))
      { dawo-appliance-data = {
      description = "Persistent appliance data on the USB stick (dawo-data.ext4 on DAWO_LOGS)";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" "systemd-udev-settle.service" ];
      wants = [ "systemd-udev-settle.service" ];
      before = stateUsers;
      unitConfig.DefaultDependencies = false;
      conflicts = [ "shutdown.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${setup}/bin/dawo-appliance-data-setup";
        ExecStop = "${teardown}";
        TimeoutStartSec = "10min";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      }; }
    ];

    environment.systemPackages = [ setup ];
  };
}
