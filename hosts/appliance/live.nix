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
      # The UTC clock as seconds since the epoch: the ISO boot test checks it
      # against the host's time (the RTC local-time warp, #124).
      say "report started (clock $(date -u +%s))"
      # Where the appliance data lives (live-data.nix, #109).
      for _ in $(seq 1 60); do [ -s /run/dawo-appliance/data ] && break; sleep 1; done
      say "data: $(cat /run/dawo-appliance/data 2>/dev/null || echo unknown)"
      if [ ! -e /dev/kvm ]; then
        # Real laptops often ship with VT-x/AMD-V disabled; a VM host may not
        # pass virtualisation through (VirtualBox on a Hyper-V host).
        say "WARNING no /dev/kvm: hardware virtualisation (VT-x/AMD-V) is off or not passed through; the Ubuntu guest and K3s cannot start"
      fi
      key=/var/lib/dawo-appliance/ssh/id_ed25519
      g() { ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR ops@192.168.150.10 "$@"; }
      deadline=$(( $(up) + ''${DAWO_LIVE_REPORT_TIMEOUT:-1800} ))
      desktop=no; guest=no; k3s=no
      skipped=""
      while [ "$(up)" -lt "$deadline" ]; do
        if [ -z "$skipped" ] && [ -s /run/dawo-appliance/guest-skipped ]; then
          skipped="$(cat /run/dawo-appliance/guest-skipped)"
          say "guest skipped: $skipped"
        fi
        if [ -n "$skipped" ] && [ "$desktop" = yes ]; then
          say "DONE ok (desktop only; guest skipped)"
          exit 0
        fi
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
  statusPage = pkgs.writeShellApplication {
    name = "dawo-appliance-status-page";
    runtimeInputs = with pkgs; [ coreutils gnused gnugrep curl systemd ];
    text = builtins.readFile ../../health/dawo-appliance-status-page.sh;
  };
  # Starts the page writer and opens the page once in the browser.
  statusApp = pkgs.writeShellApplication {
    name = "dawo-appliance-status";
    runtimeInputs = with pkgs; [ coreutils xdg-utils ];
    text = ''
      page="''${XDG_RUNTIME_DIR:-/tmp}/dawo-appliance-status.html"
      ${statusPage}/bin/dawo-appliance-status-page &
      for _ in $(seq 1 20); do [ -s "$page" ] && break; sleep 1; done
      xdg-open "file://$page" >/dev/null 2>&1 || true
      wait
    '';
  };
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
    ../../installer/live-payload.nix
    ./live-logs.nix
    ./live-data.nix
    ./live-mijnbureau.nix
  ];

  image.baseName = lib.mkForce "dawo-appliance-live";
  # Boot menu: "DAWO appliance live — NixOS <version>", and the debug entry
  # (specialisation below) says what it does.
  isoImage.prependToMenuLabel = "DAWO appliance live — ";
  isoImage.appendToMenuLabel = " — DEBUG (default for now): logs + screenshots to USB";
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
    # Room for Mijn Bureau's laptop profile (ADR 0007: ~7.3 GiB requests,
    # 11.3 GiB limits); fitToHost still keeps 6 GiB for the desktop.
    vcpus = lib.mkForce 8;
    memoryGiB = lib.mkForce 16;
    autostart = lib.mkForce true;
    imageOverride = pinnedImage;
    # Whatever laptop the stick is plugged into: size the guest to it, or
    # skip it with a reason (no VT-x, too little RAM) instead of failing.
    fitToHost = true;
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
  environment.systemPackages = [ report statusPage statusApp ];

  # Marker for the welcome/status window: this is the live USB, so it
  # mentions debug mode (health/dawo-appliance-welcome.sh).
  environment.etc."dawo-appliance/live".text = "live USB (ADR 0006)
";

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

  # Debug is the DEFAULT for now (maintainer, 2026-09-27: not stable enough
  # yet): desktop screenshots every 30 s plus the logs go to a DAWO_LOGS
  # stick (live-logs.nix), announced by a dialog at login. The second boot
  # menu entry turns the screenshots off (dawo.debug=0); the text logs still
  # go to a DAWO_LOGS stick when one is present.
  specialisation.nodebug.configuration = {
    boot.kernelParams = [ "dawo.debug=0" ];
    isoImage.appendToMenuLabel = lib.mkForce "";
    isoImage.configurationName = "— without debug screenshots";
  };

  # Demo Wi-Fi (issue #105, maintainer 2026-09-27): every live boot starts
  # without network, so DAWO's online app installs fail until someone types a
  # Wi-Fi password. The image knows one demo network, e.g. a phone hotspot
  # named "Dawo" with WPA2 password "DawoDawo". This is a deliberate, PUBLIC
  # demo credential, not a secret (docs/deviations.md D27). Low priority: any
  # network the user picks wins; anyone can offer a "Dawo" network, so this is
  # for demos only (traffic to Mijn Bureau is TLS).
  networking.networkmanager.ensureProfiles.profiles.dawo-demo = {
    connection = {
      id = "Dawo (demo)";
      type = "wifi";
      autoconnect = true;
      autoconnect-priority = -10;
    };
    wifi = {
      ssid = "Dawo";
      mode = "infrastructure";
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk = "DawoDawo";
    };
    ipv4.method = "auto";
    ipv6.method = "auto";
  };

  # The stick boots laptops that also run Windows, which keeps the hardware
  # clock in local time; NixOS keeps UTC. After a DAWO session Windows showed
  # the time 2 h off (CEST) until it synced (#115). Keep local time, as
  # Windows does.
  time.hardwareClockInLocalTime = lib.mkForce true;
  # Load the RTC driver in the initrd (#124). As a module loaded later in
  # stage 2 its hctosys set the clock from the RTC *as UTC* one second after
  # systemd had applied the local-time delta, so the laptop and the guest ran
  # 2 h ahead until NTP stepped them back; K3s took that jump badly.
  boot.initrd.kernelModules = [ "rtc_cmos" ];

  # Shut the guest down (never suspend: that writes its RAM to the tmpfs
  # root) and do not wait 5 minutes for it (#115).
  virtualisation.libvirtd.shutdownTimeout = lib.mkForce 60;

  # The power button shuts the live system down cleanly (D30). A live stick
  # is often left with just that button; the persistence test presses it
  # (ACPI power-down) and asserts a clean power-off (#115). In a Plasma
  # session PowerDevil holds logind's low-level handle-power-key lock (which
  # logind always honours) and by default only shows the logout screen, so
  # the action is set in PowerDevil's system-wide defaults (8 = shut down);
  # logind's own setting covers the time before and after the session.
  services.logind.settings.Login.HandlePowerKey = "poweroff";
  # While Mijn Bureau deploys (30-60 minutes) the status page must stay in
  # view and the machine awake (D32, #132): no dimming, no display-off and no
  # automatic suspend (a suspend pauses the deployment); on mains power
  # closing the lid does nothing either. The screen lock itself stays as DAWO
  # sets it (mandatory hardening: kscreenlockerrc [Daemon][$i] Autolock=true,
  # Timeout=5); relaxing it is the maintainer's call (#132).
  environment.etc."xdg/powerdevilrc".text = ''
    [AC][Display]
    DimDisplayWhenIdle=false
    TurnOffDisplayWhenIdle=false

    [AC][SuspendAndShutdown]
    AutoSuspendAction=0
    LidAction=0
    PowerButtonAction=8

    [Battery][Display]
    DimDisplayWhenIdle=false
    TurnOffDisplayWhenIdle=false

    [Battery][SuspendAndShutdown]
    AutoSuspendAction=0
    PowerButtonAction=8

    [LowBattery][SuspendAndShutdown]
    PowerButtonAction=8
  '';
  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";

  # No KWallet on the live USB (D31, #128): the session logs in automatically,
  # so pam_kwallet has no password to open a wallet with, and the first app
  # asking for a secret started KWallet's setup wizard (Blowfish/GPG, a new
  # password). A demo stick holds no user secrets worth a wallet.
  environment.etc."xdg/kwalletrc".text = ''
    [Wallet]
    Enabled=false
    First Use=false
  '';

  # One live status page instead of the static welcome window (#116): it
  # opens in the browser at login and updates itself (internet, storage,
  # virtual machine, Mijn Bureau with a progress bar, debug mode).
  environment.etc."xdg/autostart/dawo-appliance-welcome.desktop".text = lib.mkForce ''
    [Desktop Entry]
    Type=Application
    Name=DAWO appliance welcome (replaced by the live status page)
    Hidden=true
  '';
  environment.etc."xdg/autostart/dawo-appliance-status.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=DAWO appliance status
    Comment=Live status page: what works and what we are waiting for
    Exec=${statusApp}/bin/dawo-appliance-status
    OnlyShowIn=KDE;
    X-KDE-autostart-phase=2
  '';

  system.stateVersion = lib.mkDefault "26.05";
}
