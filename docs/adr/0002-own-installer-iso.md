# ADR 0002: Keep our own installer ISO alongside upstream `dawo-installer`

- Status: Accepted
- Date: 2026-09-25
- Deciders: maintainer (eywitteveen)

## Context

When this project started (June 2026) DAWO-NixOS had no ISO or installer
output, so ADR 0001 decided we provide our own live ISO. Since then upstream,
now **DAWO-Core** on Codeberg with releases 0.1.0 (2026-06-29) through 0.1.3
(2026-09-07), ships two installer hosts and a companion repository:

- `nixosConfigurations.dawo-installer`: a **headless provisioning ISO**. At
  build time it bakes in wifi credentials and one operator SSH public key
  (read from environment variables, so the build needs `--impure`), disables
  NetworkManager in favour of `wpa_supplicant`, and starts `sshd` with
  `PermitRootLogin prohibit-password`. It installs nothing itself: an operator
  logs in from a workstation and drives `nixos-anywhere`, which applies the
  fixed `disko-single-nvme-luks` layout (LUKS on `/dev/nvme0n1`; Secure Boot
  and TPM2 unlock as follow-up steps). Without the baked-in key the ISO cannot
  be logged into at all.
- `nixosConfigurations.dawo-installer-netboot`: the same idea as PXE
  kernel + initrd + iPXE script, for imaging a fleet without USB sticks.
- `MinBZK/DAWO-NixOS-installatie`: Dutch runbooks and scripts for USB/PXE
  imaging, a provisioning station ("inspoelstraat") and a "Zaanstad-grade"
  overlay (named users, VPN for SSH management, comin auto-update).

Both installer hosts are **fleet imaging tools for laptops**, operated remotely
by an administrator. Our ISO has a different job (`docs/purpose.md`): a
**self-contained, interactive installer for one demo appliance** that ends
with the DAWO workplace on screen and Mijn Bureau open in the browser.

## Decision

1. **Keep `installer/iso` and `dawo-appliance-bootstrap`.** They remain the
   installer of this project.
2. **Do not import upstream's installer host modules.** They assume
   remote-driven `nixos-anywhere`, baked-in credentials and the fixed LUKS/NVMe
   layout. None of that fits an appliance installed at the console with an
   explicit, confirmed target disk and no secrets in the image.
3. **Consume DAWO-Core for the *installed* system instead**: the workplace
   profile, desktop and hardening (ADR 0003). The installer is ours; what it
   installs is upstream's workplace plus our additions.
4. **Revisit** if upstream ships an interactive, stand-alone installer, or if
   fleet imaging ever enters scope (it is out of scope for v0.1).

## Comparison

| Aspect | upstream `dawo-installer` | our `installer-iso` |
| --- | --- | --- |
| Purpose | image a fleet of laptops | install one demo appliance |
| Operation | remote: operator SSH + `nixos-anywhere` | local: console, `dawo-appliance-bootstrap` |
| Secrets in the image | wifi PSK + operator SSH key | none |
| Networking on the live system | `wpa_supplicant`, NetworkManager off | NetworkManager |
| Disk | fixed `/dev/nvme0n1`, LUKS | explicit `--target-disk`, no LUKS in v0.1 |
| Safety gate | operator discipline | `--target-disk` + `--confirm-destroy`, dry-run, refusal tests |
| Verification | none | pinned manifest + SHA-256 root of trust |
| Result | DAWO workplace | DAWO workplace + VM + K3s + Mijn Bureau + browser |

## Consequences

- We keep maintaining a small ISO definition (about 40 lines over nixpkgs'
  `installation-cd-minimal.nix`) and the bootstrap. Both are already covered by
  the offline dry-run suite and the headless boot test.
- No credentials ever enter the image; the manifest trust chain stays intact.
- The two installers coexist and are documented as different tools
  (`README.md`, `docs/upstream/ecosystem.md`). We must never present ours as
  "the DAWO installer".
- Upstream's pattern of a `warnings` entry instead of a hard failure for
  missing optional build-time input is worth borrowing if we ever need
  build-time parameters.

## Alternatives considered

- **Use `dawo-installer` as-is.** Rejected: requires baked-in secrets, an
  external operator machine and the fixed NVMe/LUKS layout; has no manifest
  verification; performs none of the appliance steps (VM, K3s, Mijn Bureau,
  browser).
- **Import its module and layer the bootstrap on top.** Rejected: the module
  forces wifi on and NetworkManager off, reads `builtins.getEnv`, and only
  adds sshd plus a key over the same nixpkgs base we already use. Little to
  gain, real conflicts to manage.
