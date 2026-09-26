# Nix setup (WSL2 runbook)

How to install Nix on a Windows + WSL2 development machine and make KVM
usable inside the Nix sandbox, so `nix flake check`, the ISO build and the VM
boot tests work (`development.md`).

> **This installs system software (a host change).** Per `CLAUDE.md`, the
> maintainer runs these commands; an assistant prepares and verifies them but
> does not execute them. The installer needs a real TTY for its `sudo`
> prompt: run it in an actual terminal window, not piped through a
> non-interactive assistant shell.

Two machines have used this runbook so far, with different WSL distro names —
check `wsl -l -v` before assuming which one has Nix:

| Machine | WSL distro | Nix | KVM (`/dev/kvm`) |
| --- | --- | --- | --- |
| Laptop, physical, 12 vCPU / 24 GB WSL | `Ubuntu-24.04` | 2.34.7 | yes |
| Nutanix AHV VDI, 4 vCPU / 8 GB WSL, 6 CPU / 16 GB host | `Ubuntu` (plain, 24.04.1) | 2.34.7 | **no** — WSL2 reports "nested virtualization is not supported on this computer" regardless of `nestedVirtualization=true` in `.wslconfig`. This is a VDI (Nutanix AHV, SeaBIOS), i.e. a VM itself; nested-in-nested KVM depends on the underlying hypervisor exposing nested-virt to the Windows guest, which is outside anything changeable from Windows/WSL. `nix flake check` and any eval/build-only work run fine here; VM boot tests would need slow TCG software emulation, or a machine that actually has KVM. |

If `wsl -d <distro> -e bash -lc 'ls /dev/kvm'` fails after setting
`nestedVirtualization=true` and `wsl --shutdown`, check whether the *physical*
host itself is virtualized (`systeminfo`'s "System Manufacturer"/"System
Model", or `(Get-CimInstance Win32_ComputerSystem).Model` in PowerShell) —
if so, this is very likely the same hard limit, not a misconfiguration.

Pin the exact same Nix version (**2.34.7**) on every machine so "it works
here" means the same installer ran everywhere, not whatever was newest that
day:

```bash
sh <(curl -L https://releases.nixos.org/nix/nix-2.34.7/install) --daemon
```

## Where the store goes

The Nix store lives at `/nix` on the WSL **ext4** root filesystem. Do not
relocate it onto the `/mnt/c` 9p mount (slow). The default install does the
right thing. The working tree may stay on `/mnt/c` (it mounts with `metadata`,
so `git` and `chmod` work there; OQ-1).

Pre-flight: `systemctl is-system-running` reports `running` (so use the
multi-user daemon install), `uname -m` is `x86_64`, `/dev/kvm` exists, `curl`
and `xz` are present.

## Install Nix (multi-user)

Run in a real interactive WSL terminal (the installer calls `sudo` and needs a
TTY; without one it aborts on the first `sudo` and rolls back cleanly). Use
the pinned command above (repeated here for the copy-paste path):

```bash
sh <(curl -L https://releases.nixos.org/nix/nix-2.34.7/install) --daemon
```

Then open a new shell (`exec bash -l`) and enable flakes per user:

```bash
mkdir -p ~/.config/nix
printf 'experimental-features = nix-command flakes\n' >> ~/.config/nix/nix.conf
nix --version && nix flake --help >/dev/null && echo "flakes OK"
```

Alternative: the Determinate Systems installer
(`curl -fsSL https://install.determinate.systems/nix | sh -s -- install`)
enables flakes itself and has a clean `nix-installer uninstall`. Either works;
the official one keeps provenance simplest.

First check against this repo, from `/mnt/c/git/dawo-appliance`:

```bash
nix flake check
nix build .#bootstrap && ./result/bin/dawo-appliance-bootstrap version
```

The first run populates `/nix` from the binary cache (hundreds of MB to a few
GB); later runs reuse it.

## Make KVM usable inside the Nix sandbox

The VM tests (`test-installer-boot`, `test-appliance-boot`, `appliance-vm`)
start QEMU with `accel=kvm:tcg`: if KVM is not usable they **silently fall back
to TCG software emulation** and take minutes instead of seconds per boot. That
happened on this machine for months before it was noticed (2026-09-25). Two
things are needed, and there is one trap:

1. Nix must advertise the `kvm` system feature
   (`extra-system-features = kvm` in `/etc/nix/nix.conf`; restart `nix-daemon`).
2. The sandbox build user must be able to open `/dev/kvm`. **Trap:** adding
   `nixbld*` to group `kvm` is not enough, because the Nix sandbox drops
   supplementary groups. `/dev/kvm` must be mode `0666`, **persistently**: a
   systemd-tmpfiles rule `/etc/tmpfiles.d/99-kvm-nix-sandbox.conf`
   (`z /dev/kvm 0666 - - -`) applied at every boot, plus the udev rule
   `/etc/udev/rules.d/99-kvm-nix-sandbox.rules` for hot-plug. On WSL the udev
   rule alone does not survive `wsl --shutdown` (issue #37).

Do not do this by hand; the re-entrant checker reports and, with `APPLY=1`,
fixes it:

```bash
bash scripts/speed-check.sh            # report: OK / FIX per item
APPLY=1 bash scripts/speed-check.sh    # apply fixes (asks for your sudo password)
nix build .#check-kvm --rebuild        # proves /dev/kvm is writable INSIDE the sandbox
```

`scripts/verify.sh` runs the same probe (`kvm-in-sandbox`) before the boot
tests, so a regression shows up in `verification-latest.md`. No logout is
needed: builds run via the daemon, so your own shell's groups are irrelevant.

## WSL2 resources (`.wslconfig`)

By default WSL2 gets half the RAM. `%USERPROFILE%\.wslconfig` on the Windows
side sets more; the reference laptop (32 GB) uses:

```ini
[wsl2]
memory=24GB
processors=12
swap=8GB
nestedVirtualization=true
```

Apply with `wsl --shutdown` (this stops every running WSL process, including a
running appliance VM). `nestedVirtualization` is needed for KVM inside the
appliance VM (Slice 4). `scripts/speed-check.sh` reports whether the file
exists and what WSL currently sees.

## Uninstall / rollback

- Official installer: follow the uninstall steps in the Nix manual (stop and
  disable `nix-daemon`, remove `/nix`, the `nixbld` users and the shell-profile
  snippets).
- Determinate Systems installer: `/nix/nix-installer uninstall`.
