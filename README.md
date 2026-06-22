# dawo-appliance

> **Experimental and unofficial.** This is an independent experiment. It is
> **not** an official DAWO, Mijn Bureau, or Ministerie van BZK distribution and
> is not endorsed by them.

A reproducible appliance for **demonstrating a digitally autonomous government
workplace**. The deliverable is a small, bootable installer ISO that — after
booting — sets up a NixOS host with a DAWO-based desktop, runs an Ubuntu 24.04
VM via KVM/libvirt, brings up single-node K3s inside that VM, deploys
[Mijn Bureau](https://code.overheid.nl/MinBZK/mijn-bureau-infra), waits until it
is healthy, and opens it in the browser.

## Target architecture (v0.1)

```
NixOS host
├── DAWO-based desktop (KDE Plasma 6)
├── browser
├── KVM/libvirt
└── Ubuntu 24.04 VM
    └── K3s (single node)
        └── Mijn Bureau
```

## Status

Built in vertical slices (`docs/roadmap.md`); each is independently runnable.
Live session handoff: `docs/STATUS.md` (or run `bash scripts/status.sh`).

| Slice | What | State |
| --- | --- | --- |
| 0 | Scaffolding: pinned manifest + checksum, Nix flake/dev shell, bootstrap `plan`/`verify` | ✅ Done |
| 1 | Non-destructive live ISO + bootstrap dry-run | ✅ **Done & verified** |
| 2 | Host install to disk (disko, gated by `--target-disk` + `--confirm-destroy`) | 🟡 2a done (host + storage); 2b next (operator `install`, LUKS) |
| 3 | DAWO desktop (KDE Plasma 6) + KVM/libvirt | ⬜ Scaffolding |
| 4 | Ubuntu 24.04 VM (libvirt + cloud-init) | ⬜ Scaffolding |
| 5 | Single-node K3s in the VM | ⬜ Scaffolding |
| 6 | Mijn Bureau (Helmfile) | ⬜ Scaffolding · needs OQ-3 |
| 7 | Health check + auto-open browser | ⬜ Scaffolding · needs OQ-3 |

**Slice 1** produces `dawo-appliance-installer.iso`: it boots, brings up
networking, ships `dawo-appliance-bootstrap`, downloads + checksum-verifies a
pinned manifest, prints the install plan, and **writes nothing to disk**. It is
verified two ways — the offline dry-run suite (`nix flake check`, no privileges)
and a full headless boot test (`nix build .#test-installer-boot`, needs KVM).

Slices 5–7 (full Mijn Bureau) need a large host to actually run end-to-end (see
hardware requirement below); their build/config can still be validated locally.

## Scope for v0.1

Supported: x86-64, online install, one physical machine, one Ubuntu 24.04 VM,
single-node K3s, Mijn Bureau, automatic start, a local health check, and
automatic opening of the browser.

Explicitly **out of scope** for v0.1: openDesk, Nextcloud AIO, multiple
Kubernetes nodes, HA, org-specific branding, Active Directory, and offline
installation. The structure allows adding application profiles later, but those
profiles are not built yet.

## Hardware requirement (read before you build)

Mijn Bureau's single-node deployment requires **>= 12 vCPU and >= 48 GiB RAM**
(upstream `prerequisites.md`). The VM that runs it must therefore be large, so
the **physical appliance host needs roughly >= 16 vCPU and >= 56–64 GiB RAM**.
A typical 16 GiB laptop can build and dry-run the installer but cannot run the
full stack.

## Upstream projects (consumed, not forked)

- DAWO-NixOS — <https://code.overheid.nl/MinBZK/DAWO-NixOS>
- Mijn Bureau infra — <https://code.overheid.nl/MinBZK/mijn-bureau-infra>

Exact inspected revisions and pins: `docs/upstream/revisions.md` and
`manifest/appliance-manifest.json`.

## Repository layout

| Path | Purpose |
| --- | --- |
| `flake.nix`, `flake.lock`, `nix/` | Nix flake, dev shell, host/system Nix modules |
| `installer/iso/` | Live installer ISO definition |
| `installer/bootstrap/` | The appliance bootstrap command (runs on the booted ISO) |
| `hosts/` | NixOS host definitions and disko (storage) profiles |
| `vm/` | Ubuntu 24.04 VM definition (libvirt domain, cloud-init) |
| `k8s/` | Single-node K3s bootstrap |
| `apps/mijn-bureau/` | Mijn Bureau deployment config (Helmfile driver) |
| `apps/profiles/` | Placeholder for future application profiles |
| `health/` | Health checks |
| `manifest/` | Pinned release manifest + checksum |
| `tests/` | Local tests |
| `docs/` | Architecture, development, roadmap, ADRs, open questions |

## Getting started (development)

See `docs/development.md` (and `docs/nix-setup.md` to install Nix). Start a
session with `bash scripts/status.sh` to see where things stand.

Quick local validation that needs **no Nix and no root**:

```bash
make test          # or: tests/test-bootstrap-dryrun.sh
make plan          # run the bootstrap dry-run against the local manifest
```

With Nix available:

```bash
nix flake check                    # portable checks (dry-run + shellcheck)
nix build .#installer-iso          # build the live ISO (~1.4 GiB)
nix build .#test-installer-boot -L # headless boot test (needs KVM)
```

## License

Licensed under the **EUPL-1.2** (European Union Public Licence v. 1.2). See
[`LICENSE`](LICENSE). This aligns with Mijn Bureau (EUPL-1.2) and is compatible
with DAWO-NixOS (GPL-3.0), which the EUPL lists as a Compatible Licence.

## Security

No passwords, tokens, private keys, or generated secrets are stored in Git.
Secrets are generated during installation. See `docs/architecture.md`.
