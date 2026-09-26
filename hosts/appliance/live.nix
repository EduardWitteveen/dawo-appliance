# Live USB variant of the appliance (ADR 0006, issue #93), first slice.
#
# The same appliance system as the installed host (DAWO workplace, libvirt,
# guest VM, health check), booted from a USB stick like a live CD. It never
# writes to the machine's internal disk: there is no disko layout here and no
# internal disk is mounted. The root filesystem is a tmpfs; the Nix store is
# the image's read-only squashfs.
#
# This first slice has NO data partition yet, so everything written at run
# time (guest overlay disk, K3s images) lives in RAM and is gone after a
# reboot. That is enough to see the desktop, the guest and K3s on a real
# laptop; Mijn Bureau needs the data partition (next slice) and the laptop
# profile.
#
# The installer stays available on the live system (ADR 0006 decision 4):
# `dawo-appliance-bootstrap` and disko-install come from live-payload.nix and
# the flake's liveInstallerExtras.
#
# Experimental and unofficial. Not for production.
{ modulesPath, lib, pkgs, config, ... }:

let
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  image = manifest.vm.image;
  # The pinned Ubuntu cloud image, verified by its manifest SHA-256 at build
  # time and carried on the stick: no 600 MB download on every live boot.
  pinnedImage = pkgs.fetchurl {
    url = "${image.base_url}${image.file}";
    sha256 = image.sha256;
  };

  # Per-boot report (ADR 0006 decision 3, first slice): each stage with the
  # seconds since boot, on the console, in the journal and in
  # /run/dawo-appliance/live-report.txt. The data partition (next slice) will
  # keep these across boots. `DAWO-LIVE:` lines are what the ISO boot test
  # (nix/tests/live-iso-boot.sh) waits for.
  report = pkgs.writeShellApplication {
    name = "dawo-appliance-live-report";
    runtimeInputs = with pkgs; [ coreutils gnugrep procps systemd openssh ];
    text = ''
      out=/run/dawo-appliance/live-report.txt
      mkdir -p /run/dawo-appliance
      : > "$out"
      up() { cut -d' ' -f1 /proc/uptime | cut -d. -f1; }
      say() {
        line="DAWO-LIVE: $* t=$(up)s"
        echo "$line" | tee -a "$out"
        # Also on the first serial port when there is one (the ISO boot test
        # reads it; on a laptop without a serial port this is a no-op).
        if [ -w /dev/ttyS0 ]; then echo "$line" > /dev/ttyS0 2>/dev/null || true; fi
      }
      say "report started"
      if [ ! -e /dev/kvm ]; then
        # Real laptops often ship with VT-x/AMD-V disabled; a VM host may not
        # pass virtualisation through (VirtualBox on a Hyper-V host).
        say "WARNING no /dev/kvm: hardware virtualisation (VT-x/AMD-V) is off or not passed through; the Ubuntu guest and K3s cannot start"
      fi
      key=/var/lib/dawo-appliance/ssh/id_ed25519
      g() { ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR ops@192.168.150.10 "$@"; }
      deadline=$(( $(up) + ''${DAWO_LIVE_REPORT_TIMEOUT:-1800} ))
      desktop=no; guest=no; k3s=no
      while [ "$(up)" -lt "$deadline" ]; do
        if [ "$desktop" = no ] && pgrep -u dawo -f plasmashell >/dev/null; then
          desktop=yes; say "desktop ready (plasma session for dawo)"
        fi
        if [ "$guest" = no ] && /run/current-system/sw/bin/dawo-appliance-guest-status >/dev/null 2>&1; then
          guest=yes; say "guest ssh ready"
        fi
        if [ "$guest" = yes ] && [ "$k3s" = no ] && g sudo k3s kubectl get node 2>/dev/null | grep -q ' Ready'; then
          k3s=yes; say "k3s node ready"
        fi
        if [ "$desktop" = yes ] && [ "$k3s" = yes ]; then
          say "DONE ok"
          exit 0
        fi
        sleep 5
      done
      say "DONE fail desktop=$desktop guest=$guest k3s=$k3s"
      /run/current-system/sw/bin/dawo-appliance-guest-status 2>&1 | tee -a "$out" || true
      exit 1
    '';
  };
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
    ../../installer/live-payload.nix
    ./live-logs.nix
  ];

  image.baseName = lib.mkForce "dawo-appliance-live";
  isoImage.volumeID = lib.mkForce "DAWO_LIVE";
  # Boot from USB sticks and DVDs on both UEFI and legacy BIOS machines.
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  # zstd: much faster to build than xz, slightly larger image.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  # No disko storage on a live medium: the iso-image module provides / and
  # the store. Never touch the internal disk.
  disko.enableConfig = lib.mkForce false;

  # The iso-image module brings its own boot loader (GRUB/syslinux on the
  # image); the workplace's installed-system boot loader does not apply.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;

  # The guest lives in RAM in this slice: keep it small enough to leave room
  # for the tmpfs root on a 32 GB laptop. K3s fits; Mijn Bureau does not yet.
  appliance.guest = {
    vcpus = lib.mkForce 6;
    memoryGiB = lib.mkForce 8;
    autostart = lib.mkForce true;
    imageOverride = pinnedImage;
  };

  # Messages on the laptop screen (tty0, last = the primary console) and on a
  # serial port for the boot test.
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];

  systemd.services.dawo-appliance-live-report = {
    description = "DAWO appliance live report: desktop, guest and K3s timings";
    wantedBy = [ "multi-user.target" ];
    after = [ "dawo-appliance-guest.service" "display-manager.service" ];
    path = [ config.systemd.package ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${report}/bin/dawo-appliance-live-report";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };
  environment.systemPackages = [ report ];

  # libvirt encrypts its secrets key with systemd-creds in "auto" mode, which
  # refuses on a live system: no TPM2 (or none usable) and the host key lives
  # on the tmpfs root ("TPM2 not available and host key located on temporary
  # file system"). libvirtd then never starts and neither does the guest.
  # Use the host key explicitly: on a live medium the key and the secrets it
  # protects are both in RAM and gone at power-off, so nothing is weakened.
  systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${pkgs.bash}/bin/bash -c 'umask 0077 && mkdir -p /var/lib/libvirt/secrets && (${pkgs.coreutils}/bin/dd if=/dev/random status=none bs=32 count=1 | ${config.systemd.package}/bin/systemd-creds encrypt --with-key=host --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key)'"
  ];

  system.stateVersion = lib.mkDefault "26.05";
}
