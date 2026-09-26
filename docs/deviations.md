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
| D14 | Images pulled by tag | Images pinned by digest (`container.<key>.tag = "tag@sha256:digest"`, spliced by `apps/mijn-bureau/deploy.sh`'s `phase_values`; a post-deploy check compares running pods' `imageID`s against the pins) | Tags can be re-pointed; `--check` now runs in `scripts/verify.sh` to catch it | active | `docs/upstream/image-digests.md`, #9 |
| D15 | cert-manager v1.16.2 (EOL, K8s <= 1.32) | **No deviation (maintainer decision, #10):** we keep upstream's v1.16.2 on K3s 1.36 | Parity with mijn-bureau-infra; no removed Kubernetes API is known to break it. Proven at the first real deploy by a check (cert-manager pods Ready, a `Certificate` issued by the appliance CA). Only if that fails: pin a supported line (1.21.x) as a real deviation with an ADR. Pinning K3s to 1.32 is rejected (that line is itself end-of-life) | decided: follow upstream | #10 |
| D16 | >= 12 vCPU / 48 GiB for single-node, `resourcesPreset: none` | Default `laptop-demo` profile: 5 core apps, global preset `micro` (per-app map unchanged), guest 8 vCPU / 16 GiB; `full` profile keeps upstream sizing | Must run next to the desktop on the 32 GB reference laptop | planned | `docs/upstream/mijn-bureau-sizing.md`, #11 |

## Known upstream issues (tracked here, not reported upstream)

Problems found in upstream code that we consume by pin. Per `AGENTS.md` rule 11
(maintainer decision, #35) they are **not** reported to upstream trackers
during v0.1: each has its own GitHub issue with the label `upstream`, and this
table records our workaround so it stays traceable. Reporting upstream is a
later, separate decision. A workaround that changes behaviour is also a
deviation and gets its own row above.

| # | Upstream (pin) | Problem | Our workaround | Issue |
|---|---|---|---|---|
| U1 | DAWO-Core 0.1.3 (`maid-dawo-generic`) | `kdeconfig-cleanup.service` fails on the first boot of a fresh install: `find: '/home/*/.config': No such file or directory`, because no user has logged in yet. Harmless; it runs again later | None in the code: we do not patch upstream. No check asserts "no failed units"; a check that does must allow this unit explicitly and point at U1. Suggested upstream fix: a tolerant glob (`nullglob`, or `find /home -mindepth 2 -maxdepth 2 -name .config`) | #35 |

## Versus common practice (tooling and process)

| # | Standard | What we do | Why | Status | Motivation |
| --- | --- | --- | --- | --- | --- |
| D17 | `/dev/kvm` mode 0660, group `kvm` | Development machine: udev rule for mode 0666 | The Nix sandbox drops supplementary groups; without it every VM test silently runs under TCG | active (dev machine only) | `docs/nix-setup.md` |
| D18 | Continuous integration on every push | Local `scripts/verify.sh` with a committed report | No CI runner with KVM yet; the report is the evidence in each PR | active | `docs/testing.md` |
| D19 | Squash merges | Rebase merges (`gh pr merge --rebase`) | Squash lets GitHub author the commit with the account's e-mail; rebase keeps the noreply author | active | #19, `AGENTS.md` |
| D20 | disko-install builds its install artifacts at run time | The e2e test pre-builds the same artifacts by mirroring disko's `install-cli.nix` (rev de57087) | The test VM is offline; must be kept in sync when the disko pin moves | active (tests only) | `nix/tests/install-e2e.nix` |
| D21 | Private key files are root-only (0600/0700, owner and group `root`) | The guest operator SSH key is `0600` owned by `dawo`; its directory is `0750 root:libvirtd` (`hosts/appliance/guest-vm.nix`) | Slice 7's health check runs as `dawo` (in `libvirtd`) and must read this key; root must too. OpenSSH refuses a group-readable key owned by the invoking user, so `0640 root:libvirtd` broke every root SSH (#75). Never world-readable, never in Git | active | ADR 0003, #12, #75 |
| D22 | A CA private key never leaves the host it was generated on | The appliance CA private key (`ca.key`) is transported once, alongside the certificate, into the guest through the cloud-init seed ISO (`write_files`, root-only in the guest at `/etc/dawo-appliance/ca.key`; the seed ISO itself is root-only on the host, `hosts/appliance/guest-vm.nix`) | cert-manager's CA `ClusterIssuer` needs the CA private key in-cluster to sign certificates (ADR 0004); the seed ISO is generated per install and attached only to this one local guest, never uploaded or shared — a demo trade-off, **not for production** | active | ADR 0004, #6 |
| D23 | K3s is installed online (`get.k3s.io` / GitHub release downloads at install time) | The guest installs the pinned K3s release air-gapped: the host fetches the binary, `install.sh` and the air-gap image tarball at build time as fixed-output derivations (manifest SHA-256) and attaches them to the guest as a read-only ISO labelled `DAWO_K3S`; `k8s/bootstrap/install-k3s.sh` then uses `K3S_OFFLINE_DIR` (`hosts/appliance/guest-vm.nix`, `vm/ubuntu-2404/user-data.yaml.in`) | K3s' own documented air-gap method: every byte is pinned and verified by Nix, the guest needs no internet for K3s, and the nested test VM (offline) can prove a Ready node. Without the disk the stage falls back to the online install | active | #7 |
| D24 | All repository content is in English (`AGENTS.md` rule 2) | Documents actually written for the non-technical target audience are in Dutch instead — `docs/README.md` indexes the current set (check there, not here, for the exact file list; as of writing: the `README.md` preamble, `docs/demo-script.md`, `docs/demo-hardware.md`, everything under `docs/audience/`). The project's own technical/architectural docs (`docs/purpose.md` and similar) are NOT in scope for this exception even if a PR translates one by mistake — see #84/#92 | Written for municipal civil servants, policy advisors and CISOs, who need Dutch-language material before the English technical documentation; all code, Nix modules, tests, architecture docs and ADRs stay English-only per the rule | active | `AGENTS.md` rule 2 exception, #44, #84, #92 |
