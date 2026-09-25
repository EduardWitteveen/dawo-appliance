# Architecture

> Experimental and unofficial. See `README.md`. Why the project exists and
> where it deviates from upstream: `docs/purpose.md`.

## Goal

A reproducible appliance that demonstrates a digitally autonomous government
workplace, delivered as a **small** bootable installer ISO. The ISO does not
contain the VMs, container images, or application payloads; it downloads pinned,
verified artifacts after booting. The installed system **is** the DAWO pilot
workplace (same DAWO-Core profile, desktop, apps and policies), plus the
virtual machine, Kubernetes and Mijn Bureau layers on top
(`docs/adr/0003-workplace-parity.md`).

## Boot-to-demo flow (target)

The installer, once booted, performs these steps in order:

1. Establish an internet connection.
2. Download a pinned release of this repository.
3. Verify downloaded artifacts (checksums; signatures later).
4. Install NixOS (to an explicit, confirmed target disk).
5. Configure the DAWO workplace (DAWO-Core `profiles-dawo-generic`, Plasma).
6. Configure KVM/libvirt.
7. Download or build one Ubuntu 24.04 VM.
8. Automatically start that VM.
9. Install/start single-node K3s inside the VM.
10. Deploy Mijn Bureau.
11. Wait until Mijn Bureau is healthy.
12. Open Mijn Bureau in the browser.

Steps 4–12 are destructive and/or heavy; v0.1 builds them incrementally behind
explicit confirmation. Slices 1–2 implement steps 1–4 (the plan is
non-destructive; `install` is gated); Slice 3 implements steps 5–6; steps 7–12
are slices 4–7 (`docs/roadmap.md`). Steps 5–12 take effect on the **installed
host after reboot**, not on the live ISO; the ISO only installs.

## Target topology (v0.1)

```
NixOS host (x86-64) = DAWO workplace + additions
├── DAWO-Core profiles-dawo-generic: KDE Plasma 6 + SDDM, pilot app sets,
│   nl_NL, mandatory hardening, printing/scanning, Flatpak   (upstream, unchanged)
├── browser (Firefox/Chromium from the profile) — opens the dashboard at the end
├── KVM / libvirt                                            (addition)
└── Ubuntu 24.04 guest VM                                    (addition)
    └── single-node K3s
        └── Mijn Bureau (Helmfile, pinned rev)
            └── dashboard "bureaublad" — the URL opened in the browser
```

## Component boundaries

| Layer | What we own | What we consume (pinned) |
| --- | --- | --- |
| Host OS | Live ISO, host NixOS config, explicit-target disko | DAWO-Core `flake.modules.nixos.*` (`profiles-dawo-generic`, boot, maid) |
| Bootstrap | `installer/bootstrap` command, manifest format + verify | — |
| Virtualisation | libvirt domain XML, cloud-init for the guest | nixpkgs libvirt/qemu, Ubuntu 24.04 cloud image |
| Kubernetes | K3s install/config inside the guest | pinned K3s release |
| Application | Helmfile driver + environment values | mijn-bureau-infra (Helmfile, charts, images) |
| Verification | health checks, browser-open, parity check | upstream documented health checks |

We **consume** upstream, we do not fork or copy it. DAWO-Core is a flake input;
Mijn Bureau is driven through its documented Helmfile / single-VPS install path,
pinned by revision.

## Reuse model for DAWO-Core

DAWO-Core exports reusable modules as `flake.modules.nixos.<name>` (its own
convention, via `flake-parts` + `import-tree`), **not** the conventional
`nixosModules.*`. The appliance flake takes `dawo-core` as an input (pinned to a
release tag) and imports **the same set a pilot client host imports**:
`boot-loader`, `boot-plymouth-bzk`, `profiles-dawo-generic`,
`maid-dawo-generic`, then sets the same host choices (`dawo.desktop.plasma.enable`,
`dawo.apps.{office,comms,creative,media}.enable`, `dawo.secureboot.enable =
false`). Deviations are limited to the list in ADR 0003: our disko module
(upstream's is hard-coded to `/dev/nvme0n1` and uses LUKS), a generic hardware
module, `dawo.autoUpdate.enable = false` (comin would otherwise rebuild the
host from Codeberg `main`), and an install-time password for the `dawo` user.

Upstream's `hosts/dawo-installer` is a headless fleet-imaging ISO and is not
used; see ADR 0002.

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
- **Explicit target + confirmation.** The only disk-writing action is
  `install`, which requires both `--target-disk <dev>` and `--confirm-destroy`,
  refuses mounted or live-medium devices, and offers `--dry-run`. `plan` and
  `verify` refuse the destructive flags. The disko module's default device is a
  non-existent sentinel.
- **Secrets at install time.** The Mijn Bureau master password, its derived
  secrets and the local user's password are generated on the host during
  install and never stored in Git.

## Networking / TLS for a local demo (design note)

Upstream's documented single-node path uses Let's Encrypt + a public domain +
email. A self-contained local appliance demo cannot rely on that. The intended
v0.1 approach is `tls.selfSigned: true` with local name resolution for a chosen
base domain (e.g. a `*.dawo.internal` wildcard resolved on the host/VM) and
the generated CA trusted by the host and its browsers. Decided in ADR 0004 (OQ-3 resolved).

## Extensibility (structure only, not built)

`apps/profiles/` is reserved for additional application profiles (e.g. other
suites). v0.1 ships only the `mijn-bureau` profile. New profiles plug into the
same manifest + Helmfile driver pattern without changing the host or bootstrap.
