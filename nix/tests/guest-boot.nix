# Nested boot test for the Ubuntu guest (issue #41, Slice 4a).
#
# Runs the appliance host configuration in a test VM with nested KVM and lets
# it start the real Ubuntu 24.04 guest from the pinned cloud image. The image
# is a fixed-output derivation (URL and SHA-256 from the manifest), so the test
# itself needs no network. Checks that the guest boots, gets its fixed lease,
# answers SSH with the host-generated key, finishes cloud-init and trusts the
# appliance CA.
#
# Out of scope: the K3s stage in cloud-init needs internet inside the guest,
# which the test VM does not have (issue #7); the test only requires that
# cloud-init reached its end.
{ pkgs, lib, dawoHostWiring, dawoSpecialArgs }:

let
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  image = manifest.vm.image;
  pinnedImage = pkgs.fetchurl {
    url = "${image.base_url}${image.file}";
    sha256 = image.sha256;
  };
  ssh = "ssh -i /var/lib/dawo-appliance/ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR ops@192.168.150.10";
in
pkgs.testers.runNixOSTest {
  name = "guest-boot";
  node.specialArgs = dawoSpecialArgs;
  node.pkgsReadOnly = false;

  nodes.machine = { lib, ... }: {
    imports = dawoHostWiring ++ [ ../../hosts/appliance/configuration.nix ];
    boot.consoleLogLevel = lib.mkForce 7;
    virtualisation = {
      memorySize = 8192;
      cores = 4;
      diskSize = 8192;
      # Expose VMX/SVM so libvirt inside the test VM can use KVM.
      qemu.options = [ "-cpu host" ];
    };
    appliance.guest = {
      vcpus = 2;
      memoryGiB = 3;
      imageOverride = pinnedImage;
    };
  };

  testScript = ''
    import time
    t0 = time.time()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test -c /dev/kvm")
    machine.wait_for_unit("dawo-appliance-guest.service", timeout=600)
    machine.wait_until_succeeds(
        "virsh -c qemu:///system domstate dawo-appliance-mb | grep -qx running", timeout=120)

    # The guest answers SSH with the key the host generated at first boot.
    machine.wait_until_succeeds("${ssh} true", timeout=900)
    t_ssh = time.time() - t0
    machine.succeed(
        "virsh -c qemu:///system net-dhcp-leases dawo-appliance | grep -q 192.168.150.10")
    hostname = machine.succeed("${ssh} hostname -f").strip()
    assert hostname == "mb.dawo.internal", f"guest hostname is {hostname!r}"

    # cloud-init reached its end (the K3s stage may fail offline; see #7).
    machine.wait_until_succeeds("${ssh} test -f /var/lib/cloud/instance/boot-finished", timeout=900)
    t_cloudinit = time.time() - t0
    print(machine.succeed("${ssh} cloud-init status --long || true"))
    # Offline, exactly two modules may fail: the apt install of
    # qemu-guest-agent and the runcmd (K3s download). Anything else is a
    # regression in our cloud-init.
    import json
    st = json.loads(machine.succeed("${ssh} cloud-init status --format json || true"))
    failed = sorted({e[0] if isinstance(e, list) else str(e).split("'")[1] for e in st.get("errors", [])})
    assert set(failed) <= {"package_update_upgrade_install", "scripts_user"}, f"unexpected cloud-init errors: {st.get('errors')}"

    # The guest trusts the appliance CA (cloud-init ca_certs, ADR 0004).
    ca_line = machine.succeed("sed -n 2p /var/lib/dawo-appliance/ca/ca.crt").strip()
    machine.succeed(f"${ssh} grep -qF '{ca_line}' /etc/ssl/certs/ca-certificates.crt")

    # The host status helper agrees.
    machine.succeed("dawo-appliance-guest-status")
    print(f"TIMING ssh={t_ssh:.0f}s cloud-init-finished={t_cloudinit:.0f}s")
  '';
}
