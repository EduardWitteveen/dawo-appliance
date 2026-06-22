{
  description = "dawo-appliance — experimental, unofficial demo appliance for a digitally autonomous government workplace";

  # Single pinned input. flake.lock pins nixpkgs to the same nixos-25.11 stable
  # revision DAWO-NixOS pins. No floating tags.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
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
            manifest = "file:///etc/dawo-appliance/manifest/appliance-manifest.json"
            out = machine.succeed(
                f"dawo-appliance-bootstrap plan --offline --manifest-url {manifest}")
            assert "INSTALL PLAN" in out, "plan did not print the install plan"
            assert "NO DISK WRITES PERFORMED" in out, "plan did not report no-writes"
            assert "checksum verified" in out, "plan did not verify the checksum"

            # The destructive path is refused in v0.1.
            machine.fail(
                "dawo-appliance-bootstrap plan --offline "
                f"--manifest-url {manifest} --target-disk /dev/vda --confirm-destroy")
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
        modules = [ ./installer/iso/iso.nix ];
      };

      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}
