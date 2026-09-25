# ADR 0001: Project scope and boundaries for v0.1

- Status: Accepted (context facts updated by ADR 0002 and ADR 0003 on
  2026-09-25: upstream is now DAWO-Core on Codeberg, release 0.1.3, and ships
  a headless fleet installer; the decisions below stand)
- Date: 2026-06-22
- Deciders: maintainer (eywitteveen)

## Context

We are starting `dawo-appliance`, an independent experiment to produce a
bootable installer ISO that demonstrates a digitally autonomous government
workplace: a NixOS host with a DAWO-based desktop running an Ubuntu 24.04 VM
with single-node K3s and a Mijn Bureau deployment, opened automatically in the
browser.

Two official upstream projects are involved and were inspected at fixed
revisions (`docs/upstream/revisions.md`):

- DAWO-NixOS `daed6f8…` — GPL-3.0, flake exposing reusable modules as
  `flake.modules.nixos.*`, KDE Plasma desktop, disko hard-coded to
  `/dev/nvme0n1`, no ISO output.
- mijn-bureau-infra `ef1d796…` — EUPL-1.2, Helmfile-based, documented
  single-node K3s path, needs >= 12 vCPU / >= 48 GiB RAM.

## Decision

1. **Scope v0.1 narrowly.** Support only: x86-64; online install; one physical
   machine; one Ubuntu 24.04 VM; single-node K3s; Mijn Bureau; automatic start;
   a local health check; automatic browser open.

2. **Explicitly exclude** (do not build, even speculatively): openDesk,
   Nextcloud AIO, multiple Kubernetes nodes, HA, org-specific branding, Active
   Directory integration, and offline installation.

3. **Consume, do not fork.** DAWO-NixOS is a pinned flake input; Mijn Bureau is
   driven through its documented Helmfile / single-VPS install path at a pinned
   revision. No copying of upstream source unless strictly necessary and
   license-permitted. No fork or submodule without a written justification.

4. **Pin everything; build reproducibly.** Exact revisions, Nix inputs, K3s
   version, chart versions, and image digests live in version-controlled files
   (`manifest/`, `flake.lock`). No `main`/`latest`/floating tags.

5. **Non-destructive by default.** The bootstrap defaults to a dry-run `plan`.
   Any disk write requires an explicit `--target-disk` and `--confirm-destroy`.
   Build destructive steps late and behind these gates.

6. **Secrets at install time only.** Never commit secrets; generate the Mijn
   Bureau master password and derived secrets on the host during install.

7. **Extensible structure, not extra features.** Reserve `apps/profiles/` for
   future application profiles but ship only `mijn-bureau` in v0.1.

8. **Defer cross-cutting decisions** that are not needed to start: license
   choice (OQ-4), local DNS/TLS (OQ-3), digest pinning (OQ-5), signatures
   (OQ-7). Tracked in `docs/open-questions.md`.

## Consequences

- Early work is a vertical slice that proves the boot → download → verify → plan
  path without writing to disk; heavy/destructive layers come later.
- The appliance needs a large target host (OQ-2); the dev laptop can build and
  dry-run but not run the full stack.
- We must provide our own ISO target and our own explicit-target disko module,
  since upstream provides neither.
- Choosing a license is required before any publication (OQ-4) and is left to
  the maintainer.

## Alternatives considered

- **Forking DAWO-NixOS / mijn-bureau-infra.** Rejected for v0.1: increases
  maintenance burden, risks license entanglement, and is unnecessary because
  both expose consumable interfaces (flake modules; documented install path).
- **One big-bang installer.** Rejected: hard to test and unsafe. Vertical slices
  with a non-destructive default are safer and demoable earlier.
