{
  description = "dawo-appliance — experimental, unofficial demo appliance for a digitally autonomous government workplace";

  # Pinned inputs. flake.lock pins exact revisions (no floating tags): nixpkgs to
  # the same nixos-25.11 stable revision DAWO-NixOS pins, and disko (declarative
  # partitioning) following our nixpkgs.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # The wrapped bootstrap command — single source of truth, also used by the
      # live-system payload (installer/live-payload.nix).
      bootstrap = pkgs.callPackage ./installer/bootstrap/package.nix { };
    in
    {
      packages.${system} = {
        default = bootstrap;
        bootstrap = bootstrap;
        # The non-destructive live installer ISO (Slice 1). Build with:
        #   nix build .#installer-iso
        installer-iso = self.nixosConfigurations.installer-iso.config.system.build.isoImage;

        # Headless boot test (Slice 1), kept OUT of `checks` because it requires
        # the `kvm` system feature (so `nix flake check` stays portable). Boots a
        # VM carrying the same live-system payload the ISO ships and asserts the
        # bootstrap works and stays non-destructive. Run explicitly:
        #   nix build .#test-installer-boot -L     (needs KVM; see docs/nix-setup.md)
        test-installer-boot = pkgs.testers.runNixOSTest {
          name = "installer-boot";
          nodes.machine = { ... }: {
            imports = [ ./installer/live-payload.nix ];
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

            # The destructive path is refused in v0.1.
            machine.fail(
                "dawo-appliance-bootstrap plan --offline "
                f"--manifest-url {manifest} --target-disk /dev/vda --confirm-destroy")
          '';
        };

        # The installed appliance host as a bootable disk image (Slice 2). disko
        # partitions + formats + installs the host into a raw image (`main.raw`).
        # Building this proves the storage layout applies and the host installs.
        #   nix build .#appliance-disk-image     (needs KVM; builds via a VM)
        appliance-disk-image =
          self.nixosConfigurations.appliance.config.system.build.diskoImages;

        # Boot test for the appliance host CONFIG (Slice 2), kept OUT of `checks`
        # (needs `kvm`). Boots the host configuration in a VM and asserts it comes
        # up with the expected identity, operator account and bootstrap. Storage
        # is verified separately by `appliance-disk-image` (disko); here the test
        # framework supplies the root fs so we exercise the host config itself.
        #   nix build .#test-appliance-boot -L   (needs KVM; see docs/nix-setup.md)
        test-appliance-boot = pkgs.testers.runNixOSTest {
          name = "appliance-boot";
          nodes.machine = { lib, ... }: {
            imports = [ ./hosts/appliance/configuration.nix ];
            # The test boots directly (no bootloader install), so neutralise the
            # host's GRUB choice for the VM only.
            boot.loader.grub.enable = lib.mkForce false;
          };
          testScript = ''
            start_all()
            machine.wait_for_unit("multi-user.target")
            machine.succeed("test \"$(hostname)\" = dawo-appliance")
            machine.succeed("dawo-appliance-bootstrap version")
            machine.succeed("id dawo")               # operator account exists
            machine.wait_for_unit("NetworkManager.service")
          '';
        };
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
          { nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.jq pkgs.gnused pkgs.gawk ]; }
          ''
            cp -r ${self} src
            chmod -R +w src
            cd src
            bash tests/test-bootstrap-dryrun.sh
            touch $out
          '';

        # Lint the shell scripts.
        shellcheck = pkgs.runCommand "shellcheck"
          { nativeBuildInputs = [ pkgs.shellcheck ]; }
          ''
            shellcheck \
              ${./installer/bootstrap/dawo-appliance-bootstrap} \
              ${./tests/test-bootstrap-dryrun.sh} \
              ${./scripts/status.sh}
            touch $out
          '';
      };

      nixosConfigurations.installer-iso = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./installer/iso/iso.nix
          # Ship disko-install so `dawo-appliance-bootstrap install` can run on
          # the booted ISO (Slice 2).
          { environment.systemPackages = [ disko.packages.${system}.disko-install ]; }
        ];
      };

      # The installed appliance host (Slice 2). Storage is declared with disko
      # and gated by an explicit `appliance.targetDisk` (sentinel default — see
      # hosts/appliance/disko.nix). The real install overrides the device.
      nixosConfigurations.appliance = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./hosts/appliance/configuration.nix
          ./hosts/appliance/disko.nix
        ];
      };

      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}
