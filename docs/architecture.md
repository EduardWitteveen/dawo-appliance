# Architecture

> Experimental and unofficial. See `README.md`.

## Goal

A reproducible appliance that demonstrates a digitally autonomous government
workplace, delivered as a **small** bootable installer ISO. The ISO does not
contain the VMs, container images, or application payloads; it downloads pinned,
verified artifacts after booting.

## Boot-to-demo flow (target)

The installer, once booted, performs these steps in order:

1. Establish an internet connection.
2. Download a pinned release of this repository.
3. Verify downloaded artifacts (checksums; signatures later).
4. Install NixOS (to an explicit, confirmed target disk).
5. Configure a DAWO-based desktop environment.
6. Configure KVM/libvirt.
7. Download or build one Ubuntu 24.04 VM.
8. Automatically start that VM.
9. Install/start single-node K3s inside the VM.
10. Deploy Mijn Bureau.
11. Wait until Mijn Bureau is healthy.
12. Open Mijn Bureau in the browser.

Steps 4–12 are destructive and/or heavy; v0.1 builds them incrementally behind
explicit confirmation. The **first** vertical slice implements steps 1–3 plus a
"show what would be installed" plan, and **stops before step 4** (no disk
writes).

## Target topology (v0.1)

```
NixOS host (x86-64)
├── DAWO-based desktop (KDE Plasma 6 + SDDM, from DAWO-NixOS modules)
├── browser (opens the dashboard at the end)
├── KVM / libvirt
└── Ubuntu 24.04 guest VM
    └── single-node K3s
        └── Mijn Bureau (Helmfile)
            └── dashboard "bureaublad" — the URL opened in the browser
```

## Component boundaries

| Layer | What we own | What we consume (pinned) |
| --- | --- | --- |
| Host OS | Live ISO, host NixOS config, explicit-target disko | DAWO-NixOS `flake.modules.nixos.*` (desktop, profiles) |
| Bootstrap | `installer/bootstrap` command, manifest format + verify | — |
| Virtualisation | libvirt domain XML, cloud-init for the guest | nixpkgs libvirt/qemu, Ubuntu 24.04 cloud image |
| Kubernetes | K3s install/config inside the guest | pinned K3s release |
| Application | Helmfile driver + environment values | mijn-bureau-infra (Helmfile, charts, images) |
| Verification | health checks, browser-open | upstream documented health checks |

We **consume** upstream, we do not fork or copy it. DAWO-NixOS is a flake input;
Mijn Bureau is driven through its documented Helmfile / single-VPS install path,
pinned by revision.

## Reuse model for DAWO-NixOS

DAWO-NixOS exports reusable modules as `flake.modules.nixos.<name>` (its own
convention, via `flake-parts` + `import-tree`), **not** the conventional
`nixosModules.*`. To reuse, the appliance flake takes `dawo-nixos` as an input
and references e.g. `profiles-dawo-generic` and `desktop-plasma`. The DAWO disko
module is hard-coded to `/dev/nvme0n1`, so the appliance provides its **own**
parameterised, explicit-target disko module (never a default device).

## Manifest + verification

`manifest/appliance-manifest.json` is the single pinned description of a release:
upstream revisions, nixpkgs rev, K3s version, chart versions, and image
references. The bootstrap downloads this manifest and verifies it against a
checksum baked into the bootstrap (`manifest/appliance-manifest.json.sha256`).
A tampered or truncated manifest fails verification and aborts. Per-artifact
checksums/digests are verified before each artifact is used.

Trust chain (v0.1): baked-in SHA-256 of the manifest → manifest pins each
artifact by version/digest → each artifact is checksum-verified on download.
Signature verification (e.g. minisign/cosign — upstream ships `cosign.pub`) is a
planned hardening step (see roadmap), not in v0.1.

## Safety model

- **Dry-run by default.** The bootstrap's default action is `plan`: it shows
  what would be installed and writes nothing to disk.
- **Explicit target + confirmation.** Any disk-writing action requires both
  `--target-disk <dev>` and `--confirm-destroy`. v0.1 does not implement the
  write path; if those flags are given it reports "not implemented" and exits.
- **Secrets at install time.** The Mijn Bureau master password and all derived
  secrets are generated on the host during install and never stored in Git.

## Networking / TLS for a local demo (design note)

Upstream's documented single-node path uses Let's Encrypt + a public domain +
email. A self-contained local appliance demo cannot rely on that. The intended
v0.1 approach is `tls.selfSigned: true` with local name resolution for a chosen
base domain (e.g. a `*.appliance.local` wildcard resolved on the host/VM). The
exact DNS mechanism is an open question (OQ-3).

## Extensibility (structure only, not built)

`apps/profiles/` is reserved for additional application profiles (e.g. other
suites). v0.1 ships only the `mijn-bureau` profile. New profiles plug into the
same manifest + Helmfile driver pattern without changing the host or bootstrap.
