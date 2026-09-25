# End-to-end install test (issue #14): boot the live installer payload in UEFI
# mode, run the real `dawo-appliance-bootstrap install --target-disk ...
# --confirm-destroy --generate-password` onto an empty disk, then boot a second
# VM from that disk and check the installed appliance.
#
# Structure follows disko's own disko-install test
# (nix-community/disko tests/disko-install/default.nix, MIT) and nixpkgs'
# installer tests: the test VM shares the host's Nix store, and every path the
# installer needs is registered in the installer VM through a closureInfo in
# /etc, so the install runs fully offline.
#
# To stay offline, the exact derivations disko-install builds must already be
# in the store. `installArtifacts` below mirrors disko's install-cli.nix (same
# rev as our disko pin, de57087): the disk mapping override for the disko
# script and the EFI/boot overrides for the toplevel. Keep it in sync when the
# disko pin moves (docs/deviations.md D20).
#
# The installed system is `nixosConfigurations.appliance-e2e`: the appliance
# plus nixpkgs' test instrumentation (the backdoor the test driver talks to)
# and a console log level the driver can read. Nothing else differs.
{ pkgs
, lib
, self
, disko
, liveInstallerExtras
, installAttr ? "appliance-e2e"
}:

let
  targetDisk = "/dev/vdb";
  mountPoint = "/mnt/disko-install-root"; # disko-install's default
  original = self.nixosConfigurations.${installAttr};

  # --- mirror of disko install-cli.nix (rev de57087) ------------------------
  modifiedDisks = builtins.mapAttrs
    (_name: value: value // {
      device = targetDisk;
      content = value.content // { device = targetDisk; };
    })
    original.config.disko.devices.disk;
  cleanedDisks = lib.filterAttrsRecursive (n: _: !lib.hasPrefix "_" n) modifiedDisks;
  diskoSystem = original.extendModules {
    modules = [{
      disko.rootMountPoint = mountPoint;
      disko.devices.disk = lib.mkVMOverride cleanedDisks;
    }];
  };
  installSystem = original.extendModules {
    modules = [
      ({ lib, ... }: {
        # dawo-appliance-bootstrap passes --write-efi-boot-entries.
        boot.loader.efi.canTouchEfiVariables = lib.mkVMOverride true;
        boot.loader.grub.devices = lib.mkVMOverride [ targetDisk ];
        imports = [ ({ _file = "disko-install --system-config"; }) ];
      })
    ];
  };
  installToplevel = installSystem.config.system.build.toplevel;
  # ---------------------------------------------------------------------------

  # Every flake input, recursively (the installer evaluates the flake offline).
  # Skips `self` references and stops at a fixed depth: follows/self links
  # otherwise make the input graph cyclic.
  allInputs = depth: inputs:
    if depth == 0 then [ ] else
    lib.concatMap
      (name:
        let i = inputs.${name}; in
        [ i.outPath ] ++ allInputs (depth - 1) (i.inputs or { }))
      (lib.filter (n: n != "self") (lib.attrNames inputs));

  dependencies = [
    installToplevel
    installToplevel.drvPath
    (installSystem.pkgs.closureInfo { rootPaths = [ installToplevel ]; })
    diskoSystem.config.system.build.diskoScript
    diskoSystem.config.system.build.diskoScript.drvPath
    original.pkgs.stdenv.drvPath
    (original.pkgs.closureInfo { rootPaths = [ ]; }).drvPath
    original.pkgs.perlPackages.ConfigIniFiles
    original.pkgs.perlPackages.FileSlurp
    self.outPath
  ] ++ lib.unique (allInputs 4 self.inputs);

  closure = pkgs.closureInfo { rootPaths = dependencies; };
in
pkgs.testers.runNixOSTest {
  name = "install-e2e";

  nodes.installer = { lib, ... }: {
    imports = [ ../../installer/live-payload.nix liveInstallerExtras ];
    virtualisation = {
      # UEFI firmware (pflash) is attached even with direct kernel boot, so
      # the live system sees /sys/firmware/efi like a real UEFI boot.
      useEFIBoot = true;
      memorySize = 6144;
      cores = 4;
      # The target disk: sparse, large enough for the Plasma closure.
      emptyDiskImages = [ 40960 ];
    };
    environment.etc."install-closure".source = "${closure}/store-paths";
    nix.settings = {
      substituters = lib.mkForce [ ];
      connect-timeout = 1;
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  testScript = ''
    import os, time
    t0 = time.time()

    def create_installed_machine(oldmachine, **kwargs):
        # Taken from disko's disko-install test / nixpkgs' installer test,
        # plus UEFI firmware so systemd-boot on the target can boot.
        os.system(f"cp ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd {oldmachine.state_dir}/target-vars.fd && chmod 644 {oldmachine.state_dir}/target-vars.fd")
        start_command = [
            "${pkgs.qemu_test}/bin/qemu-kvm",
            "-cpu", "max",
            "-m", "4096",
            "-smp", "4",
            "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd",
            "-drive", f"if=pflash,format=raw,unit=1,file={oldmachine.state_dir}/target-vars.fd",
            "-drive", f"file={oldmachine.state_dir}/empty0.qcow2,id=drive1,if=none,index=1,werror=report",
            "-device", "virtio-blk-pci,drive=drive1",
        ]
        machine = create_machine(start_command=" ".join(start_command), **kwargs)
        driver.machines.append(machine)
        return machine

    installer.wait_for_unit("multi-user.target")
    installer.succeed("test -d /sys/firmware/efi")
    installer.succeed("lsblk >&2")

    # The real install, through our bootstrap, exactly as an operator runs it
    # (the attr override selects the instrumented variant; the live Nix store
    # of a test VM is small, hence --allow-small-store).
    out = installer.succeed(
        "DAWO_APPLIANCE_INSTALL_ATTR=${installAttr} "
        "dawo-appliance-bootstrap install --target-disk ${targetDisk} "
        "--confirm-destroy --generate-password --allow-small-store 2>&1 | tee /dev/stderr")
    assert "INSTALLED on ${targetDisk}" in out, "install did not report success"
    pw = [l for l in out.splitlines() if "password:" in l][0].split("password:")[1].strip()
    t_install = time.time() - t0
    installer.shutdown()

    target = create_installed_machine(installer, name="installed")
    target.start()
    target.wait_for_unit("multi-user.target", timeout=900)
    t_boot = time.time() - t0

    # Installed from disk, booted by systemd-boot under UEFI.
    target.succeed("test -d /sys/firmware/efi")
    target.succeed("bootctl is-installed")
    target.succeed("test \"$(hostname)\" = dawo-appliance")
    target.succeed("findmnt -no FSTYPE / | grep -qx btrfs")
    # Regression for the `cp -ar STAGE/. /` bug: / must stay 755.
    target.succeed("test \"$(stat -c %a /)\" = 755")

    # --generate-password: hash applied once, plain text kept for the dialog.
    target.wait_for_unit("multi-user.target")
    target.succeed("test ! -e /var/lib/dawo-appliance/dawo.password-hash")
    target.succeed(f"grep -qx '{pw}' /var/lib/dawo-appliance/dawo.password.txt")
    target.succeed("test \"$(stat -c %a /var/lib/dawo-appliance/dawo.password.txt)\" = 644")

    # The DAWO workplace comes up by itself: auto-login session for dawo.
    target.wait_until_succeeds("pgrep -u dawo -f plasmashell", timeout=900)
    t_desktop = time.time() - t0
    target.wait_for_unit("dawo-appliance-ca.service")

    print(f"TIMING install={t_install:.0f}s boot-from-disk={t_boot:.0f}s desktop={t_desktop:.0f}s")
    target.shutdown()
  '';
}
