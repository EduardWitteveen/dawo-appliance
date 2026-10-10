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
  # systemd's escaped unit name for /run/dawo-logs (systemd-escape -p).
  logsMountUnit = "run-dawo\\x2dlogs.mount";
  qemuGid = toString config.users.groups.qemu-libvirtd.gid;
  stateDir = "/var/lib/dawo-appliance";
  seedSectors = cfg.seedMiB * 2048;

  setup = pkgs.writeShellApplication {
    name = "dawo-appliance-data-setup";
    runtimeInputs = with pkgs; [ util-linux coreutils findutils gnugrep e2fsprogs exfatprogs systemd getent ];
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

      # The disk image (dawo-appliance-live.img, #192), written by Rufus or
      # Etcher, carries a small, empty DAWO_LOGS seed (MBR entry 3, exactly
      # seedMiB) right after the ISO and leaves the rest of the USB disk
      # unallocated. Grow the seed to the end of that disk, once: only while
      # it still has the seed's size and holds no files, so nothing is lost
      # (the stick tools never make a partition this small).
      grown=""
      part="$(basename "$dev")"
      sys=/sys/class/block/$part
      if ! mountpoint -q ${logsMnt} && [ "$part" != "$disk" ] \
        && [ "$(cat "$sys/partition" 2>/dev/null)" = 3 ] \
        && [ "$(cat "$sys/size")" -eq ${toString seedSectors} ]; then
        start="$(cat "$sys/start")"
        total="$(cat "/sys/class/block/$disk/size")"
        new=$(( total - start ))
        [ "$new" -le 4294967295 ] || new=4294967295 # an MBR entry ends at 2 TiB
        # The MBR entry on the disk must be the partition the kernel sees.
        e3="$(dd if="/dev/$disk" bs=1 skip=478 count=16 status=none | od -An -v -tu1 | tr -s ' \n' ' ')"
        read -r _ _ _ _ e3type _ _ _ s0 s1 s2 s3 c0 c1 c2 c3 <<< "$e3"
        e3start=$(( s0 + (s1 << 8) + (s2 << 16) + (s3 << 24) ))
        e3count=$(( c0 + (c1 << 8) + (c2 << 16) + (c3 << 24) ))
        files=unknown
        probe="$(mktemp -d)"
        if mount -o ro "$dev" "$probe"; then
          files="$(find "$probe" -mindepth 1 -maxdepth 1 ! -name 'System Volume Information' | wc -l)"
          umount "$probe"
        fi
        rmdir "$probe"
        if [ "$e3type" = 7 ] && [ "$e3start" = "$start" ] && [ "$e3count" = ${toString seedSectors} ] \
          && [ "$files" = 0 ] && [ $(( new - e3count )) -ge 2097152 ]; then
          say "growing the empty DAWO_LOGS seed on /dev/$disk: $e3count -> $new sectors"
          printf '%b' "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((new & 255)) $(((new >> 8) & 255)) $(((new >> 16) & 255)) $(((new >> 24) & 255)))" \
            | dd of="/dev/$disk" bs=1 seek=490 conv=notrunc,fsync status=none
          # The ISO on the same disk is in use, so the whole table cannot be
          # re-read; resize just this (unmounted) partition in the kernel.
          resizepart "/dev/$disk" 3 "$new"
          udevadm settle
          [ "$(cat "$sys/size")" -eq "$new" ] || ram "growing DAWO_LOGS failed (kernel still sees $(cat "$sys/size") sectors)"
          mkfs.exfat -q -L DAWO_LOGS "$dev" >/dev/null
          udevadm settle
          grown="; DAWO_LOGS grown to the end of the USB disk"
          say "DAWO_LOGS grown to $(( new / 2097152 )) GiB"
        else
          say "DAWO_LOGS has the seed size but is not grown (entry type $e3type, start $e3start/$start, files $files)"
        fi
      fi

      # Mounted through the systemd unit below (not a bare mount), so systemd
      # unmounts the stick only after this service and the guest have
      # stopped (#115: the stick vanished under the running guest).
      if ! mountpoint -q ${logsMnt}; then
        if ! systemctl start "$(systemd-escape -p --suffix=mount ${logsMnt})"; then
          # Enough to see why on the console and in the journal.
          blkid -p "$dev" || true
          journalctl -b --no-pager -n 15 -u "$(systemd-escape -p --suffix=mount ${logsMnt})" || true
          fsck.exfat -n "$dev" 2>&1 | tail -n 5 || true
          ram "cannot mount DAWO_LOGS ($dev)"
        fi
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
        echo "stick: created dawo-data.ext4 + dawo-images (''${freeg} GiB free$grown)" > "$status"
      else
        echo "stick: reused dawo-data.ext4 + dawo-images (guest disk ''${imgg:-0} GiB, ''${freeg} GiB free)" > "$status"
      fi
      say "$(cat "$status")"
    '';
  };

  teardown = pkgs.writeShellScript "dawo-appliance-data-teardown" ''
    # A guest QEMU still using the disk (libvirt-guests timed out): stop it.
    for pid in $(${pkgs.procps}/bin/pgrep -f 'qemu.*dawo-appliance-mb' || true); do
      kill -TERM "$pid" 2>/dev/null || true
    done
    for _ in $(seq 1 15); do ${pkgs.procps}/bin/pgrep -f 'qemu.*dawo-appliance-mb' >/dev/null || break; sleep 1; done
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
    seedMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 64;
      description = "Size of the empty DAWO_LOGS seed in the disk image (nix/live-img.nix); a DAWO_LOGS of exactly this size, still empty, is grown to the end of its USB disk at boot.";
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
      # After the stick's mount unit: at shutdown this service (and so the
      # guest disk) is stopped before the stick is unmounted.
      after = [ "local-fs.target" "systemd-udev-settle.service" logsMountUnit ];
      wants = [ "systemd-udev-settle.service" ];
      # Also before libvirt: at shutdown libvirt-guests shuts the guest down
      # and libvirtd stops BEFORE the data is unmounted (#115).
      before = stateUsers ++ [ "libvirtd.service" "libvirt-guests.service" ];
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

    # The DAWO_LOGS stick as a real systemd mount (started on demand by the
    # data service and the log collector). exFAT/FAT have no per-file owners:
    # owner root, group qemu-libvirtd (QEMU opens the guest disk); others may
    # read, so the desktop user can browse the logs and screenshots in the file
    # manager but not change or delete anything (#147). That user is the
    # machine's administrator anyway (wheel, libvirtd), so reading the data
    # file exposes nothing new; demo posture, see docs/live-usb.md.
    systemd.mounts = [{
      what = "/dev/disk/by-label/DAWO_LOGS";
      where = logsMnt;
      type = "auto";
      options = "uid=0,gid=${qemuGid},fmask=0113,dmask=0002,nofail";
    }];

    environment.systemPackages = [ setup ];
  };
}
