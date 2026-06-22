{
  description = "dawo-appliance — experimental, unofficial demo appliance for a digitally autonomous government workplace";

  # Single pinned input. flake.lock pins nixpkgs to the same nixos-25.11 stable
  # revision DAWO-NixOS pins. No floating tags.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      bootstrapSrc = ./installer/bootstrap/dawo-appliance-bootstrap;

      # Wrap the bootstrap script with its runtime dependencies on PATH.
      bootstrap = pkgs.runCommand "dawo-appliance-bootstrap"
        { nativeBuildInputs = [ pkgs.makeWrapper ]; }
        ''
          mkdir -p $out/bin
          cp ${bootstrapSrc} $out/bin/dawo-appliance-bootstrap
          chmod +x $out/bin/dawo-appliance-bootstrap
          wrapProgram $out/bin/dawo-appliance-bootstrap \
            --prefix PATH : ${pkgs.lib.makeBinPath [
              pkgs.bash pkgs.coreutils pkgs.curl pkgs.jq pkgs.gnused pkgs.gawk
            ]}
        '';
    in
    {
      packages.${system} = {
        default = bootstrap;
        bootstrap = bootstrap;
        # The non-destructive live installer ISO (Slice 1). Build with:
        #   nix build .#installer-iso
        installer-iso = self.nixosConfigurations.installer-iso.config.system.build.isoImage;
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
              ${./tests/test-bootstrap-dryrun.sh}
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
