# Documentation index

> Experimental and unofficial. Not an official DAWO, Mijn Bureau or BZK
> distribution. Front door: [`../README.md`](../README.md).

One line per document. Generated files are marked; never edit those by hand.

## Start here

| Document | What it answers |
| --- | --- |
| [`purpose.md`](purpose.md) | Why the project exists, what it adds, where it deviates from upstream, what it costs, what "done" means for v0.1. |
| [`deviations.md`](deviations.md) | Every deviation from upstream or common practice, one line each, with the reason and where it is motivated. |
| [`architecture.md`](architecture.md) | The boot-to-demo flow, topology, component boundaries, manifest trust chain, safety model. |
| [`roadmap.md`](roadmap.md) | The vertical slices 0–7 with their state and what each verified. |
| [`STATUS.md`](STATUS.md) | Session handoff: now / next / recently done. Printed by `bash scripts/status.sh`. |

## Working on it

| Document | What it answers |
| --- | --- |
| [`development.md`](development.md) | Day-to-day commands: local checks without Nix, Nix checks and builds, `appliance-vm`, manifest checksum, make targets. |
| [`testing.md`](testing.md) | Which check covers which requirement; how to read a failure; the "a bug becomes a check first" rule. |
| [`releasing.md`](releasing.md) | How a release is cut: tag, ISO, manifest, draft GitHub release; how the bootstrap finds the release manifest. |
| [`nix-setup.md`](nix-setup.md) | Runbook for installing Nix in WSL2 and making KVM usable inside the Nix sandbox. |
| [`demo-hardware.md`](demo-hardware.md) | Hardware requirements, BIOS/UEFI settings, USB media creation and safe verification for demo laptops. |
| [`verification-latest.md`](verification-latest.md) | **Generated** by `REPORT=1 bash scripts/verify.sh`: result and timings of the latest real run. |
| `verification-history.csv` | **Generated**: every recorded check duration, feeds the mean/range columns above. |
| [`screenshots/README.md`](screenshots/README.md) | Rules for the screenshots in the README; [`screenshots/PROVENANCE.md`](screenshots/PROVENANCE.md) is **generated** by `scripts/screenshots.sh`. |

## Decisions and unknowns

| Document | What it answers |
| --- | --- |
| [`adr/0001-project-scope.md`](adr/0001-project-scope.md) | Scope and boundaries of v0.1; consume-not-fork; pin everything; non-destructive by default. |
| [`adr/0002-own-installer-iso.md`](adr/0002-own-installer-iso.md) | Why we keep our own installer next to upstream's headless fleet installer. |
| [`adr/0003-workplace-parity.md`](adr/0003-workplace-parity.md) | The host is the DAWO pilot workplace, unchanged, plus additions; the list of deviations. |
| [`adr/0004-local-dns-and-tls.md`](adr/0004-local-dns-and-tls.md) | **Accepted:** local DNS + TLS for the demo: base domain `dawo.internal`, per-install appliance CA, cert-manager CA issuer, browser trust (resolves OQ-3). |
| [`adr/0005-ai-agent-conduct.md`](adr/0005-ai-agent-conduct.md) | **Accepted:** AI agent conduct and multi-agent workflow: GitHub as SSOT, thoughtful investigation, English conventions, safety. |
| [`open-questions.md`](open-questions.md) | OQ-1 to OQ-9: blocking and non-blocking unknowns, with resolutions. |

## Upstream

| Document | What it answers |
| --- | --- |
| [`upstream/revisions.md`](upstream/revisions.md) | The exact DAWO-Core and mijn-bureau-infra revisions inspected and pinned, and the facts that shape our design. |
| [`upstream/ecosystem.md`](upstream/ecosystem.md) | Which DAWO / Mijn Bureau repositories exist and which ones we consume. |
| [`upstream/pins-vm-k3s.md`](upstream/pins-vm-k3s.md) | Researched pins with checksums for the Ubuntu 24.04 cloud image and K3s (OQ-6), ready for the manifest once approved. |
| [`upstream/image-digests.md`](upstream/image-digests.md) | Why and how every Mijn Bureau image tag is resolved to a `sha256:` digest in `manifest/image-digests.json` (OQ-5), how `--check` catches re-pointed tags, and the Slice 6 follow-up to pull by digest. |
| [`upstream/mijn-bureau-sizing.md`](upstream/mijn-bureau-sizing.md) | Mijn Bureau resource sizing at rev `b2ae545` (`predicted_resources.py` per preset and app subset, K3s/OS/desktop overhead) and the proposed `laptop-demo` / `full` profiles (#11). |

## Elsewhere in the repository

- [`../AGENTS.md`](../AGENTS.md): universal rules, environment notes and working method for AI coding agents and human contributors.
- [`../hosts/appliance/README.md`](../hosts/appliance/README.md): the installed host's modules.
- [`../hosts/profiles/disko/README.md`](../hosts/profiles/disko/README.md): the storage layout and the no-LUKS decision.
- `../vm/`, `../k8s/`, `../apps/`, `../health/`: one README each, scaffolding for slices 4–7.
- [`../manifest/appliance-manifest.json`](../manifest/appliance-manifest.json): every pin, protected by its `.sha256`.
