# Documentation index

> Experimental and unofficial. Not an official DAWO, Mijn Bureau or BZK
> distribution. Front door: [`../README.md`](../README.md).

One line per document. Generated files are marked; never edit those by hand.

## Start here

| Document | What it answers |
| --- | --- |
| [`purpose.md`](purpose.md) | Why the project exists, what it adds, where it deviates from upstream, what it costs, what "done" means for v0.1. |
| [`architecture.md`](architecture.md) | The boot-to-demo flow, topology, component boundaries, manifest trust chain, safety model. |
| [`roadmap.md`](roadmap.md) | The vertical slices 0–7 with their state and what each verified. |
| [`STATUS.md`](STATUS.md) | Session handoff: now / next / recently done. Printed by `bash scripts/status.sh`. |

## Working on it

| Document | What it answers |
| --- | --- |
| [`development.md`](development.md) | Day-to-day commands: local checks without Nix, Nix checks and builds, `appliance-vm`, manifest checksum, make targets. |
| [`testing.md`](testing.md) | Which check covers which requirement; how to read a failure; the "a bug becomes a check first" rule. |
| [`nix-setup.md`](nix-setup.md) | Runbook for installing Nix in WSL2 and making KVM usable inside the Nix sandbox. |
| [`verification-latest.md`](verification-latest.md) | **Generated** by `REPORT=1 bash scripts/verify.sh`: result and timings of the latest real run. |
| `verification-history.csv` | **Generated**: every recorded check duration, feeds the mean/range columns above. |
| [`screenshots/README.md`](screenshots/README.md) | Rules for the screenshots in the README; [`screenshots/PROVENANCE.md`](screenshots/PROVENANCE.md) is **generated** by `scripts/screenshots.sh`. |

## Decisions and unknowns

| Document | What it answers |
| --- | --- |
| [`adr/0001-project-scope.md`](adr/0001-project-scope.md) | Scope and boundaries of v0.1; consume-not-fork; pin everything; non-destructive by default. |
| [`adr/0002-own-installer-iso.md`](adr/0002-own-installer-iso.md) | Why we keep our own installer next to upstream's headless fleet installer. |
| [`adr/0003-workplace-parity.md`](adr/0003-workplace-parity.md) | The host is the DAWO pilot workplace, unchanged, plus additions; the list of deviations. |
| [`adr/0004-local-dns-and-tls.md`](adr/0004-local-dns-and-tls.md) | **Proposed:** local DNS + TLS for the demo (`mb.appliance.internal`, per-install appliance CA, cert-manager CA issuer, browser trust). Resolves OQ-3 once accepted. |
| [`open-questions.md`](open-questions.md) | OQ-1 to OQ-9: blocking and non-blocking unknowns, with resolutions. |

## Upstream

| Document | What it answers |
| --- | --- |
| [`upstream/revisions.md`](upstream/revisions.md) | The exact DAWO-Core and mijn-bureau-infra revisions inspected and pinned, and the facts that shape our design. |
| [`upstream/ecosystem.md`](upstream/ecosystem.md) | Which DAWO / Mijn Bureau repositories exist and which ones we consume. |
| [`upstream/pins-vm-k3s.md`](upstream/pins-vm-k3s.md) | Researched pins with checksums for the Ubuntu 24.04 cloud image and K3s (OQ-6), ready for the manifest once approved. |

## Elsewhere in the repository

- [`../CLAUDE.md`](../CLAUDE.md): hard rules and working method for AI assistants and humans.
- [`../hosts/appliance/README.md`](../hosts/appliance/README.md): the installed host's modules.
- [`../hosts/profiles/disko/README.md`](../hosts/profiles/disko/README.md): the storage layout and the no-LUKS decision.
- `../vm/`, `../k8s/`, `../apps/`, `../health/`: one README each, scaffolding for slices 4–7.
- [`../manifest/appliance-manifest.json`](../manifest/appliance-manifest.json): every pin, protected by its `.sha256`.
