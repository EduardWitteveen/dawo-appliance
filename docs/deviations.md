# Deviation register

> Experimental and unofficial. See `README.md`.

The rule (`AGENTS.md`, "Standards first"): follow upstream and common practice
unless it stands in the way of the goal, **a live installer that installs and
runs the appliance on one machine**. Every place where we do something
differently is listed here, one line each, with the reason and where it is
motivated in full. A deviation that is not in this list is a bug, or it must be
added with its motivation in the same pull request.

Status: **active** (in the code), **planned** (decided, not yet built),
**open** (under discussion; see the issue).

## Versus DAWO-Core (the workplace)

| # | Standard (upstream) | What we do | Why | Status | Motivation |
| --- | --- | --- | --- | --- | --- |
| D1 | Headless fleet installer (`hosts/dawo-installer`, SSH key and wifi baked in, `nixos-anywhere` from an operator machine) | Own interactive live ISO with `dawo-appliance-bootstrap` | One machine, no operator host, no secrets in the image, manifest verification | active | ADR 0002 |
| D2 | `disko-single-nvme-luks`: fixed `/dev/nvme0n1`, LUKS | Own disko layout, explicit `--target-disk` + `--confirm-destroy`, no LUKS in v0.1 | Never a default device (hard rule); demo simplicity | active | ADR 0003, roadmap Slice 2b, #23 |
| D3 | A hardware module per laptop model | Generic: `hardware-dawo-base` plus microcode for both CPU vendors and NixOS' `qemu-guest` profile (virtio drivers) | The appliance is not one laptop model, and must also install into a VM | active | ADR 0003 |
| D4 | Auto-update with comin from Codeberg `main` | `dawo.autoUpdate.enable = false` | The appliance is a pinned, reproducible artifact; comin would drop our additions | active | ADR 0003, `nix/parity.nix` |
| D5 | SDDM login screen | Auto-login as `dawo` plus a welcome dialog | Demo: nothing to type | active | ADR 0003, `nix/parity.nix` |
| D6 | Documented default password, never shown | Password shown in the welcome dialog; with `--generate-password` also stored readable on disk | Demo ergonomics; **not for production** | active | ADR 0003 |
| D7 | Flake built with `flake-parts` + `import-tree` | A plain flake that imports DAWO-Core's modules | Small repository; we consume upstream modules, we do not publish our own | active | this register |
| D8 | (tests) boot splash with `consoleLogLevel 0`; read-only `nixpkgs` in the test driver | Test-only overrides `consoleLogLevel 7` and `pkgsReadOnly = false` | The NixOS test driver needs kernel messages; upstream sets `nixpkgs.config` | active (tests only) | `flake.nix` comments |

## Versus mijn-bureau-infra (the collaboration suite)

| # | Standard (upstream) | What we do | Why | Status | Motivation |
| --- | --- | --- | --- | --- | --- |
| D9 | Ubuntu 24.04 server on the network | Ubuntu 24.04 VM on the same host (KVM/libvirt) | One box | active | `docs/purpose.md` |
| D10 | Let's Encrypt with a public wildcard DNS record | Base domain `dawo.internal`, libvirt dnsmasq wildcard, per-install appliance CA as cert-manager `ClusterIssuer` | No public domain; self-contained demo | active (host), planned (cluster) | ADR 0004 |
| D11 | K3s from `get.k3s.io`, unpinned | Pinned `v1.36.4+k3s1`, binary and install script verified by SHA-256 | Pin everything (hard rule) | active | `docs/upstream/pins-vm-k3s.md` |
| D12 | `install.sh` fetches sub-scripts from a live raw URL (default: a fork branch) | Run from the pinned checkout of rev `b2ae545` | Reproducibility; no code from a moving URL | active | `apps/mijn-bureau/README.md` |
| D13 | Master password passed on the command line | Generated once inside the guest, root-only | No secrets in Git or shell history | active | `apps/mijn-bureau/README.md` |
| D14 | Images pulled by tag | Images pinned by digest | Tags can be re-pointed | planned | `docs/upstream/image-digests.md`, #9 |
| D15 | cert-manager v1.16.2 (EOL, K8s <= 1.32) | Undecided on K3s 1.36 | Supportability vs parity | open | #10 |
| D16 | >= 12 vCPU / 48 GiB for single-node, `resourcesPreset: none` | Default `laptop-demo` profile: 5 core apps, global preset `micro` (per-app map unchanged), guest 8 vCPU / 16 GiB; `full` profile keeps upstream sizing | Must run next to the desktop on the 32 GB reference laptop | planned | `docs/upstream/mijn-bureau-sizing.md`, #11 |

## Versus common practice (tooling and process)

| # | Standard | What we do | Why | Status | Motivation |
| --- | --- | --- | --- | --- | --- |
| D17 | `/dev/kvm` mode 0660, group `kvm` | Development machine: udev rule for mode 0666 | The Nix sandbox drops supplementary groups; without it every VM test silently runs under TCG | active (dev machine only) | `docs/nix-setup.md` |
| D18 | Continuous integration on every push | Local `scripts/verify.sh` with a committed report | No CI runner with KVM yet; the report is the evidence in each PR | active | `docs/testing.md` |
| D19 | Squash merges | Rebase merges (`gh pr merge --rebase`) | Squash lets GitHub author the commit with the account's e-mail; rebase keeps the noreply author | active | #19, `AGENTS.md` |
| D20 | disko-install builds its install artifacts at run time | The e2e test pre-builds the same artifacts by mirroring disko's `install-cli.nix` (rev de57087) | The test VM is offline; must be kept in sync when the disko pin moves | active (tests only) | `nix/tests/install-e2e.nix` |
