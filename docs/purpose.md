# Purpose and rationale

> Experimental and unofficial. Not an official DAWO, Mijn Bureau or BZK
> distribution, and not endorsed by them. See `README.md`.

This document states what `dawo-appliance` is for, why it should exist next to
the official upstream projects, where it deliberately deviates from them, and
what that costs. It is the reference for scope discussions; ADRs record the
individual decisions (`docs/adr/`).

## In one paragraph

`dawo-appliance` turns two separate open-source government projects into **one
self-contained, reproducible demo machine**: boot a small installer ISO on a
single x86-64 computer, confirm the target disk, and end up with the **DAWO
workplace** (the NixOS-based government desktop, exactly as a pilot laptop gets
it) on screen, running a virtual machine that hosts **Mijn Bureau** (the
government collaboration suite) on single-node Kubernetes, with the Mijn Bureau
dashboard open in the browser. Every component is pinned to an exact upstream
revision and recorded in one manifest.

## The gap it fills

The two upstream projects are excellent at their own jobs and are not meant to
be a combined demo:

- **DAWO-Core** (`codeberg.org/DAWO/DAWO-Core`) delivers the workplace as a
  NixOS flake and installs it with **fleet tooling**: a headless provisioning
  ISO or PXE image with an operator's SSH key baked in, driven remotely with
  `nixos-anywhere`, aimed at imaging batches of laptops for a pilot
  (`docs/adr/0002-own-installer-iso.md`).
- **mijn-bureau-infra** (`code.overheid.nl/MinBZK/mijn-bureau-infra`) deploys
  the suite with Helmfile onto a Kubernetes cluster. Its documented single-node
  path assumes a **public server** with a wildcard DNS record, Let's Encrypt
  and at least 12 vCPU / 48 GiB RAM.

Someone who wants to *see the whole thing together*, on one box, without a
public domain, an operator workstation or cloud credentials, has to assemble it
by hand: install NixOS, find the right DAWO modules, set up KVM, create an
Ubuntu VM, install K3s, work around Let's Encrypt with self-signed TLS and local
DNS, and pin everything so a colleague sees the same result. That assembly is
this project.

## What it adds

1. **One artifact, one machine, one flow.** Boot, confirm, wait, use. No
   external services, no operator machine, no public domain.
2. **The real workplace, not a look-alike.** The installed host imports the
   same DAWO-Core profile a pilot laptop imports (`profiles-dawo-generic`),
   with the same desktop, apps, locale and mandatory hardening. Our additions
   sit next to it; nothing that shapes the user experience is overridden
   (`docs/adr/0003-workplace-parity.md`).
3. **Reproducible and auditable.** Exact revisions of DAWO-Core, nixpkgs,
   disko, mijn-bureau-infra, K3s, the Ubuntu image and every container image
   live in `manifest/appliance-manifest.json`, protected by a checksum the ISO
   carries. Two people building the same release get the same appliance.
4. **Safe by default.** Nothing writes to disk without an explicit target and
   an explicit confirmation; the default action shows the plan. No secrets are
   stored in Git; the Mijn Bureau master password and the local user password
   are generated at install time.
5. **An integration probe.** Building the appliance surfaces exactly where the
   two stacks do not yet meet: local DNS and TLS (OQ-3), resource needs
   (OQ-2), unpinned upstream install steps (OQ-6), tag-only image pins (OQ-5).
   Those findings are useful to upstream even if the appliance never is.
6. **A learning and evaluation vehicle** for NixOS, disko, libvirt, K3s and
   Helmfile in the Dutch government context, with every decision written down.

## What it is not

- Not an official distribution and not a channel for either upstream project.
- Not a production deployment: single node, no backups, no HA, self-signed
  TLS, no disk encryption in v0.1. Do not put real data on it.
- Not fleet management. Imaging many laptops, auto-update, Secure Boot and TPM
  enrolment are upstream's domain (DAWO-Core, DAWO-Sextant,
  DAWO-NixOS-installatie).
- Not a place to build features "for later": openDesk, Nextcloud AIO,
  multi-node, branding, Active Directory and offline install are out of scope
  (ADR 0001).

## Where it deviates from upstream, and why

| Area | Upstream | This appliance | Reason |
| --- | --- | --- | --- |
| Installer | headless ISO/PXE, remote `nixos-anywhere`, credentials baked in | interactive console installer, manifest-verified, gated disk writes, no secrets in the image | one machine, no operator host (ADR 0002) |
| Storage | Btrfs on LUKS, fixed `/dev/nvme0n1`, TPM2 unlock | Btrfs, explicit target disk, **no LUKS** in v0.1 | never a default device; demo simplicity (Slice 2b) |
| Hardware | per-laptop-model modules | generic Intel/AMD module | not one laptop model |
| Updates | comin pulls Codeberg `main` and rebuilds the device | auto-update **off**; updates are a new pinned release | reproducible artifact (ADR 0003) |
| Local user | `dawo` with a documented default password, SDDM login screen | auto-login as `dawo`, welcome dialog that shows the password (default, or the generated one with `install --generate-password`, which is kept readable on disk) | a demo must be usable without typing anything; **not for production** (ADR 0003) |
| Mijn Bureau host | Ubuntu 24.04 server on the network | Ubuntu 24.04 **VM** on the same machine (KVM/libvirt) | one box |
| TLS | Let's Encrypt, public wildcard DNS | self-signed CA, local wildcard DNS, CA trusted on the host | no public domain (OQ-3) |
| K3s | installed from `get.k3s.io` unpinned | pinned release + checksum | pin everything (OQ-6) |
| Install scripts | fetched from a raw `main` (or fork) URL at run time | fetched from the pinned revision | reproducibility |
| Master password | passed on the command line | generated on the host at install time | no secrets in Git or shell history |

## Advantages over doing it by hand or using upstream paths directly

- The demo can be repeated by anyone with the ISO and a big enough machine.
- What is shown is *the* workplace, so conclusions about the user experience
  transfer to the pilots.
- No public infrastructure, accounts or credentials are needed.
- Destructive steps are gated and tested; the dry-run suite and boot tests run
  without touching hardware.
- All versions are visible in one file, which makes "which Nextcloud is this?"
  a lookup rather than an investigation.

## Disadvantages and costs

- **Hardware.** Mijn Bureau alone wants 12 vCPU and 48 GiB RAM inside the VM,
  so the physical host needs roughly 16 vCPU and 56 to 64 GiB. A laptop can
  build and dry-run the installer but cannot run the full stack (OQ-2).
- **Not representative for security.** No disk encryption, self-signed TLS,
  auto-update off, single node, no backups. It demonstrates functionality, not
  a hardened deployment.
- **Lag.** Pins are deliberately behind upstream; every bump requires
  re-inspection and, for DAWO-Core, a parity review (ADR 0003).
- **Maintenance.** We own an ISO, a bootstrap, a disko module, a VM
  definition, a K3s installer, a Helmfile driver and health checks. Each is
  small, but they are ours.
- **Drift risk.** Parity with the pilot workplace has to be checked, not
  assumed; the parity check in Slice 3 exists for that reason.
- **Still not sovereign in the strict sense.** Nix inputs come from GitHub,
  container images from Docker Hub and GHCR. Upstream has the same dependency
  and a roadmap to mirror it; we inherit both.

## What "done" means for v0.1

1. Boot `dawo-appliance-installer.iso`; `dawo-appliance-bootstrap plan` shows
   the pinned plan and writes nothing.
2. `dawo-appliance-bootstrap install --target-disk DEV --confirm-destroy`
   installs the host; reboot.
3. Auto-login as `dawo` (ADR 0003); the Plasma desktop, apps, locale and
   policies match a DAWO pilot laptop at the pinned tag.
4. The Ubuntu VM starts automatically; K3s comes up; Mijn Bureau deploys from
   the pinned revision with a generated master password.
5. The health check reports all certificates ready and the dashboard
   responding; the browser opens `https://bureaublad.<base-domain>`.
6. All of this from pins in `manifest/appliance-manifest.json`; `nix flake
   check` and the boot tests are green.

Progress per slice: `docs/roadmap.md`, `docs/STATUS.md`.
