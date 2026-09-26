# The Ubuntu 24.04 guest VM and its network on the appliance host (Slice 4a,
# ADR 0004). An ADDITION on top of the DAWO workplace (ADR 0003): nothing here
# touches a user-facing upstream option.
#
# What this module provides, all idempotent and re-run at every boot:
#
# 1. dawo-appliance-guest-network.service — the libvirt network
#    `dawo-appliance` (NAT, 192.168.150.0/24, bridge virbr-dawo): a fixed DHCP
#    lease for the guest MAC -> 192.168.150.10, and libvirt's dnsmasq as the
#    single DNS authority for the base domain (wildcard
#    `address=/dawo.internal/192.168.150.10`). Defined from
#    vm/ubuntu-2404/network.xml.in; redefined only when that XML changes.
#
# 2. Host name resolution — a systemd-resolved DNS delegate (systemd >= 258,
#    `services.resolved.dnsDelegates`): queries for `~dawo.internal` go to the
#    bridge address 192.168.150.1 regardless of link state (a per-link
#    `resolvectl` rule would be ignored while the bridge has no carrier, i.e.
#    while the guest is down) and independent of NetworkManager, which only
#    manages its own links.
#
# 3. dawo-appliance-guest-image.service — downloads the pinned Ubuntu cloud
#    image (manifest `vm.image`: URL, size and SHA-256 are read from the
#    manifest JSON, the single source of truth), verifies it (hard failure on
#    mismatch), keeps it under /var/lib/dawo-appliance/images/ (nodatacow on
#    Btrfs) and creates the guest's qcow2 overlay disk (200 GiB virtual) once.
#    `appliance.guest.imageOverride` skips the download (tests, development).
#
# 4. dawo-appliance-guest.service — generates the operator SSH key pair ON THE
#    HOST once (root-only), renders cloud-init user-data (template in
#    vm/ubuntu-2404/) with that public key and the appliance CA if present,
#    builds the NoCloud seed ISO, defines the libvirt domain `dawo-appliance-mb`
#    (q35 + UEFI, virtio, fixed MAC, serial console) from
#    vm/ubuntu-2404/domain.xml.in, flags it for autostart and starts it.
#
# 5. `dawo-appliance-guest-status` — prints domain state, lease, resolution and
#    whether `ssh ops@192.168.150.10 true` works.
#
# Contract with hosts/appliance/appliance-ca.nix (Slice 4b): the CA certificate
# at `appliance.guest.caCertFile` is injected as cloud-init `ca_certs` when the
# file exists; the guest unit orders After=/Wants= dawo-appliance-ca.service and
# tolerates its absence. The K3s stage inside the guest is a marked placeholder
# (Slice 5). No secrets in Git: key pair and CA are generated per installation.
{ config, lib, pkgs, ... }:

let
  cfg = config.appliance.guest;
  net = cfg.network;

  # The manifest is the source of truth for every pin used here.
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  vmSpec = manifest.vm;
  image = vmSpec.image;
  baseDomain = manifest.mijn_bureau.base_domain.value;

  stateDir = "/var/lib/dawo-appliance";
  imagesDir = "${stateDir}/images";
  guestDir = "${stateDir}/guest";
  sshDir = "${stateDir}/ssh";
  sshKey = "${sshDir}/id_ed25519";

  # The base image carries its serial in the file name so that a re-pin never
  # overwrites the backing file of an existing overlay.
  baseImage = "${imagesDir}/${lib.removeSuffix ".img" image.file}-${image.serial}.img";
  imageUrl = "${image.base_url}${image.file}";
  overlayDisk = "${imagesDir}/${vmSpec.name}.qcow2";
  seedIso = "${guestDir}/seed.iso";
  renderedUserData = "${guestDir}/user-data";

  guestHostname = "mb";
  guestFqdn = "${guestHostname}.${baseDomain}";

  # Documented Mijn Bureau hostnames (ADR 0004); the wildcard covers the rest.
  dnsNames = [
    guestHostname
    "id"
    "bureaublad"
    "nextcloud"
    "collabora"
    "element"
    "matrix"
    "meet"
    "livekit"
    "docs"
    "grist"
    "drive"
    "conversations"
    "openproject"
  ];

  networkXml = pkgs.replaceVars ../../vm/ubuntu-2404/network.xml.in {
    NETWORK_NAME = net.name;
    BRIDGE = net.bridge;
    DOMAIN = baseDomain;
    HOST_ADDRESS = net.hostAddress;
    NETMASK = "255.255.255.0";
    DHCP_RANGE_START = "192.168.150.100";
    DHCP_RANGE_END = "192.168.150.199";
    GUEST_ADDRESS = net.guestAddress;
    GUEST_MAC = net.guestMac;
    GUEST_HOSTNAME = guestHostname;
    DNS_HOSTNAMES = lib.concatMapStringsSep "\n"
      (n: "      <hostname>${n}.${baseDomain}</hostname>")
      dnsNames;
  };

  domainXml = pkgs.replaceVars ../../vm/ubuntu-2404/domain.xml.in {
    NAME = vmSpec.name;
    MEMORY_GIB = toString cfg.memoryGiB;
    VCPUS = toString cfg.vcpus;
    OVERLAY_DISK = overlayDisk;
    SEED_ISO = seedIso;
    NETWORK_NAME = net.name;
    GUEST_MAC = net.guestMac;
  };

  networkConfig = pkgs.replaceVars ../../vm/ubuntu-2404/network-config.yaml.in {
    GUEST_MAC = net.guestMac;
    GUEST_ADDRESS = net.guestAddress;
  };

  # Runtime templates (rendered by the guest service, not by Nix).
  userDataTemplate = ../../vm/ubuntu-2404/user-data.yaml.in;
  metaDataTemplate = ../../vm/ubuntu-2404/meta-data.in;

  # Tools the services need on PATH.
  servicePath = with pkgs; [
    config.virtualisation.libvirtd.package
    qemu-utils
    cdrkit
    openssh
    curl
    coreutils
    gnused
    gawk
    gnugrep
    e2fsprogs
    util-linux
  ];

  status = pkgs.writeShellApplication {
    name = "dawo-appliance-guest-status";
    runtimeInputs = with pkgs; [ config.virtualisation.libvirtd.package openssh systemd gawk gnugrep coreutils ];
    text = ''
      # Health helper for the appliance guest (Slice 4a). Exit 0 when the guest
      # answers over SSH, 1 otherwise. Run as root (the key is root-only).
      export LIBVIRT_DEFAULT_URI=qemu:///system
      name=${lib.escapeShellArg vmSpec.name}
      netname=${lib.escapeShellArg net.name}
      mac=${lib.escapeShellArg net.guestMac}
      ip=${lib.escapeShellArg net.guestAddress}
      key=${lib.escapeShellArg sshKey}

      state="$(virsh domstate "$name" 2>&1 | head -n1 || true)"
      echo "domain:   $name  state: $state"
      if virsh net-info "$netname" >/dev/null 2>&1; then
        active="$(virsh net-info "$netname" | awk '/^Active:/ {print $2}')"
      else
        active="undefined"
      fi
      echo "network:  $netname  active: $active  bridge: ${net.bridge}  host: ${net.hostAddress}"
      lease="$(virsh net-dhcp-leases "$netname" 2>/dev/null | awk -v m="$mac" 'tolower($3)==m {print $5}' | head -n1)"
      echo "lease:    ''${lease:-none}  (expected $ip/24)"
      echo "resolve:  $(resolvectl query ${lib.escapeShellArg guestFqdn} 2>&1 | head -n1)"
      if [ ! -r "$key" ]; then
        echo "ssh:      cannot read $key (run as root)"
        exit 1
      fi
      # accept-new (not "no"): pin the guest's host key on first contact and
      # verify it after, like health/dawo-appliance-health.sh does — "no" would
      # silently trust whatever key answers on $ip, including a spoofed guest
      # on the same NAT segment.
      if ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=accept-new \
           -o LogLevel=ERROR "ops@$ip" true 2>/dev/null; then
        echo "ssh:      ok (ops@$ip)"
        exit 0
      fi
      echo "ssh:      not reachable (ops@$ip)"
      exit 1
    '';
  };
in
{
  options.appliance.guest = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Define and run the Ubuntu 24.04 guest VM and its network on the appliance host.";
    };

    vcpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = vmSpec.min_vcpu;
      defaultText = lib.literalExpression "manifest.vm.min_vcpu";
      description = "vCPUs for the guest. The default is the manifest minimum for Mijn Bureau; a development host may use less.";
    };

    memoryGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = vmSpec.min_ram_gib;
      defaultText = lib.literalExpression "manifest.vm.min_ram_gib";
      description = "RAM for the guest in GiB. The default is the manifest minimum for Mijn Bureau; a development host may use less.";
    };

    diskSizeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 200;
      description = "Virtual size of the guest's qcow2 overlay disk (thin; grows with use).";
    };

    imageOverride = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Use this local qcow2/raw image as the guest's base image instead of
        downloading the pinned Ubuntu cloud image. For tests and development
        only; the checksum in the manifest is not applied to it.
      '';
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Flag the domain for libvirt autostart and start it from dawo-appliance-guest.service.";
    };

    caCertFile = lib.mkOption {
      type = lib.types.str;
      default = "${stateDir}/ca/ca.crt";
      description = "The appliance CA certificate (hosts/appliance/appliance-ca.nix); injected as cloud-init ca_certs when the file exists.";
    };

    network = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "dawo-appliance";
        readOnly = true;
        description = "libvirt network name.";
      };
      bridge = lib.mkOption {
        type = lib.types.str;
        default = "virbr-dawo";
        readOnly = true;
        description = "Bridge interface of the libvirt network.";
      };
      hostAddress = lib.mkOption {
        type = lib.types.str;
        default = "192.168.150.1";
        readOnly = true;
        description = "Host (bridge) address; the DNS server for the base domain.";
      };
      guestAddress = lib.mkOption {
        type = lib.types.str;
        default = "192.168.150.10";
        readOnly = true;
        description = "Fixed DHCP lease of the guest; every *.dawo.internal name resolves here.";
      };
      guestMac = lib.mkOption {
        type = lib.types.str;
        default = "52:54:00:da:00:10";
        readOnly = true;
        description = "Fixed MAC of the guest's NIC (matches the DHCP host entry).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # The host reaches the guest directly on the bridge (443/80/UDP LiveKit).
    networking.firewall.trustedInterfaces = [ net.bridge ];

    # Host resolution for the base domain (ADR 0004): link-independent, does
    # not touch the resolver configuration for anything else.
    services.resolved.dnsDelegates.${net.name} = {
      Delegate = {
        DNS = net.hostAddress;
        Domains = "~${baseDomain}";
        DefaultRoute = false;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${imagesDir} 0755 root root -"
      "d ${guestDir} 0755 root root -"
      "d ${sshDir} 0700 root root -"
    ];

    environment.systemPackages = [ status ];

    systemd.services.dawo-appliance-guest-network = {
      description = "Define and start the appliance's libvirt network (${net.name})";
      wantedBy = [ "multi-user.target" ];
      requires = [ "libvirtd.service" ];
      after = [ "libvirtd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      environment.LIBVIRT_DEFAULT_URI = "qemu:///system";
      path = servicePath;
      script = ''
        set -euo pipefail
        name=${lib.escapeShellArg net.name}
        xml=${networkXml}
        stamp=${guestDir}/network.xml.sha256
        mkdir -p ${guestDir}
        want="$(sha256sum "$xml" | cut -d' ' -f1)"
        have="$(cat "$stamp" 2>/dev/null || true)"

        is_active() { virsh net-info "$name" 2>/dev/null | grep -q '^Active: *yes'; }

        if virsh net-info "$name" >/dev/null 2>&1; then
          if [ "$want" != "$have" ]; then
            echo "dawo-appliance-guest-network: definition of $name changed; redefining"
            uuid="$(virsh net-uuid "$name")"
            tmp="$(mktemp)"
            sed "s|<name>$name</name>|&\n  <uuid>$uuid</uuid>|" "$xml" > "$tmp"
            if is_active; then virsh net-destroy "$name"; fi
            virsh net-define "$tmp"
            rm -f "$tmp"
          else
            echo "dawo-appliance-guest-network: $name already defined, unchanged"
          fi
        else
          echo "dawo-appliance-guest-network: defining $name from $xml"
          virsh net-define "$xml"
        fi
        echo "$want" > "$stamp"
        virsh net-autostart "$name" >/dev/null
        if ! is_active; then
          virsh net-start "$name"
        fi
        echo "dawo-appliance-guest-network: $name active on ${net.bridge} (${net.hostAddress}/24, guest ${net.guestAddress}, *.${baseDomain} -> guest)"
      '';
    };

    systemd.services.dawo-appliance-guest-image = {
      description = "Download and verify the pinned Ubuntu 24.04 cloud image; create the guest disk";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # A 600 MB download on a slow line; upstream disables wait-online, so
        # curl's own retries also cover "network not up yet".
        TimeoutStartSec = "2h";
      };
      path = servicePath;
      script = ''
        set -euo pipefail
        mkdir -p ${imagesDir}
        # Disk images on Btrfs: no copy-on-write (checksum/fragmentation cost).
        # Only affects files created afterwards; harmless elsewhere.
        chattr +C ${imagesDir} 2>/dev/null || true

        ${if cfg.imageOverride != null then ''
          base=${lib.escapeShellArg (toString cfg.imageOverride)}
          echo "dawo-appliance-guest-image: using appliance.guest.imageOverride = $base (no download, no checksum)"
          test -s "$base" || { echo "dawo-appliance-guest-image: override image $base missing or empty" >&2; exit 1; }
        '' else ''
          base=${baseImage}
          expected=${image.sha256}
          expected_size=${toString image.size_bytes}
          if [ -s "$base" ] && [ "$(cat "$base.sha256" 2>/dev/null || true)" = "$expected" ]; then
            echo "dawo-appliance-guest-image: $base present and verified earlier (sha256 $expected)"
          else
            rm -f "$base" "$base.sha256"
            echo "dawo-appliance-guest-image: downloading ${imageUrl} (serial ${image.serial}, $expected_size bytes)"
            curl --fail --location --silent --show-error \
              --retry 20 --retry-delay 15 --retry-all-errors --retry-max-time 3600 \
              --output "$base.part" ${lib.escapeShellArg imageUrl}
            size="$(stat -c %s "$base.part")"
            if [ "$size" != "$expected_size" ]; then
              rm -f "$base.part"
              echo "dawo-appliance-guest-image: SIZE MISMATCH: got $size bytes, manifest says $expected_size; refusing the image" >&2
              exit 1
            fi
            actual="$(sha256sum "$base.part" | cut -d' ' -f1)"
            if [ "$actual" != "$expected" ]; then
              rm -f "$base.part"
              echo "dawo-appliance-guest-image: CHECKSUM MISMATCH: got $actual, manifest says $expected; refusing the image" >&2
              exit 1
            fi
            mv -f "$base.part" "$base"
            echo "$expected" > "$base.sha256"
            chmod 0644 "$base" "$base.sha256"
            echo "dawo-appliance-guest-image: verified sha256 $expected"
          fi
        ''}

        overlay=${overlayDisk}
        if [ -s "$overlay" ]; then
          backing="$(qemu-img info --output=json "$overlay" | grep -o '"backing-filename": *"[^"]*"' | head -n1 | sed 's/.*: *"//; s/"$//')"
          echo "dawo-appliance-guest-image: guest disk $overlay exists (backing: ''${backing:-?}); keeping it"
          if [ -n "$backing" ] && [ "$backing" != "$base" ]; then
            echo "dawo-appliance-guest-image: NOTE: the pinned base image is $base but the guest disk still uses $backing; remove $overlay to rebuild the guest from the new image"
          fi
        else
          echo "dawo-appliance-guest-image: creating guest disk $overlay (${toString cfg.diskSizeGiB} GiB virtual, backing $base)"
          # umask first: qemu-img must never create the file world/group
          # readable even for the instant before a separate chmod would fix it.
          (umask 0177 && qemu-img create -q -f qcow2 -b "$base" -F qcow2 "$overlay" ${toString cfg.diskSizeGiB}G)
        fi
      '';
    };

    systemd.services.dawo-appliance-guest = {
      description = "Define and start the Ubuntu 24.04 guest (${vmSpec.name}): SSH key, cloud-init seed, libvirt domain";
      wantedBy = [ "multi-user.target" ];
      requires = [ "libvirtd.service" "dawo-appliance-guest-network.service" ];
      # The CA is optional here (Slice 4b module); the image is needed only to
      # start, not to define.
      wants = [ "dawo-appliance-ca.service" "dawo-appliance-guest-image.service" ];
      after = [
        "libvirtd.service"
        "dawo-appliance-guest-network.service"
        "dawo-appliance-ca.service"
        "dawo-appliance-guest-image.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      environment.LIBVIRT_DEFAULT_URI = "qemu:///system";
      path = servicePath;
      script = ''
        set -euo pipefail
        name=${lib.escapeShellArg vmSpec.name}
        mkdir -p ${guestDir}
        install -d -m 0700 ${sshDir}

        # 1. Operator key pair, generated on the host once, never in Git.
        if [ ! -s ${sshKey} ]; then
          echo "dawo-appliance-guest: generating the operator SSH key ${sshKey}"
          rm -f ${sshKey} ${sshKey}.pub
          ssh-keygen -q -t ed25519 -N "" -C "ops@dawo-appliance" -f ${sshKey}
        fi
        chmod 0600 ${sshKey}
        chmod 0644 ${sshKey}.pub
        pubkey="$(cut -d' ' -f1,2 ${sshKey}.pub)"

        # 2. cloud-init user-data / meta-data / network-config.
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        sed \
          -e "s|@SSH_PUBKEY@|$pubkey|" \
          -e "s|@HOSTNAME@|${guestHostname}|g" \
          -e "s|@FQDN@|${guestFqdn}|g" \
          -e "s|@APPLIANCE_VERSION@|${manifest.appliance.version}|g" \
          ${userDataTemplate} > "$tmp/user-data.in"
        ca=${lib.escapeShellArg cfg.caCertFile}
        if [ -s "$ca" ] && grep -q 'BEGIN CERTIFICATE' "$ca"; then
          {
            echo "# Appliance CA (ADR 0004), from $ca on the host."
            echo "ca_certs:"
            echo "  trusted:"
            echo "    - |"
            sed 's/^/      /' "$ca"
          } > "$tmp/ca-block"
          awk -v f="$tmp/ca-block" '/^#@CA_CERTS@$/ { while ((getline l < f) > 0) print l; next } { print }' \
            "$tmp/user-data.in" > "$tmp/user-data"
          echo "dawo-appliance-guest: appliance CA $ca injected as cloud-init ca_certs"
        else
          grep -v '^#@CA_CERTS@$' "$tmp/user-data.in" > "$tmp/user-data"
          echo "dawo-appliance-guest: no appliance CA at $ca (yet); user-data without ca_certs"
        fi
        if grep -Eq '@[A-Z_]+@' "$tmp/user-data"; then
          echo "dawo-appliance-guest: unrendered placeholder in user-data:" >&2
          grep -En '@[A-Z_]+@' "$tmp/user-data" >&2
          exit 1
        fi
        # The instance-id follows the user-data: a changed key or CA re-runs
        # cloud-init's per-instance modules at the guest's next boot.
        instance="$name-$(sha256sum "$tmp/user-data" | cut -c1-12)"
        sed -e "s|@INSTANCE_ID@|$instance|" -e "s|@HOSTNAME@|${guestHostname}|" \
          ${metaDataTemplate} > "$tmp/meta-data"
        cp ${networkConfig} "$tmp/network-config"

        # 3. Seed ISO (NoCloud: volume label cidata), rebuilt only on change.
        want="$(cat "$tmp/user-data" "$tmp/meta-data" "$tmp/network-config" | sha256sum | cut -d' ' -f1)"
        stamp=${guestDir}/seed.sha256
        if [ ! -s ${seedIso} ] || [ "$(cat "$stamp" 2>/dev/null || true)" != "$want" ]; then
          echo "dawo-appliance-guest: building cloud-init seed ${seedIso} (instance-id $instance)"
          genisoimage -quiet -output "$tmp/seed.iso" -volid cidata -joliet -rock -input-charset utf-8 \
            "$tmp/user-data" "$tmp/meta-data" "$tmp/network-config"
          install -m 0644 "$tmp/seed.iso" ${seedIso}
          install -m 0640 "$tmp/user-data" ${renderedUserData}
          install -m 0644 "$tmp/meta-data" ${guestDir}/meta-data
          install -m 0644 "$tmp/network-config" ${guestDir}/network-config
          echo "$want" > "$stamp"
        else
          echo "dawo-appliance-guest: seed ${seedIso} up to date"
        fi

        # 4. The libvirt domain, redefined only when its XML changes (keeping
        #    the UUID libvirt assigned the first time).
        xml=${domainXml}
        dstamp=${guestDir}/domain.xml.sha256
        dwant="$(sha256sum "$xml" | cut -d' ' -f1)"
        if virsh dominfo "$name" >/dev/null 2>&1; then
          if [ "$dwant" != "$(cat "$dstamp" 2>/dev/null || true)" ]; then
            echo "dawo-appliance-guest: domain definition changed; redefining $name (takes effect at the next guest start)"
            uuid="$(virsh domuuid "$name")"
            sed "s|<name>$name</name>|&\n  <uuid>$uuid</uuid>|" "$xml" > "$tmp/domain.xml"
            virsh define --validate "$tmp/domain.xml"
          else
            echo "dawo-appliance-guest: domain $name already defined, unchanged"
          fi
        else
          echo "dawo-appliance-guest: defining domain $name from $xml (${toString cfg.vcpus} vCPU, ${toString cfg.memoryGiB} GiB)"
          virsh define --validate "$xml"
        fi
        echo "$dwant" > "$dstamp"

        ${if cfg.autostart then ''
          virsh autostart "$name" >/dev/null
          state="$(virsh domstate "$name")"
          if [ "$state" = "running" ]; then
            echo "dawo-appliance-guest: $name already running"
          elif [ ! -s ${overlayDisk} ]; then
            echo "dawo-appliance-guest: guest disk ${overlayDisk} not ready (image service failed or still running); not starting $name" >&2
          else
            echo "dawo-appliance-guest: starting $name"
            virsh start "$name"
          fi
        '' else ''
          virsh autostart --disable "$name" >/dev/null
          echo "dawo-appliance-guest: appliance.guest.autostart = false; $name defined but not started"
        ''}
      '';
    };
  };
}
