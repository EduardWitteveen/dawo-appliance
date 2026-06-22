# Nix setup (WSL2)

How to install Nix on this machine so the flake builds work (`nix flake check`,
`nix develop`, and the Slice 1 ISO build `nix build .#installer-iso`).

> **This installs system software (a host change).** Per the project rules, the
> maintainer runs the install commands — Claude prepares and verifies them but
> does not execute them. In this session, run a command yourself by typing it
> with a leading `!` so its output lands in the conversation.

## Why Nix here, and where the store goes

- OQ-1 is resolved: `/mnt/c` mounts with `metadata`, so `git`/`chmod` work and
  the working tree can stay at `/mnt/c/git/dawo-appliance`.
- The **Nix store lives at `/nix`**, which is on the WSL **ext4** root
  filesystem — fast, and exactly where we want it. Do **not** relocate the store
  onto the `/mnt/c` 9p mount (slow). The default install already does the right
  thing; no extra configuration is needed for store placement.

## Pre-flight (verified 2026-06-22 on this machine)

All green here — re-check with `! <cmd>` if the environment changed:

| Check | Command | Expected | Status |
| --- | --- | --- | --- |
| systemd up | `systemctl is-system-running` | `running` (or `degraded`) | ✅ running |
| ext4 free space | `df -h /` | several GB free (have ~954 GB) | ✅ |
| KVM (for later VM) | `test -e /dev/kvm` | present | ✅ |
| arch | `uname -m` | `x86_64` | ✅ |
| installer deps | `command -v curl xz` | both found | ✅ |
| clean slate | `test -e /nix` | absent | ✅ absent |

Because systemd is running, use the **multi-user (daemon)** install — the
standard, recommended mode.

## Install (run these yourself with `!`)

### 1. Install Nix (official installer, multi-user)

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

- Accept the prompts. It creates `/nix`, a `nix-daemon` systemd service, and
  build users (`nixbld*`).
- When it finishes, **open a new shell** (or `exec bash -l`) so the Nix profile
  is on `PATH`. In a fresh shell, `command -v nix` should resolve.

> Alternative — the **Determinate Systems** installer
> (`curl -fsSL https://install.determinate.systems/nix | sh -s -- install`)
> works well on WSL, enables flakes automatically, and has a clean
> `nix-installer uninstall`. The official installer above keeps provenance
> simplest (nixos.org only); pick either. If you use the DS one, skip step 2.

### 2. Enable flakes (official installer only)

The flake commands need the `nix-command` and `flakes` experimental features.
Enable them per-user (no sudo needed):

```bash
mkdir -p ~/.config/nix
printf 'experimental-features = nix-command flakes\n' >> ~/.config/nix/nix.conf
```

### 3. Verify Nix itself

```bash
nix --version
nix flake --help >/dev/null && echo "flakes OK"
```

## Verify against this repo

From the repo root (`/mnt/c/git/dawo-appliance`):

```bash
# Evaluate flake outputs + run the in-sandbox checks (bootstrap dry-run, shellcheck).
nix flake check

# Enter the dev shell (git, jq, shellcheck, shfmt, gnumake, qemu_kvm, nixpkgs-fmt).
nix develop      # then e.g. `make check`, and `exit` to leave

# Build the wrapped bootstrap (small, quick first build to confirm things work).
nix build .#bootstrap && ./result/bin/dawo-appliance-bootstrap version
```

A first `nix flake check` / `nix build` will download from the binary cache and
populate `/nix` (hundreds of MB to a few GB). That is expected and one-time.

## Build the Slice 1 ISO (large — only when ready)

```bash
nix build .#installer-iso
# Output symlink: ./result ; the ISO is under ./result/iso/*.iso
ls -lh result/iso/
```

This is a **large** build (downloads/builds a NixOS live system). It needs
real time, RAM, and disk. With ~954 GB free on ext4 and 15 GiB RAM, this machine
can build it (it cannot *run* the full appliance end-to-end — see OQ-2 — but
building and booting the non-destructive live ISO is in scope for Slice 1).

The booted ISO is non-destructive: it carries `dawo-appliance-bootstrap`, which
only runs `plan`/`verify` and refuses any disk-writing flags in v0.1.

## Uninstall / rollback

- Official installer: follow the uninstall steps in the Nix manual
  (stop/disable `nix-daemon`, remove `/nix`, the `nixbld` users, and the
  shell-profile snippets).
- Determinate Systems installer: `/nix/nix-installer uninstall`.

## Notes / follow-ups

- The flake's `checks.shellcheck` lints the bootstrap and the test but not
  `scripts/status.sh`; add it there for parity when convenient (it is already
  covered by `make lint`). Minor, non-blocking.
- `flake.lock` is hand-pinned to nixpkgs `nixos-25.11` rev
  `d6df3513510aa548c83868fd22bfddd0a8c0a0d4`; `nix flake check` validates it.
