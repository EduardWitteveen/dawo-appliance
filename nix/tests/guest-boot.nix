# Nested boot test for the Ubuntu guest (issue #41, Slice 4a).
#
# Runs the appliance host configuration in a test VM with nested KVM and lets
# it start the real Ubuntu 24.04 guest from the pinned cloud image. The image
# is a fixed-output derivation (URL and SHA-256 from the manifest), so the test
# itself needs no network. Checks that the guest boots, gets its fixed lease,
# answers SSH with the host-generated key, finishes cloud-init and trusts the
# appliance CA.
#
# K3s (Slice 5) installs air-gapped from the pinned artifacts the host
# attaches, so the whole guest boot, including a Ready K3s node, runs without
# network.
{ pkgs, lib, dawoHostWiring, dawoSpecialArgs }:

let
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/appliance-manifest.json);
  image = manifest.vm.image;
  k3sTag = manifest.kubernetes.version.tag;
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
    try:
        machine.wait_until_succeeds("${ssh} true", timeout=900)
    except Exception:
        print(machine.succeed("tail -n 120 /var/log/libvirt/qemu/dawo-appliance-mb-console.log || true"))
        raise
    t_ssh = time.time() - t0
    machine.succeed(
        "virsh -c qemu:///system net-dhcp-leases dawo-appliance | grep -q 192.168.150.10")
    hostname = machine.succeed("${ssh} hostname -f").strip()
    assert hostname == "mb.dawo.internal", f"guest hostname is {hostname!r}"

    # cloud-init reached its end (the K3s stage may fail offline; see #7).
    machine.wait_until_succeeds("${ssh} test -f /var/lib/cloud/instance/boot-finished", timeout=900)
    t_cloudinit = time.time() - t0
    print(machine.succeed("${ssh} cloud-init status --long || true"))
    # cloud-init finishes without any error: nothing comes from the Ubuntu
    # archive (#47) and K3s installs air-gapped from the pinned artifacts (#7).
    import json
    st = json.loads(machine.succeed("${ssh} cloud-init status --format json || true"))
    assert not st.get("errors"), f"cloud-init errors: {st.get('errors')}"

    # Slice 5: the pinned K3s is installed offline and the node is Ready.
    machine.succeed("${ssh} test -f /var/lib/dawo-appliance-k3s-stage.done")
    version = machine.succeed("${ssh} k3s --version").splitlines()[0]
    assert "${k3sTag}" in version, f"unexpected K3s version: {version}"
    machine.wait_until_succeeds(
        "${ssh} sudo k3s kubectl get node --no-headers | grep -qw Ready", timeout=600)
    t_k3s = time.time() - t0

    # The guest trusts the appliance CA (cloud-init ca_certs, ADR 0004).
    ca_line = machine.succeed("sed -n 2p /var/lib/dawo-appliance/ca/ca.crt").strip()
    machine.succeed(f"${ssh} grep -qF '{ca_line}' /etc/ssl/certs/ca-certificates.crt")

    # The CA cert and private key are transported into the guest at
    # deploy.sh's APPLIANCE_CA_DIR contract, root-only (ADR 0004, issue #6).
    machine.succeed("${ssh} sudo test -s /etc/dawo-appliance/ca.crt")
    machine.succeed("${ssh} sudo test -s /etc/dawo-appliance/ca.key")
    key_perms = machine.succeed(
        "${ssh} sudo stat -c '%a:%U:%G' /etc/dawo-appliance/ca.key").strip()
    assert key_perms == "600:root:root", f"guest ca.key perms: {key_perms!r}"

    # The host status helper agrees.
    machine.succeed("dawo-appliance-guest-status")
    print(f"TIMING ssh={t_ssh:.0f}s cloud-init-finished={t_cloudinit:.0f}s k3s-node-ready={t_k3s:.0f}s")
  '';
}
