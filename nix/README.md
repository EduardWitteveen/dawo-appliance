# Shared Nix code

Nix code that is not a host module and not the flake itself.

| File | Role |
| --- | --- |
| `parity.nix` | `checks.workplace-parity`: evaluation-time comparison of the user-facing option values of `nixosConfigurations.appliance` with upstream's pilot host at the pinned DAWO-Core tag. Fails with a report on drift; recorded deviations are listed here and in `docs/adr/0003-workplace-parity.md`. |

Host modules live in `hosts/appliance/` (see its README); the installer in
`installer/`. `flake.nix` wires everything together and pins nixpkgs and disko
to the revisions DAWO-Core pins (`docs/upstream/revisions.md`).
