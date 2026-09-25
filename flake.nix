{
  description = "dawo-appliance — experimental, unofficial demo appliance for a digitally autonomous government workplace";

  # Pinned inputs. flake.lock pins exact revisions (no floating tags): nixpkgs to
  # the same nixos-26.05 stable revision DAWO-Core 0.1.3 pins, disko to the
  # revision DAWO-Core pins (following our nixpkgs), and DAWO-Core itself to a
  # release tag whose exact rev is locked and recorded in the manifest. Sharing
  # upstream's pins keeps one nixpkgs in the closure. Exact revs and the reason
  # for each pin: manifest/appliance-manifest.json, docs/upstream/revisions.md.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    # The DAWO workplace (ADR 0003). Consumed, not forked.
    dawo-core.url = "git+https://codeberg.org/DAWO/DAWO-Core?ref=refs/tags/0.1.3";
    dawo-core.inputs.nixpkgs.follows = "nixpkgs";
    dawo-core.inputs.disko.follows = "disko";
  };

  outputs = { self, nixpkgs, disko, dawo-core }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = nixpkgs.lib;

      # The wrapped bootstrap command — single source of truth, also used by the
      # live-system payload (installer/live-payload.nix).
      bootstrap = pkgs.callPackage ./installer/bootstrap/package.nix { };

      # DAWO-Core's modules expect upstream's own `inputs` (including `self`) and
      # a `hostConfig` as specialArgs — exactly what upstream's
      # modules/flake-parts/host-machines.nix passes to its hosts. `dawoCore` is
      # ours, so hosts/appliance/dawo-workplace.nix can reach the module set.
      dawoSpecialArgs = {
        inputs = dawo-core.inputs // { self = dawo-core; };
        hostConfig = { name = "dawo-appliance"; };
        dawoCore = dawo-core;
      };

      # Everything the live installer system carries beyond installer/live-payload.nix
      # and that the installer boot test must see too: disko-install for
      # `dawo-appliance-bootstrap install`, and this flake itself (read-only)
      # as the default install source `/etc/dawo-appliance/config#appliance`.
      # One definition, imported by both the ISO and the test, so the test can
      # never pass on something the ISO does not ship (or vice versa).
      liveInstallerExtras = {
        environment.systemPackages = [ disko.packages.${system}.disko-install ];
        environment.etc."dawo-appliance/config".source = "${self}";
      };

      # What upstream wires around every host besides the host module itself.
      dawoHostWiring = [
        dawo-core.inputs.home-manager.nixosModules.home-manager
        { home-manager.extraSpecialArgs = dawoSpecialArgs; }
      ];

      # The installed appliance host (Slices 2–3): the DAWO workplace plus our
      # additions, with disko storage gated by an explicit `appliance.targetDisk`
      # (sentinel default — see hosts/appliance/disko.nix).
      mkAppliance = extraModules: lib.nixosSystem {
        specialArgs = dawoSpecialArgs;
        modules = dawoHostWiring ++ [
          disko.nixosModules.disko
          ./hosts/appliance/configuration.nix
          ./hosts/appliance/disko.nix
        ] ++ extraModules;
      };
    in
    {
      packages.${system} = {
        default = bootstrap;
        bootstrap = bootstrap;
        # The non-destructive live installer ISO (Slice 1). Build with:
        #   nix build .#installer-iso
        installer-iso = self.nixosConfigurations.installer-iso.config.system.build.isoImage;

        # Does the Nix sandbox get hardware virtualisation? The VM tests use
        # `accel=kvm:tcg` and silently fall back to slow software emulation when
        # /dev/kvm is not openable by the build user. This tiny derivation makes
        # that visible (scripts/speed-check.sh, scripts/verify.sh):
        #   nix build .#check-kvm --rebuild
        check-kvm = pkgs.runCommand "check-kvm" { requiredSystemFeatures = [ "kvm" ]; } ''
          if [ -w /dev/kvm ]; then
            echo "kvm: /dev/kvm is writable inside the sandbox" | tee $out
          else
            echo "kvm: /dev/kvm is NOT writable inside the sandbox (VM tests would use TCG)" >&2
            ls -l /dev/kvm >&2 || true
            id >&2
            exit 1
          fi
        '';

        # The appliance host as a local QEMU VM with a window (development aid,
        # Slice 3): look at the DAWO workplace without installing anything.
        #   nix run .#appliance-vm        (needs KVM; a display via WSLg/X11)
        # Login: dawo / upstream's documented bootstrap default (see vm.nix).
        appliance-vm = self.nixosConfigurations.appliance-vm.config.system.build.vm;

        # Headless boot test (Slice 1), kept OUT of `checks` because it requires
        # the `kvm` system feature (so `nix flake check` stays portable). Boots a
        # VM carrying the same live-system payload the ISO ships and asserts the
        # bootstrap works and stays non-destructive. Run explicitly:
        #   nix build .#test-installer-boot -L     (needs KVM; see docs/nix-setup.md)
        test-installer-boot = pkgs.testers.runNixOSTest {
          name = "installer-boot";
          nodes.machine = { ... }: {
            imports = [ ./installer/live-payload.nix liveInstallerExtras ];
            # A spare, unmounted disk (/dev/vdb) so the install gate is exercised
            # on a valid target, not only on the live disk.
            virtualisation.emptyDiskImages = [ 1024 ];
          };
          testScript = ''
            start_all()
            machine.wait_for_unit("multi-user.target")

            # The bootstrap command is installed and runs.
            machine.succeed("dawo-appliance-bootstrap version")

            # The trusted manifest + checksum are shipped read-only in /etc.
            machine.succeed(
                "test -f /etc/dawo-appliance/manifest/appliance-manifest.json")
            machine.succeed(
                "test -f /etc/dawo-appliance/manifest/appliance-manifest.json.sha256")

            # `plan` verifies the checksum, prints the plan, and writes nothing.
            # The bootstrap logs ("checksum verified") go to stderr, so capture
            # both streams with 2>&1.
            manifest = "file:///etc/dawo-appliance/manifest/appliance-manifest.json"
            out = machine.succeed(
                f"dawo-appliance-bootstrap plan --offline --manifest-url {manifest} 2>&1")
            assert "INSTALL PLAN" in out, "plan did not print the install plan"
            assert "NO DISK WRITES PERFORMED" in out, "plan did not report no-writes"
            assert "checksum verified" in out, "plan did not verify the checksum"

            # The destructive flags are refused on the non-destructive commands.
            machine.fail(
                "dawo-appliance-bootstrap plan --offline "
                f"--manifest-url {manifest} --target-disk /dev/vda --confirm-destroy")

            # The ISO carries this flake as the default install source, and the
            # tools `install` needs (Slices 2–3).
            machine.succeed("test -f /etc/dawo-appliance/config/flake.nix")
            machine.succeed("test -f /etc/dawo-appliance/config/flake.lock")
            machine.succeed("command -v disko-install")

            # `install --dry-run` previews (incl. the password step) and writes
            # nothing; without --confirm-destroy a real install is refused even
            # for a real block device.
            out = machine.succeed(
                "dawo-appliance-bootstrap install --target-disk /dev/vdb "
                "--dry-run --generate-password 2>&1")
            assert "NO DISK WRITES PERFORMED" in out, "install --dry-run did not report no-writes"
            assert "extra-files" in out, "install --dry-run did not preview the password step"
            # The default flake source (/etc/dawo-appliance/config, a symlink into
            # the store) must be resolved to a real path Nix accepts as a flake.
            assert "flake:        /nix/store/" in out, "default flake ref was not resolved to a store path"
            # A real install on a valid, unmounted disk is refused for the right
            # reason: no --confirm-destroy.
            out = machine.fail("dawo-appliance-bootstrap install --target-disk /dev/vdb 2>&1")
            assert "confirm-destroy" in out, "refusal was not about --confirm-destroy: " + out
            machine.succeed("test -z \"$(lsblk -nro FSTYPE /dev/vdb)\"")  # still untouched
            # The live disk itself is refused as a target.
            machine.fail("dawo-appliance-bootstrap install --target-disk /dev/vda --confirm-destroy")

            # Screenshots for docs/screenshots (scripts/screenshots.sh copies
            # them): the plan as an operator sees it on the console.
            # (`clear` needs TERM, which the test shell lacks; ESC c resets the VT.)
            machine.succeed(
                "printf '\\033c' > /dev/tty1; "
                f"dawo-appliance-bootstrap plan --offline --manifest-url {manifest} > /dev/tty1 2>&1")
            machine.sleep(2)
            machine.screenshot("installer-plan")
          '';
        };

        # The installed appliance host as a bootable disk image (Slice 2). disko
        # partitions + formats + installs the host into a raw image (`main.raw`).
        # Building this proves the storage layout applies and the host installs.
        #   nix build .#appliance-disk-image     (needs KVM; builds via a VM)
        appliance-disk-image =
          self.nixosConfigurations.appliance.config.system.build.diskoImages;

        # Boot test for the appliance host CONFIG (Slices 2–3), kept OUT of
        # `checks` (needs `kvm`). Boots the host configuration in a VM and asserts
        # it comes up as the DAWO workplace (SDDM/Plasma, pilot apps, hardened
        # policies) with our additions (libvirt, bootstrap). Storage is verified
        # separately by `appliance-disk-image`; the test framework supplies the
        # root fs here so we exercise the host config itself.
        #   nix build .#test-appliance-boot -L   (needs KVM; see docs/nix-setup.md)
        test-appliance-boot = pkgs.testers.runNixOSTest {
          name = "appliance-boot";
          node.specialArgs = dawoSpecialArgs;
          # Upstream's nixos-nix-settings sets nixpkgs.config (allowUnfree,
          # permittedInsecurePackages); the test framework's read-only nixpkgs
          # would reject that, so let the node instantiate its own.
          node.pkgsReadOnly = false;
          nodes.machine = { lib, pkgs, ... }: {
            imports = dawoHostWiring ++ [ ./hosts/appliance/configuration.nix ];
            # A desktop needs room; the test harness boots without a bootloader.
            virtualisation.memorySize = 4096;
            virtualisation.cores = 4;
            # The test driver wants kernel messages on the console; upstream's
            # boot splash silences them (consoleLogLevel 0). Test-only override.
            boot.consoleLogLevel = lib.mkForce 7;
            # Test tools only (not on the real host): mkpasswd for the
            # password-service check; openssl and python3 for the CA checks
            # (the CA service calls openssl by store path).
            environment.systemPackages = [ pkgs.mkpasswd pkgs.openssl pkgs.python3 ];
          };
          testScript = ''
            import os, time
            t_start = time.time()
            timing = {}

            start_all()
            machine.wait_for_unit("multi-user.target")
            timing["multi-user.target"] = time.time() - t_start

            # Slice 4b: per-install appliance CA and host trust (R20, R21; ADR 0004).
            # R20: the CA service ran once at first boot and produced the contract files.
            machine.wait_for_unit("dawo-appliance-ca.service")
            machine.succeed("systemctl is-active dawo-appliance-ca.service")   # RemainAfterExit
            ca_dir = "/var/lib/dawo-appliance/ca"
            machine.succeed(f"test -s {ca_dir}/ca.crt && test -s {ca_dir}/ca.key && test -s {ca_dir}/ca.crt.sha256")
            machine.succeed(f"test \"$(stat -c %a {ca_dir}/ca.key)\" = 600")
            machine.succeed(f"test \"$(stat -c %U:%G {ca_dir}/ca.key)\" = root:root")
            machine.succeed(f"test \"$(stat -c %a {ca_dir}/ca.crt)\" = 644")
            machine.succeed(f"cd {ca_dir} && sha256sum -c ca.crt.sha256")
            x509 = machine.succeed(f"openssl x509 -in {ca_dir}/ca.crt -noout -text")
            assert "CA:TRUE" in x509, "appliance CA lacks basicConstraints CA:TRUE"
            assert "Certificate Sign" in x509 and "CRL Sign" in x509, "appliance CA lacks keyCertSign/cRLSign"
            assert "CN=DAWO appliance local CA" in x509 or "CN = DAWO appliance local CA" in x509, "unexpected CA subject"
            machine.succeed(f"openssl x509 -in {ca_dir}/ca.crt -noout -checkend 86400")   # not about to expire
            # The key matches the certificate (same public key).
            machine.succeed(
                f"test \"$(openssl x509 -in {ca_dir}/ca.crt -noout -pubkey | sha256sum)\" = "
                f"\"$(openssl pkey -in {ca_dir}/ca.key -pubout | sha256sum)\"")
            # Idempotent: a second start keeps the same certificate.
            fp_before = machine.succeed(f"openssl x509 -in {ca_dir}/ca.crt -noout -fingerprint -sha256").strip()
            machine.succeed("systemctl restart dawo-appliance-ca.service")
            fp_after = machine.succeed(f"openssl x509 -in {ca_dir}/ca.crt -noout -fingerprint -sha256").strip()
            assert fp_before == fp_after, "dawo-appliance-ca.service regenerated an existing CA"
            # The key is unreadable for the desktop user; the certificate is readable.
            machine.fail(f"su -s /bin/sh dawo -c 'cat {ca_dir}/ca.key'")
            machine.succeed(f"su -s /bin/sh dawo -c 'test -r {ca_dir}/ca.crt'")
            # CLI trust: the env file names the files.
            machine.succeed(f"grep -qx 'DAWO_APPLIANCE_CA_CERT={ca_dir}/ca.crt' /etc/dawo-appliance/ca.env")

            # R21: Firefox trusts the CA via the merged enterprise policy (nixpkgs writes
            # `programs.firefox.policies` to /etc/firefox/policies/policies.json); upstream's
            # own policies must still be there (attrset merge, no override).
            policies = machine.succeed("cat /etc/firefox/policies/policies.json")
            assert f"{ca_dir}/ca.crt" in policies, "Firefox policies.json does not install the appliance CA"
            machine.succeed(
                "python3 -c \"import json,sys; p=json.load(open('/etc/firefox/policies/policies.json'))['policies']; "
                f"assert p['Certificates']['Install']==['{ca_dir}/ca.crt'], p.get('Certificates'); "
                "assert p['DisableTelemetry'] is True and 'plasma-browser-integration@kde.org' in p['ExtensionSettings']\"")


            # Identity and our additions.
            machine.succeed("test \"$(hostname)\" = dawo-appliance")
            machine.succeed("dawo-appliance-bootstrap version")
            machine.wait_for_unit("libvirtd.service")
            machine.succeed("virsh -c qemu:///system list >/dev/null")

            # The DAWO bootstrap account (upstream users-dawo) is a wheel admin
            # and may manage VMs. (Upstream locks root; the test driver sets a
            # root password of its own, so that is not asserted here.)
            machine.succeed("id -nG dawo | tr ' ' '\n' | grep -qx wheel")
            machine.succeed("id -nG dawo | tr ' ' '\n' | grep -qx libvirtd")

            # The workplace: SDDM + Plasma come up, the pilot app set is present,
            # the mandatory hardening is active.
            machine.wait_for_unit("graphical.target")
            timing["graphical.target"] = time.time() - t_start
            machine.wait_for_unit("display-manager.service")
            machine.wait_until_succeeds("pgrep -x sddm", timeout=180)
            for cmd in ["libreoffice", "thunderbird", "element-desktop", "gimp",
                        "inkscape", "krita", "vlc", "keepassxc", "firefox",
                        "plasmashell", "virt-manager"]:
                machine.succeed(f"command -v {cmd}")
            machine.succeed("test \"$(cat /proc/sys/kernel/kptr_restrict)\" != 0")
            machine.succeed("systemctl is-enabled sshd.service")
            machine.succeed("grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config")

            # Auto-update is deliberately off on the appliance (ADR 0003).
            machine.fail("systemctl is-active comin.service")

            # Demo ergonomics (ADR 0003): auto-login configured for dawo, welcome
            # dialog registered as an autostart entry.
            # (SDDM's config lives in the Nix store, not /etc; assert behaviour
            # instead: SDDM is the display manager, and below a dawo session
            # appears without anyone typing.)
            machine.succeed("systemctl cat display-manager.service | grep -qi sddm")
            machine.succeed("test -f /etc/xdg/autostart/dawo-appliance-welcome.desktop")

            # First-boot password service: drop a hash + plain text as the
            # installer would, start the unit, and check it applied the hash,
            # removed the hash file and kept the plain text readable for the
            # welcome dialog. (At boot it was skipped: no file present.)
            machine.succeed(
                "h=$(mkpasswd -m yescrypt --stdin <<<'appliance-test-pw'); "
                "printf '%s\\n' \"$h\" > /var/lib/dawo-appliance/dawo.password-hash; "
                "printf 'appliance-test-pw\\n' > /var/lib/dawo-appliance/dawo.password.txt; "
                "systemctl start dawo-appliance-set-password.service; "
                "test \"$(getent shadow dawo | cut -d: -f2)\" = \"$h\"")
            machine.succeed("test ! -e /var/lib/dawo-appliance/dawo.password-hash")
            # Demo appliance: the plain password stays readable for the welcome
            # dialog, which runs as the logged-in user.
            machine.succeed("su -s /bin/sh dawo -c 'grep -qx appliance-test-pw /var/lib/dawo-appliance/dawo.password.txt'")

            machine.wait_for_unit("NetworkManager.service")

            # The appliance auto-logs in as dawo (ADR 0003 deviation): a Plasma
            # session for that user must appear, then the welcome dialog.
            # Software-rendered Plasma in a test VM takes minutes to come up. Match
            # the command line: NixOS wraps the binary as `.plasmashell-wrapped`,
            # so an exact process-name match never hits.
            machine.wait_until_succeeds("pgrep -u dawo -f plasmashell", timeout=600)
            timing["plasma session (plasmashell)"] = time.time() - t_start

            # Slice 4b: CA imported into the dawo user's NSS db for Chromium (R22).
            # R22: Chromium/NSS — the per-login user service imported the CA into the
            # dawo user's NSS database (idempotent; re-run leaves one entry).
            machine.wait_until_succeeds(
                "systemctl --user -M dawo@ is-active dawo-appliance-ca-nss.service", timeout=120)
            nss_list = machine.succeed("certutil -d sql:/home/dawo/.pki/nssdb -L")
            assert "DAWO appliance local CA" in nss_list, "appliance CA not in dawo's NSS database: " + nss_list
            assert nss_list.count("DAWO appliance local CA") == 1, "duplicate CA entries in NSS db"
            # Trusted as a CA for TLS server authentication (trust flags "C,,").
            machine.succeed("certutil -d sql:/home/dawo/.pki/nssdb -L | grep 'DAWO appliance local CA' | grep -q 'C,,'")
            # Same certificate as on disk.
            machine.succeed(
                "test \"$(certutil -d sql:/home/dawo/.pki/nssdb -L -n 'DAWO appliance local CA' -r | sha256sum)\" = "
                f"\"$(openssl x509 -in {ca_dir}/ca.crt -outform DER | sha256sum)\"")
            machine.succeed("systemctl --user -M dawo@ restart dawo-appliance-ca-nss.service")
            assert machine.succeed("certutil -d sql:/home/dawo/.pki/nssdb -L").count("DAWO appliance local CA") == 1

            machine.succeed("loginctl list-sessions --no-legend | grep -q dawo")
            machine.wait_until_succeeds("pgrep -u dawo -f kdialog", timeout=300)
            timing["welcome dialog"] = time.time() - t_start
            # Give the software-rendered compositor time to actually paint.
            machine.sleep(60)
            machine.screenshot("desktop")

            # Timing report for docs (scripts/verify.sh and screenshots.sh read
            # it): seconds from VM start, in a software-rendered test VM with
            # ${toString 4} vCPUs — real hardware is much faster.
            analyze = machine.succeed("systemd-analyze time 2>/dev/null || true").strip()
            with open(os.path.join(os.environ["out"], "timing.txt"), "w") as f:
                for k, v in timing.items():
                    f.write(f"{k}\t{v:.0f}\n")
                f.write(f"systemd-analyze\t{analyze}\n")
            print("TIMING (seconds from VM start): " + ", ".join(f"{k}={v:.0f}" for k, v in timing.items()))
          '';
        };
      };

      apps.${system}.appliance-vm = {
        type = "app";
        program = "${self.packages.${system}.appliance-vm}/bin/run-dawo-appliance-vm";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          git jq curl coreutils gnused gawk
          shellcheck shfmt gnumake
          qemu_kvm
          nixpkgs-fmt
        ];
        shellHook = ''
          echo "dawo-appliance dev shell — see docs/development.md"
          echo "  local checks: make check   |   plan: make plan"
        '';
      };

      checks.${system} = {
        # Run the offline bootstrap dry-run test inside the sandbox.
        bootstrap-dryrun = pkgs.runCommand "bootstrap-dryrun"
          { nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.jq pkgs.gnused pkgs.gawk pkgs.gnugrep pkgs.mkpasswd ]; }
          ''
            cp -r ${self} src
            chmod -R +w src
            cd src
            bash tests/test-bootstrap-dryrun.sh
            touch $out
          '';

        # Lint the shell scripts.
        shellcheck = pkgs.runCommand "shellcheck"
          { nativeBuildInputs = [ pkgs.shellcheck pkgs.findutils ]; }
          ''
            # Every tracked shell script (the flake source contains only
            # tracked files), so a new script cannot slip past the linter.
            find ${self} -name '*.sh' -print0 \
              | xargs -0 shellcheck ${./installer/bootstrap/dawo-appliance-bootstrap}
            touch $out
          '';

        # Workplace parity (ADR 0003): the appliance host must make the same
        # user-facing choices as upstream's pilot client at the pinned tag.
        # Evaluation only; fails with a report when they drift.
        workplace-parity = import ./nix/parity.nix {
          inherit lib pkgs;
          appliance = self.nixosConfigurations.appliance.config;
          reference = dawo-core.nixosConfigurations."dawo-t495s".config;
          referenceName = "DAWO-Core 0.1.3 hosts/dawo-t495s";
        };
      };

      nixosConfigurations.installer-iso = lib.nixosSystem {
        inherit system;
        modules = [
          ./installer/iso/iso.nix
          liveInstallerExtras
        ];
      };

      nixosConfigurations.appliance = mkAppliance [ ];

      # Same host, run as a local QEMU VM with a display (hosts/appliance/vm.nix).
      nixosConfigurations.appliance-vm = mkAppliance [ ./hosts/appliance/vm.nix ];

      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}
