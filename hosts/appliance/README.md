# Appliance host definition

The installed NixOS host configuration for the appliance (Slices 2–3). It is
**the DAWO workplace plus additions** (`docs/adr/0003-workplace-parity.md`).

## Files

| File | Role |
| --- | --- |
| `configuration.nix` | Aggregate: imports the three modules below, sets the hostname, ships the bootstrap. Defines nothing that shapes the user experience. |
| `dawo-workplace.nix` | **The DAWO workplace, unchanged.** Imports the same DAWO-Core modules a pilot client imports (`boot-loader`, `boot-plymouth-bzk`, `profiles-dawo-generic`, `maid-dawo-generic`) and makes the same choices (Plasma; app sets office/comms/creative/media; Secure Boot off). Holds the recorded deviations: auto-update off, microcode for both vendors, acknowledged default password (replaced at first boot). |
| `virtualisation.nix` | Addition: KVM/libvirt (`libvirtd`, swtpm, virt-manager), `dawo` in `libvirtd`. Slice 4 adds the registration and autostart of the Ubuntu guest here; the domain definition and cloud-init live in `vm/ubuntu-2404/`. |
| `appliance-services.nix` | Addition: `dawo-appliance-set-password.service` applies the install-time generated password for `dawo` once at first boot (hash shipped by the installer to `/var/lib/dawo-appliance/dawo.password-hash`; the plain text stays in `dawo.password.txt` for the welcome dialog: demo appliance, not for production) and shows the welcome dialog (kdialog autostart) with the login details and a "not for production" notice. Later appliance services (VM autostart, health check, browser) join here. |
| `disko.nix` | Wires `hosts/profiles/disko/single-disk.nix` and exposes `appliance.targetDisk` (sentinel default; the install overrides it explicitly). |
| `vm.nix` | Development aid: the same host as a local QEMU VM with a window (`nix run .#appliance-vm`); disko's file systems switched off, no bootloader, upstream's default login. |

Built as `nixosConfigurations.appliance`. The DAWO modules need upstream's own
`inputs`/`hostConfig` as specialArgs; `flake.nix` supplies them (plus
`dawoCore`) through `dawoSpecialArgs` and wires home-manager as upstream does.

## Verification

- `nix flake check` → `checks.workplace-parity` compares the user-facing option
  values with upstream's pilot host `hosts/dawo-t495s` at the pinned tag and
  fails on drift (`nix/parity.nix`).
- `nix build .#test-appliance-boot -L` (KVM) boots the host: SDDM/Plasma reach
  `graphical.target`, the pilot apps are present, hardening is active, libvirtd
  runs, `dawo` is a wheel admin in `libvirtd`, root is locked, comin is off.
- `nix run .#appliance-vm` for a human look (auto-login as `dawo`; the screen
  lock accepts upstream's documented bootstrap default password; see `vm.nix`).
- `nix build .#appliance-disk-image` applies the disko layout into a raw image
  (KVM-flaky on WSL, OQ-9).

## Later (Slice 4+)

Ubuntu 24.04 guest (libvirt domain + cloud-init, autostart), K3s, Mijn Bureau,
health check and the browser step — all as additions, never by changing the
workplace. See `docs/roadmap.md`.
