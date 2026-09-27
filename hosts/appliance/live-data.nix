# Persistent data on the live USB stick (issue #109, ADR 0006).
#
# Mijn Bureau needs ~15-20 GB of guest disk that survives a reboot, and the
# guest SSH key and the appliance CA need Unix permissions that exFAT cannot
# store. So, when a USB filesystem labelled DAWO_LOGS exists (the stick the
# user prepared, docs/live-usb.md), this creates ONE FILE on it,
# `dawo-data.ext4`, formats THAT FILE as ext4 and loop-mounts it at
# /var/lib/dawo-appliance before any appliance service starts. Later boots
# reuse the file (after an fsck). It never partitions or formats a disk
# (AGENTS rule 7); it only writes a file into a filesystem the user created
# for this appliance.
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
    runtimeInputs = with pkgs; [ util-linux coreutils gnugrep e2fsprogs exfatprogs systemd ];
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
        mount "$dev" ${logsMnt} || ram "cannot mount DAWO_LOGS ($dev)"
      fi

      file=${logsMnt}/dawo-data.ext4
      if [ ! -f "$file" ]; then
        freeg="$(( $(df --output=avail -B1 ${logsMnt} | tail -n1) / 1073741824 ))"
        size=${toString cfg.sizeGiB}
        if [ "$((freeg - 2))" -lt "$size" ]; then size="$((freeg - 2))"; fi
        if [ "$size" -lt ${toString cfg.minGiB} ]; then
          ram "only ''${freeg} GiB free on DAWO_LOGS (need ${toString cfg.minGiB} GiB for dawo-data.ext4)"
        fi
        say "creating $file (''${size} GiB) on DAWO_LOGS"
        truncate -s "''${size}G" "$file.new"
        say "file allocated; formatting"
        mkfs.ext4 -q -F -L DAWO_DATA -m 0 -E lazy_itable_init=1,lazy_journal_init=1 "$file.new"
        say "formatted"
        mv "$file.new" "$file"
        created=yes
      else
        created=no
        # Repair after an unclean shutdown (a pulled stick, a power cut).
        e2fsck -p "$file" || say "e2fsck returned $? (continuing)"
      fi

      loop="$(losetup -f --show "$file")"
      mkdir -p ${stateDir}
      mount -o noatime "$loop" ${stateDir}
      # Directories and modes the appliance's tmpfiles rules create under it.
      systemd-tmpfiles --create --prefix=${stateDir} || true
      used="$(df --output=used -B1G ${stateDir} | tail -n1 | tr -d ' ')"
      sizeg="$(df --output=size -B1G ${stateDir} | tail -n1 | tr -d ' ')"
      if [ "$created" = yes ]; then
        echo "stick: created dawo-data.ext4 (''${sizeg} GiB)" > "$status"
      else
        echo "stick: reused dawo-data.ext4 (''${used} of ''${sizeg} GiB used)" > "$status"
      fi
      say "$(cat "$status")"
    '';
  };

  teardown = pkgs.writeShellScript "dawo-appliance-data-teardown" ''
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
    sizeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 40;
      description = "Size of dawo-data.ext4 on the DAWO_LOGS stick (smaller if the stick has less room).";
    };
    minGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = "Below this much room the data stays in RAM instead.";
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
